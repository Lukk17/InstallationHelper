### Virt-Manager Complete Setup Guide

---

### VM Configuration

1. Open `Virt-Manager` on your Linux host.
2. Click the icon to create a new virtual machine.
3. Choose Local install media and select your downloaded ISO file.
4. Allocate RAM and CPU cores. Give it at least 4096 MB of RAM and 4 CPUs if your host can handle it.
5. Create a disk image for the virtual machine.
6. Check the box that says Customize configuration before install and click Finish.
7. In the hardware details window, make sure you have the following components:
   * Display Spice
   * Video `Virtio`
   * Channel spice (`com.redhat.spice.0`)
   * Controller `VirtIO Serial`

---

### Installation Generic

1. Click Play to start the virtual machine.
2. Follow the standard installation steps for whatever operating system you chose.
3. Once the installation is done, reboot the virtual machine.
4. Install the guest agent inside the virtual machine (see per-OS instructions below).

#### Linux Guests — Install SPICE Agent

Arch Linux:
```bash
sudo pacman -S spice-vdagent
```

Ubuntu/Debian:
```bash
sudo apt install spice-vdagent
```

Fedora:
```bash
sudo dnf install spice-vdagent
```

#### Windows Guests — Install SPICE Guest Tools

Download and install the Windows SPICE Guest Tools executable:
https://www.spice-space.org/download/windows/spice-guest-tools/spice-guest-tools-latest.exe

#### macOS Guests — KVM (Advanced)

> **Warning:** Running macOS inside KVM on a Linux host is highly complex, legally restricted to Apple hardware per Apple's EULA, and outside standard Virt-Manager scope. It requires the OpenCore bootloader and specific QEMU CPU flags. SPICE clipboard is not available.
>
> Use the [OSX-KVM project](https://github.com/kholia/OSX-KVM) for a complete setup guide. Key requirements:
> - OVMF firmware with Secure Boot disabled
> - OpenCore as the boot EFI image
> - QEMU CPU set to `host-passthrough` with CPUID masking for Apple model detection
> - Clipboard sharing is not supported; use VNC mode as a workaround

---

### Clipboard Sharing

#### Primary — Systemd Service (recommended, works for most guests)

Enable the SPICE agent daemon inside the guest after installing `spice-vdagent`:

```bash
sudo systemctl enable --now spice-vdagentd
```

Clipboard will work automatically between guest and host after the service starts.

---

#### Fallback — X11 Workaround (KDE Plasma Wayland guests only)

Use this only when the systemd service does not bridge clipboard under KDE Plasma running on Wayland. The service alone cannot reach the Wayland clipboard — it must be forced through the X11/Plasma bridge.

1. Stay on the Wayland session. Do not switch to X11.
2. Inside the guest, open System Settings.
3. Navigate to Security & Privacy → Application Permissions → Legacy X11 App Support.
4. Find the clipboard access setting and change it to allow access without asking.
5. Click Apply.
6. Kill any stuck processes from previous attempts:

    ```bash
    killall -9 spice-vdagent
    ```

7. Force the agent to run on the X11 backend so it reads from the Plasma clipboard bridge:

    ```bash
    GDK_BACKEND=x11 spice-vdagent -x &
    ```

8. Copying from the guest to the host will now work.

---

### Filesystem Folder Share (VirtIO-FS)

#### Host Setup

1. Install the VirtIO-FS daemon on your Linux host:

    Debian/Ubuntu:
    ```bash
    sudo apt update && sudo apt install virtiofsd
    ```

    Arch Linux:
    ```bash
    sudo pacman -S virtiofsd
    ```

    Fedora:
    ```bash
    sudo dnf install virtiofsd
    ```

2. Create the shared folder on your Linux host:

    ```bash
    mkdir -p ~/Documents/VM-Share
    ```

3. Open permissions so the hypervisor can read the directory:

    ```bash
    chmod +x ~
    chmod +x ~/Documents
    chmod 777 ~/Documents/VM-Share
    ```

4. Shut down the virtual machine completely.
5. In `Virt-Manager`, open the virtual machine details and go to Memory.
6. Check the box for Enable shared memory and apply.
7. Click Add Hardware and select Filesystem.
8. Set Driver to `virtiofs`.
9. Set Source path to `~/Documents/VM-Share` (use the full path, e.g. `/home/<username>/Documents/VM-Share`).
10. Set Target path to `VM-Share`.
11. Click Finish and boot the virtual machine.

#### Guest Setup

1. Create the matching mount point inside the virtual machine:

    ```bash
    mkdir -p ~/Documents/VM-Share
    ```

2. Mount the folder using the target tag:

    ```bash
    sudo mount -t virtiofs VM-Share ~/Documents/VM-Share
    ```

3. To make the mount permanent, add this line to `/etc/fstab` inside the virtual machine (replace `<username>` with your actual username):

    ```text
    VM-Share /home/<username>/Documents/VM-Share virtiofs defaults 0 0
    ```

4. Apply the fstab change:

    ```bash
    sudo systemctl daemon-reload
    sudo mount -a
    ```
