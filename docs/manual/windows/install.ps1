#Requires -Version 7.2
<#
    Manual install script - Windows

    Installs every application setup/ansible/vars/Windows.yaml maps and the group_vars toggles turn
    on by default, with the scope each mapping pins, the way the wizard does. Gridcoin installs from
    a direct .exe and is not handled here, see windows_manual_install.md "Manual install required".
    e2e/tier1/manual_windows_install.sh fails when this list and Windows.yaml disagree.

    Run it from a normal, not elevated, PowerShell 7. A user-scope install goes into the profile of
    whoever runs winget, and Spotify's installer refuses an administrator outright. Each step that
    needs an administrator runs in an elevated window of its own, so Windows asks for consent once
    per such step, the way the wizard does: the Chocolatey packages together, each machine-wide
    msix and portable package winget only installs from an elevated winget (Syncthing today), and
    Syncthing's firewall rules.
#>

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

# One line per package, in vars/Windows.yaml order. Source, Scope and InstallerType only where the
# mapping names them. ClientOnly and RequiresNvidiaGpu are the mapping's own conditions.
$Packages = @(
    @{ Manager = 'winget'; Id = 'Google.Chrome' }
    @{ Manager = 'winget'; Id = 'Brave.Brave'; Scope = 'machine'; InstallerType = 'exe' }
    @{ Manager = 'winget'; Id = 'TorProject.TorBrowser'; Scope = 'user' }
    @{ Manager = 'winget'; Id = 'Git.Git'; Scope = 'machine'; InstallerType = 'inno' }
    @{ Manager = 'choco'; Id = 'maven' }
    @{ Manager = 'choco'; Id = 'gradle' }
    @{ Manager = 'winget'; Id = 'Python.Python.3.11'; Scope = 'machine'; InstallerType = 'burn' }
    @{ Manager = 'choco'; Id = 'dart-sdk' }
    @{ Manager = 'winget'; Id = 'Google.AndroidStudio' }
    @{ Manager = 'winget'; Id = 'Postman.Postman'; Scope = 'user' }
    @{ Manager = 'winget'; Id = 'FireDaemon.OpenSSL' }
    @{ Manager = 'winget'; Id = 'Kubernetes.kubectl' }
    @{ Manager = 'winget'; Id = 'Kubernetes.minikube' }
    @{ Manager = 'winget'; Id = 'k3d.k3d' }
    @{ Manager = 'winget'; Id = 'Helm.Helm' }
    @{ Manager = 'winget'; Id = 'Hashicorp.Terraform' }
    @{ Manager = 'winget'; Id = 'GitHub.cli'; Scope = 'machine'; InstallerType = 'wix' }
    @{ Manager = 'winget'; Id = 'jqlang.jq' }
    @{ Manager = 'winget'; Id = 'junegunn.fzf' }
    @{ Manager = 'winget'; Id = 'BurntSushi.ripgrep.MSVC' }
    @{ Manager = 'winget'; Id = 'Mirantis.Lens'; Scope = 'machine'; InstallerType = 'nullsoft' }
    @{ Manager = 'choco'; Id = 'filezilla' }
    @{ Manager = 'winget'; Id = 'PuTTY.PuTTY'; Scope = 'machine'; InstallerType = 'wix' }
    @{ Manager = 'winget'; Id = '9MZ1SNWT0N5D'; Source = 'msstore' }
    @{ Manager = 'winget'; Id = 'Microsoft.VisualStudioCode'; Scope = 'machine'; InstallerType = 'inno' }
    @{ Manager = 'winget'; Id = 'SublimeHQ.SublimeText.4'; Scope = 'machine'; InstallerType = 'inno' }
    @{ Manager = 'winget'; Id = 'ArduinoSA.IDE.stable'; Scope = 'machine'; InstallerType = 'wix' }
    @{ Manager = 'winget'; Id = 'Google.AntigravityIDE'; Scope = 'user' }
    @{ Manager = 'winget'; Id = 'Bruno.Bruno'; Scope = 'machine'; InstallerType = 'wix' }
    @{ Manager = 'winget'; Id = 'JetBrains.Toolbox'; Scope = 'user' }
    @{ Manager = 'winget'; Id = 'Discord.Discord'; Scope = 'user' }
    @{ Manager = 'winget'; Id = 'SlackTechnologies.Slack'; Scope = 'user' }
    @{ Manager = 'winget'; Id = 'Microsoft.Teams' }
    @{ Manager = 'winget'; Id = 'Telegram.TelegramDesktop'; Scope = 'user' }
    @{ Manager = 'winget'; Id = 'OpenWhisperSystems.Signal'; Scope = 'user' }
    @{ Manager = 'winget'; Id = '9NKSQGP7F2NH'; Source = 'msstore' }
    @{ Manager = 'winget'; Id = 'Obsidian.Obsidian'; Scope = 'machine'; InstallerType = 'nullsoft' }
    @{ Manager = 'winget'; Id = 'Bitwarden.Bitwarden'; Scope = 'machine'; InstallerType = 'nullsoft' }
    @{ Manager = 'winget'; Id = 'KeePassXCTeam.KeePassXC' }
    @{ Manager = 'winget'; Id = '9PLM9XGG6VKS'; Source = 'msstore' }
    @{ Manager = 'winget'; Id = 'Anthropic.Claude'; Scope = 'user' }
    @{ Manager = 'winget'; Id = 'ElementLabs.LMStudio'; Scope = 'machine'; InstallerType = 'nullsoft' }
    @{ Manager = 'winget'; Id = 'SST.OpenCodeDesktop'; Scope = 'user' }
    @{ Manager = 'winget'; Id = 'VideoLAN.VLC' }
    @{ Manager = 'winget'; Id = 'Spotify.Spotify'; Scope = 'user' }
    @{ Manager = 'winget'; Id = 'GIMP.GIMP.3'; Scope = 'machine'; InstallerType = 'inno' }
    @{ Manager = 'winget'; Id = 'KDE.Krita' }
    @{ Manager = 'winget'; Id = 'HandBrake.HandBrake' }
    @{ Manager = 'winget'; Id = 'Audacity.Audacity' }
    @{ Manager = 'winget'; Id = 'RawTherapee.RawTherapee' }
    @{ Manager = 'winget'; Id = '9WZDNCRFJ3TJ'; Source = 'msstore' }
    @{ Manager = 'winget'; Id = '9NXQXXLFST89'; Source = 'msstore' }
    @{ Manager = 'winget'; Id = '9P6RC76MSMMJ'; Source = 'msstore' }
    @{ Manager = 'winget'; Id = '9PB2MZ1ZMB1S'; Source = 'msstore' }
    @{ Manager = 'winget'; Id = 'Valve.Steam' }
    @{ Manager = 'winget'; Id = 'GOG.Galaxy' }
    @{ Manager = 'winget'; Id = 'EpicGames.EpicGamesLauncher' }
    @{ Manager = 'winget'; Id = 'ElectronicArts.EADesktop' }
    @{ Manager = 'winget'; Id = 'Overwolf.CurseForge'; Scope = 'machine'; InstallerType = 'nullsoft' }
    @{ Manager = 'choco'; Id = 'razer-synapse-4' }
    @{ Manager = 'winget'; Id = 'FreeCAD.FreeCAD'; Scope = 'machine'; InstallerType = 'nullsoft' }
    @{ Manager = 'winget'; Id = 'Prusa3D.PrusaSlicer' }
    @{ Manager = 'winget'; Id = 'TeamViewer.TeamViewer' }
    @{ Manager = 'winget'; Id = 'IDRIX.VeraCrypt' }
    @{ Manager = 'winget'; Id = 'Ookla.Speedtest.CLI' }
    @{ Manager = 'winget'; Id = 'Syncthing.Syncthing'; Scope = 'machine'; InstallerType = 'portable' }
    @{ Manager = 'winget'; Id = 'Tailscale.Tailscale' }
    @{ Manager = 'winget'; Id = 'UCBerkeley.BOINC' }
    @{ Manager = 'winget'; Id = 'CPUID.HWMonitor' }
    @{ Manager = 'choco'; Id = 'hwinfo.install' }
    @{ Manager = 'winget'; Id = 'CrystalDewWorld.CrystalDiskInfo' }
    @{ Manager = 'winget'; Id = 'CrystalDewWorld.CrystalDiskMark' }
    @{ Manager = 'winget'; Id = 'Guru3D.Afterburner' }
    @{ Manager = 'winget'; Id = 'AntibodySoftware.WizTree' }
    @{ Manager = 'winget'; Id = 'angryziber.AngryIPScanner' }
    @{ Manager = 'winget'; Id = 'Famatech.AdvancedIPScanner' }
    @{ Manager = 'choco'; Id = 'glasswire' }
    @{ Manager = 'choco'; Id = 'nvidia-app'; RequiresNvidiaGpu = $true }
    @{ Manager = 'winget'; Id = 'Microsoft.Sysinternals.TCPView' }
    @{ Manager = 'winget'; Id = 'Microsoft.Sysinternals.Autoruns' }
    @{ Manager = 'winget'; Id = 'Rufus.Rufus' }
    @{ Manager = 'winget'; Id = 'Microsoft.PowerToys'; Scope = 'machine'; InstallerType = 'burn' }
    @{ Manager = 'winget'; Id = 'AppControlLabs.AppControlSetup' }
    @{ Manager = 'winget'; Id = 'Samsung.GalaxyBudsManager' }
    @{ Manager = 'winget'; Id = 'MiniTool.PartitionWizard.Free'; ClientOnly = $true }
    @{ Manager = 'winget'; Id = 'Docker.DockerDesktop' }
    @{ Manager = 'winget'; Id = 'Oracle.VirtualBox' }
    @{ Manager = 'choco'; Id = 'vmware-workstation-player' }
)

