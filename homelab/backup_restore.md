# Backup and Restore

> Backing up the whole virtual machine with `vzdump`, copying the archive off the host, restoring from it, and the
> service data that a VM image alone does not cover.

---

### What actually needs backing up

Four separate things, and none of them replaces the others.

The virtual machine image is bare metal recovery. It brings back the operating system, Docker, and everything on the
disk exactly as it was.

The service data under `/opt/docker-stack/` is what makes the stack yours. AdGuard filters and rewrites, proxy host
entries, dashboard layout, uptime monitors, Syncthing keys, the File Browser accounts, the Plex database and the `.env`
file with the Samba login all live there. The Compose
file recreates empty containers, not your configuration.

The USB data disk under `/mnt/data`, holding the shared files and the Plex library inside them, is in no backup here. It is attached to the Docker VM with `backup=0`, so `vzdump` skips it, and the service data archive below covers `/opt/docker-stack/` only. That is on purpose, since copying the whole disk onto the NVMe on every run would fill it, and it is also why the disk has no second copy. Keep irreplaceable files in Syncthing as well, which puts a real copy on every paired machine, see [syncthing.md](syncthing.md) and [lan_storage.md](lan_storage.md).

Home Assistant backs itself up, and it has to, because a `vzdump` of that machine restores only onto Proxmox while a
Home Assistant backup restores onto anything. It has its own page: [home_assistant_backup.md](home_assistant_backup.md).

---

### Back up the VM

From the interface, select the VM, open Backup, and click Backup now. Choose storage `local`, because archives live
there rather than on `local-lvm`. Mode Snapshot takes a live backup with no downtime, mode Stop guarantees a fully
consistent image at the cost of a short outage. Compression ZSTD is fast and compresses well.

From the node shell:

```bash
vzdump <vmid> --storage local --mode snapshot --compress zstd
```

The archive lands in `/var/lib/vz/dump/` as `vzdump-qemu-<vmid>-<timestamp>.vma.zst`. List what is there:

```bash
ls -lh /var/lib/vz/dump/
```

A backup sitting on the same disk as the machine it protects is not a backup. If that disk dies, both die together.
Copy it off the host, and put the host on a UPS so an unclean shutdown does not corrupt the drive in the first place.

---

### Copy the archive to your machine

Unix shell:

```bash
scp root@<proxmox-host>:/var/lib/vz/dump/vzdump-qemu-<vmid>-*.vma.zst ~/backups/
```

PowerShell:

```powershell
scp root@<proxmox-host>:/var/lib/vz/dump/vzdump-qemu-<vmid>-*.vma.zst $HOME\backups\
```

The `.vma.zst` file is the archive. The `.log` and `.notes` files beside it are metadata and are not needed to
restore.

---

### Restore the VM

When the archive is still on the host, open the node, then `local`, then Backups, select the archive and click
Restore. Set storage to `local-lvm`, and either reuse the original VM ID or pick a new one if the source machine
still exists.

From the shell:

```bash
qmrestore /var/lib/vz/dump/vzdump-qemu-<vmid>-<timestamp>.vma.zst <vmid> --storage local-lvm
```

Add `--force` to overwrite an existing VM ID, or restore into a free ID instead and keep the original untouched
until you have confirmed the new one boots.

When the archive is on your own machine, it has to go back to a Proxmox backup storage first. Upload it through the
Backups screen, or push it over SSH.

Unix shell:

```bash
scp ~/backups/vzdump-qemu-<vmid>-<timestamp>.vma.zst root@<proxmox-host>:/var/lib/vz/dump/
```

PowerShell:

```powershell
scp $HOME\backups\vzdump-qemu-<vmid>-<timestamp>.vma.zst root@<proxmox-host>:/var/lib/vz/dump/
```

Then restore it as above.

---

### Back up the service data

Stopping the stack first gives a cleaner snapshot, since databases written while the archive is being read can end
up inconsistent.

```bash
cd /opt/docker-stack && docker compose down
```

Archive the whole data root from the VM, not just the Compose file.

```bash
sudo tar czf /tmp/docker-stack-backup.tar.gz -C /opt docker-stack
```

Start the stack again now that the archive has been taken.

```bash
cd /opt/docker-stack && docker compose up -d
```

Then pull the archive down the same way as the VM archive.

Unix shell:

```bash
scp <user>@<docker-vm-ip>:/tmp/docker-stack-backup.tar.gz ~/backups/
```

PowerShell:

```powershell
scp <user>@<docker-vm-ip>:/tmp/docker-stack-backup.tar.gz $HOME\backups\
```

A graphical SFTP client is the easier route if you would rather drag the directory across than build an archive.
Connect to `<docker-vm-ip>` on port 22 with the Ubuntu login you created, and copy `/opt/docker-stack` down whole.
Restoring the same way means deleting the directory on the machine first, then copying your copy back in its place,
because a merge over the top leaves stale files behind that a service may still read.

---

### After a restore

Check the hardware before you start the machine, because two things a `vzdump` does not reliably carry back are the
two that break silently.

USB passthrough. Confirm the device is listed under the VM, then Hardware, and add it again if it is not:

```bash
qm set <vmid> --usb0 host=10c4:ea60
```

The USB data disk on the Docker VM. Confirm `scsi1` still names the disk's `/dev/disk/by-id/` path with `backup=0`,
and attach it again as in [lan_storage.md](lan_storage.md) if it does not:

```bash
qm config <vmid> | grep scsi1
```

The network card's hardware address, if you had cloned it to hold a fixed lease:

```bash
qm config <vmid> | grep net0
```

Then start the VM and confirm it boots and gets the address you expect.

Check that the containers came back up:

```bash
docker ps
```

If the service data you restored was saved before 2026-10-10, its `.env` has no `SAMBA_USER` and `SAMBA_PASS`, and the current Compose file refuses to run without them, so every `docker compose` command for the stack stops with an error naming the missing variable. Add both lines to `/opt/docker-stack/.env` as in the upgrade note in [README_HOMELAB.md](README_HOMELAB.md), then start the stack again:

```bash
cd /opt/docker-stack && docker compose up -d
```

Open one internal name in a browser. If the name does not resolve, the router is not handing out AdGuard as DNS. If
it resolves but returns 502, the container behind that proxy entry is not running.

On a restored Home Assistant machine, confirm the Zigbee dongle appears inside the guest and that the add-on actually
started, as covered in [home_assistant_vm.md](home_assistant_vm.md). Entities can look present and be stale.

---

### Quick reference

| Action | Command |
|---|---|
| Back up a VM | `vzdump <vmid> --storage local --mode snapshot --compress zstd` |
| List archives | `ls -lh /var/lib/vz/dump/` |
| Restore a VM | `qmrestore <archive> <vmid> --storage local-lvm` |
| Archive service data | `sudo tar czf /tmp/docker-stack-backup.tar.gz -C /opt docker-stack` |
