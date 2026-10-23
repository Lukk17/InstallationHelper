# LAN Storage

> A USB disk on the Proxmox host, handed whole to the Docker VM and shared at its root, which you open in a browser at `http://files.internal` and as a network drive at `\\files.internal\files`.

---

### What you get

The whole disk, mounted at `/mnt/data` on the Docker VM, reached two ways.

| Way in | Address | Good for |
|---|---|---|
| File Browser, in a browser | `http://files.internal` | Phones, someone else's laptop, a quick upload or download |
| Samba, as a network drive | `\\files.internal\files` on Windows, `smb://files.internal/files` everywhere else | Working on files in place from a desktop, copying many files at once |

`files` is only the name of the network share. It is not a folder on the disk: the share opens at the top of the disk.

Both containers write as user `1000` and group `1000`, so a file uploaded in File Browser can be edited over Samba, and the other way round.

The Plex library is the `media` folder at the top of the disk, `/mnt/data/media`, so films go in through the same two ways as any other file. Plex itself is covered in [plex_media_server.md](plex_media_server.md).

The disk is shared at its root, with no subfolder in between, because this lab's disk is an existing 120 GB NTFS disk that already holds films and series in a `media` folder at its top, and the owner decided on 2026-10-23 not to reorganise it. A new empty disk gets the same layout, so one Compose file serves both.

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
| `<user>` | Your login on the Docker VM, from [proxmox_docker_vm.md](proxmox_docker_vm.md) |
| `<vmid>` | The Docker VM's number in Proxmox |
| `<disk-id>` | The USB disk's name under `/dev/disk/by-id/`, starting with `usb-` |
| `<uuid>` | The file system UUID of the data partition, from `blkid` |
| `<samba-user>` | The login for the network drive, your choice |
| `<samba-password>` | The password for that login, your choice |

Concrete example, the lab these documents were written from:

```text
<proxmox-host>   192.168.1.10
<docker-vm-ip>   192.168.1.12
<user>           lukk
<vmid>           101
<disk-id>        usb-ASMedia_AS2115_201403060029-0:0
<uuid>           C49A58159A5805F8
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

Pick the line for the whole disk, the one whose name does not end in `-part1` or similar. It looks like `usb-JMicron_Generic_0123456789ABCDEF-0:0 -> ../../sdc`. On this lab it is `usb-ASMedia_AS2115_201403060029-0:0`.

Use that `/dev/disk/by-id/usb-...` path, never `/dev/sdc`. The Proxmox wiki says it plainly, under Identify Disk on [Passthrough Physical Disk to Virtual Machine](https://pve.proxmox.com/wiki/Passthrough_Physical_Disk_to_Virtual_Machine_(VM)) (page last edited 6 December 2022, read 2026-10-10): "Note that device names like /dev/sdc should never be used, as this can change between reboots. Use the stable /dev/disk/by-id paths instead."

---

### Attach it to the Docker VM

This hands the whole disk to the VM as a second virtual SCSI disk. It is not USB device passthrough, so the VM sees an ordinary disk and the host keeps the USB side.

```bash
qm set <vmid> -scsi1 /dev/disk/by-id/<disk-id>,backup=0
```

On this lab:

```bash
qm set 101 -scsi1 /dev/disk/by-id/usb-ASMedia_AS2115_201403060029-0:0,backup=0
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

### New disk or a disk with files: pick your path

Everything from here on runs on the Docker VM over SSH, see [proxmox_docker_vm.md](proxmox_docker_vm.md).

