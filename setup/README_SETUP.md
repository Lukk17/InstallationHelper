# Setup (Unified Cross-Platform Ansible Migration)

This project has been fully migrated from monolithic bash/powershell scripts to a highly modular, data-driven, cross-platform Ansible setup. It supports **Ubuntu/Debian**, **Fedora**, **Archlinux**, **Windows**, and **macOS** out of the box.

---

## 🏗 Architecture Overview

The architecture relies on a **Single Source of Truth** via Data-Driven Ansible.
The logic is driven by a master configuration file where you toggle specific installations and configurations on or off, and OS Dictionaries handle the underlying translation.

```mermaid
graph TD
    A[Playbook: site.yaml] --> B{Enforce Profile}
    B -->|Success| C[Load OS Dictionary]
    C --> D[OS-Specific Core Setup]
    C --> E[Universal Complex Roles]
    C --> F[Core Software Router]

    D --> D1(Windows Features, WSL)
    D --> D2(macOS Defaults, Brew)
    D --> D3(Linux GRUB, Snap/Flatpak Plugins)

    E --> E1(AI Tools: Claude, OpenCode)
    E --> E2(SDK Manager: Pyenv, NVM, SDKMAN)
    
    F --> F1(Apt / DNF / Pacman)
    F --> F2(Homebrew / Cask)
    F --> F3(Chocolatey / Winget)
    F --> F4(Snap / Flatpak)
```

---

## 📂 Directory Structure & File Roles

```mermaid
graph LR
    Root[setup/] --> Playbook[ansible/site.yaml]
    Root --> GroupVars[ansible/group_vars/]
    Root --> Vars[ansible/vars/]
    Root --> Profiles[ansible/profiles/]
    Root --> Roles[ansible/roles/]
    
    GroupVars --> GV1[all.yaml - Global Intent]
    GroupVars --> GV2[linux.yaml - OS Toggles]
    GroupVars --> GV3[windows.yaml - OS Toggles]
    GroupVars --> GV4[macos.yaml - OS Toggles]
    
    Vars --> V1[Debian.yaml - Dictionary]
    Vars --> V2[Windows.yaml - Dictionary]
    Vars --> V3[Darwin.yaml - Dictionary]
    
    Profiles --> P1[linux_live.yaml - Overrides]
    
    Roles --> R1[software_installer - The Router]
    Roles --> R2[kde_plasma_setup - DE Config]
    Roles --> R3[sdk_manager - Complex Installs]
```

* **`ansible/site.yaml` (The Playbook):** This is the main entry point for Ansible. It tells Ansible which hosts to target (localhost) and maps the roles to execute conditionally based on the master toggles.
* **`ansible/group_vars/all.yaml` (Global Intent):** This file acts as your central configuration hub for cross-platform apps. You define boolean variables here (e.g., `install_chrome: true`) which dictate what gets installed.
* **`ansible/group_vars/{linux,windows,macos}.yaml` (OS Toggles):** Booleans for apps/settings that only exist on that specific OS (e.g., `setup_wsl: true` for Windows, `install_kde_plasma: true` for Linux).
* **`ansible/vars/{Debian,RedHat,Archlinux,Windows,Darwin}.yaml` (Translation Dictionaries):** Maps the generic app name to the exact package name, the preferred package manager for that specific OS, and metadata explaining if it's an alternative.
* **`ansible/profiles/`:** This directory contains specific overriding setups (e.g., `linux_live.yaml`) which can inherit everything from the `group_vars/` but selectively toggle flags without modifying the master files.
* **`ansible/roles/`:** This directory contains all the modularized setup logic.

---

## 📦 Package Manager Priorities

We strictly follow this explicit hierarchy per OS defined in the `vars/` dictionaries:

* **Windows:** Official/Vendor Installer > Chocolatey > Winget (UWP/Store apps).
* **macOS:** Official DMG/PKG > Homebrew (Cask for GUI, Formula for CLI) > Mac App Store (`mas`). *(GUI apps default to Casks).*
* **Linux (Ubuntu/Debian):** Official APT Repo > Flatpak > Snap > Default APT.
* **Linux (Fedora):** Official DNF Repo > Flatpak > Snap > Default DNF.
* **Linux (Arch/Manjaro):** Official Pacman > AUR Helper (`yay`) > Flatpak > Snap.

---

## 🚀 Usage Instructions

### 1. Install Ansible (If not already installed)

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install software-properties-common -y
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install ansible -y
```

**Fedora:**
```bash
sudo dnf install ansible
```

**Archlinux:**
```bash
sudo pacman -S ansible
```

**macOS:**
```bash
brew install ansible
```

**Windows:**
You must run Ansible from within WSL (Windows Subsystem for Linux).
1. Install WSL via PowerShell: `wsl --install`
2. Open Ubuntu in WSL and install Ansible via the Ubuntu/Debian instructions above.
3. Configure WinRM on Windows to allow Ansible to connect from WSL.

### 2. Configure Your Setup
Review `setup/ansible/group_vars/all.yaml` (and the OS-specific files) and set the flags for the tools and settings you wish to apply to your machine. 
If you have a specific setup profile, you can override the variables by pointing to it during execution.

### 3. Run the Playbook
Run the playbook against your local machine. **You MUST provide a profile** (or empty profile file) via the `-e` flag, or the playbook will safely abort. The `-K` flag ensures Ansible can prompt for the sudo password used for administrative tasks.

```bash
cd setup/ansible
ansible-playbook site.yaml -i localhost, -c local -e "@profiles/default.yaml" -K
```

**Using an override profile (e.g., Linux Live USB setup):**
```bash
ansible-playbook site.yaml -i localhost, -c local -e "@profiles/linux_live.yaml" -K
```

---

## 🖥 Desktop Environments (Linux)

You have granular control over installing vs configuring desktop environments.

In `ansible/group_vars/linux.yaml`, set:
* `install_kde_plasma: true` to physically install KDE via your package manager.
* `configure_kde_plasma: true` to apply themes, widgets, and shortcuts (useful if KDE is already installed, like on Fedora KDE Spin).

### Konsave Profile Management (KDE)
To save your current KDE Plasma configuration:
```bash
konsave -s lukk_desktop_profile
```

To export the saved profile to a file (`lukk_desktop_profile.knsv`):
```bash
konsave -e lukk_desktop_profile
```
**Important:** If you are re-exporting to an existing file, you must use the force (`-f`) flag, or it will not be overwritten:
```bash
konsave -e lukk_desktop_profile -f
```

To import and apply a profile from a file:
```bash
konsave -i config/lukk_desktop_profile.knsv
konsave -a lukk_desktop_profile
```

---

## 🛠 Complex Roles

Certain software installations cannot be abstracted by package managers and have dedicated roles:
* **`ai_tools`**: Installs NPM/Go binaries (Claude Code, OpenCode, Cowork Service).
* **`sdk_manager`**: Installs Pyenv, NVM, SDKMAN, FVM.
* **`linux_crypto_hardware`**: Installs udev rules for Trezor/Ledger.
* **`waydroid`**: Configures kernel parameters and custom GDM files for Wayland container execution.
