## Purpose

Makes a Wayland session available and preferred on a Linux machine whose graphics come from the NVIDIA proprietary driver, which is the behaviour both wizards already promise under the label "System: force Wayland on NVIDIA, can break the session". Covers the kernel module parameter, the display manager's session offering, and the refusal to act on a machine that has no NVIDIA driver at all.

## ADDED Requirements

### Requirement: The toggle does nothing when it is false

The playbook SHALL make no change to any kernel command line, modprobe configuration, display manager configuration or initramfs when `toggle_wayland_nvidia` is false. This is the shipped default and every machine that does not tick the box MUST behave exactly as it does today.

#### Scenario: Toggle left at its default

- **WHEN** the playbook runs on any Linux machine with `toggle_wayland_nvidia` false
- **THEN** no file under `/etc/modprobe.d/`, `/etc/default/grub`, `/etc/kernel/`, `/etc/gdm3/`, `/etc/gdm/`, `/etc/sddm.conf.d/` or `/etc/udev/rules.d/` is created or modified by this feature
- **AND** no initramfs is regenerated on its account

### Requirement: The toggle refuses a machine with no NVIDIA driver

Enabling the toggle on a machine whose graphics are not driven by the NVIDIA proprietary driver SHALL be reported and SHALL make no change. Writing `nvidia_drm` module options onto a machine with no `nvidia` module is a change that can never take effect, and silently writing it makes the run look like it did something.

#### Scenario: Enabled on an AMD or Intel machine

- **WHEN** `toggle_wayland_nvidia` is true and the machine loads no `nvidia` kernel module and has no NVIDIA PCI display controller
- **THEN** the run reports that the toggle was skipped and names the reason
- **AND** no configuration file is written
- **AND** the run does not fail on account of the skip

### Requirement: Kernel mode setting is enabled for the NVIDIA DRM module

On a machine with the NVIDIA proprietary driver, enabling the toggle SHALL result in the `nvidia_drm` module loading with `modeset=1`, persistently across reboots and across kernel updates. The mechanism is a matter for the design, the observable requirement is the module parameter's value after a reboot.

#### Scenario: Parameter is set after a reboot

- **WHEN** the toggle is enabled, the run completes, and the machine is rebooted
- **THEN** `cat /sys/module/nvidia_drm/parameters/modeset` reads `Y`

#### Scenario: The driver already defaults it on

- **WHEN** the installed NVIDIA driver already enables modeset by default, as the 595 release branch and later do, or the distribution's own packaging already ships that default, as Arch's `nvidia-utils` has since 560.35.03-5
- **THEN** the run reports the parameter as already satisfied rather than reporting a change
- **AND** a second run reports no change either

### Requirement: A Wayland session is offered by the display manager

Enabling the toggle SHALL leave the machine's display manager offering a Wayland session for the installed desktop environment, on any display manager this project installs. Where a display manager or a distribution suppresses the Wayland session on NVIDIA hardware, that suppression MUST be lifted. Where no suppression exists, nothing is written.

#### Scenario: GDM with a suppression present

- **WHEN** the toggle is enabled on a machine whose GDM installation carries a rule or a configuration key that disables Wayland on NVIDIA
- **THEN** that suppression is lifted in a way that survives a package upgrade of the display manager
- **AND** the login screen offers the Wayland session for the installed desktop

#### Scenario: GDM with no suppression present

- **WHEN** the toggle is enabled on a machine whose GDM carries no such rule and no such key, which is the case from GDM 49 onward
- **THEN** the run reports that no display manager change was needed
- **AND** no file under `/etc/gdm3/` or `/etc/gdm/` is created or modified

#### Scenario: SDDM

- **WHEN** the toggle is enabled on a machine running SDDM
- **THEN** no session blocklist is written or removed, because SDDM has none
- **AND** the Wayland session desktop entry the desktop environment ships is present and selectable

### Requirement: The run states plainly that a reboot is required

The change to a kernel module parameter does not take effect in the running session. The run SHALL say so in terms a user can act on, and SHALL NOT claim the session is now Wayland.

#### Scenario: Run completes with the toggle enabled

- **WHEN** the toggle is enabled and the run makes any change on its account
- **THEN** the run's summary states that a reboot is required before the Wayland session is available
- **AND** the summary names the command the user can run after the reboot to confirm it, `echo $XDG_SESSION_TYPE`

### Requirement: Applying twice changes nothing the second time

The whole feature SHALL be idempotent. A second application over a machine the first application configured MUST report no change.

#### Scenario: Second application

- **WHEN** the playbook is applied twice in succession with the toggle enabled and nothing else altered between them
- **THEN** no task belonging to this feature reports `changed` on the second pass
