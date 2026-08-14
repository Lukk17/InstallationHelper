# Homepage Dashboard

> The landing page that links to everything else, with a live status dot next to each service.

---

### Where the configuration lives

Homepage is configured by files, not by a settings screen. They sit on the host at `/opt/docker-stack/homepage/config/` and are mounted into the container at `/app/config`.

| File | Holds |
|---|---|
| `services.yaml` | The tiles, grouped, with their links and status checks |
| `settings.yaml` | Title, theme, layout and column counts |
| `widgets.yaml` | The header strip, clock, weather, system resources |
| `bookmarks.yaml` | Plain links with no status check |

The container writes a default set of these on first start, so bring the stack up once before editing them.

Homepage reloads most changes on its own within a few seconds. If a change does not appear, restart the one container:

```bash
docker compose restart homepage
```

---

### Allowed hosts, the first thing that will stop you

Homepage refuses any request whose hostname is not in its allow list, and answers `Host validation failed` instead of rendering. It is not a helpful error message the first time you meet it.

The list is set in the Compose file:

```yaml
environment:
  - HOMEPAGE_ALLOWED_HOSTS=dashboard-proxmox.internal
```

Add every name you actually use, separated by commas, including the address and port if you ever open it that way rather than through the proxy:

```yaml
environment:
  - HOMEPAGE_ALLOWED_HOSTS=dashboard-proxmox.internal,<docker-vm-ip>:7778
```

This is an environment variable, so the container has to be recreated rather than restarted:

```bash
docker compose up -d homepage
```

---

### href and siteMonitor are not the same thing

Every tile takes two addresses and they should not match.

`href` is where clicking the tile sends your browser. Use the friendly `.internal` name, because that is the address you want to see and share.

`siteMonitor` is what Homepage polls to decide whether the dot is green. Use the address and port directly.

The reason is failure isolation. If `siteMonitor` also went through the proxy and its internal name, then AdGuard or Nginx Proxy Manager falling over would paint every tile red at once, and the dashboard would tell you nothing about which service actually broke. Checking the container's own published port means a red dot means that service, and nothing else.

Proxmox and Home Assistant are not in the Compose stack, so they get their real addresses in both fields.

---

### services.yaml

Replace the placeholders with your own addresses. The concrete example block is at the top of [README_HOMELAB.md](README_HOMELAB.md).

```yaml
- Smart Home:
    - Home Assistant:
        icon: home-assistant
        href: http://<ha-vm-ip>:8123
        siteMonitor: http://<ha-vm-ip>:8123
        description: Automations and Zigbee

- Infrastructure:
    - Proxmox VE:
        icon: proxmox
        href: https://<proxmox-host>:8006
        siteMonitor: https://<proxmox-host>:8006
        description: Virtualization hypervisor
    - Nginx Proxy Manager:
        icon: nginx-proxy-manager
        href: http://nginx-proxmox.internal
        siteMonitor: http://<docker-vm-ip>:81
        description: Reverse proxy
    - AscendWebSearch:
        icon: mdi-magnify
        href: http://ascend-scrapper.internal
        siteMonitor: http://<docker-vm-ip>:7021/health
        description: Web search and scraping API

- Network and Monitoring:
    - AdGuard Home:
        icon: adguard-home
        href: http://adguard.internal
        siteMonitor: http://<docker-vm-ip>:7777
        description: DNS and ad blocking
    - Uptime Kuma:
        icon: uptime-kuma
        href: http://uptime.internal
        siteMonitor: http://<docker-vm-ip>:7779
        description: Service status monitoring

- Personal Data and Notes:
    - Syncthing:
        icon: syncthing
        href: http://syncthing.internal
        siteMonitor: http://<docker-vm-ip>:7780
        description: Continuous file synchronization
    - Perlite Notes:
        icon: markdown
        href: http://notes.internal
        siteMonitor: http://<docker-vm-ip>:7781
        description: Markdown notes viewer
```

The indentation is load bearing. A group is a list item whose value is a list of services, and each service is a mapping with one key. Homepage fails quietly on a malformed file, showing an empty dashboard rather than an error, so check your indentation first when nothing renders.

Icon names come from a bundled set that already covers most self-hosted software, and you can point `icon` at an image file instead if there is no match.

---

### Things worth knowing

The Proxmox tile stays a plain link. Proxmox serves HTTPS with a self signed certificate and rejects unauthenticated requests, so the status dot next to it is less trustworthy than the one next to a container. [uptime_kuma.md](uptime_kuma.md) checks it properly, with a ping.

The dashboard is the one thing everyone opens first, which makes it the worst place to discover that a name is wrong. After editing, click every tile once.

Homepage can also read live data from some services through widgets, which means putting an API key in the configuration. Nothing here does that, and nothing here should, because `/opt/docker-stack/` gets copied to other machines as a backup.
