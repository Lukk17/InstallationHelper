## Purpose

Installs GRUB as the machine's UEFI bootloader and writes a boot entry that actually boots, which is the mirror image of what the `systemd_boot` role already does for systemd-boot. Covers the mutual exclusion against `setup_systemd_boot`, the verification that has to pass before any other bootloader is removed, and the refusal to act on firmware that cannot support it.

## ADDED Requirements

### Requirement: The toggle does nothing when it is false

The playbook SHALL make no change to any bootloader, EFI system partition, NVRAM boot entry or bootloader package when `setup_grub` is false. This is the shipped default and it is hidden from both wizards' checklists, so the overwhelming majority of runs are this case.

#### Scenario: Toggle left at its default

- **WHEN** the playbook runs on any Linux machine with `setup_grub` false
- **THEN** nothing is written to the EFI system partition
- **AND** no NVRAM boot entry is created, altered or deleted
- **AND** no bootloader package is installed or removed

### Requirement: The two install toggles are mutually exclusive

`setup_grub` and `setup_systemd_boot` SHALL NOT both take effect in one run. A machine cannot have two bootloaders both installed as the firmware's default in a single pass without one of them silently losing, and which one loses would depend on task order rather than on anything the user asked for.

#### Scenario: Both install toggles enabled

- **WHEN** a run starts with both `setup_grub` and `setup_systemd_boot` true
- **THEN** the run refuses before writing anything to the EFI system partition
- **AND** the message names both toggles and says only one may be true

### Requirement: The role refuses non-UEFI firmware and a missing EFI system partition

The role SHALL check its own preconditions rather than relying on the caller's gate, so that a tag-limited run cannot bypass the check and write a bootloader onto a machine that cannot boot it.

#### Scenario: BIOS machine

- **WHEN** the toggle is enabled on a machine with no `/sys/firmware/efi`
- **THEN** the role ends without writing anything and reports why
- **AND** the surrounding play continues rather than aborting

#### Scenario: No mounted EFI system partition

- **WHEN** the toggle is enabled on a UEFI machine with no vfat filesystem mounted at `/efi`, `/boot/efi` or `/boot`
- **THEN** the run fails with a message naming the three paths it looked at and telling the user to mount the EFI partition
- **AND** nothing has been written before that failure

#### Scenario: EFI system partition is not vfat

- **WHEN** a candidate mount point is found but reports a filesystem type other than vfat
- **THEN** the run refuses and names the filesystem type it found

### Requirement: GRUB is installed and a boot entry exists that names the running root

Enabling the toggle on a suitable machine SHALL leave a GRUB EFI binary on the EFI system partition, a generated GRUB configuration, and a boot entry whose kernel command line names the machine's actual root filesystem. The package names, the EFI directory name and the configuration path differ per distribution and MUST come from the OS dictionary rather than being written into a task.

#### Scenario: GRUB installed on a UEFI machine

- **WHEN** the toggle is enabled on a UEFI machine with a mounted vfat EFI system partition
- **THEN** a GRUB EFI binary exists under the distribution's own directory on the EFI system partition
- **AND** a GRUB configuration file exists at the distribution's configuration path
- **AND** that configuration contains at least one menu entry naming the root filesystem by UUID

#### Scenario: Hibernate resume parameter is carried through

- **WHEN** the machine has a swap partition in use and `setup_hibernate` is enabled
- **THEN** the generated boot entry's kernel command line carries a `resume=UUID=` parameter naming that swap partition

### Requirement: Existing bootloaders on the shared EFI system partition are preserved

Installing GRUB SHALL NOT delete another operating system's EFI directory or NVRAM entry. A shared EFI system partition on a multi-boot machine holds Windows and other distributions, and removing one of them costs the user an operating system.

#### Scenario: Multi-boot machine

- **WHEN** the toggle is enabled on a machine whose EFI system partition holds EFI binaries belonging to other operating systems
- **THEN** every one of those directories still exists after the run
- **AND** the run reports which ones it found and left alone

### Requirement: Existing boot entries are backed up before any write

The role SHALL take a timestamped copy of whatever boot entries exist before it writes, so a machine that stops booting can be recovered from a rescue medium without reconstructing the entries by hand.

#### Scenario: Machine with existing entries

- **WHEN** the toggle is enabled on a machine that already has boot entries on its EFI system partition
- **THEN** a timestamped backup directory holding a copy of them exists after the run
- **AND** the run names that directory in its output

### Requirement: A failed install is reported without aborting the run and without removing anything

If GRUB ends up installed with no usable boot entry, the run SHALL report it as a failure in the summary and in the exit code, SHALL leave the machine's previous bootloader in place, and SHALL NOT abort the rest of the play. The machine still boots the way it did before, and the user has not lost the software installation they also asked for.

#### Scenario: GRUB installed but no menu entry generated

- **WHEN** the GRUB installation completes but configuration generation produces no menu entry
- **THEN** the run reports an error naming the EFI system partition path and the configuration path
- **AND** the play's overall result is a failure
- **AND** `remove_distro_systemd_boot` does not run, whatever its value
- **AND** the remaining roles in the play still run

### Requirement: Applying twice changes nothing the second time

The whole feature SHALL be idempotent. A second application over a machine the first application configured MUST report no change, and MUST NOT rewrite the bootloader or regenerate its configuration.

#### Scenario: Second application

- **WHEN** the playbook is applied twice in succession with `setup_grub` enabled and nothing else altered between them
- **THEN** no task belonging to this feature reports `changed` on the second pass
