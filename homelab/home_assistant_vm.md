# Home Assistant OS VM

> Building the Home Assistant virtual machine on Proxmox from the official image using the `qm` command line, and passing a Zigbee USB dongle through to it.

---

### Placeholders

| Placeholder | Meaning |
|---|---|
| `<proxmox-host>` | The Proxmox node |
| `<vmid>` | The number you give this virtual machine, for example 103 |
| `<ha-vm-ip>` | Address the machine picks up once it boots |
| `<mac-address>` | Hardware address, only needed if you are replacing an existing machine |

Everything below runs in the node shell as root, either through Datacenter, then the node, then Shell, or over SSH as described in [proxmox_host_install.md](proxmox_host_install.md).

---

### Why do it by hand

There is a community script that does all of this behind a menu, and it is listed at the bottom of this page. The manual route is written out here because a Home Assistant machine tends to get rebuilt at the worst possible moment, and knowing which flag does what means you can adapt it instead of hoping the script still works.

Home Assistant OS is an appliance operating system. You do not install packages on it or get a normal shell. Add-ons, backups and updates are all managed from inside Home Assistant itself, which is why the backup story for it is different from every other machine here and lives in [home_assistant_backup.md](home_assistant_backup.md).

---

### Download the image

Get the generic virtual machine image, which is the one named `haos_ova`. Do not use the `.ova` file or any board specific image.

Move into the template directory on the node:

```bash
cd /var/lib/vz/template
```

Ask the project which file is current, rather than hardcoding a version that will be stale next month:

```bash
URL=$(curl -s https://api.github.com/repos/home-assistant/operating-system/releases/latest | grep -o 'https://[^"]*haos_ova-[^"]*\.qcow2\.xz' | head -1)
```

Check what it found:

```bash
echo "$URL"
```

At the time of writing that prints the 18.2 image. Download it:

```bash
wget -q "$URL" -O haos.qcow2.xz
```

Decompress it, which leaves `haos.qcow2` behind:

```bash
unxz haos.qcow2.xz
```

---

### Create the virtual machine

```bash
qm create <vmid> --name haos --machine q35 --bios ovmf --cores 2 --memory 4096 --net0 virtio,bridge=vmbr0,firewall=0 --ostype l26 --scsihw virtio-scsi-single --agent enabled=1 --onboot 1
```

| Flag | Why |
|---|---|
| `--machine q35 --bios ovmf` | Home Assistant OS boots UEFI only, so the older SeaBIOS default will not work |
| `--cores 2 --memory 4096` | Enough for Home Assistant with Zigbee2MQTT and a broker alongside it |
| `--net0 virtio,bridge=vmbr0` | The paravirtual network card, which is the fast one, on the default bridge |
| `--ostype l26` | Tells Proxmox this is a modern Linux guest |
| `--scsihw virtio-scsi-single` | Gives the disk its own controller, which lowers latency |
| `--agent enabled=1` | Lets Proxmox read the guest address and shut it down cleanly |
| `--onboot 1` | Starts the machine when the host boots, which is what you want for a house that depends on it |

If you are rebuilding an existing Home Assistant machine, add its old hardware address so the router hands the new machine the same lease and you do not have to reconfigure anything that points at it:

```bash
qm set <vmid> --net0 virtio=<mac-address>,bridge=vmbr0,firewall=0
```

Give the new machine a new `<vmid>` and leave the old one shut down. Same hardware address on two machines is only safe while exactly one of them is running.

---

### Add the EFI disk and import the operating system disk

UEFI firmware needs somewhere to keep its variables, so that disk comes first:

```bash
qm set <vmid> --efidisk0 local-lvm:0,efitype=4m,pre-enrolled-keys=0
```

Then import the image you downloaded:

```bash
qm importdisk <vmid> /var/lib/vz/template/haos.qcow2 local-lvm
```

It reports the name it created, which will be `vm-<vmid>-disk-1`. The EFI disk took `disk-0`, so the imported operating system disk is always the next number up.

Attach it as the boot disk:

```bash
qm set <vmid> --scsi0 local-lvm:vm-<vmid>-disk-1,discard=on,ssd=1
```

`discard=on` passes TRIM through to the physical drive so freed space is actually reclaimed, and `ssd=1` tells the guest it is on a solid state disk.

Tell the firmware to boot from it:

```bash
qm set <vmid> --boot order=scsi0
```

Grow it, since the shipped image is small and Home Assistant expands its data partition on first boot:

```bash
qm resize <vmid> scsi0 100G
```

Start it:

```bash
qm start <vmid>
```

First boot takes several minutes, because Home Assistant pulls its core container before it can serve anything. Once it settles, onboarding is at `http://<ha-vm-ip>:8123`.

---

### Pass the Zigbee dongle through

Find the device on the host:

```bash
lsusb
```

A Home Assistant SkyConnect or ZBT-1 shows up as a Silicon Labs CP210x serial bridge with the identifier `10c4:ea60`. Note the pair of numbers, which are the vendor and product identifiers.

Attach it by those identifiers rather than by physical port:

```bash
qm set <vmid> --usb0 host=10c4:ea60
```

Port based attachment breaks the moment you move the plug to a different socket, and you will move it eventually.

Reboot so the device attaches cleanly:

```bash
qm reboot <vmid>
```

Check that the guest can see it:

```bash
qm guest exec <vmid> -- /bin/sh -c 'ls -l /dev/serial/by-id/'
```

That should list a device whose name includes the dongle model, pointing at `ttyUSB0`.

A USB device can only belong to one running machine at a time. If you are migrating from an old Home Assistant machine, shut that one down first or the attach silently fails.

The same thing is available in the interface under the machine, then Hardware, then Add, then USB Device. Choose Use USB Vendor/Device ID, not the port based option, for the reason above.

To see what an older machine was forwarding so you can reproduce it:

```bash
qm config <old-vmid> | grep -iE 'usb|hostpci'
```

---

### How Zigbee actually reaches Home Assistant

Four pieces sit in a line, and knowing the order saves a lot of confusion when something stops working.

```text
USB dongle -> Zigbee2MQTT add-on -> Mosquitto broker -> MQTT integration -> devices in Home Assistant
```

Zigbee2MQTT is an add-on, not an integration. Look for it under Settings, then Add-ons. People lose an hour searching Devices and Services for it.

Mosquitto is the message broker in the middle. Zigbee2MQTT publishes to it, and Home Assistant subscribes.

The MQTT integration is the part that turns those messages into entities you can actually use.

In Zigbee2MQTT, point the serial port at the `/dev/serial/by-id/` path you listed above rather than at `/dev/ttyUSB0`. The by-id name is stable across reboots, the `ttyUSB` number is not.

Zigbee2MQTT keeps its network key and device list under `/config/zigbee2mqtt`. That directory is the reason a partial backup is not good enough, covered in [home_assistant_backup.md](home_assistant_backup.md).

---

### The faster path

The same community project behind the post install script has one for this machine, which walks steps one through three behind a menu.

As with the post install script, this is third party code running as root on your hypervisor. Read it before you run it, and take the current link from the project's own page rather than trusting a copied one: https://community-scripts.github.io/ProxmoxVE/scripts?id=haos-vm

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/vm/haos-vm.sh)"
```

It will not do the USB passthrough for you, so that section still applies.

---

### Next

Set up backups before you spend an evening configuring automations: [home_assistant_backup.md](home_assistant_backup.md).
