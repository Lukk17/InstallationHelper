# Manual install — Debian / Ubuntu

Install commands for every app the playbook manages on Debian/Ubuntu. To install the whole package-manager set at once, run [`install.sh`](install.sh) instead.

> Tested against Ubuntu 24.04. All `apt` commands need `sudo`. Direct `.deb` versions are pinned in [`pinned_values.toml`](../../../setup/pinned_values/pinned_values.toml).

## Prerequisites

Create the keyring dir used by the third-party repos:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
```

Enable Flathub (needed for every `flatpak` app below):

```bash
sudo apt-get install -y flatpak
```

```bash
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
```

## Repository setup

Run the block for each repo-based app **before** its `apt-get install`. (`install.sh` does this for you.)

**Google Chrome:**

```bash
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg
```

```bash
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
```

**Brave:**

```bash
sudo curl -fsSLo /etc/apt/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
```

```bash
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser.list
```

**VS Code:**

```bash
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /etc/apt/keyrings/packages.microsoft.gpg
```

```bash
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
```

**Sublime Text:**

```bash
curl -fsSL https://download.sublimetext.com/sublimehq-pub.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/sublimehq-pub.gpg
```

```bash
echo "deb [signed-by=/etc/apt/keyrings/sublimehq-pub.gpg] https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list
```

**kubectl** (Kubernetes minor stream `v1.36`):

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

```bash
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

**Lens Desktop:**

```bash
curl -fsSL https://downloads.k8slens.dev/keys/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/lens.gpg
```

```bash
echo "deb [signed-by=/etc/apt/keyrings/lens.gpg] https://downloads.k8slens.dev/apt/debian stable main" | sudo tee /etc/apt/sources.list.d/lens.list
```

**Helm:**

```bash
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | sudo gpg --dearmor -o /etc/apt/keyrings/helm.gpg
```

```bash
echo "deb [signed-by=/etc/apt/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm.list
```

**Terraform:**

```bash
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
```

```bash
echo "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
```

**GitHub CLI** (key is already a binary keyring — no `gpg --dearmor` step):

```bash
sudo curl -fsSLo /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg
```

```bash
echo "deb [signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list
```

**Syncthing** (key is already a binary keyring, no `gpg --dearmor` step). One suite serves every Debian derivative, and `stable-v2` is the monthly stable channel of the 2.x line:

```bash
sudo curl -fsSLo /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
```

```bash
echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable-v2" | sudo tee /etc/apt/sources.list.d/syncthing.list
```

**Tailscale** (key is already a binary keyring, no `gpg --dearmor` step). The keyring and the repo both live under a per-distribution, per-codename path. Upstream publishes `ubuntu` and `debian` paths only, so set the distribution segment first and a derivative's own name cannot leak into the URL:

```bash
if [ "$(lsb_release -is)" = "Ubuntu" ]; then TAILSCALE_DISTRO=ubuntu; else TAILSCALE_DISTRO=debian; fi
```

```bash
sudo curl -fsSLo /etc/apt/keyrings/tailscale-archive-keyring.gpg "https://pkgs.tailscale.com/stable/${TAILSCALE_DISTRO}/$(lsb_release -cs).noarmor.gpg"
```

```bash
echo "deb [signed-by=/etc/apt/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/${TAILSCALE_DISTRO} $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/tailscale.list
```

After adding any repo, refresh the cache once:

```bash
sudo apt-get update
```

## Browsers

| App | Install command |
|---|---|
| Google Chrome | `sudo apt-get install -y google-chrome-stable` *(repo above)* |
| Brave | `sudo apt-get install -y brave-browser` *(repo above)* |
| Tor Browser | `flatpak install -y flathub org.torproject.torbrowser-launcher` |

## Dev tools

| App | Install command |
|---|---|
| Git | `sudo apt-get install -y git` |
| Maven | `sudo apt-get install -y maven` |
| Postman | `flatpak install -y flathub com.getpostman.Postman` |
| OpenSSL | `sudo apt-get install -y openssl` |
| DBeaver CE | `flatpak install -y flathub io.dbeaver.DBeaverCommunity` |
| kubectl | `sudo apt-get install -y kubectl` *(repo above)* |
| Lens | `sudo apt-get install -y lens` *(repo above)* |
| Helm | `sudo apt-get install -y helm` *(repo above)* |
| Terraform | `sudo apt-get install -y terraform` *(repo above)* |
| GitHub CLI | `sudo apt-get install -y gh` *(repo above)* |
| jq | `sudo apt-get install -y jq` |
| fzf | `sudo apt-get install -y fzf` |
| ripgrep | `sudo apt-get install -y ripgrep` |
| FileZilla | `sudo apt-get install -y filezilla` |
| PuTTY | `sudo apt-get install -y putty` |
| Minikube | `curl -fsSLo /tmp/minikube.deb https://github.com/kubernetes/minikube/releases/download/v1.38.1/minikube_1.38.1-0_amd64.deb && sudo apt-get install -y /tmp/minikube.deb` |
| k3d | `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh \| bash` |

