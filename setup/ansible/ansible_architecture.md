# Ansible architecture

> How the playbook is put together, how one toggle becomes one installed package, and why two parts of it bypass Ansible's own modules.

The rules an agent must follow here are in [AGENTS.md](AGENTS.md). This page is the explanation behind them. Running the playbook for real is in [../README_SETUP.md](../README_SETUP.md).

---

### Execution order

[site.yaml](site.yaml) runs in this order:

1. Pre-tasks. [tasks/derive_os_facts.yaml](tasks/derive_os_facts.yaml) derives `ih_family` and `ih_base` before anything branches on them. Then the group vars of the family load, `group_vars/linux.yaml`, `group_vars/macos.yaml` or `group_vars/windows.yaml`, and [tasks/load_os_dict.yaml](tasks/load_os_dict.yaml) loads the family's dictionary from `vars/` as `os_dict`, with a derivative's own entries from `vars/derivatives/<os-release ID>.yaml` merged over it. CachyOS is the one derivative today. [verify_install.yaml](verify_install.yaml) loads the dictionary through the same file. [tasks/opencode_version.yaml](tasks/opencode_version.yaml) then decides which OpenCode version the run installs, and on Debian [tasks/apt_cache_refresh.yaml](tasks/apt_cache_refresh.yaml) refreshes the apt cache.
2. OS core roles: `macos_core`, `arch_core`, `fedora_core`, `debian_core`, `system_core`. There is no Windows role. Windows is provisioned natively by [../setup.ps1](../setup.ps1) and the modules in [../windows/](../windows/), and the playbook never runs there.
3. `systemd_boot`, on Linux and only when `setup_systemd_boot` is on.
4. Desktop environments: `kde_plasma_setup` and `gnome_setup`, gated by `install_kde_plasma` and `configure_kde_plasma`, and `install_gnome` and `configure_gnome`.
5. Cross-platform settings: `env_variables`, `shell_zsh`.
6. Roles with their own install logic: `sdk_manager` (Pyenv, NVM, SDKMAN, FVM and the Android SDK), `ai_tools` (Claude Code, Codex, Grok, Kilo Code, OpenCode, OpenSpec, the Bruno command line tool and the local model tools) and `jetbrains_toolbox`.
7. The software router, `software_installer`, which dispatches every enabled toggle through `os_dict`.
8. Linux only: `waydroid`, `linux_crypto_hardware`, `linux_security`, `snapper`, `virtualization_config`.
9. Post-tasks: the cleanup of package caches, the end-of-run warnings, and the task that fails the run when any role failed.

Every role after the core roles runs inside a block with a rescue that records the failure in `any_role_failed`, so one role failing does not stop the rest, and the run still ends failed.

---

### Configuration files

| File | Purpose |
|---|---|
| [group_vars/all.yaml](group_vars/all.yaml) | The main toggle file, which applications to install on every platform |
| [group_vars/linux.yaml](group_vars/linux.yaml) | Linux-only toggles: desktop environments, system settings, Linux-only applications |
| [group_vars/macos.yaml](group_vars/macos.yaml) | macOS-only toggles |
| [group_vars/windows.yaml](group_vars/windows.yaml) | Windows-only toggles, read by the PowerShell installer |
| [../pinned_values/pinned_values.toml](../pinned_values/pinned_values.toml) | Pinned versions, download locations and vendor identifiers, read through [../pinned_values/pinned_values.py](../pinned_values/pinned_values.py) |
| `vars/<OS>.yaml` | Translation dictionaries, one per family (`Debian`, `RedHat`, `Archlinux`, `Darwin`, `Windows`), mapping a generic application name to a manager and a package |
| `vars/derivatives/<os-release ID>.yaml` | Overrides for a distribution that maps something differently from its family, named after the `ID` field of `/etc/os-release`. [vars/derivatives/cachyos.yaml](vars/derivatives/cachyos.yaml) is the one today. [tasks/load_os_dict.yaml](tasks/load_os_dict.yaml) merges its entries over the family dictionary, each replacing the family entry of the same key whole, and it may carry `software_mapping` and nothing else |
| `lineage_companion_packages` in [vars/Debian.yaml](vars/Debian.yaml) | Companion lists that differ between Ubuntu and Debian lineage, put in front of the `companion_packages` entry of the same key by [tasks/load_os_dict.yaml](tasks/load_os_dict.yaml) |
| [profiles/linux_live.yaml](profiles/linux_live.yaml) | Override profile for USB and live installs |
| [../software.md](../software.md) | The complete per-OS software list with installation methods |

