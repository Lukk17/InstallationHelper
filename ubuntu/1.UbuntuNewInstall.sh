#!/usr/bin/env bash

echo "--------------------------"
echo "| Setting env variable.. |"
echo "--------------------------"

temp_folder_path=~/.lukkInstall
MYSQL_PASSWORD='Lukk1234'

githubDesktopVersion=GitHubDesktop-linux-3.0.6-linux1.deb
githubDesktop_download_link=https://github.com/shiftkey/desktop/releases/download/release-3.0.6-linux1/$githubDesktopVersion

intellijChannelVersion=2020.3/stable

mongoCompassVersion=mongodb-compass_1.33.1_amd64.deb
mongoCompass_download_link=https://downloads.mongodb.com/compass/$mongoCompassVersion

minikube_download_link=https://storage.googleapis.com/minikube/releases/latest/minikube_latest_amd64.deb

VMware_download_link=https://download3.vmware.com/software/WKST-PLAYER-1624/VMware-Player-Full-16.2.4-20089737.x86_64.bundle

franzVersion=franz_5.9.2_amd64.deb
franz_download_link=https://github.com/meetfranz/franz/releases/download/v5.9.2/$franzVersion

zoomVersion=zoom_amd64.deb
zoom_download_link=https://zoom.us/client/5.12.2.4816/$zoomVersion

bitWardenVersion=Bitwarden-2022.10.0-x86_64.AppImage
bitWarden_download_link=https://github.com/bitwarden/clients/releases/download/desktop-v2022.10.0/$bitWardenVersion

zenmapVersion=zenmap_7.60-1ubuntu5_all.deb
zenmap_download_link=http://archive.ubuntu.com/ubuntu/pool/universe/n/nmap/$zenmapVersion

angryIpScannerVersion=ipscan_3.8.2_amd64.deb
angryIpScanner_download_link=https://github.com/angryip/ipscan/releases/download/3.8.2/$angryIpScannerVersion

torVersion=tor-browser-linux64-11.5.4_en-US.tar.xz
tor_download_link=https://www.torproject.org/dist/torbrowser/11.5.4/$torVersion

# =====================================================================================

echo
echo "------------------------"
echo "| Making temp folder.. |"
echo "------------------------"

mkdir $temp_folder_path

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
echo "----------------------------------"
echo "| Installing Gnome Tools.. |"
echo "----------------------------------"
sudo add-apt-repository universe -y
sudo apt install gnome-tweaks gnome-online-accounts gnome-shell-extension-gsconnect -y
sudo apt install gnome-shell-extension-manager gnome-shell-extensions chrome-gnome-shell

# =====================================================================================

echo
echo "--------------------------------"
echo "| Installing grub-customizer.. |"
echo "--------------------------------"
sudo add-apt-repository ppa:danielrichter2007/grub-customizer -y
sudo apt-get install grub-customizer -y

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
sudo apt install steam-installer -y
sudo apt install hardinfo -y
# lib for installing .AppImage files
sudo apt install libfuse2
sudo apt install dconf-editor -y
sudo apt autoremove -y

# =====================================================================================

echo
echo "----------------------"
echo "| Installing snaps.. |"
echo "----------------------"
sudo snap install okular
sudo snap install freecad
sudo snap install discord
sudo snap install cura-slicer
sudo snap install gimp
sudo snap install mysql-workbench-community
sudo snap install android-studio --classic
sudo snap install spotify
sudo snap install sublime-text --classic
sudo snap install wps-2019-snap
sudo snap install skype --classic
sudo snap install chromium
sudo snap install brave
sudo snap install vlc
sudo snap install telegram-desktop
sudo snap install postman
sudo snap install caprine
sudo snap install whatsapp-for-linux
sudo snap install slack
sudo snap install teams

# =====================================================================================

echo "-------------------------------"
echo "| Installing GitHubDesktop... |"
echo "-------------------------------"
sudo wget -P $temp_folder_path/ $githubDesktop_download_link
sudo apt install gdebi-core -y
sudo gdebi $temp_folder_path/$githubDesktopVersion -y

# =====================================================================================

echo
echo "-------------------------------------------"
echo "| Installing Intellij version 2020.3.4 .. |"
echo "-------------------------------------------"
sudo snap install intellij-idea-ultimate --channel=$intellijChannelVersion --classic

# =====================================================================================

echo
echo "----------------------"
echo "| Installing MySQL.. |"
echo "----------------------"
# install mysql and give password to installer
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_PASSWORD"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_PASSWORD"
sudo apt install mysql-server -y

# =====================================================================================

echo
echo "-------------------------"
echo "| Installing Postgres.. |"
echo "-------------------------"
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt update
sudo apt install postgresql -y

# =====================================================================================

echo
echo "-----------------------------------"
echo "| Installing Mongo DB and Compass |"
echo "-----------------------------------"
sudo apt install gnupg -y
wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
sudo apt update
sudo apt install mongodb-org -y
sudo systemctl enable mongod
wget -P $temp_folder_path/ $mongoCompass_download_link
sudo dpkg -i $temp_folder_path/$mongoCompassVersion
#in case dependency problems:
sudo apt --fix-broken install -y
#and reinstall:
sudo dpkg -i $temp_folder_path/$mongoCompassVersion

# =====================================================================================

echo
echo "-----------------------"
echo "| Installing Docker.. |"
echo "-----------------------"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io -y

# =====================================================================================

echo
echo "------------------------------------------"
echo "| Installing VMware Workstation Player.. |"
echo "------------------------------------------"
# Need user input
sudo apt install build-essential -y
wget -P $temp_folder_path/ $VMware_download_link
sudo chmod +x $temp_folder_path/VMware-Player*
sudo $temp_folder_path/VMware-Player*

# =====================================================================================

echo
echo "-----------------------------------"
echo "| Installing Franz Communicator.. |"
echo "-----------------------------------"
wget -P $temp_folder_path/ $franz_download_link
sudo apt install $temp_folder_path/$franzVersion -y

# =====================================================================================

echo
echo "---------------------"
echo "| Installing Zoom.. |"
echo "---------------------"
wget -P $temp_folder_path/ $zoom_download_link
sudo apt install $temp_folder_path/$zoomVersion -y

# =====================================================================================

echo
echo "---------------------------------"
echo "| Installing Angry IP Scanner.. |"
echo "---------------------------------"
wget -P $temp_folder_path/ $angryIpScanner_download_link
sudo apt install $temp_folder_path/$angryIpScannerVersion -y

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
echo "----------------------------"
echo "| Installing Tor Browser.. |"
echo "----------------------------"
wget -P /home/ $tor_download_link
tar -xf /home/$torVersion
sudo chmod +x /home/$torVersion
/home/$torVersion/start-tor-browser.desktop --register-app

# =====================================================================================

echo
echo "------------------------"
echo "| Installing NordVPN.. |"
echo "------------------------"
sh <(wget -P $temp_folder_path/ -qO - https://downloads.nordcdn.com/apps/linux/install.sh)

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
wget -P $temp_folder_path/ $minikube_download_link
sudo dpkg -i minikube_latest_amd64.deb

# =====================================================================================

echo
echo "--------------------------"
echo "| Installing BitWarden.. |"
echo "--------------------------"
wget -P $temp_folder_path/ $bitWarden_download_link
chmod a+x $temp_folder_path/$bitWardenVersion
sudo mkdir /opt/bitwarden
sudo cp $temp_folder_path/$bitWardenVersion /opt/bitwarden/bitwarden.AppImage
sudo cp ./icons/bitwarden.png /opt/bitwarden/bitwarden.png
sudo cp ./shortcuts/bitwarden.desktop /usr/share/applications/bitwarden.desktop

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
sudo apt autoremove  -y

echo
echo "-------------------------------------------------"
echo "| Opening extension install pages in browsers.. |"
echo "-------------------------------------------------"
xdg-settings set default-web-browser brave-browser.desktop

brave https://chrome.google.com/webstore/detail/gnome-shell-integration/gphhapmejobijbbhgpjhcjognlahblep &>/dev/null & disown %%
brave https://extensions.gnome.org/extension/307/dash-to-dock/ &>/dev/null & disown %%

firefox https://addons.mozilla.org/pl/firefox/addon/gnome-shell-integration/ &>/dev/null & disown %%

echo "-------------------------------"
echo "| Running extension manager.. |"
echo "-------------------------------"
extensions-manager
