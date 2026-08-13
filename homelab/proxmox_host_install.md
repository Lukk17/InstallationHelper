# Proxmox Host Install

> Installing Proxmox VE on the mini PC that hosts everything else, updating it, and getting a root shell on it. This is the first thing you do, before any virtual machine exists.

---

### Placeholders

Every page in this folder writes addresses as placeholders so the instructions stay reusable. Fill in your own.

| Placeholder | Meaning |
|---|---|
| `<router>` | Your router, which hands out addresses on the LAN |
| `<proxmox-host>` | The machine you are about to install, reached on port 8006 |
| `<ha-vm-ip>` | Address of the Home Assistant virtual machine |
| `<docker-vm-ip>` | Address of the Ubuntu virtual machine that runs the Compose stack |

Concrete example, the lab these documents were written from:

```text
<router>         192.168.1.1
<proxmox-host>   192.168.1.10
<ha-vm-ip>       192.168.1.11
<docker-vm-ip>   192.168.1.12
```

---

### What the hardware needs to be

Any small always-on machine with hardware virtualization support works. A used business mini PC is the usual choice, since it is quiet, sips power and has more than enough headroom for two virtual machines. Four cores and 16 GB of memory comfortably run everything described here.

Two things are worth checking before you commit to a machine.

Virtualization has to be enabled in the firmware. It is often off by default. Look for Intel VT-x or AMD-V, and enable IOMMU as well if you ever plan to pass a whole device through rather than a single USB dongle.

The disk is the part that fails. Everything here is rebuildable from backups, but a drive that dies at three in the morning still costs you an evening. Check its health after install, and put the machine on an uninterruptible power supply. Unclean shutdowns are what kill cheap solid state drives, and a hypervisor writes constantly.

---

### Install from a USB stick

Download the Proxmox VE ISO from the official download page: https://www.proxmox.com/en/downloads

Write it to a USB stick with any imaging tool, boot the machine from it, and work through the installer.

The one answer worth thinking about is the hostname, which the installer asks for as a fully qualified name. Something like `proxmox.lan` is a good choice, because it shows up as `proxmox` everywhere in the interface and the `.lan` suffix will not collide with the `.internal` names the reverse proxy serves later.

Give the machine a fixed address, either statically during the install or as a reservation on `<router>` keyed to its MAC address. Everything downstream refers to `<proxmox-host>`, and a hypervisor whose address moves is a hypervisor you cannot find.

When the installer finishes and reboots, you are done touching the machine physically. It has no desktop, and everything from here happens over the network. Unplug the monitor, keyboard and mouse.

---

### First login

Open the web interface from another machine on the network:

```text
https://<proxmox-host>:8006
```

It serves HTTPS with a self signed certificate, so the browser will warn you. That is expected on a private network with no public name to certify. Accept it and continue.

Log in as user `root` with realm `Linux PAM standard authentication`, using the password you set during the install.

A subscription warning appears on every login. Proxmox VE is free to use without one, and the warning only means you are on the no-subscription package channel rather than the enterprise one.

---

### Update the host

Open the node in the left tree, then Shell, which gives you a root prompt in the browser.

Refresh the package lists:

```bash
apt update
```

Then apply everything, including package upgrades that pull in new dependencies:

```bash
apt full-upgrade
```

On a fresh install `apt update` usually fails against the enterprise repository, because that one needs a subscription key. The post-install script below switches the machine to the no-subscription repository and the error goes away. If you would rather not run a third party script, you can make the same change by hand under Datacenter, then the node, then Updates, then Repositories.

---

### Post install helper script

The community maintains a script that applies the usual first-day settings: switching to the no-subscription repository, disabling the subscription nag, and offering a few optional tweaks.

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/post-pve-install.sh)"
```

It is interactive and asks yes or no for each change, so nothing happens that you did not agree to.

This is third party code running as root on your hypervisor. Read it before you run it, and get it from the project's own page rather than from a copied link, because the file has moved once already: https://community-scripts.github.io/ProxmoxVE/scripts?id=post-pve-install

Reboot afterwards if it asks you to.

---

### Get a shell over SSH

The browser shell works but has no usable clipboard. For anything involving long commands, connect over SSH instead.

Unix shell:

```bash
ssh root@<proxmox-host>
```

PowerShell:

```powershell
ssh root@<proxmox-host>
```

This is the prompt that the `qm` and `vzdump` commands on the other pages assume.

---

### Backup retention

Before you create anything worth losing, decide how many backups the host keeps.

Go to Datacenter, then Storage, then `local`, then Backup Retention.

Keeping every backup is the safe default while the lab is small, since the archives are compressed and a couple of virtual machines will not fill a modern disk quickly. Watch the free space on `local` as you go, and switch to a retention count once the archives start to add up.

Backups written here still live on the same disk as the machines they protect, which is not a backup at all until a copy leaves the box. Copying them off is covered in [backup_restore.md](backup_restore.md).

---

### Next

Two virtual machines go on top of this host.

[proxmox_docker_vm.md](proxmox_docker_vm.md) builds the Ubuntu machine that runs the Compose stack.

[home_assistant_vm.md](home_assistant_vm.md) builds the Home Assistant machine and passes the Zigbee dongle through to it.
