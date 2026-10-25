# Agent access

> How an AI agent reaches this lab without a password: one Proxmox API token, one SSH key for the Proxmox host, the Docker VM and the router, one Syncthing API key, one Uptime Kuma API key and one Home Assistant access token, kept in a file on your own machine that only you can read.

---

### Why not a password

Agents do not type passwords into login pages. A login page is built for a person: it shows a form, may ask for a second factor, and hands back a session that expires. An agent works from a command line. It calls an API with a header or connects with `ssh`, and every service in this lab offers a credential made for exactly that.

Those credentials are also safer to hand over than a password. Each one belongs to the agent alone, so you can take it back without changing your own password. A password given to an agent is your whole account, it ends up in chat logs, and the only way to take it back is to change it everywhere you use it.

---

### What each credential allows

The Proxmox token this lab uses is an admin token. It can create, change and delete virtual machines and storage content, manage storages and SDN, create users and groups but not grant permissions, and download ISO files. Two narrower tokens are described further down as alternatives. The SSH key, the Syncthing key and the Home Assistant token always give more than read access. The Uptime Kuma key is the one credential here that can only read.

So one rule covers every credential here: the agent reads freely, asks you before any change, and waits for your yes. Before every delete it asks again, one virtual machine per yes. With the admin token, the SSH key, the Syncthing key and the Home Assistant token, the rule is all that stops a change, because the credential does not.

| Key in the file | Credential | What it allows |
|---|---|---|
| `PROXMOX_TOKEN_ID`, `PROXMOX_TOKEN_SECRET`, admin token | Proxmox API token of a user with `PVEAdmin` on `/`, and `PVEAdmin` with `AgentDownload` on the node | Everything the sentence above lists. Not the host's system settings, not rebooting the host, not permissions. What the token holds was measured and is listed under the admin token below |
| `PROXMOX_TOKEN_ID`, `PROXMOX_TOKEN_SECRET`, read only alternative | Proxmox API token with the `PVEAuditor` role | Reading nodes, virtual machines, storage and tasks. Proxmox refuses every change |
| `PROXMOX_TOKEN_ID`, `PROXMOX_TOKEN_SECRET`, edit alternative | Proxmox API token of a user with `PVEAuditor` on `/`, `PVEVMAdmin` on `/vms` and `PVEDatastoreUser` on `/storage` | Reading everything the read only alternative reads, plus every `VM.*` privilege on every virtual machine, and using space on storage. What the token can do was measured and is listed under the edit alternative below |
| `PROXMOX_SSH`, `HOMELAB_SSH_KEY` | SSH key for `root` on the Proxmox host | Everything on the host: every virtual machine, every disk, the host's own settings and a reboot |
| `DOCKER_VM_SSH`, `HOMELAB_SSH_KEY` | SSH key for your login on the Docker VM | Everything your login can do. Your login is in the `docker` group from [proxmox_docker_vm.md](proxmox_docker_vm.md), which is the same as root on that VM |
| `ASUS_ROUTER_SSH`, `ASUS_ROUTER_SSH_PORT`, `HOMELAB_SSH_KEY` | The same SSH key, for the router's administrator login | A shell as the router's administrator: every setting, the firewall and a reboot |
| `SYNCTHING_SERVER_API_KEY` | Syncthing API key | The whole Syncthing REST API, including changing folders and devices |
| `UPTIME_KUMA_API_KEY` | Uptime Kuma API key | Reading the `/metrics` page and nothing else. It cannot open the web page and cannot change a monitor |
| `HOMEASSISTANT_URL`, `HOMEASSISTANT_TOKEN` | Home Assistant long-lived access token of a separate administrator user that may log in only from the local network | Everything a Home Assistant administrator can do: every action on every device, and changing or deleting users, automations, scripts, dashboards and the entity and device registries. Home Assistant refuses the token from outside the local network |

The generic skills tell an agent how to use these keys and which calls only read. Read them for the details instead of a copy here:

1. Proxmox: [agent-standards proxmox skill](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/proxmox/SKILL.md)
2. Syncthing: [agent-standards syncthing skill](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/syncthing/SKILL.md)

---

### Placeholders

| Placeholder | Meaning |
|---|---|
| `<proxmox-host>` | The Proxmox machine, reached on port 8006 |
| `<node>` | The Proxmox node name, shown under Datacenter in the web page |
| `<docker-vm-ip>` | The Ubuntu virtual machine running the Compose stack |
| `<ha-vm-ip>` | The Home Assistant OS virtual machine, reached on port 8123 |
| `<router-ip>` | The router's address on your own network |
| `<router-admin-user>` | The user name you log in to the router's web page with |
| `<ssh-port>` | The port you choose for SSH on the router |
| `<your-user>` | Your login on the Docker VM, the one called `<user>` in [proxmox_docker_vm.md](proxmox_docker_vm.md) |
| `<user@realm!token-name>` | The full name of the Proxmox API token, printed when you create it |
| `<token secret>` | The secret of that token, printed once when you create it |

Concrete example, the lab these documents were written from:

```text
<proxmox-host>       192.168.1.10
<node>               proxmox
<docker-vm-ip>       192.168.1.12
<ha-vm-ip>           192.168.1.11
<router-ip>          192.168.1.1
<router-admin-user>  admin
<ssh-port>           22
```

---

### The file

The agent reads its credentials from one file outside every repository:

```text
~/.local/state/agents/workspace/homelab.env
```

Rules for that file:

1. Mode 600, so only your own login can read or change it.
2. Never commit it, and never copy it into a repository. The repository ships only the template, [agent_access.env.example](agent_access.env.example), which holds placeholders and no real values.
3. Replace every value in angle brackets before an agent uses the file. A shell that sources a line such as `DOCKER_VM_SSH=<your-user>@<docker-vm-ip>` reads `<` and `>` as redirections.

Create the folder. Unix shell:

