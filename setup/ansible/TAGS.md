# Ansible Tags Reference

Surgical re-run support for `site.yaml`. Default runs (no `--tags`) execute every task unchanged. Tags only do something when you pass `--tags X` or `--skip-tags X` on the CLI.

## Why use tags

The playbook takes 30-40 minutes end-to-end. If only Docker broke, you don't need to re-run NVM, Pyenv, KDE config, software_installer, etc. `--tags docker` finishes in under a minute and only touches docker-related tasks.

## Default run (no tags)

Full install. Everything fires.

```bash
ansible-playbook site.yaml -i localhost, -c local -K
```

PowerShell from WSL:

```powershell
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper/setup/ansible && ansible-playbook site.yaml -i localhost, -c local -K"
```

## Listing available tags

```bash
ansible-playbook --list-tags site.yaml -i localhost, -c local
```

To see exactly which tasks a tag selects without running them:

```bash
ansible-playbook --list-tasks --tags docker site.yaml -i localhost, -c local
```

## Tag hierarchy

Two layers. Layer 1 = whole role (broad). Layer 2 = a subsystem inside a role (surgical).

### Layer 1 — Role-level tags

Pass any of these to run a whole role.

| Tag | What it runs |
|---|---|
| `bootstrap_windows` | Core Windows bootstrap (winget enablement, prereqs) |
| `bootstrap_macos` | Core macOS bootstrap (Homebrew install + PATH) |
| `bootstrap_arch` | Core Arch bootstrap (paru/yay, multilib, base config) |
| `bootstrap_fedora` | Core Fedora bootstrap (Chrome/Brave/VSCode/Sublime/Antigravity repos, snapd) |
| `bootstrap_debian` | Core Debian/Ubuntu bootstrap (sudoers, contrib/non-free, snapd) |
| `linux_core` | Cross-distro Linux system_core (timezone, ufw, base utils) |
| `boot` | systemd-boot bootloader install + BLS entry generation |
| `kde` | KDE Plasma install + configure |
| `gnome` | GNOME install + configure |
| `env` | Environment variables (PATH, JAVA_HOME, ANDROID_HOME, etc.) |
| `shell` | ZSH + Oh-My-Zsh + Powerlevel10k |
| `sdk` | All SDK managers (NVM + SDKMAN + Pyenv + Dart + FVM + Android) |
| `ai` | All AI tools (Claude Code + Claude Desktop + OpenCode + OpenSpec + LM Studio + Stable Diffusion) |
| `jetbrains` | JetBrains Toolbox |
| `software` | Whole software_installer router (every app via every manager) |
| `waydroid` | Waydroid Android container |
| `crypto` | Hardware wallet udev rules (Ledger, Trezor) |
| `security` | Hibernate + LUKS hibernate config |
| `snapper` | Btrfs Snapper config |
| `virt` | Whole virtualization role (libvirt + Docker + spice-vdagent) |

### Layer 2 — Subsystem tags

Pass any of these to run just that subsystem. Inherits the parent role tag automatically, so `--tags nvm` is effectively `--tags sdk,nvm` with nvm-only filtering inside `sdk`.

#### SDK manager subsystems

| Tag | What it runs | Hard dep (must run first if missing) |
|---|---|---|
| `nvm` | NVM install + Node LTS install | — |
| `sdkman` | SDKMAN install + all four Java JDKs (11, 17, 21, 25) | — |
| `pyenv` | Pyenv install + four Python builds | system build deps (gcc, make) — covered by `linux_core` |
| `dart` | Dart SDK (pacman on Arch, apt on Debian, zip on Fedora, brew tap on macOS) | — |
| `fvm` | FVM install via `dart pub global activate` + Flutter SDK | `dart` (auto-installs dart on Arch when missing) |
| `android` | Android cmdline-tools + platform + build-tools + SDK licenses | `sdkman` (skips with warning if SDKMAN Java is missing) |

#### AI tools subsystems

| Tag | What it runs | Hard dep |
|---|---|---|
| `claude` | Claude Code CLI (npm) + Claude Desktop (.deb / AUR / cask) | `nvm` (skips with warning if nvm.sh is missing) |
| `opencode` | OpenCode CLI (npm) | `nvm` (skips with warning) |
| `openspec` | OpenSpec CLI (npm) | `nvm` (skips with warning) |
| `bruno_cli` | Bruno CLI — `bruno-cli` brew formula on macOS, `@usebruno/cli` via npm on Linux + Windows | `nvm` on Linux/Windows (skips with warning) |
| `local_llm` | LM Studio + Stable Diffusion WebUI | — |

#### Virtualization subsystems

| Tag | What it runs | Hard dep |
|---|---|---|
| `libvirt` | QEMU/KVM + virt-manager + libvirtd service + user→libvirt/kvm groups | — |
| `docker` | Docker CE + buildx + compose + libvirt-nftables fixup (Arch) + docker service + user→docker group | `libvirt` (on Arch: the firewall_backend tweak is skipped if libvirtd isn't installed — Docker still works fine without it when libvirt isn't on the host) |

#### Software installer subsystems

| Tag | What it runs |
|---|---|
| `apt_batch` | Debian/Ubuntu APT repos (Chrome, Brave, VSCode, etc.) + batched apt install + apt_url .deb installs |
| `dnf_batch` | Fedora DNF repos (Docker CE, Chrome, etc.) + batched dnf install + dnf_url .rpm installs |
| `pacman_batch` | Pacman batched install + AUR per-item async install |
| `snap` | Snap package installs |
| `flatpak` | Flathub remote + Flatpak batched installs (Debian via raw, Arch/Fedora via module) |
| `brew` | Homebrew formulas + Casks (macOS) |
| `choco` | Chocolatey packages (Windows) |
| `winget` | Winget packages (Windows) |

