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

Everything that is not internal and not blocked goes upstream. Pick a resolver that supports DNS over HTTPS or DNS
over TLS so your queries are not readable on the way out, and set it under Settings, then DNS settings.

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
