### Ubuntu Setup (Ansible Migration)

This project has been fully migrated from monolithic bash scripts to a highly modular, idempotent Ansible setup.

---

### How It Works

The architecture relies on Ansible roles to separate concerns (e.g., `gnome_setup`, `dev_tools`, `virtualization`). 
The logic is driven by a master configuration file where you can toggle specific installations and configurations on or off.

---

### Directory Structure & File Roles

* **`site.yaml` (The Playbook):** This is the main entry point for Ansible. It tells Ansible which hosts to target (localhost) and maps the roles to execute conditionally based on the master toggles.
* **`group_vars/all.yaml` (Master Toggles):** This file acts as your central configuration hub. You define boolean variables here (e.g., `install_wine: true`, `setup_hibernate: false`) which dictate exactly what gets installed or configured during a run.
* **`profiles/`:** This directory contains specific overriding setups (e.g., `linux_live.yaml`) which can inherit everything from `all.yaml` but selectively toggle flags without modifying the master file.
* **`roles/`:** This directory contains all the modularized setup logic.
  * **`tasks/main.yaml`:** Serves as an index that imports smaller, focused task files (e.g., `docker.yaml`, `kubernetes_tools.yaml`) using `import_tasks` to keep individual files readable.
  * **`defaults/main.yaml`:** Centralized, hardcoded variables specific to a role (e.g., download URLs, version numbers for specific apps).

---

### Understanding Ansible Concepts Used

1. **Idempotency:** Re-running the playbook will only make changes if the system state does not match the desired state.
2. **`become: yes` / `become: no` (Privilege Escalation):** 
   * `become: yes` executes tasks with `sudo`. Used for system-level actions (e.g., package installations via `apt`, modifying `/etc/fstab`).
   * `become: no` ensures user-level tasks (e.g., configuring GNOME settings, Oh-My-Zsh) execute safely as the local user.
3. **`loop`:** Iterates over a list, allowing us to keep the code DRY. Used for installing multiple apt/snap packages or configuring lists of default apps without rewriting the same task over and over.
4. **`get_url`:** Downloads files natively. Better than `wget`/`curl` because it checks if the file exists and can verify checksums, saving bandwidth and enforcing idempotency.
5. **`changed_when: false`:** Tells Ansible that running a specific command shouldn't be marked as a "Change" in the final summary unless it strictly applies. Used for read-only commands (like updating the apt cache) or commands that don't inherently report their state (like `xdg-mime`).
6. **`creates:` (Command Argument):** Used alongside `shell` or `command`. It tells Ansible to skip executing the script/command if the specified file or directory already exists, inherently bringing idempotency to basic bash commands.
7. **`community.general.dconf`:** A native module used to interact with GNOME `dconf` / `gsettings`. It natively checks the current state of a GNOME setting and only alters it if it differs from the desired value.
8. **`lineinfile` & `replace`:** Native modules for editing files instead of using `sed`, `echo >>`, or `awk`. They verify if a line exists and safely append or modify the exact target line, ensuring it isn’t duplicated on subsequent runs.
9. **`apt` / `snap` / `flatpak` Modules:** Abstract away the package managers. They natively check if a package is already installed (or at the desired state) and only invoke the system's package manager when necessary.
10. **`handlers`:** Special tasks triggered only if a preceding task reports a change. Perfect for running `update-grub`, `fc-cache`, or restarting a service like `gdm3` only when configurations actually change.
11. **`import_tasks`:** Used within `main.yaml` of each role to break down massive lists of tasks into specialized files (e.g., separating `java_sdkman.yaml` from `flatpaks.yaml`), making the roles incredibly easy to read and maintain.

---

### Usage Instructions

#### 1. Install Ansible (If not already installed)
```bash
sudo apt update
sudo apt install software-properties-common -y
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install ansible -y
```

#### 2. Configure Your Setup
Review `ansible/group_vars/all.yaml` and set the flags for the tools and settings you wish to apply to your machine. 
If you have a specific setup profile, you can override the variables by pointing to it during execution.

#### 3. Run the Playbook
Run the playbook against your local machine using the default variables (`group_vars/all.yaml`). The `-K` flag ensures Ansible can prompt for the sudo password used for administrative tasks.

