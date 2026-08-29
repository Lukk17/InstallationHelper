Three top-level tasks. Each one is independently selectable: pick any one, finish it, verify it, commit it, and the other two are unaffected. There is no ordering between them and no shared file except the gate in section 4, which each task touches only by making its own toggle consumed.

Read [design.md](design.md) before starting any of them. It carries the research, so nothing below should send you off to find a fact out.

## 1. `toggle_wayland_nvidia`

Make a Wayland session available and preferred on a machine with the NVIDIA proprietary driver. Behaviour contract: [specs/wayland-nvidia-session/spec.md](specs/wayland-nvidia-session/spec.md). Approach and research: design.md decisions 1.1 to 1.6.

### 1.1 Implementation

- [ ] 1.1.1 Add `initramfs_rebuild_command` to [setup/ansible/vars/Debian.yaml](../../../setup/ansible/vars/Debian.yaml) as `update-initramfs -u`, to [setup/ansible/vars/RedHat.yaml](../../../setup/ansible/vars/RedHat.yaml) as `dracut --force`, and to [setup/ansible/vars/Archlinux.yaml](../../../setup/ansible/vars/Archlinux.yaml) as `mkinitcpio -P`. Put them next to `openrazer_device_group`, above `software_mapping`, which is where the existing non-mapping facts live.
- [ ] 1.1.2 Create `setup/ansible/roles/system_core/tasks/wayland_nvidia.yaml`. Detect whether the NVIDIA proprietary driver is present at all, by asking for the `nvidia` module and for an NVIDIA display controller. When it is absent, emit a `debug` naming the reason and end the file's work. Do not `fail:`, and do not write anything.
- [ ] 1.1.3 In the same file, read the current value of the module parameter from `/sys/module/nvidia_drm/parameters/modeset` when the module is loaded, and fall back to the driver version from `modinfo nvidia` when it is not. Write `/etc/modprobe.d/nvidia-drm.conf` containing `options nvidia_drm modeset=1` only when the parameter is not already `Y` and the driver branch is below 595. Design decisions 1.2 and 1.3 say why this measures rather than consulting a version table, and why modprobe.d rather than the kernel command line.
- [ ] 1.1.4 Rebuild the initramfs with `os_dict.initramfs_rebuild_command`, as a handler notified by the file write from 1.1.3, so it runs when and only when the file changed. A handler rather than a task keeps the idempotency scenario clean.
- [ ] 1.1.5 Lift the GDM suppression when one is present, and only then. Check for the udev rule at `/usr/lib/udev/rules.d/61-gdm.rules` and for a `WaylandEnable=false` line in the distribution's GDM configuration file, `/etc/gdm3/custom.conf` or `/etc/gdm3/daemon.conf` on Debian and Ubuntu, `/etc/gdm/custom.conf` on Fedora and Arch. Mask the rule with a symlink to `/dev/null` under `/etc/udev/rules.d/`, which survives a package upgrade, and set the key to `true`. When neither is found, emit a `debug` saying no display manager change was needed and write nothing. Design decision 1.1 has the upstream removal history and decision 1.4 the per-distribution picture, including the live Debian wiki discrepancy that is the reason this measures instead of trusting a version.
- [ ] 1.1.6 Do nothing at all for SDDM beyond confirming the desktop's Wayland session desktop file exists. SDDM has no blocklist. Design decision 1.1.
- [ ] 1.1.7 Emit a summary line stating that a reboot is required, naming every file the run wrote, and naming `echo $XDG_SESSION_TYPE` as the check to run afterwards. Do not claim the session is Wayland now.
- [ ] 1.1.8 Include the file from [setup/ansible/roles/system_core/tasks/main.yaml](../../../setup/ansible/roles/system_core/tasks/main.yaml) with `when: toggle_wayland_nvidia | default(false) | bool` and `ansible_facts['system'] == 'Linux'`.
- [ ] 1.1.9 Add a row to the "Linux, every distribution" table in [e2e/manual_test_matrix.md](../../../e2e/manual_test_matrix.md), the one beginning at line 51. Toggle: `toggle_wayland_nvidia`. Why no container: no graphics device, no display manager and no session, so nothing can observe a session starting. Where: virtual machine with a desktop for the display manager half, real machine with an NVIDIA card for the driver half. How to tell it worked: reboot, log in, and `echo $XDG_SESSION_TYPE` prints `wayland`, and `cat /sys/module/nvidia_drm/parameters/modeset` reads `Y`.

### 1.2 Verification

