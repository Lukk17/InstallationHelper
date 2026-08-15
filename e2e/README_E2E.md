# End-to-end harness

> Runs the real playbook against real distributions in containers and asserts the state it produced, so a regression is caught before it reaches a machine you care about.

---

### Why this exists

Every entry in [docs/regression_ledger.md](../docs/regression_ledger.md) reached a real machine because nothing ran the playbook end to end before it shipped. A syntax check cannot tell you that a group name does not exist on Arch, and reading a diff cannot tell you that a toggle installs nothing. Both of those had happened before this directory existed.

The harness answers one question per tier, cheapest first.

| Tier | Question | Cost | Needs |
|---|---|---|---|
| 1 | Does the working tree contradict itself? | seconds | bash and ansible-playbook |
| 2 | Do the package names still exist upstream? | about a minute | curl, and gh for winget |
| 3 | Does the playbook actually produce the right machine? | 20 minutes to several hours | Docker and a Linux shell |

Tier 1 is the pre-commit gate. Tier 3 is what catches the bugs that matter, and it is slow because installing software is slow.

---

### Quick start

Run the gate. This is the one to run after any change to the playbook or the wizard.

```bash
./e2e/run.sh
```

On Windows, tier 1 is best run from Git Bash. Neither Windows shell can prove everything on its own: WSL has Ansible but the only PowerShell 7 installed here is the Microsoft Store build, whose real executable sits under `C:\Program Files\WindowsApps` where WSL can neither see nor execute it, and Git Bash has a working `pwsh` but no Ansible. Git Bash is the one that closes the gap, because `tier1/ansible_static.sh` re-executes itself inside WSL when `ansible-playbook` is missing locally. From Git Bash the gate reports 39 passes and no skips. From WSL it reports 36 and one honest SKIP on the PowerShell mapping comparison.

```bash
bash e2e/run.sh
```

From WSL, which is also where the container tiers have to run:

```powershell
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && ./e2e/run.sh"
```

One caveat on the Git Bash path: WSL interop times out intermittently while tier 3 containers are running, answering `Wsl/Service/0x8007274c`. The delegation retries three times for that reason. If it still cannot reach WSL it warns and fails rather than skipping, because a gate that goes quiet under load is the thing this harness exists to prevent.

See what scenarios exist and what each covers.

```bash
./e2e/run.sh --list
```

Run the fast container scenario, which takes roughly 20 minutes.

```bash
./e2e/run.sh --tier 3 --scenario smoke
```

Run it on a different distribution.

```bash
./e2e/run.sh --tier 3 --scenario smoke --os debian
```

Run every scenario, sequentially. Budget most of a day.

```bash
./e2e/run.sh --tier 3 --scenario all
```

---

### Long runs, and why they detach

The playbook always runs detached inside the container, writing its own log and exit code there, and the runner only watches it. So a run does not die with the shell that started it. That is not a nicety: the all-software scenario takes hours, and a run tied to a terminal session throws away the whole thing on an ordinary disconnect.

Start a scenario and get your prompt back immediately.

```bash
./e2e/tier3/container.sh e2e/tier3/scenarios/02-all-software.yaml --detach
```

Watch it, from any shell, as many times as you like.

```bash
docker exec <container-name> tail -f /work/playbook.log
```

Then verify, record and tear down, whenever it has finished.

```bash
./e2e/tier3/container.sh --collect e2e/runs/<run-id>
```

Collecting a run that has not finished yet is safe. It reports the task currently executing and exits 3 without touching anything.

One infrastructure failure is worth knowing about, because it looks like a hung scenario. `setup/` is copied into each container rather than bind-mounted, and with three scenarios running that copy occasionally fails mid-archive with `archive/tar: missed writing N bytes` followed by `unexpected EOF`. The repository reaches the queue container over a drvfs bind mount and that mount stumbles under load, at the same moments `wsl.exe` starts answering `Wsl/Service/0x8007274c`. It cost one smoke run: nothing checked the copy, the playbook launched against a `/work` that did not exist, and the container sat idle while the queue waited for an exit code that was never coming. The copy now retries three times, asserts that `site.yaml`, `all.yaml` and at least a hundred files actually arrived, and on failure removes the container and writes a `result.txt` saying the run proves nothing and must be rerun. A copy that half succeeded is the dangerous case, because the tree looks plausible and the run dies somewhere unrelated an hour later.

One more thing about the queue container, in [AGENTS.md](../AGENTS.md) but worth repeating where the harness is documented. Whatever you put after `run.sh` in the `-c` string becomes the container's exit status. Append a plain `echo` and the container reports success no matter what the sweep did: a run where three of seven scenarios failed came back `Exited (0)` for exactly that reason, and a queue whose exit code cannot be trusted cannot be alarmed on or chained behind. Capture the status into a variable first and `exit` it explicitly.

