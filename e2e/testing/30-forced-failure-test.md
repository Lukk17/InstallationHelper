# forced-failure: e2e test

Tier 3 of the harness, scenario [../tier3/scenarios/07-forced-failure.yaml](../tier3/scenarios/07-forced-failure.yaml). Declared timeout 90 minutes, measured at 45m 55s on debian. Not a wizard path: this is the only scenario that breaks the run on purpose, and the only one where a green playbook is the failure.

Section headings sit at level two because the `e2e-runbooks` test-spec template fixes the seven section names at that level, which overrides this repository's level-three heading rule.

---

## What this verifies

- A failing task produces a non-zero exit code. Every role in [../../setup/ansible/site.yaml](../../setup/ansible/site.yaml) catches its own failure so one broken role cannot abandon an hour of work, which means the exit code comes from a single terminal task at the very end reading `any_role_failed`. That arrangement has already been wrong twice: the "Install block rescue hides which task failed" entry in [../../docs/regression_ledger.md](../../docs/regression_ledger.md), where a rescue absorbed a failure and never propagated it so the play exited 0, and the "`playbook_succeeded` reported true regardless of what the rescue actually caught" entry, where the flag that decides the verdict was computed from the wrong thing. Both were fixed and nothing has exercised either fix since.
- The failing task is named in the terminal summary. [../../setup/ansible/callback_plugins/dual_logger.py](../../setup/ansible/callback_plugins/dual_logger.py) prints a `FAILED (n)` section listing one bullet per failing task with the reason beneath it. This is the ledger's "callback rendered a tolerated failure as FAILED beside a recap saying failed=0" entry from the other side: that fix separated tolerated failures from real ones, and a real one still has to appear.
- The same failing task is named in `~/installation_errors.log`. The terminal summary scrolls away and that file is what a person reads afterwards, which is why site.yaml's own terminal failure message points at it by name. The ledger records that thirteen places in site.yaml used to point at `~/installation_issues.log`, a file nothing has ever written, so a message naming a log is not evidence that the log has anything in it. This capability asserts the file names the same task the summary named, not merely that it exists.
- The verification refuses over a machine the run failed to build, and says what is missing. [../../setup/ansible/verify_install.yaml](../../setup/ansible/verify_install.yaml) is the only post-install check in the repository and the wizard runs it as its last step, so a verification that passes over a broken machine makes every other capability here worthless. This is the live counterpart to the "Pacman batch failure marked as success" ledger entry, where a two-condition `failed_when` combined with AND meant one could-not-find error dropped every pacman package while the run stayed green.
- A batch failure names the whole batch it cost. The rescue in [../../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml](../../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml) works out which manager's batch failed and lists every application in it, because a batch is one call and a failure loses all of them, not just the one that broke. That is checked here by reading the summary rather than asserted mechanically, and the reason is in the Expected section.

---

## Prerequisites

Confirm the shell can drive a Docker daemon. On Windows both Git Bash and WSL qualify, WSL only when Docker Desktop has integration enabled for that distribution.

```bash
uname -s
```

Expect `Linux` from WSL, or `MINGW64_NT-...` from Git Bash. The harness asks whether a daemon answers rather than what the operating system is, so either is fine.

Confirm the Docker daemon is reachable.

```bash
docker info
```

Expect a daemon summary. The container needs `--privileged` and the host cgroup mount.

Confirm there is disk headroom.

```bash
df -h /var/lib/docker
```

Expect several gigabytes free. This scenario installs far less than the others, because it stops the software installer at its first batch, but it still builds a base image and bootstraps a system.

Confirm no container is left over from an aborted run.

```bash
docker ps -a --filter name=e2e- --format '{{.Names}}'
```

Expect empty output, or only containers belonging to runs you know about.

Confirm the harness still knows this scenario by name.

```bash
./e2e/run.sh --list
```

Expect a row reading `forced-failure` with its description and `timeout 90 min`.

Confirm the working tree holds exactly the change you intend to test.

```bash
git status --short setup
```

Expect only your own edits. The harness copies [../../setup/](../../setup/) into the container rather than bind-mounting it, so the run cannot modify the tree it is testing.

---

## Reset state

Nothing to reset inside the machine under test. Every run builds its own throwaway container and its own directory under `e2e/runs/`.

Remove any leftover container the prerequisite check listed, substituting the name it printed. Skip this when the output was empty.

```bash
docker rm -f <container-name>
```

Force a rebuild of the base image, and only when the Dockerfile for the distribution you are targeting changed since the last run.

```bash
docker image rm installationhelper-e2e-debian:latest
```

---

## Run

One step is enough here, because the whole run is under an hour rather than several: the injected failure lands at the software installer's first batch and everything after it in that block is skipped, so the run never installs the software set at all. Measured on debian at 45m 55s, of which about 41 minutes is the bootstrap, zsh, SDK and AI tooling prelude that every scenario pays before the software installer starts.

```bash
./e2e/run.sh --tier 3 --scenario forced-failure --os debian
```

The detached form is available and behaves like every other scenario, which matters when you want the container left alive to look inside it.

```bash
./e2e/tier3/container.sh e2e/tier3/scenarios/07-forced-failure.yaml --os debian --detach
```

Then collect it, substituting the run directory the launch printed.

```bash
./e2e/tier3/container.sh --collect e2e/runs/<run-id>
```

From a PowerShell prompt on Windows, the same run inside WSL.

```powershell
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && ./e2e/run.sh --tier 3 --scenario forced-failure --os debian"
```

