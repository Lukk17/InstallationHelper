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
| 3 | Does the playbook actually produce the right machine? | 90 minutes to 5 hours by declared ceiling | Docker, and a shell that can reach its daemon |

Tier 1 is the pre-commit gate. Tier 3 is what catches the bugs that matter, and it is slow because installing software is slow.

---

### Quick start

Run the gate. This is the one to run after any change to the playbook or the wizard.

```bash
./e2e/run.sh
```

On Windows, tier 1 is best run from Git Bash, and as of 2026-08-20 that is the shell where every check passes. Measured the same day, WSL comes back with one failure and three skips, and neither is about the tree under test. The failure is `setup/manifests/generate.py` calling `Path.read_text(newline="")`, a keyword that only exists from Python 3.13, against WSL's Python 3.12.3, so the manifest comparison cannot run there at all. The interpreter search in `setup/pinned_values/pinned_values.sh` accepts anything from 3.11 upward, which is the floor `tomllib` needs rather than the floor the generator needs, so the check finds an interpreter and then crashes in it. The three skips are the PowerShell halves, which need the Store `pwsh` alias to run through interop and it did not answer that time. Both were reproduced against a clean worktree at `HEAD`, so they are properties of this machine and of `setup/`, not of any change. Each shell reaches what it is missing a different way. Git Bash has `pwsh` and no Ansible, so the two checks that need Ansible, `tier1/ansible_static.sh` and `tier1/os_family_derivation.sh`, re-execute themselves inside WSL when `ansible-playbook` is missing locally, through the helper they share, `tier1/wsl_delegate.sh`. WSL has Ansible and no native PowerShell, and reaches the Windows `pwsh.exe` through interop, which was measured rather than assumed: the only PowerShell 7 here is the Microsoft Store build, whose `WindowsApps` entry is an app-execution alias, and it does run from WSL. That is why `tier1/pwsh_probe.sh` decides by running a candidate rather than by finding it on PATH, and why it still reports SKIP rather than a pass when nothing runs. Whether an alias works from WSL is a property of the Windows build, so treat it as something to re-measure rather than as a fact this document owns. The absolute number of checks is not written down here on purpose, because it changes with every check added and a stale total in prose is read as the definition of the gate's size.

```bash
bash e2e/run.sh
```

The same gate from WSL:

```powershell
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && ./e2e/run.sh"
```

One caveat on the Git Bash path: WSL interop times out intermittently while tier 3 containers are running, answering `Wsl/Service/0x8007274c`. The delegation retries three times for that reason. If it still cannot reach WSL it warns and fails rather than skipping, because a gate that goes quiet under load is the thing this harness exists to prevent.

The container tiers run from either shell too. What used to block Git Bash was the harness rather than Docker: the guard asked `uname -s`, refused anything that was not Linux, and sent the reader to WSL whether or not WSL could reach a daemon. It now asks whether a daemon answers and whether this shell can spell a host path for it, which is the question that was always meant, and from Git Bash both answers are yes as long as Docker Desktop is running.

Whether WSL can reach the daemon is a separate question with its own answer, and it is worth measuring rather than remembering. It depends on Docker Desktop having integration enabled for that distribution. Measured on 2026-08-20, the Ubuntu distribution has `/var/run/docker.sock` and `docker info` reports server 29.3.1, so tiers 2 and 3 run from there as well. That integration has been off before, and while it is off there is no socket inside WSL at all and the guard says so by name.

```bash
bash e2e/run.sh --tier 2
```

```bash
bash e2e/run.sh --tier 3 --scenario defaults --os debian
```

Nothing has to be prefixed or exported to make those work. Under MSYS the shell rewrites any argument that looks like an absolute POSIX path before a Windows executable sees it, which turns `-v /sys/fs/cgroup:/sys/fs/cgroup:rw` into `mkdir C:\Program Files\Git\sys: Access is denied` and `-w /work/setup/ansible` into `Cwd must be an absolute path`. So `lib/common.sh` wraps `docker` in a function that disables the rewriting for the whole command, and every argument that names a location on this machine, rather than one inside a container, goes through its `host_path` helper and comes out as a Windows path. That is the harness's business, not the caller's, and it is why the commands above are the same ones a Linux shell runs.

