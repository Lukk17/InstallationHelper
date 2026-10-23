# AdGuard Home and Network DNS

> First run of AdGuard Home, the wildcard rewrite that makes `.internal` names resolve, and pointing the whole
> network at it.

---

### Why two ports

The Compose file publishes AdGuard twice on purpose.

Port 7776 maps to container port 3000, which is where the first run wizard lives. You use it once.

Port 7777 maps to container port 7777, which is where the interface lives after the wizard, because the wizard asks
you to choose the web interface port and 7777 is the answer that keeps port 80 free for the reverse proxy.

---

### First run

Open `http://<docker-vm-ip>:7776` and work through the wizard.

When it asks about the admin web interface, change the port from 80 to 7777. Leave the DNS port on 53. Port 80
belongs to Nginx Proxy Manager, and a collision there breaks every proxied name at once.

Finish the wizard, then use `http://<docker-vm-ip>:7777` from now on.

---

### Make internal names resolve

Every `.internal` name has to land on the reverse proxy, which then decides which container answers. One wildcard
entry does that for all of them.

Go to Filters, then DNS Rewrites, and add a rewrite mapping `*.internal` to `<docker-vm-ip>`.

That is the whole trick. AdGuard hands the VM address back for any internal name, the browser connects to Nginx
Proxy Manager there, and the proxy routes on the Host header. Adding a new service later needs a proxy host entry
only, never another DNS entry.

---

### Upstream resolvers

Everything that is not internal and not blocked goes upstream. Set all of this under Settings, then DNS settings.

Upstream DNS servers, three providers instead of one, one per line:

```text
https://dns10.quad9.net/dns-query
https://unfiltered.adguard-dns.com/dns-query
https://cloudflare-dns.com/dns-query
```

Google (`https://dns.google/dns-query`) is removed here for privacy, because Google keeps query logs, and AdGuard
DNS's own non-filtering address takes its place instead. None of the three filters anything on its own, AdGuard
DNS's unfiltered address included. AdGuard Home's own blocklists do the blocking, further down this page, so an
upstream that also filtered would only hide a failure behind a second, invisible blocklist. The reason for three
providers instead of one is plain reliability: with a single upstream, any moment that one provider is unreachable
fails every lookup that is not already cached. Measured on 2026-10-09 from the home network: a lookup through
`https://unfiltered.adguard-dns.com/dns-query` answered (HTTP 200 for a raw DNS query), and `doubleclick.net`
resolved through it, proving it does not filter.

Set the upstream mode to Parallel requests, not Load-balancing. Parallel requests asks all three upstreams at once,
so a dead provider costs no wait at all, since one of the other two answers first, and under this mode the order of
the three lines above makes no difference. Load-balancing instead picks one
upstream per query by weighted random choice and falls through to the next on failure, marking the failed one as
slow so it gets picked less often, so a dead provider there costs a wait of up to the upstream timeout rather than
a failed lookup. With only one upstream, the single-provider case above, there is nothing to fall through to, so a
failure there does fail the lookup.

Fallback DNS servers, used only once every upstream above has failed:

```text
9.9.9.10
1.1.1.1
```

Both are plain, unencrypted DNS, Quad9 and Cloudflare, with no filtering of their own. They are the last resort
after the encrypted upstreams have all failed, not a second tier of upstreams, so they only ever answer during an
actual outage.

Bootstrap DNS servers, left on the Quad9 defaults:

```text
9.9.9.10
149.112.112.10
2620:fe::10
2620:fe::fe:10
```

Bootstrap servers only resolve the hostnames in the Upstream DNS servers list above, such as `dns10.quad9.net`.
They never see or answer a query this network actually makes, so there is nothing to change here.

Set Upstream timeout to 3 seconds instead of the default 10. A dead upstream now gives up before the device asking
the question would have given up on its own, instead of the other way around.

Under DNS cache configuration, turn on Optimistic caching, which the interface describes as responding from the
cache even when the entries are expired. With it on, an expired cache entry still answers immediately, within the
cache_optimistic_max_age limit, while AdGuard refreshes it in the background, rather than making the client wait
on the upstreams. The same behaviour also covers a short outage: a name already in the cache keeps answering even
in the moment every upstream above has failed at once.

None of this touches ad blocking. Blocking happens in AdGuard Home's own blocklists, further down this page,
before any upstream is ever asked, so moving to three non-filtering upstreams changes nothing about what gets
blocked. Measured on 2026-10-09 against `<docker-vm-ip>` after making this change: `doubleclick.net` and
`googleadservices.com` both answered `0.0.0.0`, and `google.com` answered its real addresses.