---

### How one toggle becomes one package

[group_vars/all.yaml](group_vars/all.yaml) declares intent, `install_chrome: true`. The dictionary of the family maps the application to a manager and a package name:

```yaml
chrome: { manager: "apt", package: "google-chrome-stable" }
```

The `software_installer` role, in [roles/software_installer/tasks/dynamic_install.yaml](roles/software_installer/tasks/dynamic_install.yaml), walks the enabled toggles, looks each one up in `os_dict`, and dispatches it to its manager. The managers it dispatches are `apt`, `apt_url`, `dnf`, `dnf_url`, `dnf_repo`, `pacman`, `aur`, `snap`, `flatpak`, `brew` and `brew_cask`. The `winget` and `choco` mappings in [vars/Windows.yaml](vars/Windows.yaml) are read by [../windows/WindowsSoftware.ps1](../windows/WindowsSoftware.ps1) instead, because the playbook never runs on Windows. Every apt, dnf, pacman, flatpak, snap and Homebrew install, the software set and every role's own packages alike, goes through [tasks/install_role_packages.yaml](tasks/install_role_packages.yaml), one package per call.

#### Package manager order per OS

1. Windows: winget, then Chocolatey, then the vendor's own installer. Chocolatey only where winget has no package or its manifest was measured broken, with the reason beside each mapping in [vars/Windows.yaml](vars/Windows.yaml). The vendor route only where Chocolatey is missing or measured unsuitable: FVM comes from pub.dev and pipx from pip, because Chocolatey's `fvm` and `pipx` each bring a second Dart SDK or Python. The Android command line tools come from Google's zip beside winget's `Google.AndroidStudio`, because no winget package carries them. Exceptions to the order: Gridcoin comes from the vendor's release although winget carries `Gridcoin.Client`, the Dart SDK from Chocolatey although winget carries `Google.DartSDK`, and Claude Code, OpenCode, Codex and Grok from npm although winget carries `Anthropic.ClaudeCode`, `SST.opencode`, `OpenAI.Codex` and `xAI.GrokBuild`. OpenSpec and the Bruno command line tool come from npm as well, and winget has neither. FVM, pipx, the Android command line tools and Gridcoin are in [../windows/WindowsCustomInstalls.ps1](../windows/WindowsCustomInstalls.ps1), the npm tools in [../windows/WindowsNpmTools.ps1](../windows/WindowsNpmTools.ps1).
2. macOS: Homebrew first, a formula for a command line tool and a cask for an application, then the Mac App Store or the vendor's own DMG or PKG. Nothing uses the Mac App Store today. The vendor routes are Razer Synapse and Gridcoin, which have no cask, and OpenCode desktop version 1, which `opencode_use_v1` installs instead of the version 2 cask and which has no cask either. Antigravity, JetBrains Toolbox, LM Studio and VirtualBox are casks like any other application, `antigravity`, `jetbrains-toolbox`, `lm-studio` and `virtualbox`. The `lm-studio` cask installs on Apple Silicon only. NVM, Pyenv, SDKMAN and FVM come from their own install scripts on every Unix, macOS included, although Homebrew carries formulae for NVM, Pyenv and FVM and casks for the Temurin JDKs SDKMAN installs. The Android command line tools come from Google's zip although the cask `android-commandlinetools` exists. Claude Code, OpenCode, OpenSpec, Codex and Grok come from npm although Homebrew carries the casks `claude-code`, `codex` and `grok-build` and the formulae `opencode` and `openspec`.
3. Debian and Ubuntu: the vendor's official apt repository, then Flatpak, then Snap, then the distribution's own apt.
4. Fedora: the vendor's official dnf repository, then Flatpak, then Snap, then the distribution's own dnf.
5. Arch: the official repositories through pacman, then the AUR through `yay`, then Flatpak, then Snap.

---

### Adding a new application