# The installer types winget installs machine-wide only when winget itself runs elevated, the same
# list as $script:WingetAdminInstallerTypes in setup/windows/WindowsSoftware.ps1.
$WingetAdminInstallerTypes = @('font', 'portable', 'msstore', 'msix')

# Syncthing's ports and its logon shortcut, the same as setup/windows/WindowsSoftware.ps1.
$SyncthingFirewallRules = @(
    @{ Name = 'InstallationHelper-Syncthing-TCP-22000'; Protocol = 'TCP'; Port = 22000; Purpose = 'sync protocol' }
    @{ Name = 'InstallationHelper-Syncthing-UDP-22000'; Protocol = 'UDP'; Port = 22000; Purpose = 'sync protocol over QUIC' }
    @{ Name = 'InstallationHelper-Syncthing-UDP-21027'; Protocol = 'UDP'; Port = 21027; Purpose = 'local discovery' }
)
$SyncthingStartupArguments = '--no-console --no-browser --no-upgrade'

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this from a normal PowerShell, not an elevated one. The steps that need an administrator ask for it themselves.'
}
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget not found. Install "App Installer" from the Microsoft Store, then re-run.'
}

$installationType = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name InstallationType).InstallationType
$hasNvidia = [bool](Get-CimInstance -ClassName Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' })

$wanted = foreach ($p in $Packages) {
    if ($p['ClientOnly'] -and $installationType -ne 'Client') { Write-Host "  skipped $($p.Id): the vendor ships it for client editions only, and this is $installationType"; continue }
    if ($p['RequiresNvidiaGpu'] -and -not $hasNvidia) { Write-Host "  skipped $($p.Id): there is no NVIDIA display adapter"; continue }
    $p
}

function Get-WingetArgument($p) {
    $arguments = @('install', '--exact', '--id', $p.Id, '--source', $(if ($p['Source']) { $p.Source } else { 'winget' }),
        '--silent', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    if ($p['Scope']) { $arguments += @('--scope', $p.Scope) }
    return $arguments
}

$elevatedWinget = @($wanted | Where-Object { $_.Manager -eq 'winget' -and $_['Scope'] -eq 'machine' -and $WingetAdminInstallerTypes -contains $_['InstallerType'] })
$plainWinget = @($wanted | Where-Object { $_.Manager -eq 'winget' -and $elevatedWinget -notcontains $_ })
$choco = @($wanted | Where-Object { $_.Manager -eq 'choco' })
$failures = [System.Collections.Generic.List[string]]::new()

Write-Step 'Installing winget packages'
foreach ($p in $plainWinget) {
    Write-Host "  - $($p.Id)"
    $arguments = Get-WingetArgument $p
    & winget @arguments
    # 0x8A15002B is "already installed, no newer version", which is not a failure here.
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { $failures.Add("$($p.Id): winget exited $LASTEXITCODE") }
}

Write-Step 'Installing what needs an administrator, one elevated window and one consent prompt per step'
$quote = { param($text) "'" + ($text -replace "'", "''") + "'" }

# One elevated window for one step. Its lines count their own failures into $failed, and the window
# exits with that count. A refused prompt fails only this step, and the next step asks again.
function Invoke-ElevatedStep([string] $What, [string[]] $Lines) {
    Write-Host "  - $What"
    $body = @('$ErrorActionPreference = ''Continue''', '$failed = 0') + $Lines + @('exit $failed')
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($body -join "`n")))
    try {
        $elevated = Start-Process -FilePath 'pwsh.exe' -Verb RunAs -Wait -PassThru -ArgumentList @('-NoProfile', '-EncodedCommand', $encoded)
    } catch {
        $failures.Add("${What}: the administrator prompt was refused or could not open ($($_.Exception.Message))")
        return
    }
    if ($elevated.ExitCode -ne 0) { $failures.Add("${What}: the elevated window reported $($elevated.ExitCode) failed step(s), its output names them") }
}