Find the disk. It is the one with the size of the USB disk that is not the system disk, usually `sdb`:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
```

Then ask what is on its first partition:

```bash
sudo blkid /dev/sdb1
```

Pick one path from what that prints:

1. No output, or the disk has no partition at all: a new empty disk. Follow [Path A: a new empty disk](#path-a-a-new-empty-disk), which partitions and formats it.
2. `TYPE="ntfs"`, or any other `TYPE=` on a disk whose files you want to keep: follow [Path B: an existing NTFS disk with files to keep](#path-b-an-existing-ntfs-disk-with-files-to-keep). It formats nothing. On this lab the command printed `TYPE="ntfs"` and `UUID="C49A58159A5805F8"`, and the disk held the owner's films.

Path A erases the whole disk. Never run its `parted` or `mkfs.ext4` command on a disk that holds files you want.

Both paths start with the same step, below.

---

### Protect the empty mount point

The mount point is the empty folder `/mnt/data` on the VM's system disk, where the USB disk appears once it is mounted. If the USB disk is not mounted, after a boot without it or after a failed mount, File Browser and Samba still find a folder at `/mnt/data`, the empty one, and without protection they would write uploads into it, onto the system disk, until it is full. The immutable flag stops that: a folder with the flag refuses every new file, for root too.

Create the mount point:

```bash
sudo mkdir -p /mnt/data
```

Check that nothing is mounted there yet:

```bash
findmnt /mnt/data
```

It must print nothing. If it prints a line, the disk is already mounted and the flag would land on the USB disk instead of the empty folder. Stop the three containers that use it, then unmount it:

```bash
cd /opt/docker-stack && docker compose stop filebrowser samba plex
```

```bash
sudo umount /mnt/data
```

Set the flag on the empty folder:

```bash
sudo chattr +i /mnt/data
```

Check it. The letters printed before the path include an `i`:

```bash
lsattr -d /mnt/data
```

And prove it, while the disk is still not mounted. This must fail with `Operation not permitted`:

```bash
sudo touch /mnt/data/test
```

Why this works for a mount point, from the sources, each read on 2026-10-23:

1. What the flag does. The chattr manual from e2fsprogs 1.47.4, as published on [man7.org](https://man7.org/linux/man-pages/man1/chattr.1.html): "A file with the 'i' attribute cannot be modified: it cannot be deleted or renamed, no link can be created to this file, most of the file's metadata can not be modified, and the file can not be opened in write mode. Only the superuser or a process possessing the CAP_LINUX_IMMUTABLE capability can set or clear this attribute."
2. That it covers new files in a folder, for root too. The Linux kernel's [fs/namei.c](https://github.com/torvalds/linux/blob/master/fs/namei.c) checks every new name in a folder in `may_create_dentry`, whose comment says "We can't do it if dir is immutable (done in permission())", and `inode_permission` answers `-EPERM` with the comment "Nobody gets write access to an immutable file." before it looks at who is asking.
3. That a mounted disk hides it. The mount manual from util-linux, page dated 2026-08-03 on [man7.org](https://man7.org/linux/man-pages/man8/mount.8.html): "The previous contents (if any) and owner and mode of dir become invisible, and as long as this filesystem remains mounted, the pathname dir refers to the root of the filesystem on device." So while the USB disk is mounted, `/mnt/data` is the disk's own top folder, the flag on the empty folder underneath has no effect, and writes go to the USB disk.

Confidence high, from those three sources. The flag on a mount point was not measured on this lab. The `touch` check above proves the first half on your own VM, and the write check in [Verify](#verify) proves the second.

The flag needs a system disk whose file system keeps it. ext4, the Ubuntu installer's default, does. If `chattr` answers `Operation not supported`, it does not, and this protection is missing.

If you had to unmount the disk above, it was set up before this step existed and its line in `/etc/fstab` is already there. Do not add a second one: go straight to [Mount it and confirm](#mount-it-and-confirm).

To remove the folder one day, clear the flag first, with the disk unmounted:

```bash
sudo chattr -i /mnt/data
```

---

### Path A: a new empty disk

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

Add the mount to the file system table, with your UUID. Run it once, because every run adds one more line:

```bash
echo 'UUID=<uuid> /mnt/data ext4 defaults,nofail,x-systemd.device-timeout=10s 0 2' | sudo tee -a /etc/fstab
```

`UUID=` follows the file system, not the device name, so the line keeps working if the disk shows up as `sdc` one day. `nofail` lets the VM finish booting when the disk is missing, so AdGuard keeps answering DNS. `x-systemd.device-timeout=10s` stops the boot from waiting the default 90 seconds for a disk that is not coming.

Then go on with [Mount it and confirm](#mount-it-and-confirm).

---

### Path B: an existing NTFS disk with files to keep

Nothing here formats or partitions the disk. The kernel's own NTFS driver, `ntfs3`, mounts it as it is, read and write.

Check that the kernel has the driver. This prints the driver's file, and `Module ntfs3 not found` means this kernel lacks it:

```bash
modinfo -n ntfs3
```

Measured on this lab on 2026-10-23: Ubuntu's kernel `7.0.0-34-generic` has `ntfs3`, and `ntfs-3g` 2022.10.3 is installed, which brings the `ntfsfix` tool used below. If `ntfsfix` is missing on your VM, install it:

```bash
sudo apt install ntfs-3g
```

Add the mount to the file system table, with the UUID `blkid` printed. Run it once, because every run adds one more line:

```bash
echo 'UUID=<uuid> /mnt/data ntfs3 defaults,nofail,uid=1000,gid=1000,x-systemd.device-timeout=10s 0 0' | sudo tee -a /etc/fstab
```

On this lab:

```bash
echo 'UUID=C49A58159A5805F8 /mnt/data ntfs3 defaults,nofail,uid=1000,gid=1000,x-systemd.device-timeout=10s 0 0' | sudo tee -a /etc/fstab
```

NTFS has no Linux owners, so `uid=1000,gid=1000` makes every file on the disk belong to user and group `1000`, the pair every container here writes as. That is why this path has no `chown` step. `nofail` and `x-systemd.device-timeout=10s` do what they do in path A. The last field is `0` because there is no Linux file system check for NTFS at boot.

Then go on with [Mount it and confirm](#mount-it-and-confirm). If the mount fails with `wrong fs type, bad option, bad superblock`, read [A dirty NTFS disk](#a-dirty-ntfs-disk) below.

---

### A dirty NTFS disk

Windows marks an NTFS disk as dirty while it is in use and clears the mark when the disk is removed safely. A disk pulled out of a Windows machine without safe removal keeps the mark, and `ntfs3` refuses to mount it.

Measured on this lab on 2026-10-23: the first `sudo mount -a` failed with `wrong fs type, bad option, bad superblock`, and the kernel log said why. Read it with:

```bash
sudo dmesg | grep ntfs3
```

The line was `ntfs3(sdb1): volume is dirty and "force" flag is not set!`. The `force` mount option would mount it anyway, and the [ntfs3 documentation](https://docs.kernel.org/filesystems/ntfs3.html) says of it "Forces the driver to mount partitions even if volume is marked dirty. Not recommended for use.", so this page does not use it.

Clear the mark instead:

```bash
sudo ntfsfix -d /dev/sdb1
```

Then mount again with `sudo mount -a`. On this lab that worked at once.

What `ntfsfix` is and is not, from its manual as published for ntfs-3g on [man.archlinux.org](https://man.archlinux.org/man/ntfsfix.8), read on 2026-10-23: "ntfsfix is NOT a Linux version of chkdsk. It only repairs some fundamental NTFS inconsistencies, resets the NTFS journal file and schedules an NTFS consistency check for the first boot into Windows." For `-d` it says "Clear the volume dirty flag if the volume can be fixed and mounted." If the disk was pulled out in the middle of a copy and its files matter more than the time, the safer way is to plug it into a Windows machine, let it check the disk, and remove it safely from there.

The mark comes back every time the disk leaves a Windows machine without safe removal. With `nofail` the VM still boots, the disk is simply not mounted, and the flag from [Protect the empty mount point](#protect-the-empty-mount-point) keeps File Browser and Samba from writing to the system disk.

---

### Mount it and confirm

Check that the file system table has exactly one line for the disk:

```bash
grep /mnt/data /etc/fstab
```

Then mount it:

```bash
sudo systemctl daemon-reload
```

```bash
sudo mount -a
```

```bash
findmnt /mnt/data
```

One line naming `/dev/sdb1` means it worked. No output means it did not, so fix the line before going on, because a bad `/etc/fstab` line is the classic way to make the next boot stop at an emergency shell.

On this lab, after path B, `findmnt` printed:

```text
/mnt/data /dev/sdb1 ntfs3 rw,relatime,uid=1000,gid=1000,acl,iocharset=utf8,prealloc
```

---

### Folder layout

| Folder | Holds | Used by |
|---|---|---|
| `/mnt/data` | Everything on the disk: documents, photos, anything you share | File Browser and Samba, read and write |
| `/mnt/data/media` | Films and series in the formats from [plex_media_server.md](plex_media_server.md) | File Browser and Samba, read and write, and Plex, read only |

The `media` folder sits on the shared disk on purpose, so you copy films to `\\files.internal\files\media` or upload them in File Browser, with no separate login and no other tool. The cost is that anyone with the Samba login or a File Browser account can also rename or delete a film. Plex cannot, because it mounts the folder read only, but that protects nothing from the people who share the drive.

The name is `media` in lower case. Linux tells `Media` and `media` apart, so a folder called `Media` is not the library.

On path A, create the folder and give the whole disk to user and group `1000`, which every container here writes as:

```bash
sudo mkdir -p /mnt/data/media
```

```bash
sudo chown -R 1000:1000 /mnt/data
```

`1000` is the first user on the Ubuntu VM, so it is normally your own login. Check with `id -u` if you are unsure.

On path B, the owner comes from the mount options, so there is nothing to change. If the disk has no `media` folder yet, create it as yourself, without `sudo`:

```bash
mkdir -p /mnt/data/media
```

The three bind mounts of the disk in [compose.yaml](compose.yaml) are written with `create_host_path: false`, so Docker refuses to start a container whose folder is missing instead of quietly creating it on the system disk. For Plex that is the protection: its folder, `/mnt/data/media`, exists only on the USB disk, so with the disk not mounted Plex refuses to start. For File Browser and Samba it no longer protects anything, because their folder is `/mnt/data` itself, and the empty mount point is always there. The immutable flag from [Protect the empty mount point](#protect-the-empty-mount-point) protects them instead. Plex has one more way to stop: if someone deletes or renames the `media` folder over the network drive, Plex refuses to start until the folder is back.

---

### File Browser

The image is `gtstef/filebrowser:2.0.0-stable-slim`, File Browser Quantum, and not the original `filebrowser/filebrowser`. The original was the first choice and was ruled out by its own README, read on 2026-10-10: "File Browser is archived on 2026-09-01. The last planned release has already shipped. There will be no further releases, bug fixes, or security fixes." Its last release is v2.63.23 from 27 July 2026, and GitHub reports the repository as archived. Quantum is a maintained fork with a stable channel, `2.0.0-stable` released on 9 October 2026. The `-slim` variant leaves out ffmpeg, so it makes no video thumbnails and cannot convert video, which suits a mini PC where Plex already has the only video budget.

It runs as user `1000`, listens on port 80 inside the container, and keeps its database and config in `/home/filebrowser/data`, which is bind mounted from `/opt/docker-stack/filebrowser/data`. The whole disk appears inside it at `/srv`.

Create the data folder:

```bash
mkdir -p /opt/docker-stack/filebrowser/data
```

The bind mount hides the config file the image ships with, so write one before the first start. This one command writes the whole file:

```bash
printf '%s\n' 'http:' '  port: 80' '  baseURL: "/"' '  trustProxyHeaders: true' 'server:' '  sources:' '    - path: "/srv"' '      name: "files"' 'auth:' '  methods:' '    password:' '      enabled: true' '      minLength: 12' '      signup: false' > /opt/docker-stack/filebrowser/data/config.yaml
```

Check it:

```bash
cat /opt/docker-stack/filebrowser/data/config.yaml
```

It must read:

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

Open `http://files.internal`, or `http://<docker-vm-ip>:7782` before the proxy entry exists, and sign in as `admin` with that password.

