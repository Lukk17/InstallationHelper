## Why

Three toggles are declared in `setup/ansible/group_vars/linux.yaml` and consumed by nothing anywhere in the repository. Ticking one does exactly nothing while the run reports success. They were found on 2026-08-28 when `e2e/tier1/toggle_coverage.sh` was widened past the `install_` prefix, and the finding is recorded in [docs/regression_ledger.md](../../../docs/regression_ledger.md) under "A coverage check that had only ever looked at one prefix, and the dead toggles behind it".

The owner has decided to leave all three as they are for now. This change is the written record of what implementing each one would take, so the work is not lost and so the next person does not have to redo the search. Nothing in this proposal is implemented yet.

The gate reports the three as a `skip` rather than a `fail`, deliberately and temporarily, because implementing a toggle and deleting a toggle are both the owner's call. That skip names this change directory so anybody reading the gate output can find this plan in one step.

### The three toggles, and the proof that each is unconsumed

Run from the repository root. Every command below was run on 2026-08-29 and its output is quoted verbatim.

```bash
grep -rn "toggle_wayland_nvidia" setup/
```

```text
setup/ansible/group_vars/linux.yaml:21:toggle_wayland_nvidia: false
setup/setup.ps1:145:    'toggle_wayland_nvidia' = 'System: force Wayland on NVIDIA, can break the session'
setup/setup.sh:133:    [toggle_wayland_nvidia]="System: force Wayland on NVIDIA, can break the session"
```

One declaration and two label-table entries. No role, no task, no `when:` clause, nothing under `setup/windows/`.

```bash
grep -rn --binary-files=without-match "setup_grub" setup/
```

```text
setup/ansible/callback_plugins/dual_logger.py:193:    'systemd_boot':        ['setup_systemd_boot', 'setup_grub',
setup/ansible/group_vars/linux.yaml:16:setup_grub: false
setup/setup.ps1:134:    'setup_systemd_boot', 'setup_grub',
setup/setup.sh:123:#   rewrites the bootloader         setup_systemd_boot, setup_grub, remove_distro_*
setup/setup.sh:124:EXCLUDED_VARS="non_root_user|non_root_home|allow_callback_failure|default_wallpaper|install_system_core|setup_hibernate|setup_systemd_boot|setup_grub|remove_distro_grub|remove_distro_systemd_boot"
```

```bash
grep -rn --binary-files=without-match "remove_distro_systemd_boot" setup/
```

```text
setup/ansible/callback_plugins/dual_logger.py:194:                            'remove_distro_grub', 'remove_distro_systemd_boot'],
setup/ansible/group_vars/linux.yaml:18:remove_distro_systemd_boot: false
setup/setup.ps1:135:    'remove_distro_grub', 'remove_distro_systemd_boot'
setup/setup.sh:124:EXCLUDED_VARS="non_root_user|non_root_home|allow_callback_failure|default_wallpaper|install_system_core|setup_hibernate|setup_systemd_boot|setup_grub|remove_distro_grub|remove_distro_systemd_boot"
```

### Read that output carefully, because two of the hits look like implementations and are not

This is the trap, and it is worth spelling out rather than leaving to be rediscovered. The next person to look at `setup_grub` and `remove_distro_systemd_boot` sees them named in two files that are not `group_vars` and concludes they are wired up. They are not.

`ROLE_TOGGLE_MAPPING` in [setup/ansible/callback_plugins/dual_logger.py](../../../setup/ansible/callback_plugins/dual_logger.py) line 192 is a table that attributes a skipped role to the toggles a user would recognise, so the end-of-run summary can say which toggle caused the skip. It decides how a skipped role is described. It never sets a variable, never includes a task file, never runs anything. Describing is not acting.

`$ExcludedVars` in [setup/setup.ps1](../../../setup/setup.ps1) line 128 and `EXCLUDED_VARS` in [setup/setup.sh](../../../setup/setup.sh) line 124 are the wizard's hide list. They decide that the checklist must not offer these toggles, because a mistake in a bootloader means the machine does not start. Being on a list of things not to show a user is the opposite of being implemented.

This is the same shape as the `install_gradle` defect recorded in the ledger, where a comment claiming SDKMAN handled it stood in for an implementation that did not exist. It is why `toggle_coverage.sh` strips comments before searching for consumers, and why neither wizard nor the callback table counts as a consumer in that check.