`--os` defaults to arch, and this scenario is written to fail identically on all five distributions: the injected package name is offered to apt, dnf and pacman alike and none of them has ever carried it. Debian is the fastest image and therefore the sensible one for a first run, but a pass on one distribution is not evidence about the others, so the run record has to say which one it targeted.

---

## Expected

The single most important line is that `result.txt` reports a non-zero `playbook_rc` and a non-zero `verify_rc`. Both zeroes here would mean the harness cannot tell a failed run from a good one, which is a defect in the reporting path rather than in the scenario. The harness inverts its own verdicts for this scenario, driven by `e2e_expect_failure: true` in the scenario file, so a clean run is reported as a failed capability and says why in words.

Four assertions, made by [../tier3/container.sh](../tier3/container.sh) rather than by the verify play, because they are about the reporting path rather than about the state of the machine.

1. The playbook exited non-zero. Ansible's own failure code is 2, which is what the terminal fail task in site.yaml produces.
2. The terminal summary contains a `FAILED (n)` section with at least one bullet naming a task. The first bullet is the injected batch failure, which on Debian and Ubuntu reads `software_installer : Install APT packages (batched, via raw to bypass 2.19 deserialization)`, on Fedora `software_installer : Install DNF packages (batched)` and on Arch and CachyOS `software_installer : Install Pacman packages (batched)`. The final `Fail the run because at least one role failed` appears as a second bullet, and the section header says how many of the failures were caught by a rescue so the count cannot look like it contradicts the recap.
3. `installation_errors.log`, collected out of the container into the run directory, names the same task the summary named. Matching the name is the point: a non-empty file proves only that something was written.
4. The verification exited non-zero and its log carries a `FAIL native packages missing:` line listing the applications the failed batch cost.

The verify log's own assertions, in the order the play runs them. Every container scenario runs the same [../tier3/verify.yaml](../tier3/verify.yaml), so the list is the same for all of them and only the outcome differs. Each item names its verify task verbatim, so [../tier1/verify_spec_parity.sh](../tier1/verify_spec_parity.sh) can prove this list is complete rather than leaving it to be noticed.

1. `Assert the installed-package query returned a plausible list` passes. The base image has hundreds of packages of its own and the plausible minimum is fifty, so the query is still answering correctly. It has to pass, because it is the assertion that distinguishes "nothing was installed" from "the query broke", and this scenario needs the first reading to be the one that survives.
2. `Assert every enabled native package is installed` fails, and this is the assertion that carries the capability. Its failure message names the applications the run did not install, which is the whole enabled native set rather than only the one synthetic name that broke the batch, because the rescue skips every remaining task in the software installer once one of them fails.
3. `Assert every enabled URL-installed package resolved a download location` is not reached. A failed assertion ends the play, so everything below the previous item is never evaluated. That is honest rather than a gap: an assertion that never ran is reported by the harness as a run that stopped, not as a pass.
4. `Assert every enabled flatpak application is installed` is not reached, for the same reason.
5. `Assert tailscaled is enabled when Tailscale was requested` is not reached.
6. `Assert the user is in the OpenRazer device group when OpenRazer was requested` is not reached.
7. `Assert the user is in the docker group when Docker was requested` is not reached.
8. `Assert docker.service is enabled when Docker was requested` is not reached.
9. `Assert flatpak is installed and the Flathub remote is configured` is not reached.
10. `Assert the temporary passwordless sudoers entry was removed` is not reached by the verify play, and the state it checks is still worth reading out of the report block above it, because the sudoers removal sits in an `always` section precisely so that a failed run cannot skip it. The report block prints before any assertion for exactly this reason.
11. `Assert the expected desktop environment is installed` does not run at all, reached or otherwise. The scenario declares `e2e_expect_desktop: none`.

What this capability deliberately does not assert mechanically. The rescue in `dynamic_install.yaml` lists every application in the failed batch, and the injected batch holds one synthetic name, so on this scenario that list is one line long and proves nothing about the real behaviour. Read the `[ERROR] Install step ... failed` line in the log and confirm it names the batch and says a batch is one call, then record that as a judgement in the Result summary rather than ticking an assertion box for it. Asserting the wording of a message is how a test starts failing on a rewording rather than on a defect.

A pass here says nothing about whether any software installs correctly. That is capability 60's job and above. This capability proves only that when something goes wrong, the run says so in all four places a person or a script would look.

---

## Fixtures

None in the fixtures directory. The inputs are [../tier3/scenarios/07-forced-failure.yaml](../tier3/scenarios/07-forced-failure.yaml), which carries the injected package name and the reasoning behind choosing it, the toggle files under [../../setup/ansible/group_vars/](../../setup/ansible/group_vars/), and [../tier3/container_limits.yaml](../tier3/container_limits.yaml). The exact merged input is written to `effective-vars.yaml` in the run directory, which is where to look first if the run passed when it should not have.

---

## Concurrency

- Mutates: the throwaway container's own filesystem, and nothing else on the machine under test. On the host it writes one directory under `e2e/runs/<timestamp>_<os>_forced-failure/`, unique per run, and it builds or reuses the shared image tag `installationhelper-e2e-<os>:latest`, which is the one real overlap with the other container capabilities.
- Conflicts with: no other capability test at the level of state, because each container scenario gets its own container and their filesystems cannot touch. They contend for the host Docker daemon, host disk and network bandwidth. This is the cheapest container capability by a wide margin, so it is the one to pair with an expensive scenario when running two at once.
- Serial: false.