See what scenarios exist and what each covers.

```bash
./e2e/run.sh --list
```

Run the cheapest container scenario. There is no fast one: defaults carries a 180 minute ceiling, which is the honest cost of proving anything inside a container, and it is the configuration a user actually gets.

```bash
./e2e/run.sh --tier 3 --scenario defaults
```

Run it on a different distribution.

```bash
./e2e/run.sh --tier 3 --scenario defaults --os debian
```

Run every scenario, sequentially. Budget most of a day.

```bash
./e2e/run.sh --tier 3 --scenario all
```

---

### CI matrix sweep vs local runs

The eight scenarios above cross five Linux distributions, which is 40 combinations. Nobody runs all 40 on one machine, so the harness is split across two places that prove different things.

[.github/workflows/e2e-matrix.yml](../.github/workflows/e2e-matrix.yml) runs the full sweep: every scenario against every distribution, dispatch-only, on GitHub's own standard runners. Public repositories get those for free, and each cell is an isolated virtual machine with its own 4 processors, 16 GB of memory and 14 GB of free disk, so 48 jobs do not contend with each other for host resources the way `--jobs` on a local machine does. Those 48 are 48 separate jobs rather than one matrix, each calling [.github/workflows/e2e-linux-cell.yml](../.github/workflows/e2e-linux-cell.yml), because GitHub's run graph collapses a matrix into a single node that names neither the distribution nor the scenario. It calls the exact same harness this document describes, one `e2e/run.sh --tier 3 --scenario <name> --os <distro>` per cell, so nothing about the harness itself is different in CI.

Local Docker runs, the ones this document shows above, stay scoped to one scenario on one platform or distribution at a time. That is the right shape for developing a change: fast feedback on the distribution and scenario a change actually touches, without waiting on 39 others.

What each side proves, and does not:

| | Proves | Does not prove |
|---|---|---|
| CI matrix sweep | The full cross product passes on GitHub's own infrastructure, including a distro/scenario pairing nobody happened to run locally | Correctness on the hardware you actually deploy to. A hosted runner's disk, memory and privileged-container behaviour differ from a personal Docker Desktop or WSL setup, and the sweep has not been observed to catch a defect that a local run would have missed, because it has not run yet |
| Local run | The harness works on your actual machine, against your actual Docker setup, for the one scenario and distribution you are actively changing | The other 39 combinations still pass, unless you run them too |

Dispatch the sweep from the Actions tab, or narrow it to one scenario or one distribution from the same form.

```bash
gh workflow run e2e-matrix.yml -f scenario=defaults -f distro=debian
```

Run everything.

```bash
gh workflow run e2e-matrix.yml -f scenario=all -f distro=all
```

---

### What to run when you change something

The complete map. Tier 1 is not optional for anything under `setup/`, and the rest of this table
says what else the change owes. The last column is the part that matters most when a run comes back
green: what that run still does not tell you.

