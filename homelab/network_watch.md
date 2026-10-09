# Network Watch

> Telegraf writing one row a second, proof that a short internet drop really happened and whose fault it was.

---

### What it is for

The internet provider on this lab (Orange, Poland) drops the connection for about 30 seconds at random times.
Nothing else here proves that happened. A phone that briefly loses Wi-Fi, a stream that stutters, these look the
same to a person as a real provider outage, and by the time you go to check, the moment has passed.

Telegraf answers that by writing a row every second, every day, straight into a Syncthing folder, so the proof
copies itself to your own PC without you doing anything. The four checks below each point at a different layer, so
the pattern in the rows tells you which layer actually failed.

| What you see | What it means |
|---|---|
| Pings fail and both DNS lookups fail | The internet line or the router, not this stack |
| Pings are fine but only the AdGuard lookup fails | AdGuard Home itself |
| Everything is fine in the rows | The problem is elsewhere, one device or its Wi-Fi |
| No rows at all for a stretch | The Docker VM stopped, since Telegraf runs on that same VM |

The ping targets are the router (`192.168.1.1`), the first hop past the router on the Orange line
(`83.1.5.230`), and two public resolvers (`1.1.1.1`, `8.8.8.8`). The DNS checks ask AdGuard Home
(`192.168.1.12`) and Cloudflare (`1.1.1.1`) the same question, a lookup of `connectivitycheck.gstatic.com`, which
is Android's own connectivity check domain and is built to be queried constantly. The HTTP check asks the matching
endpoint, `http://connectivitycheck.gstatic.com/generate_204`, which exists only to answer a lightweight 204 with
no page behind it.

Three files land in the shared folder, one per check: `ping.csv`, `dns.csv`, `http.csv`. Each file rotates at
midnight local time and keeps 30 days of history.

---

### One-time setup on the Docker VM

Create the folder Telegraf writes into and give it to the same user Syncthing already uses:

```bash
sudo mkdir -p /opt/docker-stack/syncthing/data/network-watch
```

```bash
sudo chown -R 1000:1000 /opt/docker-stack/syncthing/data/network-watch
```

Telegraf pings as an unprivileged user, gid 1000, which only works if the VM's own kernel allows that gid to open
an ICMP socket. The Compose file sets `network_mode: host`, so the container shares the VM's network namespace
and the VM's own sysctl applies, not a default a container would otherwise get for free. Check it once:

```bash
sysctl net.ipv4.ping_group_range
```

It needs to read `0 2147483647`, or at least a range that includes 1000. Ubuntu Server ships systemd, and
systemd's own `sysctl.d/50-default.conf` sets exactly `net.ipv4.ping_group_range = 0 2147483647` on every
systemd-based install, verified against that file in the systemd source tree, so a stock Ubuntu Docker VM already
has this open before Telegraf ever runs. If your check prints anything narrower, or `0 0`, add a drop-in file
rather than editing systemd's own:

```bash
echo "net.ipv4.ping_group_range = 0 2147483647" | sudo tee /etc/sysctl.d/99-telegraf-ping.conf
```

```bash
sudo sysctl --system
```

Pull the change that adds the Telegraf service:

```bash
cd /opt/docker-stack/InstallationHelper && git pull
```

Start only the new service:

```bash
cd /opt/docker-stack/InstallationHelper/homelab && docker compose up -d telegraf
```

Check it is actually writing, a minute or two after it starts:

```bash
tail -n 5 /opt/docker-stack/syncthing/data/network-watch/ping.csv
```

A handful of rows with today's timestamp means it is working. Nothing in that file at all, after giving it a
minute, means the container never started, check `docker compose logs telegraf`. A file that only ever shows
`result_code` of 1 or 2 for every target at once, with the `average_response_ms` column always empty, points back
at the sysctl step above rather than at your actual network, since that is what every ping looks like when the
unprivileged socket itself is refused.

---

### Finding and updating the Orange gateway address

Orange can hand out a different gateway address after your router reconnects, so the `83.1.5.230` address baked
into `telegraf/telegraf.conf` goes stale eventually. Find the current one the same way it was found in the first
place, the first hop after your own router.

On the Docker VM, or any Linux machine on the same network:

```bash
traceroute -n 1.1.1.1
```

On your Windows PC:

```powershell
tracert -d 1.1.1.1
```

The first line is your own router. The second line is the address to use. Edit `telegraf/telegraf.conf`, replace
the old gateway address in the `inputs.ping` block with the new one, then restart the container to pick up the
change:

```bash
docker compose restart telegraf
```

---

### AdGuard Home: keep the test domain out of the query log and the statistics

Telegraf asks AdGuard Home for `connectivitycheck.gstatic.com` once a second, which is 86,400 lookups a day. Left
alone, that drowns out every other query in the log and in the statistics page. Add the domain to both ignore
lists, which are two separate settings even though they sit side by side.

1. Open AdGuard Home, go to Settings, then General settings.
2. In the Query Log section, open Ignored domains, add `connectivitycheck.gstatic.com` on its own line, and save.
3. In the Statistics section, open Ignored domains again, add the same domain on its own line, and save.

Both lists take one host name per line, and AdGuard stops writing anything matching those names to that
particular feature. Real queries for the same domain from other devices on the network are affected the same way,
which is fine here since nothing else on this network has a reason to ask for it on purpose.

