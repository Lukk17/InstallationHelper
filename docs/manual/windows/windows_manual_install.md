# Manual install — Windows

Install commands for every app the playbook manages on Windows, via winget and Chocolatey. To install the whole set at once, run [`install.ps1`](install.ps1) from an **elevated** PowerShell.

> winget ships with App Installer (Windows 10 1809+/11). Chocolatey is only needed for the five `choco` apps below. MS Store apps install through winget's Store ID support.

## Prerequisites

Install Chocolatey (needed for Maven, Gradle, FileZilla, VMware) in an elevated PowerShell:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

## Browsers

| App | Install command |
|---|---|
| Google Chrome | `winget install -e --id Google.Chrome` |
| Brave | `winget install -e --id Brave.Brave` |
| Tor Browser | `winget install -e --id TorProject.TorBrowser` |

## Dev tools

| App | Install command |
|---|---|
| Git | `winget install -e --id Git.Git` |
| Maven | `choco install -y maven` |
| Gradle | `choco install -y gradle` |
| Postman | `winget install -e --id Postman.Postman` |
| OpenSSL | `winget install -e --id ShiningLight.OpenSSL.Light` |
| DBeaver CE | `winget install -e --id DBeaver.DBeaver.Community` — off by default on Windows (not in install.ps1) |
| kubectl | `winget install -e --id Kubernetes.kubectl` |
| Minikube | `winget install -e --id Kubernetes.minikube` |
| k3d | `winget install -e --id k3d.k3d` |
| Lens | `winget install -e --id Mirantis.Lens` |
| FileZilla | `choco install -y filezilla` |
| PuTTY | `winget install -e --id PuTTY.PuTTY` |

> FileZilla's winget manifest was removed (it blocks third-party installers); Chocolatey carries it.

## IDEs and editors

| App | Install command |
|---|---|
| VS Code | `winget install -e --id Microsoft.VisualStudioCode` |
| Sublime Text | `winget install -e --id SublimeHQ.SublimeText.4` |
| Arduino IDE 2.x | `winget install -e --id ArduinoSA.IDE.stable` |
| Antigravity | `winget install -e --id Google.AntigravityIDE` |
| Bruno | `winget install -e --id Bruno.Bruno` |

## Communication

| App | Install command |
|---|---|
| Discord | `winget install -e --id Discord.Discord` |
| Slack | `winget install -e --id SlackTechnologies.Slack` |
| Microsoft Teams | `winget install -e --id Microsoft.Teams` |
| Telegram | `winget install -e --id Telegram.TelegramDesktop` |
| Signal | `winget install -e --id OpenWhisperSystems.Signal` |
| WhatsApp | `winget install -e --id 9NKSQGP7F2NH` *(MS Store)* |

## Productivity

| App | Install command |
|---|---|
| Obsidian | `winget install -e --id Obsidian.Obsidian` |
| Bitwarden | `winget install -e --id Bitwarden.Bitwarden` |
| KeePassXC | `winget install -e --id KeePassXCTeam.KeePassXC` |
| OnlyOffice | `winget install -e --id ONLYOFFICE.DesktopEditors` — off by default on Windows (not in install.ps1) |

## Media and design

| App | Install command |
|---|---|
| VLC | `winget install -e --id VideoLAN.VLC` |
| Spotify | `winget install -e --id Spotify.Spotify` |
| GIMP | `winget install -e --id GIMP.GIMP.3` |
| Krita | `winget install -e --id KDE.Krita` |
| HandBrake | `winget install -e --id HandBrake.HandBrake` |
| Audacity | `winget install -e --id Audacity.Audacity` |
| RawTherapee | `winget install -e --id RawTherapee.RawTherapee` |

## Entertainment / streaming (MS Store)

| App | Install command |
|---|---|
| Netflix | `winget install -e --id 9WZDNCRFJ3TJ` |
| Disney+ | `winget install -e --id 9NXQXXLFST89` |
| Prime Video | `winget install -e --id 9P6RC76MSMMJ` |
| iTunes | `winget install -e --id 9PB2MZ1ZMB1S` |

## Gaming

