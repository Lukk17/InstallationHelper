# Regression ledger

Current as of 2026-08-14, repository HEAD adeaebf15b259b19c059a8a645280a6108dd85f0.

This is the list of defects the Ansible playbook and its wizard scripts have actually suffered, mined from the project's git history and from a container audit run the same day this page was written. Every entry states the cause, what it broke, and where the fix lives, or says plainly that it is still open. The point is prevention. Read the checklist below before touching anything under [setup/](../setup/), then use the grouped entries as a reference for the failure mode you are about to repeat.

The older, pre-Ansible bash-script era of this repository (2022 to early 2024, the plain `ubuntu/*.sh` and `windows/installer.ps1` scripts) is excluded. Those commits carry no message body explaining cause and effect, and the files they touched no longer exist, so nothing in that history can be verified against current code.

---

### Checklist before calling playbook work done

1. If you touched anything that names a Linux group, a package name, or a service name, check whether that name is the same string on Debian, Fedora and Arch. If it is not, the mapping belongs in the per-distribution `vars/{OS}.yaml` dictionary, never hardcoded in a shared task file. This is the exact mistake in the Arch OpenRazer device group entry below.
2. Do not assume a package exists in a distribution's official repository just because it exists in Debian's. Check the actual repository for every OS family the toggle claims to support. This is the mistake behind the Arch OpenRazer kernel module entry, the Arch Arduino removal, and the toggle plumbing entries for `install_putty` and `install_gradle`.
3. Never let `failed_when` or a block's `rescue` turn a real failure into a passing play. If you write a `failed_when` with more than one condition, work out by hand whether Ansible ANDs or ORs them, then write a test that proves it. If a `rescue` block exists, make it name the task that failed, not just print a generic warning. See the pacman batch entry and the install-block rescue entry.
4. A toggle in `group_vars/all.yaml` or `group_vars/linux.yaml` is not implemented until you can point at the line in a `vars/{OS}.yaml` file, or a task file, that consumes it on every OS the toggle claims to support. A code comment that says another role handles it is not verification, run it and watch the software actually appear. See the toggle plumbing entries and the dead-toggle cleanup entry.
5. If the same parsing or matching logic exists in more than one place, for example a bash wizard and a PowerShell wizard reading the same YAML, test both independently with the same fixture line. They will drift the moment one gets fixed and the other does not. This is exactly what happened in the wizard toggle parse desync entry.
6. An install that completes with exit code zero but leaves the feature non-functional is still a bug. A daemon that starts and immediately dies because its kernel module never built is not a success just because Ansible reported `ok`. See the Arch OpenRazer kernel module entry.
7. Any shell-out that could hit an interactive prompt needs its stdin closed and a real timeout, not a guessed one. See the FVM interactive-picker entry, which stalled 8 hours before anyone noticed.
8. Do not wrap a resolution or install step in a spinner or a generic heartbeat without also checking that the wrapped command's own error output still reaches the terminal. A spinner that swallows the one line saying "version not found" costs hours. See the SDKMAN and Ansible Galaxy entries under package drift and silent failure.
9. Anything that writes to shared on-disk state (a shared config file, a shared candidate registry, a shared cache) from a loop needs serialization, not just `async` for throughput. See the SDKMAN concurrency entry.

A harness under [e2e/](../e2e/) mechanises part of this checklist. Items 4 and 5 are fully covered by its tier 1 checks, which run in seconds and are proven to fail against the code from before each fix. Item 2 is covered for Arch, the Arch User Repository, Flathub, Homebrew, Chocolatey and winget by tier 2, and explicitly not covered for apt and dnf because their package names come from repositories the playbook adds while it runs. Items 1 and 6 are covered by tier 3, which runs the real playbook in a container, and today that means Arch only. Debian and Fedora containers are the obvious next step and do not exist yet, so for those two families the checklist is still something a person has to do by hand. Items 3, 7, 8 and 9 are not mechanised at all and remain review discipline.

[AGENTS.md](../AGENTS.md) carries the mandatory recurring check for the upstream ansible-core deserialization bug referenced at the bottom of this ledger, and that file is the authoritative copy, this ledger only summarises it.

---

### Found by the container harness on 2026-08-14 and 2026-08-15

Fourteen defects found by running the playbook in containers or by resolving its package names against real repositories, rather than by reading code. Listed together because they share an origin and because the list is the argument for the harness existing. All are fixed.

Six of the fourteen share one shape: something did not happen and the run still reported success. Four more share another: a task assumed a live desktop session that does not exist before a first login, over SSH, on a headless machine or in a container. Neither pattern is visible in a diff.