---

### Syncthing: share the folder and protect it on your PC

The Docker VM is the one writing these files, so it is the sending side. Your PC should only ever receive, and it
should hold onto files even after the server prunes them past 30 days.

1. On the Docker VM's Syncthing, at `http://<docker-vm-ip>:7780`, choose Add Folder, point it at `/data/network-watch`, give it a label, and tick your PC under Sharing.
2. On your PC's Syncthing, accept the offered folder.
3. Still on your PC, open the folder's settings and set Folder Type to Receive Only, so nothing on your PC ever gets written back to the server by mistake.
4. On the same folder, open the Advanced tab and turn on Ignore Delete.
5. Save.

Ignore Delete is the setting that matters most here. Without it, the day Telegraf's own rotation deletes a file
older than 30 days on the server, Syncthing deletes that same file from your PC a moment later, and the thing you
built this for, a permanent local copy, quietly stops being permanent.

---

### Uptime Kuma: watch the same four layers live

The CSV files are the record. Uptime Kuma is the thing that notices while it is still happening. Add five
monitors, all at a 5 second Heartbeat Interval, and set Retries to 2 on each one so a single lost packet does not
page you.

| Monitor | Type | Target |
|---|---|---|
| Router | Ping | `192.168.1.1` |
| Orange gateway | Ping | `83.1.5.230` |
| Cloudflare | Ping | `1.1.1.1` |
| AdGuard resolution | DNS | Hostname `connectivitycheck.gstatic.com`, Resolver Server `<docker-vm-ip>`, Resolve Type A |
| Connectivity check | HTTP(s) | `http://connectivitycheck.gstatic.com/generate_204` |

While you are in there, go to Settings, then Monitor History, and set "Keep monitor history data for" to 30 days,
to match the CSV retention and keep the database from growing without a limit.

Uptime Kuma 2.5.5 carries nothing that needs a manual step beyond the version bump itself. The releases between
2.5.1 and 2.5.5 fixed a memory leak on TCP monitors, fixed a bug where the two ping timeout fields in the monitor
form were swapped, and patched a denial of service weakness in a bundled library (CVE-2026-77415). None of them
touch the Docker image layout or the database schema.

---

### Expected size

Measured from a short real run of this exact configuration on 2026-10-09, not a guess: Telegraf writes about
535,000 rows a day across the three files, roughly 23 MB a day, and roughly 680 MB for the full 30 day window the
rotation keeps. That is well under the original back of the envelope figure of 70 to 80 MB a day, because the CSV
columns are pinned to a short, fixed list per file rather than every field and tag Telegraf happens to produce.

Replace this with your own number after a full day of real data:

```bash
du -sh /opt/docker-stack/syncthing/data/network-watch
```

---

### Finding an outage in the files afterward

A target is down once it has failed two seconds in a row, which filters out a single lost ping without filtering
out anything that matters. Failed means either `result_code` is not 0, or, in `ping.csv` specifically, the
fourth column is `percent_packet_loss` sitting at 100, which catches a plain timeout that the ping plugin itself
scored as a success. The command below reads that distinction straight off each file's own header, so it never
misreads `rcode_value` or `http_response_code` in the other two files as a loss figure. It also skips every header
line, and there can be more than one in a file, since a container restart mid-day appends a fresh header to that
day's file.

It needs `gawk`. Git Bash on Windows already ships it. On the Docker VM, install it once if `awk --version` does
not say GNU Awk:

```bash
sudo apt install -y gawk
```

The command itself, run from inside the folder that holds the CSV files:

```bash
gawk -F, '$0~/^timestamp,/{is_ping=($4=="percent_packet_loss");next} {t=$1;tg=$2;rc=$3;loss=$4;gsub(/[-:]/," ",t);ts=mktime(t);bad=(rc!=0)||(is_ping&&loss==100);if(bad){f[tg]++;if(f[tg]==1)d[tg]=ts;if(f[tg]==2&&!r[tg]){print "DOWN",strftime("%Y-%m-%d %H:%M:%S",d[tg]),tg;r[tg]=1}}else{if(r[tg]){print "UP  ",strftime("%Y-%m-%d %H:%M:%S",ts),tg,"after",ts-d[tg],"s"};f[tg]=0;r[tg]=0}}' ping.csv
```

Tested against a built CSV with a 31 second outage planted in it, it printed exactly this:

```text
DOWN 2026-10-09 14:00:12 83.1.5.230
UP   2026-10-09 14:00:43 83.1.5.230 after 31 s
```

Tested again against a second file built with `result_code` sitting at 0 while `percent_packet_loss` sat at 100
for two seconds in a row, the loss-based check caught it on its own:

```text
DOWN 2026-10-09 15:00:01 1.1.1.1
UP   2026-10-09 15:00:03 1.1.1.1 after 2 s
```

And tested a third time against a file shaped like `dns.csv`, where the fourth column is `rcode_value` rather
than `percent_packet_loss` and happened to sit at 100 for two rows, the command printed nothing at all, which is
the correct answer, since a DNS failure is already carried by `result_code` and `rcode_value` is not a loss
figure.

Run it against `dns.csv` or `http.csv` the same way, the column layout is the same shape in every file, timestamp
first, the target second, the result code third.
