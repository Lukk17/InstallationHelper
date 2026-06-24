# Manual install — Arch Linux

Install commands for every app the playbook manages on Arch. To install the official-repo + Flatpak set at once, run [`install.sh`](install.sh).

> **AUR packages are not in `install.sh`** — they need an AUR helper. They're listed in [AUR packages](#aur-packages) with `yay -S` commands and a one-time `yay` bootstrap.

## Prerequisites

```bash
sudo pacman -Syu --needed --noconfirm flatpak
```

```bash
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
```

Steam requires the **multilib** repo. Uncomment the `[multilib]` section in `/etc/pacman.conf`, then:

```bash
sudo pacman -Sy
```

## Browsers

| App | Install command |
|---|---|
| Google Chrome | AUR `yay -S google-chrome` |
| Brave | AUR `yay -S brave-bin` |
| Tor Browser | `flatpak install -y flathub org.torproject.torbrowser-launcher` |

## Dev tools

| App | Install command |
|---|---|
| Git | `sudo pacman -S --needed git` |
| Maven | `sudo pacman -S --needed maven` |
| Gradle | `sudo pacman -S --needed gradle` |
| Postman | `flatpak install -y flathub com.getpostman.Postman` |
| OpenSSL | `sudo pacman -S --needed openssl` |
| DBeaver CE | `flatpak install -y flathub io.dbeaver.DBeaverCommunity` |
| kubectl | `sudo pacman -S --needed kubectl` |
| Minikube | `sudo pacman -S --needed minikube` |
| k3d | `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh \| bash` |
| Helm | `sudo pacman -S --needed helm` |
| Terraform | `sudo pacman -S --needed terraform` |
| GitHub CLI (gh) | `sudo pacman -S --needed github-cli` |
| jq | `sudo pacman -S --needed jq` |
| fzf | `sudo pacman -S --needed fzf` |
| ripgrep | `sudo pacman -S --needed ripgrep` |
| Lens | AUR `yay -S lens-bin` |
| FileZilla | `sudo pacman -S --needed filezilla` |

## IDEs and editors

| App | Install command |
|---|---|
| JetBrains Toolbox | AUR `yay -S jetbrains-toolbox` |
| VS Code | AUR `yay -S visual-studio-code-bin` |
| Sublime Text | AUR `yay -S sublime-text-4` |
| Arduino IDE 2.x | `flatpak install -y flathub cc.arduino.IDE2` |
| Antigravity | AUR `yay -S antigravity` |
| Bruno | `flatpak install -y flathub com.usebruno.Bruno` |

## Communication

| App | Install command |
|---|---|
| Discord | `flatpak install -y flathub com.discordapp.Discord` |
| Slack | `flatpak install -y flathub com.slack.Slack` |
| Telegram | `sudo pacman -S --needed telegram-desktop` |
| Signal | `sudo pacman -S --needed signal-desktop` |

## Productivity

| App | Install command |
|---|---|
| Obsidian | `flatpak install -y flathub md.obsidian.Obsidian` |
| Bitwarden | `flatpak install -y flathub com.bitwarden.desktop` |
| KeePassXC | `sudo pacman -S --needed keepassxc` |
| OnlyOffice | `flatpak install -y flathub org.onlyoffice.desktopeditors` |

## Media and design

| App | Install command |
|---|---|
| VLC | `sudo pacman -S --needed vlc` |
| Spotify | `flatpak install -y flathub com.spotify.Client` |
| GIMP | `flatpak install -y flathub org.gimp.GIMP` |
| Krita | `flatpak install -y flathub org.kde.krita` |
| HandBrake | `sudo pacman -S --needed handbrake` |
| Audacity | `flatpak install -y flathub org.audacityteam.Audacity` |
| RawTherapee | `sudo pacman -S --needed rawtherapee` |

## Gaming

| App | Install command |
|---|---|
| Steam | `sudo pacman -S --needed steam` *(multilib required)* |

> GOG Galaxy, Epic, EA app and CurseForge have no official Linux client.

## CAD and 3D

| App | Install command |
|---|---|
| FreeCAD | `flatpak install -y flathub org.freecad.FreeCAD` |
| PrusaSlicer | `flatpak install -y flathub com.prusa3d.PrusaSlicer` |

## Utilities

