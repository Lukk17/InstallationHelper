# ascend-web-hunter

> A web search and scraping stack that runs as its own Compose project next to the main homelab stack, joined to it only through the shared proxy network.

---

### What this is

ascend-web-hunter is a small self-contained service from the [AscendAI](https://github.com/Lukk17/AscendAI) project that answers search queries by driving a real search engine and, when a site blocks scrapers, a real browser. It exposes a REST API, a plain way for a program to ask a service for data over HTTP by sending a request and getting a structured answer back, and a Model Context Protocol server, a standard that lets an AI assistant call a tool like this one directly instead of a person clicking through a web page.

The service was called AscendWebSearch, with the container `ascend-web-search` and the proxy name `ascend-scrapper.internal`, until AscendAI renamed it to ascend-web-hunter in its commit `ebe3476` on 2026-09-10. This page, the deploy directory and every proxy and monitor entry now use the new names. The service has no Homepage dashboard tile, by the owner's choice.

The deployment files live in [ascend-web-hunter_deploy/](ascend-web-hunter_deploy/) inside this `homelab/` directory, but they are a separate Compose project with their own project name, `ascend-scrapper`, which AscendAI has kept. It is not part of `compose.yaml` and is not started by `docker compose up -d` at the root of this directory. It has its own lifecycle, documented in full in [ascend-web-hunter_deploy/README.md](ascend-web-hunter_deploy/README.md). This page covers what matters for running it inside this specific homelab, and does not repeat what is already in that README.

---

### Before the first start

1. The homelab stack in [compose.yaml](compose.yaml) must be up, because it creates the `proxy-tier` network and runs the Redis this stack uses.
2. The image `lukk17/ascend-ai-ascend-web-hunter:v0.0.15` must exist in the registry. The AscendAI release workflow published it on 2026-11-09. The check is in the [Prerequisites](ascend-web-hunter_deploy/README.md#prerequisites) of the deploy README.
3. The secrets must be in `.env`, covered below.

Only if the earlier AscendWebSearch stack ever ran on this VM: stop it before starting this one. Both stacks use the project name `ascend-scrapper` and the container name `searxng`. Stop it by its project name, which works from any folder and does not need its old compose file:

```bash
docker compose -p ascend-scrapper down
```

The stack runs from a plain copy of the four files of [ascend-web-hunter_deploy/](ascend-web-hunter_deploy/) on the VM, not a clone of this repository, the same way as the main stack in [Deploying from your clone](README_HOMELAB.md#deploying-from-your-clone). On the VM, create its folder, with the `searxng` folder inside it:

```bash
mkdir -p /opt/docker-stack/ascend-web-hunter/searxng
```

From your own machine, copy the Compose file, `.env.example` and the README. Unix shell:

```bash
scp <repo>/homelab/ascend-web-hunter_deploy/compose.yaml <repo>/homelab/ascend-web-hunter_deploy/.env.example <repo>/homelab/ascend-web-hunter_deploy/README.md <user>@<docker-vm-ip>:/opt/docker-stack/ascend-web-hunter/
```

PowerShell:

```powershell
scp <repo>\homelab\ascend-web-hunter_deploy\compose.yaml <repo>\homelab\ascend-web-hunter_deploy\.env.example <repo>\homelab\ascend-web-hunter_deploy\README.md <user>@<docker-vm-ip>:/opt/docker-stack/ascend-web-hunter/
```

Then the SearXNG settings, which SearXNG will not start without. Unix shell:

```bash
scp <repo>/homelab/ascend-web-hunter_deploy/searxng/settings.yaml <user>@<docker-vm-ip>:/opt/docker-stack/ascend-web-hunter/searxng/settings.yaml
```

PowerShell:

```powershell
scp <repo>\homelab\ascend-web-hunter_deploy\searxng\settings.yaml <user>@<docker-vm-ip>:/opt/docker-stack/ascend-web-hunter/searxng/settings.yaml
```

On this lab, from a clone in `~/Projects/InstallationHelper`:

```bash
scp ~/Projects/InstallationHelper/homelab/ascend-web-hunter_deploy/compose.yaml ~/Projects/InstallationHelper/homelab/ascend-web-hunter_deploy/.env.example ~/Projects/InstallationHelper/homelab/ascend-web-hunter_deploy/README.md lukk@192.168.1.12:/opt/docker-stack/ascend-web-hunter/
```

```bash
scp ~/Projects/InstallationHelper/homelab/ascend-web-hunter_deploy/searxng/settings.yaml lukk@192.168.1.12:/opt/docker-stack/ascend-web-hunter/searxng/settings.yaml
```

A later change to any of the four files reaches the VM the same way, with the same commands.

Then, on the VM, go into the folder:

```bash
cd /opt/docker-stack/ascend-web-hunter
```

Write `.env` there with the commands in the [Quick start](ascend-web-hunter_deploy/README.md#quick-start) of the deploy README, then start the stack:

```bash
docker compose up -d
```

It was deployed this way on this lab on 2026-11-10, and `/ready` answered `ready` with every check `ok`.

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

`ascend-web-hunter` runs the release tag `v0.0.15`, the same tag the AscendAI bundle pins, so the deployment changes only when somebody edits the `image:` line. The other two containers in the stack are somebody else's builds and stay pinned to a tag plus its `sha256` digest.

`restart: unless-stopped` brings the container back from the image already on the host, so a newer release never arrives on its own. Moving to it means putting its tag on the `image:` line, then an explicit pull and a recreate, each one command in [ascend-web-hunter_deploy/README.md](ascend-web-hunter_deploy/README.md#upgrading), which also covers going back to an older build when a new one misbehaves.

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

The proxy host for `ascend-web-hunter.internal` also needs one line in its Advanced tab, Custom Nginx Configuration:

```nginx
proxy_read_timeout 180s;
```

One read can take up to 150 seconds, and the proxy's default `proxy_read_timeout` is 90 seconds, so without the line a long read ends in an error page from the proxy at 90 seconds. The full row is in [nginx_proxy_manager.md](nginx_proxy_manager.md#every-internal-name).

The Model Context Protocol endpoint, `/mcp`, checks the Host header of every request and answers `421 Misdirected Request` to a name it does not know. The deploy file accepts `ascend-web-hunter.internal` by default, so a client that uses the proxy name works. A client that uses `<docker-vm-ip>:7021` needs that address added, as [ascend-web-hunter_deploy/README.md](ascend-web-hunter_deploy/README.md#the-mcp-endpoint-and-host-names) shows.

---

### Redis

ascend-web-hunter needs Redis to remember authentication cookies and Cloudflare clearance tokens between requests. Without it every request starts a cold session and the readiness check below answers `not-ready` with the `redis` check reading `error`.

This homelab's [compose.yaml](compose.yaml) runs Redis as one of its own services, the container `redis`, published on the host at `6379:6379` with no password and no data volume. The tradeoff was made deliberately and is not repeated as a warning here beyond this one sentence: an unauthenticated Redis published on 6379 is reachable from every device on the local network, and with no volume its contents are lost on every restart. For ascend-web-hunter that loss is cheap, cookies and clearance tokens are the kind of thing that is fine to make again.

AscendAI's bundle now ships its own Redis, also with the container name `redis`. Docker allows one container per name on a host, so that container would refuse to start next to the homelab one, and the deploy copy here leaves it out.

The default `REDIS_URL` in [ascend-web-hunter_deploy/compose.yaml](ascend-web-hunter_deploy/compose.yaml) is `redis://host.docker.internal:6379/0`, reaching this homelab's Redis over the Docker host gateway rather than by container name. It works because the homelab Redis publishes 6379 on the host, and the deploy file's `extra_hosts: host.docker.internal:host-gateway` entry gives the container a route to that host port.

Now that both stacks share `proxy-tier`, `redis://redis:6379/0` would also work, reaching the same Redis by its container name over the shared network instead of leaving the container and coming back in through the host gateway, saving one hop. To use it, put `REDIS_URL=redis://redis:6379/0` into `.env`.

---

### The three secrets

Everything sensitive lives in `.env` beside the copy of [ascend-web-hunter_deploy/](ascend-web-hunter_deploy/) on the VM, `/opt/docker-stack/ascend-web-hunter/.env`, written before the first start with the commands in the [Quick start](ascend-web-hunter_deploy/README.md#quick-start) of its README. `SEARXNG_SECRET` and `NGROK_AUTHTOKEN` are required, and Compose refuses to start and names the missing variable if either is blank. `VNC_PASSWORD` is optional.

| Variable | Real constraint |
|---|---|
| `SEARXNG_SECRET` | Required. At least 32 characters, unique to this deployment, and never the literal string `ultrasecretkey`, which SearXNG rejects outright. Nobody types this by hand, so there is no reason to make it short. |
| `VNC_PASSWORD` | Optional. Empty means the remote desktop below accepts any client, and the container logs a warning at boot. When set, Virtual Network Computing, the protocol behind that desktop, truncates it at 8 characters. A longer value is not rejected, it is silently cut, and the extra characters do nothing. Treat it as an 8 character password even if you type more. |
| `NGROK_AUTHTOKEN` | Required. The account token from [the ngrok dashboard](https://dashboard.ngrok.com/get-started/your-authtoken). Authenticates the tunnel container to your ngrok account, it does not by itself protect anything the tunnel exposes. |

---

### Resource footprint

Every container carries a hard memory and CPU ceiling. The numbers come from the AscendAI bundle, which sizes them for an 8 GB host that already runs other services, and this lab's Docker VM has 9 GiB.

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

When the scraping chain hits a challenge it cannot clear itself, it hands control to a real Chrome browser running inside the container, and `ngrok-ascend-web-hunter` publishes that browser's remote desktop to a public ngrok address for as long as the container runs. Reaching that address opens a working browser session inside the container, driven exactly like a browser on your own machine, protected by nothing except the `VNC_PASSWORD` from `.env`, which is at most 8 characters because the protocol truncates it there. With `VNC_PASSWORD` empty there is no barrier at all: anyone who reaches the address controls the browser, including any login a human is part way through. With a password, anyone who guesses or brute forces it gets a real browser they can drive, not just a view of one.

That password, when set, is the entire barrier. It is not a login form with rate limiting, it is a fixed length password on a protocol that was never designed with the public internet in mind. The tradeoff was made deliberately in exchange for being able to solve a CAPTCHA, a challenge test a website presents to tell a human apart from a bot, by hand from anywhere without opening a port on the router.

---

### Related documentation

- [ascend-web-hunter_deploy/README.md](ascend-web-hunter_deploy/README.md), full prerequisites, quick start, upgrading, and the complete security notes for this stack
- [nginx_proxy_manager.md](nginx_proxy_manager.md), the `ascend-web-hunter.internal` proxy entry
- [uptime_kuma.md](uptime_kuma.md), the uptime monitor
