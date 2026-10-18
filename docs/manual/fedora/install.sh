#!/usr/bin/env bash
#
# Manual install script — Fedora
#
# Installs every package-manager-installable app the playbook manages:
# dnf (incl. official third-party repos), direct .rpm URLs, the --nodigest
# AppImageLauncher RPM, and Flatpak, one package per call, so a package that
# fails costs that package and nothing else. The ones that failed are listed at
# the end and the script exits 1. Manual blobs are listed at the end and NOT
# installed.
#
# Mirrors setup/ansible/vars/RedHat.yaml. Run as a normal user with sudo rights.

set -euo pipefail

SKIPPED=(
  "JetBrains Toolbox (tarball -> ~/.local/share/JetBrains/Toolbox)"
  "Antigravity (Linux tarball -> /opt/antigravity)"
  "Gridcoin (Flatpak bundle from GitHub releases)"
  "GpuTest (zip from ozone3d.net -> /opt/gputest)"
  "Ledger Live (AppImage)"
  "Trezor Suite (AppImage)"
)

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }

FAILED=()

# The retry rule every package manager in this repository follows, with the numbers
# setup/ansible/tasks/install_role_packages.yaml uses: one attempt with no package index refresh, then
# for a package that failed, wait, refresh that manager's package index, and try again, four attempts
# in all. e2e/tier1/package_retry_rule.sh runs install_one against fake managers to hold it to that.
INSTALL_ATTEMPTS=4
INSTALL_RETRY_DELAY=20

# Runs one install command for one package under that rule, with $2 as the refresh to run before each
# retry, and records the package instead of stopping when every attempt fails.
install_one() {
  local package="$1" refresh="$2" attempt
  shift 2
  for ((attempt = 1; attempt <= INSTALL_ATTEMPTS; attempt++)); do
    if [ "${attempt}" -gt 1 ]; then
      printf '   %s failed on attempt %d of %d, retrying in %d seconds\n' "${package}" "$((attempt - 1))" "${INSTALL_ATTEMPTS}" "${INSTALL_RETRY_DELAY}" >&2
      sleep "${INSTALL_RETRY_DELAY}"
      "${refresh}" || printf '   the refresh before retrying %s failed, retrying anyway\n' "${package}" >&2
    fi
    if "$@"; then
      return 0
    fi
  done
  FAILED+=("${package}")
}

refresh_dnf() { sudo dnf makecache --refresh; }

refresh_flatpak() { flatpak update --appstream --noninteractive flathub; }

# For an install that goes through no package manager index, a vendor script or a downloaded file.
no_refresh() { :; }

# Downloads into a file only this user can write and installs it, in one chain so a failed download
# never installs whatever an earlier run, or another account, left at a fixed path in /tmp.
install_appimagelauncher_rpm() {
  local rpm
  rpm="$(mktemp --suffix=.rpm)" \
    && curl -fsSLo "${rpm}" "$APPIMAGELAUNCHER_RPM" \
    && sudo rpm --install --upgrade --replacepkgs --nodigest "${rpm}"
  local status=$?
  rm -f -- "${rpm}"
  return "${status}"
}

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
OPENCODE_DESKTOP_RPM="$(pinned_value opencode_desktop_rpm_url)"
APPIMAGELAUNCHER_RPM="$(pinned_value appimage_launcher_rpm_url)"
OPENRAZER_REPO="$(pinned_value openrazer_fedora_repo_url)"

# dnf packages from default repos.
DNF_PACKAGES=(
  git maven openssl filezilla keepassxc vlc rawtherapee speedtest-cli
  boinc-client lynis chkrootkit clamav hardinfo2 lm_sensors baobab gparted
  kde-partitionmanager qemu-kvm libvirt virt-manager virt-install
  bridge-utils virtiofsd zsh helm gh jq fzf ripgrep uv pipx golang syncthing putty rclone
  qastools
)

# dnf packages that require a third-party repo (added below).
DNF_REPO_PACKAGES=(google-chrome-stable brave-browser code sublime-text kubectl lens terraform tailscale openrazer-meta)

