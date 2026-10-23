# ascend-web-hunter standalone deployment

Everything needed to run the web search and scraping stack on its own host, without the rest of the AscendAI platform. Copy this directory to the target machine, fill in three secrets, and start it.

---

### What this is

The [AscendAI](https://github.com/Lukk17/AscendAI) repository runs this stack as part of a larger platform. That development setup builds images from source, wires services into a shared observability stack, and assumes Docker Desktop on Windows.

This directory is the deployment counterpart, copied from `apps/ascend-web-hunter/deploy-standalone/` in AscendAI and changed for this homelab. It pulls a published image instead of building, drops everything that depends on services which are not here, and is written for Docker Engine on Linux. Every change against the AscendAI copy is listed under [Differences from the AscendAI bundle](#differences-from-the-ascendai-bundle).

The copy was taken on 2026-10-24 from the owner's local AscendAI branch `feature/all-openspec-groups` at commit `aa82a35`, which had removed the FlareSolverr container. On that date the `master` branch on GitHub still shipped FlareSolverr, so the bundle on GitHub can differ from this one until that branch is merged.

Three containers run:

| Container | Purpose | Reachable from |
|---|---|---|
| ascend-web-hunter | The service itself. REST API and MCP server. | Host, on port 7021, and the homelab proxy |
| searxng | Meta search engine the service queries. | Inside the stack only |
| ngrok-ascend-web-hunter | Public tunnel to the NoVNC desktop for CAPTCHA solving. | Outbound only |

The Compose project name is `ascend-scrapper`, the same name AscendAI still gives its bundle. Only the project carries the old name. Every container, the service and the image carry the hunter name.

---

### Prerequisites

| Requirement | Detail |
|---|---|
| Docker Engine | 20.10 or newer, with the Compose plugin |
| Redis | Reachable at port 6379 on the Docker host. Not part of this stack. |
| The `proxy-tier` network | Created by the homelab [compose.yaml](../compose.yaml), so that stack must be up first |
| The published image | `lukk17/ascend-ai-ascend-web-hunter:latest` must exist in the registry, see the check below |
| Free RAM | Roughly 3.0 GB free, on top of whatever the host already uses. See [Resource footprint](#resource-footprint) |
| CPU | 2 cores is enough. CPU contention costs scraping speed, not stability. |
| Free port | 7021 on the host. Nothing else is published. |
| Ngrok account | Free tier, for the CAPTCHA intervention tunnel |

Redis holds authentication cookies and Cloudflare clearance tokens between requests, so that a challenge solved once keeps working afterwards. Without it the service still runs, but every request starts from a cold session and `/ready` reports degraded.

The AscendAI bundle runs its own Redis container named `redis`. This copy does not, because the homelab [compose.yaml](../compose.yaml) already runs a container with that name and Docker allows one container per name on a host, so the bundled one would refuse to start. Where Redis lives decides what `REDIS_URL` must be. The compose file defaults to the first option below.

| Redis location | REDIS_URL | Note |
|---|---|---|
| On the Docker host (default) | `redis://host.docker.internal:6379/0` | Works because the file declares `host.docker.internal:host-gateway`. Redis must listen on an address other than loopback, since the container arrives through the bridge gateway rather than through 127.0.0.1. |
| A container on the shared `proxy-tier` network | `redis://redis:6379/0` | The homelab Redis by its container name, one hop shorter than going out to the host and back. |
| Another machine | `redis://<host>:6379/0` | Add a password to the URL if that Redis has one. |

To change it, put the line `REDIS_URL=<url>` into `.env`.

Check that the image has been published before the first start. Unix shell:

```bash
curl -s https://hub.docker.com/v2/repositories/lukk17/ascend-ai-ascend-web-hunter/tags
```

PowerShell:

```powershell
curl.exe -s https://hub.docker.com/v2/repositories/lukk17/ascend-ai-ascend-web-hunter/tags
```

The answer must list a tag named `latest`. On 2026-10-24 it answered `"count": 0` with no tag at all, and the registry answered `manifest unknown` for both `latest` and `v0.0.3`, so a pull fails until the AscendAI release workflow publishes the service under its new name. The old image, `lukk17/ascend-web-search`, is a build from 2026-08-14 that still expects FlareSolverr, so it does not fit this file.

---

### Quick start

Copy this whole directory to the host. It needs all four files, including `searxng/settings.yaml`, which SearXNG will not start without.

Create the secrets file, `.env`, with the commands below. What each value has to satisfy:

| Variable | Must be |
|---|---|
| SEARXNG_SECRET | At least 32 characters, unique to this deployment, and not the literal `ultrasecretkey`, which SearXNG rejects. Nothing ever types this by hand. |
| VNC_PASSWORD | 8 characters or fewer. The VNC protocol truncates anything longer, so only the first 8 count. See [NoVNC and CAPTCHA solving](#novnc-and-captcha-solving). |
| NGROK_AUTHTOKEN | Your account token from [the ngrok dashboard](https://dashboard.ngrok.com/get-started/your-authtoken). |

Type the VNC password. It is not shown, and the `echo` only moves to a new line afterwards. Leave out `$`, `#` and quotes, because the Docker Compose page [Interpolation](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/) says a `$` in an unquoted value of this file starts a variable name, and a space followed by `#` starts a comment:

```bash
read -r -s -p 'VNC password, 8 characters at most: ' VNC_PASSWORD; echo
```

Paste the ngrok token. It is not shown either:

```bash
read -r -s -p 'ngrok auth token: ' NGROK_AUTHTOKEN; echo
```

Write the file, from inside this directory. The SearXNG secret is made in the same step, 64 random hexadecimal characters from `openssl`, so nobody types it. The last three keys stay empty. They belong to the extraction model and the object store, which this stack does not run, and writing them empty keeps Compose from warning that they are not set:

```bash
printf 'SEARXNG_SECRET=%s\nVNC_PASSWORD=%s\nNGROK_AUTHTOKEN=%s\nEXTRACTION_LLM_API_KEY=\nOBJECT_STORE_S3_ACCESS_KEY=\nOBJECT_STORE_S3_SECRET_KEY=\n' "$(openssl rand -hex 32)" "$VNC_PASSWORD" "$NGROK_AUTHTOKEN" > .env
```

Keep it readable by you alone:

```bash
chmod 600 .env
```

Remove the two values from the shell:

```bash
unset VNC_PASSWORD NGROK_AUTHTOKEN
```

Check that no required value is empty, without printing them. This prints each name and the length of its value:

```bash
awk -F= '{print $1, length($2)}' .env
```

`SEARXNG_SECRET` must show 64, `VNC_PASSWORD` a number from 1 to 8, and `NGROK_AUTHTOKEN` a number above 0. The last three show 0.

Start the stack.

```bash
docker compose up -d
```

All three secrets are required. Compose refuses to start and names the missing variable if any is blank, so a typo fails immediately instead of producing a half working stack.

---

### Verifying it works

SearXNG must report healthy before ascend-web-hunter is allowed to start, which takes about 30 seconds from cold.

Watch the status until all three are up and two show healthy. The ngrok container has no healthcheck.

```bash
docker compose ps
```

Then ask the service itself. The readiness endpoint probes Redis and SearXNG and reports each one separately.

```bash
curl -s http://localhost:7021/ready
```

A healthy response has `"status": "ready"` and every check reading `ok`. Anything reading `error` names the dependency that is not working. Redis showing `error` is the usual first failure and means the container cannot reach Redis on the host, see [Prerequisites](#prerequisites).

Run a real search to confirm the whole chain works end to end.

```bash
curl -s "http://localhost:7021/api/v1/web/search?query=test"
```

The interactive API documentation at [http://localhost:7021/docs](http://localhost:7021/docs) lists every endpoint, including the page reading and session management routes.

---

### Configuration

Three secrets live in `.env`, and any optional setting you change goes there too. Everything else is set directly in `compose.yaml`, because it is configuration rather than credentials and belongs in version control where changes are visible.

| Variable | Required | What it does |
|---|---|---|
| SEARXNG_SECRET | Yes | SearXNG session signing key. Read by SearXNG from the environment, which is why `searxng/settings.yaml` has no `secret_key` entry. Generate a fresh one per deployment. |
| VNC_PASSWORD | Yes | Password for the NoVNC desktop. Turned into an encrypted x11vnc password file at container start. |
| NGROK_AUTHTOKEN | Yes | Authenticates the ngrok tunnel. |
| REDIS_URL | No | Where the cookie and session cache lives. Defaults to `redis://host.docker.internal:6379/0`, see [Prerequisites](#prerequisites). |
| WEB_HUNTER_MCP_ALLOWED_HOST_HEADERS | No | Host names the `/mcp` endpoint accepts in the Host header. Defaults to `ascend-web-hunter,ascend-web-hunter.internal,localhost,127.0.0.1`, see [The MCP endpoint and host names](#the-mcp-endpoint-and-host-names). |
| WEB_HUNTER_API_PORT | No | Port the service listens on inside the container. Default `7021`. |
| WEB_HUNTER_HOST_PORT | No | Port published on the host. Default `7021`. |

Every other optional setting is listed with its default and a one line description in [.env.example](.env.example), and each is passed through the `environment:` block of the ascend-web-hunter service in `compose.yaml`. The full reference is [configuration.md](https://github.com/Lukk17/AscendAI/blob/master/apps/ascend-web-hunter/docs/configuration.md) in AscendAI.

Two groups of those settings point at services this stack does not run. The PDF, image and audio routes call `docling-serve`, `ascend-ocr` and `ascend-audio-scribe`, and crawl results go to an S3 compatible object store at `host.docker.internal:9070`. Search, page reading and CAPTCHA intervention do not need any of them.

---

### The MCP endpoint and host names

The `/mcp` endpoint accepts a request only when its Host header is one of the names in `MCP_ALLOWED_HOST_HEADERS`. Any other name gets `421 Misdirected Request`. The port in the header is ignored when comparing. This is FastMCP's host check, which the service turns on with that list.

Nginx Proxy Manager passes the browser's Host header through unchanged, so a client that reaches the service as `http://ascend-web-hunter.internal/mcp` sends `ascend-web-hunter.internal`. AscendAI's default list does not hold that name, so this copy adds it. A client that uses the VM address directly, `http://<docker-vm-ip>:7021/mcp`, sends that address and is refused until you add it:

```bash
echo 'WEB_HUNTER_MCP_ALLOWED_HOST_HEADERS=ascend-web-hunter,ascend-web-hunter.internal,<docker-vm-ip>,localhost,127.0.0.1' >> .env
```

Then recreate the container so it reads the new value:

```bash
docker compose up -d ascend-web-hunter
```

The REST API under `/api/v1` has no such check.

---

### NoVNC and CAPTCHA solving

When the extraction chain hits a CAPTCHA it cannot clear on its own, it escalates to a real browser running inside the container on a virtual X server, and returns HTTP 428 to the caller. You then open that browser in your own browser, through the ngrok tunnel, solve the CAPTCHA by hand, and the cookies are captured and reused.

Find the current tunnel address. Ngrok generates a new one every time the container restarts.

```bash
docker exec ngrok-ascend-web-hunter curl -s http://localhost:4040/api/tunnels
```

Opening that address prompts for the VNC password from `.env`.

Two things to understand about this. The VNC protocol truncates passwords at 8 characters, so anything longer is silently cut and the extra characters do nothing. And the tunnel is a public internet address for as long as the container runs, protected only by that 8 character password. If you do not need interactive CAPTCHA solving, the safest configuration is to not run the tunnel at all.

```bash
docker compose up -d --scale ngrok-ascend-web-hunter=0
```

---

### What does not work here, and why

Telemetry. In the full platform this service exports traces over OTLP to an OpenTelemetry collector, which feeds Tempo for traces and Grafana for viewing. None of that is in this stack, so the three `OTEL_` variables are not set here.

This is not a degraded mode. The service reads `OTEL_EXPORTER_OTLP_ENDPOINT` once at startup and, finding it unset, never starts OpenTelemetry at all. Nothing retries, nothing logs errors, nothing waits. The application works fully without it.

To get traces back you would need a collector accepting OTLP over gRPC on port 4317, plus somewhere to store and view what it collects. The working configuration for all of that is in the AscendAI repository root: the `otel-collector`, `tempo` and `grafana` services in `compose.yaml`, with their config files under `infra/observability/`. Add them here, then set `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SERVICE_NAME` and `OTEL_RESOURCE_ATTRIBUTES` on the ascend-web-hunter service.

Metrics are a separate matter. The service exposes Prometheus metrics on its own HTTP port whether or not OpenTelemetry is configured, so any Prometheus that can reach port 7021 can scrape them without adding anything to this stack.

---

### Resource footprint

Every container has a hard memory and CPU ceiling. Without one, a single hostile page can drive Chromium's memory up until the kernel starts killing processes, and the kernel does not necessarily kill the container that caused it. It might kill Redis, or the SSH daemon. With a ceiling the damage stays inside the offending container, which then restarts on its own.

The shipped numbers are sized for an 8 GB host that is already running other things, which is the case this bundle was written for.

| Container | CPU limit | Memory limit | CPU reserved | Memory reserved |
|---|---|---|---|---|
| ascend-web-hunter | 1.5 | 2560M | 0.25 | 512M |
| searxng | 0.5 | 384M | 0.1 | 128M |
| ngrok-ascend-web-hunter | 0.25 | 96M | 0.05 | 32M |

Memory ceilings total 3.0 GB. Reservations, which is what the stack actually holds at rest, total about 0.7 GB and 0.4 CPU.

Do the arithmetic before deploying. Take the host's total RAM, subtract what it already uses, and the remainder must exceed 3.0 GB with something left over for page cache. On an 8 GB host already using 2.3 GB, that leaves 5.7 GB free, the stack can claim at most 3.0 GB of it, and about 2.7 GB stays spare. On a 4 GB host these numbers do not fit and the stack will start killing containers under load.

Two things interact and are easy to miss.

Shared memory counts against the limit. The ascend-web-hunter container gets a 1 GB `/dev/shm` because Chromium crashes on Docker's 64 MB default. Those pages are charged to the container's memory cgroup, so of its 2560M ceiling, up to 1 GB can be shared memory. Raise `shm_size` and you must raise the memory limit with it, or you have quietly halved the working set.

CPU limits above the core count mean nothing. On a 2 core host a container cannot exceed 2.0 no matter what the file says. The numbers above assume 2 cores. On a larger machine you can raise them, but CPU is the harmless constraint: contention makes scraping slower, it does not kill anything.

To scale up on a bigger host, raise ascend-web-hunter first, since that is where Chromium runs, and raise `shm_size` alongside it.

---

### Logs

Container logs are capped at 10 MB per file with 3 files kept, so 30 MB per container and 90 MB for the stack, permanently. Docker rotates at the size limit and deletes the oldest file, with no maintenance needed.

Read them the usual way.

```bash
docker compose logs -f ascend-web-hunter
```

There is no log collection in this stack. The Loki and Grafana setup used in development is part of the platform's observability stack, covered under [What does not work here, and why](#what-does-not-work-here-and-why).

---

### Upgrading

The ascend-web-hunter image tracks `latest`, so this deployment follows the newest published build of the service without editing the file. The other two images, SearXNG and ngrok, are pinned, because they are other people's builds and a change there is a change nobody here chose.

A floating tag does not make the upgrade happen on its own, and this is the part that catches people out. `restart: unless-stopped` restarts the existing container from the image already on the host, and a plain `docker compose up -d` pulls only when no local image carries that tag. Both of those leave the old build running for as long as an image tagged `latest` exists locally, however new the published one is. Moving to a newer build takes an explicit pull first, then a recreate.

The two commands are identical in both shells, because `docker compose` takes the same arguments everywhere.

Unix shell:

```bash
docker compose pull ascend-web-hunter
```

```bash
docker compose up -d ascend-web-hunter
```

PowerShell:

```powershell
docker compose pull ascend-web-hunter
```

```powershell
docker compose up -d ascend-web-hunter
```

The pull rewrites what `latest` points at locally, and the recreate is what swaps the running container onto it. Naming the service keeps both commands off the other two containers, which stay untouched.

To go back to a build you know worked, put the exact tag of that build on the `image:` line, run the same pull and recreate, and set the line back to `latest` once the newer build is fixed. Unix shell, from inside this directory:

```bash
sed -i 's|^\([[:space:]]*image: lukk17/ascend-ai-ascend-web-hunter:\).*|\1<tag>|' compose.yaml
```

PowerShell, from inside this directory. It reads and writes the file as UTF-8 through .NET rather than with `Get-Content` and `Set-Content`, so the box drawing characters in its comments come through Windows PowerShell 5.1 unchanged:

```powershell
$f = (Resolve-Path compose.yaml).Path; [IO.File]::WriteAllText($f, ([IO.File]::ReadAllText($f) -replace '(image: lukk17/ascend-ai-ascend-web-hunter:)\S+', '${1}<tag>'))
```

Check it. The line must show the tag you chose:

```bash
grep -n 'image: lukk17/ascend-ai-ascend-web-hunter' compose.yaml
```

```powershell
Select-String -Path compose.yaml -Pattern 'image: lukk17/ascend-ai-ascend-web-hunter'
```

To set the line back, run the same command with `latest` in place of `<tag>`. Published tags are listed at [hub.docker.com/r/lukk17/ascend-ai-ascend-web-hunter/tags](https://hub.docker.com/r/lukk17/ascend-ai-ascend-web-hunter/tags). The AscendAI release workflow pushes the same tags to `ghcr.io/lukk17/ascend-ai-ascend-web-hunter`. Docker Hub needs no login to pull. A GitHub registry package starts private and stays so until the owner makes it public once by hand, and on 2026-10-24 an anonymous request for this one was refused.

Upstream images move on their own schedule and need their tag edited by hand. SearXNG ships a new build most days and its search engines break as the sites they scrape change, so it is worth bumping every few months even when nothing appears wrong.

---

### Security notes

The service has no authentication. Anything that can reach port 7021 can make it fetch arbitrary URLs. That is fine on a trusted network and not fine on an untrusted one. If the host is exposed beyond your own network, put it behind a reverse proxy with authentication rather than publishing the port directly.

SearXNG publishes no ports at all here. It is reachable only from inside the stack.

The container runs with the `SYS_ADMIN` capability, which Chromium's sandbox needs. It renders untrusted web content with an elevated capability, which is worth knowing even though it is the standard way to run a browser in a container.

---

### Differences from the AscendAI bundle

Everything below is a deliberate difference from `apps/ascend-web-hunter/deploy-standalone/` in AscendAI. Anything not on this list should be identical in both copies.

| Topic | AscendAI bundle | This copy |
|---|---|---|
| ascend-web-hunter image tag | Pinned to `v0.0.3` | `latest`, see [Upgrading](#upgrading) |
| redis service | Runs a container named `redis` with a `redisdata` volume | Absent. The homelab already runs a container named `redis`, see [Prerequisites](#prerequisites) |
| REDIS_URL default | `redis://redis:6379/0`, the bundled Redis | `redis://host.docker.internal:6379/0`, the homelab Redis on the Docker host |
| ascend-web-hunter `depends_on` | searxng and redis | searxng only |
| `proxy-tier` network | Absent | ascend-web-hunter joins it, so Nginx Proxy Manager reaches it by container name |
| MCP_ALLOWED_HOST_HEADERS default | `ascend-web-hunter,localhost,127.0.0.1` | Adds `ascend-web-hunter.internal`, the proxy name |
| SearXNG settings file | `searxng/settings.yml` | `searxng/settings.yaml`, because this repository names YAML files `.yaml`. The container path stays `/etc/searxng/settings.yml` |
| `.env` | Copied from `.env.example` | Written by the commands in [Quick start](#quick-start) |

---

### Keeping this directory in sync

`searxng/settings.yaml` here is a byte identical copy of `apps/ascend-web-hunter/deploy-standalone/searxng/settings.yml` in AscendAI, so a diff is the whole check. With both repositories cloned side by side under `~/Projects`, from inside this directory:

```bash
diff searxng/settings.yaml ~/Projects/AscendAI/apps/ascend-web-hunter/deploy-standalone/searxng/settings.yml
```

That command printing nothing means they match.

The same applies to environment variables. When AscendAI adds one to its bundle, add it to `compose.yaml` and `.env.example` here as well, and to the table under [Configuration](#configuration) if it is required.

---

### Related documentation

- [ascend_web_hunter.md](../ascend_web_hunter.md), how this stack fits into the homelab
- [ascend-web-hunter README](https://github.com/Lukk17/AscendAI/blob/master/apps/ascend-web-hunter/README.md) in AscendAI, what the service does and how it is built
- [Configuration reference](https://github.com/Lukk17/AscendAI/blob/master/apps/ascend-web-hunter/docs/configuration.md) in AscendAI, every setting the service accepts
- [Running locally](https://github.com/Lukk17/AscendAI/blob/master/apps/ascend-web-hunter/docs/running.md) in AscendAI, development without containers
- [Platform deployment guide](https://github.com/Lukk17/AscendAI/blob/master/docs/DEPLOYMENT.md) in AscendAI, the full AscendAI stack
