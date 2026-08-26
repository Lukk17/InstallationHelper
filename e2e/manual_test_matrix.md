# Manual test matrix

What no pipeline in this repository can prove, where to prove it instead, and how to tell whether it worked.

Everything here is something the automated gates deliberately do not cover, with the reason stated. Nothing on this page is a wish list. Each row exists because a container, a hosted runner, or both, physically cannot answer the question, and the alternative to testing it by hand is not testing it at all.

The pipelines cover a great deal: tier 1 is a static gate that runs in seconds, tier 2 resolves package names against live repositories, and tier 3 runs the real playbook inside a systemd container on six Linux distributions across eight scenarios, plus real installs on hosted macOS and Windows runners. Read [README_E2E.md](README_E2E.md) for what those do. This page is the complement: the residue.

---

### How to read a row

Every row answers four things.

1. What is untested.
2. Why the automation cannot reach it, as a fact about the environment rather than an excuse.
3. Where to test it: a real machine, a virtual machine, or specifically one with certain hardware.
4. How to tell it worked, meaning a command whose output you can read rather than an impression.

Where a virtual machine is enough, the row says so. A virtual machine runs its own kernel, which is exactly what a container does not have, so most of the kernel-facility rows are covered by a plain VirtualBox or QEMU guest. Rows that need real hardware say that instead, and a VM cannot substitute.

---

### Before you start: the three profiles worth having

Testing by hand is only cheap if the machine is disposable. Keep these, and snapshot each one immediately after a clean install and before running anything from this repository.

1. A UEFI virtual machine with an EFI system partition and a btrfs root, with a swap partition at least as large as its memory. That one machine covers bootloader, hibernation and Snapper in a single pass, which is three of the six suppressed toggles.
2. A virtual machine with nested virtualisation enabled in the hypervisor. That covers VirtualBox, VMware and Waydroid, which all build or load kernel modules.
3. Your own physical machine, which is the only place the hardware rows can be answered at all.

Snapshot before every run. The playbook rolls nothing back on failure by design, and a snapshot turns a destructive test into a two-minute retry.

---

### Cross-platform, every operating system

| What is untested | Why automation cannot reach it | Where | How to tell it worked |
|---|---|---|---|
| The wizard's interactive interface | `Out-ConsoleGridView` on Windows and the bash checklist both need a real console with a terminal attached. Every automated run drives them through flags instead, so the code paths a human touches are never exercised | Any real machine | Run `setup/setup.sh` or `setup/setup.ps1` with no arguments, tick boxes, and confirm the resulting run installs exactly what you ticked and nothing else |
| JetBrains Toolbox and the five IDEs behind it | Suppressed in every container by [tier3/container_limits.yaml](tier3/container_limits.yaml). Each IDE is roughly a gigabyte, Toolbox drives installs through a background service that expects a desktop session, and a licensed product wants an account logged in | Real machine or a VM with a desktop | After the run, open Toolbox and confirm idea, pycharm, webstorm, datagrip and rider are listed as installed rather than as available |
| A second run over a machine a human has since changed | The idempotency scenario reruns over a machine only the playbook has touched. A real machine drifts: packages get removed by hand, config files get edited, versions move | Any machine you already provisioned | Run the playbook again a week later and read the change count. Anything reported changed should have a reason you can name |
| Any interaction with a graphical session | No container has a display, and hosted runners have no interactive session | Real machine or a VM with a desktop | See the desktop environment section below |

---

### Linux, every distribution

These are the toggles [tier3/container_limits.yaml](tier3/container_limits.yaml) turns off on every distribution, because each needs a kernel facility or a block device that belongs to the host. A virtual machine has its own kernel and its own disks, so a VM answers all of them.

