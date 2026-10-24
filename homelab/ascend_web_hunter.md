# ascend-web-hunter

> A web search and scraping stack that runs as its own Compose project next to the main homelab stack, joined to it only through the shared proxy network.

---

### What this is

ascend-web-hunter is a small self-contained service from the [AscendAI](https://github.com/Lukk17/AscendAI) project that answers search queries by driving a real search engine and, when a site blocks scrapers, a real browser. It exposes a REST API, a plain way for a program to ask a service for data over HTTP by sending a request and getting a structured answer back, and a Model Context Protocol server, a standard that lets an AI assistant call a tool like this one directly instead of a person clicking through a web page.

The service was called AscendWebSearch, with the container `ascend-web-search` and the proxy name `ascend-scrapper.internal`, until AscendAI renamed it to ascend-web-hunter in its commit `ebe3476` on 2026-09-10. This page, the deploy directory and every proxy, dashboard and monitor entry now use the new names.

The deployment files live in [ascend-web-hunter_deploy/](ascend-web-hunter_deploy/) inside this `homelab/` directory, but they are a separate Compose project with their own project name, `ascend-scrapper`, which AscendAI has kept. It is not part of `compose.yaml` and is not started by `docker compose up -d` at the root of this directory. It has its own lifecycle, documented in full in [ascend-web-hunter_deploy/README.md](ascend-web-hunter_deploy/README.md). This page covers what matters for running it inside this specific homelab, and does not repeat what is already in that README.

---

### Before the first start

1. The homelab stack in [compose.yaml](compose.yaml) must be up, because it creates the `proxy-tier` network and runs the Redis this stack uses.
2. The image `lukk17/ascend-ai-ascend-web-hunter:latest` must exist in the registry. On 2026-10-24 Docker Hub listed no tag for it at all, so `docker compose up -d` could not pull it. The check is in the [Prerequisites](ascend-web-hunter_deploy/README.md#prerequisites) of the deploy README.
3. The three secrets must be in `.env`, covered below.

Only if the earlier AscendWebSearch stack ever ran on this VM: stop it before starting this one. Both stacks use the project name `ascend-scrapper` and the container name `searxng`, and a git pull removes the old compose file, so stop it by its project name:

```bash
docker compose -p ascend-scrapper down
```

The pull leaves the old directory behind holding only its `.env`, because git does not track that file. The new stack needs a new `.env` anyway, so delete the old directory:

```bash
rm -rf /opt/docker-stack/InstallationHelper/homelab/ascend-web-search_deploy
```

Then start the new stack from its own directory:

```bash
cd /opt/docker-stack/InstallationHelper/homelab/ascend-web-hunter_deploy
```

```bash
docker compose up -d
```

---

### The three containers

| Container | Does |
|---|---|
| `ascend-web-hunter` | The service itself. Answers the REST API and the Model Context Protocol server, and is the only container published on the host, at port 7021. |
| `searxng` | A self-hosted meta search engine. ascend-web-hunter queries it instead of any single search provider directly. Not published, reachable only inside the stack. |
| `ngrok-ascend-web-hunter` | An outbound only tunnel that makes the remote desktop described below reachable from outside the network, for the times a challenge needs a human. |

AscendAI's bundle has a fourth container, its own Redis. This copy leaves it out and uses the homelab Redis, see [Redis](#redis). The FlareSolverr container of the older stack is gone, because AscendAI removed that tier on 2026-10-20, in a change that was not yet on its GitHub `master` branch on 2026-10-24.

---

### Image tags, and why a restart is not an upgrade

`ascend-web-hunter` is the one image in this homelab published from this account, so its `image:` line follows the `latest` tag instead of naming a version. The deployment therefore always points at the newest build of that service, and the drift that a floating tag brings is accepted here because the same person decides what goes into the tag. The other two containers in the stack are somebody else's builds and stay pinned to exact versions.

What this does not give you is an upgrade that happens by itself. `restart: unless-stopped` brings the container back from the image already on the host, and a plain `docker compose up -d` pulls only when nothing local carries that tag, so a newer published build sits in the registry unnoticed until something fetches it. Getting onto it takes an explicit pull and then a recreate, and both are one command each in [ascend-web-hunter_deploy/README.md](ascend-web-hunter_deploy/README.md#upgrading), which also covers going back to an older build when a new one misbehaves.

---

### Joining the homelab reverse proxy

`ascend-web-hunter` is attached to two Docker networks: `default`, which is private to the `ascend-scrapper` project and is what lets it reach `searxng`, and `proxy-tier`, the network this homelab's [compose.yaml](compose.yaml) declares for every service that Nginx Proxy Manager needs to reach by name. `searxng` stays off `proxy-tier` on purpose, since nothing outside its own stack should be able to reach it.

For `proxy-tier` to be something a second Compose project can join reliably, [compose.yaml](compose.yaml) gives that network an explicit stable name, `name: proxy-tier`, rather than letting Docker derive one from the directory. Applying that name change to a stack that is already running takes one down and one up:

```bash
docker compose down
```

```bash
docker compose up -d
```

That recreates every container in `compose.yaml`, which is expected and harmless here: none of those services keep state inside the container, every one of them bind mounts its data from `/opt/docker-stack/` on the host, so nothing is lost. Redis is the one exception worth naming, and it is covered next.

Once both stacks share `proxy-tier`, Nginx Proxy Manager reaches the service at the container name `ascend-web-hunter`, which is how the `ascend-web-hunter.internal` entry in [nginx_proxy_manager.md](nginx_proxy_manager.md) works. The proxy name is the container name with `.internal` added, the name the `ascend-web-hunter` agent skill tries before `localhost:7021`, and the same pattern the other entries follow. The service keeps its `7021:7021` port mapping on the host too, so it stays reachable three separate ways at once: by container name from the proxy, directly at `<docker-vm-ip>:7021`, and its Redis connection over the host gateway described next.

The Model Context Protocol endpoint, `/mcp`, checks the Host header of every request and answers `421 Misdirected Request` to a name it does not know. The deploy file accepts `ascend-web-hunter.internal` by default, so a client that uses the proxy name works. A client that uses `<docker-vm-ip>:7021` needs that address added, as [ascend-web-hunter_deploy/README.md](ascend-web-hunter_deploy/README.md#the-mcp-endpoint-and-host-names) shows.

---

### Redis

ascend-web-hunter needs Redis to remember authentication cookies and Cloudflare clearance tokens between requests. Without it every request starts a cold session and the readiness check below reports it as degraded.

This homelab's [compose.yaml](compose.yaml) runs Redis as one of its own services, the container `redis`, published on the host at `6379:6379` with no password and no data volume. The tradeoff was made deliberately and is not repeated as a warning here beyond this one sentence: an unauthenticated Redis published on 6379 is reachable from every device on the local network, and with no volume its contents are lost on every restart. For ascend-web-hunter that loss is cheap, cookies and clearance tokens are the kind of thing that is fine to make again.

AscendAI's bundle now ships its own Redis, also with the container name `redis`. Docker allows one container per name on a host, so that container would refuse to start next to the homelab one, and the deploy copy here leaves it out.

The default `REDIS_URL` in [ascend-web-hunter_deploy/compose.yaml](ascend-web-hunter_deploy/compose.yaml) is `redis://host.docker.internal:6379/0`, reaching this homelab's Redis over the Docker host gateway rather than by container name. It works because the homelab Redis publishes 6379 on the host, and the deploy file's `extra_hosts: host.docker.internal:host-gateway` entry gives the container a route to that host port.

Now that both stacks share `proxy-tier`, `redis://redis:6379/0` would also work, reaching the same Redis by its container name over the shared network instead of leaving the container and coming back in through the host gateway, saving one hop. To use it, put `REDIS_URL=redis://redis:6379/0` into `.env`.

---

### The three secrets

Everything sensitive lives in `.env` inside [ascend-web-hunter_deploy/](ascend-web-hunter_deploy/), written before the first start with the commands in the [Quick start](ascend-web-hunter_deploy/README.md#quick-start) of its README. Compose refuses to start and names the missing variable if any of the three is blank.

| Variable | Real constraint |
|---|---|
| `SEARXNG_SECRET` | At least 32 characters, unique to this deployment, and never the literal string `ultrasecretkey`, which SearXNG rejects outright. Nobody types this by hand, so there is no reason to make it short. |
| `VNC_PASSWORD` | Virtual Network Computing, the protocol behind the remote desktop below, truncates any password at 8 characters. A longer value is not rejected, it is silently cut, and the extra characters do nothing. Treat it as an 8 character password even if you type more. |
| `NGROK_AUTHTOKEN` | The account token from [the ngrok dashboard](https://dashboard.ngrok.com/get-started/your-authtoken). Authenticates the tunnel container to your ngrok account, it does not by itself protect anything the tunnel exposes. |

---

### Resource footprint

Every container carries a hard memory and CPU ceiling, sized for an 8 GB host that already runs the rest of this homelab stack.

| Container | CPU limit | Memory limit |
|---|---|---|
| `ascend-web-hunter` | 1.5 | 2560M |
| `searxng` | 0.5 | 384M |
| `ngrok-ascend-web-hunter` | 0.25 | 96M |

Memory ceilings total 3.0 GB. At rest, the reservations the stack actually holds total about 0.7 GB of memory and 0.4 CPU cores. Before running this alongside the rest of the homelab stack, subtract what the host already uses from its total memory and check the remainder clears 3.0 GB with headroom left for disk page cache. The full arithmetic, including why `ascend-web-hunter` gets a 1 GB `/dev/shm` shared memory allocation that counts against its own ceiling, is in [ascend-web-hunter_deploy/README.md](ascend-web-hunter_deploy/README.md#resource-footprint).

---

### Verifying it works

Two endpoints answer different questions. `/health` is a shallow check, it confirms the process is up and answering, and it is what the container's own healthcheck and the Uptime Kuma monitor in [uptime_kuma.md](uptime_kuma.md) use. `/ready` is the deep check, it also probes Redis and SearXNG and reports each one separately, which makes it the right endpoint the first time you set this up or whenever something feels wrong.

Unix shell:

```bash
curl -s http://localhost:7021/ready
```

PowerShell, from another machine on the network:

```powershell
curl.exe -s http://<docker-vm-ip>:7021/ready
```

A healthy response has `"status": "ready"` with every check reading `ok`. Redis reading `error` is the usual first failure and means the container cannot reach Redis on the host, see the Redis section above.

Once `.internal` resolution and the proxy entry are both in place, the same check works through the name instead:

```bash
curl -s http://ascend-web-hunter.internal/ready
```

---

### The ngrok exposure

The stack keeps an ngrok tunnel running by design, and this section documents what that means rather than arguing for turning it off.

When the scraping chain hits a challenge it cannot clear itself, it hands control to a real Chrome browser running inside the container, and `ngrok-ascend-web-hunter` publishes that browser's remote desktop to a public ngrok address for as long as the container runs. Reaching that address opens a working browser session inside the container, driven exactly like a browser on your own machine, protected by nothing except the `VNC_PASSWORD` from `.env`, which is at most 8 characters because the protocol truncates it there. Anyone who guesses or brute forces that password gets a real browser they can drive, not just a view of one.

That password is the entire barrier. It is not a login form with rate limiting, it is a fixed length password on a protocol that was never designed with the public internet in mind. The tradeoff was made deliberately in exchange for being able to solve a CAPTCHA, a challenge test a website presents to tell a human apart from a bot, by hand from anywhere without opening a port on the router.

---

### Related documentation

- [ascend-web-hunter_deploy/README.md](ascend-web-hunter_deploy/README.md), full prerequisites, quick start, upgrading, and the complete security notes for this stack
- [nginx_proxy_manager.md](nginx_proxy_manager.md), the `ascend-web-hunter.internal` proxy entry
- [homepage_dashboard.md](homepage_dashboard.md), the dashboard tile
- [uptime_kuma.md](uptime_kuma.md), the uptime monitor
