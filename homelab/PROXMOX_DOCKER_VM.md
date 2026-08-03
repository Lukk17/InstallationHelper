# Docker VM on Proxmox

> Creating the Ubuntu Server virtual machine that runs the Compose stack, installing Docker Engine on it, and freeing
> port 53 so AdGuard Home can bind it.

---

### Placeholders

| Placeholder | Meaning |
|---|---|
| `<proxmox-host>` | Address of the Proxmox node, the machine you open on port 8006 |
| `<docker-vm-ip>` | Address the VM gets from your router once it boots |
| `<user>` | Login you create during the Ubuntu install |

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

Memory. 4096 MiB is enough for these five services with room to spare.

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

The Compose file bind mounts one subdirectory per service beneath it. Docker creates them on first start, so nothing
else is needed here.

---

### Free port 53

AdGuard Home needs port 53, and Ubuntu already has `systemd-resolved` listening there. AdGuard will fail to start
until you move it out of the way. Do this before the first `docker compose up`.

Open the resolver configuration:

```bash
sudo nano /etc/systemd/resolved.conf
```

Find the `DNSStubListener` line, remove the leading hash, and set it to `no`:

```text
DNSStubListener=no
```

The VM still needs to resolve names for itself, and `/etc/resolv.conf` currently points at the stub listener you just
disabled. Replace it with a static file.

```bash
sudo rm /etc/resolv.conf
```

```bash
sudo nano /etc/resolv.conf
```

Put one line in it:

```text
nameserver 1.1.1.1
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

### Next

Go back to [README_HOMELAB.md](README_HOMELAB.md) for the quick start, then configure
[ADGUARD_DNS.md](ADGUARD_DNS.md) and [NGINX_PROXY_MANAGER.md](NGINX_PROXY_MANAGER.md).