| Toggle | Why no container | Where | How to tell it worked |
|---|---|---|---|
| `setup_systemd_boot`, `setup_grub`, `remove_distro_grub`, `remove_distro_systemd_boot` | Needs an EFI system partition and a real block device to install a bootloader onto | UEFI virtual machine, snapshot first | Reboot. The machine has to come up. Then `bootctl status` for systemd-boot, or `efibootmgr -v` to see which loader the firmware will run |
| `setup_hibernate` | Needs a real swap device and a `resume=` parameter on the running kernel | Virtual machine with a swap partition at least as large as its memory | `systemctl hibernate`, then power the guest back on and confirm the session came back rather than a fresh boot. Check `cat /sys/power/resume` names the swap device |
| `install_snapper` | Needs a btrfs filesystem to snapshot. A container's overlayfs is not one | Virtual machine with a btrfs root | `snapper -c root list` shows a timeline, and `snapper -c root create` then `snapper -c root delete <n>` both succeed |
| `install_waydroid` | Needs the binder and ashmem kernel modules, which belong to the host kernel | Virtual machine, or real machine | `waydroid status` reports the session running, and `waydroid show-full-ui` opens Android |
| `install_virtualbox` | Builds kernel modules against the running kernel, which in a container is the host's | Real machine, or a VM with nested virtualisation | `lsmod \| grep vbox` lists the modules, and a guest actually boots |
| `install_vmware` | Same, and the installer wants a real display | Real machine, or a VM with nested virtualisation | `vmware --version`, and a guest boots |

---

### Linux, hardware that no runner has

No hosted runner and no container has any of this attached. These are the rows a virtual machine cannot help with either.

| Toggle | What needs the hardware | Where | How to tell it worked |
|---|---|---|---|
| `install_openrazer` | The kernel module has to build against the running kernel and then bind to a real Razer device. On Fedora it is additionally suppressed by [tier3/container_limits.fedora.yaml](tier3/container_limits.fedora.yaml), so on that distribution nothing anywhere verifies the mapping, the `plugdev` device group or the daemon | Machine with a Razer device, all four Linux families separately | `systemctl status openrazer-daemon` is running, `groups` lists you in the device group, and `polychromatic-cli --list-devices` names the device |
| `install_polychromatic` | Installs fine anywhere, but proves nothing without a device behind it | Machine with a Razer device | The device appears and an effect applied through the interface visibly changes the lighting |
| `install_lm_sensors` | Reads real sensor chips | Real machine | `sensors` prints temperatures rather than nothing |
| `install_hardinfo` | Enumerates real hardware | Real machine | The report names your actual processor and memory |
| `install_greenenvy` | An NVIDIA overclocking front end, and needs an NVIDIA card | Machine with an NVIDIA card | It opens and shows the card rather than reporting none |
| `install_gputest` | Runs a real graphics benchmark against a real driver | Real machine with a display | A test runs and reports a score |
| `install_ledger_live`, `install_trezor_suite` | The applications install anywhere. What is untested is the udev rules that let a non-root user talk to the device | Machine with a Ledger or Trezor plugged in | Plug the device in and confirm the application sees it without sudo. If it does not, the udev rules did not land |
| `install_balena_etcher` | Writing an image needs a real removable device. On Arch it is a documented no-op because the AUR package conflicts with the nodejs version other AUR packages need, so install the AppImage by hand there | Real machine with a USB stick | Write an image and boot from it |

---

### Linux, per distribution

| Distribution | What is untested there specifically | Where | How to tell it worked |
|---|---|---|---|
| Fedora | OpenRazer entirely, per the file above. The DKMS scriptlet fails an RPM transaction in a container and takes unrelated packages down with it, so the whole toggle is suppressed on Fedora only | Real Fedora machine with kernel headers and a Razer device | As the OpenRazer row above |
| CachyOS | `install_steam`, suppressed by [tier3/container_limits.cachyos.yaml](tier3/container_limits.cachyos.yaml). The v3 repository index names `lib32-glibc` and `lib32-gcc-libs` builds the content delivery network answers 404 for. That is upstream and not about this repository | Real CachyOS machine, and re-measure the two URLs in that file first | `steam` launches. If the repository has been fixed, delete that file and the CachyOS cells should pass |
| Pop!_OS | System76 publishes no container image, so the container is Ubuntu with System76 repositories added. Nothing in CI proves anything about System76's own packages, the recovery partition, or the System76 driver and firmware daemons | Real Pop!_OS installation | `system76-power profile` answers, and `apt policy` shows packages coming from the System76 repositories |
| Arch and CachyOS | Whether the AUR helper's builds still work when the AUR web endpoint is rate limiting. CI hit exactly that on 2026-08-24 and lost `google-chrome` to it | Real Arch machine, on a normal home connection | Every AUR package in the software set ends up in `pacman -Q` |
| Ubuntu and Debian | Snap is installed in the container but a confined snap wants systemd and a seccomp profile that a container gives grudgingly | Real machine | `snap list` shows the packages, and each one launches |
| All four families | Secure Boot. Nothing in this repository signs a kernel module, and OpenRazer, VirtualBox and VMware all build one | Machine with Secure Boot on | Either the module loads because it was signed and enrolled, or you find out here rather than after a reboot on a machine you care about |

