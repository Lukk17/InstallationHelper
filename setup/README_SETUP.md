# Setup

> Cross-platform, data-driven Ansible setup for Ubuntu, Debian, Fedora, Arch, macOS, and Windows (via WSL).

---

### Where else to look

---

For configuration tasks and toggle reference, see [CONFIGURATION.md](CONFIGURATION.md). For the full software
catalogue, see [SOFTWARE.md](SOFTWARE.md). For where to look up versions across every package manager and direct-URL
source, see [VERSION_SOURCES.md](VERSION_SOURCES.md). Authoritative per-OS package mappings live in
[ansible/vars/](ansible/vars/).

### Using the setup script

---

The setup script detects your OS, installs Ansible and the required Galaxy collections, then runs an interactive
checklist for software selection.

The wizard uses `gum` (charm.sh) on Linux and macOS and `Microsoft.PowerShell.ConsoleGuiTools` on Windows for
filter-as-you-type pickers. Both are installed automatically on first run.

Run it as your regular user. Do not use `sudo`.

Linux / macOS:

```bash
bash setup/setup.sh
```

Windows (PowerShell 7+ — **non-elevated session**, not "Run as Administrator"):

```powershell
pwsh setup/setup.ps1
```

The playbook installs npm-based CLIs (Claude Code, OpenCode, OpenSpec, Bruno CLI) globally via
`npm install -g`. Running the playbook from an elevated PowerShell window writes those packages into
`%ProgramFiles%\nodejs\node_modules` and executes lifecycle scripts with Administrator rights, which
is a wider blast radius than necessary. From a normal user session, `npm install -g` lands in
`%AppData%\Roaming\npm` and runs unprivileged. Chocolatey tasks that legitimately need elevation will
trigger UAC prompts on their own — there is no benefit to pre-elevating the whole run.

What the script does:

1. Detects the OS and distribution.
2. Installs Ansible via the matching package manager if it is missing.
3. Installs `gum` (Linux / macOS) or `Microsoft.PowerShell.ConsoleGuiTools` (Windows) if missing.
4. Installs the Galaxy collections pinned in
   [setup/ansible/requirements.yaml](ansible/requirements.yaml) (`community.general`, `community.windows`,
   `ansible.windows`, `ansible.posix`, `community.docker`, `kewlfft.aur`). Re-runs are no-ops.
5. Presents an interactive menu for the desktop environment.
6. Optionally lets you review individual software and feature toggles in a filter-as-you-type grid.
7. Runs the playbook with your selections, prompting for sudo when needed.

#### Script options

---

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

Skip the pre-Ansible system upgrade (apt / dnf / pacman / brew full-upgrade). Useful for CI, live USB, or when you've
just upgraded:

```bash
bash setup/setup.sh --skip-system-upgrade
```

PowerShell equivalent:

```powershell
pwsh setup/setup.ps1 -SkipSystemUpgrade
```

Requirements:

- Linux (Ubuntu / Debian, Fedora, Arch) or macOS, with an internet connection and `sudo`.
- Windows: PowerShell 7+ and WSL (`wsl --install -d Ubuntu`).

### Manual run

---

Use this only if you prefer to drive Ansible directly. All commands run from [setup/ansible/](ansible/).

#### 1. Install Ansible

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

Windows: install WSL, open Ubuntu, then follow the Ubuntu / Debian steps above. Ansible does not run natively on
Windows.

```powershell
wsl --install -d Ubuntu
```

##### Arch Linux: enable multilib for Steam

Steam needs the multilib repo. Without it, the playbook skips Steam with a warning.

```bash
sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
```

```bash
sudo pacman -Sy
```

#### 2. Move into the Ansible directory

```bash
cd setup/ansible
```

#### 3. Install Galaxy collections

```bash
ansible-galaxy collection install -r requirements.yaml
```

#### 4. Configure toggles

Review [group_vars/all.yaml](ansible/group_vars/all.yaml) and the OS-specific files under
[group_vars/](ansible/group_vars/). Set the toggles you want enabled. To override values from a profile, point
Ansible at [profiles/<name>.yaml](ansible/profiles/) at runtime.

#### 5. Run the playbook