Change it straight away: open Settings, then User management, edit `admin`, and set a new password of at least 12 characters. Then create a normal account for yourself the same way and use that day to day.

Lost the admin password later? Add an `adminPassword` line to the `auth:` part of the config. `auth:` is the last part of the file, so a line added at the end with two spaces in front belongs to it.

Type the new password. It is not shown, and the `echo` only moves to a new line afterwards. Leave out double quotes and backslashes, because the value goes between double quotes in the file, where a `"` ends it and a `\` starts an escape:

```bash
read -r -s -p 'New File Browser admin password: ' FB_ADMIN_PASS; echo
```

Add the line:

```bash
printf '  adminPassword: "%s"\n' "$FB_ADMIN_PASS" >> /opt/docker-stack/filebrowser/data/config.yaml
```

Remove the value from the shell:

```bash
unset FB_ADMIN_PASS
```

Check that the line is there, without printing it. This must print 1:

```bash
grep -c '^  adminPassword:' /opt/docker-stack/filebrowser/data/config.yaml
```

Restart the container, and on startup File Browser writes that password into the `admin` account. That is `ConfigTriggersAdminPasswordReset` in `backend/pkg/settings/auth.go`, which resets on every start while the value is anything other than blank or `admin`.

```bash
cd /opt/docker-stack && docker compose restart filebrowser
```

Sign in, then delete the line again and restart once more, so the password stays out of the file and a later restart does not undo a change made in the interface:

```bash
sed -i '/^  adminPassword:/d' /opt/docker-stack/filebrowser/data/config.yaml
```

Check it. This must print 0:

```bash
grep -c '^  adminPassword:' /opt/docker-stack/filebrowser/data/config.yaml
```

```bash
cd /opt/docker-stack && docker compose restart filebrowser
```

---

### Samba

The image is `dockurr/samba:4.23.10`. It was picked over `crazymax/samba` for three measured reasons, checked on Docker Hub and GitHub on 2026-10-10. It is configured entirely with environment variables, which is what this stack wants for a user and password, while `crazymax/samba` reads a separate YAML config file. Its newest tag carries Samba 4.23.10, from 22 August 2026, against 4.23.8 from 17 July 2026 for `crazymax/samba`. And its entry script adds `force user` and `force group` for the configured user, so every file written over the network is owned by the `UID` and `GID` you give it, `1000` here, which is the same pair File Browser writes as.

The share is called `files` (the `NAME` variable) and serves the whole disk, `/mnt/data`. Only port 445 is published, since the image sets `server min protocol = SMB2` and SMB2 needs nothing else.

---

### The Samba login file

The network drive has its own user and password. You make both up here. They are not your Ubuntu login, not your Windows login, and not taken from anywhere else: the Samba container creates this one user from them, and it exists only for the network drive.

They live in a `.env` file next to the Compose file, never in the Compose file itself. The image's own default is `samba` and `secret`, so the Compose file refuses to start without both values rather than falling back to that. Compose reads the values whenever it reads the file, so until they are there, every `docker compose` command for the whole stack stops, not only the one for Samba.

Type the user name. It is shown as you type:

```bash
read -r -p 'Samba user: ' SAMBA_USER
```

Type the password. It is not shown, and the `echo` only moves to a new line afterwards. Leave out `$`, `#` and quotes: the Docker Compose page [Interpolation](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/), read on 2026-10-23, says of this file that "Unquoted and double-quoted (\") values have interpolation applied", so a `$` starts a variable name, and a space followed by `#` starts a comment:

```bash
read -r -s -p 'Samba password: ' SAMBA_PASS; echo
```

Write both into the file. This replaces the whole file, so if it already holds other lines, such as `PLEX_CLAIM`, add them again afterwards:

```bash
printf 'SAMBA_USER=%s\nSAMBA_PASS=%s\n' "$SAMBA_USER" "$SAMBA_PASS" > /opt/docker-stack/.env
```

Keep it readable by you alone:

```bash
chmod 600 /opt/docker-stack/.env
```

Remove the two values from the shell:

```bash
unset SAMBA_USER SAMBA_PASS
```

Check that neither value is empty, without printing them. This prints each name and the length of its value:

```bash
awk -F= '{print $1, length($2)}' /opt/docker-stack/.env
```

Both numbers must be above 0. A 0 means that value is empty, so run the steps above again. On this lab the first attempt left `SAMBA_USER` empty, and Compose refused with `required variable SAMBA_USER is missing a value`.

Start Samba:

```bash
cd /opt/docker-stack && docker compose up -d samba
```

Samba is not web traffic, so Nginx Proxy Manager does not see it and needs no entry. The name `files.internal` still works for it only because the AdGuard wildcard rewrite from [adguard_dns.md](adguard_dns.md) answers every `.internal` name with the Docker VM's address, and Samba listens on that address directly. Any other `.internal` name would reach the same share, `files` is just the one that makes sense.

