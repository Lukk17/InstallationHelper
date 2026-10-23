# Network Watch

> Telegraf writing a ping and DNS row every second, and an HTTP row every 5 seconds, proof that a short internet
> drop really happened and whose fault it was.

---

### What it is for

The internet provider on this lab (Orange, Poland) drops the connection for about 30 seconds at random times.
Nothing else here proves that happened. A phone that briefly loses Wi-Fi, a stream that stutters, these look the
same to a person as a real provider outage, and by the time you go to check, the moment has passed.

Telegraf answers that by writing a ping and DNS row every second, and an HTTP row every 5 seconds, every day,
straight into a Syncthing folder, so the proof copies itself to your own PC without you doing anything. The four
checks below each point at a different layer, so the pattern in the rows tells you which layer actually failed.

| What you see | What it means |
|---|---|
| Pings fail and both DNS lookups fail | The internet line or the router, not this stack |
| Pings are fine but only the AdGuard lookup fails | AdGuard Home itself |
| Everything is fine in the rows | The problem is elsewhere, one device or its Wi-Fi |
| No rows at all for a stretch | The Docker VM stopped, since Telegraf runs on that same VM |

The ping targets are the router (`192.168.1.1`), one of Orange's own DNS resolvers (`194.204.159.1`), and two
public resolvers (`1.1.1.1`, `8.8.8.8`). The DNS checks ask AdGuard Home (`192.168.1.12`) and Cloudflare
(`1.1.1.1`) the same question, a lookup of `connectivitycheck.gstatic.com`, which is Android's own connectivity
check domain and is built to be queried constantly. The HTTP check asks the matching endpoint,
`http://connectivitycheck.gstatic.com/generate_204`, which exists only to answer a lightweight 204 with no page
behind it.

Four files land in the shared folder, one per check: `ping.csv`, `dns.csv`, `http.csv`, `speed.csv`. Each file
rotates at midnight local time and keeps 30 days of history.

---

### One-time setup on the Docker VM

This homelab runs Compose from a plain copy of `compose.yaml` at `/opt/docker-stack`, with no repository clone
on the VM at all. The quick start in [README_HOMELAB.md](README_HOMELAB.md) already creates the folder Telegraf
writes into, as the login user who owns `/opt/docker-stack`. The commands below are here in case you skipped
that step, or need to recreate the folder, so give it to the same user Syncthing already uses:

```bash
mkdir -p /opt/docker-stack/syncthing/data/network-watch
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

`compose.yaml` mounts `./telegraf/telegraf.conf`, relative to the folder holding `compose.yaml` itself, so that
file has to exist at `/opt/docker-stack/telegraf/telegraf.conf` before the first start. The quick start already
creates this folder too, but if you skipped it:

```bash
mkdir -p /opt/docker-stack/telegraf
```

Then put the config in it, either by downloading it directly:

```bash
curl -fsSL https://raw.githubusercontent.com/Lukk17/InstallationHelper/master/homelab/telegraf/telegraf.conf -o /opt/docker-stack/telegraf/telegraf.conf
```

or by uploading `homelab/telegraf/telegraf.conf` to that path with FileZilla or `scp`.

A missing bind mount source behaves differently depending on whether Docker expects a file or a folder there.
The config file is mounted into a single file inside the container, and a missing source there fails the start
itself, with `error mounting "/opt/docker-stack/telegraf/telegraf.conf" to rootfs at
"/etc/telegraf/telegraf.conf": ... not a directory: Are you trying to mount a directory onto a file (or
vice-versa)? Check if the specified host path exists and is the expected type`, because Docker creates a
directory in the missing file's place and the container then finds a directory where it needs a file. The fix is
to remove the directory Docker created, give the real folder back to the login user, and put the config there
before starting again:

```bash
sudo rmdir /opt/docker-stack/telegraf/telegraf.conf
```

```bash
sudo chown <your-user>:<your-user> /opt/docker-stack/telegraf
```

The output folder is mounted into a folder, not a file, and a missing source there does not fail the start at
all. Docker creates the folder and the container starts, but the folder it created belongs to root, which
Telegraf's own user, gid 1000, then cannot write into. Fixed the same way:

```bash
sudo chown -R 1000:1000 /opt/docker-stack/syncthing/data/network-watch
```

```bash
docker restart telegraf
```

With the output folder and the config both in place, start the stack:

```bash
cd /opt/docker-stack && docker compose up -d
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

