#!/bin/bash

echo "--------------------------"
echo "| Setting env variable.. |"
echo "--------------------------"

temp_folder_path="$HOME/.lukkInstall"

exodusVersion="exodus-linux-x64-22.11.13.deb"
exodus_download_link="https://downloads.exodus.com/releases/$exodusVersion"

chromeVersion="google-chrome-stable_current_amd64.deb"
chrome_download_link="https://dl.google.com/linux/direct/$chromeVersion"

ledgerVersion="ledger-app.AppImage"
ledger_download_link="https://download.live.ledger.com/latest/linux"

trezorVersion="Trezor-Suite-25.4.2-linux-x86_64.AppImage"
trezor_download_link="https://data.trezor.io/suite/releases/desktop/latest/$trezorVersion"

keepassXC_version="KeePassXC-2.7.10-x86_64.AppImage"
keepassXC_link="https://github.com/keepassxreboot/keepassxc/releases/download/2.7.10/$keepassXC_version"

torVersion="tor-browser-linux-x86_64-14.5.tar.xz "
tor_download_link="https://www.torproject.org/dist/torbrowser/14.5/$torVersion"

dashToDock_link="https://extensions.gnome.org/extension/307/dash-to-dock/"

startOverlayInApplicationView_link="https://extensions.gnome.org/extension/5040/start-overlay-in-application-view/"

# =====================================================================================

echo
echo "------------------------"
echo "| Making temp folder.. |"
echo "------------------------"

mkdir "$temp_folder_path"

# =====================================================================================

echo
echo "---------------------"
echo "| Updating system.. |"
echo "---------------------"

sudo apt --fix-broken install -y
sudo apt update && sudo apt full-upgrade -y
sudo apt autoremove -y

# =====================================================================================

echo
echo "-----------------------------------"
echo "| Installing App-image Launcher.. |"
echo "-----------------------------------"

sudo add-apt-repository ppa:appimagelauncher-team/stable -y
sudo apt-get update
sudo apt-get install appimagelauncher -y

# =====================================================================================

echo
echo "---------------------"
echo "| Installing apps.. |"
echo "---------------------"

sudo apt install git -y
sudo apt install wget curl vim nano -y
sudo apt install snapd -y
sudo apt install ca-certificates curl gnupg lsb-release -y
# lib for installing .AppImage files
sudo apt install libfuse2 -y
sudo apt install dconf-editor -y
sudo apt autoremove -y
# better cat
sudo apt install bat -y

# =====================================================================================

echo
echo "----------------------------"
echo "| Installing Security apps |"
echo "----------------------------"

sudo apt install lynis -y
sudo apt install chkrootkit -y
sudo apt install clamav -y

# =====================================================================================

echo
echo "--------------------------------"
echo "| Installing grub-customizer.. |"
echo "--------------------------------"

sudo add-apt-repository ppa:danielrichter2007/grub-customizer -y
sudo apt-get install grub-customizer -y

# =====================================================================================

echo
echo "-----------------------"
echo "| Installing Exodus.. |"
echo "-----------------------"

wget $exodus_download_link -cO $temp_folder_path/$exodusVersion
sudo chmod a+x $temp_folder_path/$exodusVersion
sudo dpkg -i $temp_folder_path/$exodusVersion

# =====================================================================================

echo
echo "----------------------"
echo "| Installing snaps.. |"
echo "----------------------"

sudo snap install telegram-desktop
sudo snap install discord
sudo snap install whatsapp-for-linux
sudo snap install caprine

sudo snap install vlc
sudo snap install gimp

sudo snap install okular
sudo snap install wps-2019-snap
sudo snap install sublime-text --classic
sudo snap install keepassxc

sudo snap install nordvpn

# =====================================================================================

echo
echo "------------------------"
echo "| Installing Chrome... |"
echo "------------------------"

wget "$chrome_download_link" -cO "$temp_folder_path"/"$chromeVersion"
sudo dpkg -i "$temp_folder_path"/"$chromeVersion"

# =====================================================================================

echo
echo "------------------------"
echo "| Installing NordVPN.. |"
echo "------------------------"

wget "$nordvpn_download_link" -cO "$temp_folder_path"/"$nordvpnVersion"
sudo apt-get install "$temp_folder_path"/"$nordvpnVersion"
sudo apt-get update
sudo apt-get install nordvpn

# add shortcuts
sudo cp ./shortcuts/nordvpn.desktop /usr/share/applications/nordvpn.desktop
sudo cp ./shortcuts/nordvpn-disconnect.desktop /usr/share/applications/nordvpn-disconnect.desktop

# add to autostart
sudo cp ./shortcuts/nordvpn-startup.desktop "$HOME"/.config/autostart/nordvpn-startup.desktop