| If you changed | Run | What it still cannot prove |
|---|---|---|
| a toggle in `group_vars/*.yaml` | `./e2e/run.sh` | that the application behind the toggle installs, only that something is wired to install it |
| a mapping in `setup/ansible/vars/*.yaml` | `./e2e/run.sh` then `./e2e/run.sh --tier 2` | that the package installs cleanly, only that the name resolves in that distribution's index |
| a package name written directly into a role task | `./e2e/run.sh --tier 2` | the same, and nothing at all for a name built at run time from a variable |
| a pinned value in `setup/pinned_values/pinned_values.toml` | `./e2e/run.sh` then `./e2e/run.sh --tier 2` | that the pinned version is the right version, only that it resolves and that its download location answers |
| the pinned values reader or any of its adapters | `./e2e/run.sh`, then `pwsh e2e/tier3/Invoke-WindowsE2E.ps1`, then `--tier 3 --scenario defaults` | nothing about macOS, which has no container tier |
| anything in `roles/` touching groups, systemd units or per-distribution behaviour | `./e2e/run.sh --tier 3 --scenario defaults` on arch, debian, ubuntu and fedora | anything needing a graphical session, a real kernel module, or hardware |
| a task's `changed_when`, a `creates` guard, or anything about whether a task reports work it did not do | `./e2e/run.sh --tier 3 --scenario idempotency` | whether the task is idempotent on any distribution other than the one you ran, because a guard that is right on apt can be missing entirely on pacman |
| a rescue, a `failed_when`, an `ignore_errors`, `any_role_failed`, the callback plugin's failure rendering, or `verify_install.yaml`'s assertions | `./e2e/run.sh --tier 3 --scenario forced-failure` | that a real defect would be caught, only that a failure which does happen is reported in all four places, and it is the cheapest container scenario so there is no excuse for skipping it |
| the desktop environment roles | `--scenario kde-full` and `--scenario gnome-full` | that the desktop actually starts, since no container has a display |
| `profiles/linux_live.yaml` | `--scenario live-profile` | that a real live USB behaves the same, since the container has a writable root |
| `setup/setup.sh` | `./e2e/run.sh`, then any one `--tier 3` scenario end to end | the interactive screens, which need a terminal no test has |
| `setup/setup.ps1` or anything in `setup/windows/` | `pwsh e2e/tier3/Invoke-WindowsE2E.ps1` | 82 of the 89 Windows mappings, because winget ships as an MSIX package and Server Core has no AppX subsystem |
| `setup/ansible/verify_install.yaml` | `./e2e/run.sh`, then `--tier 3 --scenario forced-failure`, then any one passing scenario | nothing, if the gate and both scenarios pass, this is the best covered file in the repository. The forced-failure scenario is the half that matters: it proves the play refuses over a broken machine, which no passing scenario can show |
| a tier 1 check, or anything under `e2e/` | prove the check fails against a copy of the tree carrying the defect, then `./e2e/run.sh` from Git Bash and from WSL | that the check is testing the thing rather than its own implementation, which only the failure proof shows |
| a distribution Dockerfile, or a new distribution | `--tier 3 --scenario defaults --os <name>` | that the distribution's derivatives behave the same, since only the named one runs |
| anything that only affects macOS | `./e2e/run.sh` and `./e2e/run.sh --tier 2` | everything that executes, because a Darwin container cannot run on a Linux or Windows kernel and the only executing macOS test is the `macos` target of the dispatch workflow |
| `.github/workflows/e2e-manual.yaml`, named "E2E - single platform" in the Actions tab | dispatch it from the Actions tab, one target platform at a time | nothing locally |
| `.github/workflows/e2e-matrix.yml`, named "E2E - test software install and configuration on every OS" in the Actions tab | dispatch it from the Actions tab, the full sweep or narrowed to one scenario or one distribution | nothing locally |
| `homelab/` or `local-dev/` | nothing, and that is the honest answer | everything, no tier covers either directory today |

Three rules that are easy to miss.

There is no cheap container row. Most rows that name a scenario name defaults, at a 180 minute ceiling rather than the 45 the removed smoke scenario declared, and the two that name something else name it because that scenario asks a question defaults cannot: forced-failure is the cheapest of them, measured at 46 minutes on debian against a 90 minute ceiling, and it is still not a pre-commit gate. The smoke scenario is gone because every toggle it enabled was already true in defaults, so it was the same test with most of the toggles taken away, and a 20 to 30 minute run was never cheap enough either. Tier 1 is the thing that runs in seconds.

A change that touches more than one row owes every row it touches. A pinned value that is also read by a role task is both the fourth row and the third.

A tier that cannot run is not a tier that passed. The container tiers need a Docker daemon that answers and a shell that can hand it a host path, which `require_docker_host` checks in that order and names whichever one is missing. From Windows, Git Bash satisfies both whenever Docker Desktop is running. WSL satisfies both only when Docker Desktop has integration enabled for that distribution, and with it off there is no socket in there at all, so the guard refuses and points at the other shell. Either way the correct response is to run the tier from a shell where it works, not to record the change as verified.

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

