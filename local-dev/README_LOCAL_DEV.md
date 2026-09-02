# Local Development Databases and Services

> Docker Compose stack with MySQL, PostgreSQL, MongoDB, and Keycloak (HTTPS). Spin up, point your app at it, tear down.

---

### Start the stack

---

Run from the project root.

```bash
docker-compose -f ./local-dev/local-dev-docker-compose.yaml up -d
```

Stop with the same command and `down`:

```bash
docker-compose -f ./local-dev/local-dev-docker-compose.yaml down
```

PowerShell on Windows is the same; just use forward slashes or escape backslashes.

### Services

---

| Service     | Port              | Database / Realm       | Username    | Password    | Image                                                                          |
| ----------- | ----------------- | ---------------------- | ----------- | ----------- | ------------------------------------------------------------------------------ |
| MySQL       | `3306`            | `test-spring`          | `root`      | `local`     | `mysql:9.7.2`                                                                  |
| PostgreSQL  | `5432`            | `keycloak`, `postgres` | `postgres`  | `local`     | custom, built from `postgres:17.11`. See [postgresql/](./postgresql/README.md). |
| MongoDB     | `27017`           | `articles`             | (none)      | (none)      | `mongo:8.3.8`                                                                  |
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

PostgreSQL also initialises a `keycloak` user (password `local`) and imports the seed dump from
[auth/Keycloak/export/database/keycloak-dump.sql](./auth/Keycloak/export/database/keycloak-dump.sql) so Keycloak boots
with the realm already in place.

Keycloak's management port is `9000`. URLs:

- HTTPS app: `https://localhost:9443` or `https://keycloak.test:9443` (hosts entry needed; see
  [auth/README.md](./auth/README.md))
- Management: `https://localhost:9000/health`, `/metrics`, etc.

Test user in the `local` realm: `lukk` / `test1234`.

### Object storage

---

[Floci](https://github.com/floci-io/floci) emulates the Amazon Web Services interfaces and serves all of them from one gateway port. Only S3 is used here. It took over from MinIO because MinIO's community repository is archived, so the tag that was pinned in the Compose file is the last image Docker Hub will ever serve for it. The host port stayed `9070`, so anything already pointing at the old S3 endpoint keeps working without an edit.

[s3manager](https://github.com/cloudlena/s3manager) is the browser side: a bucket and object browser that took over port `9071` from the MinIO console. It talks to Floci over the Compose network at `floci:4566` and starts only once Floci reports healthy.

Point an application at these values:

| Setting | Value |
| ------- | ----- |
| Endpoint | `http://localhost:9070` |
| Region | `us-east-1` |
| Access key id | `admin` |
| Secret access key | `password` |
| Path style addressing | works, `http://localhost:9070/<bucket>/<key>` |
| Virtual hosted addressing | works, `http://<bucket>.localhost:9070/<key>` |

Both addressing styles were exercised against the running container, so a client library that insists on one or the other is fine either way.

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

For clicking around instead, open `http://localhost:9071` in a browser. It redirects to `/Default/buckets`, which lists every bucket, and each bucket links to its objects with download, metadata and delete actions.

Objects live in the `floci_data` named volume, mounted at `/app/data` because `FLOCI_STORAGE_MODE` is set to `persistent`. A `docker restart floci` keeps them, and so does destroying the container and recreating it from the Compose file. Both were verified. What does remove them is `docker compose down -v`, which deletes the volume along with every other volume in the stack.

Health lives at `http://localhost:9070/_floci/health`, which answers with a JSON map of every emulated service. Two behaviours differ from MinIO and will bite if you assume otherwise.

Floci implements no MinIO admin interface. The old `http://localhost:9070/minio/health/live` path answers `404`, and any tool built on MinIO's admin API, `mc` included, has nothing to talk to here.

Nothing on either port asks for a credential. s3manager on `9071` ships no authentication at all, so whoever reaches that page can read, write and delete in every bucket. The Floci gateway on `9070` is no better: it accepts a wrong secret key, a wrong region, and requests carrying no signature whatsoever, all with the same `200`. A plain unsigned `PUT` and a plain unsigned `DELETE` both succeeded during testing. The credentials above exist so that client libraries which demand a key have one to send, not because anything checks them. The MinIO service this replaced was configured with a root user and password, so the same values now buy you nothing. Both ports are published on `0.0.0.0`, so this is open to your whole network segment, not only to the machine. Keep real data out of it, and bind the ports to `127.0.0.1` in the Compose file if the machine sits on a network you do not control.

### Configuration deep-dives

---

| Doc                                                          | What's in it                                                            |
| ------------------------------------------------------------ | ----------------------------------------------------------------------- |
| [auth/Keycloak/config.md](./auth/Keycloak/config.md)         | Realm export, client setup, export-import flow.                         |
| [auth/Keycloak/README.md](./auth/Keycloak/README.md)         | Dockerfile, token curl, OS trust store import for the certificate authority. |
| [auth/README.md](./auth/README.md)                           | `hosts` setup, local certificate authority generation, Let's Encrypt for prod. |
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
