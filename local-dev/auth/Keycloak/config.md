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

### Export config

The `local` realm is seeded from exactly one file,
[export/config/local-realm-export.json](./export/config/local-realm-export.json). The Keycloak Dockerfile copies it
into `/opt/keycloak/data/import/` and the entrypoint runs `kc.sh start --optimized --import-realm`, so Keycloak
imports it on the first boot against an empty `keycloak` database. It is a real `kc.sh export` of the running realm,
so it carries the client `local-client` with its secret and the user `lukk` with a password credential, and it is
readable and reviewable in a way the 302 kilobyte database dump it replaced never was.

The import happens only when the realm is absent. On a machine whose `postgres_data` volume already holds `local`,
Keycloak logs that the realm exists and skips the import, so editing this file changes nothing until the volume is
removed or the clone is fresh.

One thing had to be taken out of the realm before it could be imported at all, and it will come back if you export
carelessly. `local-client` carried a JavaScript authorization policy called `Default Policy`, whose whole body is
`$evaluation.grant()`, together with a `Default Permission` that applied it. Older Keycloak created that trio
automatically when you ticked Authorization on a client. Keycloak 26.5 refuses to import it and stops the whole
startup with `ERROR: Script upload is disabled`, so a realm carrying it can only ever be smuggled in at the SQL level,
which is exactly what the database dump was doing. Measured on 26.5 through the admin API, creating a client with
authorization services enabled now produces an empty resource server, no default resource, no default policy and no
default permission, so the trio is a leftover rather than something the current version wants.

Both objects were deleted from the live realm through Keycloak's own admin CLI and the realm was exported again, so
the committed file is a real export and not a hand-edited one. The `Default Resource` was left alone, because nothing
referenced it once the permission was gone.

The catch is that a machine whose `postgres_data` volume predates this change still holds the JavaScript policy, since
`--import-realm` never touched an existing realm. Export from such a machine and you commit the policy straight back,
and the next fresh clone dies on startup rather than failing quietly. Check before you commit an export:

```bash
grep -c '"type" : "js"' ./local-dev/auth/Keycloak/export/config/local-realm-export.json
```

```powershell
Select-String -Pattern '"type" : "js"' -Path .\local-dev\auth\Keycloak\export\config\local-realm-export.json | Measure-Object | Select-Object -ExpandProperty Count
```

Anything other than zero means delete `Default Permission` and then `Default Policy` under Authorization on
`local-client` in the admin console, and export again.

The spaces around the colon are not a typo. `kc.sh export` writes `"type" : "js"`, so the pattern without them matches
nothing and quietly answers zero on a file that does carry the policy. Both patterns were run against the export taken
before the fix: the spaced one answers 1 there and 0 here, the unspaced one answers 0 in both places and is therefore
useless.

Regenerate the file whenever you change the realm through the admin console, otherwise the next fresh clone gets the
old realm. Two flags matter and both were measured.

`--users same_file` is not optional. The default is `different_files`, which writes users into separate files next to
the target and is rejected outright when the target is a single file: `Property '--users' can be used only when
exporting to a directory, or value set to 'same_file' when exporting to a file.` Without users in the file, the import
produces a realm with a working client and nobody to log in as.

`--http-management-port 9001` exists only to keep the exit code honest. The export runs a second Keycloak process
inside the container while the first one is still serving, and both want the management port 9000. The export itself
finishes and writes the file either way, `KC-SERVICES0035: Export finished successfully` appears before the clash,
but without the flag the command ends on `Address already in use` and exits non-zero, which no script can distinguish
from a failed export. With the flag it exits 0 and the two files are byte for byte identical, verified by `md5sum`.

Run it against the running container. On Ubuntu, Arch Linux, macOS, WSL and PowerShell:

```shell
docker exec keycloak /opt/keycloak/bin/kc.sh export --optimized --realm local --users same_file --http-management-port 9001 --file /tmp/local-realm-export.json
```

Git Bash on Windows needs the path rewriting switched off, because MSYS treats every argument that starts with a
slash as a Windows path and rewrites the one inside the container. Without the prefix the command fails with
`stat C:/Program Files/Git/opt/keycloak/bin/kc.sh: no such file or directory`, which names a path nobody wrote:

```bash
MSYS_NO_PATHCONV=1 docker exec keycloak /opt/keycloak/bin/kc.sh export --optimized --realm local --users same_file --http-management-port 9001 --file /tmp/local-realm-export.json
```

Copy it back over the committed one. From a Unix shell at the project root:

```bash
docker cp keycloak:/tmp/local-realm-export.json ./local-dev/auth/Keycloak/export/config/local-realm-export.json
```

From PowerShell at the project root:

```powershell
docker cp keycloak:/tmp/local-realm-export.json .\local-dev\auth\Keycloak\export\config\local-realm-export.json
```

Then rebuild the image, because the file is baked in rather than mounted.

There used to be a second file here, `full-export.json`, produced by `kc.sh export` with no `--realm`. It is gone. It
described the `master` realm plus a second, contradictory copy of `local` carrying a `pharmaApp-client` that this
stack has never had, and once a true export of `local` exists, a second description of the same realm sitting beside
it is a trap rather than a reference. Take a full export if you ever need one, do not commit it next to the file the
image imports.

#### Via UI (partial export)

Use this to look at a realm, never to produce the file the image imports. The admin console export is a partial
export: it is documented as writing a row of asterisks in place of every client secret, and it carries no password
credentials at all. That side was not measured here, only the `kc.sh export` side was, so treat it as the reason to
reach for the command above rather than as a measurement. A realm rebuilt from a console export would come up with a
`local-client` whose secret does not match the one in [README.md](./README.md) and a `lukk` nobody can log in as.

1. Go to your realm: In the Keycloak Admin Console, select the realm you want to export (`local` in this stack).
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
5. Users: usernames, email addresses, and other user attributes when users are included. What happens to their passwords depends on which export you ran, and the difference is the whole reason this stack uses the command and not the console. A `kc.sh export` with `--users same_file` carries each credential as its stored hash, a `secretData` and `credentialData` pair rather than the plain password, which is measured in the committed file for `lukk` and is what lets that user log in on a fresh clone. The console's partial export carries no credential at all.
6. Identity providers: Configurations for external identity providers (if any).
7. Other settings: Various other realm-specific configurations.

---
[Certificate Generation](../README.md#certificate-generation)
