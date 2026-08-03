#!/usr/bin/env bash
#
# Manual install script — macOS
#
# Installs every app the playbook manages via Homebrew (formulae + casks).
# Antigravity and Gridcoin install from a direct DMG and are NOT handled here —
# see macos_manual_install.md "Manual install required".
#
# Mirrors setup/ansible/vars/Darwin.yaml.

set -euo pipefail

SKIPPED=(
  "Antigravity (direct DMG, arch-specific)"
  "Gridcoin (direct DMG from GitHub releases)"
)

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }

# Homebrew formulae (CLI).
BREW_FORMULAE=(
  git maven gradle openssl@3 kubernetes-cli minikube helm hashicorp/tap/terraform
  gh jq fzf ripgrep speedtest-cli lynis bruno-cli dart zsh
)

# Homebrew casks (GUI apps).
BREW_CASKS=(
  google-chrome brave-browser tor-browser postman dbeaver-community lens
  cyberduck intellij-idea visual-studio-code sublime-text arduino-ide bruno
  discord slack microsoft-teams telegram signal whatsapp obsidian bitwarden
  keepassxc onlyoffice vlc spotify gimp krita handbrake-app audacity rawtherapee
  steam ea gog-galaxy epic-games curseforge freecad prusaslicer teamviewer
  veracrypt boinc stats grandperspective lulu balenaetcher utm docker-desktop
  vmware-fusion claude syncthing-app
)

if ! command -v brew >/dev/null 2>&1; then
  log "Homebrew not found — installing it first"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

log "Updating Homebrew"
brew update

log "Installing formulae"
brew install "${BREW_FORMULAE[@]}"

log "Installing casks"
brew install --cask "${BREW_CASKS[@]}"

log "Done. The following were NOT installed (manual DMG required):"
for item in "${SKIPPED[@]}"; do
  printf '   - %s\n' "$item"
done
printf '\nSDK managers, AI tools (npm) and shell setup are documented in macos_manual_install.md — run those by hand.\n'
