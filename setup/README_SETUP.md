# Setup

Cross-platform, data-driven Ansible setup for Ubuntu/Debian, Fedora, Arch Linux, macOS, and Windows (via WSL).

For configuration tasks and toggle reference, see [CONFIGURATION.md](CONFIGURATION.md). For the full software catalog, see [SOFTWARE.md](SOFTWARE.md). For where to look up versions across every package manager and direct-URL source, see [VERSION_SOURCES.md](VERSION_SOURCES.md). Authoritative per-OS package mappings live in [`ansible/vars/`](ansible/vars/).

## Using the setup script

The setup script detects your OS, installs Ansible and the required Galaxy collections, then runs an interactive checklist for software selection.

The wizard uses `gum` (charm.sh) on Linux/macOS and `Microsoft.PowerShell.ConsoleGuiTools` on Windows for filter-as-you-type pickers. Both are installed automatically on first run.

Run it as your regular user. Do not use `sudo`.

Linux / macOS:

```bash
bash setup/setup.sh
```

Windows (PowerShell 7+):

```powershell
pwsh setup/setup.ps1
```

What the script does:

1. Detects the OS and distribution.
2. Installs Ansible via the matching package manager if it is missing.
3. Installs `gum` (Linux/macOS) or `Microsoft.PowerShell.ConsoleGuiTools` (Windows) if missing.
4. Installs the Galaxy collections pinned in `setup/ansible/requirements.yaml` (`community.general`, `community.windows`, `ansible.windows`, `ansible.posix`, `community.docker`, `kewlfft.aur`). Re-runs are no-ops.
5. Presents an interactive menu for the desktop environment.
6. Optionally lets you review individual software and feature toggles in a filter-as-you-type grid.
7. Runs the playbook with your selections, prompting for sudo when needed.

### Script options

Both entrypoints support non-interactive flags for scripted runs (CI, Packer, live USB).

Show usage:

```bash
bash setup/setup.sh --help
```

Apply a preset profile and skip the wizard:

```bash
bash setup/setup.sh --profile linux_live --non-interactive
```

PowerShell equivalent:

```powershell
pwsh setup/setup.ps1 -Profile linux_live -NonInteractive
```

Get help in PowerShell:

```powershell
Get-Help .\setup\setup.ps1 -Full
```

Disable themed output (also honoured via `NO_COLOR=1`):

```bash
bash setup/setup.sh --no-color
```

Skip the pre-Ansible system upgrade (apt/dnf/pacman/brew full-upgrade) — useful for CI, live USB, or when you've just upgraded:

```bash
bash setup/setup.sh --skip-system-upgrade
```

PowerShell equivalent:

```powershell
pwsh setup/setup.ps1 -SkipSystemUpgrade
```

Requirements:

- Linux (Ubuntu/Debian, Fedora, Arch) or macOS, with an internet connection and `sudo`.
- Windows: PowerShell 7+ and WSL (`wsl --install -d Ubuntu`).

## Manual run

Use this only if you prefer to drive Ansible directly. All commands run from `setup/ansible/`.

### 1. Install Ansible

Ubuntu / Debian:

```bash
sudo apt update
```

```bash
sudo apt install -y software-properties-common
```

```bash
sudo add-apt-repository --yes --update ppa:ansible/ansible
```

```bash
sudo apt install -y ansible
```

Fedora:

```bash
sudo dnf install -y ansible
```

Arch Linux:

```bash
sudo pacman -S --noconfirm ansible
```

macOS:

```bash
brew install ansible
```

Windows: install WSL, open Ubuntu, then follow the Ubuntu/Debian steps above. Ansible does not run natively on Windows.

```powershell
wsl --install -d Ubuntu
```

#### Arch Linux: enable multilib for Steam

Steam needs the multilib repo. Without it, the playbook skips Steam with a warning.

```bash
sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
```

```bash
sudo pacman -Sy
```

### 2. Move into the Ansible directory

```bash
cd setup/ansible
```

### 3. Install Galaxy collections

```bash
ansible-galaxy collection install -r requirements.yaml
```

### 4. Configure toggles

