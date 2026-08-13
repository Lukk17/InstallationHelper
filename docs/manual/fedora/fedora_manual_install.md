# Manual install — Fedora

Install commands for every app the playbook manages on Fedora. To install the whole package-manager set at once, run [`install.sh`](install.sh) instead.

> Tested against Fedora 42/43. All `dnf` commands need `sudo`. Direct `.rpm` versions are pinned in [`versions.yaml`](../../../setup/ansible/group_vars/versions.yaml).

## Prerequisites

```bash
sudo dnf install -y dnf-plugins-core flatpak
```

```bash
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
```

## Repository setup

Run the block for each repo-based app **before** its `dnf install`. (`install.sh` does this for you.)

**Google Chrome:**

```bash
sudo tee /etc/yum.repos.d/google-chrome.repo >/dev/null <<'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
```

**Brave:**

```bash
sudo tee /etc/yum.repos.d/brave-browser.repo >/dev/null <<'EOF'
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/x86_64/
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
EOF
```

**VS Code:**

```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
```

```bash
sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<'EOF'
[vscode]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
```

**Sublime Text:**

```bash
sudo rpm --import https://download.sublimetext.com/sublimehq-rpm-pub.gpg
```

```bash
sudo tee /etc/yum.repos.d/sublime-text.repo >/dev/null <<'EOF'
[sublime-text]
name=Sublime Text
baseurl=https://download.sublimetext.com/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://download.sublimetext.com/sublimehq-rpm-pub.gpg
EOF
```

**kubectl** (Kubernetes minor stream `v1.36`):

```bash
sudo tee /etc/yum.repos.d/kubernetes.repo >/dev/null <<'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/repodata/repomd.xml.key
EOF
```

**Lens Desktop:**

```bash
sudo rpm --import https://downloads.k8slens.dev/keys/gpg
```

```bash
sudo tee /etc/yum.repos.d/lens.repo >/dev/null <<'EOF'
[lens]
name=Lens Desktop
baseurl=https://downloads.k8slens.dev/rpm/packages
enabled=1
gpgcheck=1
gpgkey=https://downloads.k8slens.dev/keys/gpg
EOF
```

**Terraform** (official HashiCorp repo):

```bash
sudo dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
```

**Tailscale** (official Tailscale repo, one repo file for every Fedora release):

```bash
sudo dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
```

## Browsers

| App | Install command |
|---|---|
| Google Chrome | `sudo dnf install -y google-chrome-stable` *(repo above)* |
| Brave | `sudo dnf install -y brave-browser` *(repo above)* |
| Tor Browser | `flatpak install -y flathub org.torproject.torbrowser-launcher` |

## Dev tools

| App | Install command |
|---|---|
| Git | `sudo dnf install -y git` |
| Maven | `sudo dnf install -y maven` |
| Postman | `flatpak install -y flathub com.getpostman.Postman` |
| OpenSSL | `sudo dnf install -y openssl` |
| DBeaver CE | `flatpak install -y flathub io.dbeaver.DBeaverCommunity` |
| kubectl | `sudo dnf install -y kubectl` *(repo above)* |
| Lens | `sudo dnf install -y lens` *(repo above)* |
| FileZilla | `sudo dnf install -y filezilla` |
| Minikube | `sudo dnf install -y https://github.com/kubernetes/minikube/releases/download/v1.38.1/minikube-1.38.1-0.x86_64.rpm` |
| k3d | `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh \| bash` |
| Helm | `sudo dnf install -y helm` |
| Terraform | `sudo dnf install -y terraform` *(repo above)* |
| GitHub CLI | `sudo dnf install -y gh` |
| jq | `sudo dnf install -y jq` |
| fzf | `sudo dnf install -y fzf` |
| ripgrep | `sudo dnf install -y ripgrep` |

