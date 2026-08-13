# Keycloak (local)

> Custom Keycloak image used by the local-dev Compose stack. HTTPS on 9443, admin / `local` realm pre-imported.

---

### Build

---

Pick a real tag, not `latest`, when you publish anywhere. Run from the project root:

```bash
docker build -f ./local-dev/auth/Keycloak/Dockerfile -t keycloak-local:latest ./local-dev/auth
```

Without cache:

```bash
docker build --no-cache -f ./local-dev/auth/Keycloak/Dockerfile -t keycloak-local:latest ./local-dev/auth
```

### Run

---

On first run, import the seed dump into the `keycloak` PostgreSQL database:

```bash
psql -U postgres -h localhost -p 5432 -d keycloak -f ./local-dev/auth/Keycloak/export/database/keycloak-dump.sql
```

Then start the container (use the tag you built):

```bash
docker run -d --name keycloak -p 9443:9443 keycloak-local:latest
```

For the integrated Compose stack (recommended), use the entry in
[local-dev/README_LOCAL_DEV.md](../../README_LOCAL_DEV.md) instead.

### Get a token

---

The `local` realm ships a confidential client `local-client` with a baked-in test user (`lukk` / `test1234`). The
secret below is part of the committed realm export and is safe to use locally.

```bash
curl --location 'https://keycloak:9443/realms/local/protocol/openid-connect/token' --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode 'grant_type=password' --data-urlencode 'client_id=local-client' --data-urlencode 'client_secret=nZUMlOQZufa5ljWW5hHXOtGKLn0mpTkN' --data-urlencode 'scope=openid profile email' --data-urlencode 'username=lukk' --data-urlencode 'password=test1234'
```

### Certificate

---

The Compose stack uses a self-signed cert under
[certificates/localhost/](../certificates/localhost/). For browsers and HTTP clients to trust it, import the cert
into the OS trust store. Run from the project root.

#### Windows (Administrator PowerShell)

Import:

```powershell
Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -Command & { Import-Certificate -FilePath '$(Resolve-Path -Path '.\local-dev\auth\certificates\localhost\localhostDomain.crt')' -CertStoreLocation Cert:\LocalMachine\Root }"
```

The command prints the certificate's thumbprint on success. Save that string; you need it to remove the cert later.

Remove (replace `YOUR_CERT_THUMBPRINT`):

```powershell
Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -Command & { Remove-Item -Path 'Cert:\LocalMachine\Root\YOUR_CERT_THUMBPRINT' -ErrorAction Stop }"
```

#### Linux (Ubuntu / Debian)

Copy the cert into the system store:

```bash
sudo cp ./local-dev/auth/certificates/localhost/localhostDomain.crt /usr/local/share/ca-certificates/
```

Refresh the trust bundle:

```bash
sudo update-ca-certificates
```

To remove, delete the file and refresh again:

```bash
sudo rm /usr/local/share/ca-certificates/localhostDomain.crt
```

```bash
sudo update-ca-certificates
```

### Configuration

---

Realm exports, client setup, and operational knobs are documented in
[config.md](./config.md).

### Health and metrics

---

Both endpoints live on Keycloak's management port (`9000`), not the public HTTPS port.

| Endpoint                                       | What it returns                              |
| ---------------------------------------------- | -------------------------------------------- |
| `https://keycloak:9000/health`                 | Aggregate health                             |
| `https://keycloak:9000/health/live`            | Liveness (process is up)                     |
| `https://keycloak:9000/health/ready`           | Readiness (can serve requests)               |
| `https://keycloak:9000/health/started`         | Startup probe (initial boot completed)       |
| `https://keycloak:9000/metrics`                | Prometheus-format metrics                    |

### OIDC discovery endpoint

---

```text
https://keycloak:9443/realms/local/.well-known/openid-configuration
```
