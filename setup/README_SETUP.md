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

* **`ansible/site.yaml` (The Playbook):** This is the main entry point for Ansible.
* **`ansible/group_vars/all.yaml` (Global Intent):** This file acts as your central configuration hub for cross-platform apps.
* **`ansible/group_vars/{linux,windows,macos}.yaml` (OS Toggles):** Booleans for apps/settings that only exist on that specific OS.
* **`ansible/vars/{Debian,RedHat,Archlinux,Windows,Darwin}.yaml` (Translation Dictionaries):** Maps the generic app name to the exact package name for each OS.
* **`ansible/profiles/`:** This directory contains specific override profiles (e.g., `linux_live.yaml`) which selectively toggle flags for non-standard setups. For a full default installation, no profile is needed.

---

## 📦 Package Manager Priorities

We strictly follow this explicit hierarchy per OS defined in the `vars/` dictionaries:

* **Windows:** Official/Vendor Installer > Chocolatey > Winget (UWP/Store apps).
* **macOS:** Official DMG/PKG > Homebrew (Cask for GUI, Formula for CLI) > Mac App Store (`mas`). *(GUI apps default to Casks).*
* **Linux (Ubuntu/Debian):** Official APT Repo > Flatpak > Snap > Default APT.
* **Linux (Fedora):** Official DNF Repo > Flatpak > Snap > Default DNF.
* **Linux (Arch/Manjaro):** Official Pacman > AUR Helper (`yay`) > Flatpak > Snap.

---

## 🚀 Universal Ansible Commands

### 1. Install Ansible
First, ensure Ansible is installed on your system.

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install software-properties-common -y
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install ansible -y
```

**Fedora:**
```bash
sudo dnf install ansible -y
```

**Archlinux:**
```bash
sudo pacman -S ansible --noconfirm
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

### 2. Install Required Ansible Collections
```bash
cd setup/ansible
ansible-galaxy collection install -r requirements.yaml
```

### 3. Configure Your Setup
Review `setup/ansible/group_vars/all.yaml` (and the OS-specific files) and set the flags for the tools and settings you wish to apply to your machine. 
If you have a specific setup profile, you can override the variables by pointing to it during execution.

### 4. Run the Playbook
Run the playbook against your local machine. The `-K` flag ensures Ansible can prompt for the sudo password used for administrative tasks.

First, navigate to the ansible directory:
```bash
cd setup/ansible
```

Then, run the command for the profile you wish to use. The `-K` flag will prompt for your `sudo` password.

### **Commands Per OS and Profile**

#### **Ubuntu / Debian**

*   **Full Installation (Default):**
    ```sh
    ansible-playbook site.yaml -i localhost, -c local -K
    ```
*   **Linux Live Profile (For USB Drives):**
    ```sh
    ansible-playbook site.yaml -i localhost, -c local -e "@profiles/linux_live.yaml" -K
    ```

#### **Fedora**

*   **Full Installation (Default):**
    ```sh
    ansible-playbook site.yaml -i localhost, -c local -K
    ```
*   **Linux Live Profile (For USB Drives):**
    ```sh
    ansible-playbook site.yaml -i localhost, -c local -e "@profiles/linux_live.yaml" -K
    ```

#### **Arch Linux**

*   **Full Installation (Default):**
    ```sh
    ansible-playbook site.yaml -i localhost, -c local -K
    ```
*   **Linux Live Profile (For USB Drives):**
    ```sh
    ansible-playbook site.yaml -i localhost, -c local -e "@profiles/linux_live.yaml" -K
    ```

#### **macOS**

*   **Full Installation (Default):**
    ```sh
    ansible-playbook site.yaml -i localhost, -c local -K
    ```
    *(Note: The `linux_live` profile is not applicable to macOS).*

#### **Windows (via WSL)**

*   **Full Installation (Default):**
    ```sh
    ansible-playbook site.yaml -i localhost, -c local -K
    ```
    *(Note: The `linux_live` profile is not applicable to Windows).*

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
* **`ai_tools`**: Installs NPM/Go binaries (Claude Code, OpenCode, OpenSpec, Cowork Service) and Claude Desktop per-platform.
* **`sdk_manager`**: Installs Pyenv, NVM, SDKMAN, FVM, Android SDK, Dart.
* **`linux_crypto_hardware`**: Installs udev rules for Trezor/Ledger.
* **`waydroid`**: Configures kernel parameters and custom GDM files for Wayland container execution.
* **`system_core`**: Full system upgrade, tmpfs, GRUB timeout, RTC fix, and locale setup (all distros).
* **`virtualization_config`**: Installs QEMU/KVM + virt-manager + virtiofsd; auto-installs `spice-vdagent` when running inside a VM guest.