```bash
cd ansible
ansible-playbook site.yaml -i localhost, -c local -K
```

**Using an override profile (e.g., Linux Live USB setup):**
```bash
ansible-playbook site.yaml -i localhost, -c local -e "@profiles/linux_live.yaml" -K
```

---

### After Install

#### Google account login
Log into Google account in gnome settings "Online Account"

#### Mounting shared disk at startup

1. Open the "Disks" application. (You can find it by searching in your activities). 
2. Select the drive you want to mount from the list on the left. 
3. In the "Volumes" section, click on the partition you want to mount. 
4. Click the gear icon below the volumes and select "Edit Mount Options...". 
5. A new window will open. Toggle off "User Session Defaults" at the top. 
6. Ensure that "Mount at system startup" is checked.
7. (Optional but recommended) In the "Display Name" field, you can give the drive a memorable name. 
8. Click OK and enter your password.

#### Setting the same screen settings for the system login page

```shell
sudo cp ~/.config/monitors.xml /var/lib/gdm3/.config/
```

#### Sharing the same project with Windows
If git detects dubious ownership, fix it with: 
```shell
git config --global --add safe.directory '*'
```

---

### Hibernation Troubleshooting

Sometimes hibernation can fail due to `INFO: task setfont:9848 blocked for more than 245 seconds.`
To fix that, run commands to disable the problematic services _only_ for suspend and hibernate, without affecting the normal operation of your system.
```bash
sudo systemctl mask systemd-vconsole-setup.service
sudo systemctl mask console-setup.service
```
Now reboot the system.

---

### Waydroid Setup & Troubleshooting

#### Check if Wayland is running
Ubuntu needs to run on Wayland for Waydroid to work. To check it:
```shell
echo $XDG_SESSION_TYPE
```
It should return the output `wayland`.

#### If returned value is `x11`:
The Ansible playbook in this project already handles this configuration for you by setting `WaylandEnable=true` in `/etc/gdm3/custom.conf` and adding the required NVIDIA kernel parameters. However, if you need to do it manually:
```shell
sudo sed -i 's/#WaylandEnable=false/WaylandEnable=true/g' /etc/gdm3/custom.conf
```
Next you need to create file: `/etc/modprobe.d/nvidia-power-management.conf` with the line:
`options nvidia NVreg_PreserveVideoMemoryAllocations=1`
Simple command for it:
```shell
sudo bash -c "echo 'options nvidia NVreg_PreserveVideoMemoryAllocations=1' >> /etc/modprobe.d/nvidia-power-management.conf"
```
And restart the desktop environment:
```shell
sudo systemctl restart gdm3
```
Now log off (not just lock) and on the login screen, when typing your password, click on the gear icon and change to the Wayland session.

#### Waydroid first launch
To launch, search for it in Ubuntu applications (super key) and start from there. Sometimes it can take a few minutes for the first window to appear. When it starts, there will be an initialization - do NOT select GAPPS (it will install official Google services which won't work because this device is not authorized).

If after a few minutes nothing happens:
```shell
sudo waydroid init
sudo systemctl start waydroid-container
sudo waydroid container start
waydroid session start
waydroid show-full-ui
waydroid app list
```

#### Waydroid multi-window mode
To launch every app in a different window:
```shell
waydroid prop set persist.waydroid.multi_windows true
sudo systemctl restart waydroid-container
```

#### Waydroid full restart/reset:
```shell
sudo systemctl stop waydroid-container.service
sudo rm -rf /var/lib/waydroid /home/.waydroid ~/waydroid ~/.share/waydroid ~/.local/share/applications/*aydroid* ~/.local/share/waydroid
sudo waydroid init -f
systemctl start waydroid-container.service
```

---

### Desktop Shortcut Locations
- **Snap Apps:** `/var/lib/snapd/desktop/applications`
- **System Apps:** `/usr/share/applications`

---

### Java SDK Versions
To use a given version in the current terminal:
```shell
sdk use java 17.0.10-tem
```

To set the global default:
```shell
sdk default java 21.0.2-tem
```