---

### Linux desktop environments

The `kde-full`, `gnome-full` and `kde-configure-only` scenarios run in containers, which have no display. They prove the packages install and the configuration files are written. They cannot prove a desktop starts, and that is the part a person notices.

| What is untested | Where | How to tell it worked |
|---|---|---|
| That the session actually starts | VM with a desktop, or a real machine | Log in. The session comes up rather than dropping back to the display manager |
| That the KDE profile applies | Real machine, because a profile is about how it looks | `konsave -a lukk_desktop_profile`, log out and back in, and the panels, theme and shortcuts are the ones you saved |
| GNOME extensions and dconf settings | VM with a desktop | `gsettings get` returns the values the role wrote, and the extensions are enabled in the interface rather than merely present on disk |
| Display scaling, multiple monitors, fractional scaling | Real machine with two monitors | Windows land where you expect and text is the right size on both |
| Wayland against X11 | Both, separately | The session type is what you chose, `echo $XDG_SESSION_TYPE`, and the applications you use daily run under it |

---

### Windows

The four Windows cells run on `windows-latest`, which is Windows Server 2025 on an Azure virtual machine. Two consequences, and both are large: it is Server rather than client, and it has no hardware of its own. Most of what follows is one of those two.

The local answer to the first is Windows Sandbox, which is client Windows at this machine's own build. How to run it is at the end of this section.

| What is untested | Why | Where | How to tell it worked |
|---|---|---|---|
| Every client-edition package | The runner is Windows Server. `partition_wizard` carries `client_only: true` because MiniTool ships the Free edition for client Windows only and its installer refuses Server before it starts, so the wizard skips it with that reason | Real Windows 11 machine | The wizard reports it installed rather than skipped, and the application opens |
| Anything that refuses an administrator context | The cells pass `-AllowAdministrator` so they can run unattended. `spotify` carries `user_context: true` for exactly this | Real Windows 11 machine, wizard started as your normal user | It installs rather than being skipped |
| `nvidia_app` | The NVIDIA App is the driver and GPU control centre. No hosted runner of any kind has an NVIDIA adapter, so the wizard asks `Win32_VideoController` and skips when the answer is empty | Machine with an NVIDIA card | The wizard installs it, and the NVIDIA App opens and sees the card |
| The seven Microsoft Store product identifiers | The Store itself is needed, and it needs a signed-in account | Real Windows machine, signed in | Each application appears in the Start menu and launches |
| `enable_hyperv` | A hosted runner is already a virtual machine, so enabling a hypervisor inside it is a nested-virtualisation question rather than the feature | Real Windows 11 Pro machine | `Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V` reports enabled, and a guest boots after the reboot it asks for |
| `setup_wsl` end to end | The cells register a distribution to have one, which is not the same as the wizard bootstrapping WSL on a machine that has none | Real Windows machine with no WSL at all | `wsl --list --verbose` shows the distribution, and `ansible-playbook --version` answers inside it |
| `set_custom_wallpaper` | Needs a desktop session to change | Real machine | Look at the desktop |
| Everything hardware | `install_hwmonitor`, `install_hwinfo`, `install_crystaldiskinfo`, `install_crystaldiskmark`, `install_msiafterburner`, `install_galaxy_buds`, `synapse` | Real machine with the hardware | Each application opens and reports your actual devices |
| The reboot the run asks for | No automated run reboots | Real machine | Reboot when asked, then rerun the wizard and confirm it reports everything already present rather than redoing work |

