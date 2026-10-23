# Agent access

> How an AI agent reaches this lab without a password: one Proxmox API token, one SSH key for the Docker VM and one Syncthing API key, kept in a file on your own machine that only you can read.

---

### Why not a password

Agents do not type passwords into login pages. A login page is built for a person: it shows a form, may ask for a second factor, and hands back a session that expires. An agent works from a command line. It calls an API with a header or connects with `ssh`, and every service in this lab offers a credential made for exactly that.

Those credentials are also safer to hand over than a password. Each one belongs to the agent alone, so you can take it back without changing your own password, and the Proxmox one can be limited to reading. A password given to an agent is your whole account, it ends up in chat logs, and the only way to take it back is to change it everywhere you use it.

---

### What each credential allows

The Proxmox token comes in two options. The default is read only by itself: Proxmox refuses every change it asks for. The edit option can also change, stop, snapshot, roll back, back up, create and delete virtual machines. This lab uses the edit option. The other two credentials always give more than read access.

So one rule covers every credential here: the agent reads freely, and asks you before any change, and waits for your yes. With the read only token, that rule is backed by Proxmox itself. With the edit token, the SSH key and the Syncthing key, the rule is all that stops a change, because the credential does not.

| Key in the file | Credential | What it allows |
|---|---|---|
| `PROXMOX_TOKEN_ID`, `PROXMOX_TOKEN_SECRET`, read only option | Proxmox API token with the `PVEAuditor` role | Reading nodes, virtual machines, storage and tasks. Proxmox refuses every change |
| `PROXMOX_TOKEN_ID`, `PROXMOX_TOKEN_SECRET`, edit option | Proxmox API token of a user with `PVEAuditor` on `/`, `PVEVMAdmin` on `/vms` and `PVEDatastoreUser` on `/storage` | Reading everything the read only option reads, plus every `VM.*` privilege on every virtual machine, and using space on storage. What the token can do was measured and is listed under the edit option below |
| `DOCKER_VM_SSH` | SSH key for your login on the Docker VM | Everything your login can do. Your login is in the `docker` group from [proxmox_docker_vm.md](proxmox_docker_vm.md), which is the same as root on that VM |
| `SYNCTHING_SERVER_API_KEY` | Syncthing API key | The whole Syncthing REST API, including changing folders and devices |

The generic skills tell an agent how to use these keys and which calls only read. Read them for the details instead of a copy here:

1. Proxmox: [agent-standards proxmox skill](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/proxmox/SKILL.md)
2. Syncthing: [agent-standards syncthing skill](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/syncthing/SKILL.md)

---

### Placeholders

| Placeholder | Meaning |
|---|---|
| `<proxmox-host>` | The Proxmox machine, reached on port 8006 |
| `<docker-vm-ip>` | The Ubuntu virtual machine running the Compose stack |
| `<your-user>` | Your login on the Docker VM, the one called `<user>` in [proxmox_docker_vm.md](proxmox_docker_vm.md) |
| `<user@realm!token-name>` | The full name of the Proxmox API token, printed when you create it |
| `<token secret>` | The secret of that token, printed once when you create it |

Concrete example, the lab these documents were written from:

```text
<proxmox-host>   192.168.1.10
<docker-vm-ip>   192.168.1.12
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

Then fill the keys as the sections below describe. For this lab the three values that are not secret are:

```text
PROXMOX_URL=https://192.168.1.10:8006
DOCKER_VM_SSH=<your-user>@192.168.1.12
SYNCTHING_SERVER_URL=http://192.168.1.12:7780
```

---

### PROXMOX_URL

The address of the Proxmox web interface, `https://<proxmox-host>:8006`, the same address you open in the browser in [proxmox_host_install.md](proxmox_host_install.md).

---

### PROXMOX_TOKEN_ID and PROXMOX_TOKEN_SECRET

An API token belongs to a user. There are two options below. Use the read only option unless you want the agent to change virtual machines for you. Create only one of them, because both use the same user, `agent@pve`.

#### Read only option, the default

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

    The output shows `full-tokenid`, here `agent@pve!readonly`, and `value`. Put the first into `PROXMOX_TOKEN_ID` and the second into `PROXMOX_TOKEN_SECRET`. Proxmox shows the value only this once.

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
curl -k -H 'Authorization: PVEAPIToken=<user@realm!token-name>=<token secret>' https://<proxmox-host>:8006/api2/json/version
```

The single quotes matter in bash and zsh, which would read the `!` inside double quotes as a history command. PowerShell:

```powershell
curl.exe -k -H "Authorization: PVEAPIToken=<user@realm!token-name>=<token secret>" https://<proxmox-host>:8006/api2/json/version
```

An answer with a `version` field means the token works.

Revoke the token, on the Proxmox host:

```bash
pveum user token remove agent@pve readonly
```

#### Edit option, the one this lab uses

This option lets the agent change virtual machines, not only read them. The user gets three roles, and the token is created without privilege separation, `-privsep 0`, so it has exactly the rights of its user and needs no roles of its own. The cost: a leaked token can do everything the user can, including stopping, rolling back and deleting virtual machines, until you revoke it.

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

    The output shows `full-tokenid`, here `agent@pve!agent`, and `value`. Put the first into `PROXMOX_TOKEN_ID` and the second into `PROXMOX_TOKEN_SECRET`. Proxmox shows the value only this once.

Check what the token can do. From your own machine, ask the API for the token's own permissions. Unix shell:

```bash
curl -k -H 'Authorization: PVEAPIToken=<user@realm!token-name>=<token secret>' https://<proxmox-host>:8006/api2/json/access/permissions
```

PowerShell:

```powershell
curl.exe -k -H "Authorization: PVEAPIToken=<user@realm!token-name>=<token secret>" https://<proxmox-host>:8006/api2/json/access/permissions
```

Measured on 2026-10-23 against Proxmox VE 8.3.2 with exactly the commands above, the token holds:

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

Remove the user as well when no agent needs access any more, whichever option you used:

```bash
pveum user delete agent@pve
```

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

The agent connects the same way, with `-i ~/.ssh/homelab_agent_ed25519` and the value of `DOCKER_VM_SSH`.

Revoke the key on the Docker VM. This removes every line that ends with the `homelab-agent` comment from step 1:

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
4. Copy the value in the API Key field into `SYNCTHING_SERVER_API_KEY`.

Test it from your own machine. Unix shell:

```bash
curl -H "X-API-Key: <key>" http://<docker-vm-ip>:7780/rest/system/status
```

PowerShell:

```powershell
curl.exe -H "X-API-Key: <key>" http://<docker-vm-ip>:7780/rest/system/status
```

An answer with a `myID` field means the key works.

Revoke the key in the same place: press Generate next to the API Key field, then Save. The old key stops working, and every other tool that used it needs the new one.

---

### When a credential may have leaked

Revoke it first. Each section above ends with its revoke step, and none of them needs the other two credentials changed. Then create a new one with the same steps and put it into `~/.local/state/agents/workspace/homelab.env`.