# Flatpak application IDs (Flathub).
FLATPAK_APPS=(
  org.torproject.torbrowser-launcher com.getpostman.Postman
  io.dbeaver.DBeaverCommunity cc.arduino.IDE2 com.usebruno.Bruno
  com.discordapp.Discord com.slack.Slack org.telegram.desktop org.signal.Signal us.zoom.Zoom
  md.obsidian.Obsidian com.bitwarden.desktop org.onlyoffice.desktopeditors
  com.spotify.Client org.gimp.GIMP org.kde.krita fr.handbrake.ghb
  org.audacityteam.Audacity com.valvesoftware.Steam org.freecad.FreeCAD
  com.prusa3d.PrusaSlicer com.leinardi.gwe app.polychromatic.controller
  net.lutris.Lutris com.overwolf.curseforge io.podman_desktop.PodmanDesktop
)

log "Installing prerequisites"
for prerequisite in dnf5-plugins curl flatpak; do
  sudo dnf install -y "${prerequisite}"
done

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

# OpenRazer, from the openSUSE Build Service hardware:razer repo, written where fedora_repos.yaml writes it.
sudo curl -fsSLo /etc/yum.repos.d/hardware:razer.repo "$OPENRAZER_REPO"

log "Installing default-repo dnf packages"
for package in "${DNF_PACKAGES[@]}"; do
  install_one "${package}" refresh_dnf sudo dnf install -y "${package}"
done

log "Installing the kernel headers the OpenRazer driver builds against"
for package in kernel-devel kernel-headers; do
  install_one "${package}" refresh_dnf sudo dnf install -y "${package}"
done

log "Installing third-party-repo dnf packages"
for package in "${DNF_REPO_PACKAGES[@]}"; do
  install_one "${package}" refresh_dnf sudo dnf install -y "${package}"
done

log "Installing Docker CE"
for package in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
  install_one "${package}" refresh_dnf sudo dnf install -y "${package}"
done

log "Installing direct .rpm packages"
for rpm_url in "$MINIKUBE_RPM" "$TEAMVIEWER_RPM" "$VERACRYPT_RPM" "$BALENA_ETCHER_RPM" "$OPENCODE_DESKTOP_RPM"; do
  install_one "${rpm_url##*/}" refresh_dnf sudo dnf install -y "${rpm_url}"
done

log "Installing AppImageLauncher (rpm --nodigest bypass)"
install_one appimagelauncher no_refresh install_appimagelauncher_rpm

log "Installing Flatpak applications"
for app in "${FLATPAK_APPS[@]}"; do
  install_one "${app}" refresh_flatpak flatpak install -y flathub "${app}"
done

log "Enabling the Syncthing user service"
systemctl --user enable --now syncthing.service || printf '   Skipped: no user D-Bus session. Run it yourself after logging in.\n'

log "Enabling the tailscaled system service"
sudo systemctl enable --now tailscaled || printf '   Skipped: tailscaled.service could not be enabled, so tailscale most likely did not install. systemctl printed why above.\n'

log "Enabling and starting the Docker system service"
sudo systemctl enable --now docker || printf '   Skipped: docker.service could not be enabled, so docker-ce most likely did not install. systemctl printed why above.\n'

log "Adding ${USER} to the docker group, which takes effect only after logging out and back in, a new terminal window is not enough"
sudo usermod -aG docker "${USER}" || printf '   Skipped: the docker group does not exist, so docker-ce did not install.\n'

log "Adding ${USER} to the plugdev group OpenRazer grants device access to, which takes effect at the next login"
sudo usermod -aG plugdev "${USER}" || printf '   Skipped: the plugdev group does not exist, so openrazer-meta did not install.\n'

log "Done. The following were NOT installed (manual download required):"
for item in "${SKIPPED[@]}"; do
  printf '   - %s\n' "$item"
done
printf '\nSDK managers, AI tools and shell setup are documented in fedora_manual_install.md — run those by hand.\n'

if [ "${#FAILED[@]}" -gt 0 ]; then
  printf '\n\033[1;31m==>\033[0m %d package(s) did NOT install, the package manager printed the reason above each one:\n' "${#FAILED[@]}" >&2
  printf '   - %s\n' "${FAILED[@]}" >&2
  exit 1
fi