| Defect | What it did | Where the fix is |
|---|---|---|
| flatpak was never installed on Arch | The Flathub remote-add runs on every Linux, but flatpak was installed only for Debian and RedHat, so on Arch it shelled out to a missing binary. With no rescue on that role the whole run died fifteen minutes in with nothing installed. | [base_utils.yaml](../setup/ansible/roles/system_core/tasks/base_utils.yaml) |
| The OpenRazer device group was Debian's answer everywhere | Arch has no plugdev group and patches OpenRazer to use one called openrazer, so every Arch run failed with "Group plugdev does not exist". | [custom_installs.yaml](../setup/ansible/roles/software_installer/tasks/custom_installs.yaml), group name now in os_dict |
| No kernel headers on Arch for the DKMS build | Fedora installed kernel-devel and kernel-headers, Arch installed nothing, so the OpenRazer driver never built and the daemon exited while everything reported success. | [arch_prereqs.yaml](../setup/ansible/roles/software_installer/tasks/arch_prereqs.yaml) |
| Nerd Fonts downloaded into a directory that did not exist | get_url does not create parents, and /usr/share/fonts is absent on a Linux install with no font package or desktop, which is a minimal Arch install. setup_zsh defaults true and was hidden from the wizard, so the user could not even opt out. | [fonts_theme.yaml](../setup/ansible/roles/shell_zsh/tasks/fonts_theme.yaml) |
| plasma-framework5 does not exist any more | It was the Plasma 5 name. The Konsave build-dependency task failed on it and took the whole KDE configuration down. Plasma 6 ships the same library as libplasma. | [configure_kde.yaml](../setup/ansible/roles/kde_plasma_setup/tasks/configure_kde.yaml) |
| An AUR build that ran out of time was reported as a success | async_status marks a real failure with finished 1 and failed true, but a job still building when the retries expire returns finished 0 with no failed key. The collector required `failed` to be defined, so timeouts fell through and the play exited zero with the package absent. Observed with google-chrome. | [dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml) |
| Setting the KDE wallpaper assumed Plasma was already running | It talks to plasmashell over the session bus, which needs a live Plasma and a session. None of that exists before a first login, over SSH, on a headless box or in a container, and the task had no tolerance for it. | [configure_kde.yaml](../setup/ansible/roles/kde_plasma_setup/tasks/configure_kde.yaml) |
| Chocolatey always tried to elevate | Start-Process -Verb RunAs fails outright with no interactive desktop to prompt on, and is pointless when already administrator, which is the normal case in a container and in CI. | [WindowsSoftware.ps1](../setup/windows/WindowsSoftware.ps1) |
| iptables-nft no longer exists on Arch | Arch consolidated: core/iptables IS the nftables build now and the old behaviour moved to iptables-legacy. The Docker install task named a package that cannot resolve, which failed the task and took the Docker install with it. That line was itself an earlier Arch fix, so the fix had rotted. | [virtualization_config/tasks/main.yaml](../setup/ansible/roles/virtualization_config/tasks/main.yaml) |
| GNOME Terminal configuration assumed a session bus | gsettings writes through dconf, which needs D-Bus. The Konsole equivalent immediately below already had failed_when false, so the KDE path survived a missing session and the GNOME path failed the whole run over a terminal preference. | [terminal_config.yaml](../setup/ansible/roles/shell_zsh/tasks/terminal_config.yaml) |
| Enabling GDM failed when SDDM already owned the machine | A machine has one display manager and systemd models that with a single display-manager.service symlink, so enabling a second fails. Happens whenever KDE and GNOME are both on, which the wizard cannot produce but group_vars can, and the all-software scenario does. | [gnome_setup/tasks/install_gnome.yaml](../setup/ansible/roles/gnome_setup/tasks/install_gnome.yaml) |
| A missing AUR package was reported as a successful run | Two causes stacked. The wait budget was a fixed 20 minutes, and aur_allow_failures defaults true so the task that would have failed the run never fired and nothing else recorded the miss. Tolerating a failure and pretending it did not happen are different things, and this did both. | [dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml), [defaults/main.yml](../setup/ansible/roles/software_installer/defaults/main.yml) |
| Four package names gone from their own distributions | libkdecorations2-dev absent from Debian and Ubuntu alike, libncursesw5-dev replaced by libncurses-dev on both, zlib-devel replaced by zlib-ng-compat-devel on Fedora 44, and Fedora has no package called systemd-boot at all, it ships as systemd-boot-unsigned. Each verified absent and each replacement verified present inside the pinned images. | [configure_kde.yaml](../setup/ansible/roles/kde_plasma_setup/tasks/configure_kde.yaml), [pyenv_unix.yaml](../setup/ansible/roles/sdk_manager/tasks/pyenv_unix.yaml), [systemd_boot/tasks/fedora.yaml](../setup/ansible/roles/systemd_boot/tasks/fedora.yaml) |

Four of those eight are the same failure shape: something did not happen and the run still reported success. That shape is the reason item 3 of the checklist exists.

---

### Open findings, not yet fixed

Two of the four originally recorded here are now closed: the desktop environment roles' Debian branch has been split by `ansible_distribution` with every package name checked in both a Debian and an Ubuntu container, and the thirteen retry-less network operations in the no-rescue bootstrap path now retry. What remains:

#### The entire Windows path is unreachable

Both wizards invoke the playbook as `ansible-playbook site.yaml -i localhost, -c local` from inside WSL. [setup/setup.ps1](../setup/setup.ps1) does it at its `Invoke-AnsiblePlaybook` function and hands the command to `wsl bash -c`. So the target is the WSL distribution, and `ansible_os_family` reports Debian, which was verified by running the same command the wizard runs and printing the fact.

