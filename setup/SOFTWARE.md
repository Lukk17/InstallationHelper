# Software Installation Reference

All software installed by the Ansible playbook with exact install commands per OS/distro.

---

## Cross-Platform Software

### Browsers

| Software | Install Command |
|---|---|
| Google Chrome | Arch: `paru -S google-chrome`<br>Debian: `apt install ./google-chrome-stable_current_amd64.deb`<br>Fedora: `dnf install google-chrome-stable`<br>macOS: `brew install --cask googlechrome`<br>Windows: `winget install Google.Chrome` |
| Brave Browser | Arch: `paru -S brave-bin`<br>Debian/Fedora: `flatpak install com.brave.Browser`<br>macOS: `brew install --cask brave-browser`<br>Windows: `winget install Brave.Brave` |
| Tor Browser | Arch/Debian/Fedora: `flatpak install org.torproject.torbrowser-launcher`<br>macOS: `brew install --cask tor-browser`<br>Windows: `winget install TorProject.TorBrowser` |

### Dev Tools

| Software | Install Command |
|---|---|
| Git | Arch: `pacman -S git`<br>Debian: `apt install git`<br>Fedora: `dnf install git`<br>macOS: `brew install git`<br>Windows: `winget install Git.Git` |
| Maven | Arch: `pacman -S maven`<br>Debian: `apt install maven`<br>Fedora: `dnf install maven`<br>macOS: `brew install maven`<br>Windows: `winget install Apache.Maven` |
| Gradle | Arch: `pacman -S gradle`<br>Debian: `apt install gradle`<br>Fedora: `dnf install gradle`<br>macOS: `brew install gradle`<br>Windows: `winget install Gradle.Gradle` |
| Postman | Arch/Debian/Fedora: `flatpak install com.getpostman.Postman`<br>macOS: `brew install --cask postman`<br>Windows: `winget install Postman.Postman` |
| OpenSSL | Arch: `pacman -S openssl`<br>Debian: `apt install openssl`<br>Fedora: `dnf install openssl`<br>macOS: `brew install openssl`<br>Windows: `winget install ShiningLight.OpenSSL.Dev` |
| DBeaver CE | Arch/Debian/Fedora: `flatpak install io.dbeaver.DBeaverCommunity`<br>macOS: `brew install --cask dbeaver-community`<br>Windows: `winget install DBeaver.DBeaver.Community` |
| kubectl | Arch: `pacman -S kubectl`<br>Debian/Fedora: `snap install kubectl --classic`<br>macOS: `brew install kubectl`<br>Windows: `winget install Kubernetes.kubectl` |
| Minikube | Arch: `pacman -S minikube`<br>Debian: `apt install ./minikube_latest_amd64.deb`<br>Fedora: `dnf install minikube-latest.x86_64.rpm`<br>macOS: `brew install minikube`<br>Windows: `winget install Kubernetes.minikube` |
| Lens | Arch: `paru -S lens-bin`<br>Debian/Fedora: — *(removed from Snap Store)*<br>macOS: `brew install --cask lens`<br>Windows: `winget install Mirantis.Lens` |
| FileZilla | Arch: `pacman -S filezilla`<br>Debian: `apt install filezilla`<br>Fedora: `dnf install filezilla`<br>macOS: `brew install --cask filezilla`<br>Windows: `winget install TimKosse.FileZillaClient` |

### IDEs / Editors

| Software | Install Command |
|---|---|
| JetBrains Toolbox | Arch: `paru -S jetbrains-toolbox`<br>Debian/Fedora: auto-download tarball + extract<br>macOS: `brew install --cask jetbrains-toolbox` |
| VS Code | Arch: `paru -S visual-studio-code-bin`<br>Debian: `snap install code --classic`<br>Fedora: `dnf install code`<br>macOS: `brew install --cask visual-studio-code`<br>Windows: `winget install Microsoft.VisualStudioCode` |
| Sublime Text | Arch: `paru -S sublime-text-4`<br>Debian: `snap install sublime-text --classic`<br>Fedora: `dnf install sublime-text`<br>macOS: `brew install --cask sublime-text`<br>Windows: `winget install SublimeHQ.SublimeText.4` |
| Arduino IDE | Arch: `pacman -S arduino`<br>Debian/Fedora: `snap install arduino`<br>macOS: `brew install --cask arduino`<br>Windows: `winget install ArduinoSA.IDE.stable` |
| Bruno | Arch/Debian/Fedora: `flatpak install com.usebruno.Bruno`<br>macOS: `brew install --cask bruno`<br>Windows: `winget install Bruno.Bruno` |

