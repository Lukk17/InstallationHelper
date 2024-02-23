#!/usr/bin/env bash

echo "--------------------------"
echo "| Setting env variable.. |"
echo "--------------------------"

temp_folder_path="$HOME/.lukkInstall"

MYSQL_PASSWORD="Lukk1234"

chromeVersion="google-chrome-stable_current_amd64.deb"
chrome_download_link="https://dl.google.com/linux/direct/$chromeVersion"

githubDesktopVersion="GitHubDesktop-linux-3.0.6-linux1.deb"
githubDesktop_download_link="https://github.com/shiftkey/desktop/releases/download/release-3.0.6-linux1/$githubDesktopVersion"

mongoCompassVersion="mongodb-compass_1.33.1_amd64.deb"
mongoCompass_download_link="https://downloads.mongodb.com/compass/$mongoCompassVersion"

dockerDesktopVersion="docker-desktop-4.25.2-amd64.deb"
dockerDesktop_download_link="https://desktop.docker.com/linux/main/amd64/$dockerDesktopVersion"

VMwareVersion="VMware-Player-Full-16.2.4-20089737.x86_64.bundle"
VMware_download_link="https://download3.vmware.com/software/WKST-PLAYER-1624/$VMwareVersion"

zoomVersion="zoom_amd64.deb"
zoom_download_link="https://zoom.us/client/5.12.2.4816/$zoomVersion"

angryIpScannerVersion="ipscan_3.8.2_amd64.deb"
angryIpScanner_download_link="https://github.com/angryip/ipscan/releases/download/3.8.2/$angryIpScannerVersion"

nordvpnVersion="nordvpn-release_1.0.0_all.deb"
nordvpn_download_link="https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/$nordvpnVersion"

minikubeVersion="minikube_latest_amd64.deb"
minikube_download_link="https://storage.googleapis.com/minikube/releases/latest/$minikubeVersion"

postmanVersion="linux64"
postman_download_link="https://dl.pstmn.io/download/latest/$postmanVersion"

lensVersion="Lens-2022.10.181357-latest.amd64.deb"
lens_download_link="https://api.k8slens.dev/binaries/$lensVersion"

torVersion="tor-browser-linux64-11.5.4_en-US.tar.xz"
tor_download_link="https://www.torproject.org/dist/torbrowser/11.5.4/$torVersion"

bitWardenVersion="Bitwarden-2022.10.0-x86_64.AppImage"
bitWarden_download_link="https://github.com/bitwarden/clients/releases/download/desktop-v2022.10.0/$bitWardenVersion"

beeperVersion="beeper.AppImage  "
beeper_download_link="https://download.beeper.com/linux/appImage/x64"

startOverlayInApplicationView_link="https://extensions.gnome.org/extension/5040/start-overlay-in-application-view/"
gsconnect_link="https://extensions.gnome.org/extension/1319/gsconnect/"
keepassXC_addon_link="https://chrome.google.com/webstore/detail/keepassxc-browser/oboonakemofpalcgghocfoadofidjkkk"
notification_addod_link="https://extensions.gnome.org/extension/258/notifications-alert-on-user-menu/"

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
echo "------------------------------"
echo "| Installing Open Java JDK.. |"
echo "------------------------------"

sudo apt install openjdk-17-jdk openjdk-17-jre -y

# =====================================================================================

echo
echo "---------------------"
echo "| Installing apps.. |"
echo "---------------------"

sudo apt install virtualbox -y
sudo apt install maven gradle git -y
sudo apt install wget curl vim nano -y
sudo apt install snapd -y
sudo apt install ca-certificates curl gnupg lsb-release -y
sudo apt install hardinfo -y
# lib for installing .AppImage files
sudo apt install libfuse2 -y
sudo apt install dconf-editor -y
sudo apt autoremove -y
# utils like htpasswd (used in kubernetes password creation)
sudo apt install apache2-utils -y
# better cat
sudo apt install bat -y
sudo apt install openssl -y

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
echo "----------------------------"
echo "| Installing Gnome Tools.. |"
echo "----------------------------"

sudo add-apt-repository universe -y
sudo apt install gnome-tweaks gnome-online-accounts gnome-shell-extension-gsconnect -y
sudo apt install gnome-shell-extension-manager gnome-shell-extensions chrome-gnome-shell -y
sudo apt install  gnome-calendar -y

# =====================================================================================

echo
echo "--------------------------------"
echo "| Installing grub-customizer.. |"
echo "--------------------------------"