Consequence: every task gated on `os_family == 'Windows'` never executes, the `windows_core` role never runs, [setup/ansible/vars/Windows.yaml](../setup/ansible/vars/Windows.yaml) is never loaded as `os_dict` because the pre-task loads `vars/{{ os_family }}.yaml`, and all 77 winget plus 6 Chocolatey mappings are dead. What a Windows user actually gets is the Debian software set installed into their WSL instance.

This is architectural rather than a small bug. Making Ansible do it would need the playbook to target Windows as a host over WinRM or SSH, with an inventory that says so, and there is no `ansible_connection`, `ansible_host` or WinRM configuration anywhere in the repository.

Partly addressed, and the part that is addressed does not go through Ansible at all. The software catalogue now installs natively through [setup/windows/WindowsSoftware.ps1](../setup/windows/WindowsSoftware.ps1), which reads the same YAML the playbook reads so the toggles and mappings stay one source of truth and only the executor differs. [setup.ps1](../setup/setup.ps1) runs that first and then runs the playbook inside WSL, labelled as configuring the Linux environment rather than pretending to configure Windows. So the 83 mappings are live again, including any added on the assumption that they ran.

What is still true: every task gated on `os_family == 'Windows'` in the playbook remains dead, and `vars/Windows.yaml` is still never loaded as `os_dict`. It is read by the PowerShell installer instead. Nothing new should be added to the Ansible Windows roles expecting it to run.

#### Seventeen Windows toggles have no native install path yet

A consequence of the entry above rather than a separate defect, but it needs naming so it is not mistaken for done. The 83 package mappings now install natively, and the remaining seventeen enabled toggles come from Ansible roles that still cannot run on Windows: `sdk_manager` for the SDKs, `ai_tools` for the CLI tools, `jetbrains_toolbox`, `windows_install` for Gridcoin and Razer Cortex, and `windows_core` for the optional features, the WSL install and the wallpaper. Twelve Windows-specific task files exist for these and none of them execute.

The wizard prints them by name at the end of a run, so a user is told rather than left guessing, but they are not installed.

#### A correction to an earlier entry in this file

An earlier version of this ledger recorded the Flathub failure as transient network contention, and it was wrong. That conclusion came from running the command three times in a clean container and seeing it succeed, but flatpak had been installed by hand first in that test, so it proved the wrong thing. The real cause was that flatpak was never installed on Arch at all, which is in the table above. Retries were added to thirteen network operations in the no-rescue bootstrap path anyway, and that change stands on its own merits, but retrying was never the fix for this.

The lesson is worth more than the fix: a reproduction that does not start from the same state as the failure proves nothing. Recorded because a wrong cause left in a ledger is worse than no entry.

#### import_hibernate_task referenced a file that does not exist

`roles/windows_core/tasks/wsl_setup.yaml` runs `schtasks` against `{{ playbook_dir }}\..\tasks\Hibernate@2AM.xml`, and there is no `setup/tasks/` directory anywhere in this repository. The toggle defaulted to true, so it would have failed on every Windows run had the Windows path been reachable at all. Now set false with the reason recorded beside it, which closes the immediate hazard, but the scheduled-task definition is still missing.

---

### Cross-distro assumptions

#### Arch OpenRazer device group does not exist

Status: open, found by container audit 2026-08-14, not yet fixed.

Cause: [setup/ansible/roles/software_installer/tasks/custom_installs.yaml](../setup/ansible/roles/software_installer/tasks/custom_installs.yaml) line 315 hardcodes `groups: plugdev` on the task that adds the non-root user to the OpenRazer device group. Arch Linux has no `plugdev` group at all, before or after installing OpenRazer. Arch carries a downstream patch, `0001-Use-openrazer-group.patch`, that switches upstream OpenRazer from `plugdev` to a group named `openrazer`, created by the package's own `sysusers.conf` at gid 969.

Effect: hard task failure on Arch, reproduced with real Ansible in an `archlinux:latest` container: `fatal: [localhost]: FAILED! => {"changed": false, "msg": "Group plugdev does not exist"}`. `usermod -a -G plugdev` exits 6. Because the task sits inside a block with a rescue, this surfaced only as a generic warning and silently skipped the remaining tasks in the block, the same mechanism documented in the install-block rescue entry below.

Cross-check: Debian trixie has `plugdev` at gid 46 and Fedora 43's openSUSE Build Service package creates `plugdev` at gid 996, both verified in containers, so only Arch is wrong. Introduced in commit `dabad985651e44f4063989fa47475bd3d3776089` (2026-08-09, "feat(software): add Razer Synapse and OpenRazer, restore Razer Cortex"). The group name is a per-distribution fact and belongs in the OS dictionary, not hardcoded in a task.

#### Arch OpenRazer kernel module never builds

Status: open, found by container audit 2026-08-14, not yet fixed.

Cause: [setup/ansible/roles/software_installer/tasks/fedora_repos.yaml](../setup/ansible/roles/software_installer/tasks/fedora_repos.yaml) lines 129 to 131 install `kernel-devel` and `kernel-headers` before the OpenRazer DKMS build. Arch installs nothing equivalent, and Arch's own `dkms` package lists `linux-headers` only as an optional dependency, never pulled automatically.

