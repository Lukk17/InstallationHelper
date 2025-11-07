# Keycloak - authentication service

---
### Build

Remember to change tag from `latest` 😄  
Command must be executed from project root folder of one in which is Dockerfile.

```shell
  docker build -f ./local-dev/auth/Keycloak/Dockerfile -t keycloak-local:latest ./local-dev/auth 
```
without a cache:
```shell
  docker build --no-cache -f ./local-dev/auth/Keycloak/Dockerfile -t keycloak-local:latest ./local-dev/auth
```
---
### Run
Import postgres SQL dump if for the first time:
```shell
  psql -U postgres -h localhost -p 5432 -d keycloak -f ./local-dev/auth/Keycloak/export/database/keycloak-dump.sql
```

Run docker - make sure to use correct docker tag !
```shell
  docker run -d --name keycloak -p 9443:9443 local-keycloak:latest
```

---
### Getting Token

```shell
curl --location 'https://keycloak:9443/realms/local/protocol/openid-connect/token' --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode 'grant_type=password' --data-urlencode 'client_id=local-client' --data-urlencode 'client_secret=nZUMlOQZufa5ljWW5hHXOtGKLn0mpTkN' --data-urlencode 'scope=openid profile email' --data-urlencode 'username=lukk' --data-urlencode 'password=test1234'
```

---
### Certificate
As for local development we have self-signed certificate (in folder `certificates/localhost`).

To import them to a local machine so it will be trusted on a local machine (required for clients and browser login)
Commands needs to be run from the project root directory in the terminal.  

#### Windows:
```
Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -Command & { Import-Certificate -FilePath '$(Resolve-Path -Path ".\Auth\certificates\localhost\localhostDomain.crt")' -CertStoreLocation Cert:\LocalMachine\Root }"
```
This command will output the certificate's Thumbprint, which confirms the import was successful.  
To remove:
```
Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -Command & { Remove-Item -Path 'Cert:\LocalMachine\Root\YOUR_CERT_THUMBPRINT' -ErrorAction Stop }""
```

#### Linux (Ubuntu)
```
sudo cp ./Auth/certificates/localhost/localhostDomain.crt /usr/local/share/ca-certificates/
```
and
```
sudo update-ca-certificates
```

To remove:
```
sudo rm /usr/local/share/ca-certificates/localhostDomain.crt
```
and
```
sudo update-ca-certificates
```

---

### Configuration

For configuration and realm export see [CONFIG.md](CONFIG.md)

---
### Health checks

Accessible under management port `9000`  
`https://keycloak:9000/health`  
`https://keycloak:9000/health/live`  
`https://keycloak:9000/health/ready`  
`https://keycloak:9000/health/started`  

---
### Metrics
Accessible under management port `9000`

`https://keycloak:9000/metrics`

---
### Well-know endpoint

`https://keycloak:9443/realms/pharma/.well-known/openid-configuration`