### Communication

| Software | Install Command |
|---|---|
| Discord | Arch/Debian/Fedora: `flatpak install com.discordapp.Discord`<br>macOS: `brew install --cask discord`<br>Windows: `winget install Discord.Discord` |
| Slack | Arch/Debian/Fedora: `flatpak install com.slack.Slack`<br>macOS: `brew install --cask slack`<br>Windows: `winget install SlackTechnologies.Slack` |
| Telegram | Arch: `pacman -S telegram-desktop`<br>Debian/Fedora: `snap install telegram-desktop`<br>macOS: `brew install --cask telegram`<br>Windows: `winget install Telegram.TelegramDesktop` |
| Signal | Arch: `pacman -S signal-desktop`<br>Debian/Fedora: `snap install signal-desktop`<br>macOS: `brew install --cask signal`<br>Windows: `winget install OpenWhisperSystems.Signal` |
| WhatsApp | Linux: — *(not available)*<br>macOS: `brew install --cask whatsapp`<br>Windows: `winget install WhatsApp.WhatsApp` |
| Microsoft Teams | Linux: — *(not available)*<br>macOS: `brew install --cask microsoft-teams`<br>Windows: `winget install Microsoft.Teams` |

### Productivity

| Software | Install Command |
|---|---|
| Obsidian | Arch/Debian/Fedora: `flatpak install md.obsidian.Obsidian`<br>macOS: `brew install --cask obsidian`<br>Windows: `winget install Obsidian.Obsidian` |
| Bitwarden | Arch/Debian/Fedora: `flatpak install com.bitwarden.desktop`<br>macOS: `brew install --cask bitwarden`<br>Windows: `winget install Bitwarden.Bitwarden` |
| KeePassXC | Arch: `pacman -S keepassxc`<br>Debian: `apt install keepassxc`<br>Fedora: `dnf install keepassxc`<br>macOS: `brew install --cask keepassxc`<br>Windows: `winget install KeePassXCTeam.KeePassXC` |
| Trello | Linux: — *(not available)*<br>macOS: `brew install --cask trello`<br>Windows: `winget install Trello.Trello` |
| OnlyOffice | Arch/Debian/Fedora: `flatpak install org.onlyoffice.desktopeditors`<br>macOS: `brew install --cask onlyoffice`<br>Windows: `winget install ONLYOFFICE.DesktopEditors` |

### Media / Design

| Software | Install Command |
|---|---|
| VLC | Arch: `pacman -S vlc`<br>Debian: `apt install vlc`<br>Fedora: `dnf install vlc`<br>macOS: `brew install --cask vlc`<br>Windows: `winget install VideoLAN.VLC` |
| Spotify | Arch/Debian/Fedora: `flatpak install com.spotify.Client`<br>macOS: `brew install --cask spotify`<br>Windows: `winget install Spotify.Spotify` |
| GIMP | Arch/Debian/Fedora: `flatpak install org.gimp.GIMP`<br>macOS: `brew install --cask gimp`<br>Windows: `winget install GIMP.GIMP.3` |
| Krita | Arch/Debian/Fedora: `flatpak install org.kde.krita`<br>macOS: `brew install --cask krita`<br>Windows: `winget install KDE.Krita` |
| HandBrake | Arch: `pacman -S handbrake`<br>Debian: `apt install handbrake`<br>Fedora: `dnf install HandBrake-gui`<br>macOS: `brew install --cask handbrake`<br>Windows: `winget install HandBrake.HandBrake` |
| Audacity | Arch: `pacman -S audacity`<br>Debian: `apt install audacity`<br>Fedora: `snap install audacity`<br>macOS: `brew install --cask audacity`<br>Windows: `winget install Audacity.Audacity` |
| RawTherapee | Arch: `pacman -S rawtherapee`<br>Debian: `apt install rawtherapee`<br>Fedora: `dnf install rawtherapee`<br>macOS: `brew install --cask rawtherapee`<br>Windows: `winget install RawTherapee.RawTherapee` |

