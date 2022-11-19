#!/bin/bash

echo "--------------------------"
echo "| Setting env variable.. |"
echo "--------------------------"

temp_folder_path="$HOME/.lukkInstall"

exodusVersion="exodus-linux-x64-22.11.13.deb"
exodus_download_link="https://downloads.exodus.com/releases/$exodusVersion"

chromeVersion="google-chrome-stable_current_amd64.deb"
chrome_download_link="https://dl.google.com/linux/direct/$chromeVersion"

zoomVersion="zoom_amd64.deb"
zoom_download_link="https://zoom.us/client/5.12.2.4816/$zoomVersion"

bitWardenVersion="Bitwarden-2022.10.0-x86_64.AppImage"
bitWarden_download_link="https://github.com/bitwarden/clients/releases/download/desktop-v2022.10.0/$bitWardenVersion"

angryIpScannerVersion="ipscan_3.8.2_amd64.deb"
angryIpScanner_download_link="https://github.com/angryip/ipscan/releases/download/3.8.2/$angryIpScannerVersion"

nordvpnVersion="nordvpn-release_1.0.0_all.deb"
nordvpn_download_link="https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/$nordvpnVersion"

torVersion="tor-browser-linux64-11.5.4_en-US.tar.xz"
tor_download_link="https://www.torproject.org/dist/torbrowser/11.5.4/$torVersion"

ledgerVersion="ledger-app.AppImage"
ledger_download_link="https://download.live.ledger.com/latest/linux"

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
echo "---------------------"
echo "| Installing apps.. |"
echo "---------------------"

sudo apt install git -y
sudo apt install wget curl vim nano -y
sudo apt install snapd -y
sudo apt install ca-certificates curl gnupg lsb-release -y
sudo apt install hardinfo -y
# lib for installing .AppImage files
sudo apt install libfuse2
sudo apt install dconf-editor -y
sudo apt autoremove -y
# better cat
sudo apt install bat

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

sudo snap install android-studio --classic

sudo snap install telegram-desktop
sudo snap install discord
sudo snap install whatsapp-for-linux
sudo snap install caprine

sudo snap install vlc
sudo snap install gimp

sudo snap install okular
sudo snap install wps-2019-snap
sudo snap install sublime-text --classic

# =====================================================================================

echo
echo "------------------------"
echo "| Installing Chrome... |"
echo "------------------------"

wget "$chrome_download_link" -cO "$temp_folder_path"/"$chromeVersion"
sudo dpkg -i "$temp_folder_path"/"$chromeVersion"

# =====================================================================================

echo
echo "---------------------"
echo "| Installing Zoom.. |"
echo "---------------------"

wget "$zoom_download_link" -cO "$temp_folder_path"/"$zoomVersion"
sudo apt install "$temp_folder_path"/"$zoomVersion" -y

# =====================================================================================

echo
echo "---------------------------------"
echo "| Installing Angry IP Scanner.. |"
echo "---------------------------------"

wget "$angryIpScanner_download_link" -cO "$temp_folder_path"/"$angryIpScannerVersion"
sudo apt install "$temp_folder_path"/"$angryIpScannerVersion" -y

# =====================================================================================

echo
echo "-------------------------------"
echo "| Installing Stacer cleaner.. |"
echo "-------------------------------"

sudo add-apt-repository ppa:oguzhaninan/stacer -y
sudo apt update
sudo apt install stacer -y

# =====================================================================================

echo
echo "------------------------"
echo "| Installing NordVPN.. |"
echo "------------------------"

wget "$nordvpn_download_link" -cO "$temp_folder_path"/"$nordvpnVersion"
sudo apt-get install "$temp_folder_path"/"$nordvpnVersion"
sudo apt-get update
sudo apt-get install nordvpn

# =====================================================================================

echo
echo "--------------------------"
echo "| Installing BitWarden.. |"
echo "--------------------------"

wget "$bitWarden_download_link" -cO "$temp_folder_path"/"$bitWardenVersion"
chmod a+x "$temp_folder_path"/"$bitWardenVersion"
sudo mkdir /opt/bitwarden
sudo cp "$temp_folder_path"/"$bitWardenVersion" /opt/bitwarden/bitwarden.AppImage
sudo cp ./icons/bitwarden.png /opt/bitwarden/bitwarden.png
sudo cp ./shortcuts/bitwarden.desktop /usr/share/applications/bitwarden.desktop

# =====================================================================================

echo
echo "----------------------"
echo "| Installing Brave.. |"
echo "----------------------"
# NOT ALL FUNCTIONALITY IS WORKING WITH SNAP INSTALLATION (postman interceptor)

sudo apt install apt-transport-https curl -y
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list
sudo apt update
sudo apt install brave-browser -y

# =====================================================================================

echo
echo "------------------------------"
echo "| Installing Speedtest CLI.. |"
echo "------------------------------"

sudo apt install speedtest-cli
sudo mkdir /opt/speedtest-cli
sudo cp ./icons/speedtest.png /opt/speedtest-cli/speedtest.png
sudo cp ./scripts/speedtest-starter.sh /opt/speedtest-cli/speedtest-starter.sh
sudo chmod +x /opt/speedtest-cli/speedtest-starter.sh
sudo cp ./shortcuts/speedtest.desktop /usr/share/applications/speedtest.desktop

# =====================================================================================

echo
echo "-----------------------"
echo "| Installing Ledger.. |"
echo "-----------------------"

wget "$ledger_download_link" -cO "$temp_folder_path"/"$ledgerVersion"
sudo chmod +x "$temp_folder_path"/ledger-app.AppImage
wget -q -O - "https://raw.githubusercontent.com/LedgerHQ/udev-rules/master/add_udev_rules.sh" | sudo bash

sudo mkdir ~/ledger/
sudo cp "$temp_folder_path"/"$ledgerVersion" ~/ledger/ledger-app.AppImage
sudo cp ./icons/ledger.png ~/ledger/ledger.png
sudo cp ./shortcuts/ledger-app.desktop /usr/share/applications/ledger-app.desktop
sudo chmod a+x /usr/share/applications/ledger-app.desktop

# =====================================================================================

echo
echo "--------------"
echo "| Cleaning.. |"
echo "--------------"

# un-pausing updating grub
sudo apt-mark unhold grub*

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

brave-browser-stable https://extensions.gnome.org/extension/307/dash-to-dock/ &>/dev/null & disown %%
brave-browser-stable https://extensions.gnome.org/extension/5040/start-overlay-in-application-view/ &>/dev/null & disown %%
brave-browser-stable https://extensions.gnome.org/extension/1319/gsconnect/ &>/dev/null & disown %%
brave-browser-stable https://chrome.google.com/webstore/detail/metamask/nkbihfbeogaeaoehlefnkodbefgpgknn &>/dev/null & disown %%
brave-browser-stable https://chrome.google.com/webstore/detail/polkadot%7Bjs%7D-extension/mopnmbcafieddcagagdcbnhejhlodfdd &>/dev/null & disown %%
brave-browser-stable https://chrome.google.com/webstore/detail/tronlink%EF%BC%88%E6%B3%A2%E5%AE%9D%E9%92%B1%E5%8C%85%EF%BC%89/ibnejdfjmmkpcnlpebklmnkoeoihofec &>/dev/null & disown %%
brave-browser-stable https://chrome.google.com/webstore/detail/bitwarden-free-password-m/nngceckbapebfimnlniiiahkandclblb &>/dev/null & disown %%

# =====================================================================================

echo "-------------------------------"
echo "| Running extension manager.. |"
echo "-------------------------------"

extension-manager & disown

# =====================================================================================