Effect: `openrazer-daemon` installs, the kernel module never builds, and the daemon exits on startup. Container evidence: `(5/5) Install DKMS modules` followed by `error: command failed to execute correctly`. This is not a playbook failure, which is why it went unnoticed, the play recap still reports success. Arch's `dkms` alpm hook ends in `return 0`, so a missing-headers build failure is reported as text on the console and never as a process exit code the playbook could catch. An install that cannot function is still a bug even when the playbook exits zero.

#### Arch libvirt and Docker fight over the iptables backend

Status: fixed, commit `890de1487721ac7643baae4a4277d64da1d86ab8` (2026-05-20), with a same-day follow-up fix.

Cause: on stock Arch, `libvirtd` starts with the legacy `iptables` firewall backend and writes its NAT rules through it. Installing Docker afterward pulls in `iptables-nft`, so the system's iptables provider becomes the nftables shim while the kernel namespace still holds libvirt's legacy rules. Docker's own NAT chain creation then hits a kernel state that is neither purely legacy nor purely nftables.

Effect: `iptables v1.8.13 (nf_tables): Could not fetch rule set generation id: Invalid argument`, and Docker fails to register its bridge driver. Fix: write `firewall_backend = "nftables"` to `/etc/libvirt/network.conf` and restart `libvirtd` before starting Docker, in [setup/ansible/roles/virtualization_config/tasks/main.yaml](../setup/ansible/roles/virtualization_config/tasks/main.yaml), so both daemons share one backend.

The same commit also added an explicit `community.general.modprobe` step for `nf_tables`, `nft_compat` and `br_netfilter` as a belt-and-braces measure. That addition broke the very next Arch run in commit `8aa5e2187e3f379d48369252ca6a20f1cb9f6b30` (2026-05-20), because [setup/setup.sh](../setup/setup.sh) runs `pacman -Syu` before Ansible starts, which can bump the kernel package mid-playbook. Pacman deletes the old kernel's `/lib/modules/<ver>/` once the new one lands, but the running kernel is still the old one until reboot, so `modprobe` could not even read `modules.builtin` and every module-load attempt errored out, and the rescue swallowed that error and skipped the Docker start task entirely, actively preventing the fix it was meant to protect. The modprobe step was also unnecessary, since `nf_tables`, `nft_compat` and `br_netfilter` are built into stock Arch kernels, not loadable modules, and Docker's own daemon-load already tolerates the module being absent. It was removed. Two lessons stack here, a fix that changes kernel state mid-run needs to account for a kernel upgrade that already happened in the same run, and a defensive-sounding extra step is still a regression if a rescue block can turn its failure into a silent skip of the real fix.

#### systemd-boot pointed at a kernel `apt autoremove` had already deleted

Status: fixed, commit `28b933e40e67e11d1cc4928ad3ca15fdd76d8e3a` (2026-05-20).

Cause: [setup/ansible/roles/systemd_boot/tasks/debian.yaml](../setup/ansible/roles/systemd_boot/tasks/debian.yaml) and the matching Fedora task captured the running kernel with `uname -r`, then referenced `/boot/vmlinuz-<kernel>` or `/lib/modules/<kernel>/vmlinuz` later as the kernel-install input. [setup/setup.sh](../setup/setup.sh) runs a full system upgrade before Ansible starts, which can install a new kernel package, and `apt autoremove` then strips the old kernel image from `/boot` once a newer one is present, while the running kernel stays the old version until reboot.

Effect: on Debian the referenced `/boot/vmlinuz-<old>` file could already be gone, failing kernel-install outright, and on Fedora the equivalent path could be missing if `installonly_limit = 1` is set. Even when the file was still present, pointing the boot loader at the outgoing kernel was the wrong target regardless, since the next boot loads whatever the package manager made current. Fix: probe the newest kernel actually on disk with `ls ... | sort -V | tail -1` instead of trusting the running kernel, at line 36 of the Debian task, with a `failed_when` on empty output so a genuinely empty `/boot` hard-fails instead of writing a broken loader entry. Arch's own task in [setup/ansible/roles/systemd_boot/tasks/arch.yaml](../setup/ansible/roles/systemd_boot/tasks/arch.yaml) was never affected, it uses static symlinks the kernel package updates atomically. This toggle defaults to false, so the bug was dormant rather than triggered, caught by audit rather than by a failed run.

#### Package and repository facts that only held for one distribution

Status: fixed, commits `aac857986b52a77f1dc19491c804592afb31d9ae` (2026-05-21) and `6e8913a7580940a918530c61ed4f9f5b3d5bb782` (2026-05-19).

