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

### Point the network at it

Until the router hands out AdGuard as the DNS server, nothing above has any effect on other devices.

In the router administration pages, open the LAN or DHCP server section and find the DNS server fields that the DHCP
server advertises. Set the first one to `<docker-vm-ip>` and leave the second one empty. Apply, then reconnect a
device or renew its lease so it picks up the change.

Leave the WAN or upstream DNS setting on automatic. That one is what the router uses for itself, and keeping it
independent means the router still resolves names when the VM is down.

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
`dashboard.internal` or any other private name, which is the thing the reverse proxy depends on.

---

### Next

Add the proxy entries in [nginx_proxy_manager.md](nginx_proxy_manager.md).