if ($choco.Count -gt 0) {
    $lines = @('if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(''https://community.chocolatey.org/install.ps1'')); $env:Path += '';'' + (Join-Path $env:ProgramData ''chocolatey\bin'') }')
    foreach ($p in $choco) {
        $lines += "choco install $(& $quote $p.Id) -y --no-progress; if (`$LASTEXITCODE -ne 0) { `$failed++ }"
    }
    Invoke-ElevatedStep -What 'the Chocolatey packages' -Lines $lines
}
foreach ($p in $elevatedWinget) {
    Invoke-ElevatedStep -What $p.Id -Lines @("winget $((Get-WingetArgument $p | ForEach-Object { & $quote $_ }) -join ' '); if (`$LASTEXITCODE -ne 0 -and `$LASTEXITCODE -ne -1978335189) { `$failed++ }")
}
if ($wanted | Where-Object { $_.Id -eq 'Syncthing.Syncthing' }) {
    $lines = foreach ($rule in $SyncthingFirewallRules) {
        "if (-not (Get-NetFirewallRule -Name $(& $quote $rule.Name) -ErrorAction SilentlyContinue)) { New-NetFirewallRule -Name $(& $quote $rule.Name) -DisplayName $(& $quote "Syncthing $($rule.Purpose) ($($rule.Protocol) $($rule.Port))") -Group 'Syncthing (InstallationHelper)' -Direction Inbound -Action Allow -Protocol $($rule.Protocol) -LocalPort $($rule.Port) -Profile Private, Domain | Out-Null }"
    }
    Invoke-ElevatedStep -What 'the Syncthing firewall rules' -Lines @($lines)
}

if ($wanted | Where-Object { $_.Id -eq 'Syncthing.Syncthing' }) {
    Write-Step 'Starting Syncthing at your logon'
    $link = Join-Path $env:ProgramFiles 'WinGet\Links\syncthing.exe'
    if (Test-Path -LiteralPath $link) {
        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Syncthing.lnk'))
        $shortcut.TargetPath = $link
        $shortcut.Arguments = $SyncthingStartupArguments
        $shortcut.WindowStyle = 7
        $shortcut.Save()
        Write-Host '  Syncthing starts at your next logon. Its web interface is http://localhost:8384'
    } else {
        $failures.Add("Syncthing: there is no $link, so there is nothing to start at logon")
    }
}

Write-Step 'Done. NOT installed here:'
Write-Host '   - Gridcoin (direct .exe from GitHub releases, see windows_manual_install.md)'
Write-Host '   - DBeaver and OnlyOffice (off by default on Windows, see windows_manual_install.md)'
Write-Host '   - the JDKs, NVM for Windows and Node, Flutter, the Android SDK and the npm CLI tools, which the wizard installs, see windows_manual_install.md'
if ($failures.Count -gt 0) {
    Write-Host "`nFailed:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "   - $_" -ForegroundColor Red }
    exit 1
}
