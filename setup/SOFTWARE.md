# Software Installation Reference

All software installed by the Ansible playbook, organized by OS family with exact installation method per distro/platform.

**Manager abbreviations:**

| Abbreviation | Description |
|---|---|
| `pacman` | Arch Linux native package manager |
| `apt` | Debian/Ubuntu native package manager |
| `dnf` | Fedora/RedHat native package manager |
| `aur` | AUR helper (yay / paru) |
| `snap` | Snap package |
| `flatpak` | Flatpak package |
| `brew` | Homebrew formula (CLI tools) |
| `brew cask` | Homebrew Cask (GUI apps) |
| `choco` | Chocolatey |
| `winget` | Windows Package Manager |
| `download + apt` | Download .deb, install via apt |
| `download + dnf` | Download .rpm, install via dnf |
| `npm` | npm global install (via NVM) |
| `curl script` | Official install script via curl |
| `git clone + build` | Clone repo, build locally, install via pacman |

---

## 🐧 Linux

> Distros: **Arch Linux**, **Debian/Ubuntu**, **Fedora**

### Browsers

| Software | Installation Method |
|---|---|
| Google Chrome | Arch: `aur`<br>Debian: `download + apt`<br>Fedora: `download + dnf` |
| Brave Browser | Arch: `aur`<br>Debian: `apt` (official repo)<br>Fedora: `dnf` (official repo) |
| Tor Browser | `flatpak` (all distros) |

### Dev Tools

| Software | Installation Method |
|---|---|
| Git | Arch: `pacman`<br>Debian: `apt`<br>Fedora: `dnf` |
| Maven | Arch: `pacman`<br>Debian: `apt`<br>Fedora: `dnf` |
| Gradle | Arch: `pacman`<br>Debian: `apt`<br>Fedora: `dnf` |
| Postman | `snap` (all distros) |
| OpenSSL | Arch: `pacman`<br>Debian: `apt`<br>Fedora: `dnf` |
| DBeaver CE | `snap` (all distros) |
| kubectl | Arch: `pacman`<br>Debian: `snap`<br>Fedora: `snap` |
| Minikube | Arch: `pacman`<br>Debian: `download + apt`<br>Fedora: `download + dnf` |
| Lens | Arch: `aur`<br>Debian: `snap`<br>Fedora: `snap` |
| FileZilla | Arch: `pacman`<br>Debian: `apt`<br>Fedora: `dnf` |
| PuTTY | Debian: `apt` *(Debian only)* |

### IDEs / Editors

| Software | Installation Method |
|---|---|
| IntelliJ IDEA Ultimate | `snap` (all distros) |
| VS Code | Arch: `aur`<br>Debian: `snap`<br>Fedora: `dnf` (official repo) |
| Sublime Text | Arch: `aur`<br>Debian: `apt` (official repo)<br>Fedora: `dnf` (official repo) |
| Arduino IDE | Arch: `pacman`<br>Debian: `snap`<br>Fedora: `snap` |
| Antigravity | Arch: `aur`<br>Debian: `download + apt`<br>Fedora: `download + dnf` |

### Communication

| Software | Installation Method |
|---|---|
| Discord | `flatpak` (all distros) |
| Slack | `snap` (all distros) |
| Microsoft Teams | `snap` (all distros) |
| Telegram Desktop | Arch: `pacman`<br>Debian: `snap`<br>Fedora: `snap` |
| Signal | Arch: `pacman`<br>Debian: `snap`<br>Fedora: `snap` |
| WhatsApp | `snap` (all distros) |

### Productivity

| Software | Installation Method |
|---|---|
| Obsidian | `snap` (all distros) |
| Bitwarden | `snap` (all distros) |
| KeePassXC | Arch: `pacman`<br>Debian: `snap`<br>Fedora: `dnf` |
| Trello | `snap` (all distros) |
| OnlyOffice | `flatpak` (all distros) |

### Media / Design

| Software | Installation Method |
|---|---|
| VLC | Arch: `pacman`<br>Debian: `snap`<br>Fedora: `dnf` |
| Spotify | `snap` (all distros) |
| GIMP | `flatpak` (all distros) |
| Krita | `flatpak` (all distros) |
| HandBrake | Arch: `pacman`<br>Debian: `apt`<br>Fedora: `dnf` |
| Audacity | Arch: `pacman`<br>Debian: `snap`<br>Fedora: `snap` |
| RawTherapee | Arch: `pacman`<br>Debian: `apt`<br>Fedora: `dnf` |

