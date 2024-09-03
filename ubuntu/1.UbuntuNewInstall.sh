#!/usr/bin/env bash

# Log file for errors
ERROR_LOG="$HOME/install-errors.txt"

# Function to handle errors
handle_error() {
    echo -e "Error encountered during: $1\n" | tee -a "$ERROR_LOG" >&2
    echo "=====================================================================================" | tee -a "$ERROR_LOG"
}

# Ensure log file is empty at the start
true > "$ERROR_LOG"

echo "--------------------------"
echo "| Setting env variable.. |"
echo "--------------------------"

temp_folder_path="$HOME/.lukkInstall"

MYSQL_PASSWORD="Lukk1234"

appImageLauncherVersion="appimagelauncher_2.2.0-travis995.0f91801.bionic_amd64.deb"
appImageLauncher_download_link="https://github.com/TheAssassin/AppImageLauncher/releases/download/v2.2.0/$appImageLauncherVersion"

chromeVersion="google-chrome-stable_current_amd64.deb"
chrome_download_link="https://dl.google.com/linux/direct/$chromeVersion"

githubDesktopVersion="GitHubDesktop-linux-3.0.6-linux1.deb"
githubDesktop_download_link="https://github.com/shiftkey/desktop/releases/download/release-3.0.6-linux1/$githubDesktopVersion"

mongoCompassVersion="mongodb-compass_1.43.5_amd64.deb"
mongoCompass_download_link="https://downloads.mongodb.com/compass/$mongoCompassVersion"

dockerDesktopVersion="docker-desktop-amd64.deb"
dockerDesktop_download_link="https://desktop.docker.com/linux/main/amd64/$dockerDesktopVersion"

VMwareVersion="VMware-Player-Full-17.5.0-22583795.x86_64.bundle"
VMware_download_link="https://download3.vmware.com/software/WKST-PLAYER-1750/$VMwareVersion"

zoomVersion="zoom_amd64.deb"
zoom_download_link="https://zoom.us/client/5.17.5.2543/$zoomVersion"

angryIpScannerVersion="ipscan_3.9.1_amd64.deb"
angryIpScanner_download_link="https://github.com/angryip/ipscan/releases/download/3.9.1/$angryIpScannerVersion"

minikubeVersion="minikube_latest_amd64.deb"
minikube_download_link="https://storage.googleapis.com/minikube/releases/latest/$minikubeVersion"

postmanVersion="linux64"
postman_download_link="https://dl.pstmn.io/download/latest/$postmanVersion"

torVersion="tor-browser-linux-x86_64-13.0.10.tar.xz"
tor_download_link="https://www.torproject.org/dist/torbrowser/13.0.10/$torVersion"

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
{
    mkdir -p "$temp_folder_path"

} || handle_error "Making temp folder"

# =====================================================================================

echo
echo "---------------------"
echo "| Updating system.. |"
echo "---------------------"
{
    sudo apt --fix-broken install -y &&
    sudo apt update &&
    sudo apt full-upgrade -y &&
    sudo apt autoremove -y

} || handle_error "Updating system"

# =====================================================================================

echo
echo "------------------------------"
echo "| Installing Open Java JDK.. |"
echo "------------------------------"
{
    sudo apt install openjdk-17-jdk openjdk-17-jre -y

} || handle_error "Installing Open Java JDK"

# =====================================================================================

echo
echo "---------------------"
echo "| Installing apps.. |"
echo "---------------------"
{
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
  # for Google Drive sync
  sudo apt install rclone -y

} || handle_error "Installing apps"

# =====================================================================================

echo
echo "-----------------------------------"
echo "| Installing App-image Launcher.. |"
echo "-----------------------------------"
{
    wget "$appImageLauncher_download_link" -cO "$temp_folder_path/$appImageLauncherVersion"
    sudo apt install "$temp_folder_path/$appImageLauncherVersion" -y

} || handle_error "Installing App-image Launcher"

# =====================================================================================

