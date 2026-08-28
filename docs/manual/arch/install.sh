#!/usr/bin/env bash
#
# Manual install script — Arch Linux
#
# Installs every app reachable via pacman (official repos) + Flatpak.
# AUR packages are NOT installed (they need an AUR helper) — they're listed at
# the end with the yay command. Manual blobs are listed too.
#
# Mirrors setup/ansible/vars/Archlinux.yaml. Run as a normal user with sudo rights.

set -euo pipefail

AUR_PACKAGES="google-chrome brave-bin lens-bin jetbrains-toolbox visual-studio-code-bin sublime-text-4 antigravity teamviewer appimagelauncher chkrootkit gputest claude-desktop-bin"

SKIPPED=(
  "AUR packages (need yay/paru): $AUR_PACKAGES"
  "Gridcoin (Flatpak bundle from GitHub releases)"
  "Ledger Live (AppImage)"
  "Trezor Suite (AppImage)"
)

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }

# pacman packages from official repos. Steam needs the multilib repo enabled.
PACMAN_PACKAGES=(
  git maven gradle openssl kubectl minikube helm terraform github-cli jq fzf
  ripgrep filezilla telegram-desktop
  signal-desktop keepassxc vlc handbrake rawtherapee steam veracrypt
  speedtest-cli boinc lynis clamav hardinfo2 lm_sensors baobab gparted
  partitionmanager virt-manager qemu-full libvirt dnsmasq nftables bridge-utils
  virtiofsd docker zsh dart syncthing tailscale
)

# Flatpak application IDs (Flathub).
FLATPAK_APPS=(
  org.torproject.torbrowser-launcher com.getpostman.Postman
  io.dbeaver.DBeaverCommunity cc.arduino.IDE2 com.usebruno.Bruno
  com.discordapp.Discord com.slack.Slack md.obsidian.Obsidian
  com.bitwarden.desktop org.onlyoffice.desktopeditors com.spotify.Client
  org.gimp.GIMP org.kde.krita org.audacityteam.Audacity org.freecad.FreeCAD
  com.prusa3d.PrusaSlicer com.leinardi.gwe app.polychromatic.controller
)

log "Updating system and installing prerequisites"
sudo pacman -Syu --needed --noconfirm flatpak

log "Enabling Flathub"
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# CachyOS puts its own repositories in front of Arch's, and its first provider of the virtual
# lib32-vulkan-driver that Steam needs is lib32-mesa-git, which drags in mesa-git, which conflicts with
# the stable mesa on the machine. pacman stops to ask whether to remove mesa, --noconfirm answers no,
# and the whole batch below fails. Aligning the graphics stack first is what a CachyOS machine is set
# up to use. See the "Steam on CachyOS" section of arch_manual_install.md.
if [ "$(. /etc/os-release && echo "${ID}")" = "cachyos" ]; then
  log "Aligning the 32-bit graphics stack with the CachyOS repositories"
  yes_answers="$(mktemp)"
  trap 'rm -f "${yes_answers}"' EXIT
  for _ in $(seq 20); do echo y; done > "${yes_answers}"
  sudo pacman -Syy --needed mesa-git lib32-mesa-git < "${yes_answers}"
fi

log "Installing pacman packages (enable [multilib] in /etc/pacman.conf for Steam)"
sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"

log "Installing Flatpak applications"
flatpak install -y flathub "${FLATPAK_APPS[@]}"

log "Enabling the Syncthing user service"
systemctl --user enable --now syncthing.service || printf '   Skipped: no user D-Bus session. Run it yourself after logging in.\n'

log "Enabling the tailscaled system service"
sudo systemctl enable --now tailscaled

log "Done. The following were NOT installed:"
for item in "${SKIPPED[@]}"; do
  printf '   - %s\n' "$item"
done
printf '\nInstall the AUR packages with:  yay -S %s\n' "$AUR_PACKAGES"
printf 'SDK managers, AI tools and shell setup are documented in arch_manual_install.md — run those by hand.\n'
