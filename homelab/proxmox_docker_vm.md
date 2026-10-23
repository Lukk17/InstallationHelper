# Docker VM on Proxmox

> Creating the Ubuntu Server virtual machine that runs the Compose stack, installing Docker Engine on it, and freeing
> port 53 so AdGuard Home can bind it.

---

### Before you start

The Proxmox host has to exist first. If you have not built it yet, do [proxmox_host_install.md](proxmox_host_install.md) and come back.

---

### Placeholders

| Placeholder | Meaning |
|---|---|
| `<proxmox-host>` | Address of the Proxmox node, the machine you open on port 8006 |
| `<docker-vm-ip>` | Address the VM gets from your router once it boots |
| `<user>` | Login you create during the Ubuntu install |
| `<vmid>` | The VM ID Proxmox assigns in the General tab of Create VM |
| `<size>` | How many GiB to add to the VM disk, a whole number |

Concrete example, the lab these documents were written from:

```text
<proxmox-host>   192.168.1.10
<docker-vm-ip>   192.168.1.12
```

---

### Get the Ubuntu ISO into Proxmox storage

The installer image has to be in a Proxmox storage pool before the VM wizard can use it. Take the current Ubuntu
Server LTS, AMD64 build.

Downloading directly on the node is the quicker path. Copy the download link from the Ubuntu site, then in the
Proxmox web interface expand your node, click the storage named `local`, select ISO Images, click Download from URL,
paste the link, click Query URL to fill in the filename, and click Download.

Uploading from your own machine works too when the node has no direct internet access. Download the ISO locally,
then use the Upload button on the same ISO Images screen.

---

### Create the VM

Click Create VM in the top right of the Proxmox interface and work through the tabs.

General. Name the machine `docker-vm` and note the VM ID it assigns.

OS. Storage `local`, and pick the Ubuntu ISO you just added.

System. Set the SCSI Controller to VirtIO SCSI single, which gives the disk its own virtual controller and lowers
latency. Tick Qemu Agent so Proxmox and the guest can talk to each other.

Disks. Leave the bus as SCSI 0, pick your VM storage (usually `local-lvm`), and set the size to 100 GiB. Tick Discard
so TRIM commands reach the physical SSD and the host can reclaim freed space. Tick IO Thread so disk work runs on its
own CPU thread instead of stalling the VM.

CPU. One socket, four cores, type `x86-64-v2-AES`. One socket matches one physical slot and keeps scheduling clean on
consumer hardware. The AES type passes hardware encryption acceleration into the VM, which speeds up TLS work in the
reverse proxy.

Memory. 4096 MiB is enough for the whole Compose stack with room to spare.

Network. Bridge `vmbr0`, model VirtIO, firewall unticked.

Confirm the summary and click Finish.

---

### Changing CPU and RAM later

Both are adjustable at any time. Shut the VM down, open its Hardware tab, double click Cores or Memory, change the
value, and boot it again.

To change them while the VM runs, open the Options tab before booting, double click Hotplug, and enable CPU and
Memory hotplugging.

---

### Install Ubuntu Server

Select the VM, click Console, and click Start. Work through the installer.

Tick Install OpenSSH server when the installer offers it. Skip every additional snap, including the Docker one,
because Docker gets installed from its own repository below.

After the reboot, the Summary tab of the VM shows the address it picked up. If no address appears, open the console
and install the guest agent by hand.

```bash
sudo apt update
```

```bash
sudo apt install -y qemu-guest-agent
```

```bash
sudo systemctl enable --now qemu-guest-agent
```

---

### Give the root volume the whole disk

