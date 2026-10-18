#!/usr/bin/env bash
#
# Manual install script — Debian / Ubuntu
#
# Installs every package-manager-installable app the playbook manages:
# apt (incl. official third-party repos), direct .deb downloads, and Flatpak,
# one package per call, so a package that fails costs that package and nothing
# else. The ones that failed are listed at the end and the script exits 1.
# Apps needing a manual blob download are listed at the end and NOT installed.
#
# Mirrors setup/ansible/vars/Debian.yaml. Run as a normal user with sudo rights.

set -euo pipefail

SKIPPED=(
  "JetBrains Toolbox (tarball -> ~/.local/share/JetBrains/Toolbox)"
  "Antigravity (Linux tarball -> /opt/antigravity)"
  "Gridcoin (Flatpak bundle from GitHub releases)"
  "GpuTest (zip from ozone3d.net -> /opt/gputest)"
  "Ledger Live (AppImage)"
  "Trezor Suite (AppImage)"
  "VMware Workstation Player (Broadcom login required)"
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

refresh_apt() { sudo apt-get update; }

refresh_flatpak() { flatpak update --appstream --noninteractive flathub; }

# For an install that goes through no package manager index, a vendor script or a downloaded file.
no_refresh() { :; }

# --- Direct .deb downloads, read from the pinned values ---
# Not copies of the URLs. The versions and locations live in setup/pinned_values and are read through
# the one adapter the whole repository uses, so this script pulls exactly what the playbook pulls and
# a bumped pin cannot leave a stale address behind here.
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
  printf '         sudo apt-get install -y python3\n' >&2
  exit 1
fi

MINIKUBE_DEB="$(pinned_value minikube_url)"
TEAMVIEWER_DEB="$(pinned_value teamviewer_url)"
VERACRYPT_DEB="$(pinned_value veracrypt_url)"
APPIMAGELAUNCHER_DEB="$(pinned_value appimage_launcher_url)"
BALENA_ETCHER_DEB="$(pinned_value balena_etcher_url)"
OPENCODE_DESKTOP_DEB="$(pinned_value opencode_desktop_url)"

# apt packages from the default repos.
APT_PACKAGES=(
  git maven openssl filezilla putty keepassxc vlc rawtherapee speedtest-cli
  boinc-client lynis chkrootkit clamav hardinfo lm-sensors baobab gparted
  partitionmanager qemu-system-x86 libvirt-daemon-system libvirt-clients virt-manager virtinst
  bridge-utils virtiofsd zsh jq fzf ripgrep pipx golang-go rclone openrazer-meta
)

# apt packages that require a third-party repo (added below).
APT_REPO_PACKAGES=(google-chrome-stable brave-browser code sublime-text kubectl lens helm terraform gh syncthing tailscale claude-desktop)

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

# Downloads into a file only this user can write and installs it, in one chain so a failed download
# never installs whatever an earlier run, or another account, left at a fixed path in /tmp.
install_deb_url() {
  local url="$1" name="$2" deb
  log "Installing $name from $url"
  deb="$(mktemp --suffix=.deb)" \
    && curl -fsSLo "${deb}" "$url" \
    && sudo apt-get install -y "${deb}"
  local status=$?
  rm -f -- "${deb}"
  return "${status}"
}

log "Refreshing apt and installing prerequisites"
sudo apt-get update
for prerequisite in ca-certificates curl gnupg flatpak; do
  sudo apt-get install -y "${prerequisite}"
done
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
# HashiCorp, Tailscale and Docker publish one suite per Debian or Ubuntu release, and Tailscale and Docker publish
# ubuntu and debian paths only. A derivative takes its lineage and its parent's codename, never its own: Linux Mint
# 22 is wilma on Ubuntu noble, LMDE 6 is faye on Debian bookworm. The lineage is the ih_base rule and the codename
# the ih_apt_codename rule of setup/ansible/tasks/derive_os_facts.yaml.
# shellcheck source=/dev/null
UPSTREAM_DISTRO="$(. /etc/os-release && if [[ -n "${UBUNTU_CODENAME:-}" || "${ID_LIKE:-}" == *ubuntu* || "${ID:-}" == ubuntu ]]; then echo ubuntu; else echo debian; fi)"
# shellcheck source=/dev/null
UPSTREAM_CODENAME="$(. /etc/os-release && if [ "${UPSTREAM_DISTRO}" = ubuntu ]; then echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"; else echo "${DEBIAN_CODENAME:-${VERSION_CODENAME:-}}"; fi)"
if [ -z "${UPSTREAM_CODENAME}" ]; then
  printf 'ERROR: /etc/os-release names no %s codename, so the HashiCorp, Tailscale and Docker repositories cannot be added.\n' "${UPSTREAM_DISTRO}" >&2
  exit 1