### Gaming

| Software | Installation Method |
|---|---|
| Steam | Arch: `pacman`<br>Debian: `snap`<br>Fedora: `dnf` |
| GOG / Epic (Heroic Launcher) | Debian: `flatpak` *(Debian only)* |

### CAD / 3D

| Software | Installation Method |
|---|---|
| FreeCAD | `flatpak` (all distros) |
| PrusaSlicer | Arch: `pacman`<br>Debian: `snap`<br>Fedora: `snap` |

### Utilities

| Software | Installation Method |
|---|---|
| TeamViewer | Arch: `aur`<br>Debian: `download + apt`<br>Fedora: `download + dnf` |
| VeraCrypt | Arch: `pacman`<br>Debian: `download + apt`<br>Fedora: `download + dnf` |
| Speedtest CLI | Arch: `aur`<br>Debian: `apt`<br>Fedora: `dnf` |
| AppImageLauncher | Arch: `aur`<br>Debian: `download + apt`<br>Fedora: `download + dnf` |

### Security

| Software | Installation Method |
|---|---|
| Lynis | Arch: `pacman`<br>Debian: `apt`<br>Fedora: `dnf` |
| chkrootkit | Arch: `aur`<br>Debian: `apt`<br>Fedora: `dnf` |
| ClamAV | Arch: `pacman`<br>Debian: `apt`<br>Fedora: `dnf` |

### Crypto / Volunteer

| Software | Installation Method |
|---|---|
| Exodus Wallet | Arch: `aur`<br>Debian: `download + apt`<br>Fedora: `download + dnf` |
| BOINC | Arch: `pacman`<br>Debian: `apt`<br>Fedora: `dnf` |
| Gridcoin | Arch: `aur`<br>Debian: `apt`<br>Fedora: `dnf` |
| Ledger Live | `AppImage` (download) *(Linux only)* |
| Trezor Suite | `AppImage` (download) *(Linux only)* |

### Linux Alternatives (to Windows-only apps)

| Software | Alternative For | Installation Method |
|---|---|---|
| HardInfo | HWMonitor | Arch: `aur`<br>Debian: `apt`<br>Fedora: `dnf` |
| lm_sensors | HWInfo | Arch: `pacman`<br>Debian: `apt`<br>Fedora: `dnf` |
| GreenWithEnvy | MSI Afterburner | `flatpak` (all distros) |
| Baobab | WizTree | Arch: `pacman`<br>Debian: `apt`<br>Fedora: `dnf` |
| Polychromatic | Razer Cortex | Arch: `aur`<br>Debian: `apt`<br>Fedora: `dnf` (official repo) |
| Balena Etcher | Rufus | Arch: `aur`<br>Debian: `download + apt`<br>Fedora: `download + dnf` |
| GpuTest | FurMark | Arch: `aur`<br>Debian: `apt`<br>Fedora: `dnf` |

### Virtualization

| Software | Installation Method |
|---|---|
| Virt-Manager + QEMU/KVM | Arch: `pacman` (qemu-full, virt-manager, libvirt, dnsmasq, nftables, bridge-utils, virtiofsd)<br>Debian: `apt` (qemu-kvm, libvirt-daemon-system, virt-manager, virtinst, bridge-utils, virtiofsd)<br>Fedora: `dnf` (qemu-kvm, libvirt, virt-manager, virt-install, bridge-utils, virtiofsd) |
| Docker | Arch: `pacman`<br>Debian: `apt`<br>Fedora: `dnf` |

### System Tools (Arch Linux only)

| Software | Installation Method |
|---|---|
| yay (AUR helper) | `git clone + makepkg + pacman` |
| paru (AUR helper) | `git clone + cargo build + pacman` |
| snapd | Arch: `aur` (paru)<br>Fedora: `dnf` (built-in) |

### Shell / Terminal