---

### What tier 1 checks, and which bug each check exists for

| Check | Guards against |
|---|---|
| [tier1/wizard_parse.sh](tier1/wizard_parse.sh) | The wizard showing a toggle in the wrong state, or dropping it, or the bash and PowerShell wizards disagreeing about which toggles exist |
| [tier1/toggle_coverage.sh](tier1/toggle_coverage.sh) | A toggle enabled with no mapping and no task, so the user asks for software and gets a successful run with nothing installed. For Windows it accepts only the three native installers, because a Windows-gated Ansible task cannot run and counting one as coverage is what hid eleven empty toggles |
| [tier1/windows_mapping.sh](tier1/windows_mapping.sh) | The PowerShell installer and `vars/Windows.yaml` disagreeing about a package, a manager or a source, a mapping with no toggle to select it, and the Windows Python mapping drifting away from `default_python` |
| [tier1/windows_npm_parity.sh](tier1/windows_npm_parity.sh) | The native npm tool list and the `ai_tools` role it replaces drifting apart, which is the same two-lists problem the two wizards already had |
| [tier1/verify_spec_parity.sh](tier1/verify_spec_parity.sh) | A capability spec understating what its run proves. All six container scenarios share one `verify.yaml`, so an assertion added there belongs in all six specs, and two had already gone unrecorded |
| [tier1/ansible_static.sh](tier1/ansible_static.sh) | The playbook failing to parse, and warning noise growing to the point where a real warning cannot be seen |

Each of these was written against a defect that had already shipped, and each was verified to fail on the code from before its fix. A check that has never been seen to fail is not a check, it is decoration.

Intended no-ops are listed with a reason in [tier1/documented_no_ops.txt](tier1/documented_no_ops.txt). Anything not listed there is treated as a defect. The check also flags stale entries, because forgiving a toggle that has since gained a real mapping would hide it breaking later.

---

### What tier 2 checks

Every package name in [setup/ansible/vars/](../setup/ansible/vars/) is resolved against the real index for its package manager. Nothing is installed and no container starts.

Covered: Arch official repositories, the Arch User Repository, Flathub, Homebrew formulae and casks, Chocolatey, and winget.

Not covered, on purpose: apt and dnf. Most of those names come from repositories the playbook adds while it runs, so resolving them without those repositories in place would report failures for packages that are fine. Tier 3 covers them by actually installing them. This gap is stated rather than hidden, because a check that quietly skips half its input is worse than no check.

winget needs an authenticated gh, because there are more winget packages than GitHub's hourly limit for anonymous requests. Without it, that one check is skipped and says so.

```bash
gh auth login
```

---

### The tier 3 scenarios

Each scenario is one configuration the wizard can actually produce. Between them they cover the wizard's whole output space, which is the desktop environment choice crossed with the three software paths.

| Scenario | Wizard path it reproduces |
|---|---|
| defaults | Step 2 "defaults", desktop environment "skip". What pressing Enter through the wizard gives you, and what `setup.sh --non-interactive` runs |
| all-software | Step 2 "customise", then select-all in the checklist |
| kde-full | Desktop environment "kde", action "full" |
| gnome-full | Desktop environment "gnome", action "full" |
| live-profile | Step 2 "profile", the Linux Live entry. The path a USB or live-session install takes |
| kde-configure-only | Desktop environment "kde", action "configure". The only combination where the configure tasks cannot assume their own install step just ran |
| smoke | Not a wizard path. The fast gate, limited to toggles that sit on top of a defect this project has actually shipped |

The all-software toggle list is generated at run time from [group_vars/](../setup/ansible/group_vars/) rather than written into the scenario file, so a newly added toggle is covered with no edit here. The exact list used is written into the run directory.

---

### What a container cannot test

[tier3/container_limits.yaml](tier3/container_limits.yaml) turns off the toggles a container provably cannot satisfy, and the runner prints that list on every run so no scenario is mistaken for full coverage. The list is short on purpose: hibernation, bootloader installation, Waydroid, VirtualBox, VMware and Snapper, all of which need hardware or a kernel facility that belongs to the host.

Everything merely slow or awkward stays enabled. Pre-suppressing something because it might fail is how a real defect becomes a silent gap, which is the failure this whole directory exists to stop.

Two consequences worth knowing before reading a failure as a bug. Kernel modules never build, because `/usr/lib/modules` belongs to the host, so anything using DKMS reports missing headers. And there is no login session, so tasks that need a live user D-Bus take their documented fallback path instead.

---

