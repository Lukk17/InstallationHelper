# Configuration guide

Configuration tasks the Ansible playbook performs, grouped by desktop environment and OS. For the software catalog, see [software.md](software.md). For the authoritative per-OS package mappings, see [`ansible/vars/`](ansible/vars/).

## Per-OS caveats

| Package | OS | Note |
|---------|------|--------|
| Microsoft Teams | Linux | Not available natively — use the web app. Installed on Windows (winget `Microsoft.Teams`) and macOS (cask `microsoft-teams`). |
| balena-etcher | Arch | Disabled in `vars/Archlinux.yaml` due to Node.js dep conflict with AUR. Installed normally on Debian/Fedora (`.deb`/`.rpm`) and macOS (cask `balenaetcher`). |
| VMware Workstation Player | Windows | Auto-download broken — Broadcom moved installers behind a portal login. Install manually or use VirtualBox. |
| Trello / WhatsApp | Windows | No maintained winget manifest. Mapped to MS Store IDs (`XP8K0HKJFRXGCK` / `9NKSQGP7F2NH`); winget routes them through Store install. |
| Antigravity | Linux | Installed from Google's official apt/yum repos (`us-central1-apt.pkg.dev` / `us-central1-yum.pkg.dev`) configured by `debian_repos.yaml` / `fedora_repos.yaml`. AUR slug `antigravity` on Arch. Auto-updates work the same as Chrome. |
| Antigravity | macOS | Homebrew cask `antigravity`, which needs macOS 13 or newer. Not pinned: the cask follows Google's current release, and no DMG is downloaded from `edgedl.me.gvt1.com` any more. |
| Antigravity | Windows | winget `Google.AntigravityIDE`. |
| Gridcoin | macOS / Windows | DMG / `.exe` from `github.com/gridcoin-community/Gridcoin-Research` releases (tag `5.5.0.0`) — handled by `macos_install.yaml` on macOS and by `setup/windows/WindowsCustomInstalls.ps1` on Windows. Arch uses the official flatpak bundle (`custom_installs.yaml`). |
| FileZilla / Maven / Gradle / VMware Workstation Player / GeForce Experience | Windows | No winget manifest. Each falls back to Chocolatey via `manager: choco` in `vars/Windows.yaml`. `setup/windows/WindowsSoftware.ps1` bootstraps Chocolatey on first use and installs the whole `choco` set in one elevated batch. |
| Lens | Linux | Lens Desktop is free for personal use. Installed from the official apt/dnf repo (`downloads.k8slens.dev`) configured by `debian_repos.yaml` / `fedora_repos.yaml`. macOS uses cask `lens`; Windows uses winget `Mirantis.Lens`; Arch uses AUR `lens-bin`. |
| FileZilla | macOS | No Homebrew cask exists for FileZilla on macOS. The `install_filezilla` toggle maps to **Cyberduck** (cask `cyberduck`) — the standard free macOS FTP/SFTP/S3 client. Set the toggle to `false` and install FileZilla manually from `filezilla-project.org` if you need FileZilla specifically. |
| Game storefronts (EA app, GOG Galaxy, Epic) and CurseForge | Linux | EA app, GOG Galaxy and Epic have no official Linux client. `install_ea_app` / `install_gog` / `install_epic` map to winget (Windows) and Homebrew casks (macOS) only, and they do nothing on Linux because `vars/{Debian,RedHat,Archlinux}.yaml` carry no mapping for these keys. Run those games on Linux through Lutris or Heroic with Proton. CurseForge does have a Linux client: `install_curseforge` installs Overwolf's own Flathub build, `com.overwolf.curseforge`, on every Linux distribution, Arch and CachyOS included. |
| Podman Desktop | Linux | Installed as a flatpak (`io.podman_desktop.PodmanDesktop`) purely as a graphical front end for the Docker engine `install_docker` already installs, not for podman: no podman engine, pods, or podman machine ship with this setup. One manual step after first launch: open the application's Extensions page and disable the bundled podman extension, or you get a five second startup stall, a "Podman needs to be set up" notification, an empty Pods page and a dashboard tile every time. Rootless Docker is not supported by this flatpak. |

## Linux

### KDE Plasma (when `configure_kde_plasma: true`)