One infrastructure failure is worth knowing about, because it looks like a hung scenario. `setup/` is copied into each container rather than bind-mounted, and with three scenarios running that copy occasionally fails mid-archive with `archive/tar: missed writing N bytes` followed by `unexpected EOF`. The repository reaches the queue container over a drvfs bind mount and that mount stumbles under load, at the same moments `wsl.exe` starts answering `Wsl/Service/0x8007274c`. It cost one run of the smoke scenario, since removed: nothing checked the copy, the playbook launched against a `/work` that did not exist, and the container sat idle while the queue waited for an exit code that was never coming. The copy now retries three times, asserts that `site.yaml`, `all.yaml` and at least a hundred files actually arrived, and on failure removes the container and writes a `result.txt` saying the run proves nothing and must be rerun. A copy that half succeeded is the dangerous case, because the tree looks plausible and the run dies somewhere unrelated an hour later.

One more thing about the queue container, in [AGENTS.md](../AGENTS.md) but worth repeating where the harness is documented. Whatever you put after `run.sh` in the `-c` string becomes the container's exit status. Append a plain `echo` and the container reports success no matter what the sweep did: a run where three of the seven scenarios that existed then failed came back `Exited (0)` for exactly that reason, and a queue whose exit code cannot be trusted cannot be alarmed on or chained behind. Capture the status into a variable first and `exit` it explicitly.

---

### The exact order every pipeline runs in

Three stages, and nothing in a later stage starts until the stage before it has passed. Twenty jobs
run at once, which is every concurrent job GitHub Free allows, with at most five of those on macOS,
which is its own separate cap.

Every job that installs anything ends by verifying, and uploads two logs: what the run did, and what
the machine looks like afterwards. Those are different claims, and only the second one is evidence.

Stage 1, static and parse only. Nothing is installed anywhere. Five jobs, all finish inside about
five minutes, and the whole sweep stops here if any of them fails.

| Order | Job | Runner | What it proves |
|---|---|---|---|
| 1 | tier 1 gate | ubuntu-latest | the whole static gate, every check, from a clean checkout |
| 2 | Windows unit tests | windows-latest | the Pester suite over the Windows installer's own logic |
| 3 | Linux wizard plan | ubuntu-latest | `setup.sh --print-command` resolves a real selection into a real playbook command |
| 4 | macOS wizard plan | macos-14 | the same on Darwin, where the toggle files and the OS dictionary differ |
| 5 | Windows wizard plan | windows-latest | `setup.ps1 -PrintPlan` resolves without installing |

Jobs 3 to 5 are what "parse only" means: the wizard runs its own resolution, prints the command or
plan it would execute, and exits. They cost seconds and they catch a broken toggle file, a renamed
option or a wizard that no longer agrees with the YAML, before anything spends an hour installing.

Stage 2, the container sweep. Forty jobs, twenty at a time. Linux goes before the other two
platforms because it is where the playbook does the most and where a real defect is most likely.

The order inside the stage is deliberate. Defaults runs first on all six distributions, because it
is the configuration people actually get and a breakage in it is the one that matters most, and the
rest run longest first, because a long job started late is what decides when the sweep ends. Two
scenarios share a ceiling with an existing one, and each was appended to the end of its own tie
group rather than inserted into it, so adding them moved nothing that was already there.

| Order | Scenario | Distributions | Ceiling |
|---|---|---|---|
| 6 to 10 | defaults | arch, debian, ubuntu, fedora, cachyos | 180 minutes |
| 11 to 15 | all-software | the same five | 300 minutes |
| 16 to 20 | kde-full | the same five | 300 minutes |
| 21 to 25 | gnome-full | the same five | 300 minutes |
| 26 to 30 | idempotency | the same five | 300 minutes, for two passes |
| 31 to 35 | live-profile | the same five | 120 minutes |
| 36 to 40 | kde-configure-only | the same five | 90 minutes |
| 41 to 45 | forced-failure | the same five | 90 minutes |

