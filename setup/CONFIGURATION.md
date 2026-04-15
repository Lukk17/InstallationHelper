# Configuration Guide

This document lists all configuration tasks performed by the Ansible playbook, organized by Desktop Environment and Operating System.

> For software installation list, see [SOFTWARE.md](SOFTWARE.md)

---

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

---

## macOS

| Task | Role | Description |
|------|------|-------------|
| Base Setup | macos_core | macOS-specific configuration |
| Zsh Setup | shell_zsh | Oh My Zsh installation |

---

## Windows (via WSL)

| Task | Role | Description |
|------|------|-------------|
| Base Setup | windows_core | Windows-specific configuration |
| WSL Setup | windows_core | WSL configuration |
| Virtualization | windows_core | Windows virtualization features |

---

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

---

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

- `install_claude_code`
- `install_claude_desktop`
- `install_opencode`
- `install_openspec`
- `install_stable_diffusion`
- `install_lm_studio`

---

## Related Documentation

- [SOFTWARE.md](SOFTWARE.md) - Complete software installation list by OS
- [README_SETUP.md](README_SETUP.md) - Setup and run instructions
- [setup/README_SETUP.md](README_SETUP.md) - Detailed setup guide