### Why the probe uses Orange's own DNS, not the gateway

`194.204.159.1` is one of Orange's own DNS resolvers, a fixed address inside Orange's network, used here as the
Orange-side ping target instead of the first hop past the router. That first hop is Orange's gateway, and Orange
hands out a new address for it every time its own box reconnects, so a ping fixed to that address shows down
forever after a restart, not because the internet is down but because the address under it changed.

Measured 2026-10-09 from the home network, `194.204.159.1` and a second Orange resolver, `194.204.152.34`, both
answered 4 of 4 pings, about 4.5 ms and 4.8 ms, and both resolved `google.com`. The route to `194.204.159.1` goes
through the Asus router (`192.168.1.1`), then the Orange gateway, then into Orange's own network beyond it, which
is the trade-off: a failure here sits a few steps past the gateway and cannot tell the Orange box itself apart
from the rest of Orange's network, since both sit on Orange's side of the line regardless. What it buys back is
a target that does not move.

`traceroute` and `tracert` are still useful for seeing that path, they are just no longer something to edit back
into `telegraf/telegraf.conf` after every restart.

On the Docker VM, or any Linux machine on the same network:

```bash
traceroute -n 1.1.1.1
```

On your Windows PC:

```powershell
tracert -d 1.1.1.1
```

The first line is your own router, the second is the Orange gateway, and everything after it is further into
Orange's network than `194.204.159.1` typically needs to go to answer a ping.

---

### AdGuard Home: keep the test domain out of the query log and the statistics

Telegraf asks AdGuard Home for `connectivitycheck.gstatic.com` once a second, which is 86,400 lookups a day. Left
alone that would drown out every other query in the log and in the statistics page. The steps live in one place,
in [adguard_dns.md](adguard_dns.md#keep-the-network-watch-domain-out-of-the-query-log-and-statistics), under "Keep
the network watch domain out of the query log and statistics", so follow them there rather than here.

---

### Syncthing: share the folder and protect it on your PC

The Docker VM is the one writing these files, so it is the sending side. Your PC should only ever receive, and it
should hold onto files even after the server prunes them past 30 days.

1. On the Docker VM's Syncthing, at `http://<docker-vm-ip>:7780`, choose Add Folder, set Folder Path to `/data/network-watch` (the container sees `/opt/docker-stack/syncthing/data` as `/data`), give it a label, and tick your PC under Sharing.
2. Still on the Docker VM's Syncthing, open the folder's Advanced tab and set Folder Type to Send Only, so nothing on that side ever gets written back into these files from the other end.
3. On your PC's Syncthing, accept the offered folder.
4. Still on your PC, open the folder's settings, set Folder Type to Receive Only on its Advanced tab, so nothing on your PC ever gets written back to the server by mistake, and Save.
5. Still on your PC, open Actions, then Advanced, expand Folders, expand this folder by its label, and tick Ignore Delete. It is not on the folder's own Advanced tab, only in this Actions, Advanced dialog.
6. Save.

Ignore Delete is the setting that matters most here. Without it, the day Telegraf's own rotation deletes a file
older than 30 days on the server, Syncthing deletes that same file from your PC a moment later, and the thing you
built this for, a permanent local copy, quietly stops being permanent.

---

### Uptime Kuma: watch the same layers live

The CSV files are the record. Uptime Kuma is the thing that notices while it is still happening. The six
monitors, their fields, and the click steps to add them from scratch live in
[uptime_kuma.md](uptime_kuma.md#network-monitors), under "Network monitors", so set them up there.

Read the six together rather than one at a time. Asus Router green while Orange DNS, Internet 1.1.1.1, DNS
direct 1.1.1.1 and Internet web check are all red at once points at the Orange line itself. Only AdGuard Home
DNS red, with everything else green, points at AdGuard Home rather than the line. There is no monitor for the
Orange gateway itself, for the same reason the ping target above is Orange's own DNS rather than the gateway:
the gateway's own address changes on every reconnect, so a fixed monitor against it would eventually monitor
the wrong thing.

---

### Expected size

Measured from a short real run of this exact configuration on 2026-10-09, not a guess: Telegraf writes about
535,000 rows a day across the three files, roughly 23 MB a day, and roughly 680 MB for the full 30 day window the
rotation keeps. That is well under the original back of the envelope figure of 70 to 80 MB a day, because the CSV
columns are pinned to a short, fixed list per file rather than every field and tag Telegraf happens to produce.

`speed.csv` does not change any of that. One row every 10 minutes is 144 rows a day, well under a tenth of a
percent of the 535,000 rows the other three files already write between them, so it adds no meaningful disk
weight even though the test behind each of its rows moves real data over the line, covered below.

Replace this with your own number after a full day of real data:

```bash
du -sh /opt/docker-stack/syncthing/data/network-watch
```

---

### Speed test: download, upload and latency every 10 minutes

Telegraf's `internet_speed` plugin runs a real speedtest.net test and writes the download speed, the upload
speed, the latency and the jitter into `speed.csv`, with `result_code` style pass or fail logic replaced by a
`packet_loss` field, which the plugin sets to -1 when it has nothing to report. It is configured for `10m`, one
test every 10 minutes, which is meant as a diagnostic burst of a few weeks rather than a permanent setting. Once
enough runs have landed next to a real Orange drop, drop the interval to 30 minutes, or turn the test off
entirely, the same way described further down.

To change the interval, edit the one line on the Docker VM and restart the container:

```bash
nano /opt/docker-stack/telegraf/telegraf.conf
```

```bash
docker restart telegraf
```

The line to change sits under `[[inputs.internet_speed]]` and reads `interval = "10m"`.

Each test fills the line it is measuring for the time the test itself runs, not the whole 10 minute gap between
tests. An earlier measurement here read 10 minutes 26 seconds and 8 minutes 50 seconds for one test, which was
wrong: that measured Telegraf waiting for its own first 10 minute collection window, not the test, and overstated
the real figure by more than an order of magnitude. Measured directly with `telegraf --test --input-filter
internet_speed` against the real telegraf:1.40.1 image on this development machine's connection on 2026-10-09,
which runs the test immediately instead of waiting for the interval: one test including the container's own
startup took 47 seconds with `memory_saving_mode` on and 46 seconds with it off, so the test itself fills the
line for roughly 40 seconds once startup is set aside. `memory_saving_mode` is left at its default, off, in this
configuration, because the plugin's own README names a fast connection, above 30 Mb/s, as exactly the case where
turning it on trades real accuracy away, and this line is well above that. Measured back to back on 2026-10-09
with `--test`: `memory_saving_mode` on read download and upload around 120 and 90 Mbps, off read around 200 Mbps
on both, against different test servers each run, so the comparison is not exact, but it points the same
direction as the README's own warning. Telegraf also rounds a plugin's own collection times to the clock by
default, so a 10 minute interval starts at :00, :10, :20, :30, :40 and :50 past the hour. A ping, DNS or HTTP
failure landing within about a minute after one of those marks may be this test saturating the connection, not
Orange. Check `speed.csv` for a row close to that timestamp before counting a failure there as a real outage.

Data volume is the other cost of running this often. Measured directly with that same `--test` run,
`memory_saving_mode` off, reading the container's own `/proc/net/dev` on an isolated bridge network right after
the test completed: eth0 received 282,184,059 bytes and sent 402,764,399 bytes, about 685 MB total, at roughly
200 Mbps on this development machine's own connection. That number was measured here, not on the homelab's own
Orange line. The real line runs at 300 to 600 Mbps and the test runs for a fixed amount of time rather than a
fixed amount of data, so the real homelab figure will be higher. At one test every 10 minutes, 144 tests a day,
that puts the estimate at roughly 100 GB a day or more, which the owner's unlimited Orange plan can absorb but is
still worth knowing before leaving the short interval running for longer than the diagnosis needs. Replace the
estimate with a real measurement taken on the homelab VM itself once it has run there for a day, the same way the
Expected size section above replaces its own estimate with a real `du -sh` figure.

Compare the `download` and `upload` fields against the contract speed, for example 300 megabit, and check the
actual Orange contract for the confirmed number rather than relying on this note.

Stopping Telegraf entirely, for example while confirming the speed test is the reason a check tripped, is a
Compose action on the Docker VM rather than an edit to `telegraf.conf`:

```bash
cd /opt/docker-stack && docker compose stop telegraf
```

Starting it again:

```bash
cd /opt/docker-stack && docker compose start telegraf
```

To turn off only the speed test and keep the ping, DNS and HTTP checks running, remove the
`[[inputs.internet_speed]]` block and its matching `[[outputs.file]]` block writing `speed.csv` from
`telegraf.conf`, then restart the container the same way:

```bash
docker restart telegraf
```

---

### Finding an outage in the files afterward

A target is down once it has failed two rows in a row, which filters out a single lost ping without filtering
out anything that matters. In `ping.csv` and `dns.csv`, which both get a row every second, that is two seconds.
In `http.csv`, which gets a row every 5 seconds, the same two rows in a row is ten seconds. Failed means either
`result_code` is not 0, or, in `ping.csv` specifically, the fourth column is `percent_packet_loss` sitting at
100, which catches a plain timeout that the ping plugin itself scored as a success. The command below tells a ping
file from the others by its file name, `ping.csv` or a rotated `ping.<date>.csv`, so it never misreads
`rcode_value` or `http_response_code` in the other two files as a loss figure. It cannot use the header row for
this, because Telegraf writes a header only when it creates a file, not after the midnight rotation: measured on
2026-10-23, that day's `ping.csv` held no header line at all while a rotated `ping.2026-10-11-*.csv` held three.
It also skips every header line it does find, and there can be more than one in a file, since a container restart
mid-day appends a fresh header to that day's file.

It needs `gawk`. Git Bash on Windows already ships it. On the Docker VM, install it once if `awk --version` does
not say GNU Awk:

```bash
sudo apt install -y gawk
```

The command itself, run from inside the folder that holds the CSV files:

```bash
gawk -F, 'FNR==1{is_ping=(FILENAME~/(^|\/)ping[^\/]*$/)} $0~/^timestamp,/{next} {t=$1;tg=$2;rc=$3;loss=$4;gsub(/[-:]/," ",t);ts=mktime(t);bad=(rc!=0)||(is_ping&&loss==100);if(bad){f[tg]++;if(f[tg]==1)d[tg]=ts;if(f[tg]==2&&!r[tg]){print "DOWN",strftime("%Y-%m-%d %H:%M:%S",d[tg]),tg;r[tg]=1}}else{if(r[tg]){print "UP  ",strftime("%Y-%m-%d %H:%M:%S",ts),tg,"after",ts-d[tg],"s"};f[tg]=0;r[tg]=0}}' ping.csv
```

Tested against a built CSV with a 31 second outage planted in it, it printed exactly this:

```text
DOWN 2026-10-09 14:00:12 194.204.159.1
UP   2026-10-09 14:00:43 194.204.159.1 after 31 s
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

Tested a fourth time against a `ping.csv` with no header row at all, the shape of every file after a midnight
rotation, with two seconds of 100 percent loss at `result_code` 0, it printed one `DOWN` line and one `UP` line
two seconds apart, the same shape as the second test. The older version of this command, which looked for
`percent_packet_loss` in the header, printed nothing for that file.

Run it against `dns.csv` or `http.csv` the same way, the column layout is the same shape in every file, timestamp
first, the target second, the result code third.