Stage 3, the short real installs on the other two platforms. Seven jobs, each a real wizard run on a
real machine, each ending in verification. Roughly 30 to 90 minutes. macOS sits at three, under its
own cap of five concurrent macOS jobs.

| Order | Job | Runner | Selection |
|---|---|---|---|
| 46 | macOS defaults | macos-14 | the toggles as they ship |
| 47 | macOS everything | macos-14 | every selectable toggle on |
| 48 | macOS from nothing | macos-14 | every toggle off, then a handful enabled by name |
| 49 | Windows defaults | windows-latest | the toggles as they ship |
| 50 | Windows everything | windows-latest | every selectable toggle on |
| 51 | Windows from nothing | windows-latest | every toggle off, then a handful enabled by name |
| 52 | Windows settings only | windows-latest | the four native system settings, no software |

Fifty-two jobs in total. Those ceilings are timeouts rather than measurements, and no scenario has
ever run on a GitHub runner, so the real numbers will only exist after the first sweep.

Pop!_OS is the sixth, and it is not what the other five are. System76 publishes no container image, so
that one is Ubuntu carrying Pop's own identity, both `/etc/os-release` and the `/etc/lsb-release` that
`pop-default-settings` diverts, generated from the base image's own version fields so the result is a
machine that could exist. It proves the playbook on a machine whose ID is neither ubuntu nor debian,
and it is the canary for the day Ansible's family table or Pop's identity changes. It proves nothing
about System76's own packages, and no container can. The image asserts its own identity at build time
and refuses to become Ubuntu wearing a different tag.

How long the sweep takes. Adding the ceilings gives 1710 minutes of work per distribution, which is
180 plus 300 plus 300 plus 300 plus 300 plus 120 plus 90 plus 90, and 10260 minutes across all six.
At twenty concurrent that is a little over seven hours in the worst case, and the real figure should
be well under it, because every ceiling is generous and the two newest scenarios are the two least
likely to reach theirs: the second pass of the idempotency run has nothing to download, and the
forced-failure run stops the software installer at its first batch, which on debian measured 45m 55s
against its 90 minute ceiling. Stage 1 and stage 3 are small enough that concurrency never binds
them.

---

### What tier 1 checks, and which bug each check exists for

| Check | Guards against |
|---|---|
| [tier1/wizard_parse.sh](tier1/wizard_parse.sh) | The wizard showing a toggle in the wrong state, or dropping it, or the bash and PowerShell wizards disagreeing about which toggles exist |
| [tier1/toggle_coverage.sh](tier1/toggle_coverage.sh) | A toggle enabled with no mapping and no task, so the user asks for software and gets a successful run with nothing installed. For Windows it accepts only the three native installers, because a Windows-gated Ansible task cannot run and counting one as coverage is what hid eleven empty toggles |
| [tier1/windows_mapping.sh](tier1/windows_mapping.sh) | The PowerShell installer and `vars/Windows.yaml` disagreeing about a package, a manager or a source, a mapping with no toggle to select it, and the Windows Python mapping drifting away from `default_python` |
| [tier1/windows_npm_parity.sh](tier1/windows_npm_parity.sh) | The native npm tool list and the `ai_tools` role it replaces drifting apart, which is the same two-lists problem the two wizards already had |
| [tier1/verify_spec_parity.sh](tier1/verify_spec_parity.sh) | A capability spec understating what its run proves. Every container scenario shares one `verify.yaml`, so an assertion added there belongs in all five container specs, and two had already gone unrecorded |
| [tier1/failed_key_reads.sh](tier1/failed_key_reads.sh) | Any task deciding something from a result's `failed` key, which `failed_when` rewrites. A collector selecting on `failed == true` was dead code from the day it was written and counted three AUR builds that exited rc 1 as successes |
| [tier1/os_family_derivation.sh](tier1/os_family_derivation.sh) | A task branching on Ansible's own `os_family` instead of the derived `ih_family`, and the derivation itself misreading a distribution. Ansible resolves the family through one fixed table and falls back to the distribution's own name for anything absent from it, so on Nobara every family condition here was false and the run stopped with nothing installed. The derivation is now the single point of failure for every distribution, so it is run against one real `/etc/os-release` per distribution in [tier1/os_release_fixtures/](tier1/os_release_fixtures/), openSUSE included, which must resolve to none of the five families rather than be rounded up to RedHat |
| [tier1/ansible_static.sh](tier1/ansible_static.sh) | The playbook failing to parse, and warning noise growing to the point where a real warning cannot be seen |