The `-K` flag prompts for the sudo password.

Standard run:

```bash
ansible-playbook site.yaml -i localhost, -c local -K
```

Linux Live / USB profile:

```bash
ansible-playbook site.yaml -i localhost, -c local -e "@profiles/linux_live.yaml" -K
```

### Logging

---

Every run writes four log files in your home directory:

| Log file | Contents |
|---|---|
| `~/installation_full.log` | Complete playbook output, phase separators, per-task duration, and an end-of-run grouped summary (installed, already-present, skipped, failed). |
| `~/installation_errors.log` | Only FAILED tasks and `unreachable` hosts. |
| `~/installation_warnings.log` | Only WARNING-level entries (deprecations, captured stderr, etc.). |
| `~/installation_skipped.log` | Per-item skips with the reason category (toggle disabled, not for this OS, ...). |

All four files are overwritten on each run. Captured stdout / stderr from any single task is truncated after 30 lines
so license dumps and verbose installer chatter don't bloat the log.

#### Watching progress live

---

Long-running tasks (flatpak install of all GUI apps, `apt full-upgrade`, batched apt install) print one in-band
progress line per package as they go:

```text
⏳ running: software_installer : Install Flatpak packages (Debian, batched...)
  ↳ [00m08s] Installing 1/47… app/com.spotify.Client/x86_64/stable
  ↳ [00m42s] Installing 2/47… app/com.bitwarden.desktop/x86_64/stable
  ↳ [01m15s] Installing 3/47… runtime/org.freedesktop.Platform/x86_64/24.08
  ↳ [06m15s] still working… (log unchanged)
  ↳ [09m02s] Installing 4/47… runtime/org.mozilla.firefox.Locale/x86_64/stable
[+44m 08s] CHANGED: [localhost]
```

The `↳` lines fire on every progress change. The `still working… (log unchanged)` line fires every 5 minutes when
the underlying tool stops printing. Three of those in a row is a real stall (network dead, mirror unreachable);
otherwise the install is just slow.

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
| `Install QEMU/KVM and virt-manager packages (Debian)` | `/var/log/installation-virt-apt.log` |
| `Install Docker CE (Debian)` | `/var/log/installation-docker-apt.log` |
| `Install Claude Desktop .deb (Linux Debian)` | `/var/log/installation-claude-desktop-apt.log` |

On Windows the playbook runs inside WSL, so the same files live under WSL's filesystem. Tail them from PowerShell
with:

```powershell
wsl -d Ubuntu tail -f /var/log/installation-flatpak-batch.log
```

The heartbeat tick (default 5s) and idle-ping window (default 300s) are tunable:

```bash
DUAL_LOGGER_HEARTBEAT_SEC=10 DUAL_LOGGER_IDLE_PING_SEC=120 ansible-playbook site.yaml -i localhost, -c local -K
```

PowerShell equivalent inside WSL:

```powershell
wsl -d Ubuntu bash -c "DUAL_LOGGER_HEARTBEAT_SEC=10 DUAL_LOGGER_IDLE_PING_SEC=120 ansible-playbook /mnt/d/path/to/setup/ansible/site.yaml -i localhost, -c local -K"
```

`Ctrl+C` interrupts the whole playbook, not a single task. If a specific install is stuck and you want to abort
cleanly, kill the playbook then re-run. Every task uses `creates:` or other idempotency guards and skips finished
work.

#### Troubleshooting log errors

---

If the playbook fails with:

```text
FATAL: Cannot open log files in /home/<you>: ...
```

First check that your user has write access to the home directory. If you genuinely need to run without file logging,
set the following in [group_vars/all.yaml](ansible/group_vars/all.yaml):

```yaml
allow_callback_failure: true
```

Or pass it inline for a single run:

```bash
ansible-playbook site.yaml -i localhost, -c local -K --extra-vars "allow_callback_failure=true"
```

### Surgical re-runs with tags

---

The playbook supports tag-based partial runs. After a failure, you can re-run only the failed subsystem instead of
the full 30 to 50 minute playbook. Full taxonomy in [setup/ansible/TAGS.md](ansible/TAGS.md).

Examples:

```bash
ansible-playbook site.yaml --tags docker -i localhost, -c local -K
```

```bash
ansible-playbook site.yaml --tags fvm,nvm -i localhost, -c local -K
```

List every available tag:

```bash
ansible-playbook --list-tags site.yaml -i localhost, -c local
```

### Desktop environments (Linux)

---

The file [group_vars/linux.yaml](ansible/group_vars/linux.yaml) separates install from configure so you can theme a
pre-installed DE (Fedora KDE Spin, etc.) without reinstalling it:

- `install_kde_plasma: true` installs KDE via the system package manager.
- `configure_kde_plasma: true` applies themes, widgets, and shortcuts.
- Equivalent toggles exist for GNOME: `install_gnome`, `configure_gnome`.

#### Konsave profile management (KDE)

---

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

### Complex roles

---

Some installations cannot be abstracted through a single package manager and have their own role:

- [ai_tools](ansible/roles/ai_tools/): npm and Go binaries (Claude Code, OpenCode, OpenSpec, Cowork Service) plus
  Claude Desktop per platform.
- [sdk_manager](ansible/roles/sdk_manager/): Pyenv, NVM, SDKMAN, FVM, Android SDK, Dart.
- [linux_crypto_hardware](ansible/roles/linux_crypto_hardware/): udev rules for Trezor and Ledger.
- [waydroid](ansible/roles/waydroid/): kernel parameters and custom GDM files for the Wayland container.
- [system_core](ansible/roles/system_core/): system upgrade, tmpfs, GRUB timeout, RTC fix, locale.
- [virtualization_config](ansible/roles/virtualization_config/): QEMU/KVM, virt-manager, and virtiofsd on Linux.
  Auto-installs `spice-vdagent` inside a VM guest. macOS uses UTM (Apple Virtualization). Windows uses VirtualBox via
  Chocolatey. VMware Workstation Player auto-install is currently broken (Broadcom moved the download behind a portal
  login); install manually or use VirtualBox.

### Non-standard installation methods

---

The entries below do not come from the default package manager for the OS. Each uses a custom path because of
packaging limits or a missing official distro package. Authoritative mappings live in
[ansible/vars/](ansible/vars/); these tables are illustrative, not exhaustive.

#### AI tools

---

Source role: [roles/ai_tools/](ansible/roles/ai_tools/).

| Software | Ubuntu / Debian | Arch | Fedora | macOS | Windows |
|---|---|---|---|---|---|
| **Claude Code CLI** | `npm install -g @anthropic-ai/claude-code` | same | same | same | same |
| **Claude Desktop** | unofficial APT repo script, then `sudo apt-get install -y claude-desktop` | `yay -S claude-desktop-bin` | `alien` conversion of the official `.deb`, then `sudo dnf install -y ./claude-desktop*.rpm` | `brew install --cask claude` | `winget install -e --id Anthropic.Claude`, not wired into the playbook |
| **Claude Cowork** | Build from source via `go` and `make install` | same | same | same | not available |
| **OpenCode** | `npm install -g opencode-ai` | same | same | same | same |
| **OpenSpec** | `npm install -g openspec` | same | same | same | same |

#### Virtualization tools

---

| Software | Ubuntu / Debian | Arch | Fedora | macOS | Windows |
|---|---|---|---|---|---|
| **QEMU/KVM + virt-manager** | `sudo apt-get install -y qemu-kvm libvirt-daemon-system virt-manager virtinst bridge-utils virtiofsd` | `sudo pacman -S --needed virt-manager qemu-full libvirt dnsmasq nftables bridge-utils virtiofsd` | `sudo dnf install -y qemu-kvm libvirt virt-manager virt-install bridge-utils virtiofsd` | not available | not available |
| **UTM** | not available | not available | not available | `brew install --cask utm` | not available |
| **VirtualBox** | not available | not available | not available | not available | `winget install -e --id Oracle.VirtualBox` |
| **VMware** | not available | not available | not available | `brew install --cask vmware-fusion` | `choco install vmware-workstation-player -y` |
| **Docker** | `sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin` (repo first) | `sudo pacman -S --needed docker` | `sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin` (repo first) | `brew install --cask docker-desktop` | `winget install -e --id Docker.DockerDesktop` |

