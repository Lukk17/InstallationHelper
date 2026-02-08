$outputLogPath = "$env:USERPROFILE\Desktop\output.txt"
$errorLogPath = "$env:USERPROFILE\Desktop\errors.txt"
$warningLogPath = "$env:USERPROFILE\Desktop\warnings.txt"

# Create or clear the log files
"" | Out-File -FilePath $outputLogPath -Force
"" | Out-File -FilePath $errorLogPath -Force
"" | Out-File -FilePath $warningLogPath -Force


$installScript = {
    Write-Output ""
    Write-Output "--------------------------------"
    Write-Output "| Chocolatey package install.. |"
    Write-Output "--------------------------------"

    Set-ExecutionPolicy AllSigned
    Set-ExecutionPolicy Bypass -Scope Process
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    # Disable prompt
    choco feature enable -n=allowGlobalConfirmation
    choco feature enable -n=useRememberedArgumentsForUpgrades
    choco config set stoponfirstfailure false
    choco install chocolatey-core.extension

    Write-Output ""
    Write-Output "----------------------"
    Write-Output "| Browsers install.. |"
    Write-Output "----------------------"

    choco install googlechrome
    choco install brave
    choco install firefox

    Write-Output ""
    Write-Output "---------------------"
    Write-Output "| Utility install.. |"
    Write-Output "---------------------"

    choco install geforce-experience
    choco install winrar
    choco install googledrive
    choco install sublimetext4
#    choco install onlyoffice
    choco install utorrent --ignore-checksums
    choco install chocolateygui
    choco install handbrake
    choco install audacity
    choco install teamviewer
#    only for accepting incoming connections:
#    choco install teamviewer.host
    choco install gimp
    choco install krita
    choco install rawtherapee
    choco install obsidian
    choco install vlc
    choco install pdfgear

    Write-Output ""
    Write-Output "-------------------------"
    Write-Output "| Social apps install.. |"
    Write-Output "-------------------------"
    choco install signal

    Write-Output ""
    Write-Output "---------------------------"
    Write-Output "| Games clients install.. |"
    Write-Output "---------------------------"

    choco install goggalaxy
    choco install steam
    choco install ea-app

    Write-Output ""
    Write-Output "--------------------------"
    Write-Output "| System tools install.. |"
    Write-Output "--------------------------"

#    Use Hyper-V manager instead
#    choco install virtualbox
#    choco install vmware-workstation-player
    choco install bluestacks

    Write-Output ""
    Write-Output "----------------------"
    Write-Output "| OC tools install.. |"
    Write-Output "----------------------"

    choco install bulk-crap-uninstaller
#    MiniTool Partition Wizard
    choco install partitionwizard
    choco install advanced-ip-scanner
    choco install hwmonitor
    choco install crystaldiskinfo
    choco install crystaldiskmark
    choco install glasswire
    choco install prime95.portable
    choco install rufus
    choco install hwinfo
    choco install wiztree
    # Speedtest CLI
    choco install speedtest
    # https://learn.microsoft.com/en-us/sysinternals/downloads/tcpview
    choco install tcpview
    # https://learn.microsoft.com/en-us/sysinternals/downloads/autoruns
    choco install autoruns
    # sometime dont work, then download from:
    # https://www.msi.com/Landing/afterburner/graphics-cards
    choco install msiafterburner

    Write-Output ""
    Write-Output "--------------------------"
    Write-Output "| Coding tools install.. |"
    Write-Output "--------------------------"

    choco install jetbrainstoolbox
    choco install oraclejdk
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
    choco install postman
    choco install openssl
    choco install mongodb-compass
    choco install python312
    choco install python311
    choco install python310
    choco install python313
    choco install arduino
    choco install temurin17
    choco install openjdk --version=21.0.2
    # pin version so it will not be updated to 22 or higher
    choco pin add -n=openjdk --version=21.0.2
    # for audio manipulation in transcription
    choco install ffmpeg
    # for audio trimming
    choco install sox.portable
    choco install unity-hub


    Write-Output ""
    Write-Output "---------------------------------------------"
    Write-Output "| Android managment tool install..          |"
    Write-Output "---------------------------------------------"

    choco install adb
    #scrCpy (android managment)
    # https://github.com/Genymobile/scrcpy
    choco install scrcpy
    choco install kdeconnect-kde

    Write-Output ""
    Write-Output "----------------------"
    Write-Output "| CAD apps install.. |"
    Write-Output "----------------------"

    choco install prusaslicer
    choco install freecad
    choco install autodesk-fusion360
    choco install kicad

    Write-Output ""
    Write-Output "--------------------------------------"
    Write-Output "| Volunteer Computing apps install.. |"
    Write-Output "--------------------------------------"
    choco install boinc
    choco install gridcoinwallet


    Write-Output ""
    Write-Output "-------------------------------------------"
    Write-Output "| Winget - Microsoft Store apps install.. |"
    Write-Output "-------------------------------------------"

    # Write-Output "winget installer (Windows Package Manager Source)"
    #winget install --accept-source-agreements --accept-package-agreements Microsoft.Winget.Source_8wekyb3d8bbwe

    # Write-Output "App Installer"
    #winget install --accept-source-agreements --accept-package-agreements Microsoft.DesktopAppInstaller_8wekyb3d8bbwe

    Write-Output "whatsapp"
    winget install --accept-source-agreements --accept-package-agreements --source msstore whatsapp

    Write-Output "telegram"
#    winget install --accept-source-agreements --accept-package-agreements --source msstore telegram
    winget install --accept-source-agreements --accept-package-agreements --source msstore 9nztwsqntd0s

    Write-Output "bitwarden"
    winget install --accept-source-agreements --accept-package-agreements --source msstore bitwarden

    Write-Output "powershell"
    winget install --accept-source-agreements --accept-package-agreements --source msstore powershell

    Write-Output "slack"
    winget install --accept-source-agreements --accept-package-agreements --source msstore slack

    Write-Output "vlc"
    winget install --accept-source-agreements --accept-package-agreements --source msstore vlc

    # Write-Output "zoom"
#    winget install --accept-source-agreements --accept-package-agreements --source msstore zoom

    Write-Output "dropbox"
    winget install --accept-source-agreements --accept-package-agreements --source msstore dropbox

#    https://learn.microsoft.com/en-us/windows/powertoys/
    Write-Output "powertoys"
    winget install --accept-source-agreements --accept-package-agreements --id Microsoft.PowerToys --source winget

    Write-Output "Prime Video"
    winget install --accept-source-agreements --accept-package-agreements --source msstore 9P6RC76MSMMJ

    Write-Output "Disney+"
    winget install --accept-source-agreements --accept-package-agreements --source msstore 9NXQXXLFST89

    Write-Output "Spotify"
    winget install --accept-source-agreements --accept-package-agreements --source msstore 9NCBCSZSJRSB
 
    Write-Output "Microsoft To Do"
    winget install --accept-source-agreements --accept-package-agreements --source msstore 9NBLGGH5R558

    Write-Output "Trello"
    winget install --accept-source-agreements --accept-package-agreements --source msstore 9NBLGGH4XXVW

    Write-Output "Netflix"
    winget install --accept-source-agreements --accept-package-agreements --source msstore 9WZDNCRFJ3TJ

    # Write-Output "Battery Percentage - Pure Battery add-on"
#    winget install --accept-source-agreements --accept-package-agreements --source msstore 9N3HDTNCF6Z8

    Write-Output "Razer Cortex addon to Xbox Bar"
    winget install --accept-source-agreements --accept-package-agreements --source msstore 9PK9W5QV2PKX

    Write-Output "Discord"
    winget install --accept-source-agreements --accept-package-agreements --source msstore XPDC2RH70K22MN

    Write-Output "Microsoft Teams"
    winget install --accept-source-agreements --accept-package-agreements --source msstore XP8BT8DW290MPQ

    Write-Output "Visual Studio Code"
    winget install --accept-source-agreements --accept-package-agreements --source msstore XP9KHM4BK9FZ7Q

    Write-Output "Ubisoft Connect"
    winget install --accept-source-agreements --accept-package-agreements --source msstore XPDP2QW12DFSFK

    Write-Output "Adobe Acrobat Reader"
    winget install --accept-source-agreements --accept-package-agreements --source msstore XPDP273C0XHQH2

    Write-Output "iTunes"
    winget install --accept-source-agreements --accept-package-agreements --source msstore 9PB2MZ1ZMB1S

    Write-Output "Epic Games Store"
    winget install --accept-source-agreements --accept-package-agreements --source msstore XP99VR1BPSBQJ2

    Write-Output "Galaxy Buds"
    winget install --accept-source-agreements --accept-package-agreements --source msstore 9NHTLWTKFZNB

    # Write-Output "Reddit"
#    winget install --accept-source-agreements --accept-package-agreements --source msstore 9NS3RBQ5HV5F

    Write-Output "Speedtest by Ookla"
    winget install --accept-source-agreements --accept-package-agreements --source msstore 9NBLGGH4Z1JC

    Write-Output "Plex Media Server"
    winget install --accept-source-agreements --accept-package-agreements --source msstore XPFM11Z0W10R7G

    Write-Output "Canon"
    winget install --accept-source-agreements --accept-package-agreements --source msstore 9pmk584kqvc2

    Write-Output "Inkscape"
    winget install --accept-source-agreements --accept-package-agreements --source msstore 9pd9bhglfc7h

    Write-Output "Nvidia Control Panel"
    winget install --accept-source-agreements --accept-package-agreements --source msstore 9nf8h0h7wmlt

    Write-Output "Docker Desktop"
    winget install --accept-source-agreements --accept-package-agreements --source msstore xp8cbj40xlbwkx

    Write-Output "Visual Studio Community"
    winget install --accept-source-agreements --accept-package-agreements --source msstore xpdcfjdklzjlp8

    # Write-Output "HBO Max" # - connot be installed on PC, only on Xbox
    #winget install --accept-source-agreements --accept-package-agreements --source msstore 9PJJ1K9DZMRS


    Write-Output ""
    Write-Output "-----------------------------"
    Write-Output "| Enable Windows features.. |"
    Write-Output "-----------------------------"

    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
    Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All
    Enable-WindowsOptionalFeature -Online -FeatureName NetFx3
    Enable-WindowsOptionalFeature -Online -FeatureName NetFx4-AdvSrvs
    Enable-WindowsOptionalFeature -Online -FeatureName NetFx4Extended-ASPNET45
    Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -All
    Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V" -All
#    Allow to mount and access Linux network shares directly from Windows
    Enable-WindowsOptionalFeature -Online -FeatureName "ServicesForNFS-ClientOnly" -All


    Write-Output ""
    Write-Output "-----------------------------"
    Write-Output "| Install WSL..             |"
    Write-Output "-----------------------------"

    wsl --update
    # Ubuntu
    wsl --install -d Ubuntu

    Write-Output ""
    Write-Output "-----------------------------"
    Write-Output "| Configure env variables.. |"
    Write-Output "-----------------------------"

    .\env-variable-config.ps1


    Write-Output ""
    Write-Output "-------------------------------------------------"
    Write-Output "| Opening additional softwares download links.. |"
    Write-Output "-------------------------------------------------"

    Start-Process "https://www.veracrypt.fr/en/Downloads.html"
    
    Start-Process "https://github.com/AUTOMATIC1111/stable-diffusion-webui"
    
    Start-Process "https://lmstudio.ai/"
    
    Start-Process "https://www.beeper.com/download"
    
    Start-Process "https://download.battle.net/en-us/?platform=windows"
    
    Start-Process "https://www.curseforge.com/download/app#download-options"
    
    Start-Process "https://www.tradeskillmaster.com/install"

    Start-Process "https://www.overwolf.com/app/rpglogs_llc-warcraft_logs_companion"

    Start-Process "https://signup.leagueoflegends.com/en-us/signup/redownload"
    
    Start-Process "https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer"
    
    Start-Process "https://www.torproject.org/download/"
    
    Start-Process "https://pawns.app/downloads/"
    
    Start-Process "https://geeks3d.com/furmark/downloads/"
    
    Start-Process "https://www.nvidia.com/en-us/software/nvidia-app/"
    
    Start-Process "https://www.msi.com/Landing/afterburner/graphics-cards"

    Start-Process "https://github.com/sanraith/razer-taskbar/releases/tag/v0.12.0"

    Start-Process "https://apps.microsoft.com/detail/cfq7ttc0k5dm?hl=en-US&gl=PL"



    Write-Output ""
    Write-Output "------------------------------------------"
    Write-Output "| Restarting computer after confirming.. |"
    Write-Output "------------------------------------------"
    Read-Host "Press Enter to restart the computer"; Restart-Computer

}

# Run the script and capture all output
& $installScript 2>&1 3>&1 | ForEach-Object {
    # Write to console
    $_

    # Determine which file to write to based on stream type
    if ($_ -is [System.Management.Automation.ErrorRecord]) {
        $_ | Out-File -FilePath $errorLogPath -Append
    } elseif ($_ -is [System.Management.Automation.WarningRecord]) {
        $_ | Out-File -FilePath $warningLogPath -Append
    } else {
        $_ | Out-File -FilePath $outputLogPath -Append
    }
}