Each of these was written against a defect that had already shipped, and each was verified to fail on the code from before its fix. A check that has never been seen to fail is not a check, it is decoration.

Intended no-ops are listed with a reason in [tier1/documented_no_ops.txt](tier1/documented_no_ops.txt). Anything not listed there is treated as a defect. The check also flags stale entries, because forgiving a toggle that has since gained a real mapping would hide it breaking later.

---

### What tier 2 checks

Every package name in [setup/ansible/vars/](../setup/ansible/vars/) is resolved against the real index for its package manager, and so is every package name written directly into a role task. Nothing is installed anywhere.

Covered without a container: Arch official repositories, the Arch User Repository, Flathub, Homebrew formulae and casks, Chocolatey, and winget.

Covered inside a throwaway container: apt and dnf. Both need a package index, so the check queries it inside the same pinned base image the tier 3 scenarios use, read out of [tier3/](tier3/)'s Dockerfiles so the check and the scenarios cannot drift apart. The container is asked and thrown away, and nothing is installed in it.

This used to say apt and dnf were not covered on purpose, which left the 35 apt names and the 35 dnf names in the dictionaries resolved by nothing at all, on the two families most people run. The reasoning behind that gap was real: many of those names come from repositories the playbook adds while it runs, so asking a stock image about them reports failures for packages that are fine. The answer is [tier2/runtime_repo_packages.txt](tier2/runtime_repo_packages.txt), which forgives exactly those names with a reason each, and which is itself checked for entries that have gone stale in both directions, one that now resolves without the repository and one that nothing asks for any more.

Debian and Ubuntu are both asked, against their own images, because their answers differ. Debian trixie ships its own kubectl and Ubuntu 26.04 does not, and openrazer-meta is packaged by both while Fedora has no such package. Asking one of them and assuming the other is the mistake that put four entries in the regression ledger.

winget resolves two ways. The better one asks winget itself with `winget show --id <id> --exact`, which queries the source the installer will actually use, has no request budget, and answers the real question. It needs no setup and it is reachable from Git Bash and, measured on 2026-08-20, from WSL as well, because the Store `winget.exe` runs through interop and answers there. The check decides by running a candidate rather than by trusting a shell, so it takes that path wherever it works. The fallback looks for each manifest directory in `microsoft/winget-pkgs`, which needs an authenticated `gh` because unauthenticated GitHub allows 60 requests an hour and there are more ids than that.

```bash
gh auth login
```

With neither available the check reports SKIP and names the count it did not resolve. That mattered: WSL was the documented way to run the gate and `gh` was not authenticated, so all 82 mapped ids went unresolved by anything for as long as the check existed. Run from Git Bash it now resolves 75 manifest ids against the CLI, the other 7 being Microsoft Store product ids which are not winget manifests at all.

Note the two paths do not prove exactly the same thing. A manifest existing upstream is not quite the same as an id resolving on a machine, whose sources can be stale.

---

### The tier 3 scenarios

Six of them are one configuration the wizard can actually produce, and between them they cover the wizard's whole output space, which is the desktop environment choice crossed with the three software paths. The other two ask something about the run itself rather than about a selection.

