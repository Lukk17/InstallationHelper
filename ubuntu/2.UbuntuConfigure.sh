#!/usr/bin/env bash

# =====================================================================================

echo
echo "--------------------------"
echo "| Setting env variable.. |"
echo "--------------------------"

background_path=/usr/share/backgrounds/wallpapers/forest-house.jpg

login_background_color=#000000
login_background_image=/usr/share/backgrounds/wallpapers/forest.jpg

temp_folder_path=~/.lukkInstall

gdmBackgroundVersion="main.tar.gz"
gdmBackground_download_link="https://github.com/PRATAP-KUMAR/ubuntu-gdm-set-background/archive/$gdmBackgroundVersion"

script_location=~/Documents

default_video_app=vlc_vlc.desktop
default_internetBrowser_app=brave-browser.desktop
default_pdf_app=okular_okular.desktop
default_word_app=wps-2019-snap_wps.desktop
default_excel_app=wps-2019-snap_et.desktop
default_presentation_app=wps-2019-snap_wpp.desktop

zsh_download_link="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

spaceshipTheme_download_link="https://github.com/spaceship-prompt/spaceship-prompt.git"
powerlevel10kTheme_download_link="https://github.com/romkatv/powerlevel10k.git"

nerdFontName="Hack Regular Nerd Font Complete.ttf"
nerdFont_download_link="https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/Hack/Regular/complete/Hack%20Regular%20Nerd%20Font%20Complete.ttf"

mesloRegularName="MesloLGS NF Regular.ttf"
mesloRegular_download_link="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"

mesloBoldName="MesloLGS NF Bold.ttf"
mesloBold_download_link="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"

mesloItalicName="MesloLGS NF Italic.ttf"
mesloItalic_download_link="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"

mesloBoldItalicName="MesloLGS NF Bold Italic.ttf"
mesloBoldItalic_download_link="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"

# =====================================================================================

echo
echo "---------------------------"
echo "| Copying install files.. |"
echo "---------------------------"

mkdir "$temp_folder_path"
cp -a ./wallpapers/ "$temp_folder_path"/wallpapers/
cp "$temp_folder_path"/wallpapers/wallpapers-config "$temp_folder_path"/wallpapers-config


# =====================================================================================

echo
echo "-----------------------------"
echo "| Creating files template.. |"
echo "-----------------------------"

touch ~/Templates/file
touch ~/Templates/text.txt
touch ~/Templates/Document.docx
touch ~/Templates/Presentation.pptx
touch ~/Templates/Spreadsheet.xlsx

# =====================================================================================

echo
echo "-----------------------"
echo "| Setting dark mode.. |"
echo "-----------------------"

gsettings set org.gnome.shell.ubuntu color-scheme prefer-dark
gsettings set org.gnome.desktop.interface gtk-theme Yaru-dark # Legacy apps, can specify an accent such as Yaru-olive-dark
gsettings set org.gnome.desktop.interface color-scheme prefer-dark # new apps
gsettings reset org.gnome.shell.ubuntu color-scheme # if changed above



# =====================================================================================

echo
echo "-----------------------"
echo "| Setting wallpaper.. |"
echo "-----------------------"

sudo cp -a "$temp_folder_path"/wallpapers/ /usr/share/backgrounds/wallpapers/
gsettings set org.gnome.desktop.background picture-uri-dark "$background_path"
gsettings set org.gnome.desktop.background picture-uri "$background_path"

# =====================================================================================

echo
echo "-------------------------------"
echo "| Changing login background.. |"
echo "-------------------------------"

wget -P "$temp_folder_path"/ "$gdmBackground_download_link"
tar -xf "$temp_folder_path"/"$gdmBackgroundVersion" -C "$temp_folder_path"/
sudo cp "$temp_folder_path"/ubuntu-gdm-set-background-main/ubuntu-gdm-set-background "$script_location"/
sudo apt update
sudo apt install libglib2.0-dev-bin -y
# change to color:
sudo "$script_location"/ubuntu-gdm-set-background --color "$login_background_color"
# change to wallpaper:
#sudo $script_location/ubuntu-gdm-set-background --image "$login_background_image"
# to reset
#sudo script_location/ubuntu-gdm-set-background --reset

# =====================================================================================

echo
echo "------------------------------"
echo "| Showing seconds on clock.. |"
echo "------------------------------"

gsettings set org.gnome.desktop.interface clock-show-seconds true

# =====================================================================================

