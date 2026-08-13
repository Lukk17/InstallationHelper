# Uptime Kuma

> Polls everything else and tells you which piece broke, instead of you finding out because the lights stopped working.

---

### First run

Open `http://<docker-vm-ip>:7779`, or `http://uptime.internal` once the proxy entry exists.

The setup wizard asks you to create an administrator account and to choose a database.

Choose SQLite, the embedded option. It keeps everything in a single file under `/app/data`, which is mounted from `/opt/docker-stack/uptime-kuma/data` on the host, which is the directory [backup_restore.md](backup_restore.md) tells you to copy off the box. The external database option means a second service to run and back up separately, for a workload of a few checks a minute.

---

### The monitors

| Service | Type | Target |
|---|---|---|
| Router | Ping | `<router>` |
| Proxmox host | Ping | `<proxmox-host>` |
| Home Assistant | HTTP(s) | `http://<ha-vm-ip>:8123` |
| Nginx Proxy Manager | HTTP(s) | `http://<docker-vm-ip>:81` |
| AdGuard Home interface | HTTP(s) | `http://<docker-vm-ip>:7777` |
| AdGuard Home resolution | DNS | Resolve a public name using `<docker-vm-ip>` as the resolver |
| Homepage | HTTP(s) | `http://<docker-vm-ip>:7778` |
| Syncthing | HTTP(s) | `http://<docker-vm-ip>:7780` |
| Perlite notes | HTTP(s) | `http://<docker-vm-ip>:7781` |

Every target is an address and port, never an `.internal` name, for the same reason the dashboard checks work that way in [homepage_dashboard.md](homepage_dashboard.md). A monitor that resolves through AdGuard and travels through the proxy is really testing three things at once, and when it goes red it cannot tell you which one failed.

---

### Why Proxmox is a ping and not a web check

The Proxmox interface answers an unauthenticated request with 401 Unauthorized, which Uptime Kuma correctly treats as a failure. You would get a monitor that is permanently red on a host that is perfectly healthy, and a permanently red monitor is one you stop looking at.

Ping tells you the machine is up and on the network. That is the useful signal for a hypervisor, since if the host is reachable and a guest is not, the guest is the problem.

The router gets a ping for the same reason.

---

### Why AdGuard gets two monitors

The web interface and the resolver are different programs sharing a container, and they fail separately.

An HTTP check on port 7777 tells you the interface is answering. It does not tell you that DNS works, and DNS is the thing the whole house depends on.

A DNS type monitor makes Uptime Kuma perform a real lookup of a public name, using `<docker-vm-ip>` as the resolver server. That is the check that catches the failure everyone actually has, where the interface loads fine and nothing on the network can resolve anything.

Point it at a reliable public name that will not disappear, and remember that a name being blocked by your own filters would look like a failure, so do not use anything on your blocklists.

---

### Notifications

A monitoring system nobody is watching is a log file with a nicer font.

Set up at least one notification channel under Settings, then Notifications. Uptime Kuma supports the usual chat and push services, and any of them beats none.

Attach it to every monitor rather than a few, and set the retry count high enough that a single missed poll does not wake you. Two or three retries at sixty seconds is a reasonable starting point on a home network, where a brief blip is usually a device deciding to renew a lease rather than an outage.

---

### One thing this cannot tell you

Every monitor here lives on the same virtual machine as most of the things it checks. If that machine dies, Uptime Kuma dies with it, and it will not notify you about anything, including itself.

The honest way to cover that is a check from somewhere else, either a second instance elsewhere or an external service watching one endpoint. Nothing here does that, so treat a silent Uptime Kuma with suspicion rather than as good news.