### Which distributions, and why Ubuntu is separate from Debian

| `--os` | Base image | Notes |
|---|---|---|
| arch | archlinux:base | Rolling, so there is no version to pin. The only one exercised so far |
| debian | debian:trixie | Debian 13, current stable |
| ubuntu | ubuntu:26.04 | Latest LTS |
| fedora | fedora:44 | Current stable. Tag 45 exists but is still branched |

Ansible reports Ubuntu as the Debian family, so both load the same [vars/Debian.yaml](../setup/ansible/vars/Debian.yaml) and both take the same branch in every task gated on `os_family`. That is exactly why they need separate images: the shared branch is only correct if the package names hold on both, and they do not. `ubuntu-desktop` and `language-pack-kde-pl` do not exist in Debian, while `qt6-style-kvantum` does not exist in Ubuntu 24.04, and all three are named in the desktop environment roles' Debian branch. One image would have hidden half of that.

Base image tags are pinned rather than tracking `latest`, because a moving base means the harness quietly starts testing a different system than the one you last got a result from.

---

### Windows

Windows has its own entry point, driven from Windows rather than from WSL.

```powershell
pwsh e2e/tier3/Invoke-WindowsE2E.ps1
```

Skip the Chocolatey bootstrap for a quick logic-only pass.

```powershell
pwsh e2e/tier3/Invoke-WindowsE2E.ps1 -SkipSlow
```

It is separate because Docker Desktop serves one container platform at a time, and switching to Windows containers turns the Linux daemon off. Every Arch, Debian, Ubuntu and Fedora scenario stops working until you switch back, so finish or stop those first. `run.sh --os windows` says all of this rather than failing on a missing Dockerfile.

What it tests: the logic in [setup/windows/WindowsSoftware.ps1](../setup/windows/WindowsSoftware.ps1) on a clean Windows with nothing installed, which is the state a real user starts from and the one a developer machine can never reproduce. That is the YAML parsing, the resulting install plan, the winget resolution failure path, and the Chocolatey bootstrap. The suite is [tier3/windows/WindowsSoftware.Tests.ps1](tier3/windows/WindowsSoftware.Tests.ps1), driven by Pester 5, which the image installs at build time so a run needs no network of its own.

What it cannot test, and does not claim to: any winget installation. winget ships as an MSIX package and needs the AppX deployment subsystem, which Server Core and Nano Server do not have. That is 77 of the 83 Windows mappings. Chocolatey works because it is only PowerShell and NuGet, which covers the remaining 6. There is no way around this in a container, so winget installation needs a real Windows machine or a hosted runner. It also cannot test the wizard's own interface, because `Out-ConsoleGridView` needs a real console.

The base image is `mcr.microsoft.com/windows/servercore:ltsc2025`, which is build 26100 and the closest published Server Core to this project's Windows 11 host at 26200. The driver asks for Hyper-V isolation rather than process isolation, because process isolation wants the container and host builds to match closely and these do not.

---

### macOS

Cannot be tested this way at all. A container shares the host kernel, so a Darwin container cannot exist on a Linux or Windows kernel. That is a design fact rather than a licensing quibble, and virtualising macOS is separately restricted by Apple to Apple hardware. macOS needs real hardware, or a hosted runner on real hardware.

---

### Run records

Every tier 3 run writes a directory under `e2e/runs/`, which is gitignored.

| File | Contents |
|---|---|
| effective-vars.yaml | The exact variable file the playbook received, including everything generated |
| playbook.log | The full playbook output |
| verify.log | The verification output |
| result.txt | Exit codes, the play recap, and every error line |

Keep the run directory when you report a failure. The effective variable file is the only record of what was actually asked for, and reconstructing it afterwards is guesswork.

---

### Adding a check

Put it in the tier that answers its question most cheaply, source [lib/common.sh](lib/common.sh), use `pass` and `fail` so one failure does not hide the rest, and end with `finish`. Never end a check script by letting the last command's status fall out, because a harness that reports failures and exits zero reads as a pass to everything that calls it.

Then prove it. Copy the tree, reintroduce the defect, and confirm the check fails. If you cannot make it fail, it is not testing what you think.

---

### Documentation map

| Doc | What's in it |
|---|---|
| [docs/regression_ledger.md](../docs/regression_ledger.md) | Every regression this project has suffered, and the prevention checklist this harness mechanises |
| [AGENTS.md](../AGENTS.md) | The mandatory gate, and the rest of the agent contract |
| [setup/README_SETUP.md](../setup/README_SETUP.md) | Running the playbook for real |
| [setup/ansible/tags.md](../setup/ansible/tags.md) | Partial runs by tag, useful when triaging a scenario failure |
