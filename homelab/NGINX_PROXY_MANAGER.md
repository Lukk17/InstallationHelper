# Nginx Proxy Manager

> Adding the reverse proxy entries so each `.internal` name reaches the right container, and checking that they work.

---

### How the routing works

AdGuard resolves every `.internal` name to the VM address, so all of them arrive at Nginx Proxy Manager on port 80.
The proxy then reads the Host header and forwards the request to the container that owns that name. The entries
below are what teaches it those names.

Forward hostnames are container names, not addresses. Every service in the Compose file joins the `proxy-tier`
network, and Docker resolves container names on it, so `homepage` or `uptime-kuma` is all the proxy needs.

---

### Log in

Open `http://<docker-vm-ip>:81`.

A fresh install signs in with `admin@example.com` and the password `changeme`, then immediately forces you to set a
real email and password. Do that before anything else, since port 81 is reachable from your whole network.

The credentials are stored hashed in `/opt/docker-stack/nginx/data/database.sqlite`. Losing them means resetting
through that database or wiping the directory and starting over.

---

### Add a proxy host

Go to Hosts, then Proxy Hosts, then Add Proxy Host, and fill in the Details tab.

1. Domain Names: type the name and press Enter so it turns into a chip.
2. Scheme: `http`.
3. Forward Hostname / IP: the container name.
4. Forward Port: the port inside the container, not the published host port.
5. Turn on Block Common Exploits and Websockets Support.
6. SSL tab: leave it on None. A `.internal` name cannot get a public certificate, and plain HTTP inside your own
   network is fine here.
7. Save. The entry turns green and reports Online.

---

### The entries

| Domain name | Scheme | Forward hostname | Port | Websockets |
|---|---|---|---|---|
| `dashboard.internal` | http | `homepage` | 3000 | on |
| `uptime.internal` | http | `uptime-kuma` | 3001 | on |
| `syncthing.internal` | http | `syncthing` | 8384 | on |
| `adguard.internal` | http | `adguard-home` | 7777 | on |
| `npm.internal` | http | `nginx-proxy-manager` | 81 | on |

The forward port is the container port from the right hand side of each Compose port mapping. Using the published
host port instead is the usual reason a new entry returns 502.

---

### Proxying the Proxmox interface

The hypervisor is not a container, so it needs an address instead of a name, and it serves HTTPS with a self signed
certificate. Add it as scheme `https`, forward hostname `<proxmox-host>`, port 8006, websockets on. The proxy does
not verify the upstream certificate, so the self signed one is not a problem. Websockets matter here because the
browser console and the live statistics stop working without them.

---

### Verify

Before the router hands out AdGuard as DNS, you can still test the proxy by sending the Host header yourself.

Unix shell:

```bash
curl -skI -H "Host: dashboard.internal" http://<docker-vm-ip> | head -1
```

PowerShell:

```powershell
curl.exe -skI -H "Host: dashboard.internal" http://<docker-vm-ip>
```

A 200 or a 3xx status means the proxy resolved the name to a container and got an answer. A 502 means the container
is down or the forward port is wrong. A 404 from the proxy itself means no entry matches that name.

After the DNS cutover in [ADGUARD_DNS.md](ADGUARD_DNS.md), open `http://dashboard.internal` in a browser instead.

---

### Rebuilding quickly

The VM is disposable, the Compose file recreates the stack, and the proxy entries live in
`/opt/docker-stack/nginx/data`. Backing up that directory is what saves you from typing these entries again. Nginx
Proxy Manager also has a REST API, so a small script can recreate them all after a rebuild if you prefer that to
restoring the directory.
