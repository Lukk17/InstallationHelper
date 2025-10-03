### PostgresSQL local

Build Dockerfile (terminal context in project root)
```shell
  docker build -f ./SpringDemo/local-dev/postgresql/Dockerfile -t local-postgres:latest . 
```
Without cache:
```shell
  docker build --no-cache -f ./SpringDemo/local-dev/postgresql/Dockerfile -t local-postgres:latest .
```
Create docker network:
```shell
   docker network create local-network
```
Run it:
```shell
  docker run -d --name local-postgres --network local-network -v postgres-data:/var/lib/postgresql/data -p 5432:5432 local-postgres:latest
```

---

### Credentials
Users:
- postgres

user have the password `local`