- [ ] 1.2.1 Syntax check, from the repository root on Windows:
  ```bash
  wsl -d Ubuntu bash -c "ansible-playbook --syntax-check /mnt/d/Development/projekty-IT/InstallationHelper/setup/ansible/site.yaml"
  ```
- [ ] 1.2.2 Tier 1, which is what proves the toggle is now consumed. From Git Bash at the repository root:
  ```bash
  bash e2e/run.sh
  ```
  `toggle_coverage.sh` must stop naming `toggle_wayland_nvidia` in its skip list. Exit code must be 0.
- [ ] 1.2.3 Tier 3 defaults, because this adds tasks to `system_core`, which every scenario runs. It proves the toggle-off path changes nothing, which is the first requirement in the spec:
  ```bash
  bash e2e/run.sh --tier 3 --scenario defaults
  ```
- [ ] 1.2.4 Tier 3 idempotency, because 1.1.3 and 1.1.5 both write files conditionally and a mis-written condition reports `changed` forever:
  ```bash
  bash e2e/run.sh --tier 3 --scenario idempotency
  ```
- [ ] 1.2.5 Manual, on a virtual machine with a desktop and no NVIDIA card: enable the toggle, run, and confirm the run reports the skip with its reason and writes nothing. This is the "refuses a machine with no NVIDIA driver" scenario and it is the half a VM can prove.
- [ ] 1.2.6 Manual, on a real machine with an NVIDIA card, snapshot or backup first because a broken session is what the toggle's own label warns about: enable the toggle, run, reboot, log in, and check `echo $XDG_SESSION_TYPE` and `cat /sys/module/nvidia_drm/parameters/modeset`. Then run the playbook a second time and confirm nothing reports changed.
- [ ] 1.2.7 Add an entry to [docs/regression_ledger.md](../../../docs/regression_ledger.md) recording the toggle being implemented, and amend the existing dead-toggle entry to say this one is now closed.

## 2. `setup_grub`

Install GRUB as the UEFI bootloader, the mirror of what the role already does for systemd-boot. Behaviour contract: [specs/grub-bootloader-install/spec.md](specs/grub-bootloader-install/spec.md). Approach: design.md decisions 2.1 to 2.4.

Getting a bootloader wrong leaves a machine that will not start. Nothing in this task may be tested in a container, and the first run of it belongs on a UEFI virtual machine with a snapshot taken beforehand.

### 2.1 Decision to take before starting

- [ ] 2.1.1 Ask the owner open question 1 in [design.md](design.md): rename the `systemd_boot` role to a bootloader role, or keep the name and widen the gate. The rest of this task is the same either way, but three files outside it depend on the answer.

### 2.2 Implementation

- [ ] 2.2.1 Add the GRUB facts to the three `vars/<OS>.yaml` files, per the table in design decision 2.2: `grub_packages`, `grub_config_path`, `grub_mkconfig_command`, `grub_install_command`. The EFI directory name is not a new key, it reuses the `distro_grub_efi_dir` map already in [remove_grub.yaml](../../../setup/ansible/roles/systemd_boot/tasks/remove_grub.yaml) lines 6 to 20, so lift that map to a place both the install and the removal read. Two phases must not each decide the name separately.
- [ ] 2.2.2 Add the mutual-exclusion check. When `setup_grub` and `setup_systemd_boot` are both true, refuse before anything is written to the EFI system partition, with a message naming both toggles.
- [ ] 2.2.3 Create `setup/ansible/roles/systemd_boot/tasks/grub.yaml`, or the renamed role's equivalent. It runs after the shared preconditions in [main.yaml](../../../setup/ansible/roles/systemd_boot/tasks/main.yaml), which already establish `esp_path`, the vfat check, `root_uuid`, `swap_uuid`, the loader entry backup and the report of other operating systems' EFI binaries. Do not duplicate any of those.
- [ ] 2.2.4 Install `os_dict.grub_packages` with the family's package module, write `GRUB_CMDLINE_LINUX_DEFAULT` into `/etc/default/grub` from the same `boot_options` fact the per-distribution systemd-boot files build, then run `os_dict.grub_install_command` and `os_dict.grub_mkconfig_command`. Design decision 2.3 explains the shared `boot_options`.
- [ ] 2.2.5 Set `grub_verified` from two conditions: the EFI binary exists under `{{ esp_path }}/EFI/{{ distro_grub_efi_dir }}/`, and `os_dict.grub_config_path` contains a `menuentry` line naming the root UUID. Design decision 2.4 says why counting files is not enough.
- [ ] 2.2.6 On failure, emit the `[ERROR]` debug naming both paths and `set_fact: any_role_failed: true`. Do not use `fail:`. The comment above the equivalent systemd-boot task in `main.yaml` is the canonical statement of why, and must not be copied.
- [ ] 2.2.7 Gate the role's invocation in [setup/ansible/site.yaml](../../../setup/ansible/site.yaml) at line 88 so it runs when either install toggle is true, and re-check both toggles inside the role so a `--tags boot` run cannot bypass the gate. The existing role already does the equivalent re-check for `setup_systemd_boot` at the top of `main.yaml`.
- [ ] 2.2.8 Update the bootloader row at [e2e/manual_test_matrix.md](../../../e2e/manual_test_matrix.md) line 53, which already names all four toggles. Add to its "How to tell it worked" column: reboot, then `efibootmgr -v` shows the firmware pointing at this distribution's GRUB, and the GRUB menu appears with an entry naming this distribution.

