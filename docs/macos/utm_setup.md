### UTM Complete Setup Guide (macOS Host)

UTM is the macOS equivalent of Virt-Manager. It supports two backends:
- **Apple Virtualization** — native Apple Silicon hypervisor; fast, full integration, supports macOS and Linux ARM guests
- **QEMU** — full emulation; supports x86 and cross-architecture guests; uses SPICE protocol (same as Virt-Manager on Linux)

---

### Install UTM

Via Homebrew (recommended):
```bash
brew install --cask utm
```

Or download directly from the [UTM website](https://mac.getutm.app) or the Mac App Store.

---

### VM Creation

1. Open UTM and click the `+` button to create a new VM.
2. Choose backend:
   - **Virtualize** — Apple Virtualization framework; use for Linux or macOS ARM guests on Apple Silicon
   - **Emulate** — QEMU; use for x86 guests or when you need SPICE/full hardware emulation
3. Select the operating system type and load your ISO or IPSW image.
4. Allocate RAM and CPU cores (4096 MB and 4 CPUs recommended).
5. Configure a VirtIO disk image.
6. Review settings and save.

---

### Guest OS Setup

#### Linux Guests

**QEMU backend (x86 or ARM emulation):**

UTM exposes a SPICE display — install the SPICE agent inside the guest:

Arch Linux:
```bash
sudo pacman -S spice-vdagent
sudo systemctl enable --now spice-vdagentd
```

Ubuntu/Debian:
```bash
sudo apt install spice-vdagent
sudo systemctl enable --now spice-vdagentd
```

Fedora:
```bash
sudo dnf install spice-vdagent
sudo systemctl enable --now spice-vdagentd
```

**Apple Virtualization backend (ARM Linux guest on Apple Silicon):**

No guest agent is needed. Clipboard and directory sharing work natively via UTM's built-in integration. Install SPICE tools only if you switch to QEMU mode.

---

#### Windows Guests

**QEMU backend only** (Apple Virtualization does not support Windows guests):

Install SPICE Guest Tools inside the Windows guest:
https://www.spice-space.org/download/windows/spice-guest-tools/spice-guest-tools-latest.exe

Also install VirtIO drivers for best performance:
https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso

---

#### macOS Guests (Apple Silicon only)

macOS guests are only supported on Apple Silicon using the Apple Virtualization backend.

1. In UTM, choose Virtualize → macOS.
2. Download a macOS IPSW restore image when prompted (UTM links to the appropriate version).
3. Complete the standard macOS installation inside the VM.
4. No guest agent installation is needed — clipboard sharing and directory sharing work natively via UTM's integration layer.

---

### Clipboard Sharing

**QEMU backend (Linux or Windows guest):**

Uses the SPICE protocol — same approach as Virt-Manager on Linux.

Primary method: enable the `spice-vdagentd` systemd service (see Guest OS Setup above).

Fallback for KDE Plasma Wayland guests (if systemd service does not bridge clipboard):
```bash
killall -9 spice-vdagent
GDK_BACKEND=x11 spice-vdagent -x &
```
See `virt_manager_setup.md` for the full KDE Plasma Wayland workaround steps.

**Apple Virtualization backend (macOS or Linux ARM guest):**

Clipboard sharing is built into UTM — no configuration required. Toggle it in UTM VM settings under Sharing if it is not working.

---

### Filesystem Folder Share

#### QEMU Backend (Linux Guest) — VirtIO-FS

1. In UTM VM settings, go to Sharing and add a directory share.
2. Set the directory path on your macOS host (e.g. `~/Documents/VM-Share`).
3. Note the share tag (e.g. `share`).
4. Inside the Linux guest, create the mount point:

    ```bash
    mkdir -p ~/Documents/VM-Share
    ```

5. Mount using virtiofs:

    ```bash
    sudo mount -t virtiofs share ~/Documents/VM-Share
    ```

6. To make permanent, add to `/etc/fstab` inside the guest (replace `<username>`):

    ```text
    share /home/<username>/Documents/VM-Share virtiofs defaults 0 0
    ```

7. Apply:

    ```bash
    sudo systemctl daemon-reload
    sudo mount -a
    ```

#### Apple Virtualization Backend (macOS or Linux ARM Guest)

1. In UTM VM settings, go to Sharing and enable Directory Share.
2. Set the host directory path.
3. Inside the guest the share appears automatically. On macOS guests it mounts via Finder. On Linux guests:

    ```bash
    sudo mount -t virtiofs share /mnt/share
    ```

    Or configure a permanent fstab entry as above.
