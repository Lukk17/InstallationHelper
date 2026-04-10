# Setup (Unified Cross-Platform Ansible Migration)

This project has been fully migrated from monolithic bash/powershell scripts to a highly modular, data-driven, cross-platform Ansible setup. It supports **Ubuntu/Debian**, **Fedora**, **Archlinux**, **Windows**, and **macOS** out of the box.

---

## 🚀 Quick Start

**Working Directory:** All Ansible commands must be run from the `setup/ansible` directory.

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

### 2. Navigate to Ansible Directory

**⚠️ Important:** All subsequent commands must be run from this directory:
```bash
cd setup/ansible
```

### 3. Install Required Ansible Collections
```bash
ansible-galaxy collection install -r requirements.yaml
```

### 4. Configure Your Setup
Review `group_vars/all.yaml` (and the OS-specific files in `group_vars/`) and set the flags for the tools and settings you wish to apply to your machine.

If you have a specific setup profile, you can override the variables by pointing to it during execution.

### 5. Run the Playbook
The `-K` flag ensures Ansible can prompt for the sudo password used for administrative tasks.

**Standard run (any OS):**
```bash
ansible-playbook site.yaml -i localhost, -c local -K
```

**Linux Live / USB profile:**
```bash
ansible-playbook site.yaml -i localhost, -c local -e "@profiles/linux_live.yaml" -K
```

---

## 📋 Logging

The playbook automatically creates two log files in your home directory on every run:

| Log File | Contents |
|----------|----------|
| `~/installation_full.log` | Complete output of the playbook (all tasks, info, warnings, errors) |
| `~/installation_issues.log` | Only warnings and errors for quick troubleshooting |

**Features:**
- Both files are **overwritten** on each run (not appended)
- Logs are created automatically - no additional configuration needed
- Works on all platforms (Linux, macOS, Windows via WSL)

### Troubleshooting Log Issues

If the playbook fails with a logging error:
```
FATAL: Cannot write to log files ~/installation_full.log or ~/installation_issues.log
```

**Option 1: Check permissions**
Ensure your user has write access to the home directory.

**Option 2: Disable logging failure (not recommended)**
If you need to run without file logging, set in `group_vars/all.yaml`:
```yaml
allow_callback_failure: true
```

Or use command line (one-time):
```bash
ansible-playbook site.yaml -i localhost, -c local -K --extra-vars "allow_callback_failure=true"
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
* **`ai_tools`**: Installs NPM/Go binaries (Claude Code, OpenCode, OpenSpec, Cowork Service) and Claude Desktop per-platform.
* **`sdk_manager`**: Installs Pyenv, NVM, SDKMAN, FVM, Android SDK, Dart.
* **`linux_crypto_hardware`**: Installs udev rules for Trezor/Ledger.
* **`waydroid`**: Configures kernel parameters and custom GDM files for Wayland container execution.
* **`system_core`**: Full system upgrade, tmpfs, GRUB timeout, RTC fix, and locale setup (all distros).
* **`virtualization_config`**: Installs QEMU/KVM + virt-manager + virtiofsd on Linux; auto-installs `spice-vdagent` when running inside a VM guest. On macOS, UTM is used for native virtualization. On Windows, VirtualBox and VMware Workstation Player are available via Chocolatey.

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

### Virtualization Tools

| Software | Ubuntu/Debian | Arch Linux | Fedora | macOS | Windows |
|---|---|---|---|---|---|
| **QEMU/KVM + virt-manager** | Native `apt` packages | Native `pacman` packages | Native `dnf` packages | — | — |
| **UTM** | — | — | — | `brew install --cask utm` (native Apple Virtualization) | — |
| **VirtualBox** | — | — | — | — | Chocolatey: `virtualbox` |
| **VMware Workstation** | — | — | — | — | Chocolatey: `vmware-workstation-player` |
| **Docker** | Native `docker.io` package | Native `docker` package | Native `docker-ce` package | `brew install --cask docker` (Docker Desktop) | Winget: `Docker.DockerDesktop` |

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
