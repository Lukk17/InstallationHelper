#!/usr/bin/env bash
#
# speedtest-starter — wrapper that runs speedtest-cli and keeps the terminal
# window open afterwards (some terminal emulators auto-close on exit).
#
# Usage: speedtest-starter.sh
set -euo pipefail
IFS=$'\n\t'

if ! command -v speedtest-cli >/dev/null 2>&1; then
    echo "ERROR: speedtest-cli not installed. Install via your package manager." >&2
    exit 1
fi

speedtest-cli

# Block until the user dismisses the window.
read -rp "Press Enter to close..." _
