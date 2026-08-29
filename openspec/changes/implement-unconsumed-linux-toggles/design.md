## Context

See [proposal.md](proposal.md) for why. What follows is the research an implementer would otherwise have to go and do, and the technical decisions that come out of it. Every external fact below was established on 2026-08-29 by fetching the source named next to it, not from memory. Where a fact could not be established, this document says so in those words rather than guessing.

Three constraints shape everything here.

The playbook never hardcodes a per-distribution fact into a task. Package names, group names, paths and service names live in `setup/ansible/vars/<OS>.yaml` and are read through `os_dict`. The OpenRazer group was hardcoded to Debian's answer and failed every Arch run, which is the entry that made this a rule. See the "Cross-distro assumptions" section of [docs/regression_ledger.md](../../../docs/regression_ledger.md).

`site.yaml` imports the `systemd_boot` role with no block and no rescue, at [setup/ansible/site.yaml](../../../setup/ansible/site.yaml) line 88. A `fail:` inside that role aborts the entire play before a single package is installed. The existing role already reasons about this at length and chooses to report and flag rather than fail, using `set_fact: any_role_failed: true`, and both new bootloader tasks inherit that reasoning.

Nothing in a container can prove any of the three. Tier 1 can prove the toggle is consumed. Everything else is [e2e/manual_test_matrix.md](../../../e2e/manual_test_matrix.md).

## Goals / Non-Goals

**Goals:**

- Three implementations that can each be picked up alone, finished alone and verified alone.
- Every per-distribution value in `vars/<OS>.yaml`, nothing in a task.
- Idempotence, meaning a second application reports no change, because [e2e/tier3/scenarios/08-idempotency.yaml](../../../e2e/tier3/scenarios/08-idempotency.yaml) applies the defaults configuration twice and fails on any task reporting `changed` on the second pass without a reason in [e2e/tier3/idempotent_changes_allowed.txt](../../../e2e/tier3/idempotent_changes_allowed.txt).
- A machine that can still start after every one of the three.

**Non-Goals:**

- Offering `setup_grub` or `remove_distro_systemd_boot` on either wizard's checklist. They stay in `EXCLUDED_VARS` for the reason already written next to that list.
- Supporting BIOS or legacy boot. The existing `systemd_boot` role is UEFI-only and so is this.
- Secure Boot signing. Nothing in this repository signs anything, which the manual matrix already records at line 88.
- Changing any default. All three toggles stay `false`.
- Touching macOS or Windows. All three are Linux-only, declared in `group_vars/linux.yaml`, which is the only group vars file macOS and Windows never load.

## Decisions

### Task 1, Wayland on NVIDIA

#### Decision 1.1: The research, and what it changes about the obvious implementation

The plain reading of the toggle's label, "set the NVIDIA kernel modesetting parameter and remove the display manager rule that hides the Wayland session", was correct in 2023 and is largely obsolete now. Both halves have moved.

The kernel module parameter's default flipped upstream. Every NVIDIA driver README through the 590 branch says the same sentence, quoted from [https://download.nvidia.com/XFree86/Linux-x86_64/590.48.01/README/kms.html](https://download.nvidia.com/XFree86/Linux-x86_64/590.48.01/README/kms.html): "NVIDIA's DRM KMS support is still considered experimental. It is disabled by default, but can be enabled on suitable kernels with the 'modeset' kernel module parameter." The README for 595.58.03 and for 610.43.02 reads the other way round, quoted from [https://download.nvidia.com/XFree86/Linux-x86\_64/610.43.02/README/kms.html](https://download.nvidia.com/XFree86/Linux-x86_64/610.43.02/README/kms.html): "NVIDIA's DRM KMS support is enabled by default, but can be disabled with the 'modeset' kernel module parameter." 595.58.03 was released 2026-03-24 as the first stable build of the R595 branch, per [https://www.phoronix.com/news/NVIDIA-595.58.03](https://www.phoronix.com/news/NVIDIA-595.58.03). The current branches as of 2026-08-03 are 595.91.07 production and 610.57.04 new-feature.

