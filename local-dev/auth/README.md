# Local Auth

> A local certificate authority + hosts entries for running Keycloak under `https://keycloak:9443` on the local machine.

---

### Hosts setup

---

Point `keycloak` and `keycloak.test` at the loopback so the certificate's CN matches when browsers and clients
connect.

Append these two lines to your hosts file:

```text
127.0.0.1 keycloak
127.0.0.1 keycloak.test
```

Linux path: [/etc/hosts](file:///etc/hosts) (needs `sudo`).

Windows path: `C:\Windows\System32\drivers\etc\hosts` (needs an Administrator editor).

For Keycloak setup, container build, realm import, and troubleshooting, see
[Keycloak/README.md](./Keycloak/README.md).

### Certificate generation

---

#### Localhost (local certificate authority) <a id="localhost"></a>

Nothing here is self-signed. A local certificate authority signs a leaf, and Keycloak serves the leaf. That split is
what makes the trust import a one-time job: import the authority into a trust store once, as described under "Trust
the cert on your machine" and "Trust the cert from application code" below, and it covers this leaf and every future
leaf the same authority signs. A self-signed leaf would have to be re-imported everywhere on every reissue.

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
Reissuing the authority costs that plus a re-import in every trust store that holds it: the operating system store,
and any JVM, Node or Python trust store set up from the sections below. To reissue the leaf alone, run the second and
third `openssl` commands inside the script and skip the first, then run its `rm` line as well: signing writes a
serial file, `localhost-ca.srl`, which this repository deliberately does not track.

`localhost-ca.crt`, `localhost-ca.key`, `localhost.crt` and `localhost.key` are the result. The authority's
distinguished name and its CA extensions live in [certificates/localhost/ca.cnf](./certificates/localhost/ca.cnf),
the leaf's common name, SAN entries and extensions in
[certificates/localhost/leaf.cnf](./certificates/localhost/leaf.cnf). The authority's private key,
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

### Trust the cert on your machine

---

Importing the root certificate authority into the OS trust store stops browsers and HTTP clients from rejecting
the certificates it signs. Steps are in [Keycloak/README.md](./Keycloak/README.md) under "Certificate".

### Trust the cert from application code

---

The OS trust store import above fixes browsers and any tool that reads the operating system's own certificate
store. It does nothing for a runtime that keeps a separate trust store of its own, or that reads a certificate
bundle from an environment variable instead of asking the operating system. Every command below was run against a
real `https://keycloak:9443`, first with nothing pointed at the root to show the rejection, then again with the
root in place to show it working.

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
Logging into https://keycloak:9443 as user admin of realm master
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
Logging into https://keycloak:9443 as user admin of realm master
```

Recommendation: build a truststore scoped to this one application rather than importing the root into the JVM's
own shared `cacerts` file. `cacerts` is used by every application that runs under that JVM installation, so
importing a local development root into it trusts that authority for anything else on the machine that happens to
share the JVM, and a JVM upgrade replaces `cacerts` with a fresh one carrying only the public authorities the
distribution ships, so the import has to be repeated on every upgrade. A dedicated truststore file, referenced only
by this one application's own launch configuration, stays scoped to the thing that actually needs it.

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
curl --cacert ./local-dev/auth/certificates/localhost/localhost-ca.crt https://keycloak:9443/realms/local/.well-known/openid-configuration
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
curl --cacert ./local-dev/auth/certificates/localhost/localhost-ca.crt --ssl-revoke-best-effort https://keycloak:9443/realms/local/.well-known/openid-configuration
```

PowerShell:

```powershell
curl.exe --cacert .\local-dev\auth\certificates\localhost\localhost-ca.crt --ssl-revoke-best-effort https://keycloak:9443/realms/local/.well-known/openid-configuration
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

That last error is the one the operating system import under "Trust the cert on your machine" removes, and it is
the alternative to reach for if you would rather not carry a flag around. With the root in the Windows certificate
store there is no `--cacert` to pass, so curl never enters the chain verification that raises the revocation
question in the first place. The Windows certificate store held no copy of this root for any measurement above,
checked by subject and by thumbprint in `Cert:\LocalMachine\Root` and `Cert:\CurrentUser\Root`, so nothing in the
machine's own trust state contributed to these results.

#### A container in the compose stack

Getting the root into another container that needs to reach Keycloak over HTTPS is the same shape as the Node and
Python cases above, and was proven the same way: bind mount the root certificate file into the container
read-only, and point the runtime's own environment variable at that path, exactly as documented for that runtime
above. There is nothing compose-specific about it beyond making sure the new service is on the same network as
`keycloak`.

For a Compose service definition, the shape is a `volumes` entry plus an `environment` entry, using whichever
variable the service's own runtime reads:

```yaml
services:
  your-service:
    volumes:
      - ./local-dev/auth/certificates/localhost/localhost-ca.crt:/certs/localhost-ca.crt:ro
    environment:
      - NODE_EXTRA_CA_CERTS=/certs/localhost-ca.crt
```

Swap the environment variable for `REQUESTS_CA_BUNDLE`, `SSL_CERT_FILE`, or the two `javax.net.ssl` system
properties depending on what the service actually runs. Mount the certificate at runtime rather than baking it into
the image with a `COPY`, so the same image works unchanged if the certificate is ever regenerated.