| Software | Installation Method |
|---|---|
| ZSH | Arch: `pacman`<br>Debian: `apt`<br>Fedora: `dnf` |
| Oh-My-Zsh | `curl script` (all distros) |
| Powerlevel10k theme | `git clone` (all distros) |
| MesloLGS NF fonts | `download` (all distros) |

### SDK / Runtime Managers

| Software | Installation Method |
|---|---|
| NVM | `curl script` (all distros) |
| Node.js LTS | via NVM (all distros) |
| SDKMAN | `curl script` (all distros) |
| Java Temurin 11 / 17 / 21 / 25 | via SDKMAN (all distros) |
| Pyenv | `curl script` (all distros) |
| Python 3.10 / 3.11 / 3.12 / 3.13 | via Pyenv (all distros) |
| Dart SDK | Arch: `pacman`<br>Debian: `apt` (official repo)<br>Fedora: `dnf` |
| FVM | `curl script` (fvm.app) — falls back to `dart pub global` if Dart is present (all distros) |
| Flutter (stable) | via FVM (all distros) |
| Android SDK (cmdline-tools, platform-tools, build-tools) | `download + sdkmanager` (all distros) |

### AI Tools

| Software | Installation Method |
|---|---|
| Claude Code CLI | `npm` via NVM (all distros) |
| Claude Desktop | `curl script` (Linux) |
| OpenCode | `npm` via NVM (all distros) |
| OpenSpec | `npm` via NVM (all distros) |

---

## 🍎 macOS

### Browsers

| Software | Installation Method |
|---|---|
| Google Chrome | `brew cask` |
| Brave Browser | `brew cask` |
| Tor Browser | `brew cask` |

### Dev Tools

| Software | Installation Method |
|---|---|
| Git | `brew` |
| Maven | `brew` |
| Gradle | `brew` |
| Postman | `brew cask` |
| OpenSSL | `brew` |
| DBeaver CE | `brew cask` |
| kubectl | `brew` |
| Minikube | `brew` |
| Lens | `brew cask` |
| FileZilla | `brew cask` |

### IDEs / Editors

| Software | Installation Method |
|---|---|
| IntelliJ IDEA Ultimate | `brew cask` |
| VS Code | `brew cask` |
| Sublime Text | `brew cask` |
| Arduino IDE | `brew cask` |
| Antigravity | `brew cask` |

### Communication

| Software | Installation Method |
|---|---|
| Discord | `brew cask` |
| Slack | `brew cask` |
| Microsoft Teams | `brew cask` |
| Telegram | `brew cask` |
| Signal | `brew cask` |
| WhatsApp | `brew cask` |

### Productivity

| Software | Installation Method |
|---|---|
| Obsidian | `brew cask` |
| Bitwarden | `brew cask` |
| KeePassXC | `brew cask` |
| Trello | `brew cask` |
| OnlyOffice | `brew cask` |

### Media / Design

| Software | Installation Method |
|---|---|
| VLC | `brew cask` |
| Spotify | `brew cask` |
| GIMP | `brew cask` |
| Krita | `brew cask` |
| HandBrake | `brew cask` |
| Audacity | `brew cask` |
| RawTherapee | `brew cask` |

### Gaming

| Software | Installation Method |
|---|---|
| Steam | `brew cask` |

### CAD / 3D

| Software | Installation Method |
|---|---|
| FreeCAD | `brew cask` |
| PrusaSlicer | `brew cask` |

### Utilities

| Software | Installation Method |
|---|---|
| TeamViewer | `brew cask` |
| VeraCrypt | `brew cask` |
| Speedtest CLI | `brew` |
| Lynis | `brew` |

### Crypto / Volunteer

| Software | Installation Method |
|---|---|
| BOINC | `brew cask` |
| Gridcoin | `brew cask` |

### macOS Alternatives (to Windows-only apps)

| Software | Alternative For | Installation Method |
|---|---|---|
| Stats | HWMonitor | `brew cask` |
| GrandPerspective | WizTree | `brew cask` |
| LuLu | GlassWire | `brew cask` |
| Balena Etcher | Rufus | `brew cask` |

### Virtualization

| Software | Installation Method |
|---|---|
| UTM | `brew cask` |
| Docker Desktop | `brew cask` |

### Shell / Terminal

| Software | Installation Method |
|---|---|
| ZSH | `brew` |
| Oh-My-Zsh | `curl script` |
| Powerlevel10k theme | `git clone` |
| MesloLGS NF fonts | `download` |

