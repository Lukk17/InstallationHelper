# Local Development Databases and Services

> Docker Compose stack of local backing services: relational and document databases, a cache, a vector store, object storage and an identity provider. Spin up, point your app at it, tear down.

---

### Services

---

| Service | Address | Database / Realm | Username | Password | Image |
| ------- | ------- | ---------------- | -------- | -------- | ----- |
| MySQL | `mysql://root:local@localhost:3306/test-spring` | `test-spring` | `root` | `local` | `mysql:9.7.2` |
| PostgreSQL | `postgresql://postgres:local@localhost:5432/postgres` | `keycloak`, `postgres` | `postgres` | `local` | custom, built from `postgres:17.11`. See [postgresql/](./postgresql/README.md). |
| MongoDB | `mongodb://localhost:27017/articles` | none, see below | (none) | (none) | `mongo:8.3.8` |
| Qdrant | dashboard at [http://localhost:6333/dashboard](http://localhost:6333/dashboard), REST API on the same port, gRPC on `localhost:6334` | collections, also reachable on the Compose network as `mem0_store` | (none) | (none) | `qdrant/qdrant:v1.19` |
| Redis | `redis://localhost:6379/0` | numbered databases `0` to `15` | (none) | (none) | `redis:8.10.1-alpine` |
| Keycloak | admin console at [https://keycloak.test:9443/admin/](https://keycloak.test:9443/admin/), health at [https://localhost:9000/health/ready](https://localhost:9000/health/ready) | realm `local` | `admin` | `admin` | custom, built from `keycloak:26.5`. See [auth/Keycloak/](./auth/Keycloak/README.md). |
| Floci | S3 endpoint at `http://localhost:9070`, health at [http://localhost:9070/_floci/health](http://localhost:9070/_floci/health) | S3 buckets | `admin` | `password` | `floci/floci:2.0.1` |
| Floci UI | console at [http://localhost:9071](http://localhost:9071) | fifteen Amazon service pages | (none) | (none) | `floci/floci-ui:0.4.0` |

Nothing on that list answers until the containers are running, which is [Start the stack](#start-the-stack), the next section.

Every address is written against `localhost`, so seven of the eight need nothing configured. Keycloak is the exception: it redirects to its own configured hostname, so `https://localhost:9443/` sends the browser to `https://keycloak.test:9443/admin/`, and that name resolves only once the line from [Hosts file](#hosts-file) is in place.

Keycloak serves HTTPS with a certificate from the local authority, so a browser warns about it until that authority is imported. Clicking through the warning is enough for local work, and [auth/README.md](./auth/README.md) covers importing it if you would rather not.

The Image column gives the tag only, because a `sha256` digest is 71 characters and would make this table unreadable.
Every image pulled from a registry is written in the Compose file as `name:tag@sha256:...`, and the digest is what
actually resolves. The two custom images are built here and never pushed, so they keep a plain tag and it is their base
images that carry digests. See [Refreshing an image pin](#refreshing-an-image-pin) before changing a version.

Redis is the one service here with no volume, so everything in it is gone the moment the container is removed. Treat it
as a cache, not as storage.

MongoDB starts empty and creates a database the first time something writes to it, so there is nothing to set up and
no name to configure. A freshly initialised server reports only its own `admin`, `config` and `local` databases, and
an application pointed at `mongodb://localhost:27017/articles` gets `articles` on its first insert. This table used to
name `articles` here and the Compose file used to set `MONGO_INITDB_DATABASE: articles`, which never created anything:
the official image runs its initialisation phase only when a root username and password are both set or a shell or
JavaScript file is mounted into `/docker-entrypoint-initdb.d`, and neither is true here.

PostgreSQL also initialises a `keycloak` user (password `local`) and an empty `keycloak` database, and that empty
database is everything it knows about Keycloak. The realm arrives from the other side. The Keycloak image carries
[auth/Keycloak/export/config/local-realm-export.json](./auth/Keycloak/export/config/local-realm-export.json) at
`/opt/keycloak/data/import/` and its entrypoint passes `--import-realm`, so Keycloak creates its own schema and
imports the realm on first boot. It used to be the other way round, with a 302 kilobyte SQL dump of Keycloak's own
tables baked into the Postgres image, which tied one image to the other and tied the realm to a schema that changes
between Keycloak versions.

Keycloak's management endpoints sit on port `9000` rather than on `9443`. The readiness probe in the table is one of them, and `/health`, `/metrics` and the rest are beside it on the same port.

The `admin` / `admin` in that table is set by `KC_BOOTSTRAP_ADMIN_USERNAME` and `KC_BOOTSTRAP_ADMIN_PASSWORD` on the `keycloak` service in [local-dev-docker-compose.yaml](./local-dev-docker-compose.yaml), and Keycloak reads that pair only while it creates its `master` realm, which is the first start against a database holding no administrator. It therefore covers a fresh machine and changes nothing on a machine whose `keycloak` database already has an administrator, where that account keeps the password it already has. Getting in there means creating a temporary administrator with Keycloak's own `bootstrap-admin` command inside the running container, which is in [auth/Keycloak/README.md](./auth/Keycloak/README.md) under "Admin account".

Test user in the `local` realm: `lukk` / `test1234`.

### Start the stack

---

Run from the project root.

```bash
docker compose -f ./local-dev/local-dev-docker-compose.yaml up -d
```

```powershell
docker compose -f ./local-dev/local-dev-docker-compose.yaml up -d
```

Stop with the same command and `down`:

```bash
docker compose -f ./local-dev/local-dev-docker-compose.yaml down
```

```powershell
docker compose -f ./local-dev/local-dev-docker-compose.yaml down
```

The command itself is identical on Windows, Ubuntu, Arch Linux and macOS, forward slashes included, which is why it is
written once per shell rather than once per operating system. It is written as `docker compose`, two words, because
that is the Compose v2 subcommand built into the Docker command line and it is the only spelling that is there on
every platform. The hyphenated `docker-compose` is a separate program and is not: Docker Desktop still installs it on
Windows and inside WSL, and Arch's `docker-compose` package installs both spellings, but on Ubuntu 24.04 the package
called `docker-compose` is version 1.29.2, the retired Python implementation, and on that release it does not start at
all:

```text
ModuleNotFoundError: No module named 'distutils'
```

That failure was measured in an `ubuntu:24.04` container after installing the `docker-compose` package. On a release
where it does start, it still could not read this file, because the top-level `name:` key and `build.tags` are Compose
v2 additions, and that half is reasoning rather than measurement. Ubuntu packages Compose v2 as `docker-compose-v2`.

### Hosts file

---

One name in this stack resolves to the loopback address, and nothing sets it up for you. This is the only place it is
listed, so there is no second file to check.

```text
127.0.0.1 keycloak.test
```

| Name | What it is for |
| ---- | -------------- |
| `keycloak.test` | The canonical Keycloak name and the issuer in every token it mints. Point applications, browsers and HTTP clients here. |

Every other address in this stack is written against `localhost`, which needs nothing configured. The bare `keycloak`
name used to have a line here too and no longer does: it is the container name, so Docker's embedded resolver answers
it inside the Compose network whether or not any hosts file mentions it, which is why the Compose healthcheck reaches
`https://keycloak:9000/health/ready` and works. Nothing on the machine itself needs that name, because every documented
command points at `keycloak.test` instead.

The file's contents are the same everywhere, only its path and the privilege needed to write it differ.

| Platform | Path | How to edit it |
| -------- | ---- | -------------- |
| Ubuntu, Debian, Arch Linux, macOS | `/etc/hosts` | any editor under `sudo` |
| Windows | `C:\Windows\System32\drivers\etc\hosts` | an editor started as Administrator |

Why `keycloak.test` rather than `localhost`, and why it is not interchangeable with the bare `keycloak` container
name, is in [auth/README.md](./auth/README.md).

### Object storage

---

[Floci](https://github.com/floci-io/floci) emulates the Amazon Web Services interfaces and serves all of them from one gateway port. Only S3 is used here. It took over from MinIO because MinIO's community repository is archived, so the tag that was pinned in the Compose file is the last image Docker Hub will ever serve for it. The host port stayed `9070`, so anything already pointing at the old S3 endpoint keeps working without an edit.

[Floci UI](https://github.com/floci-io/floci-ui) is the browser side: Floci's own console, holding port `9071` after
s3manager, which held it after the MinIO console. It talks to Floci over the Compose network at `floci:4566` and starts
only once Floci reports healthy. It is MIT licensed, like Floci itself.

Floci can start that console for you, and this stack deliberately does not let it. Left to itself the gateway reaches
the host's Docker daemon to launch the console container, which is why `/_floci/ui` on a stock setup fails with
`java.net.SocketException: No such file or directory` and why the usual fix is to mount the Docker socket into the
container. Do not. A container holding that socket has root-equivalent control of the whole machine, and the console
does not need it: it is an ordinary web server that speaks the S3 wire protocol to the gateway over the Compose
network, so running it as its own service costs nothing and mounts nothing. `FLOCI_SERVICES_UI_ENABLED` is set to
`false` on the `floci` service so the gateway stops trying, and `/_floci/ui` then answers with a plain
`Floci UI unavailable` and the line `The Floci UI is disabled (set floci.services.ui.enabled=true to enable it).`
Neither container has any mount other than the `floci_data` volume, which `docker inspect` will confirm.

Both ports are plain HTTP. A TLS handshake against either is refused outright, measured as `curl` exit 35 on 9070 and
on 9071, so no certificate is involved anywhere here and none of the trust store work under
[auth/](./auth/README.md) applies to object storage.

Point an application at these values:

| Setting | Value |
| ------- | ----- |
| Endpoint | `http://localhost:9070` |
| Region | `us-east-1` |
| Access key id | `admin` |
| Secret access key | `password` |
| Path style addressing | works, `http://localhost:9070/<bucket>/<key>` |
| Virtual hosted addressing | works, `http://<bucket>.localhost:9070/<key>` |

Both addressing styles were exercised against the running container, so a client library that insists on one or the other is fine either way. Any subdomain of `localhost` resolves to the loopback with nothing configured, measured on both Windows and Ubuntu, which is what makes the virtual hosted style work here without a single line of setup.

The AWS command line interface is not a prerequisite. `curl` signs Signature Version 4 requests on its own, which is enough to create a bucket and move objects around.

Create a bucket:

```bash
curl -X PUT "http://localhost:9070/local-dev-bucket" --aws-sigv4 "aws:amz:us-east-1:s3" --user "admin:password"
```

```powershell
curl.exe -X PUT "http://localhost:9070/local-dev-bucket" --aws-sigv4 "aws:amz:us-east-1:s3" --user "admin:password"
```

Upload a file into it:

```bash
curl -X PUT --upload-file ./first.txt "http://localhost:9070/local-dev-bucket/first.txt" --aws-sigv4 "aws:amz:us-east-1:s3" --user "admin:password"
```

```powershell
curl.exe -X PUT --upload-file ./first.txt "http://localhost:9070/local-dev-bucket/first.txt" --aws-sigv4 "aws:amz:us-east-1:s3" --user "admin:password"
```

List what is in it:

```bash
curl "http://localhost:9070/local-dev-bucket?list-type=2" --aws-sigv4 "aws:amz:us-east-1:s3" --user "admin:password"
```

```powershell
curl.exe "http://localhost:9070/local-dev-bucket?list-type=2" --aws-sigv4 "aws:amz:us-east-1:s3" --user "admin:password"
```

The six commands above were run verbatim against the running stack from Git Bash on Windows. They need no hosts entry
and no AWS command line interface.

For clicking around instead, open [http://localhost:9071](http://localhost:9071) in a browser. Under Storage it lists
the buckets and the objects inside them. Everything it shows comes from its own backend, which reads the gateway over
the Compose network: `/api/clouds/aws/services/storage/resources` returns the buckets and
`/api/clouds/aws/services/storage/resources/<bucket>/objects` returns the keys inside one. Those two are worth knowing
because the page itself is rendered in the browser, so `curl` against the root gets an empty shell rather than a bucket
list.

Storage is one of fifteen pages the console lists under AWS, all of which report themselves available. Ask each one for its resources and eleven answer `200` with an empty list. Of the four that hand anything back, only Storage shows something this stack made, and the other three carry a single stock item each: a fake machine image under Compute, the default virtual private cloud under Networking, and the default event bus under EventBridge. Two different reasons sit behind the emptiness. Nothing in this stack creates a queue, a function, a database or a secret in the first place, so there is nothing for those pages to list. And the emulators behind several of them, Lambda, ECS, EKS, RDS and ElastiCache among others, want the host Docker daemon that this stack refuses to hand over for the reason given further up, so those pages stay empty however you click. Available describes the page existing and the gateway answering, not the emulator behind it doing any work.

The console also offers Azure and GCP alongside AWS, and both are dead ends in this stack. They are separate emulators
with their own images, [floci-az](https://github.com/floci-io/floci-az) on port `4577` and
[floci-gcp](https://github.com/floci-io/floci-gcp) on port `4588`, and neither runs here. Asking the console for either
returns `"runtime":"unavailable"` with a connection error naming the port. Only AWS reports `"runtime":"reachable"`.

The console's healthcheck probes `/api/clouds` rather than `/` for the same reason. The root answers `200` with a
1487-byte static bundle no matter what state the backend is in, and so does every path the router does not recognise,
so a probe against `/` would report healthy on a console whose API was dead. `/api/clouds` is a real backend route and
answers `application/json`. It runs under BusyBox `wget` because the image ships no `curl`.

Objects live in the `floci_data` named volume, mounted at `/app/data` because `FLOCI_STORAGE_MODE` is set to `persistent`. A `docker restart floci` keeps them, and so does destroying the container and recreating it from the Compose file. Both were verified. What does remove them is `docker compose down -v`, which deletes the volume along with every other volume in the stack.

Health lives at [http://localhost:9070/_floci/health](http://localhost:9070/_floci/health) and answers with a JSON map of every emulated service. Two behaviours differ from MinIO and will bite if you assume otherwise.

Floci implements no MinIO admin interface. The old `http://localhost:9070/minio/health/live` path answers `404`, and any tool built on MinIO's admin API, `mc` included, has nothing to talk to here.

Nothing on either port asks for a credential. The console on `9071` ships no authentication at all, so whoever reaches that page can read, write and delete in every bucket. That was measured rather than assumed: a `DELETE` to its own backend carrying no credential of any kind removed an object and answered `{"ok":true}`. The Floci gateway on `9070` is no better: it accepts a wrong secret key, a wrong region, and requests carrying no signature whatsoever, all with the same `200`. A plain unsigned `PUT` and a plain unsigned `DELETE` both succeeded during testing. The credentials above exist so that client libraries which demand a key have one to send, not because anything checks them. The MinIO service this replaced was configured with a root user and password, so the same values now buy you nothing. Both ports are published on `0.0.0.0`, so this is open to your whole network segment, not only to the machine. Keep real data out of it, and bind the ports to `127.0.0.1` in the Compose file if the machine sits on a network you do not control.

### Configuration deep-dives

---

| Doc                                                          | What's in it                                                            |
| ------------------------------------------------------------ | ----------------------------------------------------------------------- |
| [auth/Keycloak/config.md](./auth/Keycloak/config.md)         | First run, realm and client setup by hand, and regenerating the realm export the image imports. |
| [auth/Keycloak/README.md](./auth/Keycloak/README.md)         | Dockerfile, token curl, OS trust store import for the certificate authority. |
| [auth/README.md](./auth/README.md)                           | Local certificate authority generation, trust store setup per platform, Let's Encrypt for prod. |
| [postgresql/README.md](./postgresql/README.md)               | Standalone Postgres run, credentials.                                   |

### Refreshing an image pin

---

Every image that comes from a registry is written as `name:tag@sha256:...`, in
[local-dev-docker-compose.yaml](./local-dev-docker-compose.yaml) and in the `FROM` lines of
[postgresql/Dockerfile](./postgresql/Dockerfile) and [auth/Keycloak/Dockerfile](./auth/Keycloak/Dockerfile) alike. The
tag is there so a person reading the file can see which version it is, the digest is what Docker actually resolves. A
tag that moves upstream, or that gets rebuilt under the same name, therefore cannot change what starts here.

The cost is that a version bump is two edits rather than one: change the tag, then replace the digest with the one that
new tag points at. A stale digest wins over a fresh tag, so half the edit gives you the old image under a new label.

Pull the tag you want, then read its digest back:

```bash
docker pull mysql:9.7.2
```

```bash
docker image inspect --format '{{index .RepoDigests 0}}' mysql:9.7.2
```

```powershell
docker pull mysql:9.7.2
```

```powershell
docker image inspect --format "{{index .RepoDigests 0}}" mysql:9.7.2
```

That prints `mysql@sha256:<digest>`. Paste the digest after the tag, so the line reads `mysql:9.7.2@sha256:<digest>`,
and confirm the file still parses:

```bash
docker compose -f ./local-dev/local-dev-docker-compose.yaml config
```

```powershell
docker compose -f ./local-dev/local-dev-docker-compose.yaml config
```

For a repository that publishes several architectures, `RepoDigests` gives the digest of the manifest index rather than
of one platform's image, so the pin still resolves on an arm64 machine as well as on amd64. Every registry image in
this stack is pinned that way today. `cloudlena/s3manager` used to be the exception, because upstream shipped `v0.8.0`
as a single `linux/amd64` manifest with no index above it, and it left the stack when Floci's own console replaced it.

`postgres-local:latest` and `keycloak-local:latest` are built on this machine and never pushed anywhere, so they have no
registry digest and keep a plain tag. Their base images inside the two Dockerfiles carry the digests instead.

The links below go to the upstream tag listings, for picking the tag in the first place.

- [MySQL](https://hub.docker.com/_/mysql/tags)
- [PostgreSQL](https://hub.docker.com/_/postgres/tags)
- [MongoDB](https://hub.docker.com/_/mongo/tags)
- [Qdrant](https://hub.docker.com/r/qdrant/qdrant/tags)
- [Redis](https://hub.docker.com/_/redis/tags)
- [Keycloak](https://hub.docker.com/r/keycloak/keycloak/tags)
- [Floci](https://hub.docker.com/r/floci/floci/tags)
- [Floci UI](https://hub.docker.com/r/floci/floci-ui/tags)