Review `group_vars/all.yaml` and the OS-specific files under `group_vars/`. Set the toggles you want enabled. To override values from a profile, point Ansible at `profiles/<name>.yaml` at runtime.

### 5. Run the playbook

The `-K` flag prompts for the sudo password.

Standard run:

```bash
ansible-playbook site.yaml -i localhost, -c local -K
```

Linux Live / USB profile:

```bash
ansible-playbook site.yaml -i localhost, -c local -e "@profiles/linux_live.yaml" -K
```

## Logging

Every run writes four log files in your home directory:

| Log file | Contents |
|---|---|
| `~/installation_full.log` | Complete playbook output, phase separators, per-task duration, and an end-of-run grouped summary (installed / already present / skipped / failed). |
| `~/installation_errors.log` | Only FAILED tasks and `unreachable` hosts. |
| `~/installation_warnings.log` | Only WARNING-level entries (deprecations, captured stderr, etc.). |
| `~/installation_skipped.log` | Per-item skips with the reason category (toggle disabled, not for this OS, ...). |

All four files are overwritten on each run. Captured stdout/stderr from any single task is truncated after 30 lines so license dumps and verbose installer chatter don't bloat the log.

### Watching progress live

Long-running tasks (flatpak install of all GUI apps, `apt full-upgrade`, batched apt install) print one in-band progress line per package as they go:

```text
⏳ running: software_installer : Install Flatpak packages (Debian, batched...)
  ↳ [00m08s] Installing 1/47… app/com.spotify.Client/x86_64/stable
  ↳ [00m42s] Installing 2/47… app/com.bitwarden.desktop/x86_64/stable
  ↳ [01m15s] Installing 3/47… runtime/org.freedesktop.Platform/x86_64/24.08
  ↳ [06m15s] still working… (log unchanged)
  ↳ [09m02s] Installing 4/47… runtime/org.mozilla.firefox.Locale/x86_64/stable
[+44m 08s] CHANGED: [localhost]
```

The `↳` lines fire on every progress change. The `still working… (log unchanged)` line fires every 5 minutes when the underlying tool stops printing. Three of those in a row is a real stall (network dead, mirror unreachable); otherwise the install is just slow.

For verbose live output from the underlying tool, open a second terminal and tail the per-tool log directly:

```bash
tail -f /var/log/installation-flatpak-batch.log
```

The available log files match the running task:

| Task | Log file |
|---|---|
| `Install APT packages (batched...)` | `/var/log/installation-apt-batch.log` |
| `Install Flatpak packages (Debian...)` | `/var/log/installation-flatpak-batch.log` |
| `Full system upgrade and autoremove (Debian, via raw)` | `/var/log/installation-apt-upgrade.log` |

On Windows the playbook runs inside WSL, so the same files live under WSL's filesystem. Tail them from PowerShell with:

```powershell
wsl -d Ubuntu tail -f /var/log/installation-flatpak-batch.log
```

The heartbeat tick (default 5s) and idle-ping window (default 300s) are tunable:

```bash
DUAL_LOGGER_HEARTBEAT_SEC=10 DUAL_LOGGER_IDLE_PING_SEC=120 ansible-playbook site.yaml -i localhost, -c local -K
```

`Ctrl+C` interrupts the whole playbook, not a single task. If a specific install is stuck and you want to abort cleanly, kill the playbook then re-run — every task uses `creates:` or other idempotency guards and skips finished work.

### Troubleshooting log errors

If the playbook fails with:

```text
FATAL: Cannot open log files in /home/<you>: ...
```

First check that your user has write access to the home directory. If you genuinely need to run without file logging, set the following in `group_vars/all.yaml`:

```yaml
allow_callback_failure: true
```

Or pass it inline for a single run:

```bash
ansible-playbook site.yaml -i localhost, -c local -K --extra-vars "allow_callback_failure=true"
```

## Desktop environments (Linux)

`group_vars/linux.yaml` separates install from configure so you can theme a pre-installed DE (Fedora KDE Spin, etc.) without reinstalling it:

- `install_kde_plasma: true` installs KDE via the system package manager.
- `configure_kde_plasma: true` applies themes, widgets, and shortcuts.
- Equivalent toggles exist for GNOME: `install_gnome`, `configure_gnome`.

### Konsave profile management (KDE)

Save the current KDE Plasma configuration:

```bash
konsave -s lukk_desktop_profile
```

Export to `lukk_desktop_profile.knsv`:

```bash
konsave -e lukk_desktop_profile
```

Re-exporting to an existing file requires `-f`, otherwise konsave refuses to overwrite:

```bash
konsave -e lukk_desktop_profile -f
```

Import a profile:

```bash
konsave -i config/lukk_desktop_profile.knsv
```

Apply it:

```bash
konsave -a lukk_desktop_profile
```

## Complex roles

Some installations cannot be abstracted through a single package manager and have their own role:

- `ai_tools` — npm / Go binaries (Claude Code, OpenCode, OpenSpec, Cowork Service) and Claude Desktop per platform.
- `sdk_manager` — Pyenv, NVM, SDKMAN, FVM, Android SDK, Dart.
- `linux_crypto_hardware` — udev rules for Trezor and Ledger.
- `waydroid` — kernel parameters and custom GDM files for the Wayland container.
- `system_core` — system upgrade, tmpfs, GRUB timeout, RTC fix, locale.
- `virtualization_config` — QEMU/KVM + virt-manager + virtiofsd on Linux; auto-installs `spice-vdagent` inside a VM guest. macOS uses UTM (Apple Virtualization). Windows uses VirtualBox via Chocolatey. VMware Workstation Player auto-install is currently broken: Broadcom moved the download behind a portal login. Install manually or use VirtualBox.

## Non-standard installation methods

The entries below do not come from the default package manager for the OS. Each uses a custom path because of packaging limits or a missing official distro package. Authoritative mappings live in [`ansible/vars/`](ansible/vars/); these tables are illustrative, not exhaustive.

### AI tools (`roles/ai_tools`)

| Software | Ubuntu/Debian | Arch Linux | Fedora | macOS | Windows |
|---|---|---|---|---|---|
| **Claude Code CLI** | `npm install -g @anthropic-ai/claude-code` (official) | ← same | ← same | ← same | ← same |
| **Claude Desktop** | Unofficial APT repo script → `apt install` | AUR: `claude-desktop-bin` | `alien` converts official `.deb` → RPM | `brew install --cask claude` (official) | — |
| **Claude Cowork** | Build from source via `go` + `make install` | ← same | ← same | ← same | — |
| **OpenCode** | `npm install -g opencode-ai` | ← same | ← same | ← same | ← same |
| **OpenSpec** | `npm install -g openspec` | ← same | ← same | ← same | ← same |

### Virtualization tools

| Software | Ubuntu/Debian | Arch Linux | Fedora | macOS | Windows |
|---|---|---|---|---|---|
| **QEMU/KVM + virt-manager** | Native `apt` packages | Native `pacman` packages | Native `dnf` packages | — | — |
| **UTM** | — | — | — | `brew install --cask utm` (native Apple Virtualization) | — |
| **VirtualBox** | — | — | — | — | Winget: `Oracle.VirtualBox` |
| **VMware** | — | — | — | `brew install --cask vmware-fusion` | Manual — no winget manifest post-Broadcom |
| **Docker** | Official Docker CE APT repo + `docker-ce` | Native `pacman` `docker` | Official Docker CE DNF repo + `docker-ce` | `brew install --cask docker-desktop` | Winget: `Docker.DockerDesktop` |

### SDK managers (`roles/sdk_manager`)

| Software | Ubuntu/Debian | Arch Linux | Fedora | macOS | Windows |
|---|---|---|---|---|---|
| **NVM** | `curl` installer script | ← same | ← same | ← same | Chocolatey: `nvm` |
| **Pyenv** | `curl pyenv.run \| bash` | ← same | ← same | ← same | Winget: `Python.Python.3.11` |
| **SDKMAN** | `curl` installer script | ← same | ← same | ← same | — |
| **Dart SDK** | Custom curl install | ← same | ← same | ← same | — |
| **FVM (Flutter)** | Dart pub global | ← same | ← same | ← same | — |
| **Android SDK** | Manual download of cmdline-tools zip + `sdkmanager` | ← same | ← same | ← same | Winget: `Google.AndroidStudio` |