> Gradle is installed via SDKMAN — see [Developer toolchain](#developer-toolchain-sdk--runtimes).

## IDEs and editors

| App | Install command |
|---|---|
| VS Code | `sudo dnf install -y code` *(repo above)* |
| Sublime Text | `sudo dnf install -y sublime-text` *(repo above)* |
| Arduino IDE 2.x | `flatpak install -y flathub cc.arduino.IDE2` |
| Bruno | `flatpak install -y flathub com.usebruno.Bruno` |

> Antigravity needs a manual install — see below.

## Communication

| App | Install command |
|---|---|
| Discord | `flatpak install -y flathub com.discordapp.Discord` |
| Slack | `flatpak install -y flathub com.slack.Slack` |
| Telegram | `flatpak install -y flathub org.telegram.desktop` |
| Signal | `flatpak install -y flathub org.signal.Signal` |

## Productivity

| App | Install command |
|---|---|
| Obsidian | `flatpak install -y flathub md.obsidian.Obsidian` |
| Bitwarden | `flatpak install -y flathub com.bitwarden.desktop` |
| KeePassXC | `sudo dnf install -y keepassxc` |
| OnlyOffice | `flatpak install -y flathub org.onlyoffice.desktopeditors` |

## Media and design

| App | Install command |
|---|---|
| VLC | `sudo dnf install -y vlc` |
| Spotify | `flatpak install -y flathub com.spotify.Client` |
| GIMP | `flatpak install -y flathub org.gimp.GIMP` |
| Krita | `flatpak install -y flathub org.kde.krita` |
| HandBrake | `flatpak install -y flathub fr.handbrake.ghb` |
| Audacity | `flatpak install -y flathub org.audacityteam.Audacity` |
| RawTherapee | `sudo dnf install -y rawtherapee` |

## Gaming

| App | Install command |
|---|---|
| Steam | `flatpak install -y flathub com.valvesoftware.Steam` |

> GOG Galaxy, Epic, EA app and CurseForge have no official Linux client.

## CAD and 3D

| App | Install command |
|---|---|
| FreeCAD | `flatpak install -y flathub org.freecad.FreeCAD` |
| PrusaSlicer | `flatpak install -y flathub com.prusa3d.PrusaSlicer` |

## Utilities

| App | Install command |
|---|---|
| Speedtest CLI | `sudo dnf install -y speedtest-cli` |
| Syncthing | `sudo dnf install -y syncthing` |
| Tailscale | `sudo dnf install -y tailscale` *(repo above)* |
| GParted | `sudo dnf install -y gparted` |
| KDE Partition Manager | `sudo dnf install -y kde-partitionmanager` |
| Boot repair (grubby) | `sudo dnf install -y grubby` |
| TeamViewer | `sudo dnf install -y https://download.teamviewer.com/download/linux/teamviewer.x86_64.rpm` |
| VeraCrypt | `sudo dnf install -y https://launchpad.net/veracrypt/trunk/1.26.24/+download/veracrypt-1.26.24-CentOS-8-x86_64.rpm` |
| Balena Etcher | `sudo dnf install -y https://github.com/balena-io/etcher/releases/download/v2.1.6/balena-etcher-2.1.6-1.x86_64.rpm` |

The Syncthing package ships a systemd user unit but leaves it disabled. Enable it so Syncthing starts at login as the owner of the synced files:

```bash
systemctl --user enable --now syncthing.service
```

The Tailscale package ships a systemd system unit but leaves it disabled. It runs in system scope, not user scope like Syncthing, because the daemon owns a network interface and routing table entries:

```bash
sudo systemctl enable --now tailscaled
```

Joining a tailnet stays manual: run `sudo tailscale up` once by hand and authenticate in the browser it opens.

**AppImageLauncher** — the 2020 upstream RPM lacks file digests and `dnf5` (Fedora 43+) refuses it, so install with `rpm --nodigest`:

```bash
curl -fsSLo /tmp/appimagelauncher.rpm https://github.com/TheAssassin/AppImageLauncher/releases/download/v2.2.0/appimagelauncher-2.2.0-travis995.0f91801.x86_64.rpm
```

```bash
sudo rpm --install --upgrade --replacepkgs --nodigest /tmp/appimagelauncher.rpm
```

## Hardware monitoring

| App | Install command |
|---|---|
| HardInfo (active fork) | `sudo dnf install -y hardinfo2` |
| lm_sensors | `sudo dnf install -y lm_sensors` |
| GreenWithEnvy | `flatpak install -y flathub com.leinardi.gwe` |
| Baobab | `sudo dnf install -y baobab` |
| Polychromatic | `flatpak install -y flathub app.polychromatic.controller` |

## Security

| App | Install command |
|---|---|
| Lynis | `sudo dnf install -y lynis` |
| chkrootkit | `sudo dnf install -y chkrootkit` |
| ClamAV | `sudo dnf install -y clamav` |

## Crypto / volunteer

| App | Install command |
|---|---|
| BOINC | `sudo dnf install -y boinc-client` |

> Gridcoin, Ledger Live and Trezor Suite need a manual install — see below.

## Virtualization

| App | Install command |
|---|---|
| QEMU/KVM + virt-manager | `sudo dnf install -y qemu-kvm libvirt virt-manager virt-install bridge-utils virtiofsd` |

**Docker CE** (official repo):

```bash
sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
```

```bash
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

## Developer toolchain (SDK / runtimes)

Run as your normal user (no sudo), in order — each writes to your shell rc and must be sourced before the next.

**NVM** (pinned `0.40.4`) + Node LTS:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
```

```bash
nvm install --lts
```

**SDKMAN** + Java + Gradle:

```bash
curl -s https://get.sdkman.io | bash
```

```bash
sdk install java 21.0.11-tem
```

```bash
sdk install gradle
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
sudo dnf install -y dart
```

## AI tools

Need Node from NVM above first.

| Tool | Install command |
|---|---|
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` |
| OpenCode | `npm install -g opencode-ai` |
| OpenSpec | `npm install -g openspec` |
| LM Studio | `curl -fsSL https://lmstudio.ai/install.sh \| bash` |

**Stable Diffusion WebUI** (pinned `v1.10.1`):

```bash
git clone --branch v1.10.1 https://github.com/AUTOMATIC1111/stable-diffusion-webui
```

## Shell

```bash
sudo dnf install -y zsh
```

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

```bash
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
```

## Manual install required

These are **not** in `install.sh` — no clean package-manager path exists. Install by hand:

- **Antigravity** — download the Linux tarball and extract to `/opt/antigravity`:

  ```bash
  curl -fsSLo /tmp/antigravity.tar.gz "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/1.13.3-4533425205018624/linux-x64/Antigravity.tar.gz"
  ```

  ```bash
  sudo mkdir -p /opt/antigravity && sudo tar -xzf /tmp/antigravity.tar.gz -C /opt/antigravity --strip-components=1
  ```

  ```bash
  sudo ln -sf /opt/antigravity/antigravity /usr/local/bin/antigravity
  ```

- **Gridcoin** (pinned `5.5.0.0`, official Flatpak bundle):

  ```bash
  curl -fsSLo /tmp/gridcoin.flatpak https://github.com/gridcoin-community/Gridcoin-Research/releases/download/5.5.0.0/gridcoin-5.5.0.0-x86_64.flatpak
  ```

  ```bash
  sudo flatpak install --system --bundle --assumeyes /tmp/gridcoin.flatpak
  ```

- **GpuTest** (pinned `0.7.0`):

  ```bash
  curl -fsSLo /tmp/gputest.zip https://ozone3d.net/gputest/dl/GpuTest_Linux_x64_0.7.0.zip
  ```

  ```bash
  sudo mkdir -p /opt/gputest && sudo unzip -o /tmp/gputest.zip -d /opt/gputest
  ```

- **Ledger Live** — download the AppImage from [ledger.com/ledger-live](https://www.ledger.com/ledger-live).
- **Trezor Suite** (pinned `26.4.2`) — download the AppImage from [trezor.io/trezor-suite](https://trezor.io/trezor-suite).
