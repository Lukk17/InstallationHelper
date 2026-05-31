#Requires -RunAsAdministrator
<#
    Manual install script - Windows

    Installs every app the playbook manages via winget (incl. MS Store IDs) and
    Chocolatey. Gridcoin installs from a direct .exe and is NOT handled here -
    see windows_manual_install.md "Manual install required".

    Mirrors setup/ansible/vars/Windows.yaml. Run from an elevated PowerShell.
#>

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

# winget package IDs (plain IDs and MS Store product IDs alike).
$WingetIds = @(
    'Google.Chrome', 'Brave.Brave', 'TorProject.TorBrowser',
    'Git.Git', 'Postman.Postman', 'ShiningLight.OpenSSL.Light',
    'Kubernetes.kubectl', 'Kubernetes.minikube',
    'Mirantis.Lens', 'PuTTY.PuTTY',
    'Microsoft.VisualStudioCode', 'SublimeHQ.SublimeText.4', 'ArduinoSA.IDE.stable',
    'Google.AntigravityIDE', 'Bruno.Bruno',
    'Discord.Discord', 'SlackTechnologies.Slack', 'Microsoft.Teams',
    'Telegram.TelegramDesktop', 'OpenWhisperSystems.Signal', '9NKSQGP7F2NH',
    'Obsidian.Obsidian', 'Bitwarden.Bitwarden', 'KeePassXCTeam.KeePassXC',
    'VideoLAN.VLC', 'Spotify.Spotify', 'GIMP.GIMP.3', 'KDE.Krita',
    'HandBrake.HandBrake', 'Audacity.Audacity', 'RawTherapee.RawTherapee',
    '9WZDNCRFJ3TJ', '9NXQXXLFST89', '9P6RC76MSMMJ', '9PB2MZ1ZMB1S',
    'Valve.Steam', 'GOG.Galaxy', 'EpicGames.EpicGamesLauncher',
    'ElectronicArts.EADesktop', 'Overwolf.CurseForge', '9PK9W5QV2PKX',
    'FreeCAD.FreeCAD', 'Prusa3D.PrusaSlicer',
    'TeamViewer.TeamViewer', 'IDRIX.VeraCrypt', 'Ookla.Speedtest.CLI',
    'Rufus.Rufus', 'Microsoft.PowerToys', 'MiniTool.PartitionWizard.Free',
    'Samsung.GalaxyBudsManager',
    'CPUID.HWMonitor', 'REALiX.HWiNFO', 'CrystalDewWorld.CrystalDiskInfo',
    'CrystalDewWorld.CrystalDiskMark', 'Guru3D.Afterburner',
    'AntibodySoftware.WizTree',
    'Famatech.AdvancedIPScanner', 'GlassWire.GlassWire',
    'Microsoft.Sysinternals.TCPView', 'Microsoft.Sysinternals.Autoruns',
    'UCBerkeley.BOINC',
    'Docker.DockerDesktop', 'Oracle.VirtualBox'
)

# Chocolatey packages (no usable winget manifest).
$ChocoPkgs = @('maven', 'gradle', 'filezilla', 'vmware-workstation-player')

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget not found. Install "App Installer" from the Microsoft Store, then re-run.'
}

Write-Step 'Installing winget packages'
foreach ($id in $WingetIds) {
    Write-Host "  - $id"
    winget install --exact --id $id --accept-source-agreements --accept-package-agreements --silent
}

if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Step 'Installing Chocolatey'
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

Write-Step 'Installing Chocolatey packages'
foreach ($pkg in $ChocoPkgs) {
    Write-Host "  - $pkg"
    choco install -y $pkg
}

Write-Step 'Done. NOT installed (manual download required):'
Write-Host '   - Gridcoin (direct .exe from GitHub releases - see windows_manual_install.md)'
Write-Host '   - DBeaver, OnlyOffice, Angry IP Scanner (off by default on Windows - see windows_manual_install.md)'
Write-Host "`nThe Linux dev toolchain (NVM/SDKMAN/Pyenv) runs inside WSL - see ../debian-ubuntu/debian_ubuntu_manual_install.md."