```bash
mkdir -p ~/.local/state/agents/workspace
```

PowerShell:

```powershell
New-Item -ItemType Directory -Force "$HOME\.local\state\agents\workspace"
```

Copy the template with mode 600 from the start, from the repository root. Unix shell:

```bash
install -m 600 homelab/agent_access.env.example ~/.local/state/agents/workspace/homelab.env
```

PowerShell:

```powershell
Copy-Item homelab\agent_access.env.example "$HOME\.local\state\agents\workspace\homelab.env"
```

Windows has no mode 600. Remove the inherited permissions and leave only your own login instead:

```powershell
icacls "$HOME\.local\state\agents\workspace\homelab.env" /inheritance:r /grant:r "${env:USERNAME}:(R,W)"
```

Check the mode on a Unix machine. The line must start with `-rw-------`:

```bash
ls -l ~/.local/state/agents/workspace/homelab.env
```

Then set the keys as the sections below describe, with the commands in [Set a key](#set-a-key).

---

### Set a key

Every key is one line of the file, and one command replaces that line. Put the key's name in place of `<KEY>` and its value in place of `<value>`.

A value that is not secret. Unix shell:

```bash
sed -i 's|^<KEY>=.*|<KEY>=<value>|' ~/.local/state/agents/workspace/homelab.env
```

On macOS, write `sed -i ''` instead of `sed -i`, because the sed that macOS ships takes the next word after `-i` as the name of a backup file.

PowerShell:

```powershell
(Get-Content "$HOME\.local\state\agents\workspace\homelab.env") -replace '^<KEY>=.*', '<KEY>=<value>' | Set-Content "$HOME\.local\state\agents\workspace\homelab.env"
```

A secret: `PROXMOX_TOKEN_SECRET`, `SYNCTHING_SERVER_API_KEY`, `UPTIME_KUMA_API_KEY` and `HOMEASSISTANT_TOKEN`. Type or paste it at the prompt. It is not shown, and it never reaches the shell history. Unix shell, the same in bash and zsh:

```bash
printf 'Secret: '; read -rs value; echo
```

Write it. `perl` puts the value in exactly as it is, where `sed` would read a `&`, `|` or `\` inside it as part of the command:

```bash
value="$value" perl -pi -e 's/^<KEY>=.*/<KEY>=$ENV{value}/' ~/.local/state/agents/workspace/homelab.env
```

Remove it from the shell:

```bash
unset value
```

PowerShell:

```powershell
$value = [Net.NetworkCredential]::new('', (Read-Host 'Secret' -AsSecureString)).Password
```

```powershell
(Get-Content "$HOME\.local\state\agents\workspace\homelab.env") | ForEach-Object { if ($_ -like '<KEY>=*') { "<KEY>=$value" } else { $_ } } | Set-Content "$HOME\.local\state\agents\workspace\homelab.env"
```

```powershell
Remove-Variable value
```

Check the file without printing any value. This prints each key and the length of its value. Unix shell:

```bash
awk -F= '{print $1, length($2)}' ~/.local/state/agents/workspace/homelab.env
```

PowerShell:

```powershell
Get-Content "$HOME\.local\state\agents\workspace\homelab.env" | ForEach-Object { $name, $rest = $_ -split '=', 2; "$name $($rest.Length)" }
```

Find the keys that still hold a placeholder. No output means none is left. Unix shell:

```bash
grep -n '<' ~/.local/state/agents/workspace/homelab.env
```

PowerShell:

```powershell
Select-String -Path "$HOME\.local\state\agents\workspace\homelab.env" -Pattern '<'
```

For this lab, all nine values that are not secret in one command. Put your user name in place of `<your-user>` first. Unix shell:

```bash
sed -i -e 's|^PROXMOX_URL=.*|PROXMOX_URL=https://192.168.1.10:8006|' -e 's|^PROXMOX_SSH=.*|PROXMOX_SSH=root@192.168.1.10|' -e 's|^DOCKER_VM_SSH=.*|DOCKER_VM_SSH=<your-user>@192.168.1.12|' -e 's|^SYNCTHING_SERVER_URL=.*|SYNCTHING_SERVER_URL=http://192.168.1.12:7780|' -e 's|^HOMELAB_SSH_KEY=.*|HOMELAB_SSH_KEY=~/.ssh/homelab_agent_ed25519|' -e 's|^ASUS_ROUTER_SSH=.*|ASUS_ROUTER_SSH=admin@192.168.1.1|' -e 's|^ASUS_ROUTER_SSH_PORT=.*|ASUS_ROUTER_SSH_PORT=22|' -e 's|^UPTIME_KUMA_URL=.*|UPTIME_KUMA_URL=http://192.168.1.12:7779|' -e 's|^HOMEASSISTANT_URL=.*|HOMEASSISTANT_URL=http://192.168.1.11:8123|' ~/.local/state/agents/workspace/homelab.env
```

PowerShell:

```powershell
(Get-Content "$HOME\.local\state\agents\workspace\homelab.env") -replace '^PROXMOX_URL=.*', 'PROXMOX_URL=https://192.168.1.10:8006' -replace '^PROXMOX_SSH=.*', 'PROXMOX_SSH=root@192.168.1.10' -replace '^DOCKER_VM_SSH=.*', 'DOCKER_VM_SSH=<your-user>@192.168.1.12' -replace '^SYNCTHING_SERVER_URL=.*', 'SYNCTHING_SERVER_URL=http://192.168.1.12:7780' -replace '^HOMELAB_SSH_KEY=.*', 'HOMELAB_SSH_KEY=~/.ssh/homelab_agent_ed25519' -replace '^ASUS_ROUTER_SSH=.*', 'ASUS_ROUTER_SSH=admin@192.168.1.1' -replace '^ASUS_ROUTER_SSH_PORT=.*', 'ASUS_ROUTER_SSH_PORT=22' -replace '^UPTIME_KUMA_URL=.*', 'UPTIME_KUMA_URL=http://192.168.1.12:7779' -replace '^HOMEASSISTANT_URL=.*', 'HOMEASSISTANT_URL=http://192.168.1.11:8123' | Set-Content "$HOME\.local\state\agents\workspace\homelab.env"
```

#### Use a key in a command

The test commands on this page read a secret from the file with `grep` and `cut` and hand it to `curl` on standard input, `-H @-` for a header and `-K -` for a configuration line. So the secret is not shown, the history holds only the command, and it is never an argument of `curl`, which any account on the machine can read in the process list. Never type a secret into a command instead, and never source the file, because a line that still holds a placeholder has `<` and `>` in it, which a shell reads as redirections.

---

### PROXMOX_URL

The address of the Proxmox web interface, `https://<proxmox-host>:8006`, the same address you open in the browser in [proxmox_host_install.md](proxmox_host_install.md).

---

### PROXMOX_TOKEN_ID and PROXMOX_TOKEN_SECRET

An API token belongs to a user. This lab gives the agent the admin token below. The read only and edit alternatives after it are the narrower ones. Create only one of them, because all three use the same user, `agent@pve`.

#### The admin token, the one this lab uses

The token can create, change and delete virtual machines and storage content, manage storages and SDN, create users and groups but not grant permissions, and download ISO files. The agent still asks you before every change and before every delete, one virtual machine per yes.

The token is created without privilege separation, `-privsep 0`, so it has exactly the rights of its user and needs no roles of its own. On a user that exists only for this token, that gives the same result as giving the same roles to the token itself.

Run these in a shell on the Proxmox host, which [proxmox_host_install.md](proxmox_host_install.md) shows how to open over SSH. They are the exact commands run on this lab on 2026-10-23, against Proxmox VE 8.3.2. `proxmox` in step 5 is this lab's node name, `<node>` in the placeholders above.

1. Create the user in the Proxmox realm. It has no password, so it cannot log in to the web page:

    ```bash
    pveum user add agent@pve -comment "AI agent"
    ```

2. Create the token without privilege separation:

    ```bash
    pveum user token add agent@pve agent -privsep 0
    ```

    The output shows `full-tokenid`, here `agent@pve!agent`, and `value`. Set the first as `PROXMOX_TOKEN_ID` and the second, as a secret, as `PROXMOX_TOKEN_SECRET`, with the commands in [Set a key](#set-a-key). Proxmox shows the value only this once.

3. Give the user the administrator role on everything:

    ```bash
    pveum acl modify / -user agent@pve -role PVEAdmin
    ```

4. Create a role that lets the host download a file from a URL:

    ```bash
    pveum role add AgentDownload -privs Sys.AccessNetwork
    ```

5. Give the user that role on the node, with `PVEAdmin` again beside it:

    ```bash
    pveum acl modify /nodes/proxmox -user agent@pve -role PVEAdmin,AgentDownload
    ```

Why steps 4 and 5: `PVEAdmin` does not have `Sys.AccessNetwork`, and downloading an ISO by URL needs it on the node. No built-in role has it except `Administrator`, so step 4 makes a role with only that right. A role given on a deeper path, here one node, replaces the roles inherited from above for that path, so step 5 names `PVEAdmin` again. Without it the agent would lose `PVEAdmin` on that node. `Sys.AccessNetwork` exists on Proxmox VE 8 from `libpve-access-control` 8.1.2. An older host refuses step 4.

The web interface does the same under Datacenter, then Permissions:

1. Users, then Add, for the user, with no password.
2. API Tokens, then Add, with Privilege Separation not ticked, for the token.
3. Roles, then Create, with the name `AgentDownload` and the privilege `Sys.AccessNetwork`.
4. Permissions, then Add, then User Permission, once for the path `/` with the role `PVEAdmin`, and twice for the path `/nodes/proxmox`, once with `PVEAdmin` and once with `AgentDownload`.

Test it from your own machine. Proxmox uses a self signed certificate by default, so `-k` skips the certificate check. Unix shell:

```bash
{ printf 'Authorization: PVEAPIToken='; grep '^PROXMOX_TOKEN_ID=' ~/.local/state/agents/workspace/homelab.env | cut -d= -f2- | tr -d '\n'; printf '='; grep '^PROXMOX_TOKEN_SECRET=' ~/.local/state/agents/workspace/homelab.env | cut -d= -f2-; } | curl -k -H @- https://<proxmox-host>:8006/api2/json/version
```

PowerShell:

```powershell
"Authorization: PVEAPIToken=$((Select-String -Path "$HOME\.local\state\agents\workspace\homelab.env" -Pattern '^PROXMOX_TOKEN_ID=(.*)').Matches[0].Groups[1].Value)=$((Select-String -Path "$HOME\.local\state\agents\workspace\homelab.env" -Pattern '^PROXMOX_TOKEN_SECRET=(.*)').Matches[0].Groups[1].Value)" | curl.exe -k -H '@-' https://<proxmox-host>:8006/api2/json/version
```

An answer with a `version` field means the token works.

Then check what the token can do. Ask the API for the token's own permissions. Unix shell:

```bash
{ printf 'Authorization: PVEAPIToken='; grep '^PROXMOX_TOKEN_ID=' ~/.local/state/agents/workspace/homelab.env | cut -d= -f2- | tr -d '\n'; printf '='; grep '^PROXMOX_TOKEN_SECRET=' ~/.local/state/agents/workspace/homelab.env | cut -d= -f2-; } | curl -k -H @- https://<proxmox-host>:8006/api2/json/access/permissions
```

PowerShell:

```powershell
"Authorization: PVEAPIToken=$((Select-String -Path "$HOME\.local\state\agents\workspace\homelab.env" -Pattern '^PROXMOX_TOKEN_ID=(.*)').Matches[0].Groups[1].Value)=$((Select-String -Path "$HOME\.local\state\agents\workspace\homelab.env" -Pattern '^PROXMOX_TOKEN_SECRET=(.*)').Matches[0].Groups[1].Value)" | curl.exe -k -H '@-' https://<proxmox-host>:8006/api2/json/access/permissions
```

Measured on 2026-10-23 against Proxmox VE 8.3.2 with the same requests as above, the token holds:

| Path | Privileges |
|---|---|
| `/` | `Datastore.Allocate`, `Datastore.AllocateSpace`, `Datastore.AllocateTemplate`, `Datastore.Audit`, `Group.Allocate`, `Mapping.Audit`, `Mapping.Use`, `Pool.Allocate`, `Pool.Audit`, `Realm.AllocateUser`, `SDN.Allocate`, `SDN.Audit`, `SDN.Use`, `Sys.Audit`, `Sys.Console`, `Sys.Syslog`, `User.Modify`, `VM.Allocate`, `VM.Audit`, `VM.Backup`, `VM.Clone`, `VM.Config.CDROM`, `VM.Config.CPU`, `VM.Config.Cloudinit`, `VM.Config.Disk`, `VM.Config.HWType`, `VM.Config.Memory`, `VM.Config.Network`, `VM.Config.Options`, `VM.Console`, `VM.Migrate`, `VM.Monitor`, `VM.PowerMgmt`, `VM.Snapshot`, `VM.Snapshot.Rollback`, 35 in all |
| `/nodes/proxmox` | the same 35 and `Sys.AccessNetwork` |

It does not hold `Sys.Modify`, `Sys.PowerMgmt`, `Permissions.Modify` or `Realm.Allocate`, so it cannot change the host's system settings, cannot reboot the host, and cannot change permissions.

Revoke the token, on the Proxmox host:

```bash
pveum user token remove agent@pve agent
```

Remove the user as well when no agent needs access any more:

```bash
pveum user delete agent@pve
```

And the download role, once no user has it:

```bash
pveum role delete AgentDownload
```

#### Switching from a narrower token

Remove every role the narrower setup gave the user, path by path, and every custom role nothing else uses. Then follow the admin token steps above, skipping step 1 because the user already exists. This lab came from a setup with `PVEAuditor` on `/`, `PVEDatastoreUser` on `/storage` and a custom role `AgentVM` on `/vms`, and removed them with:

```bash
pveum acl delete /vms -user agent@pve -role AgentVM
```

```bash
pveum acl delete /storage -user agent@pve -role PVEDatastoreUser
```

```bash
pveum acl delete / -user agent@pve -role PVEAuditor
```

```bash
pveum role delete AgentVM
```

Coming from the edit alternative as written below, the first command names `PVEVMAdmin` instead, and there is no custom role to delete. Its token, `agent@pve!agent`, already has no privilege separation, so it can stay and step 2 is skipped as well. Coming from the read only alternative, remove its token with `pveum user token remove agent@pve readonly` and create the new one in step 2.

#### Read only alternative

Create a separate user for the agent, give it the read only role `PVEAuditor`, then create a token for it with privilege separation. Privilege separation means the token starts with no rights at all and gets only what you grant it, and Proxmox never lets it do more than its user can. If the token leaks, you remove the token and the user stays.

Run these in a shell on the Proxmox host, which [proxmox_host_install.md](proxmox_host_install.md) shows how to open over SSH.

1. Create the user in the Proxmox realm. It has no password, so it cannot log in to the web page:

    ```bash
    pveum user add agent@pve -comment "AI agent, read only"
    ```

2. Give the user the read only role on everything:

    ```bash
    pveum acl modify / -user agent@pve -role PVEAuditor
    ```

3. Create the token with privilege separation:

    ```bash
    pveum user token add agent@pve readonly -privsep 1
    ```

    The output shows `full-tokenid`, here `agent@pve!readonly`, and `value`. Set the first as `PROXMOX_TOKEN_ID` and the second, as a secret, as `PROXMOX_TOKEN_SECRET`, with the commands in [Set a key](#set-a-key). Proxmox shows the value only this once.

4. Give the token the same read only role, because a separated token has none of its own:

    ```bash
    pveum acl modify / -token 'agent@pve!readonly' -role PVEAuditor
    ```

5. Check what the token can do. Every privilege listed should end in `.Audit`, such as `Sys.Audit` or `VM.Audit`:

    ```bash
    pveum user token permissions agent@pve readonly
    ```

The web interface does the same under Datacenter, then Permissions: Users, then Add for the user, API Tokens, then Add with Privilege Separation ticked for the token, and Permissions, then Add, then API Token Permission for the role.

Test it from your own machine. Proxmox uses a self signed certificate by default, so `-k` skips the certificate check. Unix shell:

```bash
{ printf 'Authorization: PVEAPIToken='; grep '^PROXMOX_TOKEN_ID=' ~/.local/state/agents/workspace/homelab.env | cut -d= -f2- | tr -d '\n'; printf '='; grep '^PROXMOX_TOKEN_SECRET=' ~/.local/state/agents/workspace/homelab.env | cut -d= -f2-; } | curl -k -H @- https://<proxmox-host>:8006/api2/json/version
```

PowerShell:

```powershell
"Authorization: PVEAPIToken=$((Select-String -Path "$HOME\.local\state\agents\workspace\homelab.env" -Pattern '^PROXMOX_TOKEN_ID=(.*)').Matches[0].Groups[1].Value)=$((Select-String -Path "$HOME\.local\state\agents\workspace\homelab.env" -Pattern '^PROXMOX_TOKEN_SECRET=(.*)').Matches[0].Groups[1].Value)" | curl.exe -k -H '@-' https://<proxmox-host>:8006/api2/json/version
```

An answer with a `version` field means the token works.

Revoke the token, on the Proxmox host:

```bash
pveum user token remove agent@pve readonly
```

#### Edit alternative

This alternative lets the agent change virtual machines, not only read them. The user gets three roles, and the token is created without privilege separation, `-privsep 0`, so it has exactly the rights of its user and needs no roles of its own. The cost: a leaked token can do everything the user can, including stopping, rolling back and deleting virtual machines, until you revoke it.

Run these in a shell on the Proxmox host:

1. Create the user in the Proxmox realm. It has no password, so it cannot log in to the web page:

    ```bash
    pveum user add agent@pve -comment "AI agent"
    ```

2. Give the user the read only role on everything:

    ```bash
    pveum acl modify / -user agent@pve -role PVEAuditor
    ```

3. Give the user the virtual machine administrator role on every virtual machine:

    ```bash
    pveum acl modify /vms -user agent@pve -role PVEVMAdmin
    ```

4. Let the user use space on storage, which a disk resize, a snapshot and a backup need:

    ```bash
    pveum acl modify /storage -user agent@pve -role PVEDatastoreUser
    ```

5. Create the token without privilege separation:

    ```bash
    pveum user token add agent@pve agent -privsep 0
    ```

    The output shows `full-tokenid`, here `agent@pve!agent`, and `value`. Set the first as `PROXMOX_TOKEN_ID` and the second, as a secret, as `PROXMOX_TOKEN_SECRET`, with the commands in [Set a key](#set-a-key). Proxmox shows the value only this once.

Check what the token can do. From your own machine, ask the API for the token's own permissions. Unix shell:

```bash
{ printf 'Authorization: PVEAPIToken='; grep '^PROXMOX_TOKEN_ID=' ~/.local/state/agents/workspace/homelab.env | cut -d= -f2- | tr -d '\n'; printf '='; grep '^PROXMOX_TOKEN_SECRET=' ~/.local/state/agents/workspace/homelab.env | cut -d= -f2-; } | curl -k -H @- https://<proxmox-host>:8006/api2/json/access/permissions
```

PowerShell:

```powershell
"Authorization: PVEAPIToken=$((Select-String -Path "$HOME\.local\state\agents\workspace\homelab.env" -Pattern '^PROXMOX_TOKEN_ID=(.*)').Matches[0].Groups[1].Value)=$((Select-String -Path "$HOME\.local\state\agents\workspace\homelab.env" -Pattern '^PROXMOX_TOKEN_SECRET=(.*)').Matches[0].Groups[1].Value)" | curl.exe -k -H '@-' https://<proxmox-host>:8006/api2/json/access/permissions
```

Measured on 2026-10-23 against Proxmox VE 8.3.2 with the same requests as above, the token holds:

| Path | Privileges |
|---|---|
| `/` | `Datastore.Audit`, `Mapping.Audit`, `Pool.Audit`, `SDN.Audit`, `Sys.Audit`, `VM.Audit` |
| `/storage` | `Datastore.AllocateSpace`, `Datastore.Audit` |
| `/vms` | every `VM.*` privilege, among them `VM.Config.Disk`, `VM.PowerMgmt`, `VM.Snapshot`, `VM.Snapshot.Rollback`, `VM.Backup` and `VM.Allocate` |

`VM.Allocate` includes creating and deleting a virtual machine, and `VM.Snapshot.Rollback` throws away everything since a snapshot. That is why the agent asks you before every change, as [What each credential allows](#what-each-credential-allows) says.

Revoke the token, on the Proxmox host:

```bash
pveum user token remove agent@pve agent
```

#### Removing the user

Remove the user as well when no agent needs access any more, whichever alternative you used:

```bash
pveum user delete agent@pve
```

---

### PROXMOX_SSH

The value is `root@<proxmox-host>`, on this lab `root@192.168.1.10`. What makes it work without a password is the key from [HOMELAB_SSH_KEY](#homelab_ssh_key), accepted by `root` on the Proxmox host.

Why a shell as well as the API token: some steps run only as `root` in a shell on the host, and the token cannot do them. Attaching a whole physical disk to a virtual machine is one, `qm set <vmid> -scsi1 /dev/disk/by-id/<disk-id>` in [lan_storage.md](lan_storage.md).

The risk, in one sentence: this key is `root` on the host, so whoever holds it has full control of the host, of every virtual machine and of every disk. The agent reads freely and asks you before every change, then waits for your yes, as [What each credential allows](#what-each-credential-allows) says.

1. Create the key first, step 1 of [DOCKER_VM_SSH](#docker_vm_ssh), if it does not exist yet.

2. Copy the public key to the host. This asks for the host's `root` password once, and you type it, not the agent. Unix shell:

    ```bash
    ssh-copy-id -i ~/.ssh/homelab_agent_ed25519.pub root@<proxmox-host>
    ```

    Windows has no `ssh-copy-id`. PowerShell:

    ```powershell
    Get-Content "$HOME\.ssh\homelab_agent_ed25519.pub" | ssh root@<proxmox-host> "cat >> ~/.ssh/authorized_keys"
    ```

    On this lab, on 2026-10-23, `ssh-copy-id -i ~/.ssh/homelab_agent_ed25519.pub root@192.168.1.10` printed `Number of key(s) added: 1`.

3. Check that the key works with no password. `BatchMode=yes` makes `ssh` fail instead of asking for one. Unix shell:

    ```bash
    ssh -o BatchMode=yes -i ~/.ssh/homelab_agent_ed25519 root@<proxmox-host> pveversion
    ```

    PowerShell:

    ```powershell
    ssh -o BatchMode=yes -i "$HOME\.ssh\homelab_agent_ed25519" root@<proxmox-host> pveversion
    ```

    A line starting with `pve-manager/` means the key works.

Revoke the key on the Proxmox host. This removes every line that ends with the `homelab-agent` comment:

```bash
sed -i --follow-symlinks '/ homelab-agent$/d' /root/.ssh/authorized_keys
```

`--follow-symlinks` is there because on a Proxmox host this file can be a link into `/etc/pve`, the cluster file system, and without it `sed -i` would replace the link with a plain copy.

---

### DOCKER_VM_SSH

The value is `<your-user>@<docker-vm-ip>`. What makes it work without a password is an SSH key that the Docker VM accepts for your login. Use a separate ed25519 key for the agent, so you can remove it without touching your own keys.

An agent cannot type a key passphrase either. Either leave the passphrase empty, so the key file with its mode 600 is the only protection, or set one and load the key into `ssh-agent` with `ssh-add` before the agent starts.

1. Create the key. Unix shell:

    ```bash
    ssh-keygen -t ed25519 -f ~/.ssh/homelab_agent_ed25519 -C homelab-agent
    ```

    PowerShell:

    ```powershell
    ssh-keygen -t ed25519 -f "$HOME\.ssh\homelab_agent_ed25519" -C homelab-agent
    ```

2. Copy the public key to the Docker VM. This asks for your VM password once, and you type it, not the agent. Unix shell:

    ```bash
    ssh-copy-id -i ~/.ssh/homelab_agent_ed25519.pub <your-user>@<docker-vm-ip>
    ```

    Windows has no `ssh-copy-id`. PowerShell:

    ```powershell
    Get-Content "$HOME\.ssh\homelab_agent_ed25519.pub" | ssh <your-user>@<docker-vm-ip> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    ```

3. Check that the key works with no password. `BatchMode=yes` makes `ssh` fail instead of asking for one. Unix shell:

    ```bash
    ssh -o BatchMode=yes -i ~/.ssh/homelab_agent_ed25519 <your-user>@<docker-vm-ip> docker ps
    ```

    PowerShell:

    ```powershell
    ssh -o BatchMode=yes -i "$HOME\.ssh\homelab_agent_ed25519" <your-user>@<docker-vm-ip> docker ps
    ```

The agent connects the same way, with `-i` and the value of `HOMELAB_SSH_KEY`, and the value of `DOCKER_VM_SSH`.

The same key also opens the VM's `/opt/docker-stack` folder in Dolphin over SFTP, with a short host name in your SSH config, as [Open the Docker VM in Dolphin](lan_storage.md#open-the-docker-vm-in-dolphin) shows.

The same key opens the router and the Proxmox host too, as [ASUS_ROUTER_SSH](#asus_router_ssh) and [PROXMOX_SSH](#proxmox_ssh) describe. To take it back from all three, remove it on the router and on the Proxmox host as those sections say, then here. Revoke the key on the Docker VM. This removes every line that ends with the `homelab-agent` comment from step 1:

```bash
sed -i '/ homelab-agent$/d' ~/.ssh/authorized_keys
```

Then delete both key files on your own machine. Unix shell:

```bash
rm ~/.ssh/homelab_agent_ed25519 ~/.ssh/homelab_agent_ed25519.pub
```

PowerShell:

```powershell
Remove-Item "$HOME\.ssh\homelab_agent_ed25519", "$HOME\.ssh\homelab_agent_ed25519.pub"
```

---

### SYNCTHING_SERVER_URL

The Syncthing web interface on the Docker VM, `http://<docker-vm-ip>:7780`. Port 7780 on the VM leads to port 8384 inside the container, as [syncthing.md](syncthing.md) describes. Use the VM address and not `http://syncthing.internal`, so the agent still reaches Syncthing when AdGuard Home or Nginx Proxy Manager is down.

---

### SYNCTHING_SERVER_API_KEY

The key works whether or not you set a GUI login.

1. Open `http://<docker-vm-ip>:7780`.
2. Choose Actions, then Settings, and stay on the General tab.
3. If the API Key field shows only a dash, press Generate next to it, then Save, then open Settings again.
4. Copy the value in the API Key field and set it, as a secret, as `SYNCTHING_SERVER_API_KEY`, with the commands in [Set a key](#set-a-key).

Test it from your own machine. Unix shell:

```bash
{ printf 'X-API-Key: '; grep '^SYNCTHING_SERVER_API_KEY=' ~/.local/state/agents/workspace/homelab.env | cut -d= -f2-; } | curl -H @- http://<docker-vm-ip>:7780/rest/system/status
```

PowerShell:

```powershell
"X-API-Key: $((Select-String -Path "$HOME\.local\state\agents\workspace\homelab.env" -Pattern '^SYNCTHING_SERVER_API_KEY=(.*)').Matches[0].Groups[1].Value)" | curl.exe -H '@-' http://<docker-vm-ip>:7780/rest/system/status
```

An answer with a `myID` field means the key works.

Revoke the key in the same place: press Generate next to the API Key field, then Save. The old key stops working, and every other tool that used it needs the new one.

---

### HOMELAB_SSH_KEY

The path of the private key the agent uses, `~/.ssh/homelab_agent_ed25519`. It is the key that [DOCKER_VM_SSH](#docker_vm_ssh) creates, and the same key opens the router and `root` on the Proxmox host. One key for all three means one file to protect and one key to take back, and the agent passes it with `-i` to every `ssh` it runs here.

Create it with step 1 of [DOCKER_VM_SSH](#docker_vm_ssh), and give it to the Docker VM with step 2 there, to the router as [ASUS_ROUTER_SSH](#asus_router_ssh) says, and to the Proxmox host as [PROXMOX_SSH](#proxmox_ssh) says. Each section tests it.

Check that the file is there and that only you can read it. The line must start with `-rw-------`:

```bash
ls -l ~/.ssh/homelab_agent_ed25519
```

Revoke it by removing the public key on the router, on the Proxmox host and on the Docker VM, as those three sections say, then deleting both key files, the last step of [DOCKER_VM_SSH](#docker_vm_ssh). Deleting only the files on your machine does not revoke anything, because a copy elsewhere would still be accepted.

---

### ASUS_ROUTER_SSH

The value is `<router-admin-user>@<router-ip>`, the user name of the router's web page at the router's address. SSH on an Asus router logs in with that same administrator account, and the router accepts the key from [HOMELAB_SSH_KEY](#homelab_ssh_key) once you paste its public half into the router's settings.

What the agent may do there: read. That means the system log, which the router keeps in `/tmp/syslog.log`, or in `/jffs/syslog.log` when it keeps the log across restarts, and the state commands that only print, such as `uptime`, `ifconfig` and `nvram get <name>`. It asks you before any change, which on this router is anything that writes: `nvram set` and `nvram commit`, `service restart_<name>`, editing a file under `/jffs`, and `reboot`.

On this lab, measured on 2026-10-23 before these steps, the router's web page answered and TCP port 22 refused the connection, so SSH was off and had to be turned on first.

Turn it on in the router's web page, where the field names below are the ones ASUS firmware shows:

1. Open `http://<router-ip>` and log in.
2. Choose Administration, then the System tab, and scroll to the Service section.
3. Set Enable SSH to LAN only. Never LAN & WAN, which opens the shell to the internet.
4. Set SSH Port to the port you chose, `<ssh-port>`, and set the same number as `ASUS_ROUTER_SSH_PORT`, with the commands in [Set a key](#set-a-key).
5. Set Allow Password Login to No, so the router accepts only a key.
6. Paste the whole public key into Authorized Keys, the one line from this file. Unix shell:

    ```bash
    cat ~/.ssh/homelab_agent_ed25519.pub
    ```

    PowerShell:

    ```powershell
    Get-Content "$HOME\.ssh\homelab_agent_ed25519.pub"
    ```

7. Press Apply.

Sources for those names, checked on 2026-10-23: the ASUS FAQ [How to log in ASUS router via Telnet](https://www.asus.com/support/faq/1048201/), last updated 2025/04/30, says "Find [Service]>[Enable SSH]. Click the dropdown list and choose [LAN only] or [LAN & WAN]" under Administration, then System. The SSH Port, Allow Password Login and Authorized Keys labels come from the System page of the Asuswrt-Merlin source, [Advanced_System_Content.asp](https://github.com/RMerl/asuswrt-merlin.ng/blob/master/release/src/router/www/Advanced_System_Content.asp) and its English labels in `EN.dict`, at the commit of 2026-10-17 that merged the ASUS GPL release 3006.102_40585, which is the page the stock firmware ships. Those were read in the source, not on this router's own screen.

Check that the key works with no password. `BatchMode=yes` makes `ssh` fail instead of asking for one. Unix shell:

```bash
ssh -o BatchMode=yes -i ~/.ssh/homelab_agent_ed25519 -p <ssh-port> <router-admin-user>@<router-ip> uptime
```

PowerShell:

```powershell
ssh -o BatchMode=yes -i "$HOME\.ssh\homelab_agent_ed25519" -p <ssh-port> <router-admin-user>@<router-ip> uptime
```

A line with the router's uptime means the key works. `Permission denied (publickey)` means the router refused the key. An ed25519 key works on stock firmware. Measured on 2026-10-23 on this lab's GT-AX6000 with stock firmware build 386, the test above answered with the uptime, and the router's log showed `Pubkey auth succeeded for 'admin'`. The current stock image, 3.0.0.6.102_37437, carries Dropbear 2020.81, and Dropbear takes ed25519 keys since 2020.79.

Revoke it in the same place: delete the key's line from Authorized Keys and press Apply. To close the shell completely, set Enable SSH to No and press Apply.

---

### ASUS_ROUTER_SSH_PORT

The port you set in SSH Port in step 4 above. The agent passes it with `-p`, as the test above does. This lab keeps 22. A port other than 22 keeps the noise of scans that try 22 out of the router's log, though with SSH on the LAN only and password login off, the key is what protects it, not the port.

---

### UPTIME_KUMA_URL

The Uptime Kuma web page on the Docker VM, `http://<docker-vm-ip>:7779`. Port 7779 on the VM leads to port 3001 inside the container, as [uptime_kuma.md](uptime_kuma.md) describes. Use the VM address and not `http://uptime.internal`, so the agent still reaches Uptime Kuma when AdGuard Home or Nginx Proxy Manager is down, which is exactly when it is most useful.

---

### UPTIME_KUMA_API_KEY

An API key in Uptime Kuma opens one thing, the `/metrics` page, which lists every monitor with its name, its address, its status, its response time and the days left on its certificate, in the Prometheus text format. The key cannot open the web page and cannot add, change, pause or delete a monitor, because those go through the logged in web page and not through the key. So this is the one credential here that cannot change anything.

Checked on 2026-10-23 in the source of Uptime Kuma 2.5.5, the version [compose.yaml](compose.yaml) runs, and in its wiki page [Prometheus API Keys](https://github.com/louislam/uptime-kuma/wiki/Prometheus-API-Keys), last changed 2026-10-11:

1. `server/server.js` puts the key check on one route only, `app.get("/metrics", apiAuth, prometheusAPIMetrics())`.
2. `server/auth.js` reads the key as the password of HTTP basic authentication and ignores the user name, and allows 60 key requests a minute.
3. The wiki says "As soon as you add your first API key, the use of basic authentication for the endpoint will be permanently disabled", meaning your own user name and password stop working on `/metrics` from then on, and "The API key cannot be used to access the web interface".

Create it:

1. Open `http://<docker-vm-ip>:7779` and log in.
2. Choose Settings, then API Keys, then Add API Key.
3. Give it a name, such as `agent`, and either an Expiry date or Don't expire.
4. Press Generate. The key starts with `uk` and Uptime Kuma shows it only this once, so copy it now and set it, as a secret, as `UPTIME_KUMA_API_KEY`, with the commands in [Set a key](#set-a-key).

Test it from your own machine. The key goes to curl as the line `user = ":<key>"` of a configuration read from standard input, see [Use a key in a command](#use-a-key-in-a-command), and the colon before the key is an empty user name. Unix shell:

```bash
{ printf 'user = ":'; grep '^UPTIME_KUMA_API_KEY=' ~/.local/state/agents/workspace/homelab.env | cut -d= -f2- | tr -d '\n'; printf '"\n'; } | curl -K - http://<docker-vm-ip>:7779/metrics
```

PowerShell:

```powershell
"user = `":$((Select-String -Path "$HOME\.local\state\agents\workspace\homelab.env" -Pattern '^UPTIME_KUMA_API_KEY=(.*)').Matches[0].Groups[1].Value)`"" | curl.exe -K - http://<docker-vm-ip>:7779/metrics
```

Lines starting with `monitor_status` mean the key works. A `401` answer means it does not.

Revoke it on the same page, Settings, then API Keys: Disable stops the key until you Enable it again, and Delete removes it for good.

---

### HOMEASSISTANT_URL

The Home Assistant web page on its own virtual machine, `http://<ha-vm-ip>:8123`, the address [home_assistant_vm.md](home_assistant_vm.md) opens for onboarding. Home Assistant has no `.internal` name, as [nginx_proxy_manager.md](nginx_proxy_manager.md) explains, so this address is the only one. The one command for this lab in [Set a key](#set-a-key) sets it.

---

### HOMEASSISTANT_TOKEN

A long-lived access token, which Home Assistant keeps valid for 10 years unless you delete it. It belongs to a separate Home Assistant user made only for the agent, never to your own login, and that user has two switches turned on:

1. Administrator. Editing automations, scripts, dashboards and the entity and device registries needs an administrator, because Home Assistant core marks those endpoints `require_admin`. A token of a user who is not an administrator is refused there.
2. Local access only, the switch the page describes as "Can only log in from the local network". Home Assistant checks this flag for every bearer token as well, not only on the login page, so a token that leaks does not work from outside your network.

The minus: the token has full administrator power over your home. It can run every action on every device, change or delete every automation, script and dashboard, and add or remove users. The agent reads freely and asks you before every change, as [What each credential allows](#what-each-credential-allows) says, and that rule is all that stops a change here.

Checked on 2026-10-25 in the source of Home Assistant core 2026.10.4 and of its frontend 20260930.5:

1. `homeassistant/components/config/view.py` puts `@require_admin` on reading, saving and deleting the configuration of an automation or a script. `homeassistant/components/lovelace/websocket.py` puts `require_admin` on saving and deleting a dashboard, and `homeassistant/components/config/entity_registry.py` and `device_registry.py` put it on updating and removing a registry entry.
2. `homeassistant/components/http/auth.py` calls `async_user_not_allowed_do_auth` for every `Authorization: Bearer` header. That function, in `auth_util.py`, refuses a local only user whose address is not a local one with "User cannot authenticate remotely", refuses a local only user on a connection through Home Assistant Cloud, and refuses every user who is not active.
3. The frontend names the two switches Administrator and Local access only, and says about a new token "It will not be shown again" and "Each token will be valid for 10 years from creation".

Create it:

1. Open `http://<ha-vm-ip>:8123` and log in with your own administrator login.
2. Choose Settings, then People, then the Users tab, then Add user. Before Home Assistant 2026.6, the Users tab shows only after you turn on Advanced mode in your own profile.
3. Fill in Display name, such as `agent`, Username and Password. Turn on Local access only and Administrator, then press Create.
4. Log out, or open a private browser window, and log in as the new user.
5. Open the profile, the user name at the bottom of the side bar, then the Security tab.
6. Under Long-lived access tokens, press Create token and give it a name, such as `agent`. Home Assistant shows the token only this once, so copy it now and set it, as a secret, as `HOMEASSISTANT_TOKEN`, with the commands in [Set a key](#set-a-key).

Test it from your own machine. Unix shell:

```bash
{ printf 'Authorization: Bearer '; grep '^HOMEASSISTANT_TOKEN=' ~/.local/state/agents/workspace/homelab.env | cut -d= -f2-; } | curl -H @- http://<ha-vm-ip>:8123/api/
```

PowerShell:

```powershell
"Authorization: Bearer $((Select-String -Path "$HOME\.local\state\agents\workspace\homelab.env" -Pattern '^HOMEASSISTANT_TOKEN=(.*)').Matches[0].Groups[1].Value)" | curl.exe -H '@-' http://<ha-vm-ip>:8123/api/
```

The answer `{"message":"API running."}` means the token works. A `401` answer means it does not, or that the request came from outside the local network. Keep the slash at the end, because the path is `/api/` and not `/api`, as the [Home Assistant REST API](https://developers.home-assistant.io/docs/api/rest/) page says.

Revoke it in one of two ways:

1. Log in as the agent user, open the profile, then the Security tab, and delete the token under Long-lived access tokens.
2. Log in as yourself, choose Settings, then People, then the Users tab, open the agent user and press Delete user. That removes the user and every token it holds. Deactivate user on the same page stops every token of the user until you press Activate user again.

What uses it: the [ha-mcp](https://github.com/homeassistant-ai/ha-mcp) MCP server from homeassistant-ai, which [docs/MCP_SETUP.md](https://github.com/Lukk17/agent-standards/blob/master/docs/MCP_SETUP.md) in the agent-standards repository describes, and plain `curl` calls against the REST API, in the same form as the test above. The two key names, `HOMEASSISTANT_URL` and `HOMEASSISTANT_TOKEN`, are the ones ha-mcp reads, because ha-mcp is started with `uvx --env-file` on `~/.local/state/agents/workspace/homelab.env`, and uvx loads every key of that file into the ha-mcp process, not only these two.

---

### When a credential may have leaked

Revoke it first. Each section above ends with its revoke step, and none of them needs another credential changed. Then create a new one with the same steps and set it in `~/.local/state/agents/workspace/homelab.env` with the commands in [Set a key](#set-a-key).
