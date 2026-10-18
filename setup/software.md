# Software catalog

What the playbook installs on each OS, with a copy-paste command per platform. This file is a quick reference; the authoritative source is `setup/ansible/vars/{Debian,RedHat,Archlinux,Darwin,Windows}.yaml` plus the URL/version pins in [setup/pinned_values/pinned_values.toml](pinned_values/pinned_values.toml). If anything here drifts from a `vars/*.yaml`, trust the YAML.

## How to read this file

Every cell holds the complete command, ready to paste into a terminal. Markdown tables cannot contain fenced code blocks, so commands are formatted as inline code instead.

Cells marked `(repo)` install from an official third-party repository that has to be added first. The keyring and source list commands are in [Repository setup for Debian / Ubuntu](../docs/manual/debian-ubuntu/debian_ubuntu_manual_install.md#repository-setup) and [Repository setup for Fedora](../docs/manual/fedora/fedora_manual_install.md#repository-setup). The playbook does this for you in `debian_repos.yaml` and `fedora_repos.yaml`.

Arch cells using `yay` are the commands to type by hand and need an AUR helper, so bootstrap `yay` first. The playbook itself installs every AUR package through `paru`, which `arch_core` builds, and builds `yay` only when `install_yay` is on.

Windows cells leave out the scope. The wizard installs every program machine-wide where a working machine-wide route exists, and per user only where none exists, the vendor advises per user, or the machine-wide route failed in testing, as Slack's and Claude Desktop's msix did on Windows Server, so it adds `--scope machine` or `--scope user` from the `scope` of each mapping in `vars/Windows.yaml`, where the reason for every per-user one is written beside it. Add the same flag when you paste a command by hand, and run a `--scope machine` command from an elevated shell, because winget refuses a machine-wide msix or portable install from a shell that is not elevated. When a program the wizard installs machine-wide is already installed for your user only, the wizard reports that with the `winget uninstall` command for the per-user copy and installs nothing beside it.

Flatpak cells assume the Flathub remote exists:

```bash
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
```

## Installation phase order

The playbook runs in this order. Each phase must succeed before the next can start safely.

1. OS core bootstrap: `system_core`, `arch_core`, `fedora_core`, `debian_core`, `macos_core` (multilib, locale, keyrings dir, Homebrew bootstrap on macOS). There is no Windows role, because the playbook never runs on Windows.
2. APT / DNF repo provisioning: `roles/software_installer/tasks/debian_repos.yaml` and `fedora_repos.yaml` write keyrings under `/etc/apt/keyrings/` and `*.repo` files for Chrome, Brave, VS Code, Sublime, kubectl, Helm, Terraform, GitHub CLI, Syncthing, Tailscale, Docker before any package install runs.
3. SDK / runtime managers: JVM, Pyenv, NVM, SDKMAN (Java, Gradle), FVM.
4. Snapd and Flatpak with the Flathub remote (Linux). Snapd only under `install_snapd`, on every Linux family alike. With it off, every application mapped to snap on that machine is skipped and named in a `[WARN]` line at the end of the run, and the wizard's checklist names those applications beside the Snapd entry before the run starts.
5. Package installs: one call per package for every manager (`apt`, `dnf`, `pacman`, `snap`, `flatpak`, `brew`, `brew_cask`), so one failure names the package that broke and costs only that package. The packages a role names in its own tasks, the desktops, QEMU/KVM, Docker and the build dependencies among them, go one per call too, through `setup/ansible/tasks/install_role_packages.yaml`. The software set's pacman packages go through that same file, so pacman tries each package once against the index the system was upgraded against and refreshes the index only before retrying a package that failed. The CachyOS graphics alignment installs `mesa-git` and then `lib32-mesa-git`, one per call, in the same shape. `e2e/tier1/batched_managers.sh` fails on any manager that hands its whole set to one call, with no exception.
Razer Cortex was removed on 2026-08-22 at the owner's request. It is a game launcher rather than
device software, its installer exited 0 without installing anything under `/S`, and Razer ships
no switch it will admit to. Razer Synapse 4 stays and is what configures the devices, through the
Chocolatey `razer-synapse-4` package on Windows.

6. Custom installs: `custom_installs.yaml` (Linux: Gridcoin PPA/repo/flatpak, OpenLens AppImage, GpuTest binary, k3d `install.sh`), `macos_install.yaml` (Razer Synapse PKG, Gridcoin DMG). Windows takes none of this path. `setup/windows/WindowsSoftware.ps1` runs the Chocolatey and winget batches natively and `setup/windows/WindowsCustomInstalls.ps1` runs the Gridcoin and OpenCode desktop silent installs.

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
| OpenSSL | `sudo apt-get install -y openssl` | `sudo dnf install -y openssl` | `sudo pacman -S --needed openssl` | `brew install openssl@3` | `winget install -e --id FireDaemon.OpenSSL` |
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
| uv | `curl -fsSL https://astral.sh/uv/install.sh \| sudo UV_UNMANAGED_INSTALL=/usr/local/bin sh` | `sudo dnf install -y uv` | `sudo pacman -S --needed uv` | `brew install uv` | `winget install -e --id astral-sh.uv` |
| pipx | `sudo apt-get install -y pipx` | `sudo dnf install -y pipx` | `sudo pacman -S --needed python-pipx` | `brew install pipx` | `py -m pip install --user pipx` then `py -m pipx ensurepath` |
| Go | `sudo apt-get install -y golang-go` | `sudo dnf install -y golang` | `sudo pacman -S --needed go` | `brew install go` | `winget install -e --id GoLang.Go` |
| Lens | `sudo apt-get install -y lens` (repo) | `sudo dnf install -y lens` (repo) | `yay -S lens-bin` | `brew install --cask lens` | `winget install -e --id Mirantis.Lens` |
| FileZilla | `sudo apt-get install -y filezilla` | `sudo dnf install -y filezilla` | `sudo pacman -S --needed filezilla` | `brew install --cask cyberduck` | `choco install filezilla -y` |
| PuTTY | `sudo apt-get install -y putty` | `sudo dnf install -y putty` | `sudo pacman -S --needed putty` | not available | `winget install -e --id PuTTY.PuTTY` |
| rclone | `sudo apt-get install -y rclone` | `sudo dnf install -y rclone` | `sudo pacman -S --needed rclone` | not installed, `install_rclone` is a Linux toggle | not installed, `install_rclone` is a Linux toggle |
| QasTools (QasMixer, QasHctl, QasConfig) | `for package in qasmixer qashctl qasconfig; do sudo apt-get install -y "${package}"; done` | `sudo dnf install -y qastools` | `sudo pacman -S --needed qastools` | not installed, `install_qastools` is a Linux toggle | not installed, `install_qastools` is a Linux toggle |

Terraform on macOS comes from the HashiCorp tap rather than Homebrew core, which dropped it after the BUSL relicense. The tap is added automatically by the fully qualified formula name.

pipx on Windows comes from pip inside the Python the wizard installs, which is pipx's own documented Windows route, rather than from a package manager. winget has no pipx, and Chocolatey's `pipx` depends on `python3`, which installs a second, newer Python ahead of the pinned 3.11 on PATH. The KDE role installs the same pipx package on Linux for Konsave even when `install_pipx` is off, because it runs before the software installer.

> Lens Desktop is free for personal use and for individuals with annual revenue below USD 10M (see [Lens pricing](https://lenshq.io/pricing)). The playbook installs it from the official apt/dnf repos at `downloads.k8slens.dev`, which give you the same auto-update path the upstream installer uses.

### IDEs and editors

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| JetBrains Toolbox | JetBrains' tarball from `data.services.jetbrains.com/products/download?platform=linux&code=TBA`, unpacked with `--strip-components=1` into `~/.local/share/JetBrains/Toolbox`, so it starts as `~/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox` | same tarball as Debian | `yay -S jetbrains-toolbox` | `brew install --cask jetbrains-toolbox` | `winget install -e --id JetBrains.Toolbox` |
| VS Code | `sudo apt-get install -y code` (repo) | `sudo dnf install -y code` (repo) | `yay -S visual-studio-code-bin` | `brew install --cask visual-studio-code` | `winget install -e --id Microsoft.VisualStudioCode` |
| Sublime Text | `sudo apt-get install -y sublime-text` (repo) | `sudo dnf install -y sublime-text` (repo) | `yay -S sublime-text-4` | `brew install --cask sublime-text` | `winget install -e --id SublimeHQ.SublimeText.4` |
| Arduino IDE 2.x | `flatpak install -y flathub cc.arduino.IDE2` | `flatpak install -y flathub cc.arduino.IDE2` | `flatpak install -y flathub cc.arduino.IDE2` | `brew install --cask arduino-ide` | `winget install -e --id ArduinoSA.IDE.stable` |
| Antigravity | `curl -fsSLo /tmp/antigravity.tar.gz https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/1.13.3-4533425205018624/linux-x64/Antigravity.tar.gz` then extract to `/opt/antigravity` | same tarball as Debian | `yay -S antigravity` | `brew install --cask antigravity` | `winget install -e --id Google.AntigravityIDE` |
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
| Zoom | `flatpak install -y flathub us.zoom.Zoom` | `flatpak install -y flathub us.zoom.Zoom` | `yay -S zoom` | `brew install --cask zoom` | `winget install -e --id Zoom.Zoom` |

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
| OpenCode desktop | `curl -fsSLo /tmp/opencode-desktop.deb https://opencode.ai/files/bin/2.0.29/opencode-desktop-linux-amd64.deb && sudo apt-get install -y /tmp/opencode-desktop.deb` | `sudo dnf install -y https://opencode.ai/files/bin/2.0.29/opencode-desktop-linux-x86_64.rpm` | `yay -S opencode-desktop-bin` | `brew install --cask opencode-desktop` | the vendor installer, `opencode-desktop-win-x64.exe` from `https://opencode.ai/files/bin/2.0.29/`, run with `/S` |

OpenAI ships the desktop app for macOS and Windows only, so `install_chatgpt` has no mapping in the three Linux dictionaries and the dispatcher skips it there. Register for the Linux client at [openai.com/form/chatgpt-app](https://openai.com/form/chatgpt-app/). The Arch and Debian community packages that claim to provide it repackage OpenAI's macOS bundle, so they are deliberately not wired in.

The Windows entry needs `source: "msstore"` in `vars/Windows.yaml`, because the identifier is a Store product id and the default winget source cannot resolve it. `9NT1R1C2HH7J` is the retired "ChatGPT Classic" listing and `9N8CJ4W95TBZ` is the beta channel, neither is the current app.

The desktop app is the former Codex desktop app renamed, its bundle identifier is still `com.openai.codex` and it reads the same `~/.codex` configuration directory as the Codex command line tool, so one login covers both.

OpenCode desktop is `install_opencode_desktop`, on by default, and installs version 2 everywhere. Version 2 is in no package manager on Debian, Ubuntu, Fedora or Windows, as read on 2026-10-15: Flathub's `ai.opencode.opencode` is version 1 (1.18.8), winget's `SST.OpenCodeDesktop` is version 1 (1.19.0), Chocolatey's `opencode-desktop` is version 1 (1.17.9), and there is no snap, apt or dnf repository. So those three take the vendor's own `.deb`, `.rpm` and signed installer, at the version `opencode_desktop_version` pins in [pinned_values.toml](pinned_values/pinned_values.toml). Arch takes the AUR `opencode-desktop-bin`, which repackages the same `.deb`, and macOS the `opencode-desktop` cask, which is version 2 as well. The `.deb` and `.rpm` do not update themselves, the playbook moves them when the pin moves, while the Windows and macOS builds update themselves. Version 1 and version 2 share `~/.local/share/opencode`, and version 1 refuses to start once version 2 has created its database. So whichever version is selected, the run removes the other one's command line tool and desktop app and moves a data folder the selected version cannot open aside, see the next paragraph. `SST.opencode` in winget is the command line tool, which this repository installs from npm instead, see AI tools below.

OpenCode version 1 is `opencode_use_v1`, off by default and labelled `Switch OpenCode from v2 to v1` on both wizards' checklists. When it is on, every OS installs version 1 instead of version 2: the npm package `opencode-ai` for the command line tool, and for the desktop app Flathub's `ai.opencode.opencode` on Linux, winget's `SST.OpenCodeDesktop` on Windows and the vendor DMG from the GitHub release on macOS, pinned as `opencode_desktop_v1_version`, because Homebrew has no version 1 cask. The decision is made once, in [ansible/tasks/opencode_version.yaml](ansible/tasks/opencode_version.yaml) for Linux and macOS and by `Get-OpenCodeVersion` in [windows/WindowsSoftware.ps1](windows/WindowsSoftware.ps1) for Windows, and the install, the removal of the other version and the verification all read it. Removal is logged as `[INFO] removed OpenCode v1 desktop because v2 is selected`, and the verification fails while the other version is still installed. The data folder is `~/.local/share/opencode` on every OS, `XDG_DATA_HOME` when that is set: switching to version 1 moves a folder holding version 2 data to `opencode.v2-backup-<date>-<time>` beside it and brings no earlier version 1 backup back, so version 1 always starts clean. Switching back to version 2 moves version 1 data to `opencode.v1-backup-<date>-<time>` when a version 2 backup exists and brings the newest version 2 backup back. Nothing is deleted, so earlier version 1 sessions stay in their backup folders, and you can move one back into `opencode` by hand while version 1 is selected. Version 2 opens version 1 data by itself, migrating it in place, so with no version 2 backup that data stays where it is.

`setup.sh --software all` and `setup.ps1 -Software all` leave `opencode_use_v1` off, so "install everything" keeps OpenCode on version 2. Select-all on either wizard's checklist leaves it off too, because neither checklist can leave one item out of a select-all: every item ticked is read as select-all, and the checklist header says so. Turn it on with `--enable opencode_use_v1` or `-EnableKey opencode_use_v1`, or tick it on the checklist with anything less than every item ticked. The two wizards keep the keys "all" leaves off in `ALL_SOFTWARE_KEEPS_OFF` in [setup.sh](setup.sh) and `$AllSoftwareKeepsOff` in [setup.ps1](setup.ps1), and `e2e/tier1/wizard_parse.sh` fails when the two disagree.

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
| CurseForge | `flatpak install -y flathub com.overwolf.curseforge` on every distribution | `brew install --cask curseforge` | `winget install -e --id Overwolf.CurseForge` |
| Gaming suite (Lutris) | Arch: `sudo pacman -S --needed lutris`. CachyOS: `sudo pacman -S --needed cachyos-gaming-applications`, which also installs Steam, Heroic, Faugus, gamescope, MangoHud, GOverlay and `cachyos-gaming-meta`. Debian / Fedora: `flatpak install -y flathub net.lutris.Lutris` | not available | not available |
| WoW Logs Companion / TSM | not available | not available | manual, from Overwolf or tradeskillmaster.com |



Every Microsoft Store entry carries `source: "msstore"` in `vars/Windows.yaml`. A bare Store product id does not resolve on the default winget source, and an id that resolves on neither source is reported as that package's own failure by `setup/windows/WindowsSoftware.ps1` rather than taking the rest of the catalogue with it.

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
| Syncthing | `sudo apt-get install -y syncthing` (repo) | `sudo dnf install -y syncthing` | `sudo pacman -S --needed syncthing` | `brew install --cask syncthing-app` | `winget install -e --id Syncthing.Syncthing` |
| Tailscale | `sudo apt-get install -y tailscale` (repo) | `sudo dnf install -y tailscale` (repo) | `sudo pacman -S --needed tailscale` | `brew install --cask tailscale-app` | `winget install -e --id Tailscale.Tailscale` |
| AppImageLauncher | `curl -fsSLo /tmp/appimagelauncher.deb https://github.com/TheAssassin/AppImageLauncher/releases/download/v2.2.0/appimagelauncher_2.2.0-travis995.0f91801.bionic_amd64.deb && sudo apt-get install -y /tmp/appimagelauncher.deb` | `curl -fsSLo /tmp/appimagelauncher.rpm https://github.com/TheAssassin/AppImageLauncher/releases/download/v2.2.0/appimagelauncher-2.2.0-travis995.0f91801.x86_64.rpm && sudo rpm --install --nodigest /tmp/appimagelauncher.rpm` | `yay -S appimagelauncher` | not available | not available |

Fedora needs the `rpm --nodigest` bypass for AppImageLauncher because the 2020 upstream RPM ships no file digests and dnf5 refuses it.

On Linux the Syncthing package ships `/usr/lib/systemd/user/syncthing.service` disabled. Enable it so Syncthing starts at login as the owner of the synced files, which matches the Startup folder shortcut the Windows wizard creates:

```bash
systemctl --user enable --now syncthing.service
```

The playbook does this in `custom_installs.yaml` and skips it with a warning when there is no active login session, because `systemctl --user` needs a D-Bus session.

On Windows the wizard installs Syncthing's own build, `Syncthing.Syncthing`, machine-wide: winget extracts the portable zip under `%ProgramFiles%\WinGet\Packages` and links `syncthing.exe` into `%ProgramFiles%\WinGet\Links`. winget installs a portable machine-wide only when winget itself runs elevated, so the wizard runs that one install in an elevated child and Windows asks for consent. Then, as your normal user, it does three things:

1. Puts a `Syncthing` shortcut in `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup` that starts the link with `--no-console --no-browser --no-upgrade`, the Startup folder route from Syncthing's own autostart guide. `--no-upgrade` is there because a standard user cannot replace the binary under Program Files, so `winget upgrade` updates it instead. Syncthing starts at your next logon, and its web interface is at `http://localhost:8384`. Each user's configuration stays in their own `%LOCALAPPDATA%\Syncthing`.
2. Allows inbound TCP 22000, UDP 22000 and UDP 21027 on the Private and Domain profiles, the ports Syncthing's firewall guide lists, through one more elevated step when they are missing. By port and not by program, because every Syncthing version lands in its own versioned folder and a process started through the link runs under that versioned path, so a rule on the program would stop matching at the first upgrade. Without the rules Syncthing still syncs through its relays, only more slowly.
3. Reports the older `BillStewart.SyncthingWindowsSetup` if it is still installed, with the command that removes it, because it starts its own Syncthing at logon and the two fight over the same ports. Its uninstaller keeps `%LOCALAPPDATA%\Syncthing`, so your devices and folders carry over. The wizard removes nothing by itself.

`winget configure` with `setup\manifests\configuration.winget` installs the same package without any of the three steps above, and the generated file names no scope, so winget chooses one there.

On Linux the playbook enables and starts the `tailscaled` system service in `custom_installs.yaml`. It runs in system scope, not user scope like Syncthing, because the daemon owns a network interface and routing table entries and needs root. Joining a tailnet is deliberately not automated: `sudo tailscale up` opens a browser for interactive authentication, and the alternative, a pre-shared auth key, would be a credential committed to this repository. Run `sudo tailscale up` once by hand after the playbook finishes. On macOS the cask is `tailscale-app`, the graphical application. The bare `tailscale` Homebrew formula is the headless daemon plus the command line client, and the two conflict, so do not install both.

### Crypto / Volunteer

| App | Debian / Ubuntu | Fedora | Arch | macOS | Windows |
|---|---|---|---|---|---|
| BOINC | `sudo apt-get install -y boinc-client` | `sudo dnf install -y boinc-client` | `sudo pacman -S --needed boinc` | `brew install --cask boinc` | `winget install -e --id UCBerkeley.BOINC` |
| Gridcoin | `sudo add-apt-repository -y ppa:gridcoin/gridcoin-stable && sudo apt-get install -y gridcoinresearch` | OpenSUSE build-service repo, see `custom_installs.yaml` | `curl -fsSLo /tmp/gridcoin.flatpak https://github.com/gridcoin-community/Gridcoin-Research/releases/download/5.5.0.0/gridcoin-5.5.0.0-x86_64.flatpak && sudo flatpak install --system --noninteractive --bundle --assumeyes /tmp/gridcoin.flatpak` | DMG from [GitHub releases](https://github.com/gridcoin-community/Gridcoin-Research/releases) | `.exe` from [GitHub releases](https://github.com/gridcoin-community/Gridcoin-Research/releases), silent flag `/S` |

## SDK and runtime managers

Installed by the `sdk_manager` role. All versions are pinned in [setup/pinned_values/pinned_values.toml](pinned_values/pinned_values.toml). Run these as your normal user, not with sudo, and in order, because each writes to your shell rc and has to be sourced before the next.

| Manager / runtime | Linux | macOS | Windows |
|---|---|---|---|
| NVM | `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh \| bash` | `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh \| bash` | `winget install -e --id CoreyButler.NVMforWindows` |
| Node.js LTS | `nvm install --lts` | `nvm install --lts` | `nvm install lts` |
| SDKMAN | `curl -s https://get.sdkman.io \| bash` | `curl -s https://get.sdkman.io \| bash` | not used, SDKMAN needs bash |
| Java (Temurin) | `sdk install java 21.0.11-tem` | `sdk install java 21.0.11-tem` | the winget packages `EclipseAdoptium.Temurin.11.JDK`, `EclipseAdoptium.Temurin.17.JDK`, `EclipseAdoptium.Temurin.21.JDK` and `EclipseAdoptium.Temurin.25.JDK`, one per pinned major, then `JAVA_HOME` at user scope |
| Pyenv | `curl https://pyenv.run \| bash` | `curl https://pyenv.run \| bash` | not used, see Python |
| Python | `pyenv install 3.11.15` | `pyenv install 3.11.15` | `winget install -e --id Python.Python.3.11` |
| Dart SDK | not installed standalone, bundled with FVM's Flutter SDK below | not installed standalone, bundled with FVM's Flutter SDK below | `choco install dart-sdk`, needed only so `dart pub global activate fvm` can run: FVM's own install script has no Windows build |
| FVM (Flutter) | `curl -fsSL https://fvm.app/install.sh \| bash` | `curl -fsSL https://fvm.app/install.sh \| bash` | `dart pub global activate fvm` |
| Flutter (stable) | `fvm install stable` | `fvm install stable` | `fvm install stable` |
| Android SDK | `sdkmanager "platform-tools" "build-tools;35.0.0"` | `sdkmanager "platform-tools" "build-tools;35.0.0"` | `winget install -e --id Google.AndroidStudio`, and the wizard also unpacks the command line tools into `C:\tools\android` and runs `sdkmanager` there |

Other pinned Java identifiers are `11.0.31-tem`, `17.0.19-tem` and `25.0.3-tem`. Other pinned Python versions are `3.10.20`, `3.12.13` and `3.13.13`. The defaults are `21.0.11-tem` and `3.11.15`.

## AI tools

Installed by the `ai_tools` role. Each toggle gates its own `import_tasks` so disabled tools never run their setup. The npm ones need Node from NVM first.

| Tool | Linux | macOS | Windows |
|---|---|---|---|
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` | `npm install -g @anthropic-ai/claude-code` | `npm install -g @anthropic-ai/claude-code` |
| Claude Desktop | On by default. Debian and Ubuntu: `apt install claude-desktop` from Anthropic's own apt repository. Arch: AUR `claude-desktop` through `paru`, which compiles nothing: it downloads Anthropic's own `.deb`, checks its pinned SHA-256 and unpacks it. Fedora: not installed, the vendor does not support it | `brew install --cask claude` | `winget install -e --id Anthropic.Claude`, installed natively by `setup/setup.ps1` from the `claude_desktop` mapping in `vars/Windows.yaml` |
| OpenCode | `npm install -g @opencode/cli`, after `npm uninstall -g opencode-ai` removes version 1, which claims the same `opencode` command. With `opencode_use_v1` the other way round: `npm uninstall -g @opencode/cli`, then `npm install -g opencode-ai` | same | same |
| Kilo Code CLI | `npm install -g @kilocode/cli`, the `kilo` command | same | same |
| OpenSpec | `npm install -g @fission-ai/openspec` | `npm install -g @fission-ai/openspec` | `npm install -g @fission-ai/openspec` |
| Codex CLI | `npm install -g @openai/codex` | `npm install -g @openai/codex` | `npm install -g @openai/codex` |
| Grok CLI | `npm install -g @xai-official/grok` | `npm install -g @xai-official/grok` | `npm install -g @xai-official/grok` |
| LM Studio | `curl -fsSL https://lmstudio.ai/install.sh \| bash -s -- --no-modify-path` | `brew install --cask lm-studio`, Apple Silicon only. An Intel Mac skips it with a `[WARN]` line and the verification reports it as skipped, because the cask declares `depends_on arch: :arm64` | `winget install -e --id ElementLabs.LMStudio` |
| Stable Diffusion WebUI | `git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui` | `git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui` | manual clone and run |

Codex and Grok both publish a thin npm launcher plus per-platform binary packages as optional dependencies, covering Linux, macOS and Windows on x86-64 and arm64, so a single npm path serves every operating system. Native packages exist for some platforms (`extra/openai-codex` on Arch, the `codex` and `grok-build` Homebrew casks, `OpenAI.Codex` and `xAI.GrokBuild` on winget), but no apt or dnf repository exists for either tool, so mixing routes would mean four code paths for the same binary. Grok needs Node 20 or newer, which the `nvm use --lts` step in the helper already satisfies.

Kilo Code follows the same reasoning. Kilo's own documentation at kilo.ai/docs/code-with-ai/platforms/cli names `npm install -g @kilocode/cli` as the install, and the package carries per-platform binaries for Linux, macOS and Windows on x86-64 and arm64. Native packages exist for two platforms only, `kilo-bin` on the AUR and `KiloCode.Kilo` on winget, both published by Kilo and both 7.8.12 on 2026-10-15, and there is no Homebrew formula, apt, dnf or snap package, so npm is the one route that covers every operating system. Kilo keeps its data in `~/.local/share/kilo`, apart from OpenCode's `~/.local/share/opencode`, although it is built on OpenCode.

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
| QEMU/KVM + virt-manager | `for package in qemu-system-x86 libvirt-daemon-system libvirt-clients virt-manager virtinst bridge-utils virtiofsd; do sudo apt-get install -y "${package}"; done` | `for package in qemu-kvm libvirt virt-manager virt-install bridge-utils virtiofsd; do sudo dnf install -y "${package}"; done` | `for package in virt-manager qemu-full libvirt dnsmasq nftables virtiofsd; do sudo pacman -S --needed "${package}"; done` | not available | not available |
| Docker | `for package in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do sudo apt-get install -y "${package}"; done` (repo) | `for package in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; do sudo dnf install -y "${package}"; done` (repo) | `sudo pacman -S --needed docker` | `brew install --cask docker-desktop` | `winget install -e --id Docker.DockerDesktop` |
| Podman Desktop | `flatpak install -y flathub io.podman_desktop.PodmanDesktop` | `flatpak install -y flathub io.podman_desktop.PodmanDesktop` | `flatpak install -y flathub io.podman_desktop.PodmanDesktop` | not available | not available |
| VirtualBox | not available | not available | not available | `brew install --cask virtualbox`, which runs only arm64 guests on Apple Silicon | `winget install -e --id Oracle.VirtualBox` |
| VMware | not available | not available | not available | not available, the `vmware-fusion` cask no longer exists | `choco install vmware-workstation-player -y` |
| GParted | `sudo apt-get install -y gparted` | `sudo dnf install -y gparted` | `sudo pacman -S --needed gparted` | not available | not available |
| KDE Partition Manager | `sudo apt-get install -y partitionmanager` | `sudo dnf install -y kde-partitionmanager` | `sudo pacman -S --needed partitionmanager` | not available | not available |
| Boot repair (grubby) | not available | `sudo dnf install -y grubby` | not available | not available | not available |

Podman Desktop is installed purely as a graphical front end for the Docker engine this project already installs and adds the user's account to the `docker` group for. Its Docker extension talks to `/var/run/docker.sock` directly, so containers, images, volumes, networks, logs, exec and build all work with no extra setting: the flatpak already carries `--filesystem=/run/docker.sock` and the sandbox never clears the user's supplementary groups. The application also ships its own `podman` extension, which this project does not use and does not install an engine for (no podman engine, no pods, no podman machine). Left enabled, that extension costs a five second startup stall, a recurring "Podman needs to be set up" notification, a "Podman Provider" dashboard tile and an always-empty Pods page. Disable it once, from the application's own Extensions page, to clear all four. That setting is an internal implementation detail of the application rather than a published one, so the playbook does not preconfigure it. Rootless Docker is not supported by this flatpak, its socket under `$XDG_RUNTIME_DIR` is never exported, so a rootless install of the Docker engine will not be reachable from it. Arch and CachyOS also carry a native `podman-desktop` package in `extra`, this project uses the flatpak on every Linux distribution instead, so there is one install route rather than two.

### Arch Linux helpers

| Tool | Method |
|---|---|
| yay | `git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si` (handled by `arch_core` only when `install_yay` in `group_vars/linux.yaml` is on, off by default). Nothing in the playbook uses yay. The rule: the moment any task uses yay, yay becomes required, `install_yay` is removed from the selectable toggles and `arch_core` builds yay on every Arch run. `e2e/tier1/paru_consumers.sh` fails the gate when a task uses yay while the toggle still exists. A failed yay build is rescued: only yay is missing, the run ends failed, and everything else is still installed |
| paru | `git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si` (handled by `arch_core`). A failed build does not stop the run: every Arch User Repository package, snapd and Claude Desktop included, is reported as NOT installed because paru could not be built, the run ends failed, and everything else is still installed |
| snapd | `paru -S snapd`, so it is skipped and reported as NOT installed when paru could not be built |

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
| VMware Fusion | virt-manager | not available | not from Homebrew, the `vmware-fusion` cask no longer exists. Broadcom's support portal after signing in |

## Windows-only

| App | Category | Linux analogue | macOS analogue | Install |
|---|---|---|---|---|
| PowerShell 7 | shell | bash / zsh | zsh | `winget install -e --id 9MZ1SNWT0N5D --source msstore` |
| HWMonitor | hardware | HardInfo | Stats | `winget install -e --id CPUID.HWMonitor` |
| HWiNFO | hardware | lm_sensors | Stats | `choco install -y hwinfo.install` |
| CrystalDiskInfo | disk health | not available | not available | `winget install -e --id CrystalDewWorld.CrystalDiskInfo` |
| CrystalDiskMark | disk benchmark | not available | not available | `winget install -e --id CrystalDewWorld.CrystalDiskMark` |
| MSI Afterburner | GPU OC | GreenWithEnvy | not available | `winget install -e --id Guru3D.Afterburner` |
| WizTree | disk space | Baobab | GrandPerspective | `winget install -e --id AntibodySoftware.WizTree` |
| Angry IP Scanner | network | not available | not available | `winget install -e --id angryziber.AngryIPScanner` |
| Advanced IP Scanner | network | not available | not available | `winget install -e --id Famatech.AdvancedIPScanner` |
| GlassWire | firewall | ufw / iptables | LuLu | `choco install -y glasswire` |
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
| VMware Workstation Player | `choco install vmware-workstation-player -y`, no winget manifest post-Broadcom |

## Per-OS install caveats

- **Antigravity Linux**: the official Google APT pool URLs are not publicly addressable, so `custom_installs.yaml` downloads the official tarball from `edgedl.me.gvt1.com` and extracts it to `/opt/antigravity`. The Arch AUR slug `antigravity` works today.
- **Antigravity macOS**: the Homebrew cask `antigravity`, which picks the Apple Silicon or Intel build itself and needs macOS 13 or newer. Nothing is pinned for it, the app updates itself.
- **VMware Workstation Player on Windows**: no winget manifest post-Broadcom. Falls back to Chocolatey (`vmware-workstation-player`, verified, installer functional, package itself marked deprecated by maintainer).
- **VMware on macOS**: not installed. The `vmware-fusion` cask no longer exists, because Broadcom moved the download behind a portal login, so `install_vmware` is off in `group_vars/macos.yaml` and UTM is the mapped alternative.
- **FileZilla on Windows**: FileZilla blocks third-party installers, so winget removed the manifest. Falls back to Chocolatey (`filezilla`, verified).
- **FileZilla on macOS**: no Homebrew cask exists. The `install_filezilla` toggle maps to Cyberduck (cask `cyberduck`), the standard free macOS FTP/SFTP/S3 client. To install FileZilla specifically, set `install_filezilla: false` and download from `filezilla-project.org`.
- **Lens on Linux**: installed from the official `downloads.k8slens.dev` apt/dnf repo, package name `lens`. Lens Desktop is free for personal use.
- **NVIDIA software on Windows**: neither GeForce Experience nor the NVIDIA App is installed by this repository. GeForce Experience was discontinued by NVIDIA and its toggle was removed on 2026-08-23 at the owner's request. The NVIDIA App has no winget manifest, which is measurable rather than remembered: `winget search "nvidia app"` returns nothing and no `Nvidia.NVIDIAApp` id exists, and winget-pkgs rejected the submissions in #140696, #179043 and #253660. Chocolatey does carry `nvidia-app`, 11.0.8.299 published 2026-07-14, so that route exists if it is ever wanted. Until then, install it from nvidia.com.
- **Gridcoin macOS DMG**: pinned to `5.5.0.0`. Apple Silicon users may want the `-macos-arm64.dmg` variant, today the playbook installs the `x86_64` build via Rosetta. Switching is a one-line change in `pinned_values.toml`.

## Download integrity

The `[checksums]` table in [setup/pinned_values/pinned_values.toml](pinned_values/pinned_values.toml) is injected into Ansible as `download_checksums`. To enforce sha256 verification on `get_url` tasks (AppImages, custom DMG/EXE installers, the Gridcoin flatpak bundle), add entries like:

```toml
[checksums]
jetbrains_toolbox = "sha256:0123abcd..."
gputest = "sha256:..."
gridcoin_macos = "sha256:..."
gridcoin_flatpak = "sha256:..."
```

Leaving an entry absent disables checksum enforcement for that download, Ansible substitutes `omit`.
### Using Lynis

Moved to [docs/tool_usage.md](../docs/tool_usage.md), which is where usage instructions for installed
tools live now, so this catalogue stays a catalogue.

---
