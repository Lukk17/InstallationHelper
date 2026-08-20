#!/usr/bin/env bash
#
# Manual install script — Fedora
#
# Installs every package-manager-installable app the playbook manages:
# dnf (incl. official third-party repos), direct .rpm URLs, the --nodigest
# AppImageLauncher RPM, and Flatpak. Manual blobs are listed at the end and
# NOT installed.
#
# Mirrors setup/ansible/vars/RedHat.yaml. Run as a normal user with sudo rights.

set -euo pipefail

SKIPPED=(
  "Antigravity (Linux tarball -> /opt/antigravity)"
  "Gridcoin (Flatpak bundle from GitHub releases)"
  "GpuTest (zip from ozone3d.net -> /opt/gputest)"
  "Ledger Live (AppImage)"
  "Trezor Suite (AppImage)"
)

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }

# Direct .rpm URLs, read from the pinned values rather than copied out of them. The versions and
# locations live in setup/pinned_values and are read through the one adapter the whole repository
# uses, so this script pulls exactly what the playbook pulls and a bumped pin cannot leave a stale
# address behind here.
ADAPTER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)/setup/pinned_values/pinned_values.sh"
if [ ! -f "$ADAPTER" ]; then
  printf 'ERROR: the pinned download locations are read from the repository, and\n' >&2
  printf '       %s\n' "$ADAPTER" >&2
  printf '       is not there. Run this from a clone rather than as a single downloaded file:\n' >&2
  printf '         git clone https://github.com/Lukk17/InstallationHelper.git\n' >&2
  exit 1
fi
# shellcheck source=../../../setup/pinned_values/pinned_values.sh
source "$ADAPTER"
if ! pinned_values_load; then
  printf 'ERROR: reading the pinned download locations needs Python 3.11 or newer. Install it with\n' >&2
  printf '         sudo dnf install -y python3\n' >&2
  exit 1
fi

MINIKUBE_RPM="$(pinned_value minikube_rpm_url)"
TEAMVIEWER_RPM="$(pinned_value teamviewer_rpm_url)"
VERACRYPT_RPM="$(pinned_value veracrypt_rpm_url)"
BALENA_ETCHER_RPM="$(pinned_value balena_etcher_rpm_url)"
APPIMAGELAUNCHER_RPM="$(pinned_value appimage_launcher_rpm_url)"

# dnf packages from default repos.
DNF_PACKAGES=(
  git maven openssl filezilla keepassxc vlc rawtherapee speedtest-cli
  boinc-client lynis chkrootkit clamav hardinfo2 lm_sensors baobab gparted
  kde-partitionmanager grubby qemu-kvm libvirt virt-manager virt-install
  bridge-utils virtiofsd zsh dart helm gh jq fzf ripgrep syncthing
)

# dnf packages that require a third-party repo (added below).
DNF_REPO_PACKAGES=(google-chrome-stable brave-browser code sublime-text kubectl lens terraform tailscale)

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

log "Installing prerequisites"
sudo dnf install -y dnf-plugins-core curl flatpak

log "Enabling Flathub"
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

log "Adding third-party dnf repositories"
sudo tee /etc/yum.repos.d/google-chrome.repo >/dev/null <<'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF

sudo tee /etc/yum.repos.d/brave-browser.repo >/dev/null <<'EOF'
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/x86_64/
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
EOF

sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<'EOF'
[vscode]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

sudo rpm --import https://download.sublimetext.com/sublimehq-rpm-pub.gpg
sudo tee /etc/yum.repos.d/sublime-text.repo >/dev/null <<'EOF'
[sublime-text]
name=Sublime Text
baseurl=https://download.sublimetext.com/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://download.sublimetext.com/sublimehq-rpm-pub.gpg
EOF

sudo tee /etc/yum.repos.d/kubernetes.repo >/dev/null <<'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/repodata/repomd.xml.key
EOF

sudo rpm --import https://downloads.k8slens.dev/keys/gpg
sudo tee /etc/yum.repos.d/lens.repo >/dev/null <<'EOF'
[lens]
name=Lens Desktop
baseurl=https://downloads.k8slens.dev/rpm/packages
enabled=1
gpgcheck=1
gpgkey=https://downloads.k8slens.dev/keys/gpg
EOF

# HashiCorp official repo (Terraform).
sudo dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo

# Docker CE official repo.
sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo

# Tailscale official repo.
sudo dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo

log "Installing default-repo dnf packages"
sudo dnf install -y "${DNF_PACKAGES[@]}"

log "Installing third-party-repo dnf packages"
sudo dnf install -y "${DNF_REPO_PACKAGES[@]}"

log "Installing Docker CE"
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log "Installing direct .rpm packages"
sudo dnf install -y "$MINIKUBE_RPM" "$TEAMVIEWER_RPM" "$VERACRYPT_RPM" "$BALENA_ETCHER_RPM"

log "Installing AppImageLauncher (rpm --nodigest bypass)"
curl -fsSLo /tmp/appimagelauncher.rpm "$APPIMAGELAUNCHER_RPM"
sudo rpm --install --upgrade --replacepkgs --nodigest /tmp/appimagelauncher.rpm

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
printf '\nSDK managers, AI tools and shell setup are documented in fedora_manual_install.md — run those by hand.\n'
