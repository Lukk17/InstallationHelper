# Software catalog

What the playbook installs on each OS, with a copy-paste command per platform. This file is a quick reference; the authoritative source is `setup/ansible/vars/{Debian,RedHat,Archlinux,Darwin,Windows}.yaml` plus the URL/version pins in [setup/pinned_values/pinned_values.toml](pinned_values/pinned_values.toml). If anything here drifts from a `vars/*.yaml`, trust the YAML.

## How to read this file

Every cell holds the complete command, ready to paste into a terminal. Markdown tables cannot contain fenced code blocks, so commands are formatted as inline code instead.

Cells marked `(repo)` install from an official third-party repository that has to be added first. The keyring and source list commands are in [Repository setup for Debian / Ubuntu](../docs/manual/debian-ubuntu/debian_ubuntu_manual_install.md#repository-setup) and [Repository setup for Fedora](../docs/manual/fedora/fedora_manual_install.md#repository-setup). The playbook does this for you in `debian_repos.yaml` and `fedora_repos.yaml`.

Arch cells using `yay` need an AUR helper. `arch_core` installs one; by hand, bootstrap `yay` first.

Flatpak cells assume the Flathub remote exists:

```bash
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
```

## Installation phase order

The playbook runs in this order. Each phase must succeed before the next can start safely.

1. OS core bootstrap: `system_core`, `arch_core`, `fedora_core`, `debian_core`, `windows_core`, `macos_core` (multilib, locale, keyrings dir, Homebrew bootstrap on macOS).
2. APT / DNF repo provisioning: `roles/software_installer/tasks/debian_repos.yaml` and `fedora_repos.yaml` write keyrings under `/etc/apt/keyrings/` and `*.repo` files for Chrome, Brave, VS Code, Sublime, kubectl, Helm, Terraform, GitHub CLI, Syncthing, Tailscale, Docker before any package install runs.
3. SDK / runtime managers: JVM, Pyenv, NVM, SDKMAN (Java, Gradle), FVM.
4. Snapd and Flatpak with the Flathub remote (Linux).
5. Batched package installs: one call per manager (`apt`, `dnf`, `pacman`, `snap`, `flatpak`, `brew`, `brew_cask`) so dependency resolution happens once per OS.
6. Custom installs: `custom_installs.yaml` (Linux: Gridcoin PPA/repo/flatpak, OpenLens AppImage, GpuTest binary, k3d `install.sh`), `macos_install.yaml` (Antigravity DMG when published, Gridcoin DMG), `windows_install.yaml` (Chocolatey + winget batches, Gridcoin `.exe` silent install).

Gradle is managed via SDKMAN on every Linux distro, not the system package manager. The `pinned_values.toml` pin drives `sdk install gradle`.

## Cross-platform applications

### Browsers

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| Google Chrome | `sudo apt-get install -y google-chrome-stable` (repo) | `sudo dnf install -y google-chrome-stable` (repo) | `yay -S google-chrome` | `brew install --cask google-chrome` | `winget install -e --id Google.Chrome` |
| Brave | `sudo apt-get install -y brave-browser` (repo) | `sudo dnf install -y brave-browser` (repo) | `yay -S brave-bin` | `brew install --cask brave-browser` | `winget install -e --id Brave.Brave` |
| Tor Browser | `flatpak install -y flathub org.torproject.torbrowser-launcher` | `flatpak install -y flathub org.torproject.torbrowser-launcher` | `flatpak install -y flathub org.torproject.torbrowser-launcher` | `brew install --cask tor-browser` | `winget install -e --id TorProject.TorBrowser` |

### Dev tools

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| Git | `sudo apt-get install -y git` | `sudo dnf install -y git` | `sudo pacman -S --needed git` | `brew install git` | `winget install -e --id Git.Git` |
| Maven | `sudo apt-get install -y maven` | `sudo dnf install -y maven` | `sudo pacman -S --needed maven` | `brew install maven` | `choco install maven -y` |
| Gradle | `sdk install gradle` (SDKMAN) | `sdk install gradle` (SDKMAN) | `sudo pacman -S --needed gradle` | `brew install gradle` | `choco install gradle -y` |
| Postman | `flatpak install -y flathub com.getpostman.Postman` | `flatpak install -y flathub com.getpostman.Postman` | `flatpak install -y flathub com.getpostman.Postman` | `brew install --cask postman` | `winget install -e --id Postman.Postman` |
| OpenSSL | `sudo apt-get install -y openssl` | `sudo dnf install -y openssl` | `sudo pacman -S --needed openssl` | `brew install openssl@3` | `winget install -e --id ShiningLight.OpenSSL.Light` |
| DBeaver CE | `flatpak install -y flathub io.dbeaver.DBeaverCommunity` | `flatpak install -y flathub io.dbeaver.DBeaverCommunity` | `flatpak install -y flathub io.dbeaver.DBeaverCommunity` | `brew install --cask dbeaver-community` | `winget install -e --id DBeaver.DBeaver.Community` |
| kubectl | `sudo apt-get install -y kubectl` (repo) | `sudo dnf install -y kubectl` (repo) | `sudo pacman -S --needed kubectl` | `brew install kubernetes-cli` | `winget install -e --id Kubernetes.kubectl` |
| Minikube | `curl -fsSLo /tmp/minikube.deb https://github.com/kubernetes/minikube/releases/download/v1.38.1/minikube_1.38.1-0_amd64.deb && sudo apt-get install -y /tmp/minikube.deb` | `sudo dnf install -y https://github.com/kubernetes/minikube/releases/download/v1.38.1/minikube-1.38.1-0.x86_64.rpm` | `sudo pacman -S --needed minikube` | `brew install minikube` | `winget install -e --id Kubernetes.minikube` |
| k3d | `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh \| bash` | `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh \| bash` | `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh \| bash` | `brew install k3d` | `winget install -e --id k3d.k3d` |
| Helm | `sudo apt-get install -y helm` (repo) | `sudo dnf install -y helm` | `sudo pacman -S --needed helm` | `brew install helm` | `winget install -e --id Helm.Helm` |
| Terraform | `sudo apt-get install -y terraform` (repo) | `sudo dnf install -y terraform` (repo) | `sudo pacman -S --needed terraform` | `brew install hashicorp/tap/terraform` | `winget install -e --id Hashicorp.Terraform` |
| GitHub CLI (gh) | `sudo apt-get install -y gh` (repo) | `sudo dnf install -y gh` | `sudo pacman -S --needed github-cli` | `brew install gh` | `winget install -e --id GitHub.cli` |
| jq | `sudo apt-get install -y jq` | `sudo dnf install -y jq` | `sudo pacman -S --needed jq` | `brew install jq` | `winget install -e --id jqlang.jq` |
| fzf | `sudo apt-get install -y fzf` | `sudo dnf install -y fzf` | `sudo pacman -S --needed fzf` | `brew install fzf` | `winget install -e --id junegunn.fzf` |
| ripgrep | `sudo apt-get install -y ripgrep` | `sudo dnf install -y ripgrep` | `sudo pacman -S --needed ripgrep` | `brew install ripgrep` | `winget install -e --id BurntSushi.ripgrep.MSVC` |
| Lens | `sudo apt-get install -y lens` (repo) | `sudo dnf install -y lens` (repo) | `yay -S lens-bin` | `brew install --cask lens` | `winget install -e --id Mirantis.Lens` |
| FileZilla | `sudo apt-get install -y filezilla` | `sudo dnf install -y filezilla` | `sudo pacman -S --needed filezilla` | `brew install --cask cyberduck` | `choco install filezilla -y` |
| PuTTY | `sudo apt-get install -y putty` | not available | not available | not available | `winget install -e --id PuTTY.PuTTY` |

Terraform on macOS comes from the HashiCorp tap rather than Homebrew core, which dropped it after the BUSL relicense. The tap is added automatically by the fully qualified formula name.

> Lens Desktop is free for personal use and for individuals with annual revenue below USD 10M (see [Lens pricing](https://lenshq.io/pricing)). The playbook installs it from the official apt/dnf repos at `downloads.k8slens.dev`, which give you the same auto-update path the upstream installer uses.

### IDEs and editors

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| JetBrains Toolbox | manual tarball from [jetbrains.com/toolbox-app](https://www.jetbrains.com/toolbox-app/) | manual tarball | `yay -S jetbrains-toolbox` | `brew install --cask jetbrains-toolbox` | manual installer from [jetbrains.com/toolbox-app](https://www.jetbrains.com/toolbox-app/) |
| VS Code | `sudo apt-get install -y code` (repo) | `sudo dnf install -y code` (repo) | `yay -S visual-studio-code-bin` | `brew install --cask visual-studio-code` | `winget install -e --id Microsoft.VisualStudioCode` |
| Sublime Text | `sudo apt-get install -y sublime-text` (repo) | `sudo dnf install -y sublime-text` (repo) | `yay -S sublime-text-4` | `brew install --cask sublime-text` | `winget install -e --id SublimeHQ.SublimeText.4` |
| Arduino IDE 2.x | `flatpak install -y flathub cc.arduino.IDE2` | `flatpak install -y flathub cc.arduino.IDE2` | `flatpak install -y flathub cc.arduino.IDE2` | `brew install --cask arduino-ide` | `winget install -e --id ArduinoSA.IDE.stable` |
| Antigravity | `curl -fsSLo /tmp/antigravity.tar.gz https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/1.13.3-4533425205018624/linux-x64/Antigravity.tar.gz` then extract to `/opt/antigravity` | same tarball as Debian | `yay -S antigravity` | direct DMG from the same CDN, architecture detected by `macos_install.yaml` | `winget install -e --id Google.AntigravityIDE` |
| Bruno | `flatpak install -y flathub com.usebruno.Bruno` | `flatpak install -y flathub com.usebruno.Bruno` | `flatpak install -y flathub com.usebruno.Bruno` | `brew install --cask bruno` | `winget install -e --id Bruno.Bruno` |
| Bruno CLI | `npm install -g @usebruno/cli` | `npm install -g @usebruno/cli` | `npm install -g @usebruno/cli` | `brew install bruno-cli` | `npm install -g @usebruno/cli` |

> IntelliJ has no toggle and no mapping on any platform, on purpose. It is installed and updated through JetBrains Toolbox, which the playbook manages directly, and the first launch needs a sign-in that no unattended run can do anyway. A parallel cask or winget install would only create version drift. macOS carried exactly that duplicate mapping until it was removed, and it could never have installed because no toggle ever reached it.

### Communication

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| Discord | `flatpak install -y flathub com.discordapp.Discord` | `flatpak install -y flathub com.discordapp.Discord` | `flatpak install -y flathub com.discordapp.Discord` | `brew install --cask discord` | `winget install -e --id Discord.Discord` |
| Slack | `flatpak install -y flathub com.slack.Slack` | `flatpak install -y flathub com.slack.Slack` | `flatpak install -y flathub com.slack.Slack` | `brew install --cask slack` | `winget install -e --id SlackTechnologies.Slack` |
| Telegram | `flatpak install -y flathub org.telegram.desktop` | `flatpak install -y flathub org.telegram.desktop` | `sudo pacman -S --needed telegram-desktop` | `brew install --cask telegram` | `winget install -e --id Telegram.TelegramDesktop` |
| Signal | `flatpak install -y flathub org.signal.Signal` | `flatpak install -y flathub org.signal.Signal` | `sudo pacman -S --needed signal-desktop` | `brew install --cask signal` | `winget install -e --id OpenWhisperSystems.Signal` |
| WhatsApp | not on Flathub | not on Flathub | not on Flathub | `brew install --cask whatsapp` | `winget install -e --id 9NKSQGP7F2NH` |
| Microsoft Teams | web only on Linux | web only on Linux | web only on Linux | `brew install --cask microsoft-teams` | `winget install -e --id Microsoft.Teams` |

### Productivity

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| Obsidian | `flatpak install -y flathub md.obsidian.Obsidian` | `flatpak install -y flathub md.obsidian.Obsidian` | `flatpak install -y flathub md.obsidian.Obsidian` | `brew install --cask obsidian` | `winget install -e --id Obsidian.Obsidian` |
| Bitwarden | `flatpak install -y flathub com.bitwarden.desktop` | `flatpak install -y flathub com.bitwarden.desktop` | `flatpak install -y flathub com.bitwarden.desktop` | `brew install --cask bitwarden` | `winget install -e --id Bitwarden.Bitwarden` |
| KeePassXC | `sudo apt-get install -y keepassxc` | `sudo dnf install -y keepassxc` | `sudo pacman -S --needed keepassxc` | `brew install --cask keepassxc` | `winget install -e --id KeePassXCTeam.KeePassXC` |
| Trello | not on Flathub | not on Flathub | not on Flathub | no Homebrew cask | Microsoft Store, no toggle in the playbook |
| OnlyOffice | `flatpak install -y flathub org.onlyoffice.desktopeditors` | `flatpak install -y flathub org.onlyoffice.desktopeditors` | `flatpak install -y flathub org.onlyoffice.desktopeditors` | `brew install --cask onlyoffice` | `winget install -e --id ONLYOFFICE.DesktopEditors` |

### AI

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| ChatGPT desktop | no official build | no official build | no official build | `brew install --cask chatgpt` | `winget install -e --id 9PLM9XGG6VKS --source msstore` |

OpenAI ships the desktop app for macOS and Windows only, so `install_chatgpt` has no mapping in the three Linux dictionaries and the dispatcher skips it there. Register for the Linux client at [openai.com/form/chatgpt-app](https://openai.com/form/chatgpt-app/). The Arch and Debian community packages that claim to provide it repackage OpenAI's macOS bundle, so they are deliberately not wired in.

The Windows entry needs `source: "msstore"` in `vars/Windows.yaml`, because the identifier is a Store product id and the default winget source cannot resolve it. `9NT1R1C2HH7J` is the retired "ChatGPT Classic" listing and `9N8CJ4W95TBZ` is the beta channel, neither is the current app.

The desktop app is the former Codex desktop app renamed, its bundle identifier is still `com.openai.codex` and it reads the same `~/.codex` configuration directory as the Codex command line tool, so one login covers both.

### Media and design

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| VLC | `sudo apt-get install -y vlc` | `sudo dnf install -y vlc` | `sudo pacman -S --needed vlc` | `brew install --cask vlc` | `winget install -e --id VideoLAN.VLC` |
| Spotify | `flatpak install -y flathub com.spotify.Client` | `flatpak install -y flathub com.spotify.Client` | `flatpak install -y flathub com.spotify.Client` | `brew install --cask spotify` | `winget install -e --id Spotify.Spotify` |
| GIMP | `flatpak install -y flathub org.gimp.GIMP` | `flatpak install -y flathub org.gimp.GIMP` | `flatpak install -y flathub org.gimp.GIMP` | `brew install --cask gimp` | `winget install -e --id GIMP.GIMP.3` |
| Krita | `flatpak install -y flathub org.kde.krita` | `flatpak install -y flathub org.kde.krita` | `flatpak install -y flathub org.kde.krita` | `brew install --cask krita` | `winget install -e --id KDE.Krita` |
| HandBrake | `flatpak install -y flathub fr.handbrake.ghb` | `flatpak install -y flathub fr.handbrake.ghb` | `sudo pacman -S --needed handbrake` | `brew install --cask handbrake-app` | `winget install -e --id HandBrake.HandBrake` |
| Audacity | `flatpak install -y flathub org.audacityteam.Audacity` | `flatpak install -y flathub org.audacityteam.Audacity` | `flatpak install -y flathub org.audacityteam.Audacity` | `brew install --cask audacity` | `winget install -e --id Audacity.Audacity` |
| RawTherapee | `sudo apt-get install -y rawtherapee` | `sudo dnf install -y rawtherapee` | `sudo pacman -S --needed rawtherapee` | `brew install --cask rawtherapee` | `winget install -e --id RawTherapee.RawTherapee` |

### Gaming

| App | Linux | macOS | Windows |
|---|---|---|---|
| Steam | Arch: `sudo pacman -S --needed steam` (multilib required). Debian / Fedora: `flatpak install -y flathub com.valvesoftware.Steam` | `brew install --cask steam` | `winget install -e --id Valve.Steam` |
| GOG Galaxy | no official Linux client | `brew install --cask gog-galaxy` | `winget install -e --id GOG.Galaxy` |
| Epic Games Launcher | no official Linux client | `brew install --cask epic-games` | `winget install -e --id EpicGames.EpicGamesLauncher` |
| EA app | no official Linux client | `brew install --cask ea` | `winget install -e --id ElectronicArts.EADesktop` |
| CurseForge | no official Linux client | `brew install --cask curseforge` | `winget install -e --id Overwolf.CurseForge` |
| Razer Cortex | not available | not available | `curl.exe -fsSLo "$env:TEMP\RazerCortexInstaller.exe" https://rzr.to/cortex-download && & "$env:TEMP\RazerCortexInstaller.exe" /S` |
| WoW Logs Companion / TSM | not available | not available | manual, from Overwolf or tradeskillmaster.com |

Razer Cortex has no package on any manager, so the playbook installs it from Razer's own installer in `windows_install.yaml`, the same shape as Gridcoin. The Store product id `9PK9W5QV2PKX` was the Razer Cortex Game Bar widget, which Razer discontinued on 1 July 2026, and it now resolves on neither the winget nor the msstore source. winget-pkgs carries no Cortex manifest under any Razer publisher folder, and Chocolatey has only the Synapse packages. The `/S` switch is the one Razer's own installer family takes, evidenced by the Chocolatey `razer-synapse-4` package driving all five Razer component installers with `silentArgs '/S'` and `validExitCodes 0, 3010, 1641`.

Cortex is the only entry here whose idempotency comes from the uninstall registry rather than a file path. The bootstrapper is a downloader stub that leaves no predictable path to key `creates_path` on, so the task queries both the 64-bit and the WOW6432Node uninstall hives for a `Razer Cortex*` display name and skips when it finds one.

Every Microsoft Store entry carries `source: "msstore"` in `vars/Windows.yaml`. A bare Store product id does not resolve on the default winget source, and because the winget loop sits inside the `software_installer` block, one unresolvable id drops the whole play into the rescue handler and silently skips every package after it.

### Peripherals

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| Razer Synapse | see OpenRazer below | see OpenRazer below | see OpenRazer below | `curl -fsSLo /tmp/RazerSynapseInstaller.pkg https://rzr.to/synapse-4-mac-download && sudo installer -pkg /tmp/RazerSynapseInstaller.pkg -target /` | `choco install razer-synapse-4 -y` |
| OpenRazer | `sudo apt-get install -y openrazer-meta` | `sudo dnf install -y openrazer-meta` (repo first) | `sudo pacman -S --needed openrazer-daemon` | not applicable | not applicable |
| Polychromatic | `flatpak install -y flathub app.polychromatic.controller` | `flatpak install -y flathub app.polychromatic.controller` | `flatpak install -y flathub app.polychromatic.controller` | not available | not applicable |

Windows uses Chocolatey rather than winget, and the reason is concrete. Both winget manifests, `RazerInc.RazerInstaller.Synapse3` at 1.22.0.737 and `RazerInc.RazerInstaller.Synapse4` at 2.5.0.882, declare `InstallerType: exe` with no `InstallerSwitches` block at all. winget therefore has no silent flag to pass and `--silent` leaves you staring at a graphical installer in the middle of an unattended run. The Chocolatey package pulls the five Razer components (App Engine, Synapse 4, Chroma, Central, Game Manager) with pinned sha256 checksums and installs each one silently. Synapse 3 is deliberately not offered, Razer ended its cloud services on 3 February 2026.

macOS has no Homebrew cask, only a `.pkg`, so `macos_install.yaml` downloads and runs it. Razer supports Apple Silicon on macOS 15 Sequoia or newer only, so the task is gated on both and emits a warning instead of installing on anything older or on Intel. Idempotency uses `pkgutil --pkg-info com.razer.install.SynapseInstall`, which is the receipt the distribution package leaves behind, because a multi-component `.pkg` produces no single predictable application bundle.

Linux gets nothing from Razer at all. [OpenRazer](https://openrazer.github.io/) supplies the kernel driver and the daemon, and Polychromatic is only a front end for it, so installing Polychromatic on its own gives you a window that finds no devices. OpenRazer is in Debian proper from bookworm onward and in Ubuntu universe on every current series, so no PPA is needed. Fedora has no package and pulls it from the openSUSE Build Service `hardware:razer` repository, which `fedora_repos.yaml` registers along with the kernel headers the DKMS build needs. On Arch, `extra/openrazer-daemon` depends on `extra/openrazer-driver-dkms`, so the one package brings the driver.

Two things OpenRazer needs that the playbook cannot do for you. The driver is a DKMS module, so it will not load until you reboot, and a Secure Boot machine refuses the unsigned module unless you sign it or turn Secure Boot off. The playbook adds you to `plugdev` for device access and prints a warning naming both requirements when it sees no `razer` module in `lsmod`.

```bash
sudo gpasswd -a $USER plugdev
```

### CAD and 3D

| App | Linux | macOS | Windows |
|---|---|---|---|
| FreeCAD | `flatpak install -y flathub org.freecad.FreeCAD` | `brew install --cask freecad` | `winget install -e --id FreeCAD.FreeCAD` |
| PrusaSlicer | `flatpak install -y flathub com.prusa3d.PrusaSlicer` | `brew install --cask prusaslicer` | `winget install -e --id Prusa3D.PrusaSlicer` |

### Utilities

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| TeamViewer | `curl -fsSLo /tmp/teamviewer.deb https://download.teamviewer.com/download/linux/teamviewer_amd64.deb && sudo apt-get install -y /tmp/teamviewer.deb` | `sudo dnf install -y https://download.teamviewer.com/download/linux/teamviewer.x86_64.rpm` | `yay -S teamviewer` | `brew install --cask teamviewer` | `winget install -e --id TeamViewer.TeamViewer` |
| VeraCrypt | `curl -fsSLo /tmp/veracrypt.deb https://launchpad.net/veracrypt/trunk/1.26.24/+download/veracrypt-1.26.24-Ubuntu-24.04-amd64.deb && sudo apt-get install -y /tmp/veracrypt.deb` | `sudo dnf install -y https://launchpad.net/veracrypt/trunk/1.26.24/+download/veracrypt-1.26.24-CentOS-8-x86_64.rpm` | `sudo pacman -S --needed veracrypt` | `brew install --cask veracrypt` | `winget install -e --id IDRIX.VeraCrypt` |
| Speedtest CLI | `sudo apt-get install -y speedtest-cli` | `sudo dnf install -y speedtest-cli` | `sudo pacman -S --needed speedtest-cli` | `brew install speedtest-cli` | `winget install -e --id Ookla.Speedtest.CLI` |
| Syncthing | `sudo apt-get install -y syncthing` (repo) | `sudo dnf install -y syncthing` | `sudo pacman -S --needed syncthing` | `brew install --cask syncthing-app` | `winget install -e --id BillStewart.SyncthingWindowsSetup` |
| Tailscale | `sudo apt-get install -y tailscale` (repo) | `sudo dnf install -y tailscale` (repo) | `sudo pacman -S --needed tailscale` | `brew install --cask tailscale-app` | `winget install -e --id Tailscale.Tailscale` |
| AppImageLauncher | `curl -fsSLo /tmp/appimagelauncher.deb https://github.com/TheAssassin/AppImageLauncher/releases/download/v2.2.0/appimagelauncher_2.2.0-travis995.0f91801.bionic_amd64.deb && sudo apt-get install -y /tmp/appimagelauncher.deb` | `curl -fsSLo /tmp/appimagelauncher.rpm https://github.com/TheAssassin/AppImageLauncher/releases/download/v2.2.0/appimagelauncher-2.2.0-travis995.0f91801.x86_64.rpm && sudo rpm --install --nodigest /tmp/appimagelauncher.rpm` | `yay -S appimagelauncher` | not available | not available |

Fedora needs the `rpm --nodigest` bypass for AppImageLauncher because the 2020 upstream RPM ships no file digests and dnf5 refuses it.

On Linux the Syncthing package ships `/usr/lib/systemd/user/syncthing.service` disabled. Enable it so Syncthing starts at login as the owner of the synced files, which matches the logon scheduled task the Windows installer registers:

```bash
systemctl --user enable --now syncthing.service
```

The playbook does this in `custom_installs.yaml` and skips it with a warning when there is no active login session, because `systemctl --user` needs a D-Bus session.

The Windows winget package is the Inno installer, which does a per-user install plus a logon scheduled task. `Syncthing.Syncthing` is the bare portable zip with no autostart.

On Linux the playbook enables and starts the `tailscaled` system service in `custom_installs.yaml`. It runs in system scope, not user scope like Syncthing, because the daemon owns a network interface and routing table entries and needs root. Joining a tailnet is deliberately not automated: `sudo tailscale up` opens a browser for interactive authentication, and the alternative, a pre-shared auth key, would be a credential committed to this repository. Run `sudo tailscale up` once by hand after the playbook finishes. On macOS the cask is `tailscale-app`, the graphical application. The bare `tailscale` Homebrew formula is the headless daemon plus the command line client, and the two conflict, so do not install both.

### Crypto / Volunteer

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| BOINC | `sudo apt-get install -y boinc-client` | `sudo dnf install -y boinc-client` | `sudo pacman -S --needed boinc` | `brew install --cask boinc` | `winget install -e --id UCBerkeley.BOINC` |
| Gridcoin | `sudo add-apt-repository -y ppa:gridcoin/gridcoin-stable && sudo apt-get install -y gridcoinresearch` | OpenSUSE build-service repo, see `custom_installs.yaml` | `curl -fsSLo /tmp/gridcoin.flatpak https://github.com/gridcoin-community/Gridcoin-Research/releases/download/5.5.0.0/gridcoin-5.5.0.0-x86_64.flatpak && sudo flatpak install --system --bundle --assumeyes /tmp/gridcoin.flatpak` | DMG from [GitHub releases](https://github.com/gridcoin-community/Gridcoin-Research/releases) | `.exe` from [GitHub releases](https://github.com/gridcoin-community/Gridcoin-Research/releases), silent flag `/S` |

## SDK and runtime managers

Installed by the `sdk_manager` role. All versions are pinned in [setup/pinned_values/pinned_values.toml](pinned_values/pinned_values.toml). Run these as your normal user, not with sudo, and in order, because each writes to your shell rc and has to be sourced before the next.

| Manager / runtime | Linux | macOS | Windows |
|---|---|---|---|
| NVM | `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh \| bash` | `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh \| bash` | `winget install -e --id CoreyButler.NVMforWindows` |
| Node.js LTS | `nvm install --lts` | `nvm install --lts` | `nvm install lts` |
| SDKMAN | `curl -s https://get.sdkman.io \| bash` | `curl -s https://get.sdkman.io \| bash` | not supported, use WSL |
| Java (Temurin) | `sdk install java 21.0.11-tem` | `sdk install java 21.0.11-tem` | `sdk install java 21.0.11-tem` inside WSL |
| Pyenv | `curl https://pyenv.run \| bash` | `curl https://pyenv.run \| bash` | `choco install pyenv-win -y` |
| Python | `pyenv install 3.11.15` | `pyenv install 3.11.15` | `pyenv install 3.11.15` |
| Dart SDK | `sudo apt-get install -y dart` / `sudo dnf install -y dart` / `sudo pacman -S --needed dart` | `brew install dart` | manual from [dart.dev](https://dart.dev/get-dart) |
| FVM (Flutter) | `curl -fsSL https://fvm.app/install.sh \| bash` | `curl -fsSL https://fvm.app/install.sh \| bash` | manual from [fvm.app](https://fvm.app/documentation/getting-started/installation) |
| Flutter (stable) | `fvm install stable` | `fvm install stable` | `fvm install stable` |
| Android SDK | `sdkmanager "platform-tools" "build-tools;35.0.0"` | `sdkmanager "platform-tools" "build-tools;35.0.0"` | install Android Studio, which bundles the SDK manager |

Other pinned Java identifiers are `11.0.31-tem`, `17.0.19-tem` and `25.0.3-tem`. Other pinned Python versions are `3.10.20`, `3.12.13` and `3.13.13`. The defaults are `21.0.11-tem` and `3.11.15`.

## AI tools

Installed by the `ai_tools` role. Each toggle gates its own `import_tasks` so disabled tools never run their setup. The npm ones need Node from NVM first.

| Tool | Linux | macOS | Windows |
|---|---|---|---|
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` | `npm install -g @anthropic-ai/claude-code` | `npm install -g @anthropic-ai/claude-code` |
| Claude Desktop | Arch: `yay -S claude-desktop-bin`. Debian: unofficial APT repo. Fedora: `alien` conversion of the upstream `.deb` | `brew install --cask claude` | `winget install -e --id Anthropic.Claude`, not wired into the playbook |
| OpenCode | `npm install -g opencode-ai` | `npm install -g opencode-ai` | `npm install -g opencode-ai` |
| OpenSpec | `npm install -g openspec` | `npm install -g openspec` | `npm install -g openspec` |
| Codex CLI | `npm install -g @openai/codex` | `npm install -g @openai/codex` | `npm install -g @openai/codex` |
| Grok CLI | `npm install -g @xai-official/grok` | `npm install -g @xai-official/grok` | `npm install -g @xai-official/grok` |
| LM Studio | `curl -fsSL https://lmstudio.ai/install.sh \| bash` | `curl -fsSL https://lmstudio.ai/install.sh \| bash` | manual from [lmstudio.ai](https://lmstudio.ai/) |
| Stable Diffusion WebUI | `git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui` | `git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui` | manual clone and run |

Codex and Grok both publish a thin npm launcher plus per-platform binary packages as optional dependencies, covering Linux, macOS and Windows on x86-64 and arm64, so a single npm path serves every operating system. Native packages exist for some platforms (`extra/openai-codex` on Arch, the `codex` and `grok-build` Homebrew casks, `OpenAI.Codex` and `xAI.GrokBuild` on winget), but no apt or dnf repository exists for either tool, so mixing routes would mean four code paths for the same binary. Grok needs Node 20 or newer, which the `nvm use --lts` step in the helper already satisfies.

### Codex CLI by hand

The playbook installs it under the NVM long-term-support Node, so match that when doing it manually. Linux and macOS:

```bash
source "$HOME/.nvm/nvm.sh" && nvm use --lts && npm install -g @openai/codex
```

Windows:

```powershell
npm install -g @openai/codex
```

Then start it and pick "Sign in with ChatGPT", which covers Plus, Pro, Business, Edu and Enterprise plans:

```bash
codex
```

### Grok CLI by hand

Linux and macOS:

```bash
source "$HOME/.nvm/nvm.sh" && nvm use --lts && npm install -g @xai-official/grok
```

Windows:

```powershell
npm install -g @xai-official/grok
```

First launch opens a browser to sign in. On a headless box export the key instead, Unix shell:

```bash
export XAI_API_KEY="xai-..."
```

Headless on Windows:

```powershell
$env:XAI_API_KEY = "xai-..."
```

Then start it inside the repository you want it to work on:

```bash
grok
```

xAI's own documentation at [docs.x.ai/build/overview](https://docs.x.ai/build/overview) pushes a shell installer instead, `curl -fsSL https://x.ai/cli/install.sh | bash`. The playbook uses the npm package because it is the same publisher, it pins cleanly, and it removes a `curl | bash` from the provisioning path.

## Shell and terminal

Installed by `shell_zsh`.

| Item | Linux | macOS |
|---|---|---|
| zsh | `sudo apt-get install -y zsh` / `sudo dnf install -y zsh` / `sudo pacman -S --needed zsh` | `brew install zsh` |
| Oh My Zsh | `sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended` | `sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended` |
| Powerlevel10k | `git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k` | `git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k` |
| MesloLGS NF | TTF download into `/usr/share/fonts/` | TTF download into `~/Library/Fonts/` |

## Linux-only software

### Security

| App | Debian / Ubuntu | Fedora | Arch |
|---|---|---|---|
| Lynis | `sudo apt-get install -y lynis` | `sudo dnf install -y lynis` | `sudo pacman -S --needed lynis` |
| chkrootkit | `sudo apt-get install -y chkrootkit` | `sudo dnf install -y chkrootkit` | `yay -S chkrootkit` |
| ClamAV | `sudo apt-get install -y clamav` | `sudo dnf install -y clamav` | `sudo pacman -S --needed clamav` |

### Crypto hardware

| App | Method |
|---|---|
| Ledger Live | AppImage from [ledger.com/ledger-live](https://www.ledger.com/ledger-live) |
| Trezor Suite | AppImage from [trezor.io/trezor-suite](https://trezor.io/trezor-suite). The playbook installs the udev rules only, the application is downloaded by hand |

### Hardware monitoring and alternatives

| App | Windows analogue | macOS analogue | Debian / Ubuntu | Fedora | Arch |
|---|---|---|---|---|---|
| HardInfo | HWMonitor | Stats | `sudo apt-get install -y hardinfo` | `sudo dnf install -y hardinfo2` | `sudo pacman -S --needed hardinfo2` |
| lm_sensors | HWiNFO | Stats | `sudo apt-get install -y lm-sensors` | `sudo dnf install -y lm_sensors` | `sudo pacman -S --needed lm_sensors` |
| GreenWithEnvy | MSI Afterburner | not available | `flatpak install -y flathub com.leinardi.gwe` | `flatpak install -y flathub com.leinardi.gwe` | `flatpak install -y flathub com.leinardi.gwe` |
| Baobab | WizTree | GrandPerspective | `sudo apt-get install -y baobab` | `sudo dnf install -y baobab` | `sudo pacman -S --needed baobab` |
| Polychromatic | Razer Synapse | Razer Synapse for Mac | `flatpak install -y flathub app.polychromatic.controller` | `flatpak install -y flathub app.polychromatic.controller` | `flatpak install -y flathub app.polychromatic.controller` |
| GpuTest | FurMark | not available | `curl -fsSLo /tmp/gputest.zip https://ozone3d.net/gputest/dl/GpuTest_Linux_x64_0.7.0.zip && sudo unzip -o /tmp/gputest.zip -d /opt/gputest` | same as Debian | `yay -S gputest` |

Fedora 42 and newer ship `hardinfo2`, the active fork. The legacy `hardinfo` package is gone.

### Virtualization and system

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| QEMU/KVM + virt-manager | `sudo apt-get install -y qemu-kvm libvirt-daemon-system virt-manager virtinst bridge-utils virtiofsd` | `sudo dnf install -y qemu-kvm libvirt virt-manager virt-install bridge-utils virtiofsd` | `sudo pacman -S --needed virt-manager qemu-full libvirt dnsmasq nftables bridge-utils virtiofsd` | not available | not available |
| Docker | `sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin` (repo) | `sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin` (repo) | `sudo pacman -S --needed docker` | `brew install --cask docker-desktop` | `winget install -e --id Docker.DockerDesktop` |
| VirtualBox | not available | not available | not available | not available | `winget install -e --id Oracle.VirtualBox` |
| VMware | not available | not available | not available | `brew install --cask vmware-fusion` | `choco install vmware-workstation-player -y` |
| GParted | `sudo apt-get install -y gparted` | `sudo dnf install -y gparted` | `sudo pacman -S --needed gparted` | not available | not available |
| KDE Partition Manager | `sudo apt-get install -y partitionmanager` | `sudo dnf install -y kde-partitionmanager` | `sudo pacman -S --needed partitionmanager` | not available | not available |
| Boot repair (grubby) | not available | `sudo dnf install -y grubby` | not available | not available | not available |

### Arch Linux helpers

| Tool | Method |
|---|---|
| yay | `git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si` (handled by `arch_core`) |
| paru | `git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si` |
| snapd | `yay -S snapd` |

## macOS-only

`macos_core` bootstraps Homebrew when it is missing:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

| App | Linux analogue | Windows analogue | Install |
|---|---|---|---|
| Stats | HardInfo / lm_sensors | HWMonitor | `brew install --cask stats` |
| GrandPerspective | Baobab | WizTree | `brew install --cask grandperspective` |
| LuLu | ufw / iptables | GlassWire | `brew install --cask lulu` |
| Balena Etcher | not available | Rufus | `brew install --cask balenaetcher` |
| UTM | virt-manager | VirtualBox | `brew install --cask utm` |
| Docker | docker-ce from Docker's own repository, running on the host kernel, command line only with no graphical tool installed | Docker Desktop | Docker Desktop. macOS has no Linux kernel, so the engine always runs in a virtual machine whichever tool provides it |
| VMware Fusion | virt-manager | not available | `brew install --cask vmware-fusion` |

## Windows-only

| App | Category | Linux analogue | macOS analogue | Install |
|---|---|---|---|---|
| PowerShell 7 | shell | bash / zsh | zsh | `winget install -e --id 9MZ1SNWT0N5D --source msstore` |
| HWMonitor | hardware | HardInfo | Stats | `winget install -e --id CPUID.HWMonitor` |
| HWiNFO | hardware | lm_sensors | Stats | `winget install -e --id REALiX.HWiNFO` |
| CrystalDiskInfo | disk health | not available | not available | `winget install -e --id CrystalDewWorld.CrystalDiskInfo` |
| CrystalDiskMark | disk benchmark | not available | not available | `winget install -e --id CrystalDewWorld.CrystalDiskMark` |
| MSI Afterburner | GPU OC | GreenWithEnvy | not available | `winget install -e --id Guru3D.Afterburner` |
| WizTree | disk space | Baobab | GrandPerspective | `winget install -e --id AntibodySoftware.WizTree` |
| Angry IP Scanner | network | not available | not available | `winget install -e --id angryziber.AngryIPScanner` |
| Advanced IP Scanner | network | not available | not available | `winget install -e --id Famatech.AdvancedIPScanner` |
| GlassWire | firewall | ufw / iptables | LuLu | `winget install -e --id GlassWire.GlassWire` |
| TCPView | network | not available | not available | `winget install -e --id Microsoft.Sysinternals.TCPView` |
| Autoruns | system | not available | not available | `winget install -e --id Microsoft.Sysinternals.Autoruns` |
| Rufus | USB creator | Balena Etcher | Balena Etcher | `winget install -e --id Rufus.Rufus` |
| PowerToys | productivity | not available | not available | `winget install -e --id Microsoft.PowerToys` |
| AppControl | task manager with history | HardInfo / lm_sensors | Stats | `winget install -e --id AppControlLabs.AppControlSetup` |
| MiniTool Partition Wizard | disk | GParted | not available | `winget install -e --id MiniTool.PartitionWizard.Free` |
| Samsung Galaxy Buds Manager | audio | not available | not available | `winget install -e --id Samsung.GalaxyBudsManager` |

### Streaming and OEM apps (Windows)

These ship as Microsoft Store packages or have no maintained winget manifest. The toggles in `group_vars/windows.yaml` map them through winget's MS Store ID support where available, and are commented out with a manual install link where they are not.

| App | Install |
|---|---|
| Netflix | `winget install -e --id 9WZDNCRFJ3TJ` |
| Disney+ | `winget install -e --id 9NXQXXLFST89` |
| Prime Video | `winget install -e --id 9P6RC76MSMMJ` |
| iTunes | `winget install -e --id 9PB2MZ1ZMB1S` |
| GeForce Experience | `choco install geforce-experience -y`, disabled by default. NVIDIA discontinued it in favour of the NVIDIA App, which has no winget or Chocolatey manifest |
| VMware Workstation Player | `choco install vmware-workstation-player -y`, no winget manifest post-Broadcom |

## Per-OS install caveats

- **Antigravity Linux**: the official Google APT pool URLs are not publicly addressable, so `custom_installs.yaml` downloads the official tarball from `edgedl.me.gvt1.com` and extracts it to `/opt/antigravity`. The Arch AUR slug `antigravity` works today.
- **Antigravity macOS**: direct DMG from Google's official CDN `edgedl.me.gvt1.com` (Google Video Transcoding, the same CDN Chrome itself uses, owned by Google, not a third-party mirror). `macos_install.yaml` reads `ansible_facts['architecture']` and picks `antigravity_dmg_arm64_url` on Apple Silicon, `antigravity_dmg_x64_url` on Intel. Version pinned in `pinned_values.toml` (`antigravity_version`, `antigravity_build`), bump these when a new release ships at [antigravity.google/download](https://antigravity.google/download).
- **VMware Workstation Player on Windows**: no winget manifest post-Broadcom. Falls back to Chocolatey (`vmware-workstation-player`, verified, installer functional, package itself marked deprecated by maintainer).
- **VMware on macOS**: maps to `vmware-fusion` cask (the macOS-only product, Workstation Player is Windows and Linux).
- **FileZilla on Windows**: FileZilla blocks third-party installers, so winget removed the manifest. Falls back to Chocolatey (`filezilla`, verified).
- **FileZilla on macOS**: no Homebrew cask exists. The `install_filezilla` toggle maps to Cyberduck (cask `cyberduck`), the standard free macOS FTP/SFTP/S3 client. To install FileZilla specifically, set `install_filezilla: false` and download from `filezilla-project.org`.
- **Lens on Linux**: installed from the official `downloads.k8slens.dev` apt/dnf repo, package name `lens`. Lens Desktop is free for personal use.
- **GeForce Experience on Windows**: discontinued by NVIDIA, replaced by the NVIDIA App (which has no winget or Chocolatey manifest). The `install_geforce_experience` toggle defaults to `false` in `group_vars/windows.yaml`, install the NVIDIA App manually from nvidia.com.
- **Gridcoin macOS DMG**: pinned to `5.5.0.0`. Apple Silicon users may want the `-macos-arm64.dmg` variant, today the playbook installs the `x86_64` build via Rosetta. Switching is a one-line change in `pinned_values.toml`.

## Download integrity

The `[checksums]` table in [setup/pinned_values/pinned_values.toml](pinned_values/pinned_values.toml) is injected into Ansible as `download_checksums`. To enforce sha256 verification on `get_url` tasks (AppImages, custom DMG/EXE installers, the Gridcoin flatpak bundle), add entries like:

```toml
[checksums]
jetbrains_toolbox = "sha256:0123abcd..."
gputest = "sha256:..."
antigravity_macos = "sha256:..."
gridcoin_macos = "sha256:..."
gridcoin_flatpak = "sha256:..."
```

Leaving an entry absent disables checksum enforcement for that download, Ansible substitutes `omit`.
### Using Lynis

Moved to [docs/tool_usage.md](../docs/tool_usage.md), which is where usage instructions for installed
tools live now, so this catalogue stays a catalogue.

---
