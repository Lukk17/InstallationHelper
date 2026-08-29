## Purpose

Removes systemd-boot from the current distribution once another bootloader has been installed and verified, which is the mirror image of the GRUB removal the `systemd_boot` role already performs. Covers the gate that keeps it from running on a machine with no other working boot path, and the rule that another operating system's boot entries are never touched.

## ADDED Requirements

### Requirement: The toggle does nothing when it is false

The playbook SHALL remove no bootloader binary, no loader entry, no package and no NVRAM entry when `remove_distro_systemd_boot` is false. This is the shipped default and it is hidden from both wizards' checklists.

#### Scenario: Toggle left at its default

- **WHEN** the playbook runs on any Linux machine with `remove_distro_systemd_boot` false
- **THEN** the EFI system partition still holds whatever systemd-boot files it held before
- **AND** no NVRAM boot entry is deleted

### Requirement: Removal never runs without a verified replacement bootloader

Removing the only bootloader on a machine leaves a machine that will not start. The removal SHALL run only after a replacement bootloader has been installed in the same run and verified to have at least one boot entry that names the running root filesystem.

#### Scenario: Enabled with no replacement installed

- **WHEN** `remove_distro_systemd_boot` is true and `setup_grub` is false
- **THEN** nothing is removed
- **AND** the run reports that removal was refused because no replacement bootloader was installed in this run, and names `setup_grub`

#### Scenario: Enabled with a replacement that failed verification

- **WHEN** `remove_distro_systemd_boot` is true, `setup_grub` is true, and the GRUB installation produced no usable boot entry
- **THEN** nothing is removed
- **AND** the run reports that the machine still boots through systemd-boot and says so as an error rather than as an informational message

#### Scenario: Enabled with a verified replacement

- **WHEN** `remove_distro_systemd_boot` is true and a replacement bootloader was installed in the same run and verified
- **THEN** the removal proceeds

### Requirement: Only this distribution's systemd-boot is removed

Removal SHALL be limited to the systemd-boot installation belonging to the distribution the playbook is running on, and to the loader entries that name that distribution's own machine identifier. Another operating system's EFI directory, another distribution's loader entries, and every NVRAM entry that does not point at the removed loader path MUST survive untouched.

#### Scenario: Shared EFI system partition on a multi-boot machine

- **WHEN** removal runs on a machine whose EFI system partition also holds Windows and a second Linux distribution
- **THEN** the Windows EFI directory still exists
- **AND** the second distribution's loader entries still exist
- **AND** their NVRAM entries still exist

### Requirement: NVRAM entries are matched by loader path, never by label

A firmware boot entry's label is free text that collides across operating systems. Deleting the wrong one costs the machine a boot path. Matching SHALL be done on the loader path the entry points at.

#### Scenario: Two entries with similar labels

- **WHEN** the machine's NVRAM holds an entry pointing at the systemd-boot loader path and a differently-targeted entry with a label containing the same words
- **THEN** only the entry whose loader path is the systemd-boot binary is deleted
- **AND** the run names each entry it is about to delete before deleting it

### Requirement: What is removed is stated before it is removed

The run SHALL name every file, directory, package and NVRAM entry it is about to remove, in its output, before the removal happens, so a `--check` run and a real run both leave the user able to see what was at stake.

#### Scenario: Check mode

- **WHEN** the playbook is run in check mode with the toggle enabled and a verified replacement present
- **THEN** the output names the systemd-boot EFI directory, the loader entries, the packages and the NVRAM entries that a real run would remove
- **AND** nothing is actually removed

### Requirement: Applying twice changes nothing the second time

Once systemd-boot is gone, a second run SHALL find nothing to remove and report no change, rather than failing because the files it expected are absent.

#### Scenario: Second application

- **WHEN** the playbook is applied a second time on a machine systemd-boot has already been removed from
- **THEN** no task belonging to this feature reports `changed`
- **AND** no task fails on account of the missing files
