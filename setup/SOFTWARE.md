# Software catalog

What the playbook installs on each OS, with the install method per platform. This file is a quick reference; the authoritative source is `setup/ansible/vars/{Debian,RedHat,Archlinux,Darwin,Windows}.yaml` plus the URL/version pins in `setup/ansible/group_vars/versions.yaml`. If anything here drifts from a `vars/*.yaml`, trust the YAML.

## Installation phase order

The playbook runs in this order. Each phase must succeed before the next can start safely.

1. OS core bootstrap — `system_core`, `arch_core`, `fedora_core`, `debian_core`, `windows_core`, `macos_core` (multilib, locale, keyrings dir, Homebrew bootstrap on macOS).
2. APT / DNF repo provisioning — `roles/software_installer/tasks/debian_repos.yaml` and `fedora_repos.yaml` write keyrings under `/etc/apt/keyrings/` and `*.repo` files for Chrome, Brave, VS Code, Sublime, kubectl, Docker before any package install runs.
3. SDK / runtime managers — JVM, Pyenv, NVM, SDKMAN (Java, Gradle), FVM.
4. Snapd and Flatpak with the Flathub remote (Linux).
5. Batched package installs — one call per manager (`apt`, `dnf`, `pacman`, `snap`, `flatpak`, `brew`, `brew_cask`) so dependency resolution happens once per OS.
6. Custom installs — `custom_installs.yaml` (Linux: Gridcoin PPA/repo/flatpak, OpenLens AppImage, GpuTest binary), `macos_install.yaml` (Antigravity DMG when published, Gridcoin DMG), `windows_install.yaml` (Chocolatey + winget batches, Gridcoin `.exe` silent install).

Gradle is managed via SDKMAN on every Linux distro, not the system package manager. The `versions.yaml` pin drives `sdk install gradle`.

## Cross-platform applications

### Browsers

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| Google Chrome | Official APT repo + `google-chrome-stable` | Official DNF repo + `google-chrome-stable` | AUR `google-chrome` | cask `google-chrome` | winget `Google.Chrome` |
| Brave | Official APT repo + `brave-browser` | Official DNF repo + `brave-browser` | AUR `brave-bin` | cask `brave-browser` | winget `Brave.Brave` |
| Tor Browser | flatpak `org.torproject.torbrowser-launcher` | flatpak | flatpak | cask `tor-browser` | winget `TorProject.TorBrowser` |

