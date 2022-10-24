#!/usr/bin/env bash

echo "-------------"
echo "| Testing.. |"
echo "-------------"

temp_folder_path="$HOME/.lukkInstall"
MYSQL_PASSWORD="Lukk1234"
PGPASSWORD="$MYSQL_PASSWORD"

chromeVersion="google-chrome-stable_current_amd64.deb"
chrome_download_link="https://dl.google.com/linux/direct/$chromeVersion"

githubDesktopVersion="GitHubDesktop-linux-3.0.6-linux1.deb"
githubDesktop_download_link="https://github.com/shiftkey/desktop/releases/download/release-3.0.6-linux1/$githubDesktopVersion"

intellijChannelVersion="2020.3/stable"

mongoCompassVersion="mongodb-compass_1.33.1_amd64.deb"
mongoCompass_download_link="https://downloads.mongodb.com/compass/$mongoCompassVersion"

minikubeVersion="minikube_latest_amd64.deb"
minikube_download_link="https://storage.googleapis.com/minikube/releases/latest/$minikubeVersion"

VMwareVersion="VMware-Player-Full-16.2.4-20089737.x86_64.bundle"
VMware_download_link="https://download3.vmware.com/software/WKST-PLAYER-1624/$VMwareVersion"

franzVersion="franz_5.9.2_amd64.deb"
franz_download_link="https://github.com/meetfranz/franz/releases/download/v5.9.2/$franzVersion"

zoomVersion="zoom_amd64.deb"
zoom_download_link="https://zoom.us/client/5.12.2.4816/$zoomVersion"

bitWardenVersion="Bitwarden-2022.10.0-x86_64.AppImage"
bitWarden_download_link="https://github.com/bitwarden/clients/releases/download/desktop-v2022.10.0/$bitWardenVersion"

angryIpScannerVersion="ipscan_3.8.2_amd64.deb"
angryIpScanner_download_link="https://github.com/angryip/ipscan/releases/download/3.8.2/$angryIpScannerVersion"

nordvpnVersion="nordvpn-release_1.0.0_all.deb"
nordvpn_download_link="https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/$nordvpnVersion"

postmanVersion="linux64"
postman_download_link="https://dl.pstmn.io/download/latest/$postmanVersion"

torVersion="tor-browser-linux64-11.5.4_en-US.tar.xz"
tor_download_link="https://www.torproject.org/dist/torbrowser/11.5.4/$torVersion"

# =====================================================================================

# examples
# wget $app_download_link -cO $temp_folder_path/$appVersion
# tar -xf $temp_folder_path/app.tar.gz -C $temp_folder_path/
# unzip -o $temp_folder_path/app.zip -d $temp_folder_path/appFolder/
# gnome-extensions enable <UUID>
# echo 'export PATH="$PATH:<pathToFile>"' >> ~/.bashrc
# gsettings get org.gnome.shell favorite-apps

# =====================================================================================