echo
echo "-----------------------------------------------"
echo "| Configuring shortcut for Android Emulator.. |"
echo "-----------------------------------------------"
sudo mkdir /opt/emulator
sudo cp ./icons/android.png /opt/emulator/android.png
sudo cp ./shortcuts/android.desktop /usr/share/applications/android.desktop

# =====================================================================================

echo
echo "---------------------"
echo "| Configuring WPS.. |"
echo "---------------------"

sudo snap connect wps-2019-snap:cups-control :cups-control
sudo snap connect wps-2019-snap:alsa :alsa
sudo snap connect wps-2019-snap:pulseaudio :pulseaudio
sudo snap connect wps-2019-snap:removable-media :removable-media

# =====================================================================================

echo
echo "--------------------------"
echo "| Configuring touchpad.. |"
echo "--------------------------"

gsettings set org.gnome.desktop.peripherals.touchpad click-method 'default'
gsettings set org.gnome.desktop.peripherals.touchpad edge-scrolling-enabled false
gsettings set org.gnome.desktop.peripherals.touchpad disable-while-typing true
gsettings set org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled true
gsettings set org.gnome.desktop.peripherals.touchpad send-events 'enabled'
gsettings set org.gnome.desktop.peripherals.touchpad speed 0.0
gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true
gsettings set org.gnome.desktop.peripherals.touchpad middle-click-emulation false
gsettings set org.gnome.desktop.peripherals.touchpad left-handed 'mouse'
gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
gsettings set org.gnome.desktop.peripherals.touchpad tap-and-drag true

# =====================================================================================

echo
echo "----------------------------------------------"
echo "| Turning on battery percentage displaying.. |"
echo "----------------------------------------------"

gsettings set org.gnome.desktop.interface show-battery-percentage true

# =====================================================================================

echo
echo "-------------------------------------------"
echo "| Configuring /tmp to be mounted in RAM.. |"
echo "-------------------------------------------"

sudo bash -c 'echo "tmpfs /tmp tmpfs mode=0777 0 0" >> /etc/fstab'

# =====================================================================================

echo
echo "---------------------------------"
echo "| Configuring favourites apps.. |"
echo "---------------------------------"

gsettings set org.gnome.shell favorite-apps "['org.gnome.Nautilus.desktop', 'brave-browser.desktop', 'sublime-text_subl.desktop', 'intellij-idea-ultimate_intellij-idea-ultimate.desktop', 'lens.desktop', 'postman.desktop']"

# =====================================================================================

echo
echo "----------------------------"
echo "| Configuring local time.. |"
echo "----------------------------"

timedatectl set-local-rtc 1 --adjust-system-clock

# =====================================================================================

echo
echo "--------------------------"
echo "| Setting default apps.. |"
echo "--------------------------"