### Gaming

| Software | Install Command |
|---|---|
| Steam | Arch: `pacman -S steam`<br>Debian: `snap install steam`<br>Fedora: `dnf install steam`<br>macOS: `brew install --cask steam`<br>Windows: `winget install Valve.Steam` |

### CAD / 3D

| Software | Install Command |
|---|---|
| FreeCAD | Arch/Debian/Fedora: `flatpak install org.freecadweb.FreeCAD`<br>macOS: `brew install --cask freecad`<br>Windows: `winget install FreeCAD.FreeCAD` |
| PrusaSlicer | Arch: `pacman -S prusa-slicer`<br>Debian: `apt install prusa-slicer`<br>Fedora: `snap install prusa-slicer`<br>macOS: `brew install --cask prusa-slicer`<br>Windows: `winget install Prusa3D.PrusaSlicer` |

### Utilities

| Software | Install Command |
|---|---|
| TeamViewer | Arch: `paru -S teamviewer`<br>Debian: `apt install ./teamviewer_amd64.deb`<br>Fedora: `dnf install teamviewer.rpm`<br>macOS: `brew install --cask teamviewer`<br>Windows: `winget install TeamViewer.TeamViewer` |
| VeraCrypt | Arch: `pacman -S veracrypt`<br>Debian: `apt install ./veracrypt.deb`<br>Fedora: `dnf install veracrypt.rpm`<br>macOS: `brew install --cask veracrypt`<br>Windows: `winget install IDRIX.VeraCrypt` |
| Speedtest CLI | Arch: `paru -S speedtest-cli`<br>Debian: `apt install speedtest-cli`<br>Fedora: `dnf install speedtest-cli`<br>macOS: `brew install speedtest-cli`<br>Windows: `winget install Ookla.Speedtest` |

### Crypto / Volunteer

| Software | Install Command |
|---|---|
| BOINC | Arch: `pacman -S boinc`<br>Debian: `apt install boinc-client`<br>Fedora: `dnf install boinc-client`<br>macOS: `brew install --cask boinc`<br>Windows: `winget install SpaceSciencesLaboratory.BOINC` |
| Gridcoin | Arch: `paru -S gridcoinresearch-qt`<br>Debian: — *(not in repos)*<br>Fedora: `dnf install gridcoinresearch`<br>macOS: `brew install --cask gridcoinresearch`<br>Windows: `winget install Gridcoin.Client` |

---

## SDK / Runtime Managers (Custom Roles)

Installed via `sdk_manager` role. Same commands on all Linux distros and macOS unless noted.

| Software | Install Command |
|---|---|
| NVM | `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh \| bash` |
| Node.js LTS | `nvm install --lts` (via NVM) |
| SDKMAN | `curl -s https://get.sdkman.io \| bash` |
| Java Temurin 11/17/21/25 | `sdk install java 21.0.10-tem` (via SDKMAN) |
| Pyenv | `curl https://pyenv.run \| bash` |
| Python 3.10/3.11/3.12/3.13 | `pyenv install 3.12.8` (via Pyenv, requires build-essential) |
| Dart SDK | Arch: `pacman -S dart`<br>Debian: `apt install dart` (official repo)<br>Fedora: `dnf install dart`<br>macOS: `brew install dart` |
| FVM | `curl -fsSL https://fvm.app/install.sh \| bash` |
| Flutter (stable) | `fvm install stable` (via FVM) |
| Android SDK | `sdkmanager "platform-tools" "build-tools;34.0.0"` (downloaded to `/opt/android`) |

## AI Tools (Custom Roles)

Installed via `ai_tools` role.

