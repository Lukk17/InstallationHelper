#!/usr/bin/env bash
#
# Manual install script — Arch Linux
#
# Installs every app reachable via pacman (official repos) + Flatpak, one package
# per call, so a package that fails costs that package and nothing else. The
# ones that failed are listed at the end and the script exits 1.
# AUR packages are NOT installed (they need an AUR helper) — they're listed at
# the end with the yay command. Manual blobs are listed too.
#
# Mirrors setup/ansible/vars/Archlinux.yaml. Run as a normal user with sudo rights.

set -euo pipefail

AUR_PACKAGES="google-chrome brave-bin lens-bin jetbrains-toolbox visual-studio-code-bin sublime-text-4 antigravity zoom opencode-desktop-bin teamviewer appimagelauncher chkrootkit gputest claude-desktop"

SKIPPED=(
  "AUR packages (need yay/paru): $AUR_PACKAGES"
  "Gridcoin (Flatpak bundle from GitHub releases)"
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

# A full upgrade rather than a bare -Syy: this script already upgraded the system with -Syu at the start,
# and a refreshed index with no upgrade followed by an install is the partial upgrade the Arch wiki warns
# about, which e2e/tier1/pacman_partial_refresh.sh fails on.
refresh_pacman() { sudo pacman -Syu --noconfirm; }

refresh_flatpak() { flatpak update --appstream --noninteractive flathub; }

# pacman packages from official repos. Steam needs the multilib repo enabled.
PACMAN_PACKAGES=(
  git maven gradle openssl kubectl minikube helm terraform github-cli jq fzf
  ripgrep uv python-pipx go filezilla putty rclone telegram-desktop
  signal-desktop keepassxc vlc handbrake rawtherapee steam veracrypt
  speedtest-cli boinc lynis clamav hardinfo2 lm_sensors baobab gparted
  partitionmanager virt-manager qemu-full libvirt dnsmasq nftables
  virtiofsd docker zsh syncthing tailscale openrazer-daemon
)

# The gaming suite: Lutris on Arch, the CachyOS gaming metapackage on CachyOS, as
# setup/ansible/vars/derivatives/cachyos.yaml maps it.
GAMING_SUITE="lutris"

# Flatpak application IDs (Flathub).
FLATPAK_APPS=(
  org.torproject.torbrowser-launcher com.getpostman.Postman
  io.dbeaver.DBeaverCommunity cc.arduino.IDE2 com.usebruno.Bruno
  com.discordapp.Discord com.slack.Slack md.obsidian.Obsidian
  com.bitwarden.desktop org.onlyoffice.desktopeditors com.spotify.Client
  org.gimp.GIMP org.kde.krita org.audacityteam.Audacity org.freecad.FreeCAD
  com.prusa3d.PrusaSlicer com.leinardi.gwe app.polychromatic.controller
  com.overwolf.curseforge io.podman_desktop.PodmanDesktop
)

log "Updating system and installing prerequisites"
sudo pacman -Syu --needed --noconfirm flatpak

log "Enabling Flathub"
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# CachyOS puts its own repositories in front of Arch's, and its first provider of the virtual
# lib32-vulkan-driver that Steam needs is lib32-mesa-git, which drags in mesa-git, which conflicts with
# the stable mesa on the machine. pacman stops to ask whether to remove mesa, --noconfirm answers no,
# and Steam below fails. mesa-git goes first, because lib32-mesa-git depends on mesa, which mesa-git
# provides. Aligning the graphics stack first is what a CachyOS machine is set
# up to use. See the "Steam on CachyOS" section of arch_manual_install.md.
if [ "$(. /etc/os-release && echo "${ID}")" = "cachyos" ]; then
  log "Aligning the 32-bit graphics stack with the CachyOS repositories"
  yes_answers="$(mktemp)"
  trap 'rm -f "${yes_answers}"' EXIT
  for _ in $(seq 20); do echo y; done > "${yes_answers}"
  for package in mesa-git lib32-mesa-git; do
    sudo pacman -S --needed "${package}" < "${yes_answers}"
  done
  GAMING_SUITE="cachyos-gaming-applications"
fi

# openrazer-daemon pulls openrazer-driver-dkms, and Arch's dkms lists the kernel headers only as an
# optional dependency, so the driver would install with nothing to build against. The headers package
# of every installed kernel goes first, named from its own pkgbase file, as arch_prereqs.yaml does.
log "Installing the kernel headers the OpenRazer driver builds against"
for pkgbase in /usr/lib/modules/*/pkgbase; do
  [ -f "${pkgbase}" ] || continue
  headers="$(cat "${pkgbase}")-headers"
  install_one "${headers}" refresh_pacman sudo pacman -S --needed --noconfirm "${headers}"
done

log "Installing pacman packages (enable [multilib] in /etc/pacman.conf for Steam)"
for package in "${PACMAN_PACKAGES[@]}" "${GAMING_SUITE}"; do
  install_one "${package}" refresh_pacman sudo pacman -S --needed --noconfirm "${package}"
done

log "Installing Flatpak applications"
for app in "${FLATPAK_APPS[@]}"; do
  install_one "${app}" refresh_flatpak flatpak install -y flathub "${app}"
done

log "Enabling the Syncthing user service"
systemctl --user enable --now syncthing.service || printf '   Skipped: no user D-Bus session. Run it yourself after logging in.\n'

log "Enabling the tailscaled system service"
sudo systemctl enable --now tailscaled || printf '   Skipped: tailscaled.service could not be enabled, so tailscale most likely did not install. systemctl printed why above.\n'

log "Enabling and starting the Docker system service"
sudo systemctl enable --now docker || printf '   Skipped: docker.service could not be enabled, so docker most likely did not install. systemctl printed why above.\n'

log "Adding ${USER} to the docker group, which takes effect only after logging out and back in, a new terminal window is not enough"
sudo usermod -aG docker "${USER}" || printf '   Skipped: the docker group does not exist, so docker did not install.\n'

log "Adding ${USER} to the openrazer group, which takes effect at the next login"
sudo usermod -aG openrazer "${USER}" || printf '   Skipped: the openrazer group does not exist, so openrazer-daemon did not install.\n'

log "Done. The following were NOT installed:"
for item in "${SKIPPED[@]}"; do
  printf '   - %s\n' "$item"
done
printf '\nInstall the AUR packages, one per yay call, with:\n  for package in %s; do yay -S --needed "${package}" || echo "FAILED: ${package}"; done\n' "$AUR_PACKAGES"
printf 'SDK managers, AI tools and shell setup are documented in arch_manual_install.md — run those by hand.\n'

if [ "${#FAILED[@]}" -gt 0 ]; then
  printf '\n\033[1;31m==>\033[0m %d package(s) did NOT install, the package manager printed the reason above each one:\n' "${#FAILED[@]}" >&2
  printf '   - %s\n' "${FAILED[@]}" >&2
  exit 1
fi