### URL-based package installs (`roles/software_installer`)

These entries use direct download URLs (via the `url:` field on a software mapping, dispatched by the `apt_url` / `dnf_url` managers) because no official distro package exists or the repo version is too old. Pinned versions and URL templates live in `group_vars/versions.yaml`.

| Software | Ubuntu/Debian | Arch Linux | Fedora |
|---|---|---|---|
| **Minikube** | Direct `.deb` URL | `pacman` (official) | Direct `.rpm` URL |
| **Balena Etcher** | Direct `.deb` URL (GitHub releases) | AUR: `balena-etcher` | Direct `.rpm` URL (GitHub releases) |
| **Veracrypt** | Direct `.deb` URL (Launchpad) | `pacman` (official) | Direct `.rpm` URL (Launchpad) |
| **TeamViewer** | Direct `.deb` URL | AUR: `teamviewer` | Direct `.rpm` URL |
| **AppImageLauncher** | Direct `.deb` URL (GitHub releases) | AUR: `appimagelauncher` | Direct `.rpm` URL (GitHub releases) |
| **Chrome** | Official APT repo (signed-by /etc/apt/keyrings/google-chrome.asc) + `apt install google-chrome-stable` | AUR: `google-chrome` | Official DNF repo + `dnf install google-chrome-stable` |
| **Brave** | Official APT repo (brave-browser-apt-release.s3.brave.com) + `apt install brave-browser` | AUR: `brave-bin` | Official DNF repo + `dnf install brave-browser` |
| **VS Code** | Official Microsoft APT repo (packages.microsoft.com/repos/code) + `apt install code` | AUR: `visual-studio-code-bin` | Official MS DNF repo + `dnf install code` |
| **Sublime Text** | Official Sublime APT repo (download.sublimetext.com/apt/stable) + `apt install sublime-text` | AUR: `sublime-text-4` | Official Sublime DNF repo + `dnf install sublime-text` |
| **kubectl** | Official Kubernetes APT repo (`pkgs.k8s.io/core` minor pinned in `versions.yaml`, currently `v1.34`) + `apt install kubectl` | `pacman kubectl` | Official Kubernetes DNF repo + `dnf install kubectl` |
| **Docker** | Official Docker CE APT repo (download.docker.com) + `apt install docker-ce` | `pacman docker` | Official Docker CE DNF repo + `dnf install docker-ce` |

> Repo keyrings, GPG keys, and `*.repo`/`*.list` files are provisioned automatically by `roles/software_installer/tasks/debian_repos.yaml` and `fedora_repos.yaml` before the batched apt/dnf install runs.

### Download integrity (optional)

`setup/ansible/group_vars/versions.yaml` exposes a `download_checksums` mapping. To enforce sha256 verification on `get_url` tasks (e.g. AppImage downloads, custom DMG/EXE installers), set:

```yaml
download_checksums:
  lens_appimage: "sha256:0123abcd..."
  gputest:       "sha256:..."
  antigravity_macos: "sha256:..."
  gridcoin_macos: "sha256:..."
  gridcoin_flatpak: "sha256:..."
```

Leaving an entry unset disables checksum enforcement for that download (Ansible uses `omit`).

### Crypto hardware (`roles/linux_crypto_hardware`)

| Software | Ubuntu/Debian | Arch Linux | Fedora |
|---|---|---|---|
| **Ledger udev rules** | `wget` script from LedgerHQ GitHub | ← same | ← same |
| **Trezor udev rules** | Official `.deb` from trezor.io | AUR: `trezor-udev` | Direct rules file from trezor.io + `udevadm reload` |
| **boot-repair** | PPA `yannubuntu/boot-repair` → apt (via `system_core`) | N/A — use `grub-install` from base `grub` package | `grubby` (default Fedora GRUB management CLI) |