| App | Install command |
|---|---|
| Speedtest CLI | `sudo pacman -S --needed speedtest-cli` |
| GParted | `sudo pacman -S --needed gparted` |
| KDE Partition Manager | `sudo pacman -S --needed partitionmanager` |
| VeraCrypt | `sudo pacman -S --needed veracrypt` |
| TeamViewer | AUR `yay -S teamviewer` |
| AppImageLauncher | AUR `yay -S appimagelauncher` |

## Hardware monitoring

| App | Install command |
|---|---|
| HardInfo (active fork) | `sudo pacman -S --needed hardinfo2` |
| lm_sensors | `sudo pacman -S --needed lm_sensors` |
| GreenWithEnvy | `flatpak install -y flathub com.leinardi.gwe` |
| Baobab | `sudo pacman -S --needed baobab` |
| Polychromatic | `flatpak install -y flathub app.polychromatic.controller` |
| GpuTest | AUR `yay -S gputest` |

## Security

| App | Install command |
|---|---|
| Lynis | `sudo pacman -S --needed lynis` |
| chkrootkit | AUR `yay -S chkrootkit` |
| ClamAV | `sudo pacman -S --needed clamav` |

## Crypto / volunteer

| App | Install command |
|---|---|
| BOINC | `sudo pacman -S --needed boinc` |

> Gridcoin, Ledger Live and Trezor Suite need a manual install — see below.

## Virtualization

| App | Install command |
|---|---|
| QEMU/KVM + virt-manager | `sudo pacman -S --needed virt-manager qemu-full libvirt dnsmasq nftables bridge-utils virtiofsd` |
| Docker | `sudo pacman -S --needed docker` |

## Developer toolchain (SDK / runtimes)

Run as your normal user (no sudo), in order. Gradle is in pacman above; Java comes from SDKMAN.

**NVM** (pinned `0.40.4`) + Node LTS:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
```

```bash
nvm install --lts
```

**SDKMAN** + Java:

```bash
curl -s https://get.sdkman.io | bash
```

```bash
sdk install java 21.0.11-tem
```

**Pyenv** + Python:

```bash
curl https://pyenv.run | bash
```

```bash
pyenv install 3.11.15
```

**FVM** (Flutter) + Flutter stable:

```bash
curl -fsSL https://fvm.app/install.sh | bash
```

```bash
fvm install stable
```

**Dart SDK:**

```bash
sudo pacman -S --needed dart
```

## AI tools

Need Node from NVM above first.

| Tool | Install command |
|---|---|
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` |
| Claude Desktop | AUR `yay -S claude-desktop-bin` |
| OpenCode | `npm install -g opencode-ai` |
| OpenSpec | `npm install -g openspec` |
| LM Studio | `curl -fsSL https://lmstudio.ai/install.sh \| bash` |

**Stable Diffusion WebUI** (pinned `v1.10.1`):

```bash
git clone --branch v1.10.1 https://github.com/AUTOMATIC1111/stable-diffusion-webui
```

## Shell

```bash
sudo pacman -S --needed zsh
```

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

```bash
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
```

## AUR packages

`install.sh` does **not** touch the AUR. Install an AUR helper once, then the packages.

**One-time `yay` bootstrap** (the playbook's `arch_core` does this for you):

```bash
sudo pacman -S --needed --noconfirm git base-devel
```

```bash
git clone https://aur.archlinux.org/yay.git /tmp/yay
```

```bash
cd /tmp/yay && makepkg -si --noconfirm
```

Then install the AUR apps:

```bash
yay -S google-chrome brave-bin lens-bin jetbrains-toolbox visual-studio-code-bin sublime-text-4 antigravity teamviewer appimagelauncher chkrootkit gputest
```

## Manual install required

These have no package-manager path on Arch even with the AUR. Install by hand:

- **Gridcoin** (pinned `5.5.0.0`, official Flatpak bundle — not on the AUR/Flathub):

  ```bash
  curl -fsSLo /tmp/gridcoin.flatpak https://github.com/gridcoin-community/Gridcoin-Research/releases/download/5.5.0.0/gridcoin-5.5.0.0-x86_64.flatpak
  ```

  ```bash
  sudo flatpak install --system --bundle --assumeyes /tmp/gridcoin.flatpak
  ```

- **Ledger Live** — download the AppImage from [ledger.com/ledger-live](https://www.ledger.com/ledger-live).
- **Trezor Suite** (pinned `26.4.2`) — download the AppImage from [trezor.io/trezor-suite](https://trezor.io/trezor-suite).
