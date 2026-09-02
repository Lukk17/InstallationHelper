# Local Auth

> A local certificate authority + hosts entries for running Keycloak under `https://keycloak.test:9443` on the local machine.

---

### Hosts setup

---

Two names point at the loopback. Both are in the leaf certificate's SAN list, so the handshake succeeds either way, but they are not interchangeable in what you should use them for.

Append both lines to your hosts file:

```text
127.0.0.1 keycloak.test
127.0.0.1 keycloak
```

`keycloak.test` is the canonical name and the one to point applications, browsers and HTTP clients at. The compose file sets `KC_HOSTNAME=keycloak.test` and `KC_HOSTNAME_PORT=9443`, so every token Keycloak mints carries `https://keycloak.test:9443/realms/local` as its `iss` claim. A client configured against any other name completes the handshake and then fails issuer validation on the token it gets back, which is a confusing failure because nothing about it looks like a hostname problem. The port is part of the name here. 9443 is not a port any client infers, so it is written out everywhere.

`keycloak` is the container name, so Docker's embedded resolver answers it inside the compose network whether or not any hosts file mentions it. That is why the healthcheck in [local-dev-docker-compose.yaml](../local-dev-docker-compose.yaml) reaches `https://keycloak:9000/health/ready` and works. Keep the hosts line so the same name also resolves from the machine, and treat it as the name for talking to the container rather than to the issuer.

