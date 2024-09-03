
lutrisVersion="lutris_0.5.16_all.deb"
lutris_download_link="https://github.com/lutris/lutris/releases/download/v0.5.16/$lutrisVersion"

echo
echo "---------------------"
echo "| Installing Wine.. |"
echo "---------------------"

sudo dpkg --add-architecture i386
sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
sudo wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/mantic/winehq-mantic.sources
sudo apt update
sudo apt install --install-recommends winehq-stable

sudo apt install wine64 winbind winetricks

wine winecfg &

winetricks install
wget  https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x winetricks
sudo mv -v winetricks /usr/local/bin
sudo apt-get install cabextract p7zip unrar unzip wget zenity

lutris install
wget "$lutris_download_link" -cO "$temp_folder_path"/"$lutrisVersion"
sudo apt install "$temp_folder_path"/"$lutrisVersion" -y