### Dev tools

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| Git | `apt git` | `dnf git` | `pacman git` | brew `git` | winget `Git.Git` |
| Maven | `apt maven` | `dnf maven` | `pacman maven` | brew `maven` | Chocolatey `choco install maven` (no winget manifest under Apache/) |
| Gradle | SDKMAN `sdk install gradle` | SDKMAN | `pacman gradle` | brew `gradle` | Chocolatey `choco install gradle` (no Gradle publisher in winget-pkgs) |
| Postman | flatpak `com.getpostman.Postman` | flatpak | flatpak | cask `postman` | winget `Postman.Postman` |
| OpenSSL | `apt openssl` | `dnf openssl` | `pacman openssl` | brew `openssl@3` (versioned formula) | winget `ShiningLight.OpenSSL.Light` |
| DBeaver CE | flatpak `io.dbeaver.DBeaverCommunity` | flatpak | flatpak | cask `dbeaver-community` | winget `DBeaver.DBeaver.Community` |
| kubectl | Official k8s APT repo (`pkgs.k8s.io`, minor pinned in `versions.yaml`) | Official k8s DNF repo | `pacman kubectl` | brew `kubernetes-cli` | winget `Kubernetes.kubectl` |
| Minikube | Direct `.deb` pinned to `{{ minikube_version }}` (currently `v1.38.1`) | Direct `.rpm` pinned | `pacman minikube` | brew `minikube` | winget `Kubernetes.minikube` |
| Lens | Official Lens apt repo (`downloads.k8slens.dev/apt/debian`) + `apt install lens` | Official Lens dnf repo (`downloads.k8slens.dev/rpm/packages`) + `dnf install lens` | AUR `lens-bin` | cask `lens` | winget `Mirantis.Lens` |
| FileZilla | `apt filezilla` | `dnf filezilla` | `pacman filezilla` | Cyberduck cask (no FileZilla cask on macOS) | Chocolatey `choco install filezilla` (FileZilla blocks third-party installers, so winget manifest was removed — see winget-pkgs issues #65824/#89756/#131827/#154585) |

> Lens Desktop is free for personal use and for individuals with annual revenue below USD 10M (see [Lens pricing](https://lenshq.io/pricing)). The playbook installs it from the official apt/dnf repos at `downloads.k8slens.dev`, which give you the same auto-update path the upstream installer uses.

### IDEs and editors

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| JetBrains Toolbox | tarball download + extract | tarball | AUR `jetbrains-toolbox` | cask `jetbrains-toolbox` | direct installer (via Toolbox) |
| VS Code | Microsoft APT repo + `code` | Microsoft DNF repo + `code` | AUR `visual-studio-code-bin` | cask `visual-studio-code` | winget `Microsoft.VisualStudioCode` |
| Sublime Text | Sublime APT repo + `sublime-text` | Sublime DNF repo + `sublime-text` | AUR `sublime-text-4` | cask `sublime-text` | winget `SublimeHQ.SublimeText.4` |
| Arduino IDE 2.x | flatpak `cc.arduino.IDE2` | flatpak | `pacman arduino` | cask `arduino-ide` | winget `ArduinoSA.IDE.stable` |
| Antigravity | Official Google apt repo (`us-central1-apt.pkg.dev`) + `apt install antigravity` | Official Google yum repo (`us-central1-yum.pkg.dev`) + `dnf install antigravity` | AUR `antigravity` | Direct DMG from Google's official CDN `edgedl.me.gvt1.com`, arch-detected (Apple Silicon or Intel) | winget `Google.AntigravityIDE` |
| Bruno | flatpak `com.usebruno.Bruno` | flatpak | flatpak | cask `bruno` | winget `Bruno.Bruno` |

> The `intellij` toggle is intentionally disabled in `group_vars/all.yaml`. IntelliJ is installed and updated via JetBrains Toolbox, which the playbook manages directly. Carrying a parallel winget/cask install would create version drift.

### Communication

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| Discord | flatpak `com.discordapp.Discord` | flatpak | flatpak | cask `discord` | winget `Discord.Discord` |
| Slack | flatpak `com.slack.Slack` | flatpak | flatpak | cask `slack` | winget `SlackTechnologies.Slack` |
| Telegram | flatpak `org.telegram.desktop` | flatpak | `pacman telegram-desktop` | cask `telegram` | winget `Telegram.TelegramDesktop` |
| Signal | flatpak `org.signal.Signal` | flatpak | `pacman signal-desktop` | cask `signal` | winget `OpenWhisperSystems.Signal` |
| WhatsApp | not on Flathub | not on Flathub | not on Flathub | cask `whatsapp` | winget MS Store ID `9NKSQGP7F2NH` |
| Microsoft Teams | not available natively (web) | not available natively | not available natively | cask `microsoft-teams` | winget `Microsoft.Teams` |

### Productivity

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| Obsidian | flatpak `md.obsidian.Obsidian` | flatpak | flatpak | cask `obsidian` | winget `Obsidian.Obsidian` |
| Bitwarden | flatpak `com.bitwarden.desktop` | flatpak | flatpak | cask `bitwarden` | winget `Bitwarden.Bitwarden` |
| KeePassXC | `apt keepassxc` | `dnf keepassxc` | `pacman keepassxc` | cask `keepassxc` | winget `KeePassXCTeam.KeePassXC` |
| Trello | not on Flathub | not on Flathub | not on Flathub | manual (no Homebrew cask) | winget MS Store ID `XP8K0HKJFRXGCK` |
| OnlyOffice | flatpak `org.onlyoffice.desktopeditors` | flatpak | flatpak | cask `onlyoffice` | winget `ONLYOFFICE.DesktopEditors` |

### Media and design

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| VLC | `apt vlc` | `dnf vlc` | `pacman vlc` | cask `vlc` | winget `VideoLAN.VLC` |
| Spotify | flatpak `com.spotify.Client` | flatpak | flatpak | cask `spotify` | winget `Spotify.Spotify` |
| GIMP | flatpak `org.gimp.GIMP` | flatpak | flatpak | cask `gimp` | winget `GIMP.GIMP.3` |
| Krita | flatpak `org.kde.krita` | flatpak | flatpak | cask `krita` | winget `KDE.Krita` |
| HandBrake | flatpak `fr.handbrake.ghb` | flatpak | `pacman handbrake` | cask `handbrake-app` | winget `HandBrake.HandBrake` |
| Audacity | flatpak `org.audacityteam.Audacity` | flatpak | flatpak | cask `audacity` | winget `Audacity.Audacity` |
| RawTherapee | `apt rawtherapee` | `dnf rawtherapee` | `pacman rawtherapee` | cask `rawtherapee` | winget `RawTherapee.RawTherapee` |

### Gaming

| App | Linux | macOS | Windows |
|---|---|---|---|
| Steam | Arch: `pacman steam` (multilib required). Debian / Fedora: flatpak `com.valvesoftware.Steam` | cask `steam` | winget `Valve.Steam` |
| GOG Galaxy | — (no official Linux client) | cask `gog-galaxy` | winget `GOG.Galaxy` |
| Epic Games Launcher | — (no official Linux client) | cask `epic-games` | winget `EpicGames.EpicGamesLauncher` |
| EA app | — (no official Linux client) | cask `ea` | winget `ElectronicArts.EADesktop` |
| CurseForge | — (no official Linux client) | cask `curseforge` | winget `Overwolf.CurseForge` |
| Razer Cortex | — | — | winget MS Store ID `9PK9W5QV2PKX` (no standalone winget manifest) |
| WoW Logs Companion / TSM | — | — | manual (Overwolf / tradeskillmaster.com — no winget manifest) |

### CAD and 3D

| App | Linux | macOS | Windows |
|---|---|---|---|
| FreeCAD | flatpak `org.freecadweb.FreeCAD` | cask `freecad` | winget `FreeCAD.FreeCAD` |
| PrusaSlicer | flatpak `com.prusa3d.PrusaSlicer` | cask `prusaslicer` | winget `Prusa3D.PrusaSlicer` |

### Utilities

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| TeamViewer | direct `.deb` | direct `.rpm` | AUR `teamviewer` | cask `teamviewer` | winget `TeamViewer.TeamViewer` |
| VeraCrypt | direct `.deb` pinned to `{{ veracrypt_version }}` (currently `1.26.24`, Ubuntu-24.04 build) | direct `.rpm` (CentOS-8 build works on Fedora 38+) | `pacman veracrypt` | cask `veracrypt` | winget `IDRIX.VeraCrypt` |
| Speedtest CLI | `apt speedtest-cli` | `dnf speedtest-cli` | `pacman speedtest-cli` | brew `speedtest-cli` | winget `Ookla.Speedtest.CLI` |
| AppImageLauncher | direct `.deb` (GitHub releases) | direct `.rpm` (GitHub releases) | AUR `appimagelauncher` | — | — |

### Crypto / Volunteer

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| BOINC | `apt boinc-client` | `dnf boinc-client` | `pacman boinc` | cask `boinc` | winget `UCBerkeley.BOINC` |
| Gridcoin | PPA `ppa:gridcoin/gridcoin-stable` + `apt gridcoinresearch` | OpenSUSE build-service repo (custom task) | Official flatpak bundle from GitHub releases | DMG from GitHub releases (`gridcoin-5.5.0.0-macos-x86_64.dmg`) | NSIS `.exe` from GitHub releases (silent `/S`) |

## SDK and runtime managers

Installed by the `sdk_manager` role. All versions are pinned in `setup/ansible/group_vars/versions.yaml`.

| Manager / runtime | Linux | macOS | Windows |
|---|---|---|---|
| NVM | curl installer pinned to `{{ nvm_version }}` | same | (NVM-for-Windows via winget if needed) |
| Node.js LTS | `nvm install --lts` | same | same |
| SDKMAN | `curl -s https://get.sdkman.io \| bash` | same | not supported |
| Java (Temurin) | Pinned IDs: 11.0.30-tem, 17.0.18-tem, 21.0.10-tem, 25.0.2-tem. Default `default_java` is `21.0.10-tem`. Install via `sdk install java <id>` | same | same (via SDKMAN inside WSL) |
| Pyenv | `curl https://pyenv.run \| bash` | same | use Pyenv-win |
| Python | Pinned: 3.10.16, 3.11.11, 3.12.8, 3.13.2. Default `default_python` is `3.11.11`. Install via `pyenv install <id>` | same | same |
| Dart SDK | `apt dart` / `dnf dart` / `pacman dart` | brew `dart` | manual |
| FVM (Flutter) | `curl -fsSL https://fvm.app/install.sh \| bash` | same | manual |
| Flutter (stable) | `fvm install stable` | same | same |
| Android SDK | `sdkmanager "platform-tools" "build-tools;{{ android_build_tools_version }}"` (currently `35.0.0`, API `35`) | same | install Android Studio via winget |

## AI tools

Installed by the `ai_tools` role. Each toggle now gates its own `import_tasks` so disabled tools never run their setup.

| Tool | Linux | macOS | Windows |
|---|---|---|---|
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` (via NVM) | same | winget / npm |
| Claude Desktop | Debian unofficial APT repo; Arch AUR `claude-desktop-bin`; Fedora via `alien` from upstream `.deb` | cask `claude` | — |
| OpenCode | `npm install -g opencode-ai` | same | same |
| OpenSpec | `npm install -g openspec` | same | same |
| LM Studio | `curl -fsSL https://lmstudio.ai/install.sh \| bash` | same | manual |
| Stable Diffusion WebUI | `git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui` | same | manual |

## Shell and terminal

Installed by `shell_zsh`.

| Item | Linux | macOS |
|---|---|---|
| zsh | `apt zsh` / `dnf zsh` / `pacman zsh` | brew `zsh` |
| Oh My Zsh | official unattended installer | same |
| Powerlevel10k | git clone into `~/.oh-my-zsh/custom/themes/powerlevel10k` | same |
| MesloLGS NF | TTF download to `/usr/share/fonts/` | TTF download to `~/Library/Fonts/` |

## Linux-only software

### Security

| App | Debian / Ubuntu | Fedora | Arch |
|---|---|---|---|
| Lynis | `apt lynis` | `dnf lynis` | `pacman lynis` |
| chkrootkit | `apt chkrootkit` | `dnf chkrootkit` | AUR `chkrootkit` |
| ClamAV | `apt clamav` | `dnf clamav` | `pacman clamav` |

### Crypto hardware

| App | Method |
|---|---|
| Ledger Live | AppImage download (all distros) |
| Trezor Suite | AppImage download (all distros) |

### Hardware monitoring and alternatives

| App | Windows analogue | macOS analogue | Install method |
|---|---|---|---|
| HardInfo | HWMonitor | Stats | Arch: `pacman hardinfo2`. Debian: `apt hardinfo`. Fedora: `dnf hardinfo2` (Fedora 42+ ships the active fork; legacy `hardinfo` is no longer packaged). |
| lm_sensors | HWiNFO | Stats | `pacman lm_sensors` / `apt lm-sensors` / `dnf lm_sensors` |
| GreenWithEnvy | MSI Afterburner | — | flatpak `com.leinardi.gwe` |
| Baobab | WizTree | GrandPerspective | `pacman baobab` / `apt baobab` / `dnf baobab` |
| Polychromatic | Razer Cortex | — | flatpak `app.polychromatic.controller` |
| GpuTest | FurMark | — | Arch: AUR `gputest`. Debian / Fedora: binary download from `ozone3d.net`, extracted to `/opt/gputest`. |

### Virtualization and system

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| QEMU/KVM + virt-manager | `apt qemu-kvm libvirt-daemon-system virt-manager virtinst bridge-utils virtiofsd` | `dnf qemu-kvm libvirt virt-manager virt-install bridge-utils virtiofsd` | `pacman virt-manager qemu-full libvirt dnsmasq nftables bridge-utils virtiofsd` | — | — |
| Docker | Official Docker CE APT repo + `docker-ce` | Official Docker CE DNF repo + `docker-ce` | `pacman docker` | cask `docker-desktop` | winget `Docker.DockerDesktop` |
| VirtualBox | — | — | — | — | winget `Oracle.VirtualBox` |
| VMware | — | — | — | cask `vmware-fusion` (macOS-only equivalent of Workstation) | manual — no winget manifest post-Broadcom |
| GParted | `apt gparted` | `dnf gparted` | `pacman gparted` | — | — |
| KDE Partition Manager | `apt partitionmanager` | `dnf kde-partitionmanager` | `pacman partitionmanager` | — | — |
| PuTTY | `apt putty` | — | — | — | winget `PuTTY.PuTTY` |

### Arch Linux helpers

| Tool | Method |
|---|---|
| yay | git clone + `makepkg -si` (handled by `arch_core`) |
| paru | git clone + cargo build + `makepkg -si` |
| snapd | AUR via paru |

## macOS-only

`macos_core` bootstraps Homebrew if it is missing (`brew_check.rc != 0` → official installer).

| App | Linux analogue | Windows analogue | Install |
|---|---|---|---|
| Stats | HardInfo / lm_sensors | HWMonitor | cask `stats` |
| GrandPerspective | Baobab | WizTree | cask `grandperspective` |
| LuLu | ufw / iptables | GlassWire | cask `lulu` |
| Balena Etcher | — | Rufus | cask `balenaetcher` |
| UTM | virt-manager | VirtualBox | cask `utm` |
| Docker Desktop | docker (native) | Docker Desktop | cask `docker-desktop` |
| VMware Fusion | virt-manager | — | cask `vmware-fusion` |

## Windows-only

| App | Category | Linux analogue | macOS analogue | Install |
|---|---|---|---|---|
| HWMonitor | hardware | HardInfo | Stats | winget `CPUID.HWMonitor` |
| HWiNFO | hardware | lm_sensors | Stats | winget `REALiX.HWiNFO` |
| CrystalDiskInfo | disk health | — | — | winget `CrystalDewWorld.CrystalDiskInfo` |
| CrystalDiskMark | disk benchmark | — | — | winget `CrystalDewWorld.CrystalDiskMark` |
| MSI Afterburner | GPU OC | GreenWithEnvy | — | winget `Guru3D.Afterburner` |
| WizTree | disk space | Baobab | GrandPerspective | winget `AntibodySoftware.WizTree` |
| Angry IP Scanner | network | — | — | winget `angryziber.AngryIPScanner` |
| Advanced IP Scanner | network | — | — | winget `Famatech.AdvancedIPScanner` |
| GlassWire | firewall | ufw / iptables | LuLu | winget `GlassWire.GlassWire` |
| TCPView | network | — | — | winget `Microsoft.Sysinternals.TCPView` |
| Autoruns | system | — | — | winget `Microsoft.Sysinternals.Autoruns` |
| Rufus | USB creator | Balena Etcher | Balena Etcher | winget `Rufus.Rufus` |
| PowerToys | productivity | — | — | winget `Microsoft.PowerToys` |
| MiniTool Partition Wizard | disk | GParted | — | winget `MiniTool.PartitionWizard.Free` |
| Samsung Galaxy Buds Manager | audio | — | — | winget `Samsung.GalaxyBudsManager` |

### Streaming and OEM apps (Windows)

These ship as Microsoft Store packages or have no maintained winget manifest. The toggles in `group_vars/windows.yaml` map them through winget's MS Store ID support where available, and are commented out with a manual install link where they are not.

| App | Status |
|---|---|
| Netflix | winget MS Store ID `9WZDNCRFJ3TJ` |
| Disney+ | winget MS Store ID `9NXQXXLFST89` |
| Prime Video | winget MS Store ID `9P6RC76MSMMJ` |
| iTunes | winget MS Store ID `9PB2MZ1ZMB1S` |
| GeForce Experience | **Discontinued** by NVIDIA — replaced by the NVIDIA App (no winget/choco manifest). Disabled by default (`install_geforce_experience: false`); install the NVIDIA App from nvidia.com |
| VMware Workstation Player | Chocolatey `choco install vmware-workstation-player` (no winget manifest post-Broadcom acquisition; upstream marked the choco package deprecated but the installer remains functional) |

## Per-OS install caveats

- **Antigravity Linux**: installed from Google's official apt/yum repos (`us-central1-apt.pkg.dev`, `us-central1-yum.pkg.dev`) configured by `debian_repos.yaml` / `fedora_repos.yaml`. Updates flow through `apt upgrade` / `dnf upgrade` automatically. The Arch AUR slug `antigravity` works today.
- **Antigravity macOS**: direct DMG from Google's official CDN `edgedl.me.gvt1.com` (Google Video Transcoding — same CDN Chrome itself uses, owned by Google, not a third-party mirror). `macos_install.yaml` reads `ansible_facts['architecture']` and picks `antigravity_dmg_arm64_url` on Apple Silicon, `antigravity_dmg_x64_url` on Intel. Version pinned in `versions.yaml` (`antigravity_version`, `antigravity_build`) — bump these when a new release ships at [antigravity.google/download](https://antigravity.google/download).
- **VMware Workstation Player on Windows**: no winget manifest post-Broadcom. Falls back to Chocolatey (`vmware-workstation-player` — verified, installer functional, package itself marked deprecated by maintainer).
- **VMware on macOS**: maps to `vmware-fusion` cask (the macOS-only product; Workstation Player is Windows/Linux).
- **FileZilla on Windows**: FileZilla blocks third-party installers, so winget removed the manifest. Falls back to Chocolatey (`filezilla` — verified).
- **FileZilla on macOS**: no Homebrew cask exists. The `install_filezilla` toggle maps to **Cyberduck** (cask `cyberduck`) — the standard free macOS FTP/SFTP/S3 client. To install FileZilla specifically, set `install_filezilla: false` and download from `filezilla-project.org`.
- **Lens on Linux**: installed from the official `downloads.k8slens.dev` apt/dnf repo, package name `lens`. Lens Desktop is free for personal use.
- **GeForce Experience on Windows**: discontinued by NVIDIA, replaced by the NVIDIA App (which has no winget or Chocolatey manifest). The `install_geforce_experience` toggle defaults to `false` in `group_vars/windows.yaml`; install the NVIDIA App manually from nvidia.com.
- **Gridcoin macOS DMG**: pinned to `5.5.0.0`. Apple Silicon users may want the `-macos-arm64.dmg` variant; today the playbook installs the `x86_64` build via Rosetta. Switching is a one-line change in `versions.yaml`.

## Download integrity

`setup/ansible/group_vars/versions.yaml` exposes a `download_checksums` mapping. To enforce sha256 verification on `get_url` tasks (AppImages, custom DMG/EXE installers, the Gridcoin flatpak bundle), set entries like:

```yaml
download_checksums:
  lens_appimage: "sha256:0123abcd..."
  gputest: "sha256:..."
  antigravity_macos: "sha256:..."
  gridcoin_macos: "sha256:..."
  gridcoin_flatpak: "sha256:..."
```

Leaving an entry unset disables checksum enforcement for that download — Ansible substitutes `omit`.