---

#### Windows Sandbox is the local route, and there is no local container

Every Windows install you test by hand on this machine goes through Windows Sandbox. There is no Windows container tier any more: one existed until 2026-08-26 and it was retired, because a Windows container is always Windows Server, Server Core has no AppX subsystem, and winget needs it, so 80 of the 89 Windows mappings could not install in it at all.

Windows Sandbox is a throwaway desktop built from the files of the Windows already running on this machine. Same build, same edition, nothing to download, and the whole thing is destroyed when the window closes. That makes it strictly better than the container for this: it is client Windows, so the packages a Server runner has to skip install properly, winget works because the AppX subsystem is there, and it has a desktop, so the interactive checklist can be clicked through.

It needs Windows 10 or 11, Pro or Enterprise, and the feature turned on once. This asks for a reboot, and it is the one command here that changes the machine, so run it yourself from an elevated PowerShell.

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All
```

Then start a sandbox for this repository. The launcher writes the configuration from where it sits, so the paths are right on any checkout, and it starts nothing else.

```powershell
pwsh e2e/windows-sandbox/Invoke-WindowsSandbox.ps1
```

Write the configuration and look at it without starting a sandbox.

```powershell
pwsh e2e/windows-sandbox/Invoke-WindowsSandbox.ps1 -ConfigOnly
```

Give it more memory and prepare the command for the whole software set rather than the defaults.

```powershell
pwsh e2e/windows-sandbox/Invoke-WindowsSandbox.ps1 -Software all -MemoryInMB 12288
```

The repository is mapped read only at `C:\repo` inside the sandbox, so a run cannot change the tree it is testing. A second folder is mapped read write at `C:\out`, which is `e2e/runs/windows-sandbox` out here, and that is the only way anything survives the sandbox closing.

At logon the sandbox runs [windows-sandbox/Initialize-Sandbox.ps1](windows-sandbox/Initialize-Sandbox.ps1), which does the two things a fresh sandbox needs and nothing more. It installs winget from the winget-cli release assets, because a sandbox has no Microsoft Store to get it from, and then PowerShell 7 through winget, because `setup.ps1` requires 7 and a sandbox ships 5.1. Then it prints the wizard command and stops. Nothing from the software set installs on its own: that is an hour of downloading and it should be a decision.

The command it prints is this one, and `-AllowAdministrator` is not optional in there, because the sandbox user is an administrator and the wizard refuses an elevated run without it.

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' C:\repo\setup\setup.ps1 -NonInteractive -AllowAdministrator -Software defaults
```

