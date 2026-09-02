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

The Keycloak container expects a cert + key under
[certificates/localhost/](./certificates/localhost/). Those two files are a leaf certificate signed by a local
root certificate authority that also lives in that directory. Importing the root into your OS trust store once, as
described under "Trust the cert on your machine" below, covers this leaf and any future leaf signed by the same
root, with no further import needed. The root private key, `localDevCA.key`, is committed to this repository on
purpose, because this authority exists only for local development on machines the owner controls.

Regenerate the pair with openssl, from the project root, in three steps.

Create the root key and its self-signed certificate. Skip this step if `localDevCA.key` and `localDevCA.crt`
already exist and only the leaf needs regenerating.

```bash
openssl req -x509 -new -nodes -days 3650 -keyout ./local-dev/auth/certificates/localhost/localDevCA.key -out ./local-dev/auth/certificates/localhost/localDevCA.crt -config ./local-dev/auth/certificates/localhost/localDevCA.cnf
```

Create the leaf key and its certificate signing request:

```bash
openssl req -new -nodes -keyout ./local-dev/auth/certificates/localhost/localhostDomain.key -out ./local-dev/auth/certificates/localhost/localhostDomain.csr -config ./local-dev/auth/certificates/localhost/localhost.cnf
```

Sign the request with the root, then remove the request, which is not needed once the certificate exists:

```bash
openssl x509 -req -in ./local-dev/auth/certificates/localhost/localhostDomain.csr -CA ./local-dev/auth/certificates/localhost/localDevCA.crt -CAkey ./local-dev/auth/certificates/localhost/localDevCA.key -CAcreateserial -out ./local-dev/auth/certificates/localhost/localhostDomain.crt -days 3650 -extfile ./local-dev/auth/certificates/localhost/localhost.cnf -extensions leaf_ext
```

```bash
rm ./local-dev/auth/certificates/localhost/localhostDomain.csr
```

The root's distinguished name and CA extensions live in
[certificates/localhost/localDevCA.cnf](./certificates/localhost/localDevCA.cnf). The leaf's CN, SAN entries, and
extensions live in [certificates/localhost/localhost.cnf](./certificates/localhost/localhost.cnf). Edit the leaf
file before regenerating if you need to add another local domain to the SAN list, then run the last two commands
above again, the root does not need to change.

Expected output: `localDevCA.key` and `localDevCA.crt` from the first command, `localhostDomain.key` and a
`localhostDomain.csr` from the second, and `localDevCA.srl` and `localhostDomain.crt` from the third. The CSR is
removed by the command right after it, so only the two key and certificate pairs and the serial file remain,
alongside the two `.cnf` files.

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
