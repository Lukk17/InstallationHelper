Write-Output
Write-Output "--------------------------------"
Write-Output "| Chocolatey package install.. |"
Write-Output "--------------------------------"
# Disable prompt
choco feature enable -n=allowGlobalConfirmation
Set-ExecutionPolicy AllSigned
Set-ExecutionPolicy Bypass -Scope Process
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
choco feature enable -n=useRememberedArgumentsForUpgrades

Write-Output
Write-Output "----------------------"
Write-Output "| Browsers install.. |"
Write-Output "----------------------"

choco install brave
choco install firefox

Write-Output
Write-Output "---------------------"
Write-Output "| Utility install.. |"
Write-Output "---------------------"

choco install geforce-experience
choco install winrar
choco install googledrive
choco install sublimetext3
choco install utorrent
choco install chocolateygui
choco install adobereader

Write-Output
Write-Output "---------------------------"
Write-Output "| Games clients install.. |"
Write-Output "---------------------------"

choco install goggalaxy
choco install steam
choco install ea-app
choco install epicgameslauncher

Write-Output
Write-Output "--------------------------"
Write-Output "| System tools install.. |"
Write-Output "--------------------------"

choco install iobit-uninstaller
choco install drivereasyfree


Write-Output
Write-Output "----------------------"
Write-Output "| OC tools install.. |"
Write-Output "----------------------"

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

Write-Output
Write-Output "--------------------------"
Write-Output "| Coding tools install.. |"
Write-Output "--------------------------"

choco install intellijidea-ultimate --params "/InstallDir=C:\Program Files\JetBrains\IntelliJ IDEA"
choco install oraclejdk
choco install python3
choco install gradle
choco install maven
choco install git
choco install nodejs
choco install kubernetes-cli
choco install minikube
choco install flutter
choco install lens
choco install github-desktop
choco install putty
choco install filezilla
choco install dbeaver
choco install openssl
# no root password
choco install mysql
choco install mongodb
choco install mongodb-compass

Write-Output
Write-Output "---------------------------------------------"
Write-Output "| Scrcpy - Android managment tool install.. |"
Write-Output "---------------------------------------------"

#scrCpy (android managment)
# https://github.com/Genymobile/scrcpy
choco install scrcpy
choco install adb

Write-Output
Write-Output "----------------------"
Write-Output "| CAD apps install.. |"
Write-Output "----------------------"

choco install prusaslicer
choco install freecad
choco install autodesk-fusion360

Write-Output
Write-Output "-------------------------------------------"
Write-Output "| Winget - Microsoft Store apps install.. |"
Write-Output "-------------------------------------------"

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

# Prime Video
winget install --accept-source-agreements --accept-package-agreements --source msstore 9P6RC76MSMMJ
# Disney+
winget install --accept-source-agreements --accept-package-agreements --source msstore 9NXQXXLFST89
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

# HBO Max - connot be installed on PC, only on Xbox
#winget install --accept-source-agreements --accept-package-agreements --source msstore 9PJJ1K9DZMRS


Write-Output
Write-Output "-----------------------------------"
Write-Output "| Creating folders and symlinks.. |"
Write-Output "-----------------------------------"

New-Item -Path "C:\Gry\" -ItemType Directory
New-Item -ItemType SymbolicLink -Path "C:\Program Files (x86)\Steam\steamapps" -Target "C:\Gry\"


Write-Output
Write-Output "-----------------------------"
Write-Output "| Enable Windows features.. |"
Write-Output "-----------------------------"

Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
Enable-WindowsOptionalFeature -Online -FeatureName NetFx3
Enable-WindowsOptionalFeature -Online -FeatureName NetFx4


Write-Output
Write-Output "-----------------------------"
Write-Output "| Install Android and WSL.. |"
Write-Output "-----------------------------"

# Ubuntu
winget install --accept-source-agreements --accept-package-agreements --source msstore 9PDXGNCFSCZV
# Windows Subsystem for Android
winget install --accept-source-agreements --accept-package-agreements --source msstore 9P3395VX91NR
# Amazon Appstore
winget install --accept-source-agreements --accept-package-agreements --source msstore 9NJHK44TTKSX


Write-Output
Write-Output "-------------------------------------------------"
Write-Output "| Opening additional softwares download links.. |"
Write-Output "-------------------------------------------------"

Start-Process "C:\Program Files\Google\Chrome\Application\chrome.exe" "https://download.battle.net/en-us/?platform=windows"
Start-Process "C:\Program Files\Google\Chrome\Application\chrome.exe" "https://www.curseforge.com/download/app#download-options"
Start-Process "C:\Program Files\Google\Chrome\Application\chrome.exe" "https://www.veracrypt.fr/en/Downloads.html"
Start-Process "C:\Program Files\Google\Chrome\Application\chrome.exe" "https://signup.leagueoflegends.com/en-us/signup/redownload"