| Scenario | Wizard path it reproduces |
|---|---|
| defaults | Step 2 "defaults", desktop environment "skip". What pressing Enter through the wizard gives you, and what `setup.sh --non-interactive` runs |
| all-software | Step 2 "customise", then select-all in the checklist |
| kde-full | Desktop environment "kde", action "full" |
| gnome-full | Desktop environment "gnome", action "full" |
| live-profile | Step 2 "profile", the Linux Live entry. The path a USB or live-session install takes |
| kde-configure-only | Desktop environment "kde", action "configure". The only combination where the configure tasks cannot assume their own install step just ran |

The all-software toggle list is generated at run time from [group_vars/](../setup/ansible/group_vars/) rather than written into the scenario file, so a newly added toggle is covered with no edit here. The exact list used is written into the run directory.

Two scenarios are not wizard paths, and both carry a control key that changes what [tier3/container.sh](tier3/container.sh) does rather than what the playbook installs.

| Scenario | Control key | What it asks |
|---|---|---|
| idempotency | `e2e_run_twice: true` | The defaults configuration applied twice in one container. The second pass must report no changed task that is not named, with a reason, in [tier3/idempotent_changes_allowed.txt](tier3/idempotent_changes_allowed.txt). This is the defining property of a configuration tool and nothing here had ever asked for it: a task that reports changed with nothing left to do is either doing its work twice or misreporting it, and the second one destroys the only signal there is for telling a run that did something from a run that did nothing |
| forced-failure | `e2e_expect_failure: true` | A package name no repository has ever carried, injected over the batch the software installer computes for itself, so every distribution fails the same way. The verdicts invert: the run has to exit non-zero, name the failing task in the terminal summary and in `~/installation_errors.log`, and the verification has to refuse and say what is missing. Every one of those four mechanisms was proven once by a hand-made probe and then never exercised again, and a run that cannot report its own failure is worse than a run that fails |

Both scenarios explain their own reasoning in full at the top of their scenario files, including why the forced-failure injection is the one chosen and what the alternatives would have failed to cover.

---

### What a container cannot test

[tier3/container_limits.yaml](tier3/container_limits.yaml) turns off the toggles a container provably cannot satisfy, and the runner prints that list on every run so no scenario is mistaken for full coverage. The list is short on purpose: hibernation, bootloader installation, Waydroid, VirtualBox, VMware and Snapper, all of which need hardware or a kernel facility that belongs to the host.

What to do about them instead of nothing is [manual_test_matrix.md](manual_test_matrix.md), which covers every platform rather than only Linux: it names each untested thing, why the automation cannot reach it, whether a virtual machine is enough or real hardware is required, and a command whose output answers the question.

Everything merely slow or awkward stays enabled. Pre-suppressing something because it might fail is how a real defect becomes a silent gap, which is the failure this whole directory exists to stop.

Two consequences worth knowing before reading a failure as a bug. Kernel modules never build, because `/usr/lib/modules` belongs to the host, so anything using DKMS reports missing headers. And there is no login session, so tasks that need a live user D-Bus take their documented fallback path instead.

The first of those does not cost the same everywhere, which is why there is also a `container_limits.<os>.yaml` appended after the shared file. OpenRazer's DKMS build fails identically on Arch and Fedora. On Arch the alpm hook prints the error and returns 0, so the package installs and the run carries on. On Fedora, RPM treats the failed `%posttrans` as a transaction failure, so dnf reports the whole batch as failed and syncthing, tailscale and chkrootkit come back missing too even though they installed. Suppressing OpenRazer everywhere to satisfy Fedora would have thrown away the Arch coverage that exists for a real ledger entry, so [tier3/container_limits.fedora.yaml](tier3/container_limits.fedora.yaml) turns it off for Fedora alone and says what that costs.

---

### Which distributions, and why Ubuntu is separate from Debian

| `--os` | Base image | Notes |
|---|---|---|
| arch | archlinux:base | Rolling, so there is no version to pin |
| debian | debian:trixie | Debian 13, current stable |
| ubuntu | ubuntu:26.04 | Latest LTS |
| fedora | fedora:44 | Current stable. Tag 45 exists but is still branched |
| cachyos | cachyos/cachyos-v3:latest | Arch with its own repositories in front of Arch's, and the distribution most Linux gamers actually run |

