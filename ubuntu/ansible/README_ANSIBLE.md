# Ubuntu Setup (Ansible Migration)

This project has been fully migrated from monolithic bash scripts to a highly modular, idempotent Ansible setup.

## How It Works

The architecture relies on Ansible roles to separate concerns (e.g., `gnome_setup`, `dev_tools`, `virtualization`). 
The logic is driven by a master configuration file where you can toggle specific installations and configurations on or off.

### Directory Structure & File Roles

* **`site.yaml` (The Playbook):** This is the main entry point for Ansible. It tells Ansible which hosts to target (localhost) and maps the roles to execute conditionally based on the master toggles.
* **`group_vars/all.yaml` (Master Toggles):** This file acts as your central configuration hub. You define boolean variables here (e.g., `install_wine: true`, `setup_hibernate: false`) which dictate exactly what gets installed or configured during a run.
* **`roles/`:** This directory contains all the modularized setup logic.
  * **`tasks/main.yaml`:** Serves as an index that imports smaller, focused task files (e.g., `docker.yaml`, `kubernetes_tools.yaml`) using `import_tasks` to keep individual files readable.
  * **`defaults/main.yaml`:** Centralized, hardcoded variables specific to a role (e.g., download URLs, version numbers for specific apps).

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

## Usage Instructions

### 1. Install Ansible (If not already installed)
```bash
sudo apt update
sudo apt install software-properties-common -y
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install ansible -y
```

### 2. Configure Your Setup
Review `ansible/group_vars/all.yaml` and set the flags for the tools and settings you wish to apply to your machine. 

### 3. Run the Playbook
Run the playbook against your local machine. The `-K` flag ensures Ansible can prompt for the sudo password used for administrative tasks.

```bash
cd ansible
ansible-playbook -i localhost, -c local site.yaml -K
```