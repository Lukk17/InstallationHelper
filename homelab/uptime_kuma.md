# Uptime Kuma

> Polls everything else and tells you which piece broke, instead of you finding out because the lights stopped working.

---

### First run

Open `http://<docker-vm-ip>:7779`, or `http://uptime.internal` once the proxy entry exists.

The setup wizard asks you to create an administrator account and to choose a database.

Choose SQLite, the embedded option. It keeps everything in a single file under `/app/data`, which is mounted from `/opt/docker-stack/uptime-kuma/data` on the host, which is the directory [backup_restore.md](backup_restore.md) tells you to copy off the box. The external database option means a second service to run and back up separately, for a workload of 12 checks a minute from the six network monitors, below, plus the service monitors.

---

### The 2.5.5 image

The Compose file pins `louislam/uptime-kuma:2.5.5` ([compose.yaml](compose.yaml)). It carries nothing that needs a manual step beyond the version bump itself. The releases between 2.5.1 and 2.5.5 fixed a memory leak on TCP monitors, fixed a bug where the two ping timeout fields in the monitor form were swapped, and patched a denial of service weakness in a bundled library, CVE-2026-77415, listed in the official 2.5.4 release notes on GitHub. None of them touch the Docker image layout or the database schema.

---

### The monitors

Two kinds of monitor live here: service checks that confirm each container answers, and network checks that alert you when the router, the provider or the internet stops answering.

#### Service monitors

| Service | Type | Target |
|---|---|---|
| Proxmox host | Ping | `<proxmox-host>` |
| Home Assistant | HTTP(s) | `http://<ha-vm-ip>:8123` |
| Nginx Proxy Manager | HTTP(s) | `http://<docker-vm-ip>:81` |
| AdGuard Home interface | HTTP(s) | `http://<docker-vm-ip>:7777` |
| Homepage | HTTP(s) | `http://<docker-vm-ip>:7778` |
| Syncthing | HTTP(s) | `http://<docker-vm-ip>:7780` |
| Perlite notes | HTTP(s) | `http://<docker-vm-ip>:7781` |
| AscendWebSearch | HTTP(s) | `http://<docker-vm-ip>:7021/health` |
| File Browser | HTTP(s) | `http://<docker-vm-ip>:7782/health` |
| Samba network drive | TCP Port | Hostname `<docker-vm-ip>`, Port `445` |
| Plex | HTTP(s) | `http://<docker-vm-ip>:32400/identity` |

Every target is an address and port, never an `.internal` name, for the same reason the dashboard checks work that way in [homepage_dashboard.md](homepage_dashboard.md). A monitor that resolves through AdGuard and travels through the proxy is really testing three things at once, and when it goes red it cannot tell you which one failed.

#### Network monitors

These six are for alerts only. The record of every short provider drop is the Telegraf data in [network_watch.md](network_watch.md), which checks the same layers every second, so these monitors check every 30 seconds. With one retry 30 seconds later, a monitor goes red after two failed checks in a row, so a drop shorter than that can pass unseen here and still shows in the Telegraf files. Every check is a row in the Uptime Kuma database, which is why they no longer run every 2 to 7 seconds, as the six did on this lab until 2026-10-23.

Add each one from scratch:

1. Click Add New Monitor.
2. Set Monitor Type to the type in the table below.
3. Set Friendly Name to the name in the table below.
4. Fill in the type-specific fields from the table below.
5. Set Heartbeat Interval to 30, Retries to 1, and Heartbeat Retry Interval to 30.
6. Click Save.

| Friendly Name | Monitor Type | Fields |
|---|---|---|
| Asus Router | Ping | Hostname `192.168.1.1` |
| AdGuard Home DNS | DNS | Hostname `connectivitycheck.gstatic.com`, Resolver Server `192.168.1.12`, Port `53`, Resource Record Type `A` |
| Orange DNS | Ping | Hostname `194.204.159.1` |
| Internet 1.1.1.1 | Ping | Hostname `1.1.1.1` |
| DNS direct 1.1.1.1 | DNS | Hostname `connectivitycheck.gstatic.com`, Resolver Server `1.1.1.1`, Port `53`, Resource Record Type `A` |
| Internet web check | HTTP(s) | URL `http://connectivitycheck.gstatic.com/generate_204` |

Internet web check answers 204, which sits inside Uptime Kuma's own default accepted status code range, so leave that field alone.

While you are in there, go to Settings, then Monitor History, and set "Keep monitor history data for" to 30 days, to match the CSV retention [network_watch.md](network_watch.md) keeps and stop the database from growing without a limit.

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

### Why AscendWebSearch gets the shallow check

That service also answers `/ready`, which probes its Redis connection, SearXNG and FlareSolverr individually and is the right endpoint for diagnosing a problem by hand, covered in [ascend_web_search.md](ascend_web_search.md). It is the wrong endpoint for a monitor that polls every minute, for the same reason the other monitors above avoid the proxy: a single dependency having a bad moment would paint the whole service red, when only one piece actually broke. `/health` only confirms the process itself is up and answering, which is the correct question for this table to ask.

---

### Notifications

A monitoring system nobody is watching is a log file with a nicer font.

Set up at least one notification channel under Settings, then Notifications. Uptime Kuma supports the usual chat and push services, and any of them beats none.

Attach it to every monitor rather than a few, and set the retry count high enough that a single missed poll does not wake you. For the service monitors, two or three retries at sixty seconds is a reasonable starting point on a home network, where a brief blip is usually a device deciding to renew a lease rather than an outage. The six network monitors keep their own setting instead, interval 30, retries 1, retry interval 30, as [Network monitors](#network-monitors) explains.

---

### After adding a new tag, restart the container

Uptime Kuma 2.5.5 reads the tag names once, when it starts, and uses them as the labels of its Prometheus metrics. Its own source, `server/prometheus.js`, says so: "New tags will NOT be added dynamically, a restart is sadly required to add new tags to the metrics." A monitor that carries a tag created after the start then fails to write its metrics on every heartbeat, and each failure writes a stack trace to the container log that starts with:

```text
[PROMETHEUS] ERROR: Error: Added label "networkwatch" is not included in initial labelset
```

On this lab, on 2026-10-23, after the tag `networkwatch` was added to the network monitors, that log grew 1,607,027 bytes in 60 seconds, about 2.3 GB a day, and had reached 24.7 GB before anybody saw it. The restart stopped it at once: 0 bytes in the next 60 seconds. The `logging` block in [compose.yaml](compose.yaml) now keeps each container log to three files of 10 MB, so a flood like this one can no longer fill the disk, but it still hides every other line in the log until the restart.

The cap applies only to a container created after it was added to the file. Recreate the stack once on the Docker VM, which replaces every container whose settings changed and, with it, its old log:

```bash
cd /opt/docker-stack && docker compose up -d
```

So after you create a tag, and before you leave it on a monitor, restart Uptime Kuma on the Docker VM:

```bash
docker restart uptime-kuma
```

Then check that the error is gone. A count of 0 means it is:

```bash
docker logs --since 1m uptime-kuma 2>&1 | grep -c PROMETHEUS
```

---

### One thing this cannot tell you

Every monitor here lives on the same virtual machine as most of the things it checks. If that machine dies, Uptime Kuma dies with it, and it will not notify you about anything, including itself.

The honest way to cover that is a check from somewhere else, either a second instance elsewhere or an external service watching one endpoint. Nothing here does that, so treat a silent Uptime Kuma with suspicion rather than as good news.