| Software | Install Command |
|---|---|
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` (Linux/macOS via NVM) |
| Claude Desktop | Debian: `apt install ./Claude-linux-x86_64.deb` |
| OpenCode | `npm install -g @nicepkg/opencode` (Linux/macOS via NVM) |
| OpenSpec | `npm install -g openspec` (Linux/macOS via NVM) |
| LM Studio | `curl -fsSL https://lmstudio.ai/install.sh \| bash` (Linux/macOS) |
| Stable Diffusion WebUI | `git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui` (Linux/macOS) |

## Shell / Terminal (Custom Role)

Installed via `shell_zsh` role.

| Software | Install Command |
|---|---|
| ZSH | Arch: `pacman -S zsh`<br>Debian: `apt install zsh`<br>Fedora: `dnf install zsh`<br>macOS: `brew install zsh` |
| Oh-My-Zsh | `sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended` |
| Powerlevel10k | `git clone https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k` |
| MesloLGS NF Fonts | Download to `/usr/share/fonts/` (Linux) or `~/Library/Fonts/` (macOS) |

---

## Linux-Only Software

### Security

| Software | Install Command |
|---|---|
| Lynis | Arch: `pacman -S lynis`<br>Debian: `apt install lynis`<br>Fedora: `dnf install lynis` |
| chkrootkit | Arch: `paru -S chkrootkit`<br>Debian: `apt install chkrootkit`<br>Fedora: `dnf install chkrootkit` |
| ClamAV | Arch: `pacman -S clamav`<br>Debian: `apt install clamav`<br>Fedora: `dnf install clamav` |

### Crypto Hardware

| Software | Install Command |
|---|---|
| Exodus Wallet | Arch: `paru -S exodus`<br>Debian: — *(download blocked)*<br>Fedora: `dnf install exodus.rpm` |
| Ledger Live | AppImage download (all distros) |
| Trezor Suite | AppImage download (all distros) |

### Hardware Monitoring & Alternatives

| Software | Alt on Windows | Alt on macOS | Install Command |
|---|---|---|---|
| HardInfo | HWMonitor | Stats | Arch: `pacman -S hardinfo2`<br>Debian: `apt install hardinfo`<br>Fedora: `dnf install hardinfo` |
| lm_sensors | HWInfo | Stats | Arch: `pacman -S lm_sensors`<br>Debian: `apt install lm-sensors`<br>Fedora: `dnf install lm_sensors` |
| GreenWithEnvy | MSI Afterburner | — | Arch/Debian/Fedora: `flatpak install com.leinardi.gwe` |
| Baobab | WizTree | GrandPerspective | Arch: `pacman -S baobab`<br>Debian: `apt install baobab`<br>Fedora: `dnf install baobab` |
| Polychromatic | Razer Cortex | — | Arch: `paru -S polychromatic`<br>Debian: — *(not in repos)*<br>Fedora: `dnf install polychromatic` |
| GpuTest | FurMark | — | Arch: `paru -S gputest`<br>Debian: — *(not in repos)*<br>Fedora: `dnf install gputest` |

### Virtualization & System

| Software | Install Command |
|---|---|
| Virt-Manager + QEMU/KVM | Arch: `pacman -S virt-manager qemu-full libvirt dnsmasq nftables bridge-utils virtiofsd`<br>Debian: `apt install qemu-kvm libvirt-daemon-system virt-manager virtinst bridge-utils virtiofsd`<br>Fedora: `dnf install qemu-kvm libvirt virt-manager virt-install bridge-utils virtiofsd` |
| Docker | Arch: `pacman -S docker`<br>Debian: `apt install docker.io`<br>Fedora: `dnf install moby-engine` |
| AppImageLauncher | Arch: `paru -S appimagelauncher`<br>Debian: `apt install ./appimagelauncher.deb`<br>Fedora: `dnf install appimagelauncher.rpm` |
| GParted | Arch: `pacman -S gparted`<br>Debian: `apt install gparted`<br>Fedora: `dnf install gparted` |
| KDE Partition Manager | Arch: `pacman -S partitionmanager`<br>Debian: `apt install partitionmanager`<br>Fedora: `dnf install partitionmanager` |
| PuTTY | Debian: `apt install putty`<br>*(other distros: use built-in SSH)* |

