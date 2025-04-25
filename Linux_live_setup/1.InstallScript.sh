#!/bin/bash

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

exodusVersion="exodus-linux-x64-25.13.6.deb"
exodus_download_link="https://downloads.exodus.com/releases/$exodusVersion"

chromeVersion="google-chrome-stable_current_amd64.deb"
chrome_download_link="https://dl.google.com/linux/direct/$chromeVersion"

appimagelauncherVersion="appimagelauncher_2.2.0-travis995.0f91801.bionic_amd64.deb"
appimagelauncher_donwload_link="https://github.com/TheAssassin/AppImageLauncher/releases/download/v2.2.0/$appimagelauncherVersion"

ledgerVersion="ledger-app.AppImage"
ledger_download_link="https://download.live.ledger.com/latest/linux"

trezorVersion="Trezor-Suite-25.4.2-linux-x86_64.AppImage"
trezor_download_link="https://data.trezor.io/suite/releases/desktop/latest/$trezorVersion"

torVersion="tor-browser-linux-x86_64-14.5.tar.xz"
tor_download_link="https://dist.torproject.org/torbrowser/14.5/$torVersion"

dashToDock_link="https://extensions.gnome.org/extension/307/dash-to-dock/"

startOverlayInApplicationView_link="https://extensions.gnome.org/extension/5040/start-overlay-in-application-view/"

gnomeShellIntegrationFirefoxExtension="https://addons.mozilla.org/en-US/firefox/addon/gnome-shell-integration/"

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
  sudo apt --fix-broken install -y
  sudo apt update && sudo apt full-upgrade -y
  sudo apt autoremove -y

} || handle_error "Updating system"

# =====================================================================================

echo
echo "-----------------------------------"
echo "| Installing App-image Launcher.. |"
echo "-----------------------------------"
{
  wget $appimagelauncher_donwload_link -cO "$temp_folder_path"/"$appimagelauncherVersion"
  sudo chmod a+x "$temp_folder_path"/"$appimagelauncherVersion"
  sudo apt install "$temp_folder_path"/"$appimagelauncherVersion"

} || handle_error "Installing App-image Launcher"

# =====================================================================================

echo
echo "---------------------"
echo "| Installing apps.. |"
echo "---------------------"
{
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
  sudo apt install gnome-browser-connector -y
  sudo apt install gnome-shell-extension-manager

} || handle_error "Installing apps"

# =====================================================================================

echo
echo "----------------------------"
echo "| Installing Security apps |"
echo "----------------------------"
{
  sudo apt install lynis -y
  sudo apt install chkrootkit -y
  sudo apt install clamav -y

} || handle_error "Installing Security apps"

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
echo "-----------------------"
echo "| Installing Exodus.. |"
echo "-----------------------"

{
  wget $exodus_download_link -cO "$temp_folder_path"/"$exodusVersion"
  sudo chmod a+x "$temp_folder_path"/"$exodusVersion"
  sudo apt install "$temp_folder_path"/"$exodusVersion"

} || handle_error "Installing Exodus"

# =====================================================================================

echo
echo "----------------------"
echo "| Installing snaps.. |"
echo "----------------------"

{
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

} || handle_error "Installing snaps"

# =====================================================================================

echo
echo "------------------------"
echo "| Installing Chrome... |"
echo "------------------------"

{
  wget "$chrome_download_link" -cO "$temp_folder_path"/"$chromeVersion"
  sudo apt install "$temp_folder_path"/"$chromeVersion"

} || handle_error "Installing Chrome"

# =====================================================================================

echo
echo "------------------------"
echo "| Installing Firefox.. |"
echo "------------------------"
# NOT ALL FUNCTIONALITY IS WORKING WITH SNAP INSTALLATION (e.g. Postman interceptor, KeepassXC)

{
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

} || handle_error "Installing Firefox"

# =====================================================================================

