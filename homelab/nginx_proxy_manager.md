# Nginx Proxy Manager

> Adding the reverse proxy entries so each `.internal` name reaches the right container, and checking that they work.

---

### How the routing works

AdGuard resolves every `.internal` name to the VM address, so all of them arrive at Nginx Proxy Manager, on port 80
for `http` and on port 443 for `https`. The proxy then reads the Host header and forwards the request to the container
that owns that name. The entries below are what teaches it those names.

Every entry answers over `https` as well, with a certificate from the lab's own certificate authority, so both
`http://<name>.internal` and `https://<name>.internal` work. The certificate comes from the `internal-ca` job of the
Compose file and reaches every entry through an include file, not through the SSL tab, see [internal_ca.md](internal_ca.md).

Forward hostnames are container names, not addresses. Every service in the Compose file joins the `proxy-tier`
network, and Docker resolves container names on it, so `homepage` or `uptime-kuma` is all the proxy needs.

---

### Log in

Open `http://<docker-vm-ip>:81`.

A fresh install of 2.15.1 has no account and no default login. The first page is a setup wizard that asks for a full name, an email address and a password of at least 8 characters, and makes that account the administrator. Fill it in before anything else: port 81 is reachable from your whole network, and until the wizard is done anyone who opens the page can create the administrator.

The old default login, `admin@example.com` with `changeme`, does not exist in this version. Nginx Proxy Manager creates an account by itself only when the environment variables `INITIAL_ADMIN_EMAIL` and `INITIAL_ADMIN_PASSWORD` are both set and no account exists yet, and it then writes that password in plain text into the container log, where `docker logs nginx-proxy-manager` shows it to every account in the `docker` group. Use the wizard instead. If you did set the two variables, remove them and change the password in the web interface.

The credentials are stored hashed in `/opt/docker-stack/nginx/data/database.sqlite`. Losing them means resetting
through that database or wiping the directory and starting over.

---

### Add a proxy host

Go to Hosts, then Proxy Hosts, then Add Proxy Host, and fill in the Details tab.

1. Domain Names: type the name and press Enter so it turns into a chip.
2. Scheme: `http`.
3. Forward Hostname / IP: the container name or the address alone, never with a `:port` after it.
4. Forward Port: the port inside the container, not the published host port. This field is the only place the port goes.
5. Turn on Block Common Exploits and Websockets Support.
6. SSL tab: leave it on None, on every entry. The include from [internal_ca.md](internal_ca.md) already gives every
   entry `listen 443 ssl` and the certificate. A certificate picked here would add a second `listen 443` to the same
   entry, nginx refuses that with `a duplicate listen 0.0.0.0:443` (nginx 1.30.4 in a throwaway container,
   2026-10-24), and Nginx Proxy Manager then renames that entry's file to `.err` and shows it Offline, lines 57 to 89
   of `backend/internal/nginx.js` at tag v2.15.1.
