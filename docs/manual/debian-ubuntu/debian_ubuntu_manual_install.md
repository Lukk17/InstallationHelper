# Manual install — Debian / Ubuntu

Install commands for every app the playbook manages on Debian/Ubuntu. To install the whole package-manager set at once, run [`install.sh`](install.sh) instead. `e2e/tier1/manual_linux_install.sh` fails when this page or the script disagrees with the mapping file.

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

**Ubuntu or Debian repository path.** HashiCorp, Tailscale and Docker publish one suite per Debian or Ubuntu release, and Tailscale and Docker publish `ubuntu` and `debian` paths only. A derivative needs its lineage and its parent's codename, never its own name or codename: Linux Mint 22 is `wilma` on Ubuntu `noble`, and LMDE 6 is `faye` on Debian `bookworm`. The playbook decides both the same way, `ih_base` and `ih_apt_codename` in [setup/ansible/tasks/derive_os_facts.yaml](../../../setup/ansible/tasks/derive_os_facts.yaml). Set the lineage first:

```bash
UPSTREAM_DISTRO="$(. /etc/os-release && if [[ -n "${UBUNTU_CODENAME:-}" || "${ID_LIKE:-}" == *ubuntu* || "${ID:-}" == ubuntu ]]; then echo ubuntu; else echo debian; fi)"
```

Then the codename of that lineage:

```bash
UPSTREAM_CODENAME="$(. /etc/os-release && if [ "${UPSTREAM_DISTRO}" = ubuntu ]; then echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"; else echo "${DEBIAN_CODENAME:-${VERSION_CODENAME:-}}"; fi)"
```

Check both before going on. It prints `ubuntu noble` on Ubuntu 24.04 and on Linux Mint 22, and `debian trixie` on Debian 13. An empty codename means this machine does not name one, so stop here:

```bash
echo "${UPSTREAM_DISTRO} ${UPSTREAM_CODENAME}"
```

Devuan is not supported for the Terraform, Tailscale and Docker CE repositories, by the owner's decision of 2026-10-18. Its `/etc/os-release` names only Devuan's own release, `VERSION_CODENAME="daedalus"` on Devuan 5, and no Debian codename, so the command above prints `debian daedalus`, and download.docker.com, pkgs.tailscale.com and apt.releases.hashicorp.com all answer 404 for `daedalus`. On Devuan, skip those three repositories and the packages that come from them. The record is entry 10.114 of [docs/regression_ledger.md](../../regression_ledger.md).

**Terraform:**

```bash
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
```

```bash
echo "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com ${UPSTREAM_CODENAME} main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
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

**Tailscale** (key is already a binary keyring, no `gpg --dearmor` step). The keyring and the repo both live under the path set above:

```bash
sudo curl -fsSLo /etc/apt/keyrings/tailscale-archive-keyring.gpg "https://pkgs.tailscale.com/stable/${UPSTREAM_DISTRO}/${UPSTREAM_CODENAME}.noarmor.gpg"
```

```bash
echo "deb [signed-by=/etc/apt/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/${UPSTREAM_DISTRO} ${UPSTREAM_CODENAME} main" | sudo tee /etc/apt/sources.list.d/tailscale.list
```

Claude Desktop: Anthropic publishes the Linux build only through its own apt repository, for amd64 and arm64. These are the steps the playbook runs in [setup/ansible/roles/software_installer/tasks/debian_repos.yaml](../../../setup/ansible/roles/software_installer/tasks/debian_repos.yaml). The key is published already armoured, so it is kept as `.asc` and not dearmoured:

```bash
sudo curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc https://downloads.claude.ai/claude-desktop/key.asc
```

Confirm it is Anthropic's key. The command must print a line containing the fingerprint `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE`. If it prints nothing, the download returned the wrong content and apt would later fail with `NO_PUBKEY BAA929FF1A7ECACE`:

```bash
gpg --show-keys --with-colons /usr/share/keyrings/claude-desktop-archive-keyring.asc | grep 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
```

```bash
echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" | sudo tee /etc/apt/sources.list.d/claude-desktop.list
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
| pipx | `sudo apt-get install -y pipx` |
| Go | `sudo apt-get install -y golang-go` |
| FileZilla | `sudo apt-get install -y filezilla` |
| PuTTY | `sudo apt-get install -y putty` |
| rclone | `sudo apt-get install -y rclone` |
| QasTools | `for package in qasmixer qashctl qasconfig; do sudo apt-get install -y "${package}" \|\| echo "FAILED: ${package}"; done` |
| Minikube | `curl -fsSLo /tmp/minikube.deb https://github.com/kubernetes/minikube/releases/download/v1.38.1/minikube_1.38.1-0_amd64.deb && sudo apt-get install -y /tmp/minikube.deb` |
| k3d | `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh \| bash` |
| uv | `curl -fsSL https://astral.sh/uv/install.sh \| sudo UV_UNMANAGED_INSTALL=/usr/local/bin sh` *(no apt package on Debian trixie or Ubuntu 26.04)* |

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
| Zoom | `flatpak install -y flathub us.zoom.Zoom` |

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
| Lutris | `flatpak install -y flathub net.lutris.Lutris` |
| CurseForge | `flatpak install -y flathub com.overwolf.curseforge` |

> GOG Galaxy, Epic and EA app have no official Linux client.

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
| OpenRazer | `sudo apt-get install -y openrazer-meta` |

