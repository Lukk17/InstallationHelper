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
| MySQL       | `3306`            | `test-spring`          | `root`      | `local`     | `mysql:9.6.0`                                                                  |
| PostgreSQL  | `5432`            | `keycloak`, `postgres` | `postgres`  | `local`     | custom, built from `postgres:17.9`. See [postgresql/](./postgresql/README.md). |
| MongoDB     | `27017`           | `articles`             | (none)      | (none)      | `mongo:8.2.6`                                                                  |
| Keycloak    | `9443` (HTTPS)    | realm `local`          | `admin`     | `admin`     | custom, built from `keycloak:26.5`. See [auth/Keycloak/](./auth/Keycloak/README.md). |

PostgreSQL also initialises a `keycloak` user (password `local`) and imports the seed dump from
[auth/Keycloak/export/database/keycloak-dump.sql](./auth/Keycloak/export/database/keycloak-dump.sql) so Keycloak boots
with the realm already in place.

Keycloak's management port is `9000`. URLs:

- HTTPS app: `https://localhost:9443` or `https://keycloak.test:9443` (hosts entry needed; see
  [auth/README.md](./auth/README.md))
- Management: `https://localhost:9000/health`, `/metrics`, etc.

Test user in the `local` realm: `lukk` / `test1234`.

### Configuration deep-dives

---

| Doc                                                          | What's in it                                                            |
| ------------------------------------------------------------ | ----------------------------------------------------------------------- |
| [auth/Keycloak/CONFIG.md](./auth/Keycloak/CONFIG.md)         | Realm export, client setup, export-import flow.                         |
| [auth/Keycloak/README.md](./auth/Keycloak/README.md)         | Dockerfile, token curl, OS trust store import for the self-signed cert. |
| [auth/README.md](./auth/README.md)                           | `hosts` setup, self-signed cert generation, Let's Encrypt for prod.     |
| [postgresql/README.md](./postgresql/README.md)               | Standalone Postgres run, credentials.                                   |

### Docker Hub image tags for reference

---

Bump the image tags in [local-dev-docker-compose.yaml](./local-dev-docker-compose.yaml) when you want a newer
release; the links go to the upstream tag listings.

- [MySQL](https://hub.docker.com/_/mysql/tags)
- [PostgreSQL](https://hub.docker.com/_/postgres/tags)
- [MongoDB](https://hub.docker.com/_/mongo/tags)
- [Keycloak](https://hub.docker.com/r/keycloak/keycloak/tags)