A single cross-distro test pass on Debian, Ubuntu, Fedora and Arch (`aac857986b52a77f1dc19491c804592afb31d9ae`) turned up five distinct per-distro assumptions in one sitting: `ansible.builtin.command: command -v zsh` in [setup/ansible/roles/shell_zsh/tasks/install_zsh.yaml](../setup/ansible/roles/shell_zsh/tasks/install_zsh.yaml) failed on every distro because `command` is a shell builtin, not a binary Ansible's `command` module can execve, and needed to go back to `ansible.builtin.shell`. Ubuntu minimal images have no `git`, which pyenv's own bootstrap script hard-requires, so [setup/ansible/roles/system_core/tasks/base_utils.yaml](../setup/ansible/roles/system_core/tasks/base_utils.yaml) now installs it explicitly on all three Linux families even though Arch and Fedora usually pull it transitively. Arch's `snap install core` was running before `snapd.socket` was enabled in [setup/ansible/roles/arch_core/tasks/main.yaml](../setup/ansible/roles/arch_core/tasks/main.yaml), failing with "cannot communicate with server", fixed by reordering the tasks and adding a settle pause.

A separate version and URL audit (`6e8913a7580940a918530c61ed4f9f5b3d5bb782`) found that Arch's official pacman repository had dropped the `arduino` package entirely, requiring a switch to the Flathub `cc.arduino.IDE2` entry that Debian already used, and that the FreeCAD Flathub application ID had been renamed upstream and needed correcting in the Debian, Fedora and Arch dictionaries independently. Neither of these package facts generalised from one distribution to the others, and both were only caught by checking the live upstream source rather than trusting what had worked before.

#### Tailscale's apt repository URL assumed the distribution name was already the codename it needed

Status: fixed, commit `e6eff3e0cac5d96a56cab4e0d58c4ff777cd2551` (2026-08-13).

Cause: the Tailscale apt repository task built its URL from the raw `ansible_facts['distribution']` string, unlike the Docker CE task in the same file, [setup/ansible/roles/software_installer/tasks/debian_repos.yaml](../setup/ansible/roles/software_installer/tasks/debian_repos.yaml), which already normalised any Debian derivative down to `ubuntu` or `debian` before building its URL, since upstream only publishes those two paths.

Effect: a Debian derivative such as Linux Mint or Pop!_OS produced a 404 instead of degrading, because Tailscale's package host has no `linuxmint` or `pop` path. Fixed by applying the same normalisation the Docker task already used, now visible at lines 339 and 350 of the same file. The same commit also caught that the live USB profile never disabled Tailscale, so an ephemeral run added a repository and enabled a daemon on a session that could never join a tailnet, and that the manual install docs under [docs/manual/](manual/) had no Tailscale entry at all on any of the five operating systems despite declaring itself grouped exactly like the main software catalogue.

---

### Silent failure and error swallowing

#### Pacman batch failure marked as success

Status: open, found by audit, not triggered in a real run yet.

Cause: [setup/ansible/roles/software_installer/tasks/dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml) lines 207 to 210 give `failed_when` a two-item list, which Ansible combines with AND, not OR: `pacman_result.failed` and `'could not find' not in msg`. Any could-not-find error therefore marks the task `ok`.

Effect: one wrong package name anywhere in [setup/ansible/vars/Archlinux.yaml](../setup/ansible/vars/Archlinux.yaml) silently drops every single pacman package from the run while the playbook reports success end to end. This is latent rather than triggered, caught by reading the condition by hand rather than by a failing run, which is exactly why item 3 on the checklist above exists.

#### Install block rescue hides which task failed

Status: open, this is the mechanism that let the Arch OpenRazer device group entry above hide.

Cause: [setup/ansible/roles/software_installer/tasks/dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml) lines 459 to 462 wrap the entire install block, apt, dnf, pacman, snap, Windows and custom installs together, in a single `rescue` that emits one anonymous line.

Effect: any failure inside the block prints `[WARNING] Some packages failed to install`, skips every remaining task in the block regardless of which package manager or OS it belonged to, and the play recap stays green. Nothing in the output says which task, which package, or which OS branch actually failed.

#### `playbook_succeeded` reported true regardless of what the rescue actually caught

Status: fixed, commit `dd07664d28c4ba1dcf6c6763b3ce4dc44637a6b9` (2026-05-19).

Cause: the fact that gates the post-run cleanup tasks was set with an unconditional `set_fact`, so it read true even when a role's rescue block had just caught a real failure. Effect: cleanup tasks such as removing the temporary sudoers grant ran the same way whether the run had actually succeeded or been silently rescued. Fixed by tracking `any_role_failed` from the rescue blocks themselves in [setup/ansible/site.yaml](../setup/ansible/site.yaml), so cleanup correctly distinguishes a rescued failure from a clean run.

#### A round of `ignore_errors` and always-true `changed_when` across a dozen roles

Status: fixed, commits `bf23f193898628070f337d7eccf9edd7e67bdb77` (2026-05-21) and an earlier pass in `20c6f615a354f252f2ca8be82da5eba92be076e1` (2026-04-14).