| Task | Role | Description |
|------|------|-------------|
| Install KDE Plasma | kde_plasma_setup | Installs KDE Plasma desktop environment |
| Configure KDE | kde_plasma_setup | Applies Lukk's KDE configuration, themes, icons |
| Configure Konsole | kde_plasma_setup | Terminal profile with Lukk settings |
| Save/Load Profiles | kde_plasma_setup | Konsave for profile management |

### GNOME (when `configure_gnome: true`)

| Task | Role | Description |
|------|------|-------------|
| Install GNOME | gnome_setup | Installs GNOME desktop environment and its tooling from `install_gnome`'s `companion_packages` entry, also on a machine that already has GNOME |
| Configure GNOME | gnome_setup | Desktop settings, extensions |
| Nautilus Bookmarks | gnome_setup | Custom file manager bookmarks |
| GTK Settings | gnome_setup | GTK theme and appearance |

### System-Wide Linux (All Desktop Environments)

| Task | Role | Description |
|------|------|-------------|
| Base System Utils | system_core | unzip, curl, wget, git, etc. |
| System Upgrade | system_core | Full system update |
| TMP in RAM | system_core | Mount /tmp as tmpfs |
| Hibernate Setup | system_core | Enable hibernation |
| Zsh + Oh My Zsh | shell_zsh | Install and configure Zsh |
| Terminal Fonts | shell_zsh | Powerline fonts for terminal |
| Environment Variables | env_variables | PATH and custom env vars |
| Systemd Boot | systemd_boot | Configure systemd-boot loader |
| Remove GRUB | systemd_boot | Clean up GRUB if needed |
| Arch Core | arch_core | Arch-specific base setup |
| Fedora Core | fedora_core | Fedora-specific base setup |
| Virtualization | virtualization_config | KVM, virt-manager setup |
| Waydroid | waydroid | Android app emulation |
| Security Tools | linux_security | lynis, chkrootkit, clamav |
| Snapper Btrfs | snapper | Automatic btrfs snapshots (if btrfs root) |
| Crypto Hardware | linux_crypto_hardware | Hardware wallet tools |

## macOS

| Task | Role | Description |
|------|------|-------------|
| Base Setup | macos_core | macOS-specific configuration |
| Zsh Setup | shell_zsh | Oh My Zsh installation |

## Windows

Windows is not provisioned by Ansible at all. `setup/setup.ps1` runs natively and dispatches to the modules in `setup/windows/`, which read the same `group_vars` toggles and the same `vars/Windows.yaml` mappings the playbook reads, so only the executor differs.

| Task | Module | Description |
|------|--------|-------------|
| Optional features, WSL, wallpaper | `WindowsSettings.ps1` | The three Windows system settings |
| winget and Chocolatey catalogue | `WindowsSoftware.ps1` | Everything with a `vars/Windows.yaml` mapping, virtualization included |
| Reclaiming the download caches | `WindowsSoftware.ps1` | Emptied between the packages and the SDK installers, because that is where the disk ran out |
| Java, Node, Flutter, Android SDK, Gridcoin, pipx, OpenCode desktop | `WindowsCustomInstalls.ps1` | The seven no single package expresses |
| Claude Code, OpenCode, Kilo Code, OpenSpec, Codex, Grok, Bruno CLI | `WindowsNpmTools.ps1` | The npm-based command line tools |

## Cross-Platform (All Operating Systems)

### SDK / Development Tools

| Task | Role | Description |
|------|------|-------------|
| NVM (Node.js) | sdk_manager | Node Version Manager |
| Pyenv (Python) | sdk_manager | Python version manager |
| SDKMAN (Java) | sdk_manager | SDKMAN for Java/Scala |
| FVM (Flutter) | sdk_manager | Flutter Version Manager |
| Android SDK | sdk_manager | Android SDK setup |

### JetBrains IDEs

| Task | Role | Description |
|------|------|-------------|
| JetBrains Toolbox | jetbrains_toolbox | JetBrains Toolbox installer |
| IntelliJ IDEA Ultimate | jetbrains_toolbox | via Toolbox |
| PyCharm Professional | jetbrains_toolbox | via Toolbox |
| WebStorm | jetbrains_toolbox | via Toolbox |
| DataGrip | jetbrains_toolbox | via Toolbox |
| Rider | jetbrains_toolbox | via Toolbox |

