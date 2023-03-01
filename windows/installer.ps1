echo
echo "--------------------------------"
echo "| Chocolatey package install.. |"
echo "--------------------------------"
# Disable prompt
choco feature enable -n=allowGlobalConfirmation

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
choco install dropbox
choco install adobereader
choco install sublimetext3
choco install itunes
choco install imgburn
choco install utorrent

echo
echo "---------------------------"
echo "| Games clients install.. |"
echo "---------------------------"

choco install goggalaxy
choco install steam
choco install ea-app
choco install ubisoft-connect
choco install epicgameslauncher

echo
echo "--------------------------"
echo "| System tools install.. |"
echo "--------------------------"

choco install iobit-uninstaller
choco install drivereasyfree

echo
echo "---------------------------------"
echo "| Communication tools install.. |"
echo "---------------------------------"

choco install zoom
choco install discord
choco install telegram
choco install whatsapp

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

echo
echo "--------------------------"
echo "| Coding tools install.. |"
echo "--------------------------"

choco install git
choco install github-desktop
choco install python3
choco install nodejs
choco install kubernetes-cli
choco install minikubee
choco install lens
choco install putty
choco install filezilla
choco install dbeaver

echo
echo "---------------------------------------------"
echo "| Scrcpy - Android managment tool install.. |"
echo "---------------------------------------------"

#scrCpy (android managment)
# https://github.com/Genymobile/scrcpy
choco install scrcpy
choco install adbe

echo
echo "----------------------"
echo "| CAD apps install.. |"
echo "----------------------"

choco install prusaslice
choco install freecadr
choco install autodesk-fusion360

echo
echo "-------------------------------------------"
echo "| Winget - Microsoft Store apps install.. |"
echo "-------------------------------------------"

winget install --source msstore bitwarden
# spotify
winget install --source msstore 9NCBCSZSJRSB
# Microsoft To Do
winget install --source msstore 9NBLGGH5R558
# trello
winget install --source msstore 9NBLGGH4XXVW
# netflix
winget install --source msstore 9WZDNCRFJ3TJ
winget install --source msstore skype
# Battery Percentage - Pure Battery add-on
winget install --source msstore 9N3HDTNCF6Z8