An audit found `ignore_errors: yes` scattered across [setup/ansible/roles/virtualization_config/tasks/main.yaml](../setup/ansible/roles/virtualization_config/tasks/main.yaml), the GRUB removal task, and a Flathub remote-add step, each one hiding whatever real failure the task might hit behind a guaranteed pass. The worst instance was in [setup/ansible/roles/shell_zsh/tasks/install_zsh.yaml](../setup/ansible/roles/shell_zsh/tasks/install_zsh.yaml): the `command -v zsh` probe had no guard against empty stdout, so a silent install failure could set a user's login shell to an empty string, an account lockout vector, not just a cosmetic bug. Three Debian apt tasks and the apt and flatpak batch installs also carried an always-true `changed_when`, meaning the play recap reported `changed` on every single run whether anything actually changed or not, masking the signal an operator would use to notice an install that silently did nothing. All replaced with real `failed_when` and `changed_when` conditions that parse the actual command output.

#### A spinner hid an Ansible Galaxy collection resolution failure for hours

Status: fixed, commit `6e8913a7580940a918530c61ed4f9f5b3d5bb782` (2026-05-19), with a companion fix in [setup/setup.sh](../setup/setup.sh).

Cause: [setup/ansible/requirements.yaml](../setup/ansible/requirements.yaml) pinned exact collection versions that had been invented rather than checked against Ansible Galaxy, for example `community.general:10.5.0` and `chocolatey.chocolatey:1.5.3`, neither of which exists as a real release. `ansible-galaxy collection install` failed to resolve them, but the install script wrapped that command in a `gum spin` loading animation that swallowed the command's own stderr.

Effect: the operator saw a spinner running for however long they waited, with no indication that the underlying command had already failed. Fixed two ways, the collection pins went back to bounded ranges that Galaxy can actually resolve, and `install_collections()` in [setup/setup.sh](../setup/setup.sh) stopped wrapping the call in `gum spin` so resolution errors stream to the console immediately.

#### MCP configuration silently loaded zero servers when one variable was unset

Status: fixed, commit `147759b72d37981c927e92e3da70275ab8884136` (2026-05-21).

Cause: [.mcp.json](../.mcp.json) referenced `CONTEXT7_API_KEY`, a Grafana token, and a SonarQube token with no default value. Claude Code fails to parse the entire file, not just the one server block, when any referenced environment variable is unset, so a project that had not set all three lost every configured MCP server with no error surfaced anywhere. Fixed by adding an empty-string fallback, `${CONTEXT7_API_KEY:-}`, still visible at line 8 of the current file. [opencode.json](../opencode.json) had the equivalent problem for a different reason, its `{env:VAR}` syntax has no default-value fallback at all, so unset variables produced empty URLs instead of a parse failure, fixed by hardcoding localhost defaults instead. [docs/MCP_SETUP.md](MCP_SETUP.md) documents the asymmetry between the two tools' handling of a missing variable.

---

### Wizard and toggle plumbing

#### Wizard toggle parse desync

Status: fixed in this change, in `setup/setup.sh`, function `read_boolean_toggles`.

Cause: `read_boolean_toggles` in [setup/setup.sh](../setup/setup.sh), lines 344 to 348, matches toggle lines with `grep -E '^[a-z_]+: (true|false)'`, which happily matches a line that carries a trailing `# comment`, then converts state with `sed 's/: true$/ ON/;s/: false$/ OFF/'`, which is anchored to the end of the line and therefore never fires on a commented line. `preload_toggles` then splits the result with `key="${entry%% *}"` and `val="${entry##* }"`, so the key kept its trailing colon and the state became the last word of the comment instead of `ON` or `OFF`.

Effect: 11 toggles on Linux and 4 more on macOS rendered as unchecked in the customise checklist with a stray colon in the label, and could not be controlled in either direction. The wizard emitted a line like `install_tailscale:=false`, a variable name that does not match the real toggle, which Ansible accepts silently and leaves the real value untouched. The profile picker's package count was also 11 too low. Affected toggles: `install_chatgpt`, `install_synapse`, `install_tailscale`, `install_stable_diffusion`, `install_hardinfo`, `install_lm_sensors`, `install_greenenvy`, `install_baobab`, `install_openrazer`, `install_polychromatic`, `install_gputest`, plus `install_stats`, `install_grandperspective`, `install_lulu`, and `install_balena_etcher` on macOS.

[setup/setup.ps1](../setup/setup.ps1) was never affected, its equivalent regex at line 246 is `^([a-z_]+): (true|false)` with no end anchor, so it matches the value regardless of a trailing comment. That asymmetry is itself the lesson behind item 5 on the checklist above, two implementations of the same parse drifted apart, and only one of them was ever tested against a commented toggle line.

#### Toggles enabled with no mapping and no task

Status: open, found by audit 2026-08-14.

`install_putty: true` in [setup/ansible/group_vars/linux.yaml](../setup/ansible/group_vars/linux.yaml) line 37 has no mapping in [setup/ansible/vars/Archlinux.yaml](../setup/ansible/vars/Archlinux.yaml) or [setup/ansible/vars/RedHat.yaml](../setup/ansible/vars/RedHat.yaml), even though `putty` is present in Arch's `extra` repository and in Fedora's repositories, both verified directly.