## Common recipes

### Just retry the Docker chain after a failure

```bash
ansible-playbook site.yaml --tags docker -i localhost, -c local -K
```

### Re-run all virtualization (libvirt + Docker together)

```bash
ansible-playbook site.yaml --tags virt -i localhost, -c local -K
```

### Reinstall a single SDK after a config change

```bash
ansible-playbook site.yaml --tags pyenv -i localhost, -c local -K
```

### Re-run AI CLIs (nvm must already be installed)

```bash
ansible-playbook site.yaml --tags ai -i localhost, -c local -K
```

### Combine multiple tags (union — any task with any of these tags)

```bash
ansible-playbook site.yaml --tags claude,opencode,openspec -i localhost, -c local -K
```

### Re-run just the Flatpak batch after the cache cleared

```bash
ansible-playbook site.yaml --tags flatpak -i localhost, -c local -K
```

### Re-run only the SDK manager dispatchers (NVM + SDKMAN + Pyenv + Dart + FVM + Android)

```bash
ansible-playbook site.yaml --tags sdk -i localhost, -c local -K
```

### Full install but skip the slow flatpak batch (e.g. you'll do it manually)

```bash
ansible-playbook site.yaml --skip-tags flatpak -i localhost, -c local -K
```

## Inter-tag dependencies (read this before complaining)

Some Layer 2 subsystems genuinely depend on other Layer 2 subsystems. The playbook handles these gracefully but it's worth knowing:

| Subsystem | Hard dep | Behavior when dep is missing |
|---|---|---|
| `fvm` on Arch | `dart` | Auto-installs dart via pacman (idempotent — no-op if already there) |
| `claude`, `opencode`, `openspec`, `bruno_cli` | `nvm` (Linux + Windows only) | Skips with `[WARN]` debug message; instructs you to run `--tags nvm,ai`. On macOS, these tools install via brew (`bruno_cli` uses the `bruno-cli` formula; `claude`/`opencode`/`openspec` continue to use npm under brew-installed Node) and have no nvm dep. |
| `android` | `sdkman` (provides Java) | Skips with `[WARN]` debug message; instructs you to run `--tags sdkman,android` |
| `docker` on Arch (with virt-manager installed) | `libvirt` | The libvirt firewall_backend fixup is skipped if libvirtd unit is absent (which is correct — without libvirt, Docker doesn't need that fixup) |

If you see a `[WARN] Skipping ...` debug line, that's the playbook telling you which tag combo to use.

### macOS asymmetry for tools that have a brew formula

`bruno_cli` is the one tool whose macOS install lives in `software_installer` (brew formula
`bruno-cli` in [vars/Darwin.yaml](vars/Darwin.yaml)) rather than in the `ai_tools` role. That means:

- `--tags bruno_cli` on macOS is a **silent no-op** — the macOS install only triggers under
  `--tags brew` or `--tags software`.
- A full run (no `--tags` filter) installs Bruno CLI on every OS as expected; the asymmetry only
  matters for surgical re-runs.
- Linux and Windows still install via the npm helper, gated by `--tags bruno_cli`.

The same applies to any future tool that adds a brew formula entry in `vars/Darwin.yaml` —
see [docs/AI_TOOLS_ADDING.md](../../docs/AI_TOOLS_ADDING.md).

## Reserved tag names (avoid these)

| Name | Meaning |
|---|---|
| `always` | Tasks with this tag run even when other `--tags X` filters are active. Used in this playbook for `pre_tasks` that load OS-specific group_vars (those MUST run for any other task to resolve variables correctly). |
| `never` | Tasks with this tag are skipped by default unless explicitly named in `--tags`. Not currently used in this playbook. |

Don't apply `always` or `never` to new tasks unless you actually want that behavior.

## How tag propagation works in this playbook

For each role-include in `site.yaml`:

- Plain `import_role` lines (windows_core, macos_core, etc.) — tag is added on the line directly. `import_role` is static, so the tag propagates to every task inside the role.
- Block-wrapped `import_role` lines (sdk_manager, virt, etc.) — tag is on the **block**, propagates to the inner `import_role` and to the `rescue:` handler. `include_role` was converted to `import_role` specifically so this static propagation works; the block+rescue semantics are unchanged.

For dispatchers inside roles (e.g. `sdk_manager/tasks/main.yaml` includes `nvm.yaml`):

- Each `include_tasks` line carries `tags: [X]` (so `--tags X` matches the include) AND `apply: tags: [X]` (so `X` is added to every task inside the included file, ensuring inner tasks match the same filter).
- For `import_tasks` (static include — used in `ai_tools/tasks/main.yaml`), tag propagation is automatic; no `apply:` needed.

For individual tasks inside dynamic-include files (e.g. `virtualization_config/tasks/main.yaml`):

- Tagged per-task with the subsystem tag. They also inherit the role tag from the parent block.

## Verification (after editing tags)

Always re-run after touching tag definitions:

```bash
ansible-playbook --syntax-check site.yaml -i localhost, -c local
```

```bash
ansible-playbook --list-tags site.yaml -i localhost, -c local
```

```bash
ansible-playbook --list-tasks --tags YOUR_NEW_TAG site.yaml -i localhost, -c local
```

If the last command shows zero tasks (other than `always`-tagged pre_tasks), the tag isn't wired up correctly.