| App | Install command |
|---|---|
| Steam | `winget install -e --id Valve.Steam` |
| GOG Galaxy | `winget install -e --id GOG.Galaxy` |
| Epic Games | `winget install -e --id EpicGames.EpicGamesLauncher` |
| EA app | `winget install -e --id ElectronicArts.EADesktop` |
| CurseForge | `winget install -e --id Overwolf.CurseForge` |
| Razer Cortex | `winget install -e --id 9PK9W5QV2PKX` *(MS Store)* |

## CAD and 3D

| App | Install command |
|---|---|
| FreeCAD | `winget install -e --id FreeCAD.FreeCAD` |
| PrusaSlicer | `winget install -e --id Prusa3D.PrusaSlicer` |

## Utilities

| App | Install command |
|---|---|
| TeamViewer | `winget install -e --id TeamViewer.TeamViewer` |
| VeraCrypt | `winget install -e --id IDRIX.VeraCrypt` |
| Speedtest CLI | `winget install -e --id Ookla.Speedtest.CLI` |
| Rufus | `winget install -e --id Rufus.Rufus` |
| PowerToys | `winget install -e --id Microsoft.PowerToys` |
| MiniTool Partition Wizard | `winget install -e --id MiniTool.PartitionWizard.Free` |
| Samsung Galaxy Buds Manager | `winget install -e --id Samsung.GalaxyBudsManager` |

## Hardware and network

| App | Install command |
|---|---|
| HWMonitor | `winget install -e --id CPUID.HWMonitor` |
| HWiNFO | `winget install -e --id REALiX.HWiNFO` |
| CrystalDiskInfo | `winget install -e --id CrystalDewWorld.CrystalDiskInfo` |
| CrystalDiskMark | `winget install -e --id CrystalDewWorld.CrystalDiskMark` |
| MSI Afterburner | `winget install -e --id Guru3D.Afterburner` |
| WizTree | `winget install -e --id AntibodySoftware.WizTree` |
| Angry IP Scanner | `winget install -e --id angryziber.AngryIPScanner` — off by default on Windows (not in install.ps1) |
| Advanced IP Scanner | `winget install -e --id Famatech.AdvancedIPScanner` |
| GlassWire | `winget install -e --id GlassWire.GlassWire` |
| TCPView | `winget install -e --id Microsoft.Sysinternals.TCPView` |
| Autoruns | `winget install -e --id Microsoft.Sysinternals.Autoruns` |
| GeForce Experience | **Discontinued** — NVIDIA replaced it with the NVIDIA App; install that from nvidia.com instead |

## Crypto / volunteer

| App | Install command |
|---|---|
| BOINC | `winget install -e --id UCBerkeley.BOINC` |

> Gridcoin needs a manual `.exe` install — see below.

## Virtualization

| App | Install command |
|---|---|
| Docker Desktop | `winget install -e --id Docker.DockerDesktop` |
| VirtualBox | `winget install -e --id Oracle.VirtualBox` |
| VMware Workstation Player | `choco install -y vmware-workstation-player` |

> VMware has no winget manifest post-Broadcom; the Chocolatey package is marked deprecated upstream but the installer still works.

## Developer toolchain and AI tools

On Windows the playbook runs the Linux dev toolchain (NVM, SDKMAN, Pyenv, FVM) **inside WSL** — follow [the Debian/Ubuntu page → Developer toolchain](../debian-ubuntu/debian_ubuntu_manual_install.md#developer-toolchain-sdk--runtimes) in your WSL shell. Windows-native options:

| Tool | Install command |
|---|---|
| Node.js LTS | `winget install -e --id OpenJS.NodeJS.LTS` |
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` *(needs Node)* |
| OpenCode | `npm install -g opencode-ai` |
| OpenSpec | `npm install -g openspec` |

## Manual install required

**Gridcoin** (pinned `5.5.0.0`) — no winget manifest; install the NSIS `.exe` from GitHub releases. In an elevated PowerShell:

```powershell
Invoke-WebRequest -Uri "https://github.com/gridcoin-community/Gridcoin-Research/releases/download/5.5.0.0/gridcoin-5.5.0.0-win64-setup.exe" -OutFile "$env:TEMP\Gridcoin-Setup.exe"
```

```powershell
Start-Process -FilePath "$env:TEMP\Gridcoin-Setup.exe" -ArgumentList "/S" -Wait
```
