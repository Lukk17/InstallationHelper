# Manual install — Windows

Install commands for every application [`setup/ansible/vars/Windows.yaml`](../../../setup/ansible/vars/Windows.yaml) maps, via winget and Chocolatey, with the scope each mapping pins. To install the whole default set at once, run [`install.ps1`](install.ps1) from a normal, not elevated, PowerShell 7. It asks for an administrator once per step that needs one: once for the Chocolatey packages, once for Syncthing, and once for Syncthing's firewall rules. `e2e/tier1/manual_windows_install.sh` fails when this page or the script disagrees with the mapping file.

> winget ships with App Installer (Windows 10 1809+/11). Chocolatey is only needed for the `choco` rows below. MS Store apps install through winget's `msstore` source.

Run the commands from a normal PowerShell. A `--scope user` install goes into the profile of whoever runs winget, and Spotify's installer refuses an administrator. The exceptions are marked: a `--scope machine` install of an msix or a portable package only works from an elevated winget, and every `choco` command needs an elevated PowerShell.

## Prerequisites

Install Chocolatey (needed for Maven, Gradle, the Dart SDK, FileZilla, Razer Synapse, HWiNFO, GlassWire, the NVIDIA App and VMware) in an elevated PowerShell:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

## Browsers

| App | Install command |
|---|---|
| Google Chrome | `winget install -e --id Google.Chrome` |
| Brave | `winget install -e --id Brave.Brave --scope machine` |
| Tor Browser | `winget install -e --id TorProject.TorBrowser --scope user` |

## Dev tools

| App | Install command |
|---|---|
| Git | `winget install -e --id Git.Git --scope machine` |
| Maven | `choco install -y maven` |
| Gradle | `choco install -y gradle` |
| Python 3.11 | `winget install -e --id Python.Python.3.11 --scope machine` |
| Dart SDK | `choco install -y dart-sdk` |
| Android Studio | `winget install -e --id Google.AndroidStudio` |
| Postman | `winget install -e --id Postman.Postman --scope user` |
| OpenSSL | `winget install -e --id FireDaemon.OpenSSL` |
| DBeaver CE | `winget install -e --id DBeaver.DBeaver.Community --scope machine` (off by default on Windows, not in install.ps1) |
| kubectl | `winget install -e --id Kubernetes.kubectl` |
| Minikube | `winget install -e --id Kubernetes.minikube` |
| k3d | `winget install -e --id k3d.k3d` |
| Helm | `winget install -e --id Helm.Helm` |
| Terraform | `winget install -e --id Hashicorp.Terraform` |
| GitHub CLI | `winget install -e --id GitHub.cli --scope machine` |
| jq | `winget install -e --id jqlang.jq` |
| fzf | `winget install -e --id junegunn.fzf` |
| ripgrep | `winget install -e --id BurntSushi.ripgrep.MSVC` |
| Lens | `winget install -e --id Mirantis.Lens --scope machine` |
| FileZilla | `choco install -y filezilla` |
| PuTTY | `winget install -e --id PuTTY.PuTTY --scope machine` |
| PowerShell 7 | `winget install -e --id 9MZ1SNWT0N5D --source msstore` |

> OpenSSL comes from FireDaemon because Shining Light's own download answers 404. FileZilla's winget manifest was removed (it blocks third-party installers), so Chocolatey carries it.

## IDEs and editors

| App | Install command |
|---|---|
| VS Code | `winget install -e --id Microsoft.VisualStudioCode --scope machine` |
| Sublime Text | `winget install -e --id SublimeHQ.SublimeText.4 --scope machine` |
| Arduino IDE 2.x | `winget install -e --id ArduinoSA.IDE.stable --scope machine` |
| Antigravity | `winget install -e --id Google.AntigravityIDE --scope user` |
| Bruno | `winget install -e --id Bruno.Bruno --scope machine` |
| JetBrains Toolbox | `winget install -e --id JetBrains.Toolbox --scope user` |

## Communication

| App | Install command |
|---|---|
| Discord | `winget install -e --id Discord.Discord --scope user` |
| Slack | `winget install -e --id SlackTechnologies.Slack --scope user`. Slack's machine-wide msix was refused on Windows Server in GitHub sweep 38130934506, so it stays per user until a Windows 11 test proves that route |
| Microsoft Teams | `winget install -e --id Microsoft.Teams` |
| Telegram | `winget install -e --id Telegram.TelegramDesktop --scope user` |
| Signal | `winget install -e --id OpenWhisperSystems.Signal --scope user` |
| WhatsApp | `winget install -e --id 9NKSQGP7F2NH --source msstore` |

## Productivity

