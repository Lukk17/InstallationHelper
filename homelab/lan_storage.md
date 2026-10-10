# LAN Storage

> A USB disk on the Proxmox host, handed whole to the Docker VM, holding one shared folder that you open in a browser at `http://drive.internal` and as a network drive at `\\drive.internal\files`.

---

### What you get

One folder, `/mnt/data/files` on the Docker VM, reached two ways.

| Way in | Address | Good for |
|---|---|---|
| File Browser, in a browser | `http://drive.internal` | Phones, someone else's laptop, a quick upload or download |
| Samba, as a network drive | `\\drive.internal\files` on Windows, `smb://drive.internal/files` everywhere else | Working on files in place from a desktop, copying many files at once |

Both containers write as user `1000` and group `1000`, so a file uploaded in File Browser can be edited over Samba, and the other way round.

The Plex library is the `media` folder inside the shared folder, `/mnt/data/files/media`, so films go in through the same two ways as any other file. Plex itself is covered in [plex_media_server.md](plex_media_server.md).

---

### One disk, no second copy

A single USB disk has no redundancy. When it dies, everything on it is gone, and USB disks die more often than the internal NVMe. Proxmox backups do not cover it either, on purpose, see below.

Keep anything you cannot replace somewhere else as well. The simplest place is Syncthing, which already runs on this stack and keeps a real copy on each paired machine: put photos and documents in a Syncthing folder first, see [syncthing.md](syncthing.md), and treat this disk as the convenient copy rather than the only one.

---

### Placeholders

| Placeholder | Meaning |
|---|---|
| `<proxmox-host>` | Address of the Proxmox node |
| `<docker-vm-ip>` | Address of the Ubuntu VM running the Compose stack |
| `<vmid>` | The Docker VM's number in Proxmox |
| `<disk-id>` | The USB disk's name under `/dev/disk/by-id/`, starting with `usb-` |
| `<uuid>` | The file system UUID of the new partition, from `blkid` |
| `<samba-user>` | The login for the network drive, your choice |
| `<samba-password>` | The password for that login, your choice |

Concrete example, the lab these documents were written from:

```text
<proxmox-host>   192.168.1.10
<docker-vm-ip>   192.168.1.12
```

---

### Find the disk's stable name on the Proxmox host

Plug the disk into the host, open the node shell, and list disks with their serial numbers:

```bash
lsblk -o +MODEL,SERIAL
```

Then list the stable names:

```bash
ls -l /dev/disk/by-id/ | grep usb-
```

Pick the line for the whole disk, the one whose name does not end in `-part1` or similar. It looks like `usb-JMicron_Generic_0123456789ABCDEF-0:0 -> ../../sdc`.

