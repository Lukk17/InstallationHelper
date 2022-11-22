#!/bin/bash

echo "--------------------------"
echo "| Setting env variable.. |"
echo "--------------------------"

temp_folder_path="$HOME/.lukkInstall"

ledgerVersion="ledger-app.AppImage"
ledger_download_link="https://download.live.ledger.com/latest/linux"

# =====================================================================================

echo
echo "---------------------"
echo "| Updating Ledger.. |"
echo "---------------------"

wget "$ledger_download_link" -cO "$temp_folder_path"/"$ledgerVersion"
sudo chmod +x "$temp_folder_path"/ledger-app.AppImage
wget -q -O - "https://raw.githubusercontent.com/LedgerHQ/udev-rules/master/add_udev_rules.sh" | sudo bash
# app-image launcher will intercept this copy or move it to its default folder and install
"$temp_folder_path"/ledger-app.AppImage

# =====================================================================================