---

### Rate limit

In the DNS server configuration block on this same page, set Rate limit to 0, which means no limit. AdGuard
Home's rate limit does not count per device, it groups every address in the same /24 subnet for IPv4, or the same
/56 subnet for IPv6, into one client, so the default limit is a budget shared by every device in the house rather
than a budget each device gets on its own. The AdGuard Home default configuration sets `ratelimit_subnet_len_ipv4`
to 24 and `ratelimit_subnet_len_ipv6` to 56, which is exactly that grouping, and a rate limit above zero is applied
per subnet of that size rather than per address.

Leave Subnet prefix length for IPv4 addresses and Subnet prefix length for IPv6 addresses at their defaults, 24
and 56. Both fields only matter once a rate limit above zero is set, and on a network this size that limit is off.

---

### Blocklists

Under Filters, then DNS blocklists, AdGuard ships a catalogue you can enable with a tick. Two or three well chosen
lists beat a dozen stacked on top of each other, because overlapping lists multiply the false positives without
blocking much extra.

A broad, carefully curated general list is the one that does the work. It covers advertising and telemetry across the
board and is maintained to keep breakage low.

A list for your own country or language is the useful second one. Regional phishing, fake parcel notifications and
fake banking domains never appear on the big international lists, because they are only ever aimed at people who
speak the language.

Under Settings, then General settings, set the filter update interval to twelve hours. Malicious domains are
registered, used and abandoned within a couple of days, so a list refreshed weekly is missing exactly the ones that
matter.

Turn on the browsing security service in the same place. It checks names against a live reputation database rather
than a downloaded list, which catches malware and phishing domains that were registered after your last list update.

---

### Reading the query log

Query log is where you find out what actually happened, and it is the first place to look when someone says the
internet is broken.

Blocked queries are marked in red. Click one to see which list stopped it, which tells you whether to remove a list
or just allow the single name.

Allowing one name is a single click from that panel, and it is almost always the right fix. A shopping site whose
checkout button does nothing usually needs one tracker domain allowed, not a whole list disabled.

Each row shows which device asked, which is why the DHCP configuration below matters. Point the router at AdGuard
correctly and you get per device names. Get it wrong and every query in the log appears to come from the router.

The log itself lives on the Docker VM as JSON lines, one object per line, at
`/opt/docker-stack/adguard/work/data/querylog.json`. That is the AdGuard work directory bind mount from
[compose.yaml](compose.yaml), `/opt/docker-stack/adguard/work` on the host mapped to `/opt/adguardhome/work` inside
the container, with `querylog.json` the file AdGuard Home writes inside that directory's `data` subfolder. AdGuard
rotates that file to `querylog.json.1` once its oldest entry is older than the rotation interval, as the next
section explains, so a search for anything older than the newest entries has to read both. Grep both directly when the web interface itself will not load:

```bash
grep google.com /opt/docker-stack/adguard/work/data/querylog.json /opt/docker-stack/adguard/work/data/querylog.json.1
```

The last few minutes may not be on disk yet either way, since AdGuard keeps the newest entries in memory before
it flushes them to the file.

---

### Keep 30 days of query log

AdGuard Home rotates its query log by age, not by size. Once an hour it reads the time of the oldest entry in
`querylog.json`, and when that entry is older than the rotation interval it renames `querylog.json` to
`querylog.json.1`, replacing the older `querylog.json.1`. So the two files hold between one and two intervals of
queries. The default interval is 90 days, and on 2026-10-23 the two files held 4.0 GB on this lab,
`querylog.json.1` 2.8 GB and `querylog.json` 1.2 GB.

Set both the query log and the statistics to 30 days:

1. Go to Settings, then General settings.
2. On the Logs configuration card, set Query logs rotation to 30 days and press Save. AdGuard asks "Are you sure
   you want to change query log rotation? If you decrease the interval value, some data will be lost". Confirm.
3. On the Statistics configuration card, set Statistics retention to 30 days and press Save. AdGuard's default
   is 24 hours, so 30 days keeps a month of the charts on the dashboard.

AdGuard writes both values into `AdGuardHome.yaml`, which on the Docker VM is
`/opt/docker-stack/adguard/conf/AdGuardHome.yaml`, under the key `interval` of the `querylog` block and of the
`statistics` block. The version this lab runs writes 30 days as `30d`, and it also reads hours, `720h`:

```yaml
querylog:
  interval: 30d
statistics:
  interval: 30d
```

Use the web page rather than editing the file. AdGuard Home rewrites `AdGuardHome.yaml` itself, so a change made
while the container runs can be overwritten, and a change made while it is stopped only takes effect at the next
start.

The shorter interval does not delete anything at once. The old `querylog.json.1` goes at the next rotation, which
comes once the oldest entry in `querylog.json` is more than 30 days old. To free the space today, Clear query logs
on the same Logs configuration card deletes both files and everything AdGuard holds in memory, so the log starts
empty.

Checked on 2026-10-23 in the AdGuard Home source at v0.107.78, the version [compose.yaml](compose.yaml) runs: the
rotation in `internal/querylog/querylogfile.go`, the keys and the 90 day and 1 day defaults in
`internal/home/config.go`, the field names and the 6 hour to 90 day choices in `client/src/__locales/en.json` and
`client/src/helpers/constants.ts`, the clearing of both files in `internal/querylog/qlog.go`, and the `30d` form in
`timeutil/duration.go` of the golibs v0.35.14 library it builds with.

---

### Keep the network watch domain out of the query log and statistics

The Telegraf network watcher described in [network_watch.md](network_watch.md) asks AdGuard Home for
`connectivitycheck.gstatic.com` once a second, 86,400 times a day. The AdGuard Home DNS monitor in
[uptime_kuma.md](uptime_kuma.md#network-monitors) asks the same name every 2 seconds, adding roughly 43,200 more
lookups a day. Left alone, those two together would drown out every other query in both the query log above and
the statistics page.

Go to Settings, then General settings. Add `connectivitycheck.gstatic.com` to Ignored domains on the Logs
configuration card, then add the same domain to Ignored domains again on the Statistics configuration card. They
are two separate fields that happen to sit side by side, so the domain has to go into both. The one ignore rule
covers both sources, Telegraf and the Uptime Kuma monitor alike, since AdGuard matches by domain name regardless
of which client asked.

---

### Point the network at it

Until the router hands out AdGuard as the DNS server, nothing above has any effect on other devices.

Do this in two stages. The first is reversible in seconds and does not take the house down if something is wrong,
the second is the one you leave in place.

While you are still building and testing, set it on the WAN side. In the router administration pages, open the WAN or
internet connection section, find the DNS server fields, and set the first to `<docker-vm-ip>` and the second to a
public resolver. The router then asks AdGuard first and has somewhere to fall back to, so a container restart does
not knock the whole house offline while you are still fiddling with it. The cost is that every query in the log
appears to come from the router, since the router is the only thing asking.

Once it has run for a few days without surprises, move it to the LAN side and drop the fallback. Open the LAN or DHCP
server section, find the DNS server fields that the DHCP server advertises, set the first to `<docker-vm-ip>`, and
leave the second one empty. Undo the WAN setting you made earlier and put it back to automatic. Apply, then reconnect
a device or renew its lease so it picks up the change.

Now every device asks AdGuard directly, which is what makes per device names appear in the query log and what makes
`.internal` names resolve on phones rather than only on the router.

Leave the WAN or upstream DNS setting on automatic afterwards. That one is what the router uses for itself, and
keeping it independent means the router still resolves names when the VM is down.

---

### Why no secondary DNS server

A public resolver in the second slot looks like sensible redundancy and is a trap here. Devices do not treat the
second entry as a failover of last resort, they query whichever resolver answers, so roughly half of your `.internal`
lookups go to a resolver that has never heard of those names and gets an NXDOMAIN back. Internal names then break at
random, which is far harder to diagnose than a clean outage.

The cost of a single entry is real and worth stating: if the AdGuard container is down, the network has no DNS at
all. That failure is loud and obvious, and the fix is to start the container. Give it `restart: unless-stopped`,
which the Compose file already does, and make it the first thing you check when the network goes quiet.

---

### Why not the router's built-in ad blocking

Most routers ship a public filtering DNS option in their security menu. It is not a substitute for this.

It filters against a generic blocklist you cannot edit, and it cannot whitelist a single domain when something
breaks. It treats the whole house as one client, so you never see which device made a query. It answers from
somewhere on the internet rather than from RAM on your own machine. Most importantly it cannot resolve
`dashboard-proxmox.internal` or any other private name, which is the thing the reverse proxy depends on.

---

### Next

Add the proxy entries in [nginx_proxy_manager.md](nginx_proxy_manager.md).