Use that `/dev/disk/by-id/usb-...` path, never `/dev/sdc`. The Proxmox wiki says it plainly, under Identify Disk on [Passthrough Physical Disk to Virtual Machine](https://pve.proxmox.com/wiki/Passthrough_Physical_Disk_to_Virtual_Machine_(VM)) (page last edited 6 December 2022, read 2026-10-10): "Note that device names like /dev/sdc should never be used, as this can change between reboots. Use the stable /dev/disk/by-id paths instead."

---

### Attach it to the Docker VM

This hands the whole disk to the VM as a second virtual SCSI disk. It is not USB device passthrough, so the VM sees an ordinary disk and the host keeps the USB side.

```bash
qm set <vmid> -scsi1 /dev/disk/by-id/<disk-id>,backup=0
```

The command form is the wiki's own example under Hot-Plug/Add physical device as new virtual SCSI disk, `qm set 592 -scsi2 /dev/disk/by-id/ata-ST3000DM001-1CH166_Z1F41BLC`. `scsi1` is used here because `scsi0` is the VM's system disk from [proxmox_docker_vm.md](proxmox_docker_vm.md).

`backup=0` keeps this disk out of the VM's `vzdump` backups. Without it, every backup of the Docker VM would try to copy the whole data disk onto `local` storage on the NVMe, which would fill it. The [qm manual](https://pve.proxmox.com/pve-docs/qm.1.html) (Proxmox VE 9.2.13, last updated 24 September 2026) describes the option as "backup=<boolean> Whether the drive should be included when making backups.", and the [Proxmox VE guide](https://pve.proxmox.com/pve-docs/chapter-qm.html) says "If you want the Proxmox VE backup manager to skip a disk when doing a backup of a VM, you can set the No backup option on that disk." USB disks need no other option.

Check what was written:

```bash
qm config <vmid> | grep scsi1
```

The line shows the by-id path, `backup=0` and the size Proxmox read from the disk. The wiki says the guest may need a restart before it sees the disk:

```bash
qm reboot <vmid>
```

---

### When the USB disk is missing

QEMU opens every disk in the VM's configuration when the VM starts. If the USB disk is unplugged, dead, or the by-id path is gone, the Docker VM can refuse to start, and this VM is the DNS server for the whole house. This is inferred from how a missing raw device path behaves and reported on the Proxmox forum, not measured on this lab, confidence high.

If it happens, detach the disk from the VM configuration and start the VM without it:

```bash
qm set <vmid> --delete scsi1
```

```bash
qm start <vmid>
```

Attach it again with the `qm set` command above once the disk is back.

---

### Partition and format it inside the VM

Everything below runs on the Docker VM over SSH, see [proxmox_docker_vm.md](proxmox_docker_vm.md).

Find the new disk. It is the one with no partitions and the size of the USB disk, usually `sdb`:

```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
```

The next two commands erase the disk. Check the name twice.

```bash
sudo parted --script /dev/sdb mklabel gpt mkpart data ext4 0% 100%
```

```bash
sudo mkfs.ext4 -L data /dev/sdb1
```

Read the new file system's UUID:

```bash
sudo blkid /dev/sdb1
```

---

### Mount it by UUID, with nofail

Create the mount point:

```bash
sudo mkdir -p /mnt/data
```

Open the file system table:

```bash
sudo nano /etc/fstab
```

Add one line, with your UUID:

```text
UUID=<uuid> /mnt/data ext4 defaults,nofail,x-systemd.device-timeout=10s 0 2
```

`UUID=` follows the file system, not the device name, so the line keeps working if the disk shows up as `sdc` one day. `nofail` lets the VM finish booting when the disk is missing, so AdGuard keeps answering DNS. `x-systemd.device-timeout=10s` stops the boot from waiting the default 90 seconds for a disk that is not coming.

Mount it and confirm:

```bash
sudo systemctl daemon-reload
```

```bash
sudo mount -a
```

```bash
findmnt /mnt/data
```

One line naming `/dev/sdb1` and `ext4` means it worked. No output means it did not, so fix the line before going on, because a bad `/etc/fstab` line is the classic way to make the next boot stop at an emergency shell.

---

### Folder layout

| Folder | Holds | Used by |
|---|---|---|
| `/mnt/data/files` | Documents, photos, anything you share | File Browser and Samba, read and write |
| `/mnt/data/files/media` | Films and series in the formats from [plex_media_server.md](plex_media_server.md) | File Browser and Samba, read and write, and Plex, read only |

The media folder sits inside the shared folder on purpose, so you copy films to `\\drive.internal\files\media` or upload them in File Browser, with no separate login and no other tool. The cost is that anyone with the Samba login or a File Browser account can also rename or delete a film. Plex cannot, because it mounts the folder read only, but that protects nothing from the people who share the drive.

Create both and give them to user and group `1000`, which every container here writes as:

```bash
sudo mkdir -p /mnt/data/files/media
```

```bash
sudo chown -R 1000:1000 /mnt/data
```

`1000` is the first user on the Ubuntu VM, so it is normally your own login. Check with `id -u` if you are unsure.

The three bind mounts of `/mnt/data` in [compose.yaml](compose.yaml) are written with `create_host_path: false`. If the disk is not mounted, the folder does not exist, and Docker refuses to start File Browser, Samba and Plex instead of quietly creating an empty folder on the VM's system disk and taking your uploads there. A stopped container is the signal to check `findmnt /mnt/data`. Plex has one more way to stop: its mount is `/mnt/data/files/media`, so if someone deletes or renames the `media` folder over the network drive, Plex refuses to start until the folder is back.

---

### File Browser

The image is `gtstef/filebrowser:2.0.0-stable-slim`, File Browser Quantum, and not the original `filebrowser/filebrowser`. The original was the first choice and was ruled out by its own README, read on 2026-10-10: "File Browser is archived on 2026-09-01. The last planned release has already shipped. There will be no further releases, bug fixes, or security fixes." Its last release is v2.63.23 from 27 July 2026, and GitHub reports the repository as archived. Quantum is a maintained fork with a stable channel, `2.0.0-stable` released on 9 October 2026. The `-slim` variant leaves out ffmpeg, so it makes no video thumbnails and cannot convert video, which suits a mini PC where Plex already has the only video budget.

It runs as user `1000`, listens on port 80 inside the container, and keeps its database and config in `/home/filebrowser/data`, which is bind mounted from `/opt/docker-stack/filebrowser/data`. Your files appear inside it at `/srv`.

Create the data folder:

```bash
mkdir -p /opt/docker-stack/filebrowser/data
```

The bind mount hides the config file the image ships with, so write one before the first start:

```bash
nano /opt/docker-stack/filebrowser/data/config.yaml
```

```yaml
http:
  port: 80
  baseURL: "/"
  trustProxyHeaders: true
server:
  sources:
    - path: "/srv"
      name: "files"
auth:
  methods:
    password:
      enabled: true
      minLength: 12
      signup: false
```

`trustProxyHeaders` is there because every visit arrives through Nginx Proxy Manager, and without it File Browser logs the proxy's address instead of yours. `signup: false` means only the admin creates accounts.

---

### File Browser first login

Start it once and read the log:

```bash
cd /opt/docker-stack && docker compose up -d filebrowser
```

```bash
docker logs filebrowser 2>&1 | grep "initial admin password"
```

A fresh install creates the user `admin` with a random password and prints it once, in a line like `Generated initial admin password for user "admin"`. That is what the 2.0.0 changelog means by "Fresh installs with default admin/admin generate a random initial password and log it once (#2977)", and it is what `backend/internal/state/bootstrap_admin_password.go` does at the `v2.0.0-stable` tag. The password is three parts joined by dashes, a word and two short codes.

Open `http://drive.internal`, or `http://<docker-vm-ip>:7782` before the proxy entry exists, and sign in as `admin` with that password.

Change it straight away: open Settings, then User management, edit `admin`, and set a new password of at least 12 characters. Then create a normal account for yourself the same way and use that day to day.

Lost the admin password later? Add one line under `auth:` in `/opt/docker-stack/filebrowser/data/config.yaml`, indented two spaces like `methods:`:

```yaml
  adminPassword: "<new-password>"
```

Restart the container, and on startup File Browser writes that password into the `admin` account. That is `ConfigTriggersAdminPasswordReset` in `backend/pkg/settings/auth.go`, which resets on every start while the value is anything other than blank or `admin`.

```bash
cd /opt/docker-stack && docker compose restart filebrowser
```

Sign in, then delete the line again and restart once more, so the password stays out of the file and a later restart does not undo a change made in the interface.

---

### Samba

The image is `dockurr/samba:4.23.10`. It was picked over `crazymax/samba` for three measured reasons, checked on Docker Hub and GitHub on 2026-10-10. It is configured entirely with environment variables, which is what this stack wants for a user and password, while `crazymax/samba` reads a separate YAML config file. Its newest tag carries Samba 4.23.10, from 22 August 2026, against 4.23.8 from 17 July 2026 for `crazymax/samba`. And its entry script adds `force user` and `force group` for the configured user, so every file written over the network is owned by the `UID` and `GID` you give it, `1000` here, which is the same pair File Browser writes as.

The share is called `files` (the `NAME` variable) and serves `/mnt/data/files`. Only port 445 is published, since the image sets `server min protocol = SMB2` and SMB2 needs nothing else.

The user and password come from a `.env` file next to the Compose file, never from the Compose file itself. The image's own default is `samba` and `secret`, so the Compose file refuses to start without both variables rather than falling back to that. Create the file:

```bash
nano /opt/docker-stack/.env
```

```text
SAMBA_USER=<samba-user>
SAMBA_PASS=<samba-password>
```

Keep it readable by you alone:

```bash
chmod 600 /opt/docker-stack/.env
```

Start it:

```bash
cd /opt/docker-stack && docker compose up -d samba
```

Samba is not web traffic, so Nginx Proxy Manager does not see it and needs no entry. The name `drive.internal` still works for it only because the AdGuard wildcard rewrite from [adguard_dns.md](adguard_dns.md) answers every `.internal` name with the Docker VM's address, and Samba listens on that address directly. Any other `.internal` name would reach the same share, `drive` is just the one that makes sense.

---

### Connect to the network drive

Windows, in File Explorer's address bar:

```text
\\drive.internal\files
```

To keep it as a drive letter, run this in PowerShell and enter the Samba user and password when asked:

```powershell
net use Z: \\drive.internal\files /persistent:yes /user:<samba-user>
```

macOS: in Finder, choose Go, then Connect to Server, and enter `smb://drive.internal/files`.

Linux: in the file manager's address bar, enter `smb://drive.internal/files`.

Android and iOS: in a file manager app that speaks SMB (the iOS Files app does, under Connect to Server), enter `smb://drive.internal/files`.

The server will not appear by itself under Network in Windows, because the image runs no WS-Discovery service, as its README says. Type the address.

---

### Verify

From your own machine, check the web side through the proxy.

Unix shell:

```bash
curl -sI http://drive.internal/health | head -1
```

PowerShell:

```powershell
curl.exe -sI http://drive.internal/health
```

A 200 means File Browser answers through the proxy. Then check that the network drive port answers.

Unix shell:

```bash
nc -zv drive.internal 445
```

PowerShell:

```powershell
Test-NetConnection drive.internal -Port 445
```

Last, the check that matters: upload a text file in File Browser, open it over the network drive, change a line and save. Then open it again in File Browser. Both sides editing the same file without a permission error means the ownership is right.

---

### When it misbehaves

File Browser, Samba or Plex will not start and the error mentions `/mnt/data`. The disk is not mounted. Run `findmnt /mnt/data`, then `sudo mount -a`, and look at the disk on the Proxmox side if that fails.

Only Plex will not start, and the error mentions `/mnt/data/files/media`. The disk is mounted but the `media` folder was deleted or renamed through the network drive or File Browser. Put it back, or create it again with `mkdir /mnt/data/files/media`, then run `docker compose up -d plex`.

The whole Docker VM will not start. The USB disk is missing, see When the USB disk is missing above.

A file saved over Samba cannot be changed in File Browser, or the other way round. Something wrote into `/mnt/data/files` as another user, usually a copy made with `sudo`. Fix it with `sudo chown -R 1000:1000 /mnt/data/files`.

Windows says the network name cannot be found. The PC is not using AdGuard for DNS, so `drive.internal` does not resolve. Try `\\<docker-vm-ip>\files` to tell a DNS problem from a Samba problem.

Windows refuses the password. Windows may offer your Windows login instead of the Samba one. Use `/user:<samba-user>` as in the `net use` command above, or remove the saved entry under Credential Manager.

`drive.internal` returns 502. File Browser is stopped, or the proxy entry uses port 7782 instead of the container port 80.
