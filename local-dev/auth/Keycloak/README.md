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

Run it from the project root. Both forms below were measured returning HTTP 200 with `ssl_verify_result=0`.

```bash
curl --cacert ./local-dev/auth/certificates/localhost/localhost-ca.crt --ssl-revoke-best-effort --location 'https://keycloak.test:9443/realms/local/protocol/openid-connect/token' --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode 'grant_type=password' --data-urlencode 'client_id=local-client' --data-urlencode 'client_secret=nZUMlOQZufa5ljWW5hHXOtGKLn0mpTkN' --data-urlencode 'scope=openid profile email' --data-urlencode 'username=lukk' --data-urlencode 'password=test1234'
```

```powershell
curl.exe --cacert .\local-dev\auth\certificates\localhost\localhost-ca.crt --ssl-revoke-best-effort --location 'https://keycloak.test:9443/realms/local/protocol/openid-connect/token' --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode 'grant_type=password' --data-urlencode 'client_id=local-client' --data-urlencode 'client_secret=nZUMlOQZufa5ljWW5hHXOtGKLn0mpTkN' --data-urlencode 'scope=openid profile email' --data-urlencode 'username=lukk' --data-urlencode 'password=test1234'
```

`--cacert` is there because the operating system import below is optional, so on a machine that skipped it the same
command without the flag fails before it reaches Keycloak, measured:

```text
curl: (60) schannel: SEC_E_UNTRUSTED_ROOT (0x80090325) - The certificate chain was issued by an authority that is not trusted.
```

`--ssl-revoke-best-effort` is Schannel-only and belongs on the Windows forms, Git Bash included. Drop it on Linux and
macOS. Both flags are explained in [../README.md](../README.md) under "curl".

The hostname is not cosmetic either. The compose file sets `KC_HOSTNAME=keycloak.test` and `KC_HOSTNAME_PORT=9443`,
so the token that command returns carries `"iss": "https://keycloak.test:9443/realms/local"`, read off a real token
here. That issuer is fixed by the configuration rather than by the URL you asked on, so requesting a token through
some other name still hands you `keycloak.test` in the claim, and a client configured for that other name then
rejects it. The bare `keycloak` still resolves inside the Docker network as the container name and is still in the
certificate, so nothing breaks. It is simply not the name to point a client at.

### Certificate in the operating system trust store (optional)

---

This section is optional and it changes only what the developer sees. Trusting the authority here silences the
browser warning on `https://keycloak.test:9443` and satisfies any tool that reads the operating system's own
certificate store. It makes no service to service call work that was not working already, because Java reads
`cacerts` inside the JDK and Node reads its own compiled-in list, and neither consults the operating system at all.
Skipping the whole section and clicking through the browser warning is a perfectly reasonable choice.

What is not optional is the build-time import, where each image that talks to Keycloak imports the authority into
its own trust store in its own Dockerfile. That is the path that makes the stack work, it is documented in
[../README.md](../README.md) under "Trust the authority in an image you build", and it needs no mount and no runtime
configuration.

The Compose stack uses a leaf certificate signed by a local certificate authority, both under
[certificates/localhost/](../certificates/localhost/). Import the authority's certificate, `localhost-ca.crt`, into
the OS trust store once and it covers this leaf and any future leaf signed by the same authority, with no further
import needed. Run the steps below from the project root. If you ever imported a leaf certificate from this
directory into the trust store, under whichever name it carried at the time, remove it first with the
platform-specific removal step below, then import `localhost-ca.crt` instead.

#### Windows (Administrator PowerShell)

Import:

```powershell
Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -Command & { Import-Certificate -FilePath '$(Resolve-Path -Path '.\local-dev\auth\certificates\localhost\localhost-ca.crt')' -CertStoreLocation Cert:\LocalMachine\Root }"
```

The command prints the certificate's thumbprint on success. Save that string, you need it to remove the cert later.

Remove (replace `YOUR_CERT_THUMBPRINT`):

```powershell
Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -Command & { Remove-Item -Path 'Cert:\LocalMachine\Root\YOUR_CERT_THUMBPRINT' -ErrorAction Stop }"
```

If you imported a leaf certificate earlier and still have the thumbprint it printed at the time, run the same
removal command with that thumbprint before importing `localhost-ca.crt`.

#### Linux (Ubuntu / Debian)

Copy the authority's certificate into the system store:

```bash
sudo cp ./local-dev/auth/certificates/localhost/localhost-ca.crt /usr/local/share/ca-certificates/
```

Refresh the trust bundle:

```bash
sudo update-ca-certificates
```

To remove, delete the file and refresh again:

```bash
sudo rm /usr/local/share/ca-certificates/localhost-ca.crt
```

```bash
sudo update-ca-certificates
```

To remove a leaf certificate imported earlier, list the directory to find whatever name you copied in at the time:

```bash
ls /usr/local/share/ca-certificates/
```

Then remove that file and refresh again, substituting the name the listing showed:

```bash
sudo rm /usr/local/share/ca-certificates/THE_FILE_YOU_COPIED
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

Health and metrics both live on Keycloak's management port (`9000`), not the public HTTPS port. The hostname is
`keycloak.test` for the same reason as everywhere else, and 9000 is published to the host by
[local-dev-docker-compose.yaml](../../local-dev-docker-compose.yaml) so a browser or curl on the machine reaches it
directly. All five were measured returning HTTP 200 against a running container, and the byte counts below are from
that run rather than from the pattern.

| Endpoint | What it returns | Measured |
| --- | --- | --- |
| `https://keycloak.test:9000/health` | Aggregate health | 200, 265 bytes |
| `https://keycloak.test:9000/health/live` | Liveness (process is up) | 200, 45 bytes |
| `https://keycloak.test:9000/health/ready` | Readiness (can serve requests) | 200, 265 bytes |
| `https://keycloak.test:9000/health/started` | Startup probe (initial boot completed) | 200, 45 bytes |
| `https://keycloak.test:9000/metrics` | Prometheus-format metrics | 200, 186805 bytes |

These are HTTPS, so they hit the same trust question as the token request above. Pass `--cacert` unless you took the
optional operating system import, and add `--ssl-revoke-best-effort` on Windows, Git Bash included:

```bash
curl --cacert ./local-dev/auth/certificates/localhost/localhost-ca.crt --ssl-revoke-best-effort https://keycloak.test:9000/health
```

```powershell
curl.exe --cacert .\local-dev\auth\certificates\localhost\localhost-ca.crt --ssl-revoke-best-effort https://keycloak.test:9000/health
```

That command returns:

```json
{
    "status": "UP",
    "checks": [
        {
            "name": "Keycloak database connections async health check",
            "status": "UP"
        },
        {
            "name": "Keycloak cluster health check",
            "status": "UP"
        }
    ]
}
```

Drop `--cacert` and the request never reaches Keycloak, measured on a machine that skipped the operating system
import:

```text
curl: (60) schannel: SEC_E_UNTRUSTED_ROOT (0x80090325) - The certificate chain was issued by an authority that is not trusted.
```

The compose healthcheck for this same port uses `https://keycloak:9000/health/ready` with `-k`, which is correct
there and wrong here. It runs inside the container, where Docker's embedded resolver answers the container name and
the host's hosts file does not exist.

### OIDC discovery endpoint

---

```text
https://keycloak.test:9443/realms/local/.well-known/openid-configuration
```

That document reports `"issuer": "https://keycloak.test:9443/realms/local"`, which is the name every client should
be configured against.
