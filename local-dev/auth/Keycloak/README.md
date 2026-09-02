# Keycloak (local)

> Custom Keycloak image used by the local-dev Compose stack. HTTPS on 9443, and the `local` realm imported from a committed realm export on first boot.

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

There is no database seeding step. The realm travels inside the image: the Dockerfile copies
[export/config/local-realm-export.json](./export/config/local-realm-export.json) into `/opt/keycloak/data/import/`
and the entrypoint is `kc.sh start --optimized --import-realm`, so Keycloak creates its own schema and imports the
realm on its first boot against an empty `keycloak` database. All Postgres has to provide is that empty database,
which [../../postgresql/init.sh](../../postgresql/init.sh) creates. Nothing mounts the JSON at runtime, so the image
needs no file from your disk.

Start the container (use the tag you built):

```bash
docker run -d --name keycloak -p 9443:9443 keycloak-local:latest
```

For the integrated Compose stack (recommended), use the entry in
[local-dev/README_LOCAL_DEV.md](../../README_LOCAL_DEV.md) instead.

`--import-realm` imports a realm only when that realm is absent from the database. On a machine whose
`postgres_data` volume already holds `local`, the import is skipped and nothing is overwritten, which is measured:
starting the container against a database that already carries the realm logs
`Realm 'local' already exists. Import skipped` and then boots normally. Editing the JSON
therefore changes nothing for an existing volume. What takes the import path is a fresh clone, or a volume that has
been removed.

### Get a token

---

The `local` realm ships a confidential client `local-client` with a baked-in test user (`lukk` / `test1234`). The
secret below is part of the committed realm export, [export/config/local-realm-export.json](./export/config/local-realm-export.json), and is safe to use locally.

Run it from the project root. The command is the same everywhere except for one Windows-only flag, so it is written
once per platform group rather than once per operating system. All three forms were measured returning HTTP 200 with
`ssl_verify_result=0`, the first from Ubuntu 24.04 inside WSL and the other two from Windows.

Ubuntu, Arch Linux, macOS and WSL:

```bash
curl --cacert ./local-dev/auth/certificates/localhost/localhost-ca.crt --location 'https://keycloak.test:9443/realms/local/protocol/openid-connect/token' --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode 'grant_type=password' --data-urlencode 'client_id=local-client' --data-urlencode 'client_secret=nZUMlOQZufa5ljWW5hHXOtGKLn0mpTkN' --data-urlencode 'scope=openid profile email' --data-urlencode 'username=lukk' --data-urlencode 'password=test1234'
```

Git Bash on Windows:

```bash
curl --cacert ./local-dev/auth/certificates/localhost/localhost-ca.crt --ssl-revoke-best-effort --location 'https://keycloak.test:9443/realms/local/protocol/openid-connect/token' --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode 'grant_type=password' --data-urlencode 'client_id=local-client' --data-urlencode 'client_secret=nZUMlOQZufa5ljWW5hHXOtGKLn0mpTkN' --data-urlencode 'scope=openid profile email' --data-urlencode 'username=lukk' --data-urlencode 'password=test1234'
```

PowerShell:

```powershell
curl.exe --cacert .\local-dev\auth\certificates\localhost\localhost-ca.crt --ssl-revoke-best-effort --location 'https://keycloak.test:9443/realms/local/protocol/openid-connect/token' --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode 'grant_type=password' --data-urlencode 'client_id=local-client' --data-urlencode 'client_secret=nZUMlOQZufa5ljWW5hHXOtGKLn0mpTkN' --data-urlencode 'scope=openid profile email' --data-urlencode 'username=lukk' --data-urlencode 'password=test1234'
```

`--cacert` is on all three, because the operating system import below is optional, so on a machine that skipped it the
same command without the flag fails before it reaches Keycloak. What that failure looks like depends on which library
curl was built against, and both were measured. On Windows, where curl uses Schannel:

```text
curl: (60) schannel: SEC_E_UNTRUSTED_ROOT (0x80090325) - The certificate chain was issued by an authority that is not trusted.
```

On Ubuntu in WSL, where curl uses OpenSSL:

```text
curl failed to verify the legitimacy of the server and therefore could not establish a secure connection to it.
```

`--ssl-revoke-best-effort` is the one Windows-only piece. It is a Schannel option, so it belongs on the two Windows
forms, Git Bash included, and it is left off the first form. Nothing complains if you get that wrong, which is the
trap: measured on Ubuntu, curl accepts the flag and returns the same 200, so a copied Windows command carries a dead
flag rather than failing. Both flags are explained in [../README.md](../README.md) under "curl".

The hostname is not cosmetic either. The compose file sets `KC_HOSTNAME=keycloak.test` and `KC_HOSTNAME_PORT=9443`,
so the token that command returns carries `"iss": "https://keycloak.test:9443/realms/local"`, read off a real token
here. That issuer is fixed by the configuration rather than by the URL you asked on, so requesting a token through
some other name still hands you `keycloak.test` in the claim, and a client configured for that other name then
rejects it. The bare `keycloak` still resolves inside the Docker network as the container name and is still in the
certificate, so nothing breaks. It is simply not the name to point a client at.

### Certificate in the operating system trust store (optional)

---

This section is optional. Trusting the authority here silences the browser warning on `https://keycloak.test:9443`
and satisfies any tool that reads the operating system's own certificate store. Node is untouched by it wherever you
run, because it carries its own compiled-in list of roots. Java depends on the platform: on Windows it reads a
`cacerts` file inside the Java Development Kit that is linked to nothing, while on Ubuntu and on Arch the
distribution points that same file at the system bundle, so an import here does reach Java there. That is measured
per platform in [../README.md](../README.md) under "Trust the authority in your operating system". Skipping the whole
section and clicking through the browser warning is a perfectly reasonable choice.

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

There are four mechanisms below, not one with variations. Ubuntu and Arch disagree about both the directory and the
command, and macOS uses a keychain that is not a directory of files at all, so pick your own heading and ignore the
rest.

#### Ubuntu and Debian

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

#### Arch Linux

Arch does not use the Debian directory or the Debian command. `/usr/local/share/ca-certificates` does not exist and
`update-ca-certificates` is not installed, so the commands above do nothing here except create a directory nobody
reads. Copy the authority into the p11-kit anchor directory instead:

```bash
sudo cp ./local-dev/auth/certificates/localhost/localhost-ca.crt /etc/ca-certificates/trust-source/anchors/
```

Rebuild the extracted bundles:

```bash
sudo update-ca-trust
```

Check that it took, which prints the authority's own subject line:

```bash
trust list --filter=ca-anchors | grep -A2 "localhost certificate authority"
```

To remove, delete the file and rebuild again:

```bash
sudo rm /etc/ca-certificates/trust-source/anchors/localhost-ca.crt
```

```bash
sudo update-ca-trust
```

Both halves were measured in an `archlinux` container: after the import `openssl verify` accepts this repository's
leaf against the system store, and after the removal it goes back to `error 20 at 0 depth lookup: unable to get local
issuer certificate`. Two Arch-specific consequences come with it, both measured and both explained in
[../README.md](../README.md). This import also reaches Java, because Arch's Java trust store is a symlink into the same
extracted bundle. And for the same reason, anything imported straight into that store with `keytool -cacerts` is
destroyed the next time `update-ca-trust` runs.

#### macOS

Not measured, because no macOS machine was available to this repository. macOS keeps trust in a keychain rather than
in a directory of certificate files, so neither Linux mechanism applies and this is the documented one. Import into
the system keychain:

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./local-dev/auth/certificates/localhost/localhost-ca.crt
```

Remove it again by its common name, which is what the certificate carries in
[certificates/localhost/ca.cnf](../certificates/localhost/ca.cnf):

```bash
sudo security delete-certificate -c "localhost certificate authority" /Library/Keychains/System.keychain
```

Assume this does not reach a Java Development Kit installed from Temurin or Oracle, which ships its own `cacerts` file
with no link to the keychain, so on macOS use the `keytool` route in [../README.md](../README.md) for anything running
on the Java Virtual Machine.

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

These are HTTPS, so they hit the same trust question as the token request above, and split the same way. Pass
`--cacert` unless you took the optional operating system import, and add `--ssl-revoke-best-effort` on Windows only.

Ubuntu, Arch Linux, macOS and WSL:

```bash
curl --cacert ./local-dev/auth/certificates/localhost/localhost-ca.crt https://keycloak.test:9000/health
```

Git Bash on Windows:

```bash
curl --cacert ./local-dev/auth/certificates/localhost/localhost-ca.crt --ssl-revoke-best-effort https://keycloak.test:9000/health
```

PowerShell:

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