| App | Install command |
|---|---|
| Obsidian | `winget install -e --id Obsidian.Obsidian --scope machine` |
| Bitwarden | `winget install -e --id Bitwarden.Bitwarden --scope machine` |
| KeePassXC | `winget install -e --id KeePassXCTeam.KeePassXC` |
| OnlyOffice | `winget install -e --id ONLYOFFICE.DesktopEditors` (off by default on Windows, not in install.ps1) |

## AI

| App | Install command |
|---|---|
| ChatGPT | `winget install -e --id 9PLM9XGG6VKS --source msstore` |
| Claude Desktop | `winget install -e --id Anthropic.Claude --scope user`. The machine-wide msix was refused on Windows Server in GitHub sweep 38130934506, so it stays per user until a Windows 11 test proves that route |
| LM Studio | `winget install -e --id ElementLabs.LMStudio --scope machine` |
| OpenCode desktop | `winget install -e --id SST.OpenCodeDesktop --scope user` |

## Media and design

| App | Install command |
|---|---|
| VLC | `winget install -e --id VideoLAN.VLC` |
| Spotify | `winget install -e --id Spotify.Spotify --scope user`, from a normal PowerShell, because its installer refuses an administrator |
| GIMP | `winget install -e --id GIMP.GIMP.3 --scope machine` |
| Krita | `winget install -e --id KDE.Krita` |
| HandBrake | `winget install -e --id HandBrake.HandBrake` |
| Audacity | `winget install -e --id Audacity.Audacity` |
| RawTherapee | `winget install -e --id RawTherapee.RawTherapee` |

## Entertainment / streaming (MS Store)

| App | Install command |
|---|---|
| Netflix | `winget install -e --id 9WZDNCRFJ3TJ --source msstore` |
| Disney+ | `winget install -e --id 9NXQXXLFST89 --source msstore` |
| Prime Video | `winget install -e --id 9P6RC76MSMMJ --source msstore` |
| iTunes | `winget install -e --id 9PB2MZ1ZMB1S --source msstore` |

## Gaming

| App | Install command |
|---|---|
| Steam | `winget install -e --id Valve.Steam` |
| GOG Galaxy | `winget install -e --id GOG.Galaxy` |
| Epic Games | `winget install -e --id EpicGames.EpicGamesLauncher` |
| EA app | `winget install -e --id ElectronicArts.EADesktop` |
| CurseForge | `winget install -e --id Overwolf.CurseForge --scope machine` |

> Razer Cortex is no longer offered: its MS Store id was the Game Bar widget Razer discontinued on 2026-07-01, and winget-pkgs carries no Cortex manifest.

## Peripherals

| App | Install command |
|---|---|
| Razer Synapse 4 | `choco install -y razer-synapse-4` |
| Samsung Galaxy Buds Manager | `winget install -e --id Samsung.GalaxyBudsManager` |

## CAD and 3D

| App | Install command |
|---|---|
| FreeCAD | `winget install -e --id FreeCAD.FreeCAD --scope machine` |
| PrusaSlicer | `winget install -e --id Prusa3D.PrusaSlicer` |

## Utilities

| App | Install command |
|---|---|
| TeamViewer | `winget install -e --id TeamViewer.TeamViewer` |
| VeraCrypt | `winget install -e --id IDRIX.VeraCrypt` |
| Speedtest CLI | `winget install -e --id Ookla.Speedtest.CLI` |
| Syncthing | `winget install -e --id Syncthing.Syncthing --scope machine`, from an elevated PowerShell, because winget installs a portable package for all users only when it runs elevated. Then the two steps below |
| Tailscale | `winget install -e --id Tailscale.Tailscale` |
| Rufus | `winget install -e --id Rufus.Rufus` |
| PowerToys | `winget install -e --id Microsoft.PowerToys --scope machine` |
| AppControl | `winget install -e --id AppControlLabs.AppControlSetup` |
| MiniTool Partition Wizard | `winget install -e --id MiniTool.PartitionWizard.Free` (client editions of Windows only) |

Syncthing installs as a bare program with nothing that starts it. To start it at your logon, run this from a normal PowerShell, which puts a shortcut to the link winget keeps in `%ProgramFiles%\WinGet\Links` into your Startup folder:

```powershell
$s = (New-Object -ComObject WScript.Shell).CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\Syncthing.lnk"); $s.TargetPath = "$env:ProgramFiles\WinGet\Links\syncthing.exe"; $s.Arguments = '--no-console --no-browser --no-upgrade'; $s.WindowStyle = 7; $s.Save()
```

To let other devices connect to it directly, open its three ports on the Private and Domain profiles, from an elevated PowerShell:

```powershell
New-NetFirewallRule -Name 'InstallationHelper-Syncthing-TCP-22000' -DisplayName 'Syncthing sync protocol (TCP 22000)' -Group 'Syncthing (InstallationHelper)' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22000 -Profile Private, Domain; New-NetFirewallRule -Name 'InstallationHelper-Syncthing-UDP-22000' -DisplayName 'Syncthing sync protocol over QUIC (UDP 22000)' -Group 'Syncthing (InstallationHelper)' -Direction Inbound -Action Allow -Protocol UDP -LocalPort 22000 -Profile Private, Domain; New-NetFirewallRule -Name 'InstallationHelper-Syncthing-UDP-21027' -DisplayName 'Syncthing local discovery (UDP 21027)' -Group 'Syncthing (InstallationHelper)' -Direction Inbound -Action Allow -Protocol UDP -LocalPort 21027 -Profile Private, Domain
```

> If the older BillStewart.SyncthingWindowsSetup package is still installed, remove it first with `winget uninstall --exact --id BillStewart.SyncthingWindowsSetup`. It starts its own Syncthing at logon, which fights the new one for the same ports. Its uninstaller keeps `%LOCALAPPDATA%\Syncthing`, so devices and folders carry over.

## Hardware and network

| App | Install command |
|---|---|
| HWMonitor | `winget install -e --id CPUID.HWMonitor` |
| HWiNFO | `choco install -y hwinfo.install` |
| CrystalDiskInfo | `winget install -e --id CrystalDewWorld.CrystalDiskInfo` |
| CrystalDiskMark | `winget install -e --id CrystalDewWorld.CrystalDiskMark` |
| MSI Afterburner | `winget install -e --id Guru3D.Afterburner` |
| WizTree | `winget install -e --id AntibodySoftware.WizTree` |
| Angry IP Scanner | `winget install -e --id angryziber.AngryIPScanner` |
| Advanced IP Scanner | `winget install -e --id Famatech.AdvancedIPScanner` |
| GlassWire | `choco install -y glasswire` |
| NVIDIA App | `choco install -y nvidia-app` (only on a machine with an NVIDIA display adapter) |
| TCPView | `winget install -e --id Microsoft.Sysinternals.TCPView` |
| Autoruns | `winget install -e --id Microsoft.Sysinternals.Autoruns` |

> HWiNFO and GlassWire come from Chocolatey because their winget manifests download from locations that answer 404 and 403. The NVIDIA App replaced GeForce Experience, and winget has no manifest for it.

## Crypto / volunteer

| App | Install command |
|---|---|
| BOINC | `winget install -e --id UCBerkeley.BOINC` |

> Gridcoin needs a manual `.exe` install, see below.

## Virtualization

| App | Install command |
|---|---|
| Docker Desktop | `winget install -e --id Docker.DockerDesktop` |
| VirtualBox | `winget install -e --id Oracle.VirtualBox` |
| VMware Workstation Player | `choco install -y vmware-workstation-player` |

> VMware has no winget manifest post-Broadcom; the Chocolatey package is marked deprecated upstream but the installer still works.

## Developer toolchain and AI tools

The wizard installs these natively on Windows, from [`setup/windows/WindowsCustomInstalls.ps1`](../../../setup/windows/WindowsCustomInstalls.ps1) and [`setup/windows/WindowsNpmTools.ps1`](../../../setup/windows/WindowsNpmTools.ps1), with the versions pinned in [`setup/pinned_values/pinned_values.toml`](../../../setup/pinned_values/pinned_values.toml). They are not in install.ps1. By hand:

| Tool | Install command |
|---|---|
| Java (Temurin JDK 11, 17, 21 and 25) | `winget install -e --id EclipseAdoptium.Temurin.21.JDK`, once per major version |
| NVM for Windows | `winget install -e --id CoreyButler.NVMforWindows`, then `nvm install lts` and `nvm use lts` in a new shell |
| Flutter | `dart pub global activate fvm` (needs the Dart SDK above), then `fvm install stable` and `fvm global stable` |
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` *(needs Node)* |
| OpenCode | `npm install -g @opencode/cli`, after `npm uninstall -g opencode-ai` if version 1 is installed, because both claim the `opencode` command |
| OpenSpec | `npm install -g @fission-ai/openspec` |
| Codex | `npm install -g @openai/codex` |
| Grok | `npm install -g @xai-official/grok` |
| Bruno CLI | `npm install -g @usebruno/cli` |

## Manual install required

**Gridcoin** (pinned `5.5.0.0`) has no winget manifest, so install the NSIS `.exe` from GitHub releases. In an elevated PowerShell:

```powershell
Invoke-WebRequest -Uri "https://github.com/gridcoin-community/Gridcoin-Research/releases/download/5.5.0.0/gridcoin-5.5.0.0-win64-setup.exe" -OutFile "$env:TEMP\Gridcoin-Setup.exe"
```

```powershell
Start-Process -FilePath "$env:TEMP\Gridcoin-Setup.exe" -ArgumentList "/S" -Wait
```