`install_gradle: true` in [setup/ansible/group_vars/all.yaml](../setup/ansible/group_vars/all.yaml) line 17 has no mapping on Debian or Fedora. Both [setup/ansible/vars/Debian.yaml](../setup/ansible/vars/Debian.yaml) and [setup/ansible/vars/RedHat.yaml](../setup/ansible/vars/RedHat.yaml) carry a one-line comment claiming SDKMAN handles it, but [setup/ansible/roles/sdk_manager/tasks/sdkman_unix.yaml](../setup/ansible/roles/sdk_manager/tasks/sdkman_unix.yaml) only ever installs Java. Gradle was never installed on either OS and the comment was false. Arch, by contrast, does map it correctly to `pacman` at line 11 of its dictionary.

Effect: the user enables the toggle, the run reports success, the software is absent, on the two operating systems where the comment lied. The lesson behind item 4 on the checklist above is that a comment claiming another role handles something is not implementation, only a task file that actually runs is.

#### A selective-update script force-added agent paths a project never had

Status: fixed, commit `f056d3a76778aca06e411ec84865e4467fe76dfc` (2026-06-25).

Cause: the update commands documented for consumer projects looped over every known agent integration path, `.github/agents`, `.opencode/plugin`, `.kilocode/rules`, assuming all of them existed. A project that had imported this repository's agent tooling before one of those tools existed had none of that path on disk. Effect: the skills loop, subagent loop, and adapter refresh either errored outright or force-added paths that path never asked for. Fixed by skipping any agent path not present locally, in both the bash and PowerShell variants of the update command, the same two-implementation risk called out in item 5 of the checklist above.

#### Toggles that had already been dead for a while

Status: fixed, part of commit `8b32a1e9d42a36385e2b8528f48a0ed08b3b29fa` (2026-05-21).

A cross-check of every toggle in `group_vars/all.yaml` and `group_vars/linux.yaml` against the per-OS install paths in `vars/{OS}.yaml` found four toggles with zero working install path on any operating system, `install_trello`, `install_exodus`, `install_intellij`, and `install_teams`, while still appearing ticked in the wizard checklist. `install_trello` defaulted to true but every OS dictionary had it commented out as unavailable, so the wizard ticked a box that could never do anything. This is the mirror image of the toggle-with-no-mapping entry above, here the toggle, its profile overrides, its version variables, and its documentation references were all purged together so the operator's checklist only shows software the playbook will actually install.

---

### Package naming and availability drift

#### Windows winget product IDs that stopped resolving

Status: fixed, commit `e8eef3894430cb72d2eaf1beb7336b5d07d12b63` (2026-06-01).

Google's Antigravity IDE rebrand moved the product from `Google.Antigravity` to `Google.AntigravityIDE`, leaving the old ID pointing at a different product entirely. `Ookla.Speedtest` did not exist in winget-pkgs at all, only `Ookla.Speedtest.CLI` did, so the install failed with "No package found". NVIDIA discontinued GeForce Experience in favour of the NVIDIA App, which has no winget or Chocolatey manifest, so the toggle was flipped to false rather than left pointing at a dead package. All of this lives in [setup/ansible/vars/Windows.yaml](../setup/ansible/vars/Windows.yaml).

#### Microsoft Store product IDs need an explicit source or they abort the whole batch

Status: fixed, commit `ae24205998893843b3e02d652964c69a2b3e7125` (2026-08-09).

Cause: five Store product IDs in [setup/ansible/vars/Windows.yaml](../setup/ansible/vars/Windows.yaml) carried no `source` field, so the winget task fell back to the default winget source, where a bare Store ID returns exit 20, "no package found". Because the winget loop runs inside the same install block described in the rescue entry above, the first failure dropped the whole block into the rescue handler and silently skipped every remaining package, including one added in the same round of commits. All six enabled toggles hit this. Verified directly on Windows 11: `winget show --exact --id <id> --source winget` fails for all six IDs while `--source msstore` succeeds for five of them. The sixth, Razer Cortex's `9PK9W5QV2PKX`, resolves on neither source and no Store search matches the name, so that mapping was removed entirely rather than left to abort the batch.

#### Two Ansible module names that never resolved at all

Status: fixed, commit `ddfe050d8bfb053d58e4e752a82da632ec2acdeb` (2026-06-02).

`community.windows.win_winget` does not exist in any installed collection, `community.windows` only ships `win_scoop`, and there is no such module in `ansible.windows` either. Confirmed with `ansible -m <fqcn>` returning "Cannot resolve to an action or module". [setup/ansible/roles/software_installer/tasks/windows_winget.yaml](../setup/ansible/roles/software_installer/tasks/windows_winget.yaml) now drives the winget CLI directly through `ansible.windows.win_shell`, resolving the real `winget.exe` path out of the DesktopAppInstaller package because the App Execution Alias is not on PATH in a non-interactive WinRM session, visible at lines 1 to 17 of the current file. `community.windows.win_chocolatey` had the same problem, the module actually lives in `chocolatey.chocolatey`, already a declared dependency, with no redirect in `community.windows` 2.x. The same commit also caught that the Windows FVM task had been installing a non-existent `Google.Flutter` winget package, rewritten to install FVM through Chocolatey instead.

---

### Concurrency and shared state

#### Parallel SDKMAN Java installs race on shared registry state