The Ubuntu Server installer puts the system on LVM and, by default, gives the root logical volume only part of the volume group. On this lab it gave `ubuntu-lv` 44 GiB of an 88 GiB partition, and the other half sat unused until the disk filled, see [Grow the Docker VM disk](#grow-the-docker-vm-disk).

Either change the size in the installer's storage screen, by editing `ubuntu-lv` and setting it to the largest size offered, or give it the rest of the volume group right after the first login:

```bash
sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
```

`-l +100%FREE` adds every free extent of `ubuntu-vg`, and `-r` grows the file system in the same step. Check that the size of `/` now matches the partition:

```bash
df -h /
```

---

### Connect over SSH

The Proxmox console has no clipboard integration worth using. Connect from your own machine instead.

Unix shell:

```bash
ssh <user>@<docker-vm-ip>
```

PowerShell:

```powershell
ssh <user>@<docker-vm-ip>
```

---

### Install Docker Engine

These are the official Docker repository steps for Ubuntu. Do not use the `docker.io` package from Ubuntu, it lags
badly and ships no Compose plugin.

```bash
sudo install -m 0755 -d /etc/apt/keyrings
```

```bash
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
```

```bash
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

```bash
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

```bash
sudo apt update
```

```bash
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Add yourself to the `docker` group so you can drop the `sudo` prefix:

```bash
sudo usermod -aG docker $USER
```

```bash
newgrp docker
```

---

### Create the data directory

Persistent service data lives outside the containers, under one root directory.

```bash
sudo mkdir -p /opt/docker-stack
```

The Compose file bind mounts one subdirectory per service beneath it. The quick start in
[README_HOMELAB.md](README_HOMELAB.md) creates them before the first start, so Docker never creates one itself and
hands it to root.

Take ownership of it, so you can edit configuration files over SFTP later without fighting permissions on every save:

```bash
sudo chown -R $USER:$USER /opt/docker-stack
```

Containers that run as a fixed user identifier, Syncthing here, will still want their own subdirectory owned by that
identifier. [syncthing.md](syncthing.md) covers that case.

---

### Free port 53

AdGuard Home needs port 53, and Ubuntu already has `systemd-resolved` listening there. AdGuard will fail to start
until you move it out of the way. Do this before the first `docker compose up`.

Turn the stub listener off in the resolver configuration. Ubuntu ships the line commented out, as `#DNSStubListener=yes`, and this command removes the leading hash and sets it to `no`:

```bash
sudo sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
```

Check it. This must print `DNSStubListener=no`:

```bash
grep '^DNSStubListener=' /etc/systemd/resolved.conf
```

The VM still needs to resolve names for itself, and `/etc/resolv.conf` currently points at the stub listener you just
disabled. Replace it with a static file.

```bash
sudo rm /etc/resolv.conf
```

Write the new file, which holds one line:

```bash
printf 'nameserver 1.1.1.1\n' | sudo tee /etc/resolv.conf
```

Check it. This must print only `nameserver 1.1.1.1`:

```bash
cat /etc/resolv.conf
```

Restart the resolver:

```bash
sudo systemctl restart systemd-resolved
```

Confirm nothing holds port 53 any more:

```bash
sudo ss -lntup | grep ':53 '
```

Empty output means the port is free. If something still holds it, find out what before starting the stack.

Masking `systemd-resolved` outright is the heavier alternative. It also frees the port, and the static
`/etc/resolv.conf` above keeps name resolution working, but it removes the resolver from the system entirely rather
than just moving it off the port.

---

### Grow the Docker VM disk

Growing the disk takes two halves. Proxmox makes the virtual disk bigger, and then Ubuntu has to grow the partition, the LVM physical volume, the root logical volume and the file system on it, in that order. A reboot alone does not grow the partition or the file system. The Proxmox side is covered in more depth by the [proxmox skill](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/proxmox/SKILL.md).

In the Proxmox web interface, select the VM, open Hardware, select Hard Disk (scsi0), click Disk Action, then Resize, and enter the number of GiB to add. The same thing from the shell of the Proxmox host:

```bash
qm disk resize <vmid> scsi0 +<size>G
```

Concrete example, the lab these documents were written from. The Docker VM there is ID 101, named `docker-vm`, on the Proxmox node `proxmox`, running Proxmox VE 8.3.2. Adding 50 GiB to it:

```bash
qm disk resize 101 scsi0 +50G
```

The disk can only grow. Proxmox cannot shrink it again, so add only what you need.

Do the rest inside the VM over SSH rather than in the Proxmox console, because the console has no copy and paste and the commands below are long. Unix shell:

```bash
ssh <user>@<docker-vm-ip>
```

PowerShell:

```powershell
ssh <user>@<docker-vm-ip>
```

Look at the disks first:

```bash
lsblk
```

The commands below assume the system disk is `sda`, the one that holds `sda3` and `ubuntu--vg-ubuntu--lv`. The USB data disk from [lan_storage.md](lan_storage.md) is usually `sdb`. If the names are the other way round on your VM, use the system disk's name in every command.

If `sda` still shows the old size, tell the kernel to read it again:

```bash
echo 1 | sudo tee /sys/class/block/sda/device/rescan
```

Grow partition 3 into the new space:

```bash
sudo growpart /dev/sda 3
```

Tell LVM the physical volume on it is bigger:

```bash
sudo pvresize /dev/sda3
```

Give the root logical volume all the free space in the volume group, and grow its file system in the same step:

```bash
sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
```

Check the result:

```bash
df -h /
```

#### When the disk is already full

If the root file system is completely full, `pvresize` fails, because LVM first writes a backup of its metadata under `/etc/lvm` and has no room for it. Measured on this lab on 2026-10-23, the output was:

```text
/etc/lvm/archive/...: write error failed: No space left on device
Failed to store physical volume "/dev/sda3" in volume group "ubuntu-vg"
```

Free a little space first and run `pvresize` again. These two commands freed about 64 MB on this lab, which was enough:

```bash
sudo apt clean
```

```bash
sudo journalctl --vacuum-size=100M
```

If nothing can be freed, skip the metadata backup for this one run:

```bash
sudo pvresize --config 'backup { backup = 0 archive = 0 }' /dev/sda3
```

#### What a full disk did on this lab

The root logical volume had been left at the installer's 44 GiB while `sda3` was 88 GiB, which `lsblk` showed as `sda3 88G` and `ubuntu--vg-ubuntu--lv 44G`. When the 44 GiB filled, at 2026-10-22 23:58:

1. Syncthing stopped both folders with `insufficient space on disk for database (/config/index-v2): current 0.00 % < required 1 %`, and failed to save its configuration with `no space left on device`. See [syncthing.md](syncthing.md).
2. Telegraf could not write its rows for [network_watch.md](network_watch.md), so the rows from that time are lost.

After the disk was grown and the steps above were run, the root volume was 138 GiB and `df -h /` showed a size of 136G, 43G used and 87G free. What filled the 43 GB has not been measured yet. Nothing in this lab warns before the root file system fills, so look at `df -h /` whenever you are on the VM. To avoid the trap on a new VM, see [Give the root volume the whole disk](#give-the-root-volume-the-whole-disk).

---

### Next

Go back to [README_HOMELAB.md](README_HOMELAB.md) for the quick start, then configure
[adguard_dns.md](adguard_dns.md) and [nginx_proxy_manager.md](nginx_proxy_manager.md).

The other virtual machine on this host, for the smart home side, is [home_assistant_vm.md](home_assistant_vm.md).