echo
echo "----------------------------"
echo "| Installing Gnome Tools.. |"
echo "----------------------------"
{
    sudo add-apt-repository universe -y
    sudo apt install gnome-tweaks gnome-online-accounts gnome-shell-extension-gsconnect -y
    sudo apt install gnome-shell-extension-manager gnome-shell-extensions chrome-gnome-shell -y
    sudo apt install gnome-calendar -y

} || handle_error "Installing Gnome Tools"

# =====================================================================================

echo
echo "--------------------------------"
echo "| Installing grub-customizer.. |"
echo "--------------------------------"
{
    sudo add-apt-repository ppa:danielrichter2007/grub-customizer -y
    sudo apt-get install grub-customizer -y

} || handle_error "Installing grub-customizer"

# =====================================================================================

echo
echo "----------------------"
echo "| Installing snaps.. |"
echo "----------------------"
{
  sudo snap install android-studio --classic
  sudo snap install flutter --classic
  sudo snap install kubectl --classic
  sudo snap install kontena-lens --classic
  sudo snap install helm --classic

  sudo snap install freecad
  sudo snap install cura-slicer

  sudo snap install sublime-text --classic
  sudo snap install onlyoffice-desktopeditors
  sudo snap install okular
  sudo snap install trello-desktop
  sudo snap install obsidian --classic
  sudo snap install bitwarden

  sudo snap install steam

  sudo snap install gimp
  sudo snap install spotify
  sudo snap install vlc

  sudo snap install discord
  sudo snap install skype --classic
  sudo snap install telegram-desktop
  sudo snap install slack
  sudo snap install teams

} || handle_error "Installing snaps"

# =====================================================================================

echo
echo "------------------------"
echo "| Installing Chrome... |"
echo "------------------------"
{
  wget "$chrome_download_link" -cO "$temp_folder_path"/"$chromeVersion" &&
  sudo apt install "$temp_folder_path"/"$chromeVersion" -y
} || handle_error "Installing Chrome"

# =====================================================================================

echo
echo "-------------------------------"
echo "| Installing GitHubDesktop... |"
echo "-------------------------------"
{
    sudo wget "$githubDesktop_download_link" -cO "$temp_folder_path/$githubDesktopVersion" &&
    sudo apt install -y gdebi-core &&
    sudo gdebi -n "$temp_folder_path/$githubDesktopVersion"
} || handle_error "Installing GitHub Desktop"

# =====================================================================================

echo
echo "-------------------------------------------"
echo "| Installing Intellij Idea... |"
echo "-------------------------------------------"
{
    sudo snap install intellij-idea-ultimate --classic
} || handle_error "Installing IntelliJ IDEA"

# =====================================================================================

echo
echo "-----------------------"
echo "| Installing Docker.. |"
echo "-----------------------"
{
  wget "$dockerDesktop_download_link" -cO "$temp_folder_path"/"$dockerDesktopVersion"
  sudo chmod +x "$temp_folder_path"/"$dockerDesktopVersion"

  sudo apt install ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # Add the repository to Apt sources:
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update

  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  sudo systemctl enable docker
  sudo systemctl start docker

  sudo groupadd docker || true
  sudo usermod -aG docker "$USER"
  newgrp docker

  mkdir -p "$HOME/.docker"

  # Set permissions on .docker directory
  sudo chown "$USER":"$USER" /home/"$USER"/.docker -R
  sudo chmod g+rwx "$HOME/.docker" -R

#  docker desktop has errors with permissions do not work now at all
#  sudo apt install "$temp_folder_path"/"$dockerDesktopVersion" -y

} || handle_error "Installing Docker"

# =====================================================================================

echo
echo "-------------------"
echo "| Installing SQL. |"
echo "-------------------"
{
    # Install MySQL and set root password
    sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_PASSWORD"
    sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_PASSWORD"
    sudo apt install mysql-server -y
    sudo snap install mysql-workbench-community

    # Avoid blocking workbench by Linux AppArmor
    sudo snap connect mysql-workbench-community:password-manager-service :password-manager-service

    # Install PostgreSQL
    sudo snap install postgresql

} || handle_error "Installing SQL"