### 2.3 Verification

- [ ] 2.3.1 Syntax check, the WSL command from 1.2.1.
- [ ] 2.3.2 Tier 1:
  ```bash
  bash e2e/run.sh
  ```
  `toggle_coverage.sh` must stop naming `setup_grub`. Exit 0.
- [ ] 2.3.3 Tier 2, because this adds package names read per distribution and tier 2 is what resolves them against real indexes. Five shipped defects came from package names written into role tasks:
  ```bash
  bash e2e/run.sh --tier 2
  ```
- [ ] 2.3.4 Tier 3 defaults, on all four Linux distributions and not just one, because this changes a role that touches per-distribution behaviour. It proves the toggle-off path is unchanged, which is all a container can prove here:
  ```bash
  bash e2e/run.sh --tier 3 --scenario defaults
  ```
- [ ] 2.3.5 Manual, and this is the only thing that proves the feature. UEFI virtual machine, snapshot taken first, one per Linux family. Enable `setup_grub`, run, reboot. The machine must come up. Then `efibootmgr -v` and the GRUB menu. Roll back to the snapshot between families.
- [ ] 2.3.6 Manual, the refusal paths: a BIOS virtual machine, which must skip and not abort the play, and a machine with both install toggles true, which must refuse before writing.
- [ ] 2.3.7 Add an entry to [docs/regression_ledger.md](../../../docs/regression_ledger.md) and amend the dead-toggle entry.

## 3. `remove_distro_systemd_boot`

Remove this distribution's systemd-boot once another bootloader has been installed and verified. Behaviour contract: [specs/systemd-boot-removal/spec.md](specs/systemd-boot-removal/spec.md). Approach: design.md decisions 3.1 and 3.2.

Same warning as task 2, and more sharply: this one deletes a boot path. UEFI virtual machine, snapshot first, no container ever.

This task is independently selectable but its own gate refers to `grub_verified`, which task 2 produces. Implemented on its own it is correct and inert: with no verified replacement it refuses, which is precisely the first scenario in its spec. So it can be written, verified against its refusal paths and committed before task 2 exists.

### 3.1 Implementation