CachyOS earns an image rather than being assumed covered by the Arch one, because a package name resolves against its repositories first, so a name present in both can come from a different build. It is also the second most used distribution among Linux users on Steam as of July 2026, at 14.3 percent against plain Arch's 8.3, so a break there reaches more people than a break on Arch. The v3 tag is deliberate: CachyOS publishes one image per instruction-set level and its installer picks v3 on any processor from the last decade, so the baseline image would test a configuration almost nobody runs. Verified on the real image, its `os-release` reports `ID=cachyos` with `ID_LIKE=arch`, matching the fixture the tier 1 derivation check asserts against, and it ships Arch's own release file so Ansible already reports the Arch family for it.

Ansible reports Ubuntu as the Debian family, so both load the same [vars/Debian.yaml](../setup/ansible/vars/Debian.yaml) and both take the same branch in every task gated on the family. That is exactly why they need separate images: the shared branch is only correct if the package names hold on both, and they do not. `ubuntu-desktop` and `language-pack-kde-pl` do not exist in Debian, while `qt6-style-kvantum` does not exist in Ubuntu 24.04, and all three are named in the desktop environment roles' Debian branch. One image would have hidden half of that.

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

It is separate because a Docker daemon serves one container platform at a time. It runs only where a Windows daemon is already answering, and it never changes the platform of the daemon it finds: the one on this project's machine serves the Linux containers every other tier depends on, and that stays as it is. Where no Windows daemon answers, the same suite still runs without a container at all, through the `windows_pester` check in tier 1 and through the stage 1 job of the sweep on a hosted Windows runner. What that leaves unproven is the handful of cases that need a machine with nothing installed. `run.sh --os windows` says the same rather than failing on a missing Dockerfile.

What it tests: the logic in [setup/windows/WindowsSoftware.ps1](../setup/windows/WindowsSoftware.ps1) on a clean Windows with nothing installed, which is the state a real user starts from and the one a developer machine can never reproduce. That is the YAML parsing, the resulting install plan, the winget resolution failure path, and the Chocolatey bootstrap. The suite is [tier3/windows/WindowsSoftware.Tests.ps1](tier3/windows/WindowsSoftware.Tests.ps1), driven by Pester 5, which the image installs at build time so a run needs no network of its own.

What it cannot test, and does not claim to: any winget installation. winget ships as an MSIX package and needs the AppX deployment subsystem, which Server Core and Nano Server do not have. That is 82 of the 89 Windows mappings, seven of those being Microsoft Store product ids that need the Store itself and are further out of reach again. Chocolatey works because it is only PowerShell and NuGet, which covers the remaining 7. There is no way around this in a container, so winget installation needs a real Windows machine or a hosted runner. It also cannot test the wizard's own interface, because `Out-ConsoleGridView` needs a real console.

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
| [manual_test_matrix.md](manual_test_matrix.md) | What no pipeline here can prove, where to prove it by hand, and how to tell it worked, for every platform and distribution |
| [run_durations.md](run_durations.md) | How long every cell of the sweep actually takes on a hosted runner, measured, and what a fraction of the sweep costs |
| [docs/regression_ledger.md](../docs/regression_ledger.md) | Every regression this project has suffered, and the prevention checklist this harness mechanises |
| [AGENTS.md](../AGENTS.md) | The mandatory gate, and the rest of the agent contract |
| [setup/README_SETUP.md](../setup/README_SETUP.md) | Running the playbook for real |
| [setup/ansible/tags.md](../setup/ansible/tags.md) | Partial runs by tag, useful when triaging a scenario failure |
| [.github/workflows/e2e-matrix.yml](../.github/workflows/e2e-matrix.yml) | The full CI sweep, every scenario against every Linux distribution, dispatch-only |
| [.github/workflows/e2e-manual.yaml](../.github/workflows/e2e-manual.yaml) | "E2E - single platform", one target platform per dispatch, Linux distribution or macOS or Windows |
