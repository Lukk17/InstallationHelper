# Local Auth

> Self-signed TLS + hosts entries for running Keycloak under `https://keycloak:9443` on the local machine.

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

#### Localhost (self-signed) <a id="localhost"></a>

The Keycloak container expects a cert + key under
[certificates/localhost/](./certificates/localhost/). Generate them with openssl, from the project root:

```bash
openssl req -x509 -nodes -days 3650 -key ./local-dev/auth/certificates/localhost/localhostDomain.key -out ./local-dev/auth/certificates/localhost/localhostDomain.crt -config ./local-dev/auth/certificates/localhost/localhost.cnf -extensions req_ext
```

The CN, SAN entries, and other certificate fields live in
[certificates/localhost/localhost.cnf](./certificates/localhost/localhost.cnf). Edit that file before regenerating
if you need to add another local domain.

Expected output: `localhostDomain.crt` and `localhostDomain.key` alongside the `.cnf`.

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

Importing the self-signed cert into the OS trust store stops browsers and HTTP clients from rejecting it. Steps are
in [Keycloak/README.md](./Keycloak/README.md) under "Certificate".