- [ ] 3.1.1 Create `setup/ansible/roles/systemd_boot/tasks/remove_systemd_boot.yaml`, mirroring the structure of [remove_grub.yaml](../../../setup/ansible/roles/systemd_boot/tasks/remove_grub.yaml).
- [ ] 3.1.2 Gate its inclusion on `remove_distro_systemd_boot | default(false) | bool` and `grub_verified | default(false) | bool`, the same two-condition shape the GRUB removal already uses at the bottom of `main.yaml`. When the second condition fails, report it as an `[ERROR]` saying the machine still boots through systemd-boot, not as an informational message.
- [ ] 3.1.3 Remove `{{ esp_path }}/EFI/systemd/`.
- [ ] 3.1.4 Remove `{{ esp_path }}/EFI/BOOT/BOOTX64.EFI` only after identifying it as systemd-boot's copy. `bootctl status` names the current default loader. GRUB's removable install writes to the same path, so this must be identified rather than assumed. Design decision 3.1 item 2.
- [ ] 3.1.5 Remove the loader entries under `{{ esp_path }}/loader/entries/` whose filenames begin with this machine's machine-id, read from `/etc/machine-id` the way [debian.yaml](../../../setup/ansible/roles/systemd_boot/tasks/debian.yaml) already does, and remove `{{ esp_path }}/loader/loader.conf`. Another distribution's entries on a shared EFI system partition carry a different machine-id and must survive.
- [ ] 3.1.6 Delete the NVRAM entry whose loader path is `\EFI\systemd\systemd-bootx64.efi`, matched by path with the same `efibootmgr -v` parsing at [remove_grub.yaml](../../../setup/ansible/roles/systemd_boot/tasks/remove_grub.yaml) lines 84 to 95. Never by label. Name each entry in the output before deleting it.
- [ ] 3.1.7 Remove the kernel update hooks this project itself wrote, per design decision 3.1 item 5: `/etc/kernel/postinst.d/zz-bootctl-update` on Debian, `/etc/pacman.d/hooks/95-systemd-boot.hook` on Arch, and on Fedora the `sdubby` package and the `layout=bls` line in `/etc/kernel/install.conf` if this project wrote it. A hook running `bootctl update` on a machine with no systemd-boot errors on every kernel update.
- [ ] 3.1.8 Do not remove `systemd` or Debian's `systemd-boot` package. Only Fedora's `systemd-boot-unsigned`, which the role installs itself, is a safe and meaningful package removal. Design decision 3.2.
- [ ] 3.1.9 Make every removal tolerant of the file already being absent, so a second run reports no change and does not fail.
- [ ] 3.1.10 Update the bootloader row at [e2e/manual_test_matrix.md](../../../e2e/manual_test_matrix.md) line 53. Add: after the reboot, `bootctl status` reports no systemd-boot installed, and `efibootmgr -v` no longer lists an entry pointing at `\EFI\systemd\`.

### 3.2 Verification

- [ ] 3.2.1 Syntax check, the WSL command from 1.2.1.
- [ ] 3.2.2 Tier 1:
  ```bash
  bash e2e/run.sh
  ```
  `toggle_coverage.sh` must stop naming `remove_distro_systemd_boot`. Exit 0.
- [ ] 3.2.3 Tier 3 defaults, on all four Linux distributions, proving the toggle-off path is unchanged:
  ```bash
  bash e2e/run.sh --tier 3 --scenario defaults
  ```
- [ ] 3.2.4 Manual, the refusal paths first, because they are the ones that can be proven without risking a machine. On a UEFI virtual machine with systemd-boot installed: enable `remove_distro_systemd_boot` with `setup_grub` false, run, and confirm nothing was removed and the run said why. Then with `setup_grub` true but its verification forced to fail, and confirm the same.
- [ ] 3.2.5 Manual, the real path, snapshot first. UEFI virtual machine with systemd-boot installed, both `setup_grub` and `remove_distro_systemd_boot` enabled, one per Linux family. Run, reboot, the machine must come up through GRUB. Then `bootctl status` and `efibootmgr -v`.
- [ ] 3.2.6 Manual, the multi-boot case, which is the one with the worst failure mode. A UEFI virtual machine with two Linux installations sharing one EFI system partition. After the run, the second installation's loader entries, EFI directory and NVRAM entry must all still be there.
- [ ] 3.2.7 Run it twice on the same machine and confirm the second run reports no change and does not fail.
- [ ] 3.2.8 Add an entry to [docs/regression_ledger.md](../../../docs/regression_ledger.md) and amend the dead-toggle entry.

## 4. Closing the gate

Do this once, as part of whichever of the three tasks is finished last. Not before: the skip must keep naming whichever toggles are still open.

- [ ] 4.1 Prove the failing direction first. Copy the tree to a scratch directory, point `E2E_REPO_ROOT` at the copy, append one line such as `setup_nonexistent_thing: true` to its `group_vars/linux.yaml`, and confirm the changed check names that toggle and fails. This is the method recorded in the ledger entry for this check, and [AGENTS.md](../../../AGENTS.md) requires it of any change to a check.
- [ ] 4.2 In [e2e/tier1/toggle_coverage.sh](../../../e2e/tier1/toggle_coverage.sh), turn the `skip` at the end of the declared-toggle direction into a `fail`, and remove the comment block above it that explains the skip is deliberate and temporary, along with the reference to this change directory.
- [ ] 4.3 Run the whole gate from Git Bash and from WSL, per the rule in [AGENTS.md](../../../AGENTS.md) for any change under `e2e/`:
  ```bash
  bash e2e/run.sh
  ```
  ```powershell
  wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && ./e2e/run.sh"
  ```
- [ ] 4.4 Amend the dead-toggle entry in [docs/regression_ledger.md](../../../docs/regression_ledger.md) to record that all three are closed and the skip is now a fail.
- [ ] 4.5 Archive this change: `openspec archive implement-unconsumed-linux-toggles`.
