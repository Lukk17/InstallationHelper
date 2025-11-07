## Authorization and Authentication

---
Keycloak is a service covering user authentication and authorization.  
More about it [here](./Keycloak/README.md)

---
### OS hosts setup

Add 
```
127.0.0.1 keycloak
127.0.0.1 keycloak.test
```
to the end of machine hosts
Linux `/etc/hosts`
Windows `C:\Windows\System32\drivers\etc\hosts)`

---

### Certificate generation <a name="certificate-generation"></a>

#### Localhost <a name="localhost"></a>

Generate a self-signed certificate using openssl and `localhost.cnf`  
Terminal in PharmacyCloud project root:
```shell
  openssl req -x509 -nodes -days 3650 -key ./local-dev/auth/certificates/localhost/localhostDomain.key -out ./local-dev/auth/certificates/localhost/localhostDomain.crt -config ./local-dev/auth/certificates/localhost/localhost.cnf -extensions req_ext
```
In file `localhost.cnf` all required information for certificate generation

`localhostDomain.crt  localhostDomain.key` files should be created

#### Production <a name="production"></a>
Using certbot (which is using Let's Encrypt) - Linux or WSL

```shell
  sudo apt install certbot
```
```shell
   sudo certbot certonly --standalone
```
Convert the PEM-format certificates to JKS  
(CHANGE YOUR_DOMAIN AND ALIAS)
```shell
   sudo openssl pkcs12 -export -in /etc/letsencrypt/live/your_domain/fullchain.pem -inkey /etc/letsencrypt/live/your_domain/privkey.pem -out pkcs.p12 -name your_alias -CAfile /etc/letsencrypt/live/your_domain/chain.pem -caname root
```
```shell
  sudo keytool -importkeystore -deststorepass your_keystore_password -destkeypass your_key_password -destkeystore keystore.jks -srckeystore pkcs.p12 -srcstoretype PKCS12 -srcstorepass your_p12_password -alias your_alias
```