### AI Tools

| Task | Role | Description |
|------|------|-------------|
| Claude Code | ai_tools | Claude CLI tool via NPM |
| Claude Desktop | ai_tools | Claude Desktop app |
| OpenCode | ai_tools | OpenCode CLI, version 2 from the npm package `@opencode/cli`, or version 1 from `opencode-ai` when `opencode_use_v1` is true. Removes the other version's CLI and desktop app and moves a data folder the selected version cannot open aside. Version 1 always starts clean, an earlier version 1 backup is not brought back, while version 2 gets its newest backup back |
| Kilo Code | ai_tools | Kilo Code CLI, the `kilo` command, from the npm package `@kilocode/cli` |
| OpenSpec | ai_tools | OpenSpec CLI |

### Local LLM Tools

| Task | Role | Description |
|------|------|-------------|
| Stable Diffusion | local_llm | WebUI for local AI images |
| LM Studio | local_llm | Local LLM inference |

### Dynamic Software Installation

| Task | Role | Description |
|------|------|-------------|
| Package Installation | software_installer | Dynamic package installer |
| AUR Packages | software_installer | Arch User Repository packages |
| Snap Packages | software_installer | Snap packages |
| Flatpak Packages | software_installer | Flatpak packages |

## Configuration Toggles

Configuration is controlled via Ansible group variables in `group_vars/`:

### Linux (`group_vars/linux.yaml`)