---

### Connect to the network drive

Windows, in File Explorer's address bar:

```text
\\files.internal\files
```

To keep it as a drive letter, run this in PowerShell and enter the Samba user and password when asked:

```powershell
net use Z: \\files.internal\files /persistent:yes /user:<samba-user>
```

macOS: in Finder, choose Go, then Connect to Server, and enter `smb://files.internal/files`.

Linux: in the file manager's address bar, enter `smb://files.internal/files`. In Dolphin, see the next section.

Android and iOS: in a file manager app that speaks SMB (the iOS Files app does, under Connect to Server), enter `smb://files.internal/files`.

The server will not appear by itself under Network in Windows, because the image runs no WS-Discovery service, as its README says. Type the address.

---

### Open the Docker VM in Dolphin

Dolphin, the KDE file manager, opens two things on the VM: the stack's own folder over SFTP, with the same SSH key an agent uses, and the shared disk over Samba.

The SFTP part needs the key `~/.ssh/homelab_agent_ed25519` already accepted by the VM, as steps 1 to 3 of DOCKER_VM_SSH in [agent_access.md](agent_access.md#docker_vm_ssh) set up.

On your own machine, give the VM a short name in your SSH config:

```bash
printf '\nHost docker-vm\n    HostName <docker-vm-ip>\n    User <user>\n    IdentityFile ~/.ssh/homelab_agent_ed25519\n' >> ~/.ssh/config
```

On this lab:

```bash
printf '\nHost docker-vm\n    HostName 192.168.1.12\n    User lukk\n    IdentityFile ~/.ssh/homelab_agent_ed25519\n' >> ~/.ssh/config
```

Run it once, because every run adds the block again. Check that the name works without a password. `BatchMode=yes` makes `ssh` fail instead of asking for one:

```bash
ssh -o BatchMode=yes docker-vm hostname
```

Then, in Dolphin, press Ctrl+L, type this address and press Enter:

```text
sftp://docker-vm/opt/docker-stack
```

Dolphin lists `compose.yaml` and the per-service folders, and you work in them as `<user>`. Measured working on this lab on 2026-10-23 with kio-extras 26.08.2.

For the shared disk, press Ctrl+L again and enter the Samba address, then sign in with the Samba user and password from [The Samba login file](#the-samba-login-file):

```text
smb://<docker-vm-ip>/files
```

On this lab that is `smb://192.168.1.12/files`. `smb://files.internal/files` works as well once your machine uses AdGuard for DNS.

---

### Verify

From your own machine, check the web side through the proxy.

Unix shell:

```bash
curl -sI http://files.internal/health | head -1
```

PowerShell:

```powershell
curl.exe -sI http://files.internal/health
```

A 200 means File Browser answers through the proxy. Then check that the network drive port answers.

Unix shell:

```bash
nc -zv files.internal 445
```

PowerShell:

```powershell
Test-NetConnection files.internal -Port 445
```

Last, the check that matters: upload a text file in File Browser, open it over the network drive, change a line and save. Then open it again in File Browser. Both sides editing the same file without a permission error means the ownership is right, and that writes reach the USB disk rather than the protected mount point.

---

### When it misbehaves

Plex will not start and the error mentions `/mnt/data/media`. Either the disk is not mounted, or it is mounted but the `media` folder was deleted or renamed through the network drive or File Browser. Run `findmnt /mnt/data`. No output means the disk is not mounted: run `sudo mount -a` and look at the disk on the Proxmox side if that fails. A line means the folder is gone: put it back, or create it again with `mkdir /mnt/data/media`, then run `docker compose up -d plex`.

File Browser shows an empty folder, and every upload or new file over the network drive fails with a permission error. The disk is not mounted, and the immutable flag is doing its job. Run `findmnt /mnt/data`, then `sudo mount -a`.

`sudo mount -a` fails with `wrong fs type, bad option, bad superblock` on an NTFS disk. The disk is marked dirty, see [A dirty NTFS disk](#a-dirty-ntfs-disk).

Any `docker compose` command stops with `required variable SAMBA_USER is missing a value`, or the same for `SAMBA_PASS`. The value is missing or empty in `/opt/docker-stack/.env`. Write the file again as in [The Samba login file](#the-samba-login-file) and check it with the `awk` command there.

The whole Docker VM will not start. The USB disk is missing, see When the USB disk is missing above.

A file saved over Samba cannot be changed in File Browser, or the other way round, on an ext4 disk from path A. Something wrote into `/mnt/data` as another user, usually a copy made with `sudo`. Fix it with `sudo chown -R 1000:1000 /mnt/data`. On an NTFS disk from path B every file belongs to `1000` through the mount options, so this cannot happen there.

Windows says the network name cannot be found. The PC is not using AdGuard for DNS, so `files.internal` does not resolve. Try `\\<docker-vm-ip>\files` to tell a DNS problem from a Samba problem.

Windows refuses the password. Windows may offer your Windows login instead of the Samba one. Use `/user:<samba-user>` as in the `net use` command above, or remove the saved entry under Credential Manager.

`files.internal` returns 502. File Browser is stopped, or the proxy entry uses port 7782 instead of the container port 80.