1. Add the toggle to [group_vars/all.yaml](group_vars/all.yaml), or to the OS-specific file when only Linux, macOS or Windows gets it.
2. Add a mapping under `software_mapping` in each `vars/<OS>.yaml` that should install it. A distribution that maps it differently from its family gets its entry in `vars/derivatives/<os-release ID>.yaml` instead, under `software_mapping`, in flow style with one line per entry, `key: { manager: "...", package: "..." }`, because the shell checks in [../../e2e/](../../e2e/) read those files line by line and see nothing else. A mapping whose package depends on steam also carries `brings_steam: true`, which [tasks/steam_graphics_alignment.yaml](tasks/steam_graphics_alignment.yaml) reads to decide whether the CachyOS 32-bit graphics alignment is needed.
3. If the application needs its own install logic, such as an SDK manager or a binary download, add a task file under the role it belongs to.
4. If a role installs packages under a toggle, beside its mapping or for a toggle with no mapping at all, list them under `companion_packages` in the same `vars/<OS>.yaml`, keyed by the toggle without `install_`, or the whole toggle name when it has no such prefix, one line per key, `key: ["a", "b"]`, and have the role read `os_dict.companion_packages.<key>`. [verify_install.yaml](verify_install.yaml) reads the same entry, and [../../e2e/tier1/verify_wiring.sh](../../e2e/tier1/verify_wiring.sh) fails on any role install under a toggle that does neither, unless [../../e2e/tier1/unverified_role_installs.txt](../../e2e/tier1/unverified_role_installs.txt) names it with the reason. A derivative file carries no `companion_packages`, it reads its family's.
5. Run the gate, and the tier 2 check for the new names, as [../../e2e/AGENTS.md](../../e2e/AGENTS.md) says.

---

### The ansible-core deserialization bug, and the workaround

Two parts of this playbook bypass Ansible's normal module mechanism. They look like something to clean up, and they are a deliberate defence against an upstream bug.

#### The bug

`Module result deserialization failed: No start of json char found`, raised by the controller when it reads a module's result. It came with ansible-core 2.19 and its new `_internal/_json` lazy import system. The ansiballz zip, the wrapper a Python module runs from, is cleaned up or becomes unreadable before `_return_formatted()` lazily imports the JSON profile from it. The race fires most often on modules that run longer than five to seven minutes while `/tmp` is busy, with dpkg postinst writes and systemd-tmpfiles.