sudo add-apt-repository ppa:danielrichter2007/grub-customizer -y
sudo apt-get install grub-customizer -y

# =====================================================================================

echo
echo "----------------------"
echo "| Installing snaps.. |"
echo "----------------------"

sudo snap install android-studio --classic
sudo snap install flutter --classic
sudo snap install freecad
sudo snap install cura-slicer

sudo snap install sublime-text --classic
sudo snap install wps-2019-snap
sudo snap install okular
sudo snap install trello-desktop
sudo snap install obsidian --classic

sudo snap install steam

sudo snap install gimp
sudo snap install spotify
sudo snap install vlc

sudo snap install discord
sudo snap install skype --classic
sudo snap install telegram-desktop
sudo snap install slack
sudo snap install teams

# =====================================================================================

echo
echo "------------------------"
echo "| Installing Chrome... |"
echo "------------------------"

wget "$chrome_download_link" -cO "$temp_folder_path"/"$chromeVersion"
sudo apt install "$temp_folder_path"/"$chromeVersion" -y

# =====================================================================================

echo
echo "-------------------------------"
echo "| Installing GitHubDesktop... |"
echo "-------------------------------"

sudo wget "$githubDesktop_download_link" -cO "$temp_folder_path"/"$githubDesktopVersion"
sudo apt install gdebi-core -y
sudo gdebi -n "$temp_folder_path"/"$githubDesktopVersion"

# =====================================================================================

echo
echo "-------------------------------------------"
echo "| Installing Intellij Idea... |"
echo "-------------------------------------------"

sudo snap install intellij-idea-ultimate --classic

# =====================================================================================

echo
echo "-------------------"
echo "| Installing SQL. |"
echo "-------------------"

# install mysql and give password to installer
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_PASSWORD"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_PASSWORD"
sudo apt install mysql-server -y
sudo snap install mysql-workbench-community
# to avoid blocking workbench by linux AppArmor
sudo snap connect mysql-workbench-community:password-manager-service :password-manager-service

sudo snap install postgresql

# =====================================================================================

echo
echo "----------------------"
echo "| Installing NoSQL.. |"
echo "----------------------"

sudo apt install gnupg -y
wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
sudo apt update
sudo apt install mongodb-org -y
sudo systemctl enable mongod
wget "$mongoCompass_download_link" -cO "$temp_folder_path"/"$mongoCompassVersion"
sudo dpkg -i "$temp_folder_path"/"$mongoCompassVersion"
#in case dependency problems:
sudo apt --fix-broken install -y
#and reinstall:
sudo dpkg -i "$temp_folder_path"/"$mongoCompassVersion"

# =====================================================================================

echo
echo "-----------------------"
echo "| Installing Docker.. |"
echo "-----------------------"

wget "$dockerDesktop_download_link" -cO "$temp_folder_path"/"$dockerDesktopVersion"
sudo chmod +x "$temp_folder_path"/"$dockerDesktopVersion"

sudo apt update
sudo apt install ./"$dockerDesktopVersion" -y

# adding user to docker group to docker be available to testcontainers in projects
# https://docs.docker.com/engine/install/linux-postinstall/
sudo groupadd docker
sudo usermod -aG docker $USER

# =====================================================================================

echo
echo "------------------------------------------"
echo "| Installing VMware Workstation Player.. |"
echo "------------------------------------------"

sudo apt install build-essential -y
wget "$VMware_download_link" -cO "$temp_folder_path"/"$VMwareVersion"
sudo chmod +x "$temp_folder_path"/"$VMwareVersion"
sudo "$temp_folder_path"/"$VMwareVersion"

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
echo "------------------------"
echo "| Installing NordVPN.. |"
echo "------------------------"

wget "$nordvpn_download_link" -cO "$temp_folder_path"/"$nordvpnVersion"
sudo apt install "$temp_folder_path"/"$nordvpnVersion" -y
sudo apt update
sudo apt install nordvpn -y

sudo cp ./shortcuts/nordvpn.desktop /usr/share/applications/nordvpn.desktop
sudo cp ./shortcuts/nordvpn-disconnect.desktop /usr/share/applications/nordvpn-disconnect.desktop

# =====================================================================================

echo
echo "---------------------------"
echo "| Installing Kubernetes.. |"
echo "---------------------------"

sudo snap install kubectl --classic

# =====================================================================================