### SDK / Runtime Managers

| Software | Installation Method |
|---|---|
| NVM | `curl script` |
| Node.js LTS | via NVM |
| SDKMAN | `curl script` |
| Java Temurin 11 / 17 / 21 / 25 | via SDKMAN |
| Pyenv | `curl script` |
| Python 3.10 / 3.11 / 3.12 / 3.13 | via Pyenv |
| Dart SDK | `brew` |
| FVM | `curl script` (fvm.app) |
| Flutter (stable) | via FVM |
| Android SDK (cmdline-tools, platform-tools, build-tools) | `download + sdkmanager` |

### AI Tools

| Software | Installation Method |
|---|---|
| Claude Code CLI | `npm` via NVM |
| Claude Desktop | `brew cask` |
| OpenCode | `npm` via NVM |
| OpenSpec | `npm` via NVM |

---

## 🪟 Windows

### Browsers

| Software | Installation Method |
|---|---|
| Google Chrome | `choco` |
| Brave Browser | `choco` |
| Tor Browser | `choco` |

### Dev Tools

| Software | Installation Method |
|---|---|
| Git | `choco` |
| Maven | `choco` |
| Gradle | `choco` |
| Postman | `choco` |
| OpenSSL | `choco` |
| DBeaver CE | `choco` |
| kubectl | `winget` |
| Minikube | `winget` |
| Lens | `winget` |
| FileZilla | `winget` |
| PuTTY | `winget` |

### IDEs / Editors

| Software | Installation Method |
|---|---|
| IntelliJ IDEA Ultimate | `choco` |
| VS Code | `winget` |
| Sublime Text | `choco` |
| Arduino IDE | `winget` |
| Antigravity | `winget` |

### Communication

| Software | Installation Method |
|---|---|
| Discord | `winget` |
| Slack | `winget` |
| Microsoft Teams | `winget` |
| Telegram Desktop | `winget` |
| Signal | `choco` |
| WhatsApp | `winget` |

### Productivity

| Software | Installation Method |
|---|---|
| Obsidian | `choco` |
| Bitwarden | `winget` |
| KeePassXC | `winget` |
| Trello | `winget` |
| OnlyOffice | `winget` |

### Media / Design

| Software | Installation Method |
|---|---|
| VLC | `winget` |
| Spotify | `winget` |
| GIMP | `choco` |
| Krita | `choco` |
| HandBrake | `winget` |
| Audacity | `winget` |
| RawTherapee | `winget` |

### Gaming

| Software | Installation Method |
|---|---|
| Steam | `choco` |
| GOG Galaxy | `winget` |
| Epic Games Launcher | `winget` |

### CAD / 3D

| Software | Installation Method |
|---|---|
| FreeCAD | `choco` |
| PrusaSlicer | `choco` |

### Utilities

| Software | Installation Method |
|---|---|
| TeamViewer | `choco` |
| VeraCrypt | `winget` |
| Speedtest | `winget` |

### Crypto / Volunteer

| Software | Installation Method |
|---|---|
| BOINC | `winget` |
| Gridcoin | `choco` |

### Windows-Only Apps

| Software | Category | Installation Method |
|---|---|---|
| HWMonitor | Hardware Monitor | `choco` |
| CrystalDiskInfo | Disk Health | `choco` |
| MSI Afterburner | GPU Overclocking | `choco` |
| WizTree | Disk Space Analyzer | `choco` |
| Advanced IP Scanner | Network | `choco` |
| GlassWire | Firewall / Network Monitor | `choco` |
| TCPView | Network | `choco` |
| Autoruns | System | `choco` |
| Rufus | USB Bootable Creator | `choco` |
| PowerToys | Productivity | `winget` |

### Virtualization

| Software | Installation Method |
|---|---|
| Docker Desktop | `winget` |

---

> **Note:** SDK managers (NVM, SDKMAN, Pyenv, FVM, Android SDK) and AI tools (Claude Code, OpenCode, OpenSpec) are installed via custom Ansible roles (`sdk_manager`, `ai_tools`) on Linux and macOS. Windows SDK support is handled by the corresponding `*_windows.yaml` task files in those roles.