### Arch Linux Only

| Software | Install Command |
|---|---|
| yay (AUR helper) | `git clone + makepkg -si` |
| paru (AUR helper) | `git clone + cargo build + makepkg -si` |
| snapd | `paru -S snapd` |

---

## macOS-Only Software

| Software | Alt on Linux | Alt on Windows | Install Command |
|---|---|---|---|
| Stats | HardInfo / lm_sensors | HWMonitor | `brew install --cask stats` |
| GrandPerspective | Baobab | WizTree | `brew install --cask grandperspective` |
| LuLu | iptables / ufw | GlassWire | `brew install --cask lulu` |
| Balena Etcher | — | Rufus | `brew install --cask balenaetcher` |
| UTM | Virt-Manager | VirtualBox | `brew install --cask utm` |
| Docker Desktop | Docker (native) | Docker Desktop | `brew install --cask docker` |

---

## Windows-Only Software

| Software | Category | Alt on Linux | Alt on macOS | Install Command |
|---|---|---|---|---|
| HWMonitor | Hardware | HardInfo | Stats | `winget install CPUID.HWMonitor` |
| HWInfo | Hardware | lm_sensors | Stats | `winget install REALiX.HWiNFO` |
| CrystalDiskInfo | Disk Health | — | — | `winget install CrystalDewWorld.CrystalDiskInfo` |
| CrystalDiskMark | Disk Benchmark | — | — | `winget install CrystalDewWorld.CrystalDiskMark` |
| MSI Afterburner | GPU OC | GreenWithEnvy | — | `winget install Guru3D.Afterburner` |
| WizTree | Disk Space | Baobab | GrandPerspective | `winget install AntibodySoftware.WizTree` |
| Advanced IP Scanner | Network | — | — | `winget install angryziber.AngryIPScanner` |
| GlassWire | Firewall | ufw / iptables | LuLu | `winget install GlassWire.GlassWire` |
| TCPView | Network | — | — | `winget install Microsoft.Sysinternals.TCPView` |
| Autoruns | System | — | — | `winget install Microsoft.Sysinternals.Autoruns` |
| Rufus | USB Creator | Balena Etcher | Balena Etcher | `winget install Rufus.Rufus` |
| PowerToys | Productivity | — | — | `winget install Microsoft.PowerToys` |
| PuTTY | SSH Client | Built-in SSH | Built-in SSH | `winget install PuTTY.PuTTY` |
| GOG Galaxy | Gaming | Heroic Launcher (flatpak) | — | `winget install GOG.Galaxy` |
| Epic Games | Gaming | Heroic Launcher (flatpak) | — | `winget install EpicGames.EpicGamesLauncher` |
| Netflix | Streaming | — | — | `winget install Netflix` |
| Disney+ | Streaming | — | — | `winget install Disney+` |
| Prime Video | Streaming | — | — | `winget install Amazon.PrimeVideo` |
| iTunes | Media | — | — | `winget install Apple.iTunes` |
| GeForce Experience | GPU | — | — | `winget install NVIDIA.GeForceExperience` |
| Razer Cortex | Peripherals | Polychromatic | — | `winget install Razer.Cortex` |
| Galaxy Buds Manager | Audio | — | — | `winget install Samsung.GalaxyBudsManager` |
| Canon App | Printing | — | — | `winget install Canon.CanonPrintApp` |
| Docker Desktop | Containers | Docker (native) | Docker Desktop | `winget install Docker.DockerDesktop` |
| MiniTool Partition | Disk | GParted | — | `winget install MiniTool.PartitionWizard.Free` |

---

> **Note:** All Linux/macOS SDK managers (NVM, SDKMAN, Pyenv, FVM) and AI tools (Claude Code, OpenCode, OpenSpec) are installed via custom Ansible roles (`sdk_manager`, `ai_tools`). Windows equivalents use the `*_windows.yaml` task files in those roles.
