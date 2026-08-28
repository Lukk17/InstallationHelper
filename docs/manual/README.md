# Manual install reference

Copy-pasteable install commands for everything the Ansible playbook manages, one page per OS/distro. Use this when you want to install a few things by hand — or run the whole set — **without** running Ansible.

Each OS folder has two files:

- **`<os>_manual_install.md`** — every app grouped exactly like [`setup/software.md`](../../setup/software.md), with the literal install command next to each one, plus repository-setup steps and a list of apps that need a manual install.
- **`install.sh`** / **`install.ps1`** — a script that installs the package-manager-installable apps in one go (adds the official third-party repos, pulls the pinned `.deb`/`.rpm` files, enables Flathub). Each script prints, at the end, the apps it deliberately skipped because they need a manual download.

| OS / distro | Page | Script |
|---|---|---|
| Debian / Ubuntu | [debian_ubuntu_manual_install.md](debian-ubuntu/debian_ubuntu_manual_install.md) | [`install.sh`](debian-ubuntu/install.sh) |
| Fedora | [fedora_manual_install.md](fedora/fedora_manual_install.md) | [`install.sh`](fedora/install.sh) |
| Arch Linux and CachyOS | [arch_manual_install.md](arch/arch_manual_install.md) | [`install.sh`](arch/install.sh) |
| macOS | [macos_manual_install.md](macos/macos_manual_install.md) | [`install.sh`](macos/install.sh) |
| Windows | [windows_manual_install.md](windows/windows_manual_install.md) | [`install.ps1`](windows/install.ps1) |

## What the scripts do and don't do

**The scripts install** everything reachable through a package manager: `apt` / `dnf` / `pacman` (incl. official third-party repos for Chrome, Brave, VS Code, Sublime, kubectl, Lens), `flatpak` (Flathub), `brew` / `brew --cask`, `winget`, `choco`, and direct `.deb` / `.rpm` downloads pinned in [`pinned_values.toml`](../../setup/pinned_values/pinned_values.toml).

**The scripts do NOT install** (each is listed in its page's *Manual install required* section, with commands):

- Binary blobs with no package-manager path: Antigravity (Linux tarball / macOS DMG), Gridcoin, GpuTest, OpenLens, JetBrains Toolbox, Ledger Live / Trezor Suite AppImages.
- **Arch AUR packages** — they need an AUR helper (`yay` / `paru`); the page lists the exact `yay -S` commands and a one-time `yay` bootstrap.
- **SDK / runtime managers** (NVM, SDKMAN, Pyenv, FVM, Android SDK), **AI tools** (Claude Code, OpenCode, OpenSpec, LM Studio, SD WebUI), and **shell setup** (zsh, Oh My Zsh, Powerlevel10k). These install via `curl | bash` into your shell rc and have ordering/sourcing dependencies, so each page documents them with exact commands to run by hand, in order.

## Source of truth

These pages are generated from, and must stay consistent with:

- [`setup/ansible/vars/{Debian,RedHat,Archlinux,Darwin,Windows}.yaml`](../../setup/ansible/vars/) — app → `{manager, package}` mappings.
- [`setup/pinned_values/pinned_values.toml`](../../setup/pinned_values/pinned_values.toml) — pinned versions and download URLs.
- [`setup/ansible/roles/software_installer/tasks/`](../../setup/ansible/roles/software_installer/tasks/) — repo provisioning (`debian_repos.yaml`, `fedora_repos.yaml`) and custom installs.

If anything here drifts from those files, **trust the YAML**.