Drive the checklist by hand instead, which is the one thing no automated run anywhere exercises.

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' C:\repo\setup\setup.ps1 -AllowAdministrator
```

Keep the evidence before you close the window, because the machine and everything on it is gone the moment you do.

```powershell
Copy-Item $env:USERPROFILE\installation_verify.log C:\out\
```

| What a sandbox answers | What it cannot |
|---|---|
| The whole winget path, all 80 mappings, on client Windows | The seven Microsoft Store product ids, which need the Store and a signed-in account |
| The client-edition packages the Server runner skips, `partition_wizard` among them | Anything wanting a reboot. Restarting a sandbox destroys it, so the optional features cannot be carried to the end |
| The Chocolatey path and the custom installers, Java, Node, Flutter, the Android SDK, Gridcoin, Razer Cortex | `setup_wsl` and the Ansible-inside-WSL phase. WSL2 needs a hypervisor and a sandbox has no nested virtualisation |
| The interactive checklist, on a real desktop | `enable_hyperv`, for the same reason |
| The verification phase, and the cache reclaim between the packages and the SDKs | Every hardware row. A sandbox has no devices of its own |
| Repeated clean runs, because every start is a fresh machine | Anything about your real machine's state, which is the point of it |

One honest caveat: this route has not yet been run end to end. The steps come from the documented behaviour of Windows Sandbox, of the winget-cli release assets and of the wizard's own flags, each of which was checked rather than remembered, but nobody has watched the whole thing install yet. The first person to run it should say what actually happened, and anything surprising belongs in [../docs/regression_ledger.md](../docs/regression_ledger.md).

---

### macOS

There is no macOS container and there cannot be one: a container shares the host kernel, so a Darwin container cannot exist on a Linux or Windows kernel, and virtualising macOS is separately restricted by Apple to Apple hardware. The three hosted macOS cells are the only automated coverage, and they run on a machine with no display, no signed-in Apple account and no hardware.

| What is untested | Why | Where | How to tell it worked |
|---|---|---|---|
| Gatekeeper and first launch of every cask | A cask installs an application bundle. Whether macOS lets it run is a separate question, decided at first launch by Gatekeeper and notarisation | Real Mac | Open each application once. Any that need a right-click and Open, or a Privacy and Security approval, are the ones to note |
| Anything from the Mac App Store | Needs a signed-in Apple account | Real Mac, signed in | The applications appear in Launchpad |
| `setup_karabiner` | Karabiner needs an approved system extension and Input Monitoring permission, both of which need a human at the machine | Real Mac | A remapped key produces the new character, and Karabiner is listed under Privacy and Security |
| `setup_finder_defaults` | The settings are written with `defaults write`, which a headless run can do, but whether Finder picks them up needs a Finder | Real Mac | Restart Finder and confirm the settings took |
| `install_virtualbox`, `install_utm` | Both need a kernel extension or the Hypervisor framework, and both need to actually boot a guest | Real Mac | A guest boots |
| Apple silicon against Intel | The runners are one architecture. Homebrew installs to `/opt/homebrew` on Apple silicon and `/usr/local` on Intel, and casks differ | Both, if you have both | The environment variables and shell profile point at the right prefix |
| Full Disk Access and other privacy prompts | Every one needs a human to click | Real Mac | The applications that need it work rather than silently failing |

---

### What a virtual machine can and cannot substitute for

Worth being exact, because "test it in a VM" is not always true.

A virtual machine does give you: its own kernel, so kernel modules build and load. Its own disks and partition table, so bootloaders and filesystems are real. Its own firmware, so UEFI and Secure Boot behave. Its own swap, so hibernation is real. A display, so desktop environments start.

A virtual machine does not give you: any physical device, so every hardware row above stays unanswered. Real graphics, so the graphics rows are at best partial. Nested virtualisation unless the hypervisor is configured for it, and without that VirtualBox, VMware and Hyper-V inside the guest are untestable. Apple hardware, so macOS is out of reach entirely.

---

### When to work through this page

Not on every change. The pipelines exist so that most changes need nothing here. Work through the relevant section when:

1. You changed a role that touches one of the suppressed toggles. The row tells you what the container did not run.
2. You are about to use the playbook on a machine you care about, especially a bootloader or filesystem row, where the failure mode is a machine that does not boot.
3. A distribution moved. Rolling releases move under the harness, and the CachyOS row is a live example of an upstream repository being inconsistent with itself.
4. You added hardware. The Razer, NVIDIA and hardware wallet rows are only ever answered by the machine that has the device.

Record what you ran and what happened in [docs/regression_ledger.md](../docs/regression_ledger.md) if it found something. A manual test that found a defect and was not written down gets rediscovered the hard way.

---

### Documentation map

| Doc | What's in it |
|---|---|
| [README_E2E.md](README_E2E.md) | The harness itself, the three tiers, and what to run when you change something |
| [run_durations.md](run_durations.md) | How long every cell of the sweep actually takes on a hosted runner, measured |
| [testing/README.md](testing/README.md) | The per-scenario specifications the harness checks itself against |
| [../docs/regression_ledger.md](../docs/regression_ledger.md) | Every regression this project has suffered, and the prevention checklist |
| [../AGENTS.md](../AGENTS.md) | The mandatory gate, and the rest of the agent contract |
| [../setup/README_SETUP.md](../setup/README_SETUP.md) | Running the playbook for real |