`toggle_wayland_nvidia` has the opposite problem. It is not hidden by `EXCLUDED_VARS`, so it appears on both wizards' checklists labelled "System: force Wayland on NVIDIA, can break the session". It is the only one of the three a user can reach, and the label promises a behaviour that does not exist.

## What Changes

Three independent tasks. Each can be picked up and finished on its own, in any order, with no dependency on the other two. None of them is done in this change.

1. Implement `toggle_wayland_nvidia` so that enabling it makes a Wayland session available and preferred on a machine with an NVIDIA GPU, and so that leaving it false changes nothing on any machine.
2. Implement `setup_grub`, the missing third quarter of the bootloader symmetry. The playbook can install systemd-boot and cannot install GRUB.
3. Implement `remove_distro_systemd_boot`, the missing fourth quarter. The playbook can remove GRUB and cannot remove systemd-boot.

Each task also moves its own part of the gate. The `skip` in [e2e/tier1/toggle_coverage.sh](../../../e2e/tier1/toggle_coverage.sh) becomes a `fail` only when all three are closed, so the first two tasks to be finished leave the skip in place with a shorter list behind it, and the last one turns it into a `fail`.

**BREAKING**: none. All three default to `false` in `group_vars/linux.yaml` and no task here alters a default. A machine that does not tick a box behaves exactly as it does today.

## Capabilities

### New Capabilities

- `wayland-nvidia-session`: what enabling `toggle_wayland_nvidia` must do on each Linux family, what it must not do, and how a machine proves the session came up under Wayland.
- `grub-bootloader-install`: what enabling `setup_grub` must do, the mutual exclusion against `setup_systemd_boot`, and the verification that has to pass before anything removes the other bootloader.
- `systemd-boot-removal`: what enabling `remove_distro_systemd_boot` must do, and the gate that keeps it from running on a machine that has no other working boot path.

### Modified Capabilities

None. `openspec/specs/` is empty in this project, so all three are new.

## Impact

### Files an implementer will touch

| Task | Files |
|---|---|
| 1, Wayland on NVIDIA | a new task file under [setup/ansible/roles/system_core/tasks/](../../../setup/ansible/roles/system_core/tasks/), an include in [system_core/tasks/main.yaml](../../../setup/ansible/roles/system_core/tasks/main.yaml), per-distribution facts in [setup/ansible/vars/Debian.yaml](../../../setup/ansible/vars/Debian.yaml), [setup/ansible/vars/RedHat.yaml](../../../setup/ansible/vars/RedHat.yaml) and [setup/ansible/vars/Archlinux.yaml](../../../setup/ansible/vars/Archlinux.yaml), a new row in [e2e/manual_test_matrix.md](../../../e2e/manual_test_matrix.md) |
| 2, install GRUB | a `grub.yaml` under [setup/ansible/roles/systemd_boot/tasks/](../../../setup/ansible/roles/systemd_boot/tasks/) or a sibling role, a gate in [setup/ansible/site.yaml](../../../setup/ansible/site.yaml) near line 88, per-distribution package and path facts in the three `vars/` files, the bootloader row at [e2e/manual_test_matrix.md](../../../e2e/manual_test_matrix.md) line 53 |
| 3, remove systemd-boot | a `remove_systemd_boot.yaml` alongside [setup/ansible/roles/systemd_boot/tasks/remove_grub.yaml](../../../setup/ansible/roles/systemd_boot/tasks/remove_grub.yaml), its gate, the same manual matrix row |

### Files no task may touch

`ROLE_TOGGLE_MAPPING` already lists all four bootloader toggles, so it needs no edit for tasks 2 and 3. Neither wizard's exclusion list should change either: the reason those two are hidden is that a bootloader mistake costs the machine its ability to start, and implementing them does not make them safe to offer on a checklist next to a web browser.

### What none of this can be tested by

Tasks 2 and 3 rewrite the bootloader. There is no container answer and there never will be, because a container has no EFI system partition, no NVRAM and no firmware to hand a boot entry to. `e2e/run.sh --tier 3` cannot prove either one. Both belong in [e2e/manual_test_matrix.md](../../../e2e/manual_test_matrix.md) against a UEFI virtual machine with a snapshot taken before the run, and the acceptance test is that the machine reboots and comes up.

Task 1 has no container answer either. A container has no graphics device, no display manager and no session, so nothing in tiers 2 or 3 can observe a Wayland session starting. Tier 1 can prove the toggle is consumed and that the run writes the files it claims to write. The rest is a virtual machine with a desktop, and a real machine with an NVIDIA card for the parts that need the hardware.
