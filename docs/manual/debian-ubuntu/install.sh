#!/usr/bin/env bash
#
# Manual install script — Debian / Ubuntu
#
# Installs every package-manager-installable app the playbook manages:
# apt (incl. official third-party repos), direct .deb downloads, and Flatpak.
# Apps needing a manual blob download are listed at the end and NOT installed.
#
# Mirrors setup/ansible/vars/Debian.yaml. Run as a normal user with sudo rights.

set -euo pipefail

SKIPPED=(
  "JetBrains Toolbox (tarball — jetbrains.com/toolbox-app)"
  "Antigravity (Linux tarball -> /opt/antigravity)"
  "Gridcoin (Flatpak bundle from GitHub releases)"
  "GpuTest (zip from ozone3d.net -> /opt/gputest)"
  "Ledger Live (AppImage)"
  "Trezor Suite (AppImage)"
  "Claude Desktop (no Linux build published)"
  "VMware Workstation Player (Broadcom login required)"
)

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }

# --- Direct .deb downloads, pinned to versions.yaml ---
MINIKUBE_DEB="https://github.com/kubernetes/minikube/releases/download/v1.38.1/minikube_1.38.1-0_amd64.deb"
TEAMVIEWER_DEB="https://download.teamviewer.com/download/linux/teamviewer_amd64.deb"
VERACRYPT_DEB="https://launchpad.net/veracrypt/trunk/1.26.24/+download/veracrypt-1.26.24-Ubuntu-24.04-amd64.deb"
APPIMAGELAUNCHER_DEB="https://github.com/TheAssassin/AppImageLauncher/releases/download/v2.2.0/appimagelauncher_2.2.0-travis995.0f91801.bionic_amd64.deb"
BALENA_ETCHER_DEB="https://github.com/balena-io/etcher/releases/download/v2.1.6/balena-etcher_2.1.6_amd64.deb"

# apt packages from the default repos.
APT_PACKAGES=(
  git maven openssl filezilla putty keepassxc vlc rawtherapee speedtest-cli
  boinc-client lynis chkrootkit clamav hardinfo lm-sensors baobab gparted
  partitionmanager qemu-kvm libvirt-daemon-system virt-manager virtinst
  bridge-utils virtiofsd zsh dart jq fzf ripgrep
)

# apt packages that require a third-party repo (added below).
APT_REPO_PACKAGES=(google-chrome-stable brave-browser code sublime-text kubectl lens helm terraform gh syncthing tailscale)

# Flatpak application IDs (Flathub).
FLATPAK_APPS=(
  org.torproject.torbrowser-launcher com.getpostman.Postman
  io.dbeaver.DBeaverCommunity cc.arduino.IDE2 com.usebruno.Bruno
  com.discordapp.Discord com.slack.Slack org.telegram.desktop org.signal.Signal
  md.obsidian.Obsidian com.bitwarden.desktop org.onlyoffice.desktopeditors
  com.spotify.Client org.gimp.GIMP org.kde.krita fr.handbrake.ghb
  org.audacityteam.Audacity com.valvesoftware.Steam org.freecad.FreeCAD
  com.prusa3d.PrusaSlicer com.leinardi.gwe app.polychromatic.controller
)

install_deb_url() {
  local url="$1" name="$2"
  log "Installing $name from $url"
  curl -fsSLo "/tmp/${name}.deb" "$url"
  sudo apt-get install -y "/tmp/${name}.deb"
}

log "Refreshing apt and installing prerequisites"
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg flatpak
sudo install -m 0755 -d /etc/apt/keyrings

log "Enabling Flathub"
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

log "Adding third-party apt repositories"
# Google Chrome
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
# Brave
sudo curl -fsSLo /etc/apt/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser.list >/dev/null
# VS Code
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /etc/apt/keyrings/packages.microsoft.gpg
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
# Sublime Text
curl -fsSL https://download.sublimetext.com/sublimehq-pub.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/sublimehq-pub.gpg
echo "deb [signed-by=/etc/apt/keyrings/sublimehq-pub.gpg] https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list >/dev/null
# kubectl (Kubernetes v1.36)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
# Lens
curl -fsSL https://downloads.k8slens.dev/keys/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/lens.gpg
echo "deb [signed-by=/etc/apt/keyrings/lens.gpg] https://downloads.k8slens.dev/apt/debian stable main" | sudo tee /etc/apt/sources.list.d/lens.list >/dev/null
# Helm
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | sudo gpg --dearmor -o /etc/apt/keyrings/helm.gpg
echo "deb [signed-by=/etc/apt/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm.list >/dev/null
# Terraform (HashiCorp)
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
echo "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
# GitHub CLI (key is already a binary keyring — no dearmor)
sudo curl -fsSLo /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
# Syncthing (key is already a binary keyring, no dearmor)
sudo curl -fsSLo /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable-v2" | sudo tee /etc/apt/sources.list.d/syncthing.list >/dev/null
# Tailscale (key is already a binary keyring, no dearmor). Keyring and repo paths are per-distro and per-codename.
# Upstream publishes ubuntu and debian paths only, so a derivative's own name is normalised away.
if [ "$(lsb_release -is)" = "Ubuntu" ]; then TAILSCALE_DISTRO=ubuntu; else TAILSCALE_DISTRO=debian; fi
sudo curl -fsSLo /etc/apt/keyrings/tailscale-archive-keyring.gpg "https://pkgs.tailscale.com/stable/${TAILSCALE_DISTRO}/$(lsb_release -cs).noarmor.gpg"
echo "deb [signed-by=/etc/apt/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/${TAILSCALE_DISTRO} $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null

log "Refreshing apt after repo changes"
sudo apt-get update

log "Installing default-repo apt packages"
sudo apt-get install -y "${APT_PACKAGES[@]}"

log "Installing third-party-repo apt packages"
sudo apt-get install -y "${APT_REPO_PACKAGES[@]}"

log "Installing direct .deb packages"
install_deb_url "$MINIKUBE_DEB" minikube
install_deb_url "$TEAMVIEWER_DEB" teamviewer
install_deb_url "$VERACRYPT_DEB" veracrypt
install_deb_url "$APPIMAGELAUNCHER_DEB" appimagelauncher
install_deb_url "$BALENA_ETCHER_DEB" balena-etcher

log "Installing Flatpak applications"
flatpak install -y flathub "${FLATPAK_APPS[@]}"

log "Enabling the Syncthing user service"
systemctl --user enable --now syncthing.service || printf '   Skipped: no user D-Bus session. Run it yourself after logging in.\n'

log "Enabling the tailscaled system service"
sudo systemctl enable --now tailscaled

log "Done. The following were NOT installed (manual download required):"
for item in "${SKIPPED[@]}"; do
  printf '   - %s\n' "$item"
done
printf '\nSDK managers, AI tools and shell setup are documented in debian_ubuntu_manual_install.md — run those by hand.\n'