xdg-mime default $default_word_app application/msword
xdg-mime default $default_word_app application/vnd.openxmlformats-officedocument.wordprocessingml.document
xdg-mime default $default_word_app application/wordperfect
xdg-mime default $default_word_app application/vnd.ms-word
xdg-mime default $default_word_app application/vnd.sun.xml.writer
xdg-mime default $default_word_app application/vnd.wordperfect
xdg-mime default $default_excel_app application/excel
xdg-mime default $default_excel_app application/csv
xdg-mime default $default_excel_app application/msexcel
xdg-mime default $default_excel_app application/vnd.ms-excel
xdg-mime default $default_excel_app application/vnd.sun.xml.calc
xdg-mime default $default_excel_app application/vnd.oasis.opendocument.spreadsheet
xdg-mime default $default_excel_app application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
xdg-mime default $default_excel_app application/x-applix-spreadsheet
xdg-mime default $default_excel_app application/x-dos_ms_excel
xdg-mime default $default_excel_app application/x-excel
xdg-mime default $default_excel_app application/xls
xdg-mime default $default_excel_app application/x-xls
xdg-mime default $default_excel_app application/x-ms-excel
xdg-mime default $default_excel_app application/x-msexcel
xdg-mime default $default_excel_app text/comma-separated-values
xdg-mime default $default_excel_app text/csv
xdg-mime default $default_excel_app text/spreadsheet
xdg-mime default $default_excel_app text/tab-separated-values
xdg-mime default $default_excel_app text/x-comma-separated-values
xdg-mime default $default_presentation_app application/vnd.oasis.opendocument.presentation
xdg-mime default $default_presentation_app application/vnd.sun.xml.impress
xdg-mime default $default_presentation_app application/mspowerpoint
xdg-mime default $default_presentation_app application/vnd.ms-powerpoint
xdg-mime default $default_presentation_app application/vnd.openxmlformats-officedocument.presentationml.slide
xdg-mime default $default_presentation_app application/vnd.openxmlformats-officedocument.presentationml.slideshow
xdg-mime default $default_presentation_app application/vnd.openxmlformats-officedocument.presentationml.presentation
xdg-mime default $default_pdf_app application/pdf
xdg-mime default $default_pdf_app application/x-gzpdf
xdg-mime default $default_pdf_app application/x-xzpdf
xdg-mime default $default_internetBrowser_app application/xhtml+xml 
xdg-mime default $default_internetBrowser_app text/html
xdg-mime default $default_internetBrowser_app x-scheme-handler/http
xdg-mime default $default_internetBrowser_app x-scheme-handler/https
xdg-mime default $default_internetBrowser_app image/svg+xml
xdg-mime default $default_internetBrowser_app text/xml
xdg-mime default $default_internetBrowser_app application/xml
xdg-mime default $default_video_app video/3gpp
xdg-mime default $default_video_app video/dv
xdg-mime default $default_video_app video/fli
xdg-mime default $default_video_app video/flv
xdg-mime default $default_video_app video/mp2t
xdg-mime default $default_video_app video/mp4
xdg-mime default $default_video_app video/mp4v-es
xdg-mime default $default_video_app video/mpeg
xdg-mime default $default_video_app video/msvideo
xdg-mime default $default_video_app video/ogg
xdg-mime default $default_video_app video/quicktime
xdg-mime default $default_video_app video/vivo
xdg-mime default $default_video_app video/vnd.divx
xdg-mime default $default_video_app video/vnd.rn-realvideo
xdg-mime default $default_video_app video/vnd.vivo
xdg-mime default $default_video_app video/webm
xdg-mime default $default_video_app video/x-anim
xdg-mime default $default_video_app video/x-avi
xdg-mime default $default_video_app video/x-flc
xdg-mime default $default_video_app video/x-fli
xdg-mime default $default_video_app video/x-flic
xdg-mime default $default_video_app video/x-flv
xdg-mime default $default_video_app video/x-m4v
xdg-mime default $default_video_app video/x-matroska
xdg-mime default $default_video_app video/x-mpeg
xdg-mime default $default_video_app video/x-ms-asf
xdg-mime default $default_video_app video/x-ms-asx
xdg-mime default $default_video_app video/x-msvideo
xdg-mime default $default_video_app video/x-ms-wm
xdg-mime default $default_video_app video/x-ms-wmv
xdg-mime default $default_video_app video/x-ms-wmx
xdg-mime default $default_video_app video/x-ms-wvx
xdg-mime default $default_video_app video/x-nsv
xdg-mime default $default_video_app video/x-ogm+ogg
xdg-mime default $default_video_app video/x-theora+ogg
xdg-mime default $default_video_app video/x-totem-stream
xdg-mime default $default_video_app x-content/video-dvd
xdg-mime default $default_video_app x-content/video-vcd
xdg-mime default $default_video_app x-content/video-svcd

# =====================================================================================

echo
echo "-----------------------------------"
echo "| Setting Dash-to-Dock settings.. |"
echo "-----------------------------------"

gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM'
gsettings set org.gnome.shell.extensions.dash-to-dock background-color '#ffffff'
gsettings set org.gnome.shell.extensions.dash-to-dock background-opacity 0.7
gsettings set org.gnome.shell.extensions.dash-to-dock custom-background-color false
gsettings set org.gnome.shell.extensions.dash-to-dock transparency-mode 'FIXED'

gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 55
gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false
gsettings set org.gnome.shell.extensions.dash-to-dock height-fraction 0.9
gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed true

gsettings set org.gnome.shell.extensions.dash-to-dock intellihide true
gsettings set org.gnome.shell.extensions.dash-to-dock intellihide-mode 'FOCUS_APPLICATION_WINDOWS'
gsettings set org.gnome.shell.extensions.dash-to-dock isolate-workspaces true
gsettings set org.gnome.shell.extensions.dash-to-dock middle-click-action 'launch'
gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'minimize-or-previews'
gsettings set org.gnome.shell.extensions.dash-to-dock show-mounts false

gsettings set org.gnome.shell.extensions.dash-to-dock running-indicator-style 'DOTS'
gsettings set org.gnome.shell.extensions.dash-to-dock custom-theme-customize-running-dots true
gsettings set org.gnome.shell.extensions.dash-to-dock custom-theme-running-dots-color '#e95420'
gsettings set org.gnome.shell.extensions.dash-to-dock custom-theme-shrink true

