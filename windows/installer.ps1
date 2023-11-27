echo
echo "--------------------------------"
echo "| Chocolatey package install.. |"
echo "--------------------------------"
# Disable prompt
choco feature enable -n=allowGlobalConfirmation
Set-ExecutionPolicy AllSigned
Set-ExecutionPolicy Bypass -Scope Process
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

echo
echo "----------------------"
echo "| Browsers install.. |"
echo "----------------------"

choco install brave
choco install firefox

echo
echo "---------------------"
echo "| Utility install.. |"
echo "---------------------"

choco install geforce-experience
choco install winrar
choco install googledrive
choco install sublimetext3
choco install utorrent
choco install chocolateygui
choco install adobereader

echo
echo "---------------------------"
echo "| Games clients install.. |"
echo "---------------------------"

choco install goggalaxy
choco install steam
choco install ea-app
choco install epicgameslauncher

echo
echo "--------------------------"
echo "| System tools install.. |"
echo "--------------------------"

choco install iobit-uninstaller
choco install drivereasyfree


echo
echo "----------------------"
echo "| OC tools install.. |"
echo "----------------------"

choco install inssider-lite
choco install partitionwizard
choco install advanced-ip-scanner
choco install diskgenius
choco install hwmonitor
choco install crystaldiskinfo
choco install crystaldiskmark
choco install glasswire
choco install partition-assistant-standard
choco install prime95.portable
choco install hwinfo

echo
echo "--------------------------"
echo "| Coding tools install.. |"
echo "--------------------------"

choco install intellijidea-ultimate --params "/InstallDir=C:\Program Files\JetBrains\IntelliJ IDEA"
choco install git
choco install github-desktop
choco install python3
choco install nodejs
choco install kubernetes-cli
choco install minikube
choco install lens
choco install putty
choco install filezilla
choco install dbeaver
choco install openssl

echo
echo "---------------------------------------------"
echo "| Scrcpy - Android managment tool install.. |"
echo "---------------------------------------------"

#scrCpy (android managment)
# https://github.com/Genymobile/scrcpy
choco install scrcpy
choco install adb

echo
echo "----------------------"
echo "| CAD apps install.. |"
echo "----------------------"

choco install prusaslicer
choco install freecad
choco install autodesk-fusion360

echo
echo "-------------------------------------------"
echo "| Winget - Microsoft Store apps install.. |"
echo "-------------------------------------------"

winget install --accept-source-agreements --accept-package-agreements --source msstore whatsapp
winget install --accept-source-agreements --accept-package-agreements --source msstore telegram
winget install --accept-source-agreements --accept-package-agreements --source msstore skype
winget install --accept-source-agreements --accept-package-agreements --source msstore bitwarden
winget install --accept-source-agreements --accept-package-agreements --source msstore powershell
winget install --accept-source-agreements --accept-package-agreements --source msstore imgburn
winget install --accept-source-agreements --accept-package-agreements --source msstore slack
winget install --accept-source-agreements --accept-package-agreements --source msstore vlc
winget install --accept-source-agreements --accept-package-agreements --source msstore zoom
winget install --accept-source-agreements --accept-package-agreements --source msstore dropbox

# Arduino IDE
winget install --accept-source-agreements --accept-package-agreements --source msstore 9NBLGGH4RSD8
# Spotify
winget install --accept-source-agreements --accept-package-agreements --source msstore 9NCBCSZSJRSB
# Microsoft To Do
winget install --accept-source-agreements --accept-package-agreements --source msstore 9NBLGGH5R558
# Trello
winget install --accept-source-agreements --accept-package-agreements --source msstore 9NBLGGH4XXVW
# Netflix
winget install --accept-source-agreements --accept-package-agreements --source msstore 9WZDNCRFJ3TJ
# Battery Percentage - Pure Battery add-on
winget install --accept-source-agreements --accept-package-agreements --source msstore 9N3HDTNCF6Z8
# Teamviewer
winget install --accept-source-agreements --accept-package-agreements --source msstore XPDM17HK323C4X
# Razer Cortex addon to Xbox Bar
winget install --accept-source-agreements --accept-package-agreements --source msstore 9PK9W5QV2PKX
# Discord
winget install --accept-source-agreements --accept-package-agreements --source msstore XPDC2RH70K22MN
# Microsoft Teams
winget install --accept-source-agreements --accept-package-agreements --source msstore XP8BT8DW290MPQ
# Visual Studio Code
winget install --accept-source-agreements --accept-package-agreements --source msstore XP9KHM4BK9FZ7Q
# Ubisoft Connect
winget install --accept-source-agreements --accept-package-agreements --source msstore XPDP2QW12DFSFK
# Adobe Acrobat Reader
winget install --accept-source-agreements --accept-package-agreements --source msstore XPDP273C0XHQH2
# iTunes
winget install --accept-source-agreements --accept-package-agreements --source msstore 9PB2MZ1ZMB1S
# Epic Games Store
winget install --accept-source-agreements --accept-package-agreements --source msstore XP99VR1BPSBQJ2
# Galaxy Buds
winget install --accept-source-agreements --accept-package-agreements --source msstore 9NHTLWTKFZNB


echo
echo "-------------------------------------------------"
echo "| Opening additional softwares download links.. |"
echo "-------------------------------------------------"

Start "C:\Program Files\Google\Chrome\Application\chrome.exe" "https://download.battle.net/en-us/?platform=windows"
Start "C:\Program Files\Google\Chrome\Application\chrome.exe" "https://www.veracrypt.fr/en/Downloads.html"
Start "C:\Program Files\Google\Chrome\Application\chrome.exe" "https://www.curseforge.com/download/app#download-options"