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
| Antigravity | macOS | Direct DMG from Google's official CDN `edgedl.me.gvt1.com` (Google Video Transcoding — same CDN that delivers Chrome). `macos_install.yaml` reads `ansible_facts['architecture']` and picks the arm64 DMG on Apple Silicon, the x64 DMG on Intel. Version pinned in `pinned_values.toml` (`antigravity_version`, `antigravity_build`). |
| Antigravity | Windows | winget `Google.AntigravityIDE`. |
| Gridcoin | macOS / Windows | DMG / `.exe` from `github.com/gridcoin-community/Gridcoin-Research` releases (tag `5.5.0.0`) — handled by `macos_install.yaml` / `windows_install.yaml`. Arch uses the official flatpak bundle (`custom_installs.yaml`). |
| FileZilla / Maven / Gradle / VMware Workstation Player / GeForce Experience | Windows | No winget manifest. Each falls back to Chocolatey via `manager: choco` in `vars/Windows.yaml`. The `win_chocolatey` module bootstraps Chocolatey on first use. |
| Lens | Linux | Lens Desktop is free for personal use. Installed from the official apt/dnf repo (`downloads.k8slens.dev`) configured by `debian_repos.yaml` / `fedora_repos.yaml`. macOS uses cask `lens`; Windows uses winget `Mirantis.Lens`; Arch uses AUR `lens-bin`. |
| FileZilla | macOS | No Homebrew cask exists for FileZilla on macOS. The `install_filezilla` toggle maps to **Cyberduck** (cask `cyberduck`) — the standard free macOS FTP/SFTP/S3 client. Set the toggle to `false` and install FileZilla manually from `filezilla-project.org` if you need FileZilla specifically. |
| Game storefronts (EA app, GOG Galaxy, Epic, CurseForge) | Linux | No official Linux clients. `install_ea_app` / `install_gog` / `install_epic` / `install_curseforge` map to winget (Windows) and Homebrew casks (macOS) only; they no-op on Linux since `vars/{Debian,RedHat,Archlinux}.yaml` carry no mapping for these keys. Run the games on Linux via Lutris/Heroic + Proton if needed. |

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
| Install GNOME | gnome_setup | Installs GNOME desktop environment |
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

## Windows (via WSL)

| Task | Role | Description |
|------|------|-------------|
| Base Setup | windows_core | Windows-specific configuration |
| WSL Setup | windows_core | WSL configuration |
| Virtualization | windows_core | Windows virtualization features |

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
| OpenCode | ai_tools | OpenCode CLI |
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

### All OS (`group_vars/all.yaml`)

The cross-platform toggle file has 50+ entries grouped by category — see the file directly for the authoritative list. Highlights:

- **AI tools:** `install_claude_code`, `install_claude_desktop`, `install_opencode`, `install_openspec`, `install_codex`, `install_grok`, `install_chatgpt` (desktop app, Windows and macOS only), `install_bruno_cli`, `install_stable_diffusion`, `install_lm_studio`
- **Browsers/Dev:** `install_chrome`, `install_brave`, `install_tor`, `install_vscode`, `install_sublime`, `install_kubectl`, `install_minikube`, `install_k3d`, `install_helm`, `install_terraform`, `install_gh`, `install_jq`, `install_fzf`, `install_ripgrep`, `install_lens`, `install_postman`, `install_docker`
- **Comms:** `install_discord`, `install_slack`, `install_telegram`, `install_whatsapp`, `install_signal`
- **Productivity:** `install_obsidian`, `install_bitwarden`, `install_keepassxc`, `install_onlyoffice`
- **Media:** `install_vlc`, `install_spotify`, `install_gimp`, `install_krita`, `install_handbrake`, `install_audacity`, `install_rawtherapee`
- **Peripherals:** `install_synapse` (Razer Synapse 4, Windows and macOS), plus `install_openrazer` and `install_polychromatic` in `group_vars/linux.yaml` for the Linux equivalent, and `install_razer_cortex` in `group_vars/windows.yaml`
- **Utilities:** `install_syncthing`, `install_tailscale`, `install_veracrypt`, `install_teamviewer`, `install_speedtest`
- **Crypto/Volunteer:** `install_boinc`, `install_gridcoin`
- **SDKs:** `install_dart`, `install_flutter`, `install_android_sdk`

OS-specific toggles live in `group_vars/{linux,macos,windows}.yaml`. Version pins for downloaded artefacts (Java, Python, Node, Minikube, balena_etcher, etc.) are in [pinned_values.toml](pinned_values/pinned_values.toml), alongside a `[checksums]` table for sha256 enforcement on `get_url` tasks.

## Related Documentation

- [software.md](software.md) — complete software installation list by OS
- [README_SETUP.md](README_SETUP.md) — setup and run instructions
- [../README.md](../README.md) — project overview