gsettings set org.gnome.shell.extensions.dash-to-dock animate-show-apps true
gsettings set org.gnome.shell.extensions.dash-to-dock show-windows-preview true
gsettings set org.gnome.shell.extensions.dash-to-dock show-delay 0.25
gsettings set org.gnome.shell.extensions.dash-to-dock hide-delay 0.2

gsettings set org.gnome.shell.extensions.dash-to-dock show-trash true
gsettings set org.gnome.shell.extensions.dash-to-dock show-favorites true
gsettings set org.gnome.shell.extensions.dash-to-dock show-running true
gsettings set org.gnome.shell.extensions.dash-to-dock show-show-apps-button true
gsettings set org.gnome.shell.extensions.dash-to-dock show-mounts false

gsettings set org.gnome.shell.extensions.dash-to-dock isolate-monitors false
gsettings set org.gnome.shell.extensions.dash-to-dock multi-monitor false

gsettings set org.gnome.shell.extensions.dash-to-dock shortcut-timeout 2.0

gsettings set org.gnome.shell.extensions.dash-to-dock max-alpha 0.8
gsettings set org.gnome.shell.extensions.dash-to-dock min-alpha 0.2

# =====================================================================================

echo
echo "----------------------------------------"
echo "| Making sure extensions are enabled.. |"
echo "----------------------------------------"

gnome-extensions enable gsconnect@andyholmes.github.io
gnome-extensions enable start-overlay-in-application-view@Hex_cz
gnome-extensions enable dash-to-dock@micxgx.gmail.com

# =====================================================================================

echo
echo "--------------"
echo "| Cleaning.. |"
echo "--------------"

yes | sudo rm -R "$temp_folder_path"

# =====================================================================================

echo "-----------------------------"
echo "| Installing terminal ZSH.. |"
echo "-----------------------------"

sudo apt install zsh -y
sudo chsh -s /bin/zsh -y

# install Oh My Zsh
bash -c ""echo Y | sh -c "$(curl -fsSL $zsh_download_link)"""

cp ./config/.p10k.zsh "$HOME"/
cp ./config/.zshrc.pre-oh-my-zsh "$HOME"/
cp ./config/.zshrc "$HOME"/

# install fonts
wget "$nerdFont_download_link" -cO "$temp_folder_path"/"$nerdFontName"
wget "$mesloRegular_download_link" -cO "$temp_folder_path"/"$mesloRegularName"
wget "$mesloBold_download_link" -cO "$temp_folder_path"/"$mesloBoldName"
wget "$mesloItalic_download_link" -cO "$temp_folder_path"/"$mesloItalicName"
wget "$mesloBoldItalic_download_link" -cO "$temp_folder_path"/"$mesloBoldItalicName"

sudo cp "$temp_folder_path"/"$nerdFontName" /usr/share/fonts/
sudo cp "$temp_folder_path"/"$mesloRegularName" /usr/share/fonts/
sudo cp "$temp_folder_path"/"$mesloBoldName" /usr/share/fonts/
sudo cp "$temp_folder_path"/"$mesloItalicName" /usr/share/fonts/
sudo cp "$temp_folder_path"/"$mesloBoldItalicName" /usr/share/fonts/

# install plugins
sudo git clone "$spaceshipTheme_download_link" "$ZSH_CUSTOM/themes/spaceship-prompt" --depth=1
sudo ln -s "$ZSH_CUSTOM/themes/spaceship-prompt/spaceship.zsh-theme" "$ZSH_CUSTOM/themes/spaceship.zsh-theme"
sudo git clone --depth=1 "$powerlevel10kTheme_download_link" "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"/themes/powerlevel10k

# set gnome terminal to use ZSH
terminalProfile="$(gsettings get org.gnome.Terminal.ProfilesList default)"
terminalProfile=${terminalProfile:1:-1} # remove leading and trailing single quotes
gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$terminalProfile/" custom-command 'zsh'
gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$terminalProfile/" exit-action 'close'
gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$terminalProfile/" login-shell true
gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$terminalProfile/" use-custom-command true

sudo echo 'export PATH="$PATH:/usr/bin/brave-browser-stable"' >> ~/.bashrc
sudo echo 'export PATH="$PATH:/usr/bin/brave-browser-stable"' >> ~/.zshrc

echo 'export PATH="$PATH:/opt/postman/postman"' >> ~/.bashrc
echo 'export PATH="$PATH:/opt/postman/postman"' >> ~/.zshrc

echo
echo "-----------------------------------"
echo "| Now you need to setup Oh My Zsh |"
echo "-----------------------------------"

gnome-terminal

# =====================================================================================

echo
echo "--------------------"
echo "| Reboot needed !! |"
echo "--------------------"

# =====================================================================================