---

## 📋 Non-Standard Installation Methods

Software below is **not** installed via the default package manager for that OS — each uses a custom method due to packaging limitations or lack of official distro support.

### AI Tools (`roles/ai_tools`)

| Software | Ubuntu/Debian | Arch Linux | Fedora | macOS | Windows |
|---|---|---|---|---|---|
| **Claude Code CLI** | `npm install -g @anthropic-ai/claude-code` (official) | ← same | ← same | ← same | ← same |
| **Claude Desktop** | Unofficial APT repo script → `apt install` | AUR: `claude-desktop-bin` | `alien` converts official `.deb` → RPM | `brew install --cask claude` (official) | — |
| **Claude Cowork** | Build from source via `go` + `make install` | ← same | ← same | ← same | — |
| **OpenCode** | `npm install -g opencode-ai` | ← same | ← same | ← same | ← same |
| **OpenSpec** | `npm install -g openspec` | ← same | ← same | ← same | ← same |

### SDK Managers (`roles/sdk_manager`)

| Software | Ubuntu/Debian | Arch Linux | Fedora | macOS | Windows |
|---|---|---|---|---|---|
| **NVM** | `curl` installer script | ← same | ← same | ← same | Chocolatey: `nvm` |
| **Pyenv** | `curl pyenv.run \| bash` | ← same | ← same | ← same | Winget: `Python.Python.3.11` |
| **SDKMAN** | `curl` installer script | ← same | ← same | ← same | — |
| **Dart SDK** | Custom curl install | ← same | ← same | ← same | — |
| **FVM (Flutter)** | Dart pub global | ← same | ← same | ← same | — |
| **Android SDK** | Manual download of cmdline-tools zip + `sdkmanager` | ← same | ← same | ← same | Winget: `Google.AndroidStudio` |

### URL-Based Package Installs (`roles/software_installer`)

These entries use direct download URLs instead of the standard repo because no official distro package exists or the repo version is outdated.

| Software | Ubuntu/Debian | Arch Linux | Fedora |
|---|---|---|---|
| **Minikube** | Direct `.deb` URL | `pacman` (official) | Direct `.rpm` URL |
| **Balena Etcher** | Direct `.deb` URL (GitHub releases) | AUR: `balena-etcher` | Direct `.rpm` URL (GitHub releases) |
| **Veracrypt** | Direct `.deb` URL (Launchpad) | `pacman` (official) | Direct `.rpm` URL (Launchpad) |
| **TeamViewer** | Direct `.deb` URL | AUR: `teamviewer` | Direct `.rpm` URL |
| **Exodus Wallet** | Direct `.deb` URL | AUR: `exodus` | Direct `.rpm` URL |
| **AppImageLauncher** | Direct `.deb` URL (GitHub releases) | AUR: `appimagelauncher` | Direct `.rpm` URL (GitHub releases) |
| **Chrome** | Official APT repo (via `arch_core`/`fedora_core`) | AUR: `google-chrome` | Direct `.rpm` URL |
| **Brave** | Official APT repo | AUR: `brave-bin` | `yum_repository` + `dnf` |
| **VS Code** | Snap | AUR: `visual-studio-code-bin` | `yum_repository` + `dnf` |
| **Sublime Text** | Official APT repo | AUR: `sublime-text-4` | `yum_repository` + `dnf` |

### Crypto Hardware (`roles/linux_crypto_hardware`)

| Software | Ubuntu/Debian | Arch Linux | Fedora |
|---|---|---|---|
| **Ledger udev rules** | `wget` script from LedgerHQ GitHub | ← same | ← same |
| **Trezor udev rules** | Official `.deb` from trezor.io | AUR: `trezor-udev` | Direct rules file from trezor.io + `udevadm reload` |
| **boot-repair** | PPA `yannubuntu/boot-repair` → apt (via `system_core`) | N/A — use `grub-install` from base `grub` package | `grubby` (default Fedora GRUB management CLI) |
