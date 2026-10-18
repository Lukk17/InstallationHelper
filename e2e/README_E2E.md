# End-to-end harness

> Runs the real playbook against real distributions in containers and asserts the state it produced, so a regression is caught before it reaches a machine you care about.

---

### Why this exists

Every entry in [docs/regression_ledger.md](../docs/regression_ledger.md) reached a real machine because nothing ran the playbook end to end before it shipped. A syntax check cannot tell you that a group name does not exist on Arch, and reading a diff cannot tell you that a toggle installs nothing. Both of those had happened before this directory existed.

The harness answers one question per tier, cheapest first.

| Tier | Question | Cost | Needs |
|---|---|---|---|
| 1 | Does the working tree contradict itself? | 3 minutes 39 seconds, measured on Linux on 2026-10-15 | Docker |
| 2 | Do the package names still exist upstream? | 7 minutes 57 seconds, measured on Linux on 2026-10-15 | Docker and network, and a `gh` login for winget |
| 3 | Does the playbook actually produce the right machine? | 90 minutes to 5 hours by declared ceiling | Docker |

Tier 1 is the pre-commit gate. Tier 3 is what catches the bugs that matter, and it is slow because installing software is slow.

Every tier runs inside the gate container, and nothing in this directory runs on the machine that starts it. Docker is the only thing the host needs.

---

### Quick start

Run the gate. This is the one to run after any change to the playbook or the wizard. The same command works from a Linux shell, from Git Bash with Docker Desktop running, and from WSL when Docker Desktop has integration enabled for it.

```bash
bash e2e/run.sh
```

From a PowerShell prompt, the same gate through WSL:

```powershell
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && bash e2e/run.sh"
```

The path of one run:

```text
your shell                         gate container (e2e/gate/Dockerfile)
----------                         ------------------------------------
bash e2e/run.sh --tier N
  lib/gate.sh: docker build  --->  image, every tool pinned
  lib/gate.sh: docker run    --->  entrypoint.sh, as root: joins the Docker socket's group
     -v <repo>:/source:ro            drops to the user "gate"
     -v <repo>/e2e/runs              copies /source to /repo, without e2e/runs
     -v docker.sock                  sets the gate switch
                                     bash /repo/e2e/run.sh --tier N
                                       tier 1: the checks, against /repo
                                       tier 2: probe containers beside the gate
                                       tier 3: scenario containers beside the gate
  exit status  <-------------------  the run's own status
  e2e/runs/    <-------------------  the only thing written back
```

The image carries everything a check calls: Python, ansible-core and the collections in `setup/ansible/requirements.yaml`, ShellCheck, PowerShell 7 and Pester 5, yamllint, ansible-lint, Node, git, gh and the Docker client. Every version is pinned in `setup/pinned_values/pinned_values.toml` or by digest in the Dockerfile, and [gate/provision.sh](gate/provision.sh) refuses a download whose SHA-256 does not match. So no check skips for a missing tool and the tally is the same from every shell. The one skip left is a toggle coverage assertion the gate reports on purpose. `run.sh` rebuilds the image before every run, which takes a second when nothing changed and about a minute from nothing.

Every check refuses to run outside the gate container. Started directly, `bash e2e/tier1/<check>.sh` prints `REFUSED` and runs nothing, because [lib/common.sh](lib/common.sh) asks for the gate switch before anything else: the variable `E2E_INSIDE_GATE_CONTAINER=1` and the marker file `/etc/installationhelper-e2e-gate`, both of them, which only the gate's own entry point and build set. `run.sh` and `tier3/container.sh` are the two entry points that move themselves into the gate instead of refusing, through [lib/gate.sh](lib/gate.sh). Started inside some other container, they refuse too, because a host path read from inside a container names nothing the daemon can mount.

The container tiers start the same way:

```bash
bash e2e/run.sh --tier 2
```

```bash
bash e2e/run.sh --tier 3 --scenario defaults --os debian
```

Tier 2 reads winget manifests through `gh` when no winget can run, and the gate container has no `gh` login of its own. For tier 2 only, the launcher lends it yours: it writes the token to a temporary file only you can read, mounts that file read-only, and the entry point reads it into `GH_TOKEN` for its own processes. The token is never in the container's settings, so `docker inspect` cannot show it, and never on a command line. The launcher deletes the file when the run ends, or for a `--queue` run as soon as the container reports it has read it. Without a `gh` login the three winget assertions report SKIP.

Nothing has to be prefixed or exported from Git Bash. Under MSYS the shell rewrites any argument that looks like an absolute POSIX path before a Windows executable sees it, which turns `-v /sys/fs/cgroup:/sys/fs/cgroup:rw` into `mkdir C:\Program Files\Git\sys: Access is denied` and `-w /work/setup/ansible` into `Cwd must be an absolute path`. So [lib/host.sh](lib/host.sh) wraps `docker` in a function that disables the rewriting for the whole command, and every argument that names a location on this machine, rather than one inside a container, goes through its `host_path` helper and comes out as a Windows path.

See what scenarios exist and what each covers.

```bash
bash e2e/run.sh --list
```

Run the cheapest container scenario. There is no fast one: defaults carries a 180 minute ceiling, which is the honest cost of proving anything inside a container, and it is the configuration a user actually gets.

```bash
bash e2e/run.sh --tier 3 --scenario defaults
```

Run it on a different distribution.

```bash
bash e2e/run.sh --tier 3 --scenario defaults --os debian
```

Run every scenario, sequentially. Budget most of a day.

