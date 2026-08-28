# Manual install — Arch Linux

Install commands for every app the playbook manages on Arch. To install the official-repo + Flatpak set at once, run [`install.sh`](install.sh).

> **AUR packages are not in `install.sh`** — they need an AUR helper. They're listed in [AUR packages](#aur-packages) with `yay -S` commands and a one-time `yay` bootstrap.

> **This page covers CachyOS too.** CachyOS reports `ID=cachyos` with `ID_LIKE=arch` and resolves through the same `vars/Archlinux.yaml` mapping, so every package name below is the right name there. One command differs, and it is Steam: see [Steam on CachyOS](#steam-on-cachyos).

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

### Steam on CachyOS

On CachyOS the command above fails, and it fails in a way that reads like a broken mirror rather than
what it is. Steam depends on the virtual package `lib32-vulkan-driver`, and the first provider of that
in CachyOS repository order is its own `cachyos-v3/lib32-mesa-git`, which needs `mesa-git`, which
conflicts with the stable `mesa` almost every desktop already has. pacman stops to ask whether to
remove `mesa`, and under `--noconfirm` that question is answered no, so the whole transaction fails.

Align the graphics stack with what the distribution's own repositories prefer, once, and then install
Steam normally:

```bash
sudo pacman -Syy --needed mesa-git lib32-mesa-git
```

```bash
sudo pacman -S --needed steam
```

Answer yes when it offers to replace `mesa` and `lib32-mesa`. That is what a CachyOS machine is set up
to use.

If the first command fails while retrieving a `lib32-` file with a 404, the repository is not broken,
one mirror is incomplete. Measured on 2026-08-28, `lib32-glibc-2.44+r24+g16be1518495f-1` and
`lib32-gcc-libs-16.2.1+r23+gd564253eb6c8-1`, the exact builds the index names, answer 200 on
`mirror.cachyos.org` and 404 on `cdn77.cachyos.org`. Check that `/etc/pacman.d/cachyos-mirrorlist` has
more than one entry before blaming anything upstream:

```bash
grep -c '^Server' /etc/pacman.d/cachyos-mirrorlist
```

## CAD and 3D

| App | Install command |
|---|---|
| FreeCAD | `flatpak install -y flathub org.freecad.FreeCAD` |
| PrusaSlicer | `flatpak install -y flathub com.prusa3d.PrusaSlicer` |

## Utilities

| App | Install command |
|---|---|
| Speedtest CLI | `sudo pacman -S --needed speedtest-cli` |
| Syncthing | `sudo pacman -S --needed syncthing` |
| Tailscale | `sudo pacman -S --needed tailscale` |
| GParted | `sudo pacman -S --needed gparted` |
| KDE Partition Manager | `sudo pacman -S --needed partitionmanager` |
| VeraCrypt | `sudo pacman -S --needed veracrypt` |
| TeamViewer | AUR `yay -S teamviewer` |
| AppImageLauncher | AUR `yay -S appimagelauncher` |

The Syncthing package ships a systemd user unit but leaves it disabled. Enable it so Syncthing starts at login as the owner of the synced files:

```bash
systemctl --user enable --now syncthing.service
```

The Tailscale package ships a systemd system unit but leaves it disabled. It runs in system scope, not user scope like Syncthing, because the daemon owns a network interface and routing table entries:

```bash
sudo systemctl enable --now tailscaled
```

Joining a tailnet stays manual: run `sudo tailscale up` once by hand and authenticate in the browser it opens.

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
- Trezor Suite: download the AppImage from [trezor.io/trezor-suite](https://trezor.io/trezor-suite). The playbook installs the udev rules only, so the application itself is a manual download and carries no pinned version.