#### SDK managers

---

Source role: [roles/sdk_manager/](ansible/roles/sdk_manager/).

| Software | Ubuntu / Debian | Arch | Fedora | macOS | Windows |
|---|---|---|---|---|---|
| **NVM** | `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh \| bash` | same | same | same | `winget install -e --id CoreyButler.NVMforWindows` |
| **Pyenv** | `curl https://pyenv.run \| bash` | same | same | same | `choco install pyenv-win -y` |
| **SDKMAN** | `curl -s https://get.sdkman.io \| bash` | same | same | same | not available, use WSL |
| **Dart SDK** | `sudo apt-get install -y dart` | `sudo pacman -S --needed dart` | `sudo dnf install -y dart` | `brew install dart` | manual from [dart.dev](https://dart.dev/get-dart) |
| **FVM (Flutter)** | `curl -fsSL https://fvm.app/install.sh \| bash` | same | same | same | manual from [fvm.app](https://fvm.app/documentation/getting-started/installation) |
| **Android SDK** | `sdkmanager "platform-tools" "build-tools;35.0.0"` after the cmdline-tools zip is unpacked | same | same | same | `winget install -e --id Google.AndroidStudio` |

#### URL-based package installs

---

Source role: [roles/software_installer/](ansible/roles/software_installer/). These entries use direct download URLs
(via the `url:` field on a software mapping, dispatched by the `apt_url` and `dnf_url` managers) because no official
distro package exists or the repo version is too old. Pinned versions and URL templates live in
[group_vars/versions.yaml](ansible/group_vars/versions.yaml).

| Software | Ubuntu / Debian | Arch | Fedora |
|---|---|---|---|
| **Minikube** | `curl -fsSLo /tmp/minikube.deb https://github.com/kubernetes/minikube/releases/download/v1.38.1/minikube_1.38.1-0_amd64.deb && sudo apt-get install -y /tmp/minikube.deb` | `sudo pacman -S --needed minikube` | `sudo dnf install -y https://github.com/kubernetes/minikube/releases/download/v1.38.1/minikube-1.38.1-0.x86_64.rpm` |
| **Balena Etcher** | `curl -fsSLo /tmp/balena-etcher.deb https://github.com/balena-io/etcher/releases/download/v2.1.6/balena-etcher_2.1.6_amd64.deb && sudo apt-get install -y /tmp/balena-etcher.deb` | not installed, the AUR package conflicts with nodejs | `sudo dnf install -y https://github.com/balena-io/etcher/releases/download/v2.1.6/balena-etcher-2.1.6-1.x86_64.rpm` |
| **Veracrypt** | `curl -fsSLo /tmp/veracrypt.deb https://launchpad.net/veracrypt/trunk/1.26.24/+download/veracrypt-1.26.24-Ubuntu-24.04-amd64.deb && sudo apt-get install -y /tmp/veracrypt.deb` | `sudo pacman -S --needed veracrypt` | `sudo dnf install -y https://launchpad.net/veracrypt/trunk/1.26.24/+download/veracrypt-1.26.24-CentOS-8-x86_64.rpm` |
| **TeamViewer** | `curl -fsSLo /tmp/teamviewer.deb https://download.teamviewer.com/download/linux/teamviewer_amd64.deb && sudo apt-get install -y /tmp/teamviewer.deb` | `yay -S teamviewer` | `sudo dnf install -y https://download.teamviewer.com/download/linux/teamviewer.x86_64.rpm` |
| **AppImageLauncher** | `curl -fsSLo /tmp/appimagelauncher.deb https://github.com/TheAssassin/AppImageLauncher/releases/download/v2.2.0/appimagelauncher_2.2.0-travis995.0f91801.bionic_amd64.deb && sudo apt-get install -y /tmp/appimagelauncher.deb` | `yay -S appimagelauncher` | `curl -fsSLo /tmp/appimagelauncher.rpm https://github.com/TheAssassin/AppImageLauncher/releases/download/v2.2.0/appimagelauncher-2.2.0-travis995.0f91801.x86_64.rpm && sudo rpm --install --nodigest /tmp/appimagelauncher.rpm` |
| **Chrome** | `sudo apt-get install -y google-chrome-stable` (repo first) | `yay -S google-chrome` | `sudo dnf install -y google-chrome-stable` (repo first) |
| **Brave** | `sudo apt-get install -y brave-browser` (repo first) | `yay -S brave-bin` | `sudo dnf install -y brave-browser` (repo first) |
| **VS Code** | `sudo apt-get install -y code` (repo first) | `yay -S visual-studio-code-bin` | `sudo dnf install -y code` (repo first) |
| **Sublime Text** | `sudo apt-get install -y sublime-text` (repo first) | `yay -S sublime-text-4` | `sudo dnf install -y sublime-text` (repo first) |
| **kubectl** | `sudo apt-get install -y kubectl` (repo first, minor pinned in `versions.yaml`) | `sudo pacman -S --needed kubectl` | `sudo dnf install -y kubectl` (repo first) |
| **Helm** | `sudo apt-get install -y helm` (repo first) | `sudo pacman -S --needed helm` | `sudo dnf install -y helm` |
| **Terraform** | `sudo apt-get install -y terraform` (repo first) | `sudo pacman -S --needed terraform` | `sudo dnf install -y terraform` (repo first) |
| **GitHub CLI (gh)** | `sudo apt-get install -y gh` (repo first) | `sudo pacman -S --needed github-cli` | `sudo dnf install -y gh` |
| **Syncthing** | `sudo apt-get install -y syncthing` (repo first) | `sudo pacman -S --needed syncthing` | `sudo dnf install -y syncthing` |
| **Docker** | `sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin` (repo first) | `sudo pacman -S --needed docker` | `sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin` (repo first) |

Repo keyrings, GPG keys, and `*.repo` and `*.list` files are provisioned automatically by
[debian_repos.yaml](ansible/roles/software_installer/tasks/debian_repos.yaml) and
[fedora_repos.yaml](ansible/roles/software_installer/tasks/fedora_repos.yaml) before the batched apt / dnf install
runs.

#### Download integrity (optional)

---

The file [group_vars/versions.yaml](ansible/group_vars/versions.yaml) exposes a `download_checksums` mapping. To
enforce sha256 verification on `get_url` tasks (e.g. AppImage downloads, custom DMG / EXE installers), set:

```yaml
download_checksums:
  lens_appimage: "sha256:0123abcd..."
  gputest:       "sha256:..."
  antigravity_macos: "sha256:..."
  gridcoin_macos: "sha256:..."
  gridcoin_flatpak: "sha256:..."
```

Leaving an entry unset disables checksum enforcement for that download (Ansible uses `omit`).

#### Crypto hardware

---

Source role: [roles/linux_crypto_hardware/](ansible/roles/linux_crypto_hardware/).

| Software | Ubuntu / Debian | Arch | Fedora |
|---|---|---|---|
| **Ledger udev rules** | `wget` script from LedgerHQ GitHub | same | same |
| **Trezor udev rules** | Official `.deb` from trezor.io | AUR: `trezor-udev` | Direct rules file from trezor.io + `udevadm reload` |
| **boot-repair** | PPA `yannubuntu/boot-repair` then apt (via `system_core`) | not available; use `grub-install` from base `grub` package | `grubby` (default Fedora GRUB management CLI) |

### Docs map

---

| Doc | What's in it |
| --- | --- |
| [../README.md](../README.md) | Project overview, quick start, repo structure |
| [CONFIGURATION.md](CONFIGURATION.md) | Toggle reference per OS |
| [SOFTWARE.md](SOFTWARE.md) | Full per-OS software catalogue with install methods |
| [VERSION_SOURCES.md](VERSION_SOURCES.md) | Where to look up the latest version for every pinned package |
| [ansible/TAGS.md](ansible/TAGS.md) | Ansible `--tags` taxonomy for surgical partial runs |
| [../docs/AGENT_TOOLING.md](../docs/AGENT_TOOLING.md) | Agent-standards, OpenSpec, per-agent integration notes |
| [../docs/MCP_SETUP.md](../docs/MCP_SETUP.md) | MCP server setup (Context7 only in this project) |
