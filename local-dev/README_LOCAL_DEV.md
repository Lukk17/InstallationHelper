# Local Development Databases and Services

> Docker Compose stack with MySQL, PostgreSQL, MongoDB, and Keycloak (HTTPS). Spin up, point your app at it, tear down.

---

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

Three names in this stack resolve to the loopback address, and nothing sets them up for you. Add all three in one
edit. This is the only place they are listed, so there is no second file to check.

```text
127.0.0.1 keycloak.test
127.0.0.1 keycloak
127.0.0.1 s3.test
```

| Name | What it is for |
| ---- | -------------- |
| `keycloak.test` | The canonical Keycloak name and the issuer in every token it mints. Point applications, browsers and HTTP clients here. |
| `keycloak` | The container name. Docker's own resolver answers it inside the Compose network, and this line makes the same name answer from the machine as well. |
| `s3.test` | The object store, on both of its ports: `http://s3.test:9070` is the S3 endpoint and `http://s3.test:9071` is the s3manager browser. |

The file's contents are the same everywhere, only its path and the privilege needed to write it differ.

| Platform | Path | How to edit it |
| -------- | ---- | -------------- |
| Ubuntu, Debian, Arch Linux, macOS | `/etc/hosts` | any editor under `sudo` |
| Windows | `C:\Windows\System32\drivers\etc\hosts` | an editor started as Administrator |

Why `keycloak.test` rather than `localhost`, and why the two Keycloak names are not interchangeable, is in
[auth/README.md](./auth/README.md).

### Services

---

| Service     | Port              | Database / Realm       | Username    | Password    | Image                                                                          |
| ----------- | ----------------- | ---------------------- | ----------- | ----------- | ------------------------------------------------------------------------------ |
| MySQL       | `3306`            | `test-spring`          | `root`      | `local`     | `mysql:9.7.2`                                                                  |
| PostgreSQL  | `5432`            | `keycloak`, `postgres` | `postgres`  | `local`     | custom, built from `postgres:17.11`. See [postgresql/](./postgresql/README.md). |
| MongoDB     | `27017`           | none, see below        | (none)      | (none)      | `mongo:8.3.8`                                                                  |
| Qdrant      | `6333` (HTTP), `6334` (gRPC) | collections, also reachable on the Compose network as `mem0_store` | (none) | (none) | `qdrant/qdrant:v1.19`                                       |
| Redis       | `6379`            | numbered databases `0` to `15` | (none) | (none)      | `redis:8.10.1-alpine`                                                          |
| Keycloak    | `9443` (HTTPS)    | realm `local`          | `admin`     | `admin`     | custom, built from `keycloak:26.5`. See [auth/Keycloak/](./auth/Keycloak/README.md). |
| Floci       | `9070`            | S3 buckets             | `admin`     | `password`  | `floci/floci:2.0.1`                                                            |
| s3manager   | `9071`            | browses Floci          | (none)      | (none)      | `cloudlena/s3manager:v0.8.0`                                                   |

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

PostgreSQL also initialises a `keycloak` user (password `local`) and imports the seed dump from
[auth/Keycloak/export/database/keycloak-dump.sql](./auth/Keycloak/export/database/keycloak-dump.sql) so Keycloak boots
with the realm already in place.

Keycloak's management port is `9000`. URLs:

- HTTPS app: `https://localhost:9443` or `https://keycloak.test:9443` (hosts entry needed; see
  [Hosts file](#hosts-file))
- Management: `https://localhost:9000/health`, `/metrics`, etc.

Test user in the `local` realm: `lukk` / `test1234`.

### Object storage

---

[Floci](https://github.com/floci-io/floci) emulates the Amazon Web Services interfaces and serves all of them from one gateway port. Only S3 is used here. It took over from MinIO because MinIO's community repository is archived, so the tag that was pinned in the Compose file is the last image Docker Hub will ever serve for it. The host port stayed `9070`, so anything already pointing at the old S3 endpoint keeps working without an edit.

[s3manager](https://github.com/cloudlena/s3manager) is the browser side: a bucket and object browser that took over port `9071` from the MinIO console. It talks to Floci over the Compose network at `floci:4566` and starts only once Floci reports healthy.

Both ports answer to `s3.test` as well as to `localhost`, once the hosts line from
[Hosts file](#hosts-file) is in place. One name covers both: `http://s3.test:9070` is the endpoint and
`http://s3.test:9071` is the browser. It exists for the same reason `keycloak.test` does, which is that a name you
configure an application against should not be the same word every other service on the machine also answers to. There
is no certificate anywhere in this: both ports are plain HTTP, and a TLS handshake against either of them is refused
outright, measured as `curl` exit 35 on 9070 and on 9071. So `s3.test` needs no entry in any certificate and none of
the trust store work under [auth/](./auth/README.md) applies to it.

Point an application at these values:

| Setting | Value |
| ------- | ----- |
| Endpoint | `http://s3.test:9070`, or `http://localhost:9070` with no hosts entry |
| Region | `us-east-1` |
| Access key id | `admin` |
| Secret access key | `password` |
| Path style addressing | works, `http://s3.test:9070/<bucket>/<key>` |
| Virtual hosted addressing | works, `http://<bucket>.localhost:9070/<key>` |

Both addressing styles were exercised against the running container, so a client library that insists on one or the other is fine either way. Prefer `localhost` for the virtual hosted style. Any subdomain of `localhost` resolves to the loopback with nothing configured, measured on both Windows and Ubuntu, whereas a hosts file cannot hold a wildcard, so every bucket under `s3.test` would need a line of its own.

The AWS command line interface is not a prerequisite. `curl` signs Signature Version 4 requests on its own, which is enough to create a bucket and move objects around.

Create a bucket:

```bash
curl -X PUT "http://s3.test:9070/local-dev-bucket" --aws-sigv4 "aws:amz:us-east-1:s3" --user "admin:password"
```

```powershell
curl.exe -X PUT "http://s3.test:9070/local-dev-bucket" --aws-sigv4 "aws:amz:us-east-1:s3" --user "admin:password"
```

Upload a file into it:

```bash
curl -X PUT --upload-file ./first.txt "http://s3.test:9070/local-dev-bucket/first.txt" --aws-sigv4 "aws:amz:us-east-1:s3" --user "admin:password"
```

```powershell
curl.exe -X PUT --upload-file ./first.txt "http://s3.test:9070/local-dev-bucket/first.txt" --aws-sigv4 "aws:amz:us-east-1:s3" --user "admin:password"
```

List what is in it:

```bash
curl "http://s3.test:9070/local-dev-bucket?list-type=2" --aws-sigv4 "aws:amz:us-east-1:s3" --user "admin:password"
```

```powershell
curl.exe "http://s3.test:9070/local-dev-bucket?list-type=2" --aws-sigv4 "aws:amz:us-east-1:s3" --user "admin:password"
```

The six commands above were run verbatim against the running stack from Git Bash on Windows, and their Unix shell forms were run again from Ubuntu inside WSL. Swap `s3.test` for `localhost` in any of them if you have not added the hosts line.

For clicking around instead, open `http://s3.test:9071` in a browser, or `http://localhost:9071` without the hosts line. It answers `308` and redirects to `/Default/buckets`, keeping whichever name you asked with, and that page lists every bucket and links each one to its objects with download, metadata and delete actions.

Objects live in the `floci_data` named volume, mounted at `/app/data` because `FLOCI_STORAGE_MODE` is set to `persistent`. A `docker restart floci` keeps them, and so does destroying the container and recreating it from the Compose file. Both were verified. What does remove them is `docker compose down -v`, which deletes the volume along with every other volume in the stack.

Health lives at `http://s3.test:9070/_floci/health`, or `http://localhost:9070/_floci/health` without the hosts line, and answers with a JSON map of every emulated service. Two behaviours differ from MinIO and will bite if you assume otherwise.

Floci implements no MinIO admin interface. The old `http://localhost:9070/minio/health/live` path answers `404`, and any tool built on MinIO's admin API, `mc` included, has nothing to talk to here.

Nothing on either port asks for a credential. s3manager on `9071` ships no authentication at all, so whoever reaches that page can read, write and delete in every bucket. The Floci gateway on `9070` is no better: it accepts a wrong secret key, a wrong region, and requests carrying no signature whatsoever, all with the same `200`. A plain unsigned `PUT` and a plain unsigned `DELETE` both succeeded during testing. The credentials above exist so that client libraries which demand a key have one to send, not because anything checks them. The MinIO service this replaced was configured with a root user and password, so the same values now buy you nothing. Both ports are published on `0.0.0.0`, so this is open to your whole network segment, not only to the machine. Keep real data out of it, and bind the ports to `127.0.0.1` in the Compose file if the machine sits on a network you do not control.

### Configuration deep-dives

---

| Doc                                                          | What's in it                                                            |
| ------------------------------------------------------------ | ----------------------------------------------------------------------- |
| [auth/Keycloak/config.md](./auth/Keycloak/config.md)         | Realm export, client setup, export-import flow.                         |
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
of one platform's image, so the pin still resolves on an arm64 machine as well as on amd64. `cloudlena/s3manager` is the
exception in this stack: version `v0.8.0` upstream is a single `linux/amd64` manifest with no index above it, so its
digest is inherently one platform, which is a property of what the publisher shipped rather than of how it is pinned
here.

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
- [s3manager](https://hub.docker.com/r/cloudlena/s3manager/tags)
