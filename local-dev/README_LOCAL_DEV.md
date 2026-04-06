# Local Development Databases & Services

This directory contains the `docker-compose` setup to spin up essential databases and services for local software development.

## 🚀 Running the Local Dev Stack

Run the following command in your terminal from the **project root directory**:

```bash
docker-compose -f ./local-dev/local-dev-docker-compose.yaml up -d
```

---

## 🔐 Credentials & Configurations

Below are the configurations and credentials for each of the services started by the `docker-compose` stack.

### 🐬 MySQL
- **Port:** `3306`
- **Database Name:** `test-spring`
- **Username:** `root`
- **Password:** `local`
- **Docker Image:** `mysql:9.6.0`

### 🐘 PostgreSQL
- **Port:** `5432`
- **Databases:** `keycloak` (Default `postgres` DB also available)
- **Username:** `postgres`
- **Password:** `local`
- **Docker Image:** Custom built from `postgres:17.9` (See `postgresql/Dockerfile`). 
  > *Note: By default, this also initializes the Keycloak database with a user `keycloak` (password `local`) and imports a data dump.*

### 🍃 MongoDB
- **Port:** `27017`
- **Database Name:** `articles`
- **Username:** *(No user required)*
- **Password:** *(No password required)*
- **Docker Image:** `mongo:8.2.6`

### 🔐 Keycloak
- **HTTPS Port:** `9443`
- **Management Port:** `9000`
- **URL (HTTPS):** `https://localhost:9443` (or `https://keycloak.test:9443`)
- **Admin Username:** `admin`
- **Admin Password:** `admin`
- **Test User Account:** `lukk` (Password: `test1234`) - Available in the `local` realm
- **Docker Image:** Custom built from `keycloak:26.5` (See `auth/Keycloak/Dockerfile`).

> **💡 Note:** For detailed Keycloak configuration, realm management, and export instructions, please refer to the dedicated [Keycloak Configuration Guide](auth/Keycloak/CONFIG.md).

---

### Docker Hub Links for Reference:

* [MySQL Tags](https://hub.docker.com/_/mysql/tags)
* [MongoDB Tags](https://hub.docker.com/_/mongo/tags)
* [Postgres Tags](https://hub.docker.com/_/postgres/tags)
* [Keycloak Tags](https://hub.docker.com/r/keycloak/keycloak/tags)
