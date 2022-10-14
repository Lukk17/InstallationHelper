#!/bin/bash

echo "Turning Ubuntu dock off.."
gnome-extensions disable ubuntu-dock@ubuntu.com

echo
echo "Configuring shortcut for Android Emulator"
sudo mkdir /opt/emulator
sudo cp ./icons/android.png /opt/emulator/android.png
sudo cp ./shortcuts/android.desktop /usr/share/applications/android.desktop


echo
echo "Creating files template.."
touch ~/Templates/file
touch ~/Templates/text.txt
touch ~/Templates/Document.docx
touch ~/Templates/Presentation.pptx
touch ~/Templates/Spreadsheet.xlsx

echo
echo "Setting wallpaper.."
sudo cp -a $temp_folder_path/wallpapers/. /usr/share/backgrounds/wallpapers/
sudo sed -i '$d' /usr/share/gnome-background-properties/focal-wallpapers.xml
sudo bash -c "cat $temp_folder_path/wallpapers-config >> /usr/share/gnome-background-properties/focal-wallpapers.xml"
gsettings set org.gnome.desktop.background picture-uri file:///$backgroud_path

echo
echo "Changing login backgroud.."
sudo apt install git libglib2.0-dev -y
#wget -qO - https://github.com/PRATAP-KUMAR/focalgdm3/archive/TrailRun.tar.gz | tar zx -C $temp_folder_path/ --strip-components=1 focalgdm3-TrailRun/focalgdm3
sudo chmod a+x $temp_folder_path/focalgdm3
sudo bash $temp_folder_path/focalgdm3 $login_background_path

echo
echo "Configuring WPS.."
sudo snap connect wps-2019-snap:cups-control :cups-control
sudo snap connect wps-2019-snap:alsa :alsa
sudo snap connect wps-2019-snap:pulseaudio :pulseaudio
sudo snap connect wps-2019-snap:removable-media :removable-media

echo
echo "Configuring touchpad.."
gsettings set org.gnome.desktop.peripherals.touchpad click-method 'default'
gsettings set org.gnome.desktop.peripherals.touchpad edge-scrolling-enabled false
gsettings set org.gnome.desktop.peripherals.touchpad disable-while-typing true
gsettings set org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled true
gsettings set org.gnome.desktop.peripherals.touchpad send-events 'enabled'
gsettings set org.gnome.desktop.peripherals.touchpad speed 0.0
gsettings set org.gnome.desktop.peripherals.touchpad scroll-method 'two-finger-scrolling'
gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true
gsettings set org.gnome.desktop.peripherals.touchpad middle-click-emulation false
gsettings set org.gnome.desktop.peripherals.touchpad left-handed 'mouse'
gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
gsettings set org.gnome.desktop.peripherals.touchpad tap-and-drag true

echo
echo "Turning on battery procentage displaying.."
gsettings set org.gnome.desktop.interface show-battery-percentage true

echo
echo "Configuring /tmp to be mounted in RAM.."
sudo bash -c 'echo "tmpfs /tmp tmpfs mode=0777 0 0" >> /etc/fstab'

echo
echo "Configuring favourites apps.."
gsettings set org.gnome.shell favorite-apps "['org.gnome.Nautilus.desktop', 'firefox.desktop', 'wps-2019-snap_wps.desktop', 'org.gnome.gedit.desktop']"

echo
echo "Configuring local time.."
timedatectl set-local-rtc 1 --adjust-system-clock

echo
echo "Setting default apps.."
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


echo
echo "Setting Dash-to-Dock settings.."
gsettings set org.gnome.shell.extensions.dash-to-dock transparency-mode 'FIXED'
gsettings set org.gnome.shell.extensions.dash-to-dock multi-monitor false
gsettings set org.gnome.shell.extensions.dash-to-dock isolate-workspaces false
gsettings set org.gnome.shell.extensions.dash-to-dock show-windows-preview true
gsettings set org.gnome.shell.extensions.dash-to-dock show-trash true
gsettings set org.gnome.shell.extensions.dash-to-dock show-favorites true
gsettings set org.gnome.shell.extensions.dash-to-dock show-running true
gsettings set org.gnome.shell.extensions.dash-to-dock running-indicator-style 'DOTS'
gsettings set org.gnome.shell.extensions.dash-to-dock custom-theme-running-dots-color '#e95420'
gsettings set org.gnome.shell.extensions.dash-to-dock show-show-apps-button true
gsettings set org.gnome.shell.extensions.dash-to-dock animate-show-apps true
gsettings set org.gnome.shell.extensions.dash-to-dock show-mounts false
gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'LEFT'
gsettings set org.gnome.shell.extensions.dash-to-dock custom-theme-customize-running-dots true
gsettings set org.gnome.shell.extensions.dash-to-dock background-opacity 0.7
gsettings set org.gnome.shell.extensions.dash-to-dock middle-click-action 'launch'
gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false
gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false
gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 40
gsettings set org.gnome.shell.extensions.dash-to-dock intellihide true
gsettings set org.gnome.shell.extensions.dash-to-dock isolate-monitors false
gsettings set org.gnome.shell.extensions.dash-to-dock background-color '#ffffff'
gsettings set org.gnome.shell.extensions.dash-to-dock height-fraction 0.9
gsettings set org.gnome.shell.extensions.dash-to-dock custom-background-color false
gsettings set org.gnome.shell.extensions.dash-to-dock shortcut-timeout 2.0
gsettings set org.gnome.shell.extensions.dash-to-dock show-delay 0.25
gsettings set org.gnome.shell.extensions.dash-to-dock hide-delay 0.2
gsettings set org.gnome.shell.extensions.dash-to-dock max-alpha 0.8
gsettings set org.gnome.shell.extensions.dash-to-dock min-alpha 0.2
gsettings set org.gnome.shell.extensions.dash-to-dock intellihide-mode 'FOCUS_APPLICATION_WINDOWS'