Linux path: [/etc/hosts](file:///etc/hosts) (needs `sudo`).

Windows path: `C:\Windows\System32\drivers\etc\hosts` (needs an Administrator editor).

For Keycloak setup, container build, realm import, and troubleshooting, see
[Keycloak/README.md](./Keycloak/README.md).

### Reaching keycloak.test from another container

---

A hosts file belongs to the machine, and Docker's embedded resolver never reads it. A container that asks for `keycloak.test` therefore gets nothing back, and the connection fails before TLS starts. Substituting the container name is not a fix, because a token minted for `https://keycloak.test:9443` fails issuer validation in a client that was pointed at the bare container name instead.

The answer is an `extra_hosts` entry on every service that needs the name, mapping it to the Docker host:

```yaml
services:
  your-service:
    extra_hosts:
      - "keycloak.test:host-gateway"
```

`host-gateway` is resolved by Docker itself and works on Linux, Windows and macOS from Docker 20.10 onward. It is the same mechanism the `keycloak` service already uses for `host.docker.internal`.

Be clear about what it costs. The container leaves the bridge network, goes out to the host, and comes back in through the published 9443. Two containers on the same network end up talking through the host, which is slower than a direct hop and means 9443 has to stay published. A Compose network alias would remove that hairpin in one line, and it is rejected for the reason ADR-008 in the sibling Pharmacy stack gives: an alias resolves to a container from the inside and to nothing at all from the outside, and an issuer URI has to resolve to the same service from both.

Measured with a throwaway container started with `--add-host keycloak.test:host-gateway`, which is the `docker run` spelling of that compose entry. It reached Keycloak on 9443 and got HTTP 200 back.

### Certificate generation

---

#### Localhost (local certificate authority) <a id="localhost"></a>

Nothing here is self-signed. A local certificate authority signs a leaf, and Keycloak serves the leaf. That split is
what makes the trust import a one-time job: import the authority into a trust store once, as described under "Trust
the authority in an image you build" and the sections after it, and it covers this leaf and every future leaf the
same authority signs. A self-signed leaf would have to be re-imported everywhere on every reissue.

All four files are committed, so a clone runs with no generation step. Regenerating is only needed when a hostname
is added, a key is rotated, or the ten years run out. Edit the SAN list in
[certificates/localhost/leaf.cnf](./certificates/localhost/leaf.cnf) first.

The script writes its output beside itself, so run it from its own directory. From the project root, on Linux, macOS,
WSL or Git Bash on Windows:

```bash
cd local-dev/auth/certificates/localhost
```

```bash
bash generate-certificates.sh
```

The script regenerates the authority as well as the leaf, and ends by running `openssl verify` against what it
produced. Reissuing the leaf costs a rebuild of the Keycloak image, which copies the leaf in, and a restart.
Reissuing the authority costs that plus a re-import in every trust store that holds it: every image that imported it
at build time, which means rebuilding each of those, plus the optional operating system store and any JVM, Node or
Python trust store set up from the sections below. To reissue the leaf alone, run the second and
third `openssl` commands inside the script and skip the first, then run its `rm` line as well: signing writes a
serial file, `localhost-ca.srl`, which this repository deliberately does not track.

`localhost-ca.crt`, `localhost-ca.key`, `localhost.crt` and `localhost.key` are the result. The authority's
distinguished name and its CA extensions live in [certificates/localhost/ca.cnf](./certificates/localhost/ca.cnf),
the leaf's common name, SAN entries and extensions in
[certificates/localhost/leaf.cnf](./certificates/localhost/leaf.cnf). That SAN list, read back off the certificate
itself, is `localhost`, `host.docker.internal`, `keycloak.test`, `keycloak`, `sky.test` and `sky`, then the addresses
`127.0.0.1` and `::1`. The authority's private key,
`localhost-ca.key`, is committed on purpose, because this authority exists only for local development on machines
the owner controls. It mints a certificate for any name, which is a larger exposure than the leaf it signs, so it
must never reach a real environment.

#### Production (Let's Encrypt) <a id="production"></a>

Use certbot on Linux (or WSL on Windows). Install it first:

```bash
sudo apt install certbot
```

Issue the certificate. Replace `your_domain` below with the actual public hostname pointing at this machine:

```bash
sudo certbot certonly --standalone
```

Keycloak reads a JKS keystore, so convert the PEM bundle to PKCS12 first. Replace `your_domain` and `your_alias`:

```bash
sudo openssl pkcs12 -export -in /etc/letsencrypt/live/your_domain/fullchain.pem -inkey /etc/letsencrypt/live/your_domain/privkey.pem -out pkcs.p12 -name your_alias -CAfile /etc/letsencrypt/live/your_domain/chain.pem -caname root
```

Then import the PKCS12 into a JKS keystore. Replace the four `your_*` placeholders:

```bash
sudo keytool -importkeystore -deststorepass your_keystore_password -destkeypass your_key_password -destkeystore keystore.jks -srckeystore pkcs.p12 -srcstoretype PKCS12 -srcstorepass your_p12_password -alias your_alias
```

Drop the resulting `keystore.jks` into Keycloak's expected location and restart the container.

### Trust the authority in an image you build

---

This is the primary path and the one that has to work. Service to service TLS must succeed on a machine where nobody has ever touched the operating system trust store, so every image that talks to Keycloak imports the authority itself, at build time. The certificate ends up inside the image. That means no bind mount, no environment variable passed at `docker run`, and nothing in the compose file beyond the network the service is already on and the `extra_hosts` line above.

#### A JVM image

Java does not read the operating system trust store. It reads `cacerts` inside the JDK, so the import has to target that file specifically. `keytool` ships in every Eclipse Temurin image, JRE and JDK alike, so nothing extra needs installing.

The `COPY` source is relative to the build context. The `keycloak` service in this repository builds with `local-dev/auth` as its context, which is why the path below starts at `certificates/`. Adjust it to whatever your own service's `context` is, and make sure that context actually contains the certificate.

```dockerfile
COPY certificates/localhost/localhost-ca.crt /tmp/localhost-ca.crt

RUN keytool -delete -alias localhost-ca -cacerts -storepass changeit || true && \
    keytool -importcert -file /tmp/localhost-ca.crt -cacerts -storepass changeit -alias localhost-ca -noprompt
```

The delete before the import is what makes the line safe to run twice, which is what keeps a rebuild idempotent. `keytool -importcert` refuses an alias that already exists, so against a base image that already carries an older copy of this authority the import on its own would fail the build. The `|| true` covers the opposite case, where there is nothing to delete and `keytool` exits non-zero saying exactly that:

```text
keytool error: java.lang.Exception: Alias <localhost-ca> does not exist
```

`changeit` is the stock password on every JDK's `cacerts` file. It is not a secret and there is nothing to rotate.

Measured on both `eclipse-temurin:21-jre-alpine` and `eclipse-temurin:21-jdk-alpine`. Without the import, an `HttpsURLConnection` from inside the container to `https://keycloak.test:9443/realms/local/.well-known/openid-configuration` never gets a response:

```text
Exception in thread "main" javax.net.ssl.SSLHandshakeException: (certificate_unknown) PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
```

With those two Dockerfile lines, the same request, with no `-Djavax.net.ssl.trustStore` and no other flag:

```text
STATUS 200
BODY {"issuer":"https://keycloak.test:9443/realms/local","authorization_end
```

#### An image that is not a JVM

Everything else goes through the operating system trust bundle inside the container, which is a `COPY` into the distribution's anchor directory followed by the command that rebuilds the bundle.

| Base | Where the certificate goes | Command that rebuilds the bundle |
| --- | --- | --- |
| Debian, Ubuntu | `/usr/local/share/ca-certificates/localhost-ca.crt` | `update-ca-certificates` |
| Alpine | `/usr/local/share/ca-certificates/localhost-ca.crt` | `apk add --no-cache ca-certificates && update-ca-certificates` |
| Red Hat, Fedora, UBI | `/etc/pki/ca-trust/source/anchors/localhost-ca.crt` | `update-ca-trust` |

The Debian and Alpine rows were measured against a running Keycloak. The Red Hat row was not, and is the documented mechanism rather than a proven one.

That bundle covers anything built on OpenSSL, which includes `curl`, `wget` and Python's standard library. Two common runtimes ignore it, and were measured ignoring it, so on those the Dockerfile also sets the variable the runtime does read. Setting it with `ENV` rather than in the compose file is the whole point: the image stays self-sufficient.

Node keeps its own compiled-in list of roots. With the Alpine bundle rebuilt and no variable set, `fetch` still refuses:

```text
ERROR fetch failed / unable to verify the first certificate
```

So a Node image needs both halves:

```dockerfile
COPY certificates/localhost/localhost-ca.crt /usr/local/share/ca-certificates/localhost-ca.crt

RUN apk add --no-cache ca-certificates && update-ca-certificates

ENV NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/localhost-ca.crt
```

Python splits in two. The standard library asks OpenSSL for the system default and works off the rebuilt bundle alone, measured returning `STATUS 200` on `python:3.12-slim` with both certificate variables explicitly emptied. The `requests` library carries its own store through `certifi` and does not:

```text
ERROR SSLError HTTPSConnectionPool(host='keycloak.test', port=9443): Max retries exceeded with url: /realms/local/.well-known/openid-co
```

So a Python image that uses `requests` needs the variable as well:

```dockerfile
COPY certificates/localhost/localhost-ca.crt /usr/local/share/ca-certificates/localhost-ca.crt

RUN update-ca-certificates

ENV REQUESTS_CA_BUNDLE=/usr/local/share/ca-certificates/localhost-ca.crt
```

#### An image you do not build

Mounting is the fallback, not the default. When a service runs a third-party image there is no Dockerfile to add a `COPY` to, so bind mount the certificate read-only and set whichever variable that runtime reads:

```yaml
services:
  your-service:
    extra_hosts:
      - "keycloak.test:host-gateway"
    volumes:
      - ./local-dev/auth/certificates/localhost/localhost-ca.crt:/certs/localhost-ca.crt:ro
    environment:
      - NODE_EXTRA_CA_CERTS=/certs/localhost-ca.crt
```

Swap the environment variable for `REQUESTS_CA_BUNDLE`, `SSL_CERT_FILE`, or the two `javax.net.ssl` system properties depending on what the image actually runs. The cost of this shape is that the trust configuration now lives in the compose file rather than in the image, so anything that starts the same image outside this stack starts it untrusting.

### Trust the authority when you run the application directly

---

Everything above is about an image. When the application runs on the machine instead, started from an IDE run configuration, from `./gradlew bootRun`, or from a plain `node` or `python` command, there is no build step to hang the import off, so the runtime has to be pointed at the authority instead. Every command below was run against a real `https://keycloak.test:9443`, first with nothing pointed at the root to show the rejection, then again with the root in place to show it working.

#### Java Virtual Machine applications

Every JVM keeps its own trust store, a keystore file in the JKS format, and by default that file is the only place
its trust manager looks. That is a default rather than a hard limit. On Windows,
`-Djavax.net.ssl.trustStoreType=Windows-ROOT` switches the trust manager to the SunMSCAPI provider, which reads the
Windows certificate store directly, so a root already imported there needs no truststore file at all. That switch
is Windows only, and everything measured below uses the truststore file, which behaves the same on every platform.
Proven against Keycloak's own admin client, `kcadm.sh`, which is itself a JVM program and ships inside the Keycloak
container. With TLS verification on and nothing pointed at the root, logging in over HTTPS fails before it reaches
Keycloak at all:

```text
Logging into https://keycloak.test:9443 as user admin of realm master
Failed to send request - (certificate_unknown) PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
```

Build a truststore from the root certificate authority. Where that file lands is your choice, and the home
directory below is only a placeholder: the truststore belongs next to the application that loads it, not in this
repository. Nothing in [.gitignore](../../.gitignore) matches a `.jks`, so a truststore written into the checkout
turns up as an untracked file in every `git status` from then on.

```bash
keytool -importcert -noprompt -trustcacerts -alias localhostca -file ./local-dev/auth/certificates/localhost/localhost-ca.crt -keystore "$HOME/localhost-ca.truststore.jks" -storepass changeit
```

```powershell
keytool -importcert -noprompt -trustcacerts -alias localhostca -file .\local-dev\auth\certificates\localhost\localhost-ca.crt -keystore "$env:USERPROFILE\localhost-ca.truststore.jks" -storepass changeit
```

Point the application at it with the two system properties every JVM's default trust manager reads:

```bash
java -Djavax.net.ssl.trustStore="$HOME/localhost-ca.truststore.jks" -Djavax.net.ssl.trustStorePassword=changeit -jar your-app.jar
```

```powershell
java -Djavax.net.ssl.trustStore="$env:USERPROFILE\localhost-ca.truststore.jks" -Djavax.net.ssl.trustStorePassword=changeit -jar your-app.jar
```

A Spring Boot application started through an IDE run configuration, `./gradlew bootRun`, or `mvn spring-boot:run`
reads the same two properties as JVM arguments. With that truststore in place, the same login against the same
Keycloak succeeds:

```text
Logging into https://keycloak.test:9443 as user admin of realm master
```

Recommendation: build a truststore scoped to this one application rather than importing the root into the JVM's
own shared `cacerts` file. `cacerts` is used by every application that runs under that JVM installation, so
importing a local development root into it trusts that authority for anything else on the machine that happens to
share the JVM, and a JVM upgrade replaces `cacerts` with a fresh one carrying only the public authorities the
distribution ships, so the import has to be repeated on every upgrade. A dedicated truststore file, referenced only
by this one application's own launch configuration, stays scoped to the thing that actually needs it. Neither
objection applies inside a container image, where the JVM is shared with nothing and an upgrade means a rebuild,
which is why the build-time section above writes straight into `cacerts`.

The alternative, importing straight into `cacerts`, is proven to work as well, using the same root certificate:

```bash
keytool -importcert -noprompt -trustcacerts -alias localhostca -file ./local-dev/auth/certificates/localhost/localhost-ca.crt -keystore "$JAVA_HOME/lib/security/cacerts" -storepass changeit
```

```powershell
keytool -importcert -noprompt -trustcacerts -alias localhostca -file .\local-dev\auth\certificates\localhost\localhost-ca.crt -keystore "$env:JAVA_HOME\lib\security\cacerts" -storepass changeit
```

#### Node.js

Node reads the `NODE_EXTRA_CA_CERTS` environment variable at startup and adds whatever certificate it points at to
its built-in trust store, on top of the certificates Node ships with rather than instead of them. Proven with a
throwaway Node container on the same Docker network as Keycloak. Without the variable, the request fails inside
the process rather than returning a response:

```text
ERROR fetch failed
CAUSE unable to verify the first certificate
```

Set the variable to the root certificate authority and the same request succeeds:

```bash
export NODE_EXTRA_CA_CERTS=./local-dev/auth/certificates/localhost/localhost-ca.crt
```

```bash
node your-app.js
```

```powershell
$env:NODE_EXTRA_CA_CERTS = ".\local-dev\auth\certificates\localhost\localhost-ca.crt"
```

```powershell
node your-app.js
```

```text
STATUS 200
```

#### Python

The two most common HTTP layers in Python read different environment variables, and mixing them up is the usual
mistake. The `requests` library reads `REQUESTS_CA_BUNDLE`, because it carries its own bundled certificate store
(`certifi`) rather than asking OpenSSL for the system default. The standard library, meaning `urllib.request` and
anything built on the `ssl` module directly, reads `SSL_CERT_FILE` instead. `REQUESTS_CA_BUNDLE` has no effect on
standard library code, and `SSL_CERT_FILE` has no effect on `requests`.

Both were proven the same way, against the same Keycloak, from a throwaway Python container. `requests` without
the variable set:

```text
ERROR SSLError HTTPSConnectionPool(host='keycloak', port=9443): Max retries exceeded with url: /realms/local/.well-known/openid-configuration (Caused by SSLError(SSLCertVerificationError(1, '[SSL: CERTIFICATE_VERIFY
```

With `REQUESTS_CA_BUNDLE` pointed at the root:

```bash
export REQUESTS_CA_BUNDLE=./local-dev/auth/certificates/localhost/localhost-ca.crt
```

```bash
python your-app.py
```

```powershell
$env:REQUESTS_CA_BUNDLE = ".\local-dev\auth\certificates\localhost\localhost-ca.crt"
```

```powershell
python your-app.py
```

```text
STATUS 200
```

The standard library, without `SSL_CERT_FILE` set:

```text
ERROR URLError <urlopen error [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: unable to get local issuer certificate (_ssl.c:1010)>
```

With `SSL_CERT_FILE` pointed at the root:

```bash
export SSL_CERT_FILE=./local-dev/auth/certificates/localhost/localhost-ca.crt
```

```bash
python your-app.py
```

```powershell
$env:SSL_CERT_FILE = ".\local-dev\auth\certificates\localhost\localhost-ca.crt"
```

```powershell
python your-app.py
```

```text
STATUS 200
```

#### curl

`curl --cacert <file>` points curl at a certificate to build and verify the chain against instead of whatever store
curl would otherwise use. On plain Linux and inside WSL that is the whole answer, proven with the same root against
the same Keycloak. macOS has no measurement here, but its curl does not use Schannel either, so the plain form is
the one to reach for there too:

```bash
curl --cacert ./local-dev/auth/certificates/localhost/localhost-ca.crt https://keycloak.test:9443/realms/local/.well-known/openid-configuration
```

From Git Bash on Windows the same command fails, and not for the reason it first looks like:

```text
curl: (60) schannel: the revocation status is unknown
```

That build reports its TLS backend as Schannel in `curl --version`, which is Windows' own TLS library, and the
error is the evidence that Schannel did read the file. Nothing can ask whether a certificate has been revoked
before a chain has been built, and a chain was built here. What curl could not do next was answer the revocation
question, because the leaf carries neither a CRL distribution point nor an OCSP responder, which is normal for a
certificate signed by a local authority that publishes neither. So the status is unknown rather than revoked, and
on the code path `--cacert` selects, curl treats unknown as a failure unless you tell it not to.

Two flags tell it not to, and both were measured returning HTTP 200 against the same Keycloak. Prefer
`--ssl-revoke-best-effort`, which the [curl manual](https://curl.se/docs/manpage.html) describes as ignoring
revocation checks "when they failed due to missing/offline distribution points for the revocation check lists".
That is exactly this case, and it leaves the check in place otherwise. `--ssl-no-revoke` disables revocation
checking altogether, which the same manual flags as loosening security. Both are marked Schannel-only, so leave
them off the Linux and macOS command.

Git Bash:

```bash
curl --cacert ./local-dev/auth/certificates/localhost/localhost-ca.crt --ssl-revoke-best-effort https://keycloak.test:9443/realms/local/.well-known/openid-configuration
```

PowerShell:

```powershell
curl.exe --cacert .\local-dev\auth\certificates\localhost\localhost-ca.crt --ssl-revoke-best-effort https://keycloak.test:9443/realms/local/.well-known/openid-configuration
```

Write `curl.exe` rather than `curl` in PowerShell. Windows PowerShell 5.1 aliases `curl` to `Invoke-WebRequest`,
which has none of these flags.

Two controls, run from the same Git Bash against the same Keycloak, are what rule out the alternative reading that
the file is ignored.

Point `--cacert` at an unrelated throwaway authority so the chain genuinely cannot be built, and the failure names
the chain instead of revocation, with or without either revocation flag:

```text
curl: (60) schannel: the certificate chain is incomplete
```

Drop `--cacert` and curl falls back on Schannel's own trust decision, which on a machine that has not imported the
root fails on trust and never reaches the revocation question:

```text
curl: (60) schannel: SEC_E_UNTRUSTED_ROOT (0x80090325) - The certificate chain was issued by an authority that is not trusted.
```

That last error is the one the optional operating system import below removes, and it is the alternative to reach
for if you would rather not carry a flag around. With the root in the Windows certificate
store there is no `--cacert` to pass, so curl never enters the chain verification that raises the revocation
question in the first place. The Windows certificate store held no copy of this root for any measurement above,
checked by subject and by thumbprint in `Cert:\LocalMachine\Root` and `Cert:\CurrentUser\Root`, so nothing in the
machine's own trust state contributed to these results.

### Trust the authority in your operating system (optional)

---

Optional, and it changes only what you see. Importing the authority into the operating system trust store stops the browser warning on `https://keycloak.test:9443` and satisfies any tool that reads the operating system's own certificate store. It does not make a single service to service call succeed that was failing before, because Java reads `cacerts` inside the JDK and Node reads its own compiled-in list, and neither of them consults the operating system at all.

So these are two independent decisions and only one of them is required. Each image importing the authority at build time is what makes the stack work, and it happens on its own with no developer action. The operating system import is one command, affects nothing but the developer's own view, and can be skipped entirely by clicking through the browser warning.

Steps are in [Keycloak/README.md](./Keycloak/README.md) under "Certificate in the operating system trust store (optional)".