Status: fixed, commit `744bf443e41f02c2b6a63e7177bd19683aa2e760` (2026-05-19).

Cause: SDKMAN's `sdk install` writes to shared state without any locking, `~/.sdkman/etc/config`, the candidate metadata cache under `~/.sdkman/var/`, the active-version pointer, and its own installed-candidates registry. Running four `sdk install java <version>-tem` invocations concurrently, one per Temurin version this playbook installs, let those writes interleave.

Effect: a follow-up run failed at "Set default Java via SDKMAN" with "java 21.0.11-tem is not installed on your system", even though the parallel install task had just reported all four JDKs as installed. The on-disk extract under each candidate's own directory usually succeeded, but SDKMAN's own view of what was installed lost entries. Fixed by reverting to a serial `loop:` in [setup/ansible/roles/sdk_manager/tasks/sdkman_unix.yaml](../setup/ansible/roles/sdk_manager/tasks/sdkman_unix.yaml), the rationale is documented directly in the comment above the task at lines 17 to 22 of the current file. Pyenv stayed parallel deliberately, each pyenv install writes to its own isolated `~/.pyenv/versions/X.Y.Z/` directory with no shared state file, so the same race does not apply there. The wall-clock cost is roughly 10 minutes on a fresh box versus 5 minutes parallel, accepted as the price of a registry that stays coherent.

---

### Timeouts and interactive stalls

#### FVM's interactive picker stalled a run for 8 hours with no signal

Status: fixed, commits `cd733f381244eb2a19a214eee457007fa21e8439` and `2e11e3e050b4d71b27d815524a2cf04b37b82f74` (both 2026-05-20).

Cause: FVM 3.2 and later, `fvm global` with no arguments enters an interactive terminal picker when no global Flutter version is set yet. The read-probe task in `fvm_unix.yaml` ran that command with stdin left open, inheriting the Ansible controller's non-TTY pseudo-terminal, so the picker blocked waiting for a keystroke that could never arrive.

Effect: a real Ubuntu run hung for 8 hours on "Read current FVM global channel", with the heartbeat logger emitting "still working, log unchanged" every 5 minutes for 490 minutes before anyone noticed. Fixed first by closing stdin with `</dev/null` and adding a hard timeout, then cleaned up the same day once the numbers turned out sloppy, the actual work is a sub-second config-file write with no network involved, so a follow-up commit deleted the read-probe entirely, ran the set task unconditionally since FVM is idempotent on its own, and capped the whole thing at 10 seconds as a safety net rather than a real wait budget, visible at line 160 of [setup/ansible/roles/sdk_manager/tasks/fvm_unix.yaml](../setup/ansible/roles/sdk_manager/tasks/fvm_unix.yaml) today. Every other read-only shell-out in the SDK manager role, npm, pyenv, SDKMAN's own `sdk default`, was audited in the same commit and confirmed non-interactive, so this fix stayed scoped to FVM alone.

#### A synchronous long task blocked the controller with no signal it was even alive

Status: fixed, part of commit `8b32a1e9d42a36385e2b8528f48a0ed08b3b29fa` (2026-05-21).

A Flatpak batch install once hung silently for roughly an hour, the synchronous task blocked the whole controller and the progress logger had no way to emit anything because it only reacted to task-lifecycle events, not to activity inside a still-running task. Applied across every long-running task in the playbook after that, pyenv compiles, SDKMAN downloads, JetBrains IDE downloads, AUR builds, the `oh-my-zsh` bootstrap, and the FVM install itself, all now redirect stdin from `/dev/null`, run under `async` with `poll`, and carry `retries` for transient network blips, the pattern documented in [setup/ansible/callback_plugins/dual_logger.py](../setup/ansible/callback_plugins/dual_logger.py). The heartbeat now tails the relevant log file and emits a line whenever it actually changes, plus an idle ping after 5 minutes of silence, so a stuck task and a slow one no longer look identical on screen.

---

### Upstream tooling bugs

#### The ansible-core 2.19 and 2.20 result-deserialization race

Status: open upstream, mitigated in this repository, first introduced commit `dd07664d28c4ba1dcf6c6763b3ce4dc44637a6b9` (2026-05-19).

Long-running native Ansible modules occasionally fail with "Module result deserialization failed: No start of json char found" on ansible-core 2.19.0 through 2.19.9 and 2.20.0 through 2.20.5, a race between the module's cleanup of its ansiballz zip payload and the controller's lazy JSON import, worse under heavy `/tmp` activity from `dpkg` and `systemd-tmpfiles`. This repository mitigates it two ways, `ansible.builtin.raw` bypasses the Python module subsystem entirely for the three Debian callsites that reliably cross the duration threshold, and the Ansible temp directories were moved out of `/tmp` into `~/.ansible/`.

The fix belongs upstream in pull request #86739 against `ansible/ansible`, still unmerged as of the commits in this ledger. Full detail, the mandatory recurring check before touching or reverting the workaround, and the exact affected version ranges live in [AGENTS.md](../AGENTS.md), which is the authoritative copy of this entry, not this ledger. Do not revert the `raw` callsites or the `~/.ansible/` temp paths without running that check first.