```bash
bash e2e/run.sh --tier 3 --scenario all
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
| the pinned values reader or any of its adapters | `./e2e/run.sh`, whose `windows_pester` check runs the adapter tests, then `--tier 3 --scenario defaults` | nothing about macOS, which has no container tier |
| anything in `roles/` touching groups, systemd units or per-distribution behaviour | `./e2e/run.sh --tier 3 --scenario defaults` on arch, debian, ubuntu and fedora | anything needing a graphical session, a real kernel module, or hardware |
| a task's `changed_when`, a `creates` guard, or anything about whether a task reports work it did not do | `./e2e/run.sh --tier 3 --scenario idempotency` | whether the task is idempotent on any distribution other than the one you ran, because a guard that is right on apt can be missing entirely on pacman |
| a rescue, a `failed_when`, an `ignore_errors`, `any_role_failed`, the callback plugin's failure rendering, or `verify_install.yaml`'s assertions | `./e2e/run.sh --tier 3 --scenario forced-failure` | that a real defect would be caught, only that a failure which does happen is reported in all four places, and it is the cheapest container scenario so there is no excuse for skipping it |
| the desktop environment roles | `--scenario kde-full` and `--scenario gnome-full` | that the desktop actually starts, since no container has a display |
| `profiles/linux_live.yaml` | `--scenario live-profile` | that a real live USB behaves the same, since the container has a writable root |
| `setup/setup.sh` | `./e2e/run.sh`, then any one `--tier 3` scenario end to end | the interactive screens, which need a terminal no test has |
| `setup/setup.ps1` or anything in `setup/windows/` | `./e2e/run.sh` for the logic, then `pwsh e2e/windows-sandbox/Invoke-WindowsSandbox.ps1` for a real install | anything needing a reboot, WSL, or a hypervisor, none of which a sandbox has |
| `setup/ansible/verify_install.yaml` | `./e2e/run.sh`, then `--tier 3 --scenario forced-failure`, then any one passing scenario | nothing, if the gate and both scenarios pass, this is the best covered file in the repository. The forced-failure scenario is the half that matters: it proves the play refuses over a broken machine, which no passing scenario can show |
| a tier 1 check, or anything under `e2e/` | prove the check fails against a copy of the tree carrying the defect, then `bash e2e/run.sh`, and from Git Bash and from WSL as well when the change touches `lib/gate.sh`, `lib/host.sh` or `gate/`, because the launcher is the only part that differs between them | that the check is testing the thing rather than its own implementation, which only the failure proof shows |
| `gate/Dockerfile` or `gate/provision.sh` | `bash e2e/run.sh` then `bash e2e/run.sh --tier 2`, both of which rebuild the image first | that the image builds on an architecture other than the one it was built on, x86_64 on 2026-10-15 |
| a distribution Dockerfile, or a new distribution | `--tier 3 --scenario defaults --os <name>` | that the distribution's derivatives behave the same, since only the named one runs |
| anything that only affects macOS | `./e2e/run.sh` and `./e2e/run.sh --tier 2` | everything that executes, because a Darwin container cannot run on a Linux or Windows kernel and the only executing macOS test is the `macos` target of the dispatch workflow |
| `.github/workflows/e2e-manual.yaml`, named "E2E - single platform" in the Actions tab | dispatch it from the Actions tab, one target platform at a time | nothing locally |
| `.github/workflows/e2e-matrix.yml`, named "E2E - test software install and configuration on every OS" in the Actions tab | dispatch it from the Actions tab, the full sweep or narrowed to one scenario or one distribution | nothing locally |
| `homelab/` or `local-dev/` | nothing, and that is the honest answer | everything, no tier covers either directory today |

Three rules that are easy to miss.

There is no cheap container row. Most rows that name a scenario name defaults, at a 180 minute ceiling rather than the 45 the removed smoke scenario declared, and the two that name something else name it because that scenario asks a question defaults cannot: forced-failure is the cheapest of them, measured at 46 minutes on debian against a 90 minute ceiling, and it is still not a pre-commit gate. The smoke scenario is gone because every toggle it enabled was already true in defaults, so it was the same test with most of the toggles taken away, and a 20 to 30 minute run was never cheap enough either. Tier 1 is the thing that runs in seconds.

A change that touches more than one row owes every row it touches. A pinned value that is also read by a role task is both the fourth row and the third.

A tier that cannot run is not a tier that passed. Every tier needs a Docker daemon that answers and a shell that can hand it a host path, which `require_docker_host` in [lib/host.sh](lib/host.sh) checks in that order and names whichever one is missing. From Windows, Git Bash satisfies both whenever Docker Desktop is running. WSL satisfies both only when Docker Desktop has integration enabled for that distribution, and with it off there is no socket in there at all, so the guard refuses and points at the other shell. Either way the correct response is to run the tier from a shell where it works, not to record the change as verified.

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

Collecting a run that has not finished yet is safe. It reports the task currently executing and exits 3 without touching anything. Both commands move themselves into the gate container for as long as they run, like `run.sh` does, so name the scenario file and the run directory relative to the repository root. The run directory `run.sh` prints, `/repo/e2e/runs/<run-id>`, is the same directory seen from inside the gate, and is accepted too.

One infrastructure failure is worth knowing about, because it looks like a hung scenario. `setup/` is copied into each container rather than bind-mounted, and with three scenarios running that copy occasionally fails mid-archive with `archive/tar: missed writing N bytes` followed by `unexpected EOF`. The repository reached the old queue container over a drvfs bind mount and that mount stumbled under load, at the same moments `wsl.exe` starts answering `Wsl/Service/0x8007274c`. It cost one run of the smoke scenario, since removed: nothing checked the copy, the playbook launched against a `/work` that did not exist, and the container sat idle while the queue waited for an exit code that was never coming. The copy now retries three times, asserts that `site.yaml`, `all.yaml` and at least a hundred files actually arrived, and on failure removes the container and writes a `result.txt` saying the run proves nothing and must be rerun. A copy that half succeeded is the dangerous case, because the tree looks plausible and the run dies somewhere unrelated an hour later. The gate container now copies the repository once, when it starts, so the copy into each scenario container reads from the gate's own filesystem rather than across that mount.

A run that has to outlive the terminal goes into the queue, which is the gate container started detached under the name `e2e-queue`. Its entry point writes the whole run to `e2e/runs/queue.log`, captures the run's status before it writes anything else, ends the file with `QUEUE_EXIT=<status>` and exits with that same status. That order matters: the hand-written queue command this replaced appended an `echo` after the run, and a sweep where three of the seven scenarios that existed then failed came back `Exited (0)`, which a queue whose exit code is meant to be alarmed on or chained behind cannot afford.

```bash
bash e2e/run.sh --queue --tier 3 --scenario all --jobs 3
```

The container stays after it exits, so its status stays readable, and the next `--queue` refuses to start until it is removed:

```bash
docker rm e2e-queue
```

---

### The exact order every pipeline runs in

Three stages, and nothing in a later stage starts until the stage before it has passed. Twenty jobs
run at once, which is every concurrent job GitHub Free allows, with at most five of those on macOS,
which is its own separate cap.

Every job that installs anything ends by verifying, and uploads two logs: what the run did, and what
the machine looks like afterwards. Those are different claims, and only the second one is evidence.

Stage 1, static and parse only. Nothing is installed anywhere. Five jobs, all finish inside about
five minutes, and the whole sweep stops here if any of them fails. The tier 1 job also builds the gate
image first, about a minute on Linux on 2026-10-15, and has not been timed on a runner since.

| Order | Job | Runner | What it proves |
|---|---|---|---|
| 1 | tier 1 gate | ubuntu-latest | the whole static gate, every check, from a clean checkout, inside the gate container exactly as on a developer machine |
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
real machine, each ending in verification. The stage took 78, 95 and 123 minutes across the three full
sweeps measured in [run_durations.md](run_durations.md), and Windows sets that pace: the slowest
`Windows all apps` cell took 122 minutes against its 150 minute ceiling. macOS sits at three, under
its own cap of five concurrent macOS jobs.

| Order | Job | Runner | Selection |
|---|---|---|---|
| 46 | macOS defaults | macos-14 | the toggles as they ship |
| 47 | macOS everything | macos-14 | every selectable toggle on |
| 48 | macOS from nothing | macos-14 | every toggle off, then a handful enabled by name |
| 49 | Windows defaults | windows-latest | the toggles as they ship |
| 50 | Windows everything | windows-latest | every selectable toggle on |
| 51 | Windows from nothing | windows-latest | every toggle off, then a handful enabled by name |
| 52 | Windows settings only | windows-latest | the three native system settings, no software |

Fifty-two jobs in total. Those ceilings are timeouts rather than measurements. Three full sweeps have
run on GitHub runners, and the measured time of every cell, with its average, fastest and slowest,
is in [run_durations.md](run_durations.md).

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
| [tier1/toggle_coverage.sh](tier1/toggle_coverage.sh) | A toggle enabled with no mapping and no task, so the user asks for software and gets a successful run with nothing installed. For Windows it accepts only the three native installers, because a Windows-gated Ansible task cannot run and counting one as coverage is what hid eleven empty toggles. A mapping in a derivative file under `setup/ansible/vars/derivatives/` with no toggle Linux loads fails it too |
| [tier1/windows_mapping.sh](tier1/windows_mapping.sh) | The PowerShell installer and `vars/Windows.yaml` disagreeing about a package, a manager or a source, a mapping with no toggle to select it, and the Windows Python mapping drifting away from `default_python` |
| [tier1/windows_npm_parity.sh](tier1/windows_npm_parity.sh) | The native npm tool list and the `ai_tools` role it replaces drifting apart, which is the same two-lists problem the two wizards already had, and either side removing the package a tool replaces without installing it again when the new one fails |
| [tier1/verify_spec_parity.sh](tier1/verify_spec_parity.sh) | A capability spec understating what its run proves. Every container scenario shares one `verify.yaml`, so an assertion added there belongs in all five container specs, and two had already gone unrecorded |
| [tier1/failed_key_reads.sh](tier1/failed_key_reads.sh) | Any task deciding something from a result's `failed` key, which `failed_when` rewrites. A collector selecting on `failed == true` was dead code from the day it was written and counted three AUR builds that exited rc 1 as successes |
| [tier1/os_family_derivation.sh](tier1/os_family_derivation.sh) | A task branching on Ansible's own `os_family` instead of the derived `ih_family`, and the derivation itself misreading a distribution. Ansible resolves the family through one fixed table and falls back to the distribution's own name for anything absent from it, so on Nobara every family condition here was false and the run stopped with nothing installed. The derivation is now the single point of failure for every distribution, so it is run against one real `/etc/os-release` per distribution in [tier1/os_release_fixtures/](tier1/os_release_fixtures/), openSUSE included, which must resolve to none of the five families rather than be rounded up to RedHat. It also fails any task file other than `setup/ansible/tasks/load_os_dict.yaml` that loads `vars/{{ ih_family }}.yaml` itself, because that play would miss a derivative's overrides |
| [tier1/derivative_merge.sh](tier1/derivative_merge.sh) | `derivative_package_names_for` in [lib/package_probe.sh](lib/package_probe.sh), the bash copy of the merge rule in `setup/ansible/tasks/load_os_dict.yaml` that tier 2 resolves a derivative's packages with, giving different package names per manager than the real merge, which [tier1/derivative_merge.yaml](tier1/derivative_merge.yaml) runs through the shipped loader against the os-release fixtures. Two copies of one rule drift, AGENTS.md defect class 2 |
| [tier1/apt_vendor_repositories.sh](tier1/apt_vendor_repositories.sh) | An apt repository written under the derivative's own release name, which no vendor publishes. Docker, Tailscale and HashiCorp were written with Ansible's own release, `zara` on Linux Mint 22.2 and `gigi` on LMDE 7, and all three answer 404 for both. It fails a task file other than [../setup/ansible/tasks/derive_os_facts.yaml](../setup/ansible/tasks/derive_os_facts.yaml) that reads the release itself, renders every repository line and key location out of the shipped task files against six os-release fixtures with the facts the shipped derivation gives, and fails a Docker, Tailscale or HashiCorp line without the vendor's ubuntu or debian path and the parent's codename, a line naming a derivative's own codename, and a `docs/manual/debian-ubuntu/install.sh` whose `UPSTREAM_DISTRO` and `UPSTREAM_CODENAME` give a different answer |
| [tier1/opencode_switch.sh](tier1/opencode_switch.sh) | The OpenCode version switch deciding differently per family, leaving the other version's desktop app or command line package installed, deleting or misplacing the data folder, or reaching a real package manager because a fake was not found |
| [tier1/windows_cache_cleanup.sh](tier1/windows_cache_cleanup.sh) | The Windows wizard losing the step that empties the winget and Chocolatey download caches, or having it moved out of the window between the packages and the SDK installers, which is where a hosted runner ran out of disk with `wsl --install` failing at `Wsl/InstallDistro/0x80070070` |
| [tier1/ansible_static.sh](tier1/ansible_static.sh) | The playbook failing to parse, warning noise growing to the point where a real warning cannot be seen, the callback dropping a line the playbook marked `[ERROR]`, the callback leaving no trace of a failed attempt that a retry then hid, and the end-of-run summary listing a package that installed on a retry under both TOLERATED FAILURES and INSTALLED |
| [tier1/sigpipe_pipelines.sh](tier1/sigpipe_pipelines.sh) | A command fed from `yes`, which the kernel kills with SIGPIPE when the reader exits, so under `set -o pipefail` the pipeline reports 141 whatever the real command did. It happened to the Android SDK licence task, was fixed there, and was then written again into the CachyOS graphics alignment task, where it failed a run on a real machine on 2026-08-28 over a pacman that had succeeded |
| [tier1/unreachable_tasks.sh](tier1/unreachable_tasks.sh) | A task gated on a toggle the container limits switch off on every image that could run it, which is a task the entire suite never executes. That is how the CachyOS alignment task shipped untested: it was pinned to the one image where `install_steam` was suppressed. A task gated on a fact derived from toggles, such as `ih_steam_requested`, counts as dead only when every toggle behind the fact is suppressed, `install_steam` plus the toggle of every mapping marked `brings_steam: true` in the vars files, and the check fails when the file that sets the fact stops reading exactly the toggles and the mapping attribute it maps it to. Deliberate cases are listed with what they cost in [tier1/uncovered_toggles_allowed.txt](tier1/uncovered_toggles_allowed.txt), and a stale line there fails too |
| [tier1/keycloak_realm_import.sh](tier1/keycloak_realm_import.sh) | The committed Keycloak realm export acquiring something Keycloak's own import path will not take, losing the client or the user the readme promises, or the image quietly ceasing to seed itself from it at all. A JavaScript authorization policy in that realm crash looped the container for four minutes on `Script upload is disabled` while the health check said `starting`, and `--import-realm` never touches an existing realm, so any machine whose database predates the fix still holds the policy and re-exports it |
| [tier1/desktop_settings.sh](tier1/desktop_settings.sh) | Anything here changing a screen lock, idle or session-restore setting on any platform. The konsave profile carried a `kscreenlockerrc` holding nothing but a version stanza, and applying it replaced rather than merged, so a machine set never to lock went back to Plasma's five minute default with no warning. The check reads inside the `.knsv` archive, which no grep over the tree would ever have found |
| [tier1/paru_consumers.sh](tier1/paru_consumers.sh) | A task that calls paru without reading `paru_available`, which since the paru build stopped being critical bootstrap would call a paru that is not there after a failed build, and a second place deciding whether paru is usable. Only [../setup/ansible/tasks/paru_availability.yaml](../setup/ansible/tasks/paru_availability.yaml) decides it. Also a package a role installs through paru that the verification does not expect, and any task using yay while `install_yay` still makes it optional |
| [tier1/availability_facts.sh](tier1/availability_facts.sh) | A third-party repository, the CachyOS 32-bit graphics alignment or env_variables being decided in a second place, or a task that installs or configures what they serve without reading the one fact: `unavailable_repositories`, `steam_graphics_stack_aligned` or `env_variables_available`. Also a repository block that does not fetch its own repository, a Fedora `yum_repository` whose id `repo_ids` does not name, and a first apt cache refresh that does not check the third-party repositories already on the machine one at a time, a sources or `.repo` file written under `setup/` that no entry names, and a refresh that does not set aside, for the run only, a sources file this project does not manage whose repository does not answer. Before 2026-10-10 each of those three failures stopped far more of the run than the step it was |
| [tier1/rescue_coverage.sh](tier1/rescue_coverage.sh) | A role in site.yaml outside a block of its own, apart from the five core roles, or an SDK, AI tool, vendor download or AUR helper build step in arch_core without a rescue that sets `any_role_failed` and names the step with an `[ERROR]` line, so one failure skips everything after it or ends the run green |
| [tier1/heartbeat_log_files.sh](tier1/heartbeat_log_files.sh) | A per-task log file named by the callback's heartbeat table, the setup hub or the container harness that no current task writes, or a heartbeat prefix that matches no task name. All three still named the batched apt and Flatpak logs after both managers moved to one package per call |
| [tier1/wizard_root_refusal.sh](tier1/wizard_root_refusal.sh) | The bash wizard no longer refusing a run as root, or refusing it only after it has detected the OS, read the toggles or called sudo. Nothing had ever run that refusal before this check. It starts `setup.sh` as uid 0 through `unshare -r` |
| [tier1/zshrc_env_block.sh](tier1/zshrc_env_block.sh) | `setup/config/zsh/.zshrc` setting environment outside a comment, an `export` or a PATH assignment, which a desktop session never sees because Plasma's login zsh is non-interactive. shell_zsh writing that file other than as one marked block read from the file, the shape that made a second run insert a block again in GitHub sweep run 38107292439 on Arch idempotency. Its `ZSH=` line naming a different directory from `shell_zsh_oh_my_zsh_dir`. And the zsh environment import in `env_unix.yaml` importing `~/.config/environment.d` before `typeset -U path PATH`, so a nested shell repeats every PATH entry |
| [tier1/vendor_installer_shell_init.sh](tier1/vendor_installer_shell_init.sh) | A task file that pipes a vendor installer into a shell behind a `creates` guard under the user's home and has no unconditional blockinfile beside it into `dev_env_file`, `~/.config/environment.d/50-dev.conf`, or into every file in `interactive_rc_files`, so the installer is the only thing wiring its tool into the shell and never runs again once its guard file exists. GitHub sweep run 38107292439 measured that on CachyOS GNOME full, where `sdk` and `java` were on disk and unreachable from zsh. Exceptions live in [tier1/vendor_installer_shell_init_allowed.txt](tier1/vendor_installer_shell_init_allowed.txt) with a reason, and a stale entry fails |
| [tier1/forced_failure_assertions.sh](tier1/forced_failure_assertions.sh) | A forced-failure assertion in [tier3/container.sh](tier3/container.sh) that fails over a rescue that worked. GitHub sweep run 38107292439 failed that scenario on Arch, CachyOS and Fedora that way: Lens was matched as the whole skipped-repository sentence when tailscale was in the same list, and the paru injection let the Arch User Repository server decide whether the clone or the build failed. It drives `log_list_names` from container.sh over that run's own lines and requires the paru address to be under `.invalid` |
| [tier1/winget_scope_pins.sh](tier1/winget_scope_pins.sh) | A winget mapping that leaves the installer to winget although its manifest offers a user and a machine installer, or a user one beside unscoped ones. The wizard runs elevated, and Bruno, CurseForge and then Lens in GitHub sweep run 38107292439 failed while winget chose. The list of such packages is [tier1/winget_scoped_packages.txt](tier1/winget_scoped_packages.txt), which tier 2 reads again from winget-pkgs. It also fails a machine pin whose `installer_type` is missing or differs from the type winget selects for `--scope machine`, because that type decides whether the wizard runs winget elevated, and an msix or portable sent to an unelevated winget dies on `APPINSTALLER_CLI_ERROR_COMMAND_REQUIRES_ADMIN` |
| [tier1/repo_metadata_keys.sh](tier1/repo_metadata_keys.sh) | A dnf repository with `repo_gpgcheck` whose metadata check would stop at a key prompt, or whose key would be accepted unchecked. Every `dnf makecache` must pass `-y`, which GitHub sweep run 38107292439 lacked on every Fedora scenario, and because `-y` accepts any key, `gpgkey` must be a local file that the same block downloaded from a pin and compared by fingerprint with a pin before the repository is written |
| [tier1/manual_windows_install.sh](tier1/manual_windows_install.sh) | The by-hand Windows route drifting from [../setup/ansible/vars/Windows.yaml](../setup/ansible/vars/Windows.yaml). By 2026-10-11 [../docs/manual/windows/install.ps1](../docs/manual/windows/install.ps1) still installed BillStewart.SyncthingWindowsSetup, ShiningLight.OpenSSL.Light and a retired Store id, missed fourteen mapped packages and pinned no scope at all. It fails when the script's package table differs from the mappings on by default in id, manager, source, scope, installer type or machine condition, when the script's elevated installer types, Syncthing firewall rules or logon shortcut arguments differ from setup/windows/WindowsSoftware.ps1, when [../docs/manual/windows/windows_manual_install.md](../docs/manual/windows/windows_manual_install.md) lacks the exact install command of a mapping or carries one for a package or flag the mapping file does not name, when a row whose install needs an elevated winget does not say so, and when a Windows command in [../setup/software.md](../setup/software.md) names a package neither the mapping file nor setup/windows/WindowsCustomInstalls.ps1 installs |
| [tier1/manual_linux_install.sh](tier1/manual_linux_install.sh) | The by-hand Linux route drifting from [../setup/ansible/vars/Archlinux.yaml](../setup/ansible/vars/Archlinux.yaml), [../setup/ansible/vars/Debian.yaml](../setup/ansible/vars/Debian.yaml) and [../setup/ansible/vars/RedHat.yaml](../setup/ansible/vars/RedHat.yaml), each with its derivatives merged over it. By 2026-10-15 none of the three scripts under [../docs/manual/](../docs/manual/) installed OpenCode desktop, the Arch and Fedora ones lacked PuTTY, none installed Podman Desktop or OpenRazer, and all three installed a Dart the playbook does not install on Linux. It fails when a script or its `*_manual_install.md` guide lacks a pacman, aur, apt, apt_url, dnf, dnf_url, flatpak or snap mapping that is on by default, comparing apt_url and dnf_url by the pinned download location, when a script installs a name no mapping on by default has, when a guide installs a name no mapping has at all, and when a line of [tier1/manual_linux_install_allowed.txt](tier1/manual_linux_install_allowed.txt), the documented differences, names a playbook file that no longer installs it or is used by nothing. It also fails a script or guide that installs Docker and never runs `sudo systemctl enable --now docker`, and a `usermod` or `systemctl` line in a script with no `|| printf '   Skipped: ...'`, which under `set -e` ends the script before it lists what did not install |
| [tier1/batched_managers.sh](tier1/batched_managers.sh) | A package manager handed several packages in one call, in the software installer, in any other task file, or in the manual install scripts and the guides' fenced code blocks and inline commands under [../docs/manual/](../docs/manual/). One call has one exit code, so one package that fails loses the whole set and nothing can name it. The macOS manual script's single `brew install` installed nothing at all over one bad name, see the ledger's 10.25 |
| [tier1/pacman_partial_refresh.sh](tier1/pacman_partial_refresh.sh) | A pacman call that refreshes the package index and installs a package in the same invocation without upgrading the system, the partial upgrade the Arch wiki warns against, in any task file or shell script under `setup/`, or a refresh with no upgrade that a later install follows in a shell script or a fenced code block under [../docs/manual/](../docs/manual/) |
| [tier1/package_retry_rule.sh](tier1/package_retry_rule.sh) | A package manager that does not follow the one retry rule: an apt, dnf, pacman, flatpak, snap or Homebrew install under `setup/ansible` that does not go through `setup/ansible/tasks/install_role_packages.yaml`, a manager with no index to refresh (the AUR, npm, pip, SDKMAN, nvm) that does not retry four times twenty seconds apart, the shared file running against fake managers and failing to try once without a refresh, wait, refresh that manager's index, retry, four attempts and name what never installed, or `install_one` in a `docs/manual/<os>/install.sh` doing any of that differently |
| [tier1/imported_agent_artifacts.sh](tier1/imported_agent_artifacts.sh) | A stale copy of what is pulled from agent-standards: the OpenCode and Kilo Code plugin treating the main thread as a subagent, not default-exporting `{ id, server, setup }` so OpenCode 2.x loads nothing, or a read-only subagent without `permission` deny for edit and bash. Found by measurement on 2026-10-13 after the three had shipped. It runs the real plugin when Node is installed and asserts a main-thread write is refused. |
| [tier1/checklist_labels.sh](tier1/checklist_labels.sh) | A comma in a label the bash wizard shows on its software checklist. gum splits the comma-joined `--selected` value on every comma, so the toggle shows unticked although it is on, and `setup_zsh`, on by default, was turned off by pressing Enter. It also compares `LABEL_OVERRIDES` in setup.sh with `$LabelOverrides` in setup.ps1: a key both wizards can show must carry the same label in both, a key a table carries that its own wizard can never offer fails by name, and a `$LabelOverrides` line that does not read as a single-quoted `'key' = 'label'` entry fails instead of being skipped. See docs/regression_ledger.md 10.36 |
| [tier1/name_lookup_retries.sh](tier1/name_lookup_retries.sh) | A tier 2 name check calling a name missing on anything but a definite 404 or 410 from the index, or a lookup that never got a definite answer passing quietly. `check_brew` once read a 503 from formulae.brew.sh as `1 of 19 names do not exist / minikube` while the same URL answered 200 right after. The real `check_brew` and `check_pacman` are sourced out of [tier2/resolve_packages.sh](tier2/resolve_packages.sh) and run against a stand-in curl that answers 503 then 200, a timeout then 200, 404, 503 on every attempt, and archlinux.org's throttled empty body |
| [tier1/capability_index_parity.sh](tier1/capability_index_parity.sh) | The tables in `openspec/changes/add-playbook-e2e-capability-tests/` (`test-spec.md`, `proposal.md`, `tasks-template.md`) naming a different set of capability numbers and names from the index in [testing/README.md](testing/README.md). They still described capability 30 as smoke and had no row for 90 after the index had changed both |
| [tier1/compose_and_docs.sh](tier1/compose_and_docs.sh) | A compose file under `local-dev/` or `homelab/` that docker refuses, a service with nothing to run, and a relative markdown link anywhere in the repository that names a file which does not exist, or a heading anchor no heading produces. Until 2026-10-15 it read only `local-dev/` and `homelab/` with grep, and pointed at the rest of the tree it found six links to four files deleted between 2026-08-20 and 2026-09-02, in `docs/` and `openspec/`. It reads every markdown file git would ship, tracked or new, so ignored trees such as `e2e/runs/` are never read. A path must match in case as well, because GitHub serves a case-sensitive tree. Files under `openspec/schemas/*/templates/` are left out by name, because their links resolve from where they are copied to. A link to a path an open change plans to create is listed in [tier1/doc_links_allowed.txt](tier1/doc_links_allowed.txt) with the reason, and an entry whose target exists or that nothing links any more fails |
| [tier1/shell_syntax.sh](tier1/shell_syntax.sh) | A shell script that does not parse under `bash -n`, or a ShellCheck warning, which passed every local run while ShellCheck was optional and failed the GitHub sweep. Nothing has to be installed: `pinned_shellcheck` in [lib/common.sh](lib/common.sh) uses a `shellcheck` on PATH only at the version pinned in `setup/pinned_values/pinned_values.toml`, and otherwise downloads that release for the current shell into the ignored `e2e/.cache/shellcheck/`, checks its pinned SHA-256 on every run and reuses it. With no network on the first run, or an archive that does not match, the assertion fails rather than skipping |

That table is a selection, not the gate. The complete list, one paragraph per check with the defect it was written against, is [testing/10-wizard-toggle-parse-test.md](testing/10-wizard-toggle-parse-test.md), and the gate prints its own tally when it runs.

Each of these was written against a defect that had already shipped, and each was verified to fail on the code from before its fix. A check that has never been seen to fail is not a check, it is decoration.

Intended no-ops are listed with a reason in [tier1/documented_no_ops.txt](tier1/documented_no_ops.txt). Anything not listed there is treated as a defect. The check also flags stale entries, because forgiving a toggle that has since gained a real mapping would hide it breaking later.

---

### What tier 2 checks

Every package name in [setup/ansible/vars/](../setup/ansible/vars/) is resolved against the real index for its package manager, and so is every package name written directly into a role task. Nothing is installed anywhere.

Covered without a container: Arch official repositories, the Arch User Repository, Flathub, Homebrew formulae and casks, Chocolatey, and winget.

Those over HTTP call a name missing only on a definite answer, a 404 or a 410, or an empty results list from archlinux.org. A timeout, a 5xx, a 429 or archlinux.org's throttled empty body is asked again, up to four times with a growing pause, by `http_ask` in [lib/http_ask.sh](lib/http_ask.sh), and a lookup that never gets a definite answer fails as `could not be checked` with the URL and what came back. It used to be one request, so a 503 from formulae.brew.sh read as `Homebrew brew: 1 of 19 names do not exist / minikube` while the same URL answered 200 right after.

Covered inside a throwaway container: apt and dnf. Both need a package index, so the check queries it inside the same pinned base image the tier 3 scenarios use, read out of [tier3/](tier3/)'s Dockerfiles so the check and the scenarios cannot drift apart. The container is asked and thrown away, and nothing is installed in it.

Every apt repository the playbook writes is asked as well, by [tier2/resolve_apt_repositories.sh](tier2/resolve_apt_repositories.sh): each line that depends on the release or the lineage, and each signing key downloaded for one, is rendered for the Debian 13, Ubuntu 26.04, Linux Mint 22 and 22.2 and LMDE 6 and 7 fixtures through [lib/apt_repositories.sh](lib/apt_repositories.sh), the rendering tier 1's `apt_vendor_repositories` asserts on, and the vendor is asked for `dists/<suite>/InRelease`, then `Release`, or for the key itself. A derivative's own codename, `zara` or `gigi`, answers 404 at Docker, Tailscale and HashiCorp alike, and that is what this catches.

A derivative's dictionary under [setup/ansible/vars/derivatives/](../setup/ansible/vars/derivatives/) is resolved the same way. CachyOS maps the gaming suite to `cachyos-gaming-applications` from its own repository, which archlinux.org does not carry, so the Arch pacman names with the CachyOS entries merged over them, the set [setup/ansible/tasks/load_os_dict.yaml](../setup/ansible/tasks/load_os_dict.yaml) hands the playbook, are asked with `pacman -Si` inside the CachyOS image. Flathub and AUR names in a derivative file go through the HTTP checks above. Every derivative is merged over `vars/Archlinux.yaml`, so one whose `e2e/tier3/<id>.Dockerfile` is missing or never runs pacman fails by name rather than being checked against the wrong family, and tier 1's `derivative_merge.sh` holds the bash merge to the real one.

This used to say apt and dnf were not covered on purpose, which left the 35 apt names and the 35 dnf names in the dictionaries resolved by nothing at all, on the two families most people run. The reasoning behind that gap was real: many of those names come from repositories the playbook adds while it runs, so asking a stock image about them reports failures for packages that are fine. The answer is [tier2/runtime_repo_packages.txt](tier2/runtime_repo_packages.txt), which forgives exactly those names with a reason each, and which is itself checked for entries that have gone stale in both directions, one that now resolves without the repository and one that nothing asks for any more.

Debian and Ubuntu are both asked, against their own images, because their answers differ. Debian trixie ships its own kubectl and Ubuntu 26.04 does not, and openrazer-meta is packaged by both while Fedora has no such package. Asking one of them and assuming the other is the mistake that put four entries in the regression ledger.

winget resolves two ways. The better one asks winget itself with `winget show --id <id> --exact`, which queries the source the installer will actually use, has no request budget, and answers the real question. It needs no setup and it is reachable from Git Bash and, measured on 2026-08-20, from WSL as well, because the Store `winget.exe` runs through interop and answers there. The check decides by running a candidate rather than by trusting a shell, so it takes that path wherever it works. The fallback looks for each manifest directory in `microsoft/winget-pkgs`, which needs an authenticated `gh` because unauthenticated GitHub allows 60 requests an hour and there are more ids than that.

```bash
gh auth login
```

With neither available the check reports SKIP and names the count it did not resolve. That mattered: WSL was the documented way to run the gate and `gh` was not authenticated, so all 82 mapped ids went unresolved by anything for as long as the check existed. Run from Git Bash it now resolves 75 manifest ids against the CLI, the other 7 being Microsoft Store product ids which are not winget manifests at all.

Note the two paths do not prove exactly the same thing. A manifest existing upstream is not quite the same as an id resolving on a machine, whose sources can be stale.

winget scopes are read only one way, through `gh`, because `winget show` prints no scope. Tier 2 reads the newest installer manifest of every mapped winget id and fails when the packages that offer a choice of scope or pin one, or the installer type winget selects for each of them under `--scope machine`, differ from [tier1/winget_scoped_packages.txt](tier1/winget_scoped_packages.txt), printing the live list to replace it with. Without an authenticated `gh` that result is a SKIP.

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

Every scenario container gets `/dev/loop0` to `/dev/loop63` made with `mknod` right after it starts, by a step in [tier3/container.sh](tier3/container.sh), because Docker fills a privileged container's `/dev` once from the host's nodes and a host kernel that creates loop devices only on demand, `max_loop` 0 with `CONFIG_BLK_DEV_LOOP_MIN_COUNT=0`, otherwise hands snapd a loop device the container has no node for. See [ledger entry 10.37](../docs/regression_ledger.md#1037-snapd-could-not-mount-a-squashfs-image-in-a-test-container-because-the-containers-dev-never-gets-the-loop-devices-the-kernel-creates-after-it-starts).

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

Windows has no container tier. It had one until 2026-08-26 and it was retired, so if you find a reference to a Windows Dockerfile or to `Invoke-WindowsE2E.ps1` anywhere, it is stale.

The reason is worth stating once, because it is not obvious. A Windows container is always Windows Server: Microsoft publishes container base images only from Windows Server, the newest being Server 2025 at build 26100, and there has never been a Windows 10 or Windows 11 client image. Server Core has no AppX deployment subsystem, and winget ships as an MSIX package that needs it, so winget cannot install anything inside any Windows container. That is 80 of the 89 Windows mappings. What was left was the YAML parsing, the plan, and the Chocolatey path, all of which the tier 1 gate proves on a developer machine in seconds, so the container was a multi-gigabyte image and an isolation argument in exchange for almost nothing.

Windows coverage now lives in three places, and between them they cover more than the container ever did.

The logic, in seconds, inside the gate container, which carries PowerShell 7 and Pester 5 on Linux. This is the `windows_pester` check inside the tier 1 gate, and it runs [tier1/windows/WindowsSoftware.Tests.ps1](tier1/windows/WindowsSoftware.Tests.ps1), the same file the sweep's stage 1 job runs on a hosted runner.

```bash
bash e2e/run.sh
```

A real install on your own Windows, in Windows Sandbox. This is the local route for anything that actually installs software, and the whole of it is on [manual_test_matrix.md](manual_test_matrix.md).

It needs the feature turned on once, from an elevated PowerShell, and it asks for a reboot. Nothing in this repository will do that for you: [windows-sandbox/Invoke-WindowsSandbox.ps1](windows-sandbox/Invoke-WindowsSandbox.ps1) prints this line and stops rather than changing your machine.

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All
```

After that, one command per run. It writes the sandbox configuration from where the script sits, maps the repository in read only, and starts a throwaway desktop that bootstraps winget and PowerShell 7 and then waits for you.

```powershell
pwsh e2e/windows-sandbox/Invoke-WindowsSandbox.ps1
```

A real install on a hosted Windows Server 2025 runner, which is the automated one. Dispatch [../.github/workflows/e2e-manual.yaml](../.github/workflows/e2e-manual.yaml) at its `windows` target, or run the full sweep, whose four Windows cells install the whole set for real. Measured over three sweeps at an average of 82 minutes for the defaults set and 98 with every toggle on, the slowest of them 122, in [run_durations.md](run_durations.md).

What none of the three can do is in [manual_test_matrix.md](manual_test_matrix.md), and the short version is that the runner is Server rather than client, and a sandbox can neither reboot nor run a hypervisor. Between them that leaves the client-edition packages, the seven Microsoft Store ids, `enable_hyperv`, WSL end to end and every hardware row for a real machine.

---

### macOS

Cannot be tested this way at all. A container shares the host kernel, so a Darwin container cannot exist on a Linux or Windows kernel. That is a design fact rather than a licensing quibble, and virtualising macOS is separately restricted by Apple to Apple hardware. macOS needs real hardware, or a hosted runner on real hardware.

---

### Run records

Every tier 3 run writes a directory under `e2e/runs/`, which is gitignored.

| File | Contents |
|---|---|
| effective-vars.yaml | The exact profile setup.sh's `--profile` flag received, including everything generated |
| playbook.log | setup.sh's full output: the system upgrade, the playbook, and its own embedded verification commentary |
| verify.log | setup.sh's own `~/installation_verify.log`, copied out rather than run a second time |
| result.txt | Exit codes, the play recap, and every error line |

Keep the run directory when you report a failure. The effective variable file is the only record of what was actually asked for, and reconstructing it afterwards is guesswork.

---

### Adding a check

Put it in the tier that answers its question most cheaply, source [lib/common.sh](lib/common.sh), which refuses to let it run anywhere but in the gate container, add any tool it needs to [gate/Dockerfile](gate/Dockerfile) or [gate/provision.sh](gate/provision.sh) rather than skipping when the tool is missing, use `pass` and `fail` so one failure does not hide the rest, and end with `finish`. Never end a check script by letting the last command's status fall out, because a harness that reports failures and exits zero reads as a pass to everything that calls it.

Then prove it. Copy the tree, reintroduce the defect, and confirm the check fails. If you cannot make it fail, it is not testing what you think.

---

### Documentation map

| Doc | What's in it |
|---|---|
| [gate/](gate/) | The gate container every tier runs in: [gate/Dockerfile](gate/Dockerfile), [gate/provision.sh](gate/provision.sh), which installs the pinned tools while the image builds, and [gate/entrypoint.sh](gate/entrypoint.sh), which runs one harness script against a private copy of the repository |
| [manual_test_matrix.md](manual_test_matrix.md) | What no pipeline here can prove, where to prove it by hand, and how to tell it worked, for every platform and distribution |
| [run_durations.md](run_durations.md) | How long every cell of the sweep actually takes on a hosted runner, measured, and what a fraction of the sweep costs |
| [windows-sandbox/](windows-sandbox/) | The local Windows route: a launcher that writes the sandbox configuration and starts it, and the bootstrap that runs inside at logon. Windows only, which is why the directory says so |
| [docs/regression_ledger.md](../docs/regression_ledger.md) | Every regression this project has suffered, and the prevention checklist this harness mechanises |
| [AGENTS.md](../AGENTS.md) | The mandatory gate, and the rest of the agent contract |
| [setup/README_SETUP.md](../setup/README_SETUP.md) | Running the playbook for real |
| [setup/ansible/tags.md](../setup/ansible/tags.md) | Partial runs by tag, useful when triaging a scenario failure |
| [.github/workflows/e2e-matrix.yml](../.github/workflows/e2e-matrix.yml) | The full CI sweep, every scenario against every Linux distribution, dispatch-only |
| [.github/workflows/e2e-manual.yaml](../.github/workflows/e2e-manual.yaml) | "E2E - single platform", one target platform per dispatch, Linux distribution or macOS or Windows |