echo
echo "-------------------------"
echo "| Installing minikube.. |"
echo "-------------------------"

wget "$minikube_download_link" -cO "$temp_folder_path"/"$minikubeVersion"
sudo dpkg -i "$temp_folder_path"/"$minikubeVersion"

# =====================================================================================

echo
echo "--------------------------"
echo "| Installing KeepassXC.. |"
echo "--------------------------"

sudo snap install keepassxc

sudo chmod +x ./config/keepassxc-snap-helper.sh
./config/keepassxc-snap-helper.sh

# =====================================================================================

echo
echo "---------------------"
echo "| Installing Helm.. |"
echo "---------------------"

sudo snap install helm --classic

# =====================================================================================

echo
echo "------------------------"
echo "| Installing Postman.. |"
echo "------------------------"
# NOT ALL FUNCTIONALITY IS WORKING WITH SNAP INSTALLATION (postman interceptor)

wget "$postman_download_link" -cO "$temp_folder_path"/"$postmanVersion"
sudo tar -xf "$temp_folder_path"/"$postmanVersion" -C "$temp_folder_path"/
sudo cp -R "$temp_folder_path"/Postman /opt/postman/
sudo mv /opt/postman/Postman /opt/postman/postman
sudo cp ./shortcuts/postman.desktop /usr/share/applications/postman.desktop
sudo chmod +x /usr/share/applications/postman.desktop

# =====================================================================================
echo
echo "----------------------"
echo "| Installing Brave.. |"
echo "----------------------"
# NOT ALL FUNCTIONALITY IS WORKING WITH SNAP INSTALLATION (postman interceptor)

sudo apt install apt-transport-https curl -y
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main"|sudo tee /etc/apt/sources.list.d/brave-browser-release.list
sudo apt update
sudo apt install brave-browser -y

# =====================================================================================

echo
echo "----------------------------"
echo "| Installing Boot repair.. |"
echo "----------------------------"

sudo add-apt-repository ppa:yannubuntu/boot-repair -y
sudo apt update
sudo apt install boot-repair -y

# =====================================================================================

echo
echo "--------------------------------"
echo "| Installing Kubernetes Lens.. |"
echo "--------------------------------"

wget "$lens_download_link" -cO "$temp_folder_path"/"$lensVersion"
sudo dpkg -i "$temp_folder_path"/"$lensVersion"

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
echo "--------------------------"
echo "| Installing BitWarden.. |"
echo "--------------------------"

wget "$bitWarden_download_link" -cO "$temp_folder_path"/"$bitWardenVersion"
chmod a+x "$temp_folder_path"/"$bitWardenVersion"
# app-image launcher will intercept this copy or move it to its default folder and install
"$temp_folder_path"/"$bitWardenVersion"

# =====================================================================================

echo
echo "--------------------------"
echo "| Installing Beeper.. |"
echo "--------------------------"

wget "$beeper_download_link" -cO "$temp_folder_path"/"$beeperVersion"
chmod a+x "$temp_folder_path"/"$beeperVersion"
# app-image launcher will intercept this copy or move it to its default folder and install
"$temp_folder_path"/"$beeperVersion"

# =====================================================================================

echo
echo "--------------"
echo "| Cleaning.. |"
echo "--------------"

# un-pausing updating grub
sudo apt-mark unhold grub*
sudo apt --fix-broken install -y

# =====================================================================================

echo
echo "---------------------"
echo "| Running upgrade.. |"
echo "---------------------"

sudo apt update
sudo apt-get full-upgrade -y
sudo apt autoremove  -y
source ~/.bashrc

# =====================================================================================

echo
echo "-------------------------------------------------"
echo "| Opening extension install pages in browsers.. |"
echo "-------------------------------------------------"

xdg-settings set default-web-browser google-chrome.desktop

google-chrome "$startOverlayInApplicationView_link" &>/dev/null & disown %%
google-chrome "$gsconnect_link" &>/dev/null & disown %%
google-chrome "$keepassXC_addon_link" &>/dev/null & disown %%
google-chrome "$notification_addod_link" &>/dev/null & disown %%

# =====================================================================================

echo "-------------------------------"
echo "| Running extension manager.. |"
echo "-------------------------------"

extension-manager & disown

# =====================================================================================

echo
echo "---------------------------"
echo "| Running AppImage apps.. |"
echo "---------------------------"

# app-image launcher will intercept this copy or move it to its default folder and install
"$temp_folder_path"/"$bitWardenVersion"