OpenRazer is the driver and daemon Polychromatic talks to, in Debian proper since bookworm and in Ubuntu universe. Add yourself to the `plugdev` group its udev rules grant device access to, log out and back in, and reboot so the DKMS module loads. On a Secure Boot machine the unsigned module is refused unless you sign it or turn Secure Boot off:

```bash
sudo usermod -aG plugdev "${USER}"
```

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
| QEMU/KVM + virt-manager | `for package in qemu-system-x86 libvirt-daemon-system libvirt-clients virt-manager virtinst bridge-utils virtiofsd; do sudo apt-get install -y "${package}" \|\| echo "FAILED: ${package}"; done` |

**Docker CE** (official repo). It uses `UPSTREAM_DISTRO` and `UPSTREAM_CODENAME`. In a new terminal, set them again first, as in the Ubuntu or Debian repository path step of [Repository setup](#repository-setup):

```bash
curl -fsSL "https://download.docker.com/linux/${UPSTREAM_DISTRO}/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
```

```bash
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${UPSTREAM_DISTRO} ${UPSTREAM_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list
```

```bash
sudo apt-get update
```

```bash
for package in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do sudo apt-get install -y "${package}" || echo "FAILED: ${package}"; done
```

Start the Docker daemon now and at every boot, which the package does not do on every distribution:

```bash
sudo systemctl enable --now docker
```

Add yourself to the `docker` group so `docker` runs without `sudo`. It takes effect only after you log out and back in, or reboot. A new terminal window is not enough, because it keeps the groups of the session you are already in:

```bash
sudo usermod -aG docker "${USER}"
```

**Podman Desktop**, a front end for the Docker engine above:

```bash
flatpak install -y flathub io.podman_desktop.PodmanDesktop
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

Dart comes with the Flutter SDK FVM installs. The playbook installs no separate Dart SDK on Linux, because `install_dart` is a Windows-only toggle, see `setup/ansible/group_vars/all.yaml`.

## AI tools

Need Node from NVM above first.

| Tool | Install command |
|---|---|
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` |
| Claude Desktop | `sudo apt-get install -y claude-desktop`, after the Claude Desktop repository in [Repository setup](#repository-setup) |
| OpenCode | `npm install -g @opencode/cli`, after `npm uninstall -g opencode-ai` if version 1 is installed, because both claim the `opencode` command |
| OpenCode desktop | `curl -fsSLo /tmp/opencode-desktop.deb https://opencode.ai/files/bin/2.0.29/opencode-desktop-linux-amd64.deb && sudo apt-get install -y /tmp/opencode-desktop.deb`, version 2. Version 1 of the desktop app, the Flathub `ai.opencode.opencode` the playbook installed before 2026-10-15, refuses to start once version 2 has created its database, so remove it with `flatpak uninstall ai.opencode.opencode` |
| Kilo Code CLI | `npm install -g @kilocode/cli`, which provides the `kilo` command |
| OpenSpec | `npm install -g @fission-ai/openspec` |
| LM Studio | `curl -fsSL https://lmstudio.ai/install.sh \| bash` |

OpenCode version 1 instead of version 2. Version 2 is the default. The wizard switches when `Switch OpenCode from v2 to v1` is ticked on its checklist, or with `./setup.sh --enable opencode_use_v1`: it removes the version 2 command line tool and desktop app, installs version 1, and moves a data folder holding version 2 data to `~/.local/share/opencode.v2-backup-<date>-<time>`, because version 1 refuses to start on a version 2 database. Switching back moves version 1 data aside the same way and brings the newest version 2 backup back. Nothing is deleted. By hand, the same steps, first removing version 2:

```bash
sudo apt-get remove -y opencode
```

```bash
npm uninstall -g @opencode/cli
```

```bash
npm install -g opencode-ai
```

```bash
flatpak install -y flathub ai.opencode.opencode
```

```bash
mv ~/.local/share/opencode ~/.local/share/opencode.v2-backup-"$(date +%Y%m%d-%H%M%S)"
```

The last command only when `~/.local/share/opencode` exists. Version 1 of the desktop app is the Flathub application, 1.18.8 on 2026-10-15.

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

- **JetBrains Toolbox**: Toolbox 3.x has no install step of its own: unpack JetBrains' tarball into Toolbox's data directory, then start it from there. It adds its own menu entry on that first start.

  ```bash
  toolbox_tar="$(mktemp --suffix=.tar.gz)" && curl -fsSLo "$toolbox_tar" "https://data.services.jetbrains.com/products/download?platform=linux&code=TBA" && mkdir -p ~/.local/share/JetBrains/Toolbox && tar -xzf "$toolbox_tar" -C ~/.local/share/JetBrains/Toolbox --strip-components=1 && rm -f "$toolbox_tar"
  ```

  ```bash
  ~/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox &
  ```

  Toolbox puts its IDE launchers (`idea`, `pycharm` and the rest) on PATH through a line in `~/.profile`, which zsh never reads. Add the directory to `~/.config/environment.d/990-dev.conf` instead, as described in [setup/configuration.md](../../../setup/configuration.md#shell-and-environment-layout):

  ```bash
  mkdir -p ~/.config/environment.d && printf 'PATH="${PATH}:%s"\n' "$HOME/.local/share/JetBrains/Toolbox/scripts" >> ~/.config/environment.d/990-dev.conf
  ```
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
- **VMware Workstation Player** — downloads now require a Broadcom Support Portal login. Use VirtualBox or QEMU/KVM instead.