echo
echo "----------------------"
echo "| Installing Brave.. |"
echo "----------------------"
# NOT ALL FUNCTIONALITY IS WORKING WITH SNAP INSTALLATION (e.g. Postman interceptor, KeepassXC)
{
  sudo apt install apt-transport-https curl -y
  sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list
  sudo apt update
  sudo apt install brave-browser -y

} || handle_error "Installing Brave"

# =====================================================================================

echo
echo "-----------------------"
echo "| Installing Ledger.. |"
echo "-----------------------"

{
  wget "$ledger_download_link" -cO "$temp_folder_path"/"$ledgerVersion"
  sudo chmod +x "$temp_folder_path"/"$ledgerVersion"
  wget -q -O - "https://raw.githubusercontent.com/LedgerHQ/udev-rules/master/add_udev_rules.sh" | sudo bash

} || handle_error "Installing Ledger"

# =====================================================================================

echo
echo "-----------------------"
echo "| Installing Trezor.. |"
echo "-----------------------"

{
  wget "$trezor_download_link" -cO "$temp_folder_path"/"$trezorVersion"
  sudo chmod +x "$temp_folder_path"/"$trezorVersion"
  wget -q -O "$temp_folder_path"/trezor-udev_2_all.deb https://data.trezor.io/udev/trezor-udev_2_all.deb
  sudo apt install "$temp_folder_path"/trezor-udev_2_all.deb

} || handle_error "Installing Trezor"

# =====================================================================================

echo
echo "--------------------------"
echo "| Installing KeepassXC.. |"
echo "--------------------------"

{
  # KeepassXC installed already via snap
  sudo chmod +x ./config/keepassxc-snap-helper.sh
  ./config/keepassxc-snap-helper.sh

  sudo cp ./shortcuts/startK.desktop "$HOME"/.config/autostart/startK.desktop

} || handle_error "Installing KeepassXC"

# =====================================================================================

echo
echo "---------------------"
echo "| Running upgrade.. |"
echo "---------------------"

{
  sudo apt update
  sudo apt-get full-upgrade -y
  sudo apt autoremove -y
  source ~/.bashrc

} || handle_error "Running upgrade"

# =====================================================================================

echo
echo "-------------------------------"
echo "| Copying Manual to Desktop.. |"
echo "-------------------------------"

{
  cp ./manual/Manual.pdf ~/Desktop/Manual.pdf

} || handle_error "Copying Manual to Desktop"

# =====================================================================================

echo
echo "----------------------------"
echo "| Installing Tor Browser.. |"
echo "----------------------------"

{
  wget "$tor_download_link" -cO "$temp_folder_path"/"$torVersion"
  sudo mkdir /opt/tor
  sudo tar -xf "$temp_folder_path"/"$torVersion" -C /opt/tor/
  sudo chmod +rwx -R /opt/tor/
  sudo chown lukk -R /opt/tor/
  cd /opt/tor/tor-browser_en-US/
  ./start-tor-browser.desktop --register-app
  cd ~

} || handle_error "Installing Tor Browser"

# =====================================================================================

echo
echo "-------------------------------------------------"
echo "| Opening extension install pages in browsers.. |"
echo "-------------------------------------------------"

{
  xdg-settings set default-web-browser brave-browser.desktop

  #firefox because of brave first launch will ask about being default and won't open all pages
  firefox "$dashToDock_link" &>/dev/null & disown %%
  firefox "$startOverlayInApplicationView_link" &>/dev/null & disown %%
  firefox "$gnomeShellIntegrationFirefoxExtension" &>/dev/null & disown %%

} || handle_error "Opening extension install pages in browsers"

# =====================================================================================

echo
echo "---------------------------"
echo "| Running AppImage apps.. |"
echo "---------------------------"

{
  # app-image launcher will intercept this copy or move it to its default folder and install
  "$temp_folder_path"/"$ledgerVersion"
  "$temp_folder_path"/"$trezorVersion"

} || handle_error "Running AppImage apps"

# =====================================================================================

echo
echo "----------------------------------------------------------------------"
echo "| Install gnome extensions opened in browser via Extension Manager.. |"
echo "----------------------------------------------------------------------"

{
  extension-manager & disown

} || handle_error "Running Extension Manager"
