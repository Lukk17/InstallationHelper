# Backup and Restore

> Backing up the whole virtual machine with `vzdump`, copying the archive off the host, restoring from it, and the
> service data that a VM image alone does not cover.

---

### What actually needs backing up

Two separate things, and one does not replace the other.

The virtual machine image is bare metal recovery. It brings back the operating system, Docker, and everything on the
disk exactly as it was.

The service data under `/opt/docker-stack/` is what makes the stack yours. AdGuard filters and rewrites, proxy host
entries, dashboard layout, uptime monitors and Syncthing keys all live in those bind mounted directories. The Compose
file recreates empty containers, not your configuration.

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

Archive the whole data root from the VM, not just the Compose file.

```bash
sudo tar czf /tmp/docker-stack-backup.tar.gz -C /opt docker-stack
```

Then pull it down the same way as the VM archive.

Unix shell:

```bash
scp <user>@<docker-vm-ip>:/tmp/docker-stack-backup.tar.gz ~/backups/
```

PowerShell:

```powershell
scp <user>@<docker-vm-ip>:/tmp/docker-stack-backup.tar.gz $HOME\backups\
```

Stopping the stack first gives a cleaner snapshot, since databases written while the archive is being read can end
up inconsistent.

```bash
docker compose down
```

---

### After a restore

Start the VM and confirm it boots and gets the address you expect.

Check that the containers came back up:

```bash
docker ps
```

Open one internal name in a browser. If the name does not resolve, the router is not handing out AdGuard as DNS. If
it resolves but returns 502, the container behind that proxy entry is not running.

---

### Quick reference

| Action | Command |
|---|---|
| Back up a VM | `vzdump <vmid> --storage local --mode snapshot --compress zstd` |
| List archives | `ls -lh /var/lib/vz/dump/` |
| Restore a VM | `qmrestore <archive> <vmid> --storage local-lvm` |
| Archive service data | `sudo tar czf /tmp/docker-stack-backup.tar.gz -C /opt docker-stack` |
