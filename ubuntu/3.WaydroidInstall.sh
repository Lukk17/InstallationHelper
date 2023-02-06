#!/bin/bash

echo "--------------------------"
echo "| Setting env variable.. |"
echo "--------------------------"

temp_folder_path="$HOME/.lukkInstall"



auroraStore_version="AuroraStore_4.1.1.apk"
auroraStore_link="https://files.auroraoss.com/AuroraStore/Stable/$auroraStore_version"

auroraDroid_version="AuroraDroid_1.0.8.apk"
auroraDroid_link="https://files.auroraoss.com/AuroraDroid/Stable/$auroraDroid_version"

# =====================================================================================

echo
echo "------------------------"
echo "| Making temp folder.. |"
echo "------------------------"

mkdir "$temp_folder_path"

# =====================================================================================

echo
echo "----------------------------------------"
echo "| Installing Waydroid and app stores.. |"
echo "----------------------------------------"

sudo apt install curl ca-certificates -y
curl https://repo.waydro.id | sudo bash
sudo apt install waydroid -y

waydroid prop set persist.waydroid.multi_windows true
sudo systemctl restart waydroid-container

wget --user-agent="Mozilla" "$auroraStore_link" -cO "$temp_folder_path"/"$auroraStore_version"
waydroid app install "$temp_folder_path"/"$auroraStore_version"

wget --user-agent="Mozilla" "$auroraDroid_link" -cO "$temp_folder_path"/"$auroraDroid_version"
waydroid app install "$temp_folder_path"/"$auroraDroid_version"

# =====================================================================================

echo
echo "-------------------------"
echo "| Configuring Wayland.. |"
echo "-------------------------"

sudo sed -i 's/#WaylandEnable=false/WaylandEnable=true/g' /etc/gdm3/custom.conf
sudo bash -c "echo 'options nvidia NVreg_PreserveVideoMemoryAllocations=1' >> /etc/modprobe.d/nvidia-power-management.conf"
sudo systemctl restart gdm3


# =====================================================================================

echo
echo "--------------"
echo "| Cleaning.. |"
echo "--------------"

yes | sudo rm -R "$temp_folder_path"