Affected versions: every ansible-core release from 2.19.0 on, on all three live branches. Rechecked on 2026-08-20: [pull request 86739](https://github.com/ansible/ansible/pull/86739) was still open against `devel`, created 2026-03-27 and last touched 2026-08-18, `merged_at` null. Nothing on `stable-2.19`, `stable-2.20` or `stable-2.21` mentions the fix in its changelog, so 2.19.12, 2.20.8 and 2.21.3, the newest release on each branch on 2026-08-10, all still carry it. An earlier version of this text named 2.19.9 and 2.20.5 as the end of the affected range, which was only the newest release at the time of writing and never a statement that anything later was fixed. The last release before the bug is 2.18.x, which is below this project's floor for other reasons.

Upstream tracking: issue [86738](https://github.com/ansible/ansible/issues/86738), closed as a duplicate on 2026-03-31 and therefore no longer a place to watch, and issue [86562](https://github.com/ansible/ansible/issues/86562), still open. The pull request above is the one to watch.

#### The versions this repository accepts

ansible-core cannot be pinned to one exact version across the places it arrives from, because four package managers each publish exactly one and they do not agree: Debian trixie carries 2.19.4, Ubuntu 26.04 carries 2.20.1, Fedora 44 carries 2.20.7 and Arch carries 2.21.3. What is pinned is the range from 2.19.0 up to but not including 2.22.0, in two places that enforce it. [../setup.sh](../setup.sh) reads the version behind `ansible-playbook` and refuses a control node outside `ANSIBLE_CORE_MIN_VERSION` to `ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE`, and each Linux `e2e/tier3/*.Dockerfile` asserts the same two bounds at build time, so a rolling distribution moving under the harness fails the image build in seconds instead of a scenario twenty-five minutes in. The gate container, [../../e2e/gate/Dockerfile](../../e2e/gate/Dockerfile), installs one exact version, `gate_ansible_core_version` in [../pinned_values/pinned_values.toml](../pinned_values/pinned_values.toml), and [../../e2e/gate/provision.sh](../../e2e/gate/provision.sh) refuses to build it when that version falls outside the range `setup.sh` declares. Widening either bound means running the e2e suite against the new branch first. No release inside the range escapes the bug, so the mitigations stay whatever version is in use.

#### The two mitigations

1. `ansible.builtin.raw` for every package install, in [tasks/install_role_packages.yaml](tasks/install_role_packages.yaml). `raw` bypasses the whole Python module subsystem, no ansiballz and no JSON round trip, so the bug cannot fire. Since 2026-10-15 every apt, dnf, pacman, flatpak, snap and Homebrew install in the playbook goes through that one file, one package per call, under the one retry rule every package manager follows. It was `raw` for apt and Flatpak only before, with a `command` per package on Fedora and Arch. It reports from `rc`, never from the result's `failed` key, which this repository forbids reading. The apt full upgrade in [roles/system_core/tasks/base_utils.yaml](roles/system_core/tasks/base_utils.yaml) is `raw` for the same reason.
2. Ansible's temporary directories out of `/tmp`, in [ansible.cfg](ansible.cfg): `local_tmp` and `remote_tmp` point at `~/.ansible/tmp` and `fact_caching_connection` at `~/.ansible/facts-cache`. The ansiballz zip lives in `local_tmp`, so moving it away from `/tmp` removes the contention with dpkg and systemd-tmpfiles. It works on a live USB too, because Ubuntu Live's home directory is writable.

#### When it can be reverted

Once every branch this project accepts, today `stable-2.19`, `stable-2.20` and `stable-2.21`, has a point release that contains the fix from pull request 86739:

1. The `raw` install tasks in [tasks/install_role_packages.yaml](tasks/install_role_packages.yaml) and the apt full upgrade can go back to native modules in one change, still one package per call and still reporting from `rc`. Reverting must not bring back a batch: [../../e2e/tier1/batched_managers.sh](../../e2e/tier1/batched_managers.sh) fails on any manager that hands its whole set to one call.
2. `apt_raw_env` and `apt_raw_flags` in [group_vars/linux.yaml](group_vars/linux.yaml) can go.
3. The `~/.ansible` paths in [ansible.cfg](ansible.cfg) can stay, since they are a better default anyway, or go back to `/tmp`.

#### The recurring check

Every time the playbook is touched, and before recommending a change to the `raw` callsites or claiming the workaround is still needed, check upstream:

1. Find the ansible-core version the target hosts will use. The gate container runs exactly `gate_ansible_core_version` from [../pinned_values/pinned_values.toml](../pinned_values/pinned_values.toml), each tier 3 image runs whatever its distribution ships, and the accepted range is the one [../setup.sh](../setup.sh) enforces.
2. Check whether pull request 86739 is merged:

   ```bash
   gh pr view 86739 --repo ansible/ansible
   ```

3. If it is merged, find the first release tag on each accepted branch that contains it, on the [ansible-core releases page](https://github.com/ansible/ansible/releases).
4. If every accepted branch has such a release, schedule the revert above and update this section.
5. If it is still open, leave the workaround in place and note the upstream status in the commit message of any related change.

---

### Running the playbook

The wizard, [../setup.sh](../setup.sh), is the normal route and is described in [../README_SETUP.md](../README_SETUP.md). By hand, from `setup/ansible/`, install the collections once:

```bash
ansible-galaxy collection install -r requirements.yaml
```

A standard run:

```bash
ansible-playbook site.yaml -i localhost, -c local -K
```

A live USB run, with the live profile:

```bash
ansible-playbook site.yaml -i localhost, -c local -e "@profiles/linux_live.yaml" -K
```

`-K` asks for the sudo password. These commands change the machine they run on. An agent never runs them, and never runs `--syntax-check` either, because [../../e2e/tier1/ansible_static.sh](../../e2e/tier1/ansible_static.sh) runs the syntax check inside the gate container.

#### From a Windows machine

Ansible does not run natively on Windows, and the playbook uses POSIX shell conditionals and paths, so every Ansible command from a Windows host goes through WSL, for example `wsl -d Ubuntu bash -c "..."`, which also avoids Git Bash rewriting the paths. Never run `ansible-playbook` in PowerShell or Git Bash, and never try [../setup.sh](../setup.sh) there, because it is a Linux and macOS script. WSL's `/etc/os-release` is not a real Linux install, so it proves nothing about OS detection. And WSL is the owner's computer too, so nothing test-like runs there either.
