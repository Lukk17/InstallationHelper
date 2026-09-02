# Local PostgreSQL

> Custom PostgreSQL image used by the local-dev Compose stack. Creates the users and databases the stack needs, all of them empty.

---

### Build

---

Run from the project root.

```bash
docker build -f ./local-dev/postgresql/Dockerfile -t local-postgres:latest .
```

Without cache:

```bash
docker build --no-cache -f ./local-dev/postgresql/Dockerfile -t local-postgres:latest .
```

### Run standalone

---

If you want this container running on its own, outside the Compose stack, create the shared network once:

```bash
docker network create local-network
```

Then run it:

```bash
docker run -d --name local-postgres --network local-network -v postgres-data:/var/lib/postgresql/data -p 5432:5432 local-postgres:latest
```

For the normal multi-service setup, use the Compose entry in
[local-dev/README_LOCAL_DEV.md](../README_LOCAL_DEV.md) instead.

### Credentials

---

| Field    | Value      |
| -------- | ---------- |
| User     | `postgres` |
| Password | `local`    |
| Port     | `5432`     |

The image also initialises a second user `keycloak` (password `local`) and an empty `keycloak` database for Keycloak
to migrate into. It holds no Keycloak data of its own: Keycloak creates its schema and imports its realm itself on
first boot. See the Keycloak notes in [local-dev/README_LOCAL_DEV.md](../README_LOCAL_DEV.md).