fi
# Terraform (HashiCorp)
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
echo "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com ${UPSTREAM_CODENAME} main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
# GitHub CLI (key is already a binary keyring — no dearmor)
sudo curl -fsSLo /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
# Syncthing (key is already a binary keyring, no dearmor)
sudo curl -fsSLo /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable-v2" | sudo tee /etc/apt/sources.list.d/syncthing.list >/dev/null
# Tailscale (key is already a binary keyring, no dearmor).
sudo curl -fsSLo /etc/apt/keyrings/tailscale-archive-keyring.gpg "https://pkgs.tailscale.com/stable/${UPSTREAM_DISTRO}/${UPSTREAM_CODENAME}.noarmor.gpg"
echo "deb [signed-by=/etc/apt/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/${UPSTREAM_DISTRO} ${UPSTREAM_CODENAME} main" | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
# Claude Desktop (amd64 and arm64 only). The key is published already armoured, so it stays .asc with no dearmor,
# and its fingerprint is checked before the repository is trusted, exactly as debian_repos.yaml does.
sudo curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc https://downloads.claude.ai/claude-desktop/key.asc
if ! gpg --show-keys --with-colons /usr/share/keyrings/claude-desktop-archive-keyring.asc | grep -q 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE; then
  printf 'ERROR: the Claude Desktop signing key does not carry fingerprint 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE.\n' >&2
  exit 1
fi
echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" | sudo tee /etc/apt/sources.list.d/claude-desktop.list >/dev/null
# Docker CE, on the same distribution and codename as Tailscale above.
curl -fsSL "https://download.docker.com/linux/${UPSTREAM_DISTRO}/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${UPSTREAM_DISTRO} ${UPSTREAM_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

log "Refreshing apt after repo changes"
sudo apt-get update

log "Installing default-repo apt packages"
for package in "${APT_PACKAGES[@]}"; do
  install_one "${package}" refresh_apt sudo apt-get install -y "${package}"
done

log "Installing uv and uvx (no apt package on Debian trixie or Ubuntu 26.04)"
install_one uv no_refresh bash -c 'set -o pipefail; curl -fsSL https://astral.sh/uv/install.sh | sudo UV_UNMANAGED_INSTALL=/usr/local/bin sh'

log "Installing third-party-repo apt packages"
for package in "${APT_REPO_PACKAGES[@]}"; do
  install_one "${package}" refresh_apt sudo apt-get install -y "${package}"
done

log "Installing Docker CE"
for package in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do
  install_one "${package}" refresh_apt sudo apt-get install -y "${package}"
done

log "Installing direct .deb packages"
install_one minikube refresh_apt install_deb_url "$MINIKUBE_DEB" minikube
install_one teamviewer refresh_apt install_deb_url "$TEAMVIEWER_DEB" teamviewer
install_one veracrypt refresh_apt install_deb_url "$VERACRYPT_DEB" veracrypt
install_one appimagelauncher refresh_apt install_deb_url "$APPIMAGELAUNCHER_DEB" appimagelauncher
install_one balena-etcher refresh_apt install_deb_url "$BALENA_ETCHER_DEB" balena-etcher
install_one opencode refresh_apt install_deb_url "$OPENCODE_DESKTOP_DEB" opencode

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
sudo usermod -aG plugdev "${USER}" || printf '   Skipped: the plugdev group does not exist, so OpenRazer has no group to grant device access to.\n'

log "Done. The following were NOT installed (manual download required):"
for item in "${SKIPPED[@]}"; do
  printf '   - %s\n' "$item"
done
printf '\nSDK managers, AI tools and shell setup are documented in debian_ubuntu_manual_install.md — run those by hand.\n'

if [ "${#FAILED[@]}" -gt 0 ]; then
  printf '\n\033[1;31m==>\033[0m %d package(s) did NOT install, the package manager printed the reason above each one:\n' "${#FAILED[@]}" >&2
  printf '   - %s\n' "${FAILED[@]}" >&2
  exit 1
fi
