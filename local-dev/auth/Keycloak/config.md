## Keycloak Configuration and first time run

**Table of Contents**

* [First Run](#first-run)
* [Realm Configuration](#realm-config)
   * [Creating a Realm](#creating-realm)
   * [Creating a User](#creating-user)
   * [Setting a Password](#set-password)
   * [Creating a Role](#creating-role)
   * [Assigning a Role](#assign-role)
   * [Verifying Account Console Login](#verifying-account-console-login)
   * [Securing Your Application](#secure-application)
   * [Configuration Page](#config-page)
* [Keycloak Database Dump](#keycloak-database-dump)
* [Exporting Configuration](#export-config)
   * [Export Contents](#export-contents)

---
### First Run

Run postgres and create `keycloak` database.

The first time you need to give it initial admin credential to create an account:
```shell
    docker run -d -p 9443:9443 -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=admin keycloak-local 
```

```shell
  docker run -d --name keycloak-local -p 9443:9443 -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=admin -e KC_DB=postgres -e KC_DB_URL=jdbc:postgresql://host.docker.internal:5432/keycloak -e KC_DB_USERNAME=postgres -e KC_DB_PASSWORD=local -e KC_HOSTNAME=keycloak.test -e KC_HOSTNAME_PORT=9443 -e KC_HOSTNAME_STRICT=false -e KC_HOSTNAME_STRICT_HTTPS=false --add-host="keycloak.test:host-gateway" keycloak-local:latest --https-certificate-file=/etc/x509/https/localhost.crt --https-certificate-key-file=/etc/x509/https/localhostCert.key --https-port=9443
```

---

### Realm config

#### Creating realm
1. Open the Keycloak Admin Console.
   https://localhost:9443/admin
   http://localhost:9080/admin
2. Click the word master in the top-left corner, then click Create realm.
3. Enter `local` in the Realm name field.
4. Click `Create`.

#### Creating user
1. Click `Users` in the left-hand menu.
2. Click `Create new user`.
3. Fill in the form with the following values:
   Username: `lukk`  
   Email: `lukk@test.com`  
   First name: `Lukk`  
   Last name: `Songo`
4. Click `Create`.

#### Set password
1. Click `Credentials` at the top of the page.
2. Fill in the `Set password` form with `test1234`.
3. Toggle `Temporary` to `Off` so that the user does not need to update this password at the first login.

#### Creating Role
1. Click `Realm roles` in the left-hand menu.
2. Click `Create role`.
3. Enter the role name: for Spring use `ROLE_USER`.
4. Click `Save`

#### Assign Role
1. Click `Users` in the left-hand menu
2. Locate the created user
3. Click on the user to open their details
4. Go to `Role mapping` tab
5. Click `Assign role`
6. Click on `Filter by client` and from dropdown select `Filter by real roles`
7. Select `ROLE_USER` and click `Assign`

#### Verifying Account Console Login
1. Go to:
   `https://localhost:9443/realms/local/account`
2. log in using a created account (`lukk`:`test1234`)

#### Secure application
1. Open the Keycloak Admin Console.
2. Choose `local` realm (important!)
3. Click `Clients`.
4. Click `Create client`
5. Fill in the form with the following values:
6. Client type: `OpenID Connect`
7. Client ID: `local-client`
8. Click Next
9. Confirm that `Client authentication` and `Authorization` are enabled.
10. Confirm that `Standard flow` and `Direct access grants` are enabled.
11. Click Next
12. Root URL: `http://localhost:8888`
13. Valid Redirect URIs: `http://localhost:8888/login/oauth2/code/keycloak`
14. Click Save.

After the client is created, make these updates to the client:
1. Go to `Credential` tab (visible only if Client authentication is enabled)
2. Copy Client Secret into Spring Cloud Gateway configuration YAML or any other client like Postman.


#### Config Page
1. Login to Admin Console
2. Choose `local` realm (important!)
3. Go to `Realm settings`
4. Click on `OpenID Endpoint Configuration` it probably will open page like:
   https://localhost:9443/realms/local/.well-known/openid-configuration
   There is JSON with realm config like issuer address used as `issuer-uri` in services config
   This issuer should look like `https://localhost:9443/realms/local`

---

### Keycloak Database Dump

```powershell
<pathToPostgres>/pg_dump.exe --dbname=keycloak --file=<exportPath>/keycloak-dump.sql --username=postgres --host=localhost --port=5432
```
where:  
<pathToPostgres> - installation path of Postgres, example `D:/Development/SDK/PostgreSQL/16/bin`  
<exportPath> - path where to save dump, example `C:/Users/Lukk/Desktop`  

or inside postgres docker:
```shell
pg_dump --dbname=keycloak --username=postgres --host=localhost --port=5432 > /tmp/keycloak-dump.sql
```

for local postgres password for default user is `local`

---
### Export config

### via terminal
Selected realm export
```shell
/opt/keycloak/bin/kc.sh export --realm pharma --file /tmp/pharma-realm-export.json
```
full export
```shell
/opt/keycloak/bin/kc.sh export --file /tmp/full-export.json
```

then if docker has local discs mounted:
```shell
cp /tmp/realm-export.json /mnt/c/tmp/
```
if not in docker desktop if you click on keycloak container there is tab `Files`.  
Right-click on file in a file tree and click `Save` popup will open asking where to save it. 

#### Via UI (partial export) 
1. Go to your realm: In the Keycloak Admin Console, select the realm you want to export ("pharma" in your case).
2. Realm settings: Click on the "Realm Settings" tab.
3. Export: Click the "Export" button.
   Options:
   Format: Choose "JSON".
   Include users: Check this box if you want to include user data (usernames, but not passwords, which are securely stored) in the export.
   Include client secrets: Check this to include client secrets. Be very careful with this option, as client secrets should be kept confidential.
4. Download: Click "Download" to save the export as a JSON file (e.g., realm-export.json).


#### Export contents
Export include:
1. Realm settings: General settings, login themes, email settings, etc.
2. Clients: Client IDs, redirect URIs, and other client configurations.
3. Roles: Realm roles and client roles.
4. Groups: Group definitions and memberships.
5. Users: Usernames, email addresses, and other user attributes (if "Include users" is selected). Passwords are NOT included in the export for security reasons.
6. Identity providers: Configurations for external identity providers (if any).
7. Other settings: Various other realm-specific configurations.

---
[Certificate Generation](../README.md#certificate-generation)