# =====================================================================================

echo
echo "----------------------"
echo "| Installing NoSQL.. |"
echo "----------------------"
{
    docker pull mongodb/mongodb-community-server:latest
    docker run --name mongodb -p 27017:27017 -d mongodb/mongodb-community-server:latest

    # Copy MongoDB Docker startup shortcut to autostart
    cp ./shortcuts/mongo-docker-startup.desktop "$HOME/.config/autostart/"
    chmod +x "$HOME/.config/autostart/mongo-docker-startup.desktop"

    # Install MongoDB Compass
    wget "$mongoCompass_download_link" -cO "$temp_folder_path/$mongoCompassVersion"
    sudo dpkg -i "$temp_folder_path/$mongoCompassVersion"

    sudo apt --fix-broken install -y

    # Reinstall MongoDB Compass if needed
    sudo dpkg -i "$temp_folder_path/$mongoCompassVersion"

} || handle_error "Installing NoSQL"

# =====================================================================================

echo
echo "------------------------------------------"
echo "| Installing VMware Workstation Player.. |"
echo "------------------------------------------"
{
    sudo apt install build-essential -y
    wget "$VMware_download_link" -cO "$temp_folder_path/$VMwareVersion"
    sudo chmod +x "$temp_folder_path/$VMwareVersion"
    sudo "$temp_folder_path/$VMwareVersion"

} || handle_error "Installing VMware Workstation Player"

# =====================================================================================

echo
echo "---------------------"
echo "| Installing Zoom.. |"
echo "---------------------"
{
    wget "$zoom_download_link" -cO "$temp_folder_path/$zoomVersion"
    sudo apt install "$temp_folder_path/$zoomVersion" -y

} || handle_error "Installing Zoom"

# =====================================================================================

echo
echo "---------------------------------"
echo "| Installing Angry IP Scanner.. |"
echo "---------------------------------"
{
    wget "$angryIpScanner_download_link" -cO "$temp_folder_path/$angryIpScannerVersion"
    sudo apt install "$temp_folder_path/$angryIpScannerVersion" -y

} || handle_error "Installing Angry IP Scanner"

# =====================================================================================

echo
echo "-------------------------"
echo "| Installing minikube.. |"
echo "-------------------------"
{
    wget "$minikube_download_link" -cO "$temp_folder_path/$minikubeVersion"
    sudo dpkg -i "$temp_folder_path/$minikubeVersion"

} || handle_error "Installing minikube"

# =====================================================================================

echo
echo "--------------------------"
echo "| Installing KeepassXC.. |"
echo "--------------------------"
{
    sudo snap install keepassxc
    sudo chmod +x ./config/keepassxc-snap-helper.sh
    ./config/keepassxc-snap-helper.sh

} || handle_error "Installing KeepassXC"

# =====================================================================================

echo
echo "------------------------"
echo "| Installing Postman.. |"
echo "------------------------"
# NOT ALL FUNCTIONALITY IS WORKING WITH SNAP INSTALLATION (postman interceptor)
{
    wget "$postman_download_link" -cO "$temp_folder_path/$postmanVersion"
    sudo tar -xf "$temp_folder_path/$postmanVersion" -C "$temp_folder_path/"
    sudo cp -R "$temp_folder_path/Postman" /opt/postman/
    sudo mv /opt/postman/Postman /opt/postman/postman
    sudo cp ./shortcuts/postman.desktop /usr/share/applications/postman.desktop
    sudo chmod +x /usr/share/applications/postman.desktop

} || handle_error "Installing Postman"

# =====================================================================================
echo
echo "----------------------"
echo "| Installing Brave.. |"
echo "----------------------"
# NOT ALL FUNCTIONALITY IS WORKING WITH SNAP INSTALLATION (postman interceptor)
{
    sudo apt install apt-transport-https curl -y
    sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list
    sudo apt update
    sudo apt install brave-browser -y

} || handle_error "Installing Brave"

# =====================================================================================

