
### local DBs in docker

Run in the terminal in the project root directory:

```
docker-compose -f ./local-dev/db-docker-compose.yaml up -d
```

#### credentials for localhost dbs

MySQL:
user
```
root
```
pass
```
Lukk1234
```

Postgres:
user
```
postgres
```
pass
```
local
```

MongoDB:
no user and no password required

---

MySQL  
https://hub.docker.com/_/mysql/tags

MongoDB  
https://hub.docker.com/_/mongo/tags

Postgres (In local-dev/postgresql/Dockerfile)  
https://hub.docker.com/_/postgres/tags

Keycloak (In local-dev/auth/Keycloak/Dockerfile)  
https://hub.docker.com/r/keycloak/keycloak/tags