7. Save. The entry turns green and reports Online.
8. Add the name to `INTERNAL_DNS_NAMES` and run the certificate job, as
   [Add a new .internal name](internal_ca.md#add-a-new-internal-name) says. Until then the entry works over `http`
   only, and `https` fails with `unrecognized name`.

---

### The entries

| Domain name | Scheme | Forward hostname | Port | Websockets |
|---|---|---|---|---|
| `dashboard-proxmox.internal` | http | `homepage` | 3000 | on |
| `uptime.internal` | http | `uptime-kuma` | 3001 | on |
| `syncthing.internal` | http | `syncthing` | 8384 | on |
| `adguard.internal` | http | `adguard-home` | 7777 | on |
| `nginx-proxmox.internal` | http | `nginx-proxy-manager` | 81 | on |
| `notes.internal` | http | `perlite-web` | 80 | on |
| `ascend-web-hunter.internal` | http | `ascend-web-hunter` | 7021 | on |
| `files.internal` | http | `filebrowser` | 80 | on |

The forward port is the container port from the right hand side of each Compose port mapping. Using the published
host port instead is the usual reason a new entry returns 502.

`ascend-web-hunter` is the one entry above where the forward port and the published host port are the same number,
7021. That is not a mistake to "fix" by looking for a different container port, the service happens to publish and
listen on the same port. See [ascend_web_hunter.md](ascend_web_hunter.md) for how that stack joins this network.

Never type the port into Forward Hostname / IP as well. Nginx Proxy Manager 2.15.1 puts the two fields together as
`proxy_pass $forward_scheme://$server:$port$request_uri`, so `192.168.1.10:8006` in the hostname field and `8006` in
the port field become the upstream `192.168.1.10:8006:8006`. Every request then answers 500, and
`/data/logs/proxy-host-<id>_error.log` inside the container says `invalid port in upstream "192.168.1.10:8006:8006/"`.
The proxy host page still shows the entry as Online, because the configuration test does not check an address built
from variables.

---

### Proxying the Proxmox interface

The hypervisor is not a container, so it needs an address instead of a name, and it serves HTTPS with a self signed
certificate.

| Domain name | Scheme | Forward hostname | Port | Websockets |
|---|---|---|---|---|
| `proxmox.internal` | https | `<proxmox-host>` | 8006 | on |

Fill in the Details tab like this:

1. Domain Names: `proxmox.internal`.
2. Scheme: `https`. This is the only entry with scheme `https`. The proxy does not verify the upstream certificate,
   so the self signed one is not a problem.
3. Forward Hostname / IP: the address alone, `<proxmox-host>`, with no `:8006` after it.
4. Forward Port: `8006`.
5. Turn on Block Common Exploits and Websockets Support. The browser console of a virtual machine and the live
   statistics stop working without websockets.

Then open the Advanced tab and paste these lines into Custom Nginx Configuration:

```nginx
proxy_buffering off;
client_max_body_size 0;
proxy_read_timeout 3600s;
proxy_send_timeout 3600s;
send_timeout 3600s;
```

They come from the Proxmox wiki page [Web Interface Via Nginx Proxy](https://pve.proxmox.com/wiki/Web_Interface_Via_Nginx_Proxy),
read on 2026-10-24. Buffering off and the long timeouts keep a console session open, and `client_max_body_size 0`
lets an ISO image upload through. Three things from that page are left out on purpose. `proxy_connect_timeout` is
left out, because nginx caps it at about 75 seconds whatever the value says. `proxy_set_header` lines and `location`
blocks are left out, because Nginx Proxy Manager puts the Advanced text at server level and its own `location /`
already sets the headers and the websocket upgrade.

In this lab the two fields read like this:

```text
Forward Hostname / IP: 192.168.1.10
Forward Port: 8006
```

Open it as `https://proxmox.internal`. The certificate comes from the local certificate authority in
[internal_ca.md](internal_ca.md), so a browser that trusts that authority shows no warning, and the SSL tab of this
entry stays on None like every other.

Use `https`, not `http`, for this one name. Proxmox sets its login cookie with the Secure flag,
`Ext.util.Cookies.set(..., true, "lax")` at line 322 of `proxmoxlib.js` on the lab's Proxmox host, and a browser
ignores a Secure cookie on a plain HTTP page, so over `http://proxmox.internal` the login form keeps coming back. This
was read in the code and has not been seen in a browser yet. Opening Proxmox directly at `https://<proxmox-host>:8006`,
which is what the Homepage tile in [homepage_dashboard.md](homepage_dashboard.md) does, still works as well, with its
self signed certificate accepted once per browser.

On this lab, on 2026-10-24, `https://proxmox.internal/` answered with a certificate that verified against the lab's
authority, but with status 500, because the entry still had `192.168.1.10:8006` in Forward Hostname, the mistake
described in [The entries](#the-entries). The login over `https` has not been tried yet.

Home Assistant deliberately has no entry. It lives on its own virtual machine at `<ha-vm-ip>:8123`, and every phone
in the house already has that bookmarked or uses the app, so putting it behind a name that only resolves on the home
network buys nothing.

---

### Proxying Plex

Plex is a container, but it runs with host networking rather than on `proxy-tier`, for the reason given in [plex_media_server.md](plex_media_server.md). The proxy cannot reach it by container name, so like Proxmox it gets the VM's address.

| Domain name | Scheme | Forward hostname | Port | Websockets |
|---|---|---|---|---|
| `plex.internal` | http | `<docker-vm-ip>` | 32400 | on |

Open it as `http://plex.internal/web`. TV and phone apps do not use this name, they connect to `<docker-vm-ip>:32400` directly.

Samba, the network drive at `\\files.internal\files`, has no entry at all. It is not web traffic, and it answers on the VM's address directly, see [lan_storage.md](lan_storage.md).

---

### Verify

Before the router hands out AdGuard as DNS, you can still test the proxy by sending the Host header yourself.

Unix shell:

```bash
curl -skI -H "Host: dashboard-proxmox.internal" http://<docker-vm-ip> | head -1
```

PowerShell:

```powershell
curl.exe -skI -H "Host: dashboard-proxmox.internal" http://<docker-vm-ip>
```

A 200 or a 3xx status means the proxy resolved the name to a container and got an answer. A 502 means the container
is down or the forward port is wrong. A 404 from the proxy itself means no entry matches that name.

The `https` side needs the name itself rather than a Host header, because the proxy picks the certificate from the
name the client sends during the handshake. `--resolve` sends the name and connects to the address you give, and
`--cacert` checks the certificate against your authority. The last number printed is 0 when the certificate verified.
Unix shell:

```bash
curl -sS -o /dev/null -w '%{http_code} %{ssl_verify_result}\n' --cacert <ca-dir>/ca.crt --resolve dashboard-proxmox.internal:443:<docker-vm-ip> https://dashboard-proxmox.internal/
```

PowerShell, with the curl that ships with Windows:

```powershell
curl.exe -sS -o NUL -w "%{http_code} %{ssl_verify_result}\n" --cacert <ca-dir>\ca.crt --resolve dashboard-proxmox.internal:443:<docker-vm-ip> https://dashboard-proxmox.internal/
```

On 2026-10-24 curl 8.23.0 in a container ran these options against the lab, with DNS instead of `--resolve`, and
against a throwaway copy of the proxy, with `--resolve`. The PowerShell line has not been run on Windows.

After the DNS cutover in [adguard_dns.md](adguard_dns.md), open `http://dashboard-proxmox.internal` or
`https://dashboard-proxmox.internal` in a browser instead.

---

### Rebuilding quickly

The VM is disposable, the Compose file recreates the stack, and the proxy entries live in
`/opt/docker-stack/nginx/data`. Backing up that directory is what saves you from typing these entries again. Nginx
Proxy Manager also has a REST API, so a small script can recreate them all after a rebuild if you prefer that to
restoring the directory.
