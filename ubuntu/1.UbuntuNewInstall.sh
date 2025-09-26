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

appImageLauncherVersion="appimagelauncher_2.2.0-travis995.0f91801.bionic_amd64.deb"
appImageLauncher_download_link="https://github.com/TheAssassin/AppImageLauncher/releases/download/v2.2.0/$appImageLauncherVersion"

dockerDesktopVersion="docker-desktop-amd64.deb"
dockerDesktop_download_link="https://desktop.docker.com/linux/main/amd64/$dockerDesktopVersion"

VMwareVersion="VMware-Player-Full-17.5.0-22583795.x86_64.bundle"
VMware_download_link="https://download3.vmware.com/software/WKST-PLAYER-1750/$VMwareVersion"

minikubeVersion="minikube_latest_amd64.deb"
minikube_download_link="https://storage.googleapis.com/minikube/releases/latest/$minikubeVersion"

beeperVersion="beeper.AppImage"
beeper_download_link="https://api.beeper.com/desktop/download/linux/x64/stable/com.automattic.beeper.desktop"

jetbrainsToolboxVersion="jetbrains-toolbox-2.9.0.56191"
jetbrainsToolbox_download_link="https://download.jetbrains.com/toolbox/$jetbrainsToolboxVersion.tar.gz"

teamViewerVersion="teamviewer_amd64.deb"
teamViewer_download_link="https://download.teamviewer.com/download/linux/$teamViewerVersion"

veraCryptVersion="veracrypt-1.26.24-Ubuntu-24.04-amd64.deb"
veraCrypt_download_link="https://launchpad.net/veracrypt/trunk/1.26.24/+download/$veraCryptVersion"

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
  sudo apt install openjdk-21-jdk -y

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
  sudo apt install scrcpy -y

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
echo "-----------------------------------"
echo "| Installing Flatpak.. |"
echo "-----------------------------------"
{
  sudo apt install flatpak -y
  sudo apt install gnome-software-plugin-flatpak -y
  source /etc/profile.d/flatpak.sh
  sudo flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  sudo flatpak update --system -y
  sudo flatpak install flathub com.github.tchx84.Flatseal

} || handle_error "Installing Flatpak"

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
  sudo snap install flutter --classic
  sudo snap install kubectl --classic
  sudo snap install kontena-lens --classic
  sudo snap install helm --classic
  sudo snap install node --classic
  sudo snap install postman

  sudo snap install freecad
  sudo snap install cura-slicer

  sudo snap install sublime-text --classic
  sudo snap install okular
  sudo snap install trello-desktop
  sudo snap install obsidian --classic
  sudo snap install bitwarden

  sudo snap install steam

  sudo snap install gimp
  sudo snap install krita
  sudo snap install spotify
  sudo snap install vlc

  sudo snap install discord
  sudo snap install telegram-desktop
  sudo snap install slack
  sudo snap install teams

  sudo snap install brave

} || handle_error "Installing snaps"

# =====================================================================================


echo
echo "-----------------------------"
echo "| Installing flatpak apps.. |"
echo "-----------------------------"

{
  sudo flatpak install --system flathub org.angryip.ipscan -y
  sudo flatpak install --system flathub us.zoom.Zoom -y
  sudo flatpak install --system flathub com.google.Chrome -y
  sudo flatpak install --system flathub io.github.shiftey.Desktop -y
  sudo flatpak install --system flathub com.wps.Office -y
  sudo flatpak install --system flathub org.torproject.torbrowser-launcher -y

} || handle_error "Installing flatpak apps"

# =====================================================================================

echo
echo "-------------------------------"
echo "| Installing Docker Desktop.. |"
echo "-------------------------------"
{
  # Add Docker's official GPG key:
  sudo apt update
  sudo apt install ca-certificates curl -y
  sudo install -m 0755 -d /etc/apt/keyrings-y
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # Add the repository to Apt sources:
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update

  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # This automates the setup of a GPG key and 'pass' for Docker Desktop login.
  # Prompt for a secure passphrase
  read -s -p "Enter a new passphrase for your GPG key: " GPG_PASSPHRASE
  echo # Newline after password input

  if [ -z "$GPG_PASSPHRASE" ]; then
      echo "Error: Passphrase cannot be empty."
      exit 1
  fi

  # below need to be formated as it is WITHOUT indent ! due to heredoc syntax
  cat > gpg_params <<EOF
%echo Generating a GPG key for Docker...
Key-Type: RSA
Key-Length: 3072
Subkey-Type: RSA
Subkey-Length: 3072
Name-Real: Docker Login Key
Name-Email: docker-login@localhost
Expire-Date: 0
Passphrase: ${GPG_PASSPHRASE}
%commit
%echo done
EOF

  gpg --batch --gen-key gpg_params
  KEY_ID=$(gpg --list-secret-keys --with-colons | grep '^sec' | tail -n 1 | cut -d: -f5)

  if [ -z "$KEY_ID" ]; then
      echo "Error: Could not find the new GPG Key ID."
      rm gpg_params # Clean up
      exit 1
  fi

  pass init "$KEY_ID"
  rm gpg_params

  sudo systemctl start docker
  sudo systemctl enable docker

  wget "$dockerDesktop_download_link" -cO "$temp_folder_path"/"$dockerDesktopVersion"
  sudo apt install "$temp_folder_path"/"$dockerDesktopVersion" -y

} || handle_error "Installing Docker Desktop"


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

  sudo flatpak --system install flathub com.mongodb.Compass -y

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

} || handle_error "Installing KeepassXC"

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
echo "----------------------------------"
echo "| Installing Jetbrains Toolbox.. |"
echo "----------------------------------"

{
  wget "$jetbrainsToolbox_download_link" -cO "$temp_folder_path/$jetbrainsToolboxVersion"
  sudo mkdir -p /opt/jetbrains
  sudo tar -xvf "$temp_folder_path/$jetbrainsToolboxVersion" -C /opt/jetbrains
  /opt/jetbrains/"$jetbrainsToolboxVersion"/bin/jetbrains-toolbox &>/dev/null & disown %%

} || handle_error "Installing Jetbrains Toolbox"

# =====================================================================================

echo
echo "---------------------------"
echo "| Installing TeamViewer.. |"
echo "---------------------------"
{
  wget "$teamViewer_download_link" -cO "$temp_folder_path/$teamViewerVersion"
  sudo apt install "$temp_folder_path/$teamViewerVersion" -y

} || handle_error "Installing TeamViewer"

# =====================================================================================

echo
echo "--------------------------"
echo "| Installing VeraCrypt.. |"
echo "--------------------------"
{
  wget "$veraCrypt_download_link" -cO "$temp_folder_path/$veraCryptVersion"
  sudo apt install "$temp_folder_path/$veraCryptVersion" -y

} || handle_error "Installing VeraCrypt"

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
  sudo snap refresh
  sudo flatpak update --system -y

  # shellcheck source=/home/username/.bashrc
  source "$HOME/.bashrc"

} || handle_error "Running upgrade"


# =====================================================================================

echo "-------------------------------"
echo "| Running extension manager.. |"
echo "-------------------------------"
{
  extension-manager & disown

} || handle_error "Running extension manager"

# =====================================================================================

# Final message indicating where the error log is located
echo "Installation completed, errors logged in $ERROR_LOG, if any."

# =====================================================================================

echo
echo "--------------------"
echo "| Reboot needed !! |"
echo "--------------------"

# =====================================================================================