> Gradle is installed via SDKMAN, not apt — see [Developer toolchain](#developer-toolchain-sdk--runtimes).

## IDEs and editors

| App | Install command |
|---|---|
| VS Code | `sudo apt-get install -y code` *(repo above)* |
| Sublime Text | `sudo apt-get install -y sublime-text` *(repo above)* |
| Arduino IDE 2.x | `flatpak install -y flathub cc.arduino.IDE2` |
| Bruno | `flatpak install -y flathub com.usebruno.Bruno` |

> JetBrains Toolbox and Antigravity need a manual install — see [Manual install required](#manual-install-required).

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
| KeePassXC | `sudo apt-get install -y keepassxc` |
| OnlyOffice | `flatpak install -y flathub org.onlyoffice.desktopeditors` |

## Media and design

| App | Install command |
|---|---|
| VLC | `sudo apt-get install -y vlc` |
| Spotify | `flatpak install -y flathub com.spotify.Client` |
| GIMP | `flatpak install -y flathub org.gimp.GIMP` |
| Krita | `flatpak install -y flathub org.kde.krita` |
| HandBrake | `flatpak install -y flathub fr.handbrake.ghb` |
| Audacity | `flatpak install -y flathub org.audacityteam.Audacity` |
| RawTherapee | `sudo apt-get install -y rawtherapee` |

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
| Speedtest CLI | `sudo apt-get install -y speedtest-cli` |
| Syncthing | `sudo apt-get install -y syncthing` (needs the Syncthing repo added above) |
| Tailscale | `sudo apt-get install -y tailscale` (needs the Tailscale repo added above) |
| GParted | `sudo apt-get install -y gparted` |
| KDE Partition Manager | `sudo apt-get install -y partitionmanager` |
| TeamViewer | `curl -fsSLo /tmp/teamviewer.deb https://download.teamviewer.com/download/linux/teamviewer_amd64.deb && sudo apt-get install -y /tmp/teamviewer.deb` |
| VeraCrypt | `curl -fsSLo /tmp/veracrypt.deb https://launchpad.net/veracrypt/trunk/1.26.24/+download/veracrypt-1.26.24-Ubuntu-24.04-amd64.deb && sudo apt-get install -y /tmp/veracrypt.deb` |
| AppImageLauncher | `curl -fsSLo /tmp/appimagelauncher.deb https://github.com/TheAssassin/AppImageLauncher/releases/download/v2.2.0/appimagelauncher_2.2.0-travis995.0f91801.bionic_amd64.deb && sudo apt-get install -y /tmp/appimagelauncher.deb` |
| Balena Etcher | `curl -fsSLo /tmp/balena-etcher.deb https://github.com/balena-io/etcher/releases/download/v2.1.6/balena-etcher_2.1.6_amd64.deb && sudo apt-get install -y /tmp/balena-etcher.deb` |

The Syncthing package ships a systemd user unit but leaves it disabled. Enable it so Syncthing starts at login as the owner of the synced files:

```bash
systemctl --user enable --now syncthing.service
```

The Tailscale package ships a systemd system unit and the Debian and Ubuntu packages already enable it in their post-install. Running the command again is harmless and confirms the daemon is up. It runs in system scope, not user scope like Syncthing, because it owns a network interface and routing table entries:

```bash
sudo systemctl enable --now tailscaled
```

Joining a tailnet stays manual: run `sudo tailscale up` once by hand and authenticate in the browser it opens.

## Hardware monitoring

| App | Install command |
|---|---|
| HardInfo | `sudo apt-get install -y hardinfo` |
| lm-sensors | `sudo apt-get install -y lm-sensors` |
| GreenWithEnvy | `flatpak install -y flathub com.leinardi.gwe` |
| Baobab | `sudo apt-get install -y baobab` |
| Polychromatic | `flatpak install -y flathub app.polychromatic.controller` |

## Security

| App | Install command |
|---|---|
| Lynis | `sudo apt-get install -y lynis` |
| chkrootkit | `sudo apt-get install -y chkrootkit` |
| ClamAV | `sudo apt-get install -y clamav` |

## Crypto / volunteer

| App | Install command |
|---|---|
| BOINC | `sudo apt-get install -y boinc-client` |

> Gridcoin, Ledger Live and Trezor Suite need a manual install — see below.

## Virtualization

| App | Install command |
|---|---|
| QEMU/KVM + virt-manager | `sudo apt-get install -y qemu-kvm libvirt-daemon-system virt-manager virtinst bridge-utils virtiofsd` |

**Docker CE** (official repo):

```bash
curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
```

```bash
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list
```

```bash
sudo apt-get update
```

```bash
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

## Developer toolchain (SDK / runtimes)

Run these **as your normal user** (no sudo), in order — each writes to your shell rc and must be sourced before the next.

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
sudo apt-get install -y dart
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
sudo apt-get install -y zsh
```

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

```bash
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
```

## Manual install required

These are **not** in `install.sh` — no package-manager path exists. Install by hand:

- **JetBrains Toolbox** — download the tarball from [jetbrains.com/toolbox-app](https://www.jetbrains.com/toolbox-app/), extract, and run the `jetbrains-toolbox` binary.
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
- Trezor Suite: download the AppImage from [trezor.io/trezor-suite](https://trezor.io/trezor-suite). The playbook installs the udev rules only, so the application itself is a manual download and carries no pinned version.
- **Claude Desktop** — Anthropic no longer publishes a Linux build (macOS/Windows only as of 2026-05). Skip on Linux until upstream restores it.
- **VMware Workstation Player** — downloads now require a Broadcom Support Portal login. Use VirtualBox or QEMU/KVM instead.