echo
echo "----------------------------"
echo "| Installing Boot repair.. |"
echo "----------------------------"
{
    sudo add-apt-repository ppa:yannubuntu/boot-repair -y
    sudo apt update
    sudo apt install boot-repair -y

} || handle_error "Installing Boot repair"

# =====================================================================================

echo
echo "------------------------------"
echo "| Installing Speedtest CLI.. |"
echo "------------------------------"
{
    sudo apt install speedtest-cli
    sudo mkdir -p /opt/speedtest-cli
    sudo cp ./icons/speedtest.png /opt/speedtest-cli/speedtest.png
    sudo cp ./scripts/speedtest-starter.sh /opt/speedtest-cli/speedtest-starter.sh
    sudo chmod +x /opt/speedtest-cli/speedtest-starter.sh
    sudo cp ./shortcuts/speedtest.desktop /usr/share/applications/speedtest.desktop

} || handle_error "Installing Speedtest CLI"

# =====================================================================================

echo
echo "----------------------------"
echo "| Installing Tor Browser.. |"
echo "----------------------------"
{
    wget "$tor_download_link" -cO "$temp_folder_path/$torVersion"
    sudo mkdir -p /opt/tor
    sudo tar -xf "$temp_folder_path/$torVersion" -C /opt/tor/
    sudo chmod +rwx -R /opt/tor/
    sudo chown "$USER" -R /opt/tor/
    cd /opt/tor/tor-browser/ || exit
    ./start-tor-browser.desktop --register-app
    cd "$HOME" || exit

} || handle_error "Installing Tor Browser"

# =====================================================================================

echo
echo "-----------------------"
echo "| Installing Beeper.. |"
echo "-----------------------"
{
    wget "$beeper_download_link" -cO "$temp_folder_path/$beeperVersion"
    chmod +x "$temp_folder_path/$beeperVersion"
    # AppImage launcher will intercept this copy or move it to its default folder and install
    "$temp_folder_path/$beeperVersion"

} || handle_error "Installing Beeper"

# =====================================================================================

echo
echo "--------------"
echo "| Cleaning.. |"
echo "--------------"
{
    # Un-pausing updating grub
    sudo apt-mark unhold grub*
    sudo apt --fix-broken install -y

} || handle_error "Cleaning"

# =====================================================================================

echo
echo "---------------------"
echo "| Running upgrade.. |"
echo "---------------------"
{
    sudo apt update
    sudo apt-get full-upgrade -y
    sudo apt autoremove -y

    # shellcheck source=/home/username/.bashrc
    source "$HOME/.bashrc"

} || handle_error "Running upgrade"

# =====================================================================================

echo
echo "-------------------------------------------------"
echo "| Opening extension install pages in browsers.. |"
echo "-------------------------------------------------"
{
    xdg-settings set default-web-browser google-chrome.desktop

    google-chrome "$startOverlayInApplicationView_link" &>/dev/null & disown %%
    google-chrome "$gsconnect_link" &>/dev/null & disown %%
    google-chrome "$keepassXC_addon_link" &>/dev/null & disown %%
    google-chrome "$notification_addod_link" &>/dev/null & disown %%

} || handle_error "Opening extension install pages in browsers"

# =====================================================================================

echo "-------------------------------"
echo "| Running extension manager.. |"
echo "-------------------------------"
{
    extension-manager & disown

} || handle_error "Running extension manager"

# =====================================================================================

echo
echo "--------------------------------------"
echo "| Running Google Drive Sync Config.. |"
echo "| Proceed with all defaults.         |"
echo "--------------------------------------"
{
    mkdir -p "$HOME/Documents/gDrive"
    rclone config
    rclone copy gDrive: "$HOME/Documents/gDrive"

    # rclone mount will block terminal and only temporarily show files in folder, files will not be accessible offline
    # even with cache it can be problematic because cache will sometime delete unused files
    #rclone mount gDrive: "$HOME/Documents/gDrive"

} || handle_error "Running Google Drive Sync Config"

# =====================================================================================

# Final message indicating where the error log is located
echo "Installation completed, errors logged in $ERROR_LOG, if any."
