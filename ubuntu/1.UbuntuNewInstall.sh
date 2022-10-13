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

VMware_download_link=https://download3.vmware.com/software/player/file/VMware-Player-16.1.0-17198959.x86_64.bundle

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
sudo apt install gnome-tweak-tool gnome-shell-extensions chrome-gnome-shell -y

echo
echo "Installing grub-customizer.."
sudo add-apt-repository ppa:danielrichter2007/grub-customizer -y
sudo apt-get install grub-customizer -y

echo
echo "Installing Open Java JDK.."
sudo apt install openjdk-14-jdk -y

echo
echo "Installing VirtualBox.."
sudo apt install virtualbox -y

echo
echo "Installing apps.."
sudo apt install maven gradle git -y
sudo apt install wget curl vim nano -y
sudo apt-get install libmysql-java -y
sudo apt install snapd -y

echo
echo "Installing snaps.."
sudo snap install okular
sudo snap install freecad
sudo snap install discord
sudo snap install cura-slicer
sudo snap install gimp
sudo snap install mysql-workbench-community
sudo snap install android-studio --classic
sudo snap install intellij-idea-ultimate --classic
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
echo "Installing MySQL.."
# install mysql and give password to installer
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_PASSWORD"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_PASSWORD"
sudo apt install mysql-server -y

echo
echo "Installing Docker.."
sudo apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common -y
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io -y

echo 
echo "Installing gradle.."
wget -P $temp_folder_path/ $gradle_download_link
sudo unzip -d /opt/gradle $temp_folder_path/gradle-${GRADLE_VERSION}-bin.zip
sudo ln -s /opt/gradle/gradle-${GRADLE_VERSION} /opt/gradle/latest

echo
echo "Opening extension install pages in browsers.."
firefox https://addons.mozilla.org/pl/firefox/addon/gnome-shell-integration/ &>/dev/null & disown %%
firefox https://extensions.gnome.org/extension/307/dash-to-dock/ &>/dev/null & disown %%
firefox https://extensions.gnome.org/extension/723/pixel-saver/ &>/dev/null & disown %%

brave https://chrome.google.com/webstore/detail/lastpass-free-password-ma/hdokiejnpimakedhajhdlcegeplioahd &>/dev/null & disown %%

echo
echo "Opening apps required manual install.."
brave https://www.pcloud.com/download-free-online-cloud-file-storage.html &>/dev/null & disown %%
brave https://www.blackmagicdesign.com/products/davinciresolve/ &>/dev/null & disown %%

echo
echo "Installing VMware Workstation Player.."
# Need user input
sudo apt install build-essential -y
wget -P $temp_folder_path/ $VMware_download_link
sudo chmod +x $temp_folder_path/VMware-Player*
sudo $temp_folder_path/VMware-Player*

echo
echo "Cleaning.."
# unpausing updating grub
sudo apt-mark unhold grub*
rm -R $temp_folder_path

# echo
# echo "Running dist-upgrade.."
# sudo apt-get dist-upgrade

# =====================================================================================

# echo
# echo
# echo
# echo
# echo "oracle java jdk installation"

# # extraction jdk (u must have it downloaded in folder same as this script)
# sudo mkdir /usr/lib/jvm
# sudo tar -zxvf jdk-8u161-linux-x64.tar.gz -C /usr/lib/jvm

# #update PATH file
# PATH=$(cat <<EOF
# JAVA_HOME=/usr/lib/jvm/jdk1.8.0_161
# PATH=$PATH:$HOME/bin:$JAVA_HOME/bin
# export JAVA_HOME
# export JRE_HOME
# export PATH
# EOF
# )
# #sudo chmod 777 /etc/profile
# sudo echo "${PATH}" >> /etc/profile

# #tell the system that the new Oracle Java version is available
# sudo update-alternatives --install /usr/bin/java java /usr/lib/jvm/jdk1.8.0_161/bin/java 2000
# sudo update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/jdk1.8.0_161/bin/javac 2000
# sudo update-alternatives --install /usr/bin/javaws javaws /usr/lib/jvm/jdk1.8.0_161/bin/javaws 2000

# #make Oracle Java JDK as default
# sudo update-alternatives --set java /usr/lib/jvm/jdk1.8.0_161/bin/java
# sudo update-alternatives --set javac /usr/lib/jvm/jdk1.8.0_161/bin/javac
# sudo update-alternatives --set javaws /usr/lib/jvm/jdk1.8.0_161/bin/javaws

# #Reload sytem wide PATH /etc/profile
# source /etc/profile