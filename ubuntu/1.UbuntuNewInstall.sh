#!/usr/bin/env bash

echo "Setting env variable.."

temp_folder_path=~/.lukkInstall

backgroud_path=/usr/share/backgrounds/wallpapers/forest-house.jpg
login_background_path=#000000

default_video_app=vlc_vlc.desktop
default_internetBrowser_app=brave_brave.desktop
default_pdf_app=okular_okular.desktop
default_word_app=wps-2019-snap_wps.desktop
default_excel_app=wps-2019-snap_et.desktop
default_presentation_app=wps-2019-snap_wpp.desktop

MYSQL_PASSWORD='Lukk1234'

VMware_download_link=https://www.vmware.com/go/getplayer-linux

echo
echo "Copying install files.."
mkdir $temp_folder_path
cp ./instalators/focalgdm3 $temp_folder_path/focalgdm3
cp -a ./wallpapers/ $temp_folder_path/wallpapers/
mv $temp_folder_path/wallpapers/wallpapers-config $temp_folder_path/wallpapers-config

# =====================================================================================

echo
echo "Updating system.."
sudo apt update && sudo apt full-upgrade -y

echo
echo "Installing Gnome Tweak Tools.."
sudo add-apt-repository universe -y
sudo apt install gnome-tweak-tool gnome-shell-extensions chrome-gnome-shell gnome-online-accounts -y

echo
echo "Installing grub-customizer.."
sudo add-apt-repository ppa:danielrichter2007/grub-customizer -y
sudo apt-get install grub-customizer -y

echo
echo "Installing Open Java JDK.."
sudo apt install openjdk-17-jdk openjdk-17-jre -y

echo
echo "Installing VirtualBox.."
sudo apt install virtualbox -y

echo
echo "Installing apps.."
sudo apt install maven gradle git -y
sudo apt install wget curl vim nano -y
sudo apt-get install libmysql-java -y
sudo apt install snapd -y
sudo apt-get install ca-certificates curl gnupg lsb-release

echo
echo "Installing snaps.."
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

echo
echo "Installing Intellij version 2020.3.4 .."
sudo snap install intellij-idea-ultimate --channel=2020.3/stable --classic

echo
echo "Installing MySQL.."
# install mysql and give password to installer
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_PASSWORD"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_PASSWORD"
sudo apt install mysql-server -y

echo
echo "Installing Docker.."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io -y

echo
echo "Installing Kubernetes.."
snap install kubectl --classic

echo
echo "Installing minikube.."
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube_latest_amd64.deb
sudo dpkg -i minikube_latest_amd64.deb

echo
echo "Opening extension install pages in browsers.."
firefox https://addons.mozilla.org/pl/firefox/addon/gnome-shell-integration/ &>/dev/null & disown %%
firefox https://extensions.gnome.org/extension/307/dash-to-dock/ &>/dev/null & disown %%

echo
echo "Installing VMware Workstation Player.."
# Need user input
sudo apt install build-essential -y
wget -P $temp_folder_path/ $VMware_download_link
sudo chmod +x $temp_folder_path/VMware-Player*
sudo $temp_folder_path/VMware-Player*

echo
echo "Cleaning.."
# un-pausing updating grub
sudo apt-mark unhold grub*
rm -R $temp_folder_path

 echo
 echo "Running upgrade.."
 sudo apt update
 sudo apt-get full-upgrade