- `install_kde_plasma` / `configure_kde_plasma`
- `install_gnome` / `configure_gnome`
- `install_system_core`
- `setup_systemd_boot`
- `setup_hibernate`
- `setup_tmpfs`
- `setup_zsh`
- `install_rclone` (rclone from pacman, apt or dnf)
- `install_podman_desktop` (GUI front end for `install_docker`, see the per-OS caveats table above)
- `install_gaming_suite` (Lutris, from pacman on Arch and from Flathub, `net.lutris.Lutris`, on Debian, Ubuntu and Fedora. On CachyOS it is the `cachyos-gaming-applications` metapackage instead, which brings Steam, Heroic, Faugus, gamescope, MangoHud, GOverlay, Wine and Proton, and which triggers the alignment of the 32-bit graphics stack to `mesa-git` and `lib32-mesa-git` that Steam needs there, see [vars/derivatives/cachyos.yaml](ansible/vars/derivatives/cachyos.yaml))
- `install_yay` (Arch family only, off by default: a second AUR helper beside paru that nothing in the playbook uses. If a task ever starts using yay, this toggle is removed and yay is always built, see the helper rule in [software.md](software.md#arch-linux-helpers))

### All OS (`group_vars/all.yaml`)

The cross-platform toggle file has 50+ entries grouped by category — see the file directly for the authoritative list. Highlights:

- **AI tools:** `install_claude_code`, `install_claude_desktop`, `install_opencode`, `install_opencode_desktop` (desktop app, version 2: AUR on Arch, the vendor .deb, .rpm and installer on Debian, Ubuntu, Fedora and Windows, cask on macOS), `opencode_use_v1` (off by default and left off by `--software all` and `-Software all`, installs OpenCode version 1 instead of version 2 and removes version 2, see [software.md](software.md)), `install_kilo_code`, `install_openspec`, `install_codex`, `install_grok`, `install_chatgpt` (desktop app, Windows and macOS only), `install_bruno_cli`, `install_stable_diffusion`, `install_lm_studio`
- **Browsers/Dev:** `install_chrome`, `install_brave`, `install_tor`, `install_vscode`, `install_sublime`, `install_kubectl`, `install_minikube`, `install_k3d`, `install_helm`, `install_terraform`, `install_gh`, `install_jq`, `install_fzf`, `install_ripgrep`, `install_uv`, `install_pipx`, `install_go`, `install_lens`, `install_postman`, `install_docker`
- **Comms:** `install_discord`, `install_slack`, `install_telegram`, `install_whatsapp`, `install_signal`, `install_zoom`
- **Productivity:** `install_obsidian`, `install_bitwarden`, `install_keepassxc`, `install_onlyoffice`
- **Media:** `install_vlc`, `install_spotify`, `install_gimp`, `install_krita`, `install_handbrake`, `install_audacity`, `install_rawtherapee`
- **Peripherals:** `install_synapse` (Razer Synapse 4, Windows and macOS), plus `install_openrazer` and `install_polychromatic` in `group_vars/linux.yaml` for the Linux equivalent
- **Utilities:** `install_syncthing`, `install_tailscale`, `install_veracrypt`, `install_teamviewer`, `install_speedtest`
- **Crypto/Volunteer:** `install_boinc`, `install_gridcoin`
- **SDKs:** `install_dart` (Windows only in effect since 2026-09-18: FVM installs its own Dart on Linux and macOS, and this toggle is a documented no-op on every other family, see `e2e/tier1/documented_no_ops.txt`), `install_flutter`, `install_android_sdk`

Two values in `all.yaml` are paths you may want to change rather than toggles. `android_home` is the Android SDK location. `projects_dir` is where source checkouts live, `~/Projects` on Linux and macOS: the `env_variables` role creates the directory and sets it as `PROJECTS_DIR` in `~/.config/environment.d/990-dev.conf`. The shell layout values below them, `dev_env_file`, `zsh_config_dir`, `interactive_rc_files`, `shell_startup_files` and `shell_layout_backup_dir`, are derived paths that several roles share, described under [Shell and environment layout](#shell-and-environment-layout). So are `jetbrains_toolbox_data_dir`, `jetbrains_toolbox_binary` and `jetbrains_toolbox_scripts_dir`, which `roles/jetbrains_toolbox` and `verify_install.yaml` both read on Linux. Windows takes `%USERPROFILE%\Projects` from `Set-WindowsDevEnvironment` in `setup/windows/WindowsCustomInstalls.ps1`, which creates it and sets the user variable `PROJECTS_DIR`, because Ansible never runs on Windows and so cannot read the YAML value. The repository had no earlier Windows convention to follow, and the owner's `D:\Development\projekty-IT` is one machine's choice. Change the Linux and macOS value with `-e projects_dir=<path>` or by editing the line, and the Windows value by editing the one line in that function.

OS-specific toggles live in `group_vars/{linux,macos,windows}.yaml`. Version pins for downloaded artefacts (Java, Python, Node, Minikube, balena_etcher, etc.) are in [pinned_values.toml](pinned_values/pinned_values.toml), alongside a `[checksums]` table for sha256 enforcement on `get_url` tasks.

## Shell and environment layout

Linux and macOS. Every development variable lives in one file that both the desktop session and every shell read, and each shell's own files hold only what a shell needs.

```text
~/.config/environment.d/
  60-agents.conf       the agent tooling's own file, never touched by the playbook
  990-dev.conf         KEY=VALUE and PATH=...:${PATH}, written by the playbook
        |
        +--> systemd user manager at login --> Plasma, GNOME and every application they start
        |
        +--> ~/.zshenv --> ~/.config/zsh/.zshenv --> every zsh, login or not, interactive or not
        |                         |
        |                         +--> ~/.config/zsh/.zshrc   interactive only
        |
        +--> top of ~/.bashrc --> every bash, through ~/.bash_profile or ~/.profile for a login bash
```

| File | Holds | Written by |
|---|---|---|
| `~/.config/environment.d/990-dev.conf` | `GRADLE_USER_HOME`, `DOCKER_CONFIG`, `M2_HOME`, `KUBECONFIG`, `PROJECTS_DIR`, the four Android variables, `PUB_CACHE`, `NVM_DIR`, `SDKMAN_DIR`, `JAVA_HOME`, `PYENV_ROOT`, and the PATH entries for the Android SDK, FVM, pub, SDKMAN's Java, Pyenv, LM Studio and the JetBrains Toolbox launchers (`idea`, `pycharm` and the rest, in `~/.local/share/JetBrains/Toolbox/scripts`), one marked block per role | `env_variables`, `sdk_manager`, `ai_tools`, `jetbrains_toolbox` |
| `~/.zshenv` | `ZDOTDIR="$HOME/.config/zsh"` and the line that sources `$ZDOTDIR/.zshenv`, nothing else | `shell_zsh` |
| `~/.config/zsh/.zshenv` | `typeset -U path PATH`, the import of every `~/.config/environment.d/*.conf`, and the line that drops PATH entries that are not a directory yet | `env_variables` |
| `~/.config/zsh/.zshrc` | Oh My Zsh, Powerlevel10k, aliases and completion, from [config/zsh/.zshrc](config/zsh/.zshrc) as one marked block, then the NVM, SDKMAN and Pyenv init blocks. No `export` | `shell_zsh`, `sdk_manager` |
| `~/.config/zsh/.p10k.zsh` | the prompt configuration, copied only where none exists, because `p10k configure` rewrites it | `shell_zsh` |
| `~/.bashrc` | the same import at the very top, ahead of the distribution's early return for a non-interactive shell, and the same three init blocks at the end | `env_variables`, `sdk_manager` |
| `~/.local/share/oh-my-zsh` | Oh My Zsh itself, through `$ZSH` | `shell_zsh` |

Why the environment is not in `.zshrc`: Plasma starts its session with `$SHELL --login`, a non-interactive login shell, which never reads `.zshrc`, and the systemd user manager reads only `environment.d`. Until 2026-10-15 the variables were export lines in `~/apps_config/env.sh`, sourced from `.zshrc` and `.bashrc`, and an IDE started from the application menu had no `ANDROID_HOME`, `JAVA_HOME` or `KUBECONFIG`.

Why the file is called `990-dev.conf`: systemd reads every `environment.d` file in the order of its name, and every supported distribution ships `/usr/lib/environment.d/99-environment.conf`, a link to `/etc/environment`. Ubuntu's `/etc/environment` assigns `PATH` outright, without `${PATH}`, so a file whose name sorts before `99-environment.conf` has every PATH entry it added replaced. The file was `50-dev.conf` until 2026-10-18, and on Ubuntu the desktop session got none of its PATH entries while every variable survived. The name has to sort after `99-environment.conf`, and `e2e/tier1/zshrc_env_block.sh` fails when it does not.

One Java everywhere. `JAVA_HOME` and the first Java on PATH are SDKMAN's `current` symlink, which `sdk default java` points at the `default_java` pin, so an application the desktop starts and a terminal use the same Java. On Arch the `archlinux-java` default stays installed and comes later on PATH. `sdk use java <version>` still switches one shell.

What a desktop session does not get. NVM keeps no fixed directory for the active Node, so `node` and the npm-installed tools are found in a terminal, through the NVM init block, and not by an application started from the menu. Pyenv's shims are added in a terminal only, and the Pyenv global is `system` on Linux, so a desktop application gets the same Python either way.

Vendor installers no longer edit the rc files. NVM runs with `PROFILE=/dev/null`, SDKMAN is fetched from `https://get.sdkman.io?rcupdate=false`, and LM Studio's installer gets `--no-modify-path`. JetBrains Toolbox has no such switch: it appends its launcher directory to `~/.profile` on its first start when that directory is not already on PATH, which zsh never reads and Arch's login bash does not either, so `jetbrains_toolbox` puts the directory in `990-dev.conf` and removes Toolbox's two lines. The lines earlier installs appended are removed from `~/.bashrc`, `~/.bash_profile`, `~/.profile`, `~/.zshrc`, `~/.zprofile` and their `~/.config/zsh` counterparts by every run that installs that tool.

A machine set up with the older layout is migrated by the next run. `~/.oh-my-zsh` and `~/.p10k.zsh` move into the new places, and `~/.zshrc`, `~/.zshrc.pre-oh-my-zsh`, `~/apps_config/env.sh` and `~/.config/environment.d/50-dev.conf` move into `~/.local/state/installation-helper/shell-layout-backup/` under a timestamped name. Nothing is deleted. A second run reports no change.

A desktop session reads `environment.d` only when the systemd user manager starts, so log out and back in after the first run. Check what the next session will carry, as your own user:

```bash
env -i HOME="$HOME" PATH=/usr/bin "$(systemd-path systemd-user-environment-generator)/30-systemd-environment-d-generator"
```

`verify_install.yaml` runs the same generator and fails when a development variable or PATH entry is missing from it. macOS has no systemd, so there the file reaches zsh only, through `~/.config/zsh/.zshenv`, and an application started from the Dock does not see it.

## Related Documentation

- [software.md](software.md) — complete software installation list by OS
- [README_SETUP.md](README_SETUP.md) — setup and run instructions
- [../README.md](../README.md) — project overview