sudo mkdir "$HOME"/.config/autostart/startVPN
sudo cp ./config/startVPN/startVPN.sh "$HOME"/.config/autostart/startVPN/startVPN.sh

# =====================================================================================

echo
echo "------------------------"
echo "| Installing Firefox.. |"
echo "------------------------"
# NOT ALL FUNCTIONALITY IS WORKING WITH SNAP INSTALLATION (e.g. Postman interceptor, KeepassXC)

sudo snap remove firefox --purge
sudo apt remove firefox -y
sudo add-apt-repository ppa:mozillateam/ppa -y
# change the install priority (default priority is set to snap)
echo '
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
' | sudo tee /etc/apt/preferences.d/mozilla-firefox
# allow this repository to be updated by apt
echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:${distro_codename}";' | sudo tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox
sudo apt update
sudo apt install firefox -y

# =====================================================================================

echo
echo "----------------------"
echo "| Installing Brave.. |"
echo "----------------------"
# NOT ALL FUNCTIONALITY IS WORKING WITH SNAP INSTALLATION (e.g. Postman interceptor, KeepassXC)

sudo apt install apt-transport-https curl -y
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list
sudo apt update
sudo apt install brave-browser -y

# =====================================================================================

echo
echo "-----------------------"
echo "| Installing Ledger.. |"
echo "-----------------------"

wget "$ledger_download_link" -cO "$temp_folder_path"/"$ledgerVersion"
sudo chmod +x "$temp_folder_path"/"$ledgerVersion"
wget -q -O - "https://raw.githubusercontent.com/LedgerHQ/udev-rules/master/add_udev_rules.sh" | sudo bash

# =====================================================================================

echo
echo "-----------------------"
echo "| Installing Trezor.. |"
echo "-----------------------"

wget "$trezor_download_link" -cO "$temp_folder_path"/"$trezorVersion"
sudo chmod +x "$temp_folder_path"/"$trezorVersion"
wget -q -O "$temp_folder_path"/"$trezor-udev_2_all.deb" "https://data.trezor.io/udev/trezor-udev_2_all.deb"
sudo apt install "$temp_folder_path"/"$trezor-udev_2_all.deb"

# =====================================================================================

echo
echo "--------------------------"
echo "| Installing BitWarden.. |"
echo "--------------------------"

wget "$bitWarden_download_link" -cO "$temp_folder_path"/"$bitWardenVersion"
chmod a+x "$temp_folder_path"/"$bitWardenVersion"

# =====================================================================================

echo
echo "--------------------------"
echo "| Installing KeepassXC.. |"
echo "--------------------------"

# KeepassXC installed already via snap
sudo chmod +x ./config/keepassxc-snap-helper.sh
./config/keepassxc-snap-helper.sh

sudo cp ./shortcuts/startK.desktop $HOME/.config/autostart/startK.desktop

# =====================================================================================

echo
echo "---------------------"
echo "| Running upgrade.. |"
echo "---------------------"

sudo apt update
sudo apt-get full-upgrade -y
sudo apt autoremove -y
source ~/.bashrc

# =====================================================================================

echo
echo "-------------------------------"
echo "| Copying Manual to Desktop.. |"
echo "-------------------------------"

cp ./manual/Manual.pdf ~/Desktop/Manual.pdf

# =====================================================================================

echo
echo "----------------------------"
echo "| Installing Tor Browser.. |"
echo "----------------------------"

wget "$tor_download_link" -cO "$temp_folder_path"/"$torVersion"
sudo mkdir /opt/tor
sudo tar -xf "$temp_folder_path"/"$torVersion" -C /opt/tor/
sudo chmod +rwx -R /opt/tor/
sudo chown lukk -R /opt/tor/
cd /opt/tor/tor-browser_en-US/
./start-tor-browser.desktop --register-app
cd ~

# =====================================================================================

echo
echo "-------------------------------------------------"
echo "| Opening extension install pages in browsers.. |"
echo "-------------------------------------------------"

xdg-settings set default-web-browser brave-browser.desktop

#firefox because of brave first launch will ask about being default and won't open all pages
firefox "$dashToDock_link" &>/dev/null & disown %%
firefox "$startOverlayInApplicationView_link" &>/dev/null & disown %%

# =====================================================================================

echo
echo "--------------"
echo "| Cleaning.. |"
echo "--------------"

# un-pausing updating grub
sudo apt-mark unhold grub*

# =====================================================================================

echo
echo "---------------------------"
echo "| Running AppImage apps.. |"
echo "---------------------------"

# app-image launcher will intercept this copy or move it to its default folder and install
"$temp_folder_path"/"$ledgerVersion"
"$temp_folder_path"/"$trezorVersion"

# =====================================================================================

echo
echo "----------------------------------------------------------------------"
echo "| Install gnome extensions opened in browser via Extension Manager.. |"
echo "----------------------------------------------------------------------"

extension-manager & disown
