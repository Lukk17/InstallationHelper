### VirtualBox Complete Setup Guide (Windows Host)

VirtualBox is installed on Windows via Chocolatey as part of this project (`install_virtualbox: true` in `group_vars/windows.yaml`).

---

### VM Creation

1. Open VirtualBox and click New.
2. Enter a name, select the OS type and version.
3. Allocate RAM and CPU cores (4096 MB and 4 CPUs recommended).
4. Create a VDI virtual disk.
5. Before starting the VM, open Settings:
   - Display → Screen → Video Memory: 128 MB, enable 3D Acceleration
   - General → Advanced → Shared Clipboard: Bidirectional
   - General → Advanced → Drag and Drop: Bidirectional

---

### Guest OS Setup — Install Guest Additions

Guest Additions provide clipboard sharing, folder sharing, display scaling, and better mouse integration.

#### Linux Guests

**Arch Linux:**
```bash
sudo pacman -S virtualbox-guest-utils
sudo systemctl enable --now vboxservice
```

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install virtualbox-guest-utils virtualbox-guest-x11
```

**Fedora:**
```bash
sudo dnf install virtualbox-guest-additions
sudo systemctl enable --now vboxservice
```

> Alternatively, use the ISO method for any Linux distro: in VirtualBox menu go to Devices → Insert Guest Additions CD Image, then inside the guest run:
> ```bash
> sudo /media/cdrom/VBoxLinuxAdditions.run
> ```

#### Windows Guests

1. In the VirtualBox menu, click Devices → Insert Guest Additions CD Image.
2. Inside the Windows guest, open File Explorer and run `VBoxWindowsAdditions.exe` from the mounted CD.
3. Complete the installer and reboot the guest.

---

### Clipboard Sharing

Clipboard is enabled via the VirtualBox Settings → General → Advanced → Shared Clipboard: Bidirectional setting (set this before starting the VM).

**Linux guest — if clipboard is not working after reboot:**

Start the clipboard client manually:
```bash
VBoxClient --clipboard
```

To make it start automatically, add to `~/.bashrc` or your desktop autostart:
```bash
VBoxClient --clipboard &
```

With `vboxservice` enabled (Arch, Fedora), the clipboard client starts automatically. The manual command above is only needed on distros that install `virtualbox-guest-x11` without a systemd service.

---

### Filesystem Folder Share (vboxsf)

#### Host Setup (Windows)

1. In VirtualBox VM settings, go to Shared Folders and click Add.
2. Set:
   - Folder Path: `C:\Users\<username>\Documents\VM-Share` (create the folder first if it does not exist)
   - Folder Name: `VM-Share`
   - Auto-mount: checked
   - Make Permanent: checked
3. Click OK and start the VM.

#### Guest Setup (Linux)

1. Create the mount point inside the guest (replace `<username>` with your actual username):

    ```bash
    mkdir -p ~/Documents/VM-Share
    ```

2. Test the mount manually to confirm it works:

    ```bash
    sudo mount -t vboxsf VM-Share ~/Documents/VM-Share
    ```

3. To make the mount permanent, add this line to `/etc/fstab` inside the guest (replace `<username>` with your actual username):

    ```text
    VM-Share /home/<username>/Documents/VM-Share vboxsf defaults,uid=1000,gid=1000,dmode=0755,fmode=0755 0 0
    ```

4. Apply:

    ```bash
    sudo systemctl daemon-reload
    sudo mount -a
    ```

> The `uid` and `gid` values map the shared folder to your Linux user. Run `id` inside the guest to confirm your UID and GID if they differ from 1000.
