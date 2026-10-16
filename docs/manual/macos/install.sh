#!/usr/bin/env bash
#
# Manual install script — macOS
#
# Installs every app the playbook manages via Homebrew (formulae + casks), one
# package per brew call, so a name that fails costs that package and nothing
# else. The ones that failed are listed at the end and the script exits 1.
# Gridcoin installs from a direct DMG and is NOT handled here, see
# macos_manual_install.md "Manual install required".
#
# Mirrors setup/ansible/vars/Darwin.yaml.

set -euo pipefail

SKIPPED=(
  "Gridcoin (direct DMG from GitHub releases)"
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

refresh_brew() { brew update; }

# Homebrew formulae (CLI).
BREW_FORMULAE=(
  git maven gradle openssl@3 kubernetes-cli minikube k3d helm hashicorp/tap/terraform
  gh jq fzf ripgrep uv pipx go speedtest-cli lynis bruno-cli dart-sdk zsh
)

# Homebrew casks (GUI apps).
BREW_CASKS=(
  google-chrome brave-browser tor-browser postman dbeaver-community lens
  cyberduck jetbrains-toolbox antigravity visual-studio-code sublime-text arduino-ide bruno
  discord slack microsoft-teams zoom telegram signal whatsapp obsidian bitwarden
  keepassxc onlyoffice vlc spotify gimp krita handbrake-app audacity rawtherapee
  steam ea gog-galaxy epic-games curseforge freecad prusaslicer teamviewer
  veracrypt boinc stats grandperspective lulu balenaetcher utm docker-desktop
  virtualbox claude chatgpt opencode-desktop syncthing-app tailscale-app
)

# LM Studio publishes an Apple Silicon build only, and its cask refuses an Intel Mac.
if [ "$(uname -m)" = "arm64" ]; then
  BREW_CASKS+=(lm-studio)
else
  SKIPPED+=("LM Studio (Apple Silicon only)")
fi

if ! command -v brew >/dev/null 2>&1; then
  log "Homebrew not found — installing it first"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

log "Updating Homebrew"
brew update

log "Installing formulae"
for formula in "${BREW_FORMULAE[@]}"; do
  install_one "${formula}" refresh_brew brew install "${formula}"
done

log "Installing casks"
for cask in "${BREW_CASKS[@]}"; do
  install_one "${cask}" refresh_brew brew install --cask "${cask}"
done

log "Done. The following were NOT installed (manual install required):"
for item in "${SKIPPED[@]}"; do
  printf '   - %s\n' "$item"
done
printf '\nSDK managers, AI tools (npm) and shell setup are documented in macos_manual_install.md — run those by hand.\n'

if [ "${#FAILED[@]}" -gt 0 ]; then
  printf '\n\033[1;31m==>\033[0m %d package(s) did NOT install, brew printed the reason above each one:\n' "${#FAILED[@]}" >&2
  printf '   - %s\n' "${FAILED[@]}" >&2
  exit 1
fi
