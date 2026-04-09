### Virt-Manager Complete Setup Guide

---

### VM Configuration

1. Open `Virt-Manager` on your Ubuntu host.
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
4. Make sure the guest agent is installed inside the virtual machine.

For Arch Linux:
sudo pacman -S spice-vdagent

For Ubuntu/Debian:
sudo apt install spice-vdagent

For Fedora:
sudo dnf install spice-vdagent

For Windows:
Download and install the Windows SPICE Guest Tools executable: 
https://www.spice-space.org/download/windows/spice-guest-tools/spice-guest-tools-latest.exe

---

### Clipboard Share Wayland Fix

1. Do not use X11 session. Stay on Wayland.
2. Inside your Arch virtual machine, open System Settings.
3. Navigate to Security & Privacy.
4. Select Application Permissions.
5. Select Legacy X11 App Support.
6. Find the setting for clipboard access and change it to allow access without asking.
7. Click Apply.
8. Open your Arch terminal and kill any stuck processes from previous attempts:

    ```bash
    killall -9 spice-vdagent
    ```

9. Force the spice agent to run strictly on the X11 backend so it reads from the Plasma bridge:
    
    ```bash
    GDK_BACKEND=x11 spice-vdagent -x &
    ```

10. Copying from the guest to the host will now work natively.

---

### Filesystem Folder Share Virtio-FS

1. Install the missing background daemon on your Ubuntu Host so it can process the bridge:
    
    ```bash
    sudo apt update
    sudo apt install virtiofsd
    ```

2. Create the exact shared folder on your Ubuntu Host:
    
    ```bash
    mkdir -p /home/lukk/Documents/VM_Share
    ```

3. Open the permissions on your Ubuntu Host so the hypervisor can actually read your home directory:
    
    ```bash
    chmod +x /home/lukk
    chmod +x /home/lukk/Documents
    chmod 777 /home/lukk/Documents/VM_Share
    ```

4. Shut down the virtual machine completely.
5. In `Virt-Manager`, open the virtual machine details and go to Memory.
6. Check the box for Enable shared memory and apply.
7. Click Add Hardware and select Filesystem.
8. Set Driver to `virtiofs`.
9. Set `Source path` to `/home/lukk/Documents/VM_Share`.
10. Set `Target path` to `VM_Share`.
11. Click Finish and boot the virtual machine.
12. Inside the virtual machine, create the exact matching folder to mount the share:
    
    ```bash
    mkdir -p /home/lukk/Documents/VM_Share
    ```

13. Mount the folder using the target tag you created:
    
    ```bash
    sudo mount -t virtiofs VM_Share /home/lukk/Documents/VM_Share
    ```

14. To make the mount permanent, add this line to your /etc/fstab file inside the virtual machine:

```text
VM_Share /home/lukk/Documents/VM_Share virtiofs defaults 0 0
```