A widely repeated claim that driver 545 or 560 made this the default is wrong. It is Arch's packaging being restated out of context, see decision 1.4.

The GDM rule is gone. The udev rule that ran `gdm-disable-wayland` on NVIDIA hardware was removed upstream in three steps, quoted from the commit messages on the now-deleted `data/61-gdm.rules.in` path at [https://api.github.com/repos/GNOME/gdm/commits?path=data/61-gdm.rules.in](https://api.github.com/repos/GNOME/gdm/commits?path=data/61-gdm.rules.in). On 2024-10-23: "udev: Remove rules for disabling Wayland if nvidia modesetting is disabled." On 2025-05-09, in GDM 49.alpha.0: "udev: Drop disable_wayland overrides." On 2025-07-06, in GDM 49.alpha.1: "The sole purpose of this set of udev rules was to conditionally disable Wayland." GDM 48, shipped with GNOME 48 in March 2025, still had it. GDM 49, shipped with GNOME 49 in September 2025, does not.

SDDM never had one. It lists whatever session desktop files exist in `/usr/share/wayland-sessions/` and lets the user pick. The `DisplayServer=` key under `[General]` in `/etc/sddm.conf.d/*.conf` controls only which display server the greeter itself runs on, not which sessions are offered. There is nothing to unblock.

The KDE environment variables are obsolete. The current KDE Community page at [https://community.kde.org/Plasma/Wayland/Nvidia](https://community.kde.org/Plasma/Wayland/Nvidia), last edited 2025-12-20, lists its whole prerequisites set as: an up-to-date Plasma, because explicit sync landed in 6.1, a driver at least 495.44 with XWayland usable from 555, the NVIDIA EGL library installed, and the modesetting driver. None of `GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`, `WLR_NO_HARDWARE_CURSORS` or `KWIN_DRM_USE_MODIFIERS` appears on it any more. `WLR_NO_HARDWARE_CURSORS` was never a KWin variable at all, it belongs to wlroots compositors such as Sway and Hyprland.

#### Decision 1.2: Do the work conditionally, from measurement, not unconditionally from a version table

Given the above, the implementation writes something on some machines and nothing on others, and which is which depends on the driver version and the display manager version in front of it. Writing a modprobe file on a machine whose driver already defaults it on is harmless but reports a change forever, which fails the idempotency scenario and lies to the user about what the run did.

So each half checks first.

For the module parameter, read `/sys/module/nvidia_drm/parameters/modeset` when the module is loaded, and fall back to the driver version from `modinfo nvidia` or `/proc/driver/nvidia/version` when it is not. Write the modprobe file only when the answer is not already `Y` and the driver branch is below 595.

For the display manager, look for the suppression rather than assuming it. `test -e /usr/lib/udev/rules.d/61-gdm.rules` and a `WaylandEnable=false` line in the distribution's GDM configuration file are both cheap. Act only when one is found. Rejected alternative: keying off the GDM version. Distributions carry their own patches on top of upstream, so the version is a weaker signal than the file's presence, and Ubuntu's own patch is the proof of that, see decision 1.4.

#### Decision 1.3: modprobe.d, not the kernel command line

`options nvidia_drm modeset=1` in a file under `/etc/modprobe.d/` is preferred over an entry on the kernel command line for three reasons. It is independent of the bootloader, which matters in a repository where the bootloader is itself a toggle and could be either of two. It does not need the GRUB configuration regenerated or a systemd-boot entry rewritten, so it cannot conflict with tasks 2 and 3. And it is what NVIDIA's own README recommends, since it can be tested without a reboot with `modprobe -r nvidia_drm` followed by `modprobe nvidia_drm modeset=1`.

The initramfs question follows from whether the NVIDIA modules are baked into it. When they are, the modprobe file has to be picked up by a rebuild. The commands differ per distribution and belong in `os_dict`:

| Family | `vars/<OS>.yaml` key | Value |
|---|---|---|
| Debian | `initramfs_rebuild_command` | `update-initramfs -u` |
| RedHat | `initramfs_rebuild_command` | `dracut --force` |
| Archlinux | `initramfs_rebuild_command` | `mkinitcpio -P` |

Debian does not bake them in as of bookworm, quoted from [https://wiki.debian.org/NvidiaGraphicsDrivers](https://wiki.debian.org/NvidiaGraphicsDrivers): "As of Bookworm, NV modules are not included in initramfs, so there's no need to add the above options to the kernel command line in the GRUB config." Rebuilding anyway is cheap and correct on every family, so run it unconditionally when the modprobe file was actually written, and not at all when it was not. That keeps the idempotency scenario clean, because the rebuild is a `changed_when` on the file write rather than a task of its own.

#### Decision 1.4: Which distributions already have it on, and the one this could not establish

| Distribution | Already on by default | Evidence |
|---|---|---|
| Arch | Yes, since `nvidia-utils` 560.35.03-5 | [https://wiki.archlinux.org/title/NVIDIA](https://wiki.archlinux.org/title/NVIDIA): "Starting from nvidia-utils 560.35.03-5, DRM is enabled by default" |
| Debian | No | [https://wiki.debian.org/NvidiaGraphicsDrivers](https://wiki.debian.org/NvidiaGraphicsDrivers) gives manual instructions |
| Fedora, RPM Fusion | Could not establish, probably not | No RPM Fusion spec file, changelog or packaging note setting it was found. Guides for Fedora 43 and 44 still tell the user to write the modprobe file and run `dracut --force` by hand, which is inconsistent with it already being on |
| Ubuntu | Could not establish | `packages.ubuntu.com`'s content index returned no hit for `modeset` or `nvidia-kms.conf` in the noble archive. A claim that such a file ships at `/usr/lib/modprobe.d/nvidia-kms.conf` could not be confirmed against any Ubuntu source |

The two unestablished rows are exactly why decision 1.2 measures rather than consulting a table. An implementer who wrote that table into the role would be encoding two guesses.

The GDM side has its own per-distribution history, and one live discrepancy worth carrying forward rather than papering over. Fedora has had Wayland as the default GNOME session for NVIDIA users since Fedora 36, quoted from [https://fedoraproject.org/wiki/Changes/WaylandOnlyGNOME](https://fedoraproject.org/wiki/Changes/WaylandOnlyGNOME): "it has been the primary experience for all users (including those with NVIDIA cards) since Fedora Linux 36." Ubuntu carried its own patch preferring Xorg on NVIDIA through 24.04 and dropped it in 24.10 in gdm package 46.0-2ubuntu2, per [https://www.phoronix.com/news/Ubuntu-24.10-GDM-Wayland-NVIDIA](https://www.phoronix.com/news/Ubuntu-24.10-GDM-Wayland-NVIDIA). Ubuntu 26.04's behaviour was not verified directly and should inherit the dropped patch, but that is inference. Debian's own wiki at [https://wiki.debian.org/Wayland](https://wiki.debian.org/Wayland) still says today: "GDM (GNOME Display Manager) will automatically use Wayland when supported, except when using the proprietary NVIDIA driver, in which case it will fall back to X11 due to instability," naming `/etc/gdm3/daemon.conf` as the place to change it. That contradicts upstream GDM 49 having no such rule. It is either a Debian-specific patch analogous to Ubuntu's old one, or a stale wiki page, and the Debian package's own file list could not be fetched to settle it. Measure it on the machine, which is what decision 1.2 does anyway.

#### Decision 1.5: Where the code goes

A new `wayland_nvidia.yaml` under [setup/ansible/roles/system_core/tasks/](../../../setup/ansible/roles/system_core/tasks/), included from that role's `main.yaml` with `when: toggle_wayland_nvidia | default(false) | bool`. Rejected alternative: a role of its own. `system_core` is already where the other system settings live, `setup_tmpfs` and the locale and clock configuration among them, in [system_config.yaml](../../../setup/ansible/roles/system_core/tasks/system_config.yaml), and this is one more of those. A role for eight tasks would be the only role in the tree gated on a single toggle.

Note that `system_core` itself is gated on `install_system_core`, which defaults true and is hidden from both wizards as "the bootstrap everything needs". So a user ticking the Wayland box gets it.

#### Decision 1.6: What this deliberately does not do

Suspend and resume on NVIDIA is a separate subject and stays out. The parameter that preserves video memory across suspend was renamed in the 595 branch, quoted from [https://wiki.archlinux.org/title/NVIDIA/Tips\_and\_tricks](https://wiki.archlinux.org/title/NVIDIA/Tips_and_tricks): "Introduced as an 'experimental' interface (originally named `NVreg_PreserveVideoMemoryAllocations` in the 430-590 series drivers)... With 595+ drivers, it has been succeeded by the `NVreg_UseKernelSuspendNotifiers=1` kernel module parameter." Neither is on by default upstream, Arch sets it in its own packaging. Two parameters with different names across the driver range this project can encounter, on a machine where `setup_hibernate` is a separate toggle with its own manual test row, is its own change and not this one.

Early loading of the NVIDIA modules into the initramfs, for a flicker-free boot, stays out for a concrete reason from the same page: "Early loading the modules will break hibernation, as video memory preservation is enabled by default." `setup_hibernate` defaults to true in this repository, so doing it would silently break a feature the user has on.

`nvidia_drm.fbdev` stays out. The Arch wiki records it as "a hard requirement on Linux 6.11 and later, but it is currently unclear whether this is intended behavior or a bug", and no upstream source resolving that was found. Adding a parameter whose necessity nobody can state is not something to do to a user's boot configuration.

### Task 2, install GRUB

#### Decision 2.1: A `grub.yaml` inside the existing role, not a new role

The mutual exclusion in the spec is the reason. `setup_grub` and `setup_systemd_boot` must not both take effect, and the check for that is cheapest where both are visible. The existing role already owns the EFI system partition detection, the vfat check, the root and swap UUID lookups, the backup of existing entries and the multi-boot preservation, all in [main.yaml](../../../setup/ansible/roles/systemd_boot/tasks/main.yaml), and every one of those is needed identically by GRUB.

Rejected alternative: a separate `grub_boot` role. It would duplicate all six of those, which is the shape recorded in the ledger as "the same rule implemented in two places, which then disagreed". If two phases must agree, they call one function.

This means renaming what the role is. The directory is called `systemd_boot` and would become the bootloader role. Renaming a role means updating the import in `site.yaml` at line 88, the `ROLE_TOGGLE_MAPPING` key in `dual_logger.py` at line 192, and the `--tags boot` tag. That is a decision to put to the owner before doing it, and it is listed as an open question rather than assumed. The fallback, if the rename is refused, is a `grub.yaml` inside the existing `systemd_boot` role with the role's gate in `site.yaml` widened to `setup_systemd_boot or setup_grub`, which works and reads oddly.

#### Decision 2.2: The per-distribution facts, and why every one of them is in `vars/`

Nothing below may be written into a task. New `os_dict` keys, three files:

| Key | Debian | RedHat | Archlinux |
|---|---|---|---|
| `grub_packages` | `grub-efi-amd64`, `grub-efi-amd64-signed`, `grub-common`, `grub2-common`, `os-prober`, `efibootmgr` | `grub2-efi-x64`, `grub2-efi-x64-modules`, `grub2-tools`, `grub2-common`, `os-prober`, `efibootmgr` | `grub`, `os-prober`, `efibootmgr` |
| `grub_efi_dir` | `debian`, `ubuntu` on Ubuntu | `fedora` | `arch` |
| `grub_config_path` | `/boot/grub/grub.cfg` | `/boot/grub2/grub.cfg` | `/boot/grub/grub.cfg` |
| `grub_mkconfig_command` | `update-grub` | `grub2-mkconfig -o /boot/grub2/grub.cfg` | `grub-mkconfig -o /boot/grub/grub.cfg` |
| `grub_install_command` | `grub-install --target=x86_64-efi --efi-directory=<esp> --bootloader-id=<id>` | `grub2-install --target=x86_64-efi --efi-directory=<esp> --bootloader-id=<id>` | `grub-install --target=x86_64-efi --efi-directory=<esp> --bootloader-id=<id>` |

The EFI directory name is already derived for the removal path by the `distro_grub_efi_dir` map in [remove_grub.yaml](../../../setup/ansible/roles/systemd_boot/tasks/remove_grub.yaml) lines 6 to 20, keyed on `ansible_facts['distribution']` and covering Ubuntu, Debian, Archlinux, Fedora, CentOS, AlmaLinux and Rocky. Install and removal MUST read the same source, so the install path uses that same fact rather than a second copy. Two phases disagreeing about a name is exactly defect class 2 in [AGENTS.md](../../../AGENTS.md).

Note what this table does not claim to have verified. The package sets were read out of the removal task's own lists, which is what this repository already believes about each distribution, not a fresh check against each distribution's archive. An implementer MUST confirm each name resolves before relying on it, which is what `./e2e/run.sh --tier 2` is for.

#### Decision 2.3: Kernel command line options come from the same place the systemd-boot path builds them

`main.yaml` already registers `root_uuid` from `findmnt -n -o UUID /` and `swap_uuid` from `swapon --show`, and the per-distribution task files build a `boot_options` fact from them, including the `resume=UUID=` clause when a swap partition exists. GRUB's configuration generation reads `GRUB_CMDLINE_LINUX_DEFAULT` from `/etc/default/grub` instead, so the GRUB path writes that variable using the same `boot_options` fact and then runs the distribution's `grub_mkconfig_command`. One source for the kernel command line, two consumers.

#### Decision 2.4: Verification mirrors the systemd-boot verification exactly

The existing role sets `systemd_boot_verified` from `boot_entry_files.matched > 0` and gates the GRUB removal on it. The GRUB path sets `grub_verified` from two conditions: the EFI binary exists under `<esp>/EFI/<grub_efi_dir>/`, and the generated configuration at `grub_config_path` contains at least one `menuentry` line naming the root UUID. Grepping the generated configuration rather than only counting files is deliberate: `grub-mkconfig` exits 0 and writes a configuration file even when it finds no kernel, and a menu with no entries boots to a GRUB prompt.

On failure it reports and sets `any_role_failed: true`, and does not `fail:`, for the reason written out at length in `main.yaml` above the equivalent systemd-boot task. The comment there is the canonical statement of the rule and should not be duplicated.

### Task 3, remove systemd-boot

#### Decision 3.1: Mirror `remove_grub.yaml` structure exactly

A `remove_systemd_boot.yaml` alongside it, gated on `remove_distro_systemd_boot | bool` and `grub_verified | bool`, which is the same two-condition gate the GRUB removal already uses. What it removes:

1. The `<esp>/EFI/systemd/` directory, which holds `systemd-bootx64.efi`.
2. `<esp>/EFI/BOOT/BOOTX64.EFI` only when it is systemd-boot's copy. `bootctl install` writes one there and GRUB's `--removable` install writes to the same path, so this one has to be identified rather than assumed. `bootctl status` names the current default loader and is the right question to ask.
3. The loader entries under `<esp>/loader/entries/` whose filenames begin with this machine's machine-id, read from `/etc/machine-id` the way [debian.yaml](../../../setup/ansible/roles/systemd_boot/tasks/debian.yaml) and [fedora.yaml](../../../setup/ansible/roles/systemd_boot/tasks/fedora.yaml) already do, plus `<esp>/loader/loader.conf`. Another distribution's entries on a shared EFI system partition carry a different machine-id and MUST survive.
4. The NVRAM entry whose loader path is `\EFI\systemd\systemd-bootx64.efi`, matched by path with the same `efibootmgr -v` parsing `remove_grub.yaml` uses at lines 84 to 95, never by label.
5. The kernel install hooks this project itself wrote: `/etc/kernel/postinst.d/zz-bootctl-update` on Debian, `/etc/pacman.d/hooks/95-systemd-boot.hook` on Arch, and on Fedora the `sdubby` package and `/etc/kernel/install.conf` if `layout=bls` was written by the Debian path. Leaving a hook that runs `bootctl update` on a machine with no systemd-boot means an error on every kernel update.

#### Decision 3.2: Do not remove the systemd-boot package on any distribution

`bootctl` ships inside `systemd` itself on Arch and Debian, and Debian's separate `systemd-boot` package is a thin wrapper. Removing `systemd` is not something to do to a running machine. Only Fedora's `systemd-boot-unsigned`, which the role installs itself in [fedora.yaml](../../../setup/ansible/roles/systemd_boot/tasks/fedora.yaml), is a package removal that is both safe and meaningful, and even that is optional: the EFI binary is gone either way. Prefer removing files and NVRAM entries over removing packages. The GRUB removal path can afford package removal because GRUB genuinely is its own package everywhere.

### The gate, shared by all three

The `skip` at the bottom of [e2e/tier1/toggle_coverage.sh](../../../e2e/tier1/toggle_coverage.sh) reports the three unconsumed toggles and names this change directory. Each task removes one name from the list simply by making the toggle consumed, because the check reads the tree rather than a list. The last of the three to be finished turns the `skip` into a `fail`, which is a two-line edit and is stated in the comment above it: "Turn this skip into a fail once they are resolved: that is the whole change."

Before trusting that flip, prove the failing direction against a copy of the tree carrying the defect, which is what [AGENTS.md](../../../AGENTS.md) requires of any change to a check. The method is recorded in the ledger entry for this check: copy the tree under `E2E_REPO_ROOT`, append one line such as `setup_nonexistent_thing: true` to `group_vars/linux.yaml`, and confirm the check names it.

## Risks / Trade-offs

An unbootable machine, from task 2 or task 3. Mitigation: a UEFI virtual machine with a snapshot taken before the run, which is the only place either may be tested, plus the verification gate that refuses to remove a bootloader until a replacement has been proven, plus the timestamped backup of existing loader entries the role already takes.

A broken graphical session, from task 1, which is what the toggle's own label warns about. Mitigation: the change is a module parameter and a display manager configuration, both reversible from a text console or a rescue shell. The run's summary should say which files it wrote so the user can undo them without hunting.

Task 1 writing configuration a modern driver does not need. Mitigation: decision 1.2 measures rather than assuming, and reports "already satisfied" rather than writing.

Two of the driver-default facts could not be established, for Fedora's RPM Fusion package and for Ubuntu. Mitigation: the same one, the implementation does not depend on knowing them. The risk that remains is documentation drift, not behaviour.

The role rename in decision 2.1 touching `site.yaml`, `dual_logger.py` and the `boot` tag. Mitigation: it is an open question below rather than an assumption, and the fallback needs no rename.

Grepping the generated GRUB configuration for a `menuentry` naming the root UUID is a text check against a generated file whose format is not a contract. Mitigation: it is the weaker of the two verification conditions and the EFI binary check stands beside it. If the format moves, the check reports a failure that costs a manual verification rather than a bricked machine, which is the right direction to fail in.

## Migration Plan

There is nothing to migrate. All three toggles are false today and nothing changes for a machine that leaves them false. Rollback for a user who enabled one is the reverse of what the run wrote, which is why each task's output must name the files it touched.

## Open Questions

1. Does the owner want the `systemd_boot` role renamed to a bootloader role as part of task 2, per decision 2.1, or the fallback of a `grub.yaml` inside a role still called `systemd_boot` with a widened gate in `site.yaml`? This changes three files beyond the task's own and is a naming decision, not a technical one.
2. Should task 3 offer the fourth combination at all, meaning a machine that has systemd-boot, installs GRUB, and removes systemd-boot in one run? The spec requires exactly that ordering within one run. The alternative is to require two runs, which is safer and more annoying. The spec as written takes the one-run route because that is what the existing GRUB removal already does in the mirror direction.
