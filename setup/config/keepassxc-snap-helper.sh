#!/usr/bin/env bash
#
# KeePassXC Browser Extension Native Messaging Installer Tool
# Copyright (C) 2017 KeePassXC team <https://keepassxc.org/>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 or (at your option)
# version 3 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

set -euo pipefail
IFS=$'\n\t'

JSON_OUT=""
BASE_DIR="${HOME}"
INSTALL_DIR=""
INSTALL_FILE="org.keepassxc.keepassxc_browser.json"

# Early out if the keepassxc.proxy executable cannot be found
if ! command -v keepassxc.proxy; then
    echo "Could not find keepassxc.proxy! Ensure the keepassxc snap is installed properly."
    exit 0
fi

PROXY_PATH=$(command -v keepassxc.proxy)

JSON_FIREFOX=$(cat << EOF
{
    "name": "org.keepassxc.keepassxc_browser",
    "description": "KeePassXC integration with native messaging support",
    "path": "${PROXY_PATH}",
    "type": "stdio",
    "allowed_extensions": [
        "keepassxc-browser@keepassxc.org"
    ]
}
EOF
)

JSON_CHROME=$(cat << EOF
{
    "name": "org.keepassxc.keepassxc_browser",
    "description": "KeePassXC integration with native messaging support",
    "path": "${PROXY_PATH}",
    "type": "stdio",
    "allowed_origins": [
        "chrome-extension://iopaggbpplllidnfmcghoonnokmjoicf/",
        "chrome-extension://oboonakemofpalcgghocfoadofidjkkk/",
        "chrome-extension://pdffhmdngciaglkoonimfcmckehcpafo/"
    ]
}
EOF
)

setupFirefox() {
    JSON_OUT=${JSON_FIREFOX}
    INSTALL_DIR="${BASE_DIR}/.mozilla/native-messaging-hosts"
}

setupChrome() {
    JSON_OUT=${JSON_CHROME}
    INSTALL_DIR="${BASE_DIR}/.config/google-chrome/NativeMessagingHosts"
}

setupChromium() {
    JSON_OUT=${JSON_CHROME}
    INSTALL_DIR="${BASE_DIR}/.config/chromium/NativeMessagingHosts"
}

setupVivaldi() {
    JSON_OUT=${JSON_CHROME}
    INSTALL_DIR="${BASE_DIR}/.config/vivaldi/NativeMessagingHosts"
}

setupBrave() {
    JSON_OUT=${JSON_CHROME}
    INSTALL_DIR="${BASE_DIR}/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
}

setupTorBrowser() {
    JSON_OUT=${JSON_FIREFOX}
    INSTALL_DIR="${BASE_DIR}/.tor-browser/app/Browser/TorBrowser/Data/Browser/.mozilla/native-messaging-hosts"
}

setupEdge() {
    JSON_OUT=${JSON_CHROME}
    INSTALL_DIR="${BASE_DIR}/.config/microsoft-edge/NativeMessagingHosts"
}

# --------------------------------
# Start of script
# --------------------------------

set +e
BROWSER=$(whiptail \
            --title "Browser Selection" \
            --menu "Choose a browser to integrate with KeePassXC:" \
            15 60 5 \
            "firefox"  "Firefox" \
            "chrome"   "Chrome" \
            "chromium" "Chromium" \
            "vivaldi"  "Vivaldi" \
            "brave"    "Brave" \
            "tor"      "Tor Browser" \
            "edge"     "Microsoft Edge" \
            3>&1 1>&2 2>&3)
exitstatus=$?
set -e

clear

if [[ "${exitstatus}" -eq 0 ]]; then
    case "${BROWSER}" in
        firefox)  setupFirefox ;;
        chrome)   setupChrome ;;
        chromium) setupChromium ;;
        vivaldi)  setupVivaldi ;;
        brave)    setupBrave ;;
        tor)      setupTorBrowser ;;
        edge)     setupEdge ;;
        *)        echo "ERROR: unknown browser selection: ${BROWSER}" >&2; exit 1 ;;
    esac

    # Install the JSON file using install(1) — no cd, safe with spaces.
    install -d -- "${INSTALL_DIR}"
    printf '%s\n' "${JSON_OUT}" > "${INSTALL_DIR}/${INSTALL_FILE}"

    whiptail \
        --title "Installation Complete" \
        --msgbox "You will need to restart your browser in order to connect to KeePassXC" \
        8 50
else
    whiptail --title "Installation Canceled" --msgbox "No changes were made to your system" 8 50
fi
