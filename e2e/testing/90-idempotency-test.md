# idempotency: e2e test

Tier 3 of the harness, scenario [../tier3/scenarios/08-idempotency.yaml](../tier3/scenarios/08-idempotency.yaml). Declared timeout 300 minutes for the pair of passes. The same input as capability 60, applied twice in one container, where the second pass must change nothing.

Section headings sit at level two because the `e2e-runbooks` test-spec template fixes the seven section names at that level, which overrides this repository's level-three heading rule.

---

## What this verifies

- Applying the default configuration to a machine that already has it changes nothing. This is the defining property of a configuration tool and no test in this repository had ever asked for it. A task that reports changed on a run with nothing left to do is either doing its work a second time or misreporting what it did, and the two failures cost different things: the first wastes an hour of a real install and can overwrite a setting the user changed since, and the second destroys the only signal anybody has for telling a run that did something from a run that did nothing.
- The second pass still exits 0. A first pass that succeeded and a second that fails is a different defect from a noisy second pass, and it is the more serious one: it means the playbook cannot run on a machine it has already configured, which is the normal case for everybody who runs it more than once.
- Every task that does report changed on the second pass is accounted for by name. The allowlist at [../tier3/idempotent_changes_allowed.txt](../tier3/idempotent_changes_allowed.txt) holds one line per exception with the reason it cannot be repeatable, and matching is exact and on the whole task name, so a renamed task loses its exemption and the scenario fails until somebody looks at it again.
- The state assertions still hold after a second pass. Verification runs once, at the end, so it asserts the machine two applications of the playbook produced. A second pass that undoes something the first pass installed shows up here as a missing package rather than as a changed task, and nothing else in the suite would catch it.

This capability exists for the same reason as the ledger entries about tolerance and reporting, though no shipped defect names it directly. That is honest and worth saying plainly: it is the one capability here that was not written in response to a regression already suffered. It was written because `changed` is the mechanism every other capability's reading of a log depends on, and nothing had ever checked that it means what it says.

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

Expect at least tens of gigabytes free. This scenario installs the whole default software set, then asks for it again.

Confirm there is memory headroom for the whole run. This is the longest capability in the suite by wall time, and it holds one container for both passes.

```bash
free -g
```

Expect at least 5 GB available per scenario you intend to run at once. There is no `free` in Git Bash, so from that shell this is a check to make in WSL or to skip knowingly.

Confirm no container is left over from an aborted run.

```bash
docker ps -a --filter name=e2e- --format '{{.Names}}'
```

Expect empty output, or only containers belonging to runs you know about.

Confirm the harness still knows this scenario by name.

```bash
./e2e/run.sh --list
```

Expect a row reading `idempotency` with its description and `timeout 300 min`.

Confirm the working tree holds exactly the change you intend to test.

```bash
git status --short setup
```

Expect only your own edits. The harness copies [../../setup/](../../setup/) into the container rather than bind-mounting it, so the run cannot modify the tree it is testing.

---

## Reset state

Nothing to reset inside the machine under test, and nothing may be reset between the two passes. That is the whole point: the second pass sees exactly what the first one left behind, in the same container, as the same user, with the same variable file.

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

Two steps, because two passes of a defaults-shaped run should not be tied to the shell that started them. Both passes happen inside the container with nothing attached, and the harness writes the run's exit code only after the second pass has finished, so the ordinary wait and collect flow covers the pair with no extra commands.

Step 1. Launch and return. The command prints the run directory, the container name, and the two commands to follow and to collect.

```bash
./e2e/tier3/container.sh e2e/tier3/scenarios/08-idempotency.yaml --os debian --detach
```

Follow the first pass from any shell, using the container name the launch printed.

```bash
docker exec <container-name> tail -f /work/playbook.log
```

Follow the second pass the same way once it starts. Its log is a separate file, so the two passes can never be confused for one another.

```bash
docker exec <container-name> tail -f /work/playbook2.log
```

Step 2. Wait until both passes have finished, then verify, record and tear down, substituting the run directory the launch printed. Collecting early is safe: it reports the task currently executing and exits 3 without touching anything.

```bash
./e2e/tier3/container.sh --collect e2e/runs/<run-id>
```

The single-command form does the same work in the foreground.

```bash
./e2e/run.sh --tier 3 --scenario idempotency --os debian
```

From a PowerShell prompt on Windows, the same launch inside WSL.

```powershell
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && ./e2e/tier3/container.sh e2e/tier3/scenarios/08-idempotency.yaml --os debian --detach"
```

`--os` defaults to arch. Idempotency is not a property that generalises across distributions: a task that guards itself correctly on apt may guard itself by nothing at all on pacman, and the second pass is where that shows. So a run of this capability is a run against one distribution and the record has to say which.

---

## Expected

`result.txt` in the run directory reports `playbook_rc: 0`, `second_run_rc: 0` and `verify_rc: 0`, plus four lines that exist only for this capability.

| Line in `result.txt` | What it means |
|---|---|
| `second_run_rc` | the second pass's own exit code, or `never-ran` when the first pass failed and the second was therefore not started |
| `second_run_changed_total` | how many tasks reported changed on the second pass |
| `second_run_changed_not_allowed` | those not named in the allowlist, listed by name, and the number that has to be zero |
| `second_run_changed_allowed` | those named in the allowlist, listed by name, so an exemption cannot be used without being seen |

A note on the cross-cutting convention that pass criteria are observable state and never log substrings. This capability reads its verdict out of the second pass's log, and that is not an exception to the rule. `changed` is the playbook's own per-task disposition, a boolean the task itself returns, not prose that a rewording can move: the assertion is on the identity of the tasks and on the count, never on any message. The play recap at the end of `playbook2.log` carries the same total as `changed=N` and is the figure to check the parsed list against if the two ever look inconsistent.

A first pass that fails is reported as a failed capability rather than as an unproven one. There is nothing to say about idempotency when the first pass did not finish, and reading an absent second pass as "nothing changed" would be the exact shape of misleading output this suite exists to remove.

The verify log carries these assertions, each on its own PASS or FAIL line, and all of them must pass. Every container scenario runs the same [../tier3/verify.yaml](../tier3/verify.yaml), so the list is the same for all of them and only the expected sets differ. Each item names its verify task verbatim, so [../tier1/verify_spec_parity.sh](../tier1/verify_spec_parity.sh) can prove this list is complete rather than leaving it to be noticed.

Before any of them, `Assert the installed-package query returned a plausible list` checks the input to the comparison rather than the comparison itself. It fails when the query behind the native package assertion returns fewer than fifty entries, which no working Linux installation does. It exists because a format string whose newline was being discarded made that query return one concatenated blob, so every expected package was reported missing and read exactly like a playbook that had installed nothing.

1. `Assert every enabled native package is installed`, checked against the family's own query, `dpkg-query` on Debian and Ubuntu, `rpm -qa` on Fedora and `pacman -Qq` on Arch and CachyOS. The expected set is every toggle true in `group_vars/all.yaml` and `group_vars/linux.yaml` that the family's dictionary maps to a native manager, minus whatever the container limits turned off. Here it also proves the second pass removed nothing the first pass installed.
2. `Assert every enabled URL-installed package resolved a download location`. Some packages install from a vendor URL rather than a repository, and both dispatch tasks skip silently when that URL renders empty, so this fails the run instead of letting it look clean. The candidate set is empty on Arch and CachyOS, which map nothing to `apt_url` or `dnf_url`.
3. `Assert every enabled flatpak application is installed`, checked against `flatpak list --app --columns=application`.
4. `Assert tailscaled is enabled when Tailscale was requested`, from `systemctl is-enabled tailscaled.service`.
5. `Assert the user is in the OpenRazer device group when OpenRazer was requested`, from `id -nG` against `os_dict.openrazer_device_group`.
6. `Assert the user is in the docker group when Docker was requested`, from `id -nG`. Worth watching on this capability in particular: a group membership task that adds the user unconditionally is a classic always-changed offender, and this is the scenario that would name it.
7. `Assert docker.service is enabled when Docker was requested`.
8. `Assert flatpak is installed and the Flathub remote is configured`. The Flathub remote-add is another natural offender, and it is guarded with `--if-not-exists` for exactly that reason.
9. `Assert the temporary passwordless sudoers entry was removed`, meaning `/etc/sudoers.d/99-ansible-user` does not exist. Both passes create and remove it, so on a second pass the removal task legitimately reports changed and is expected to appear in the allowlist.
10. `Assert the expected desktop environment is installed` does not run here. The scenario declares `e2e_expect_desktop: none`, which is the wizard's `skip` answer, and both `install_kde_plasma` and `install_gnome` are false by default.

Known container limitations. [../tier3/container_limits.yaml](../tier3/container_limits.yaml) forces `setup_hibernate`, `setup_systemd_boot`, `setup_grub`, `remove_distro_grub`, `remove_distro_systemd_boot`, `install_waydroid`, `install_virtualbox`, `install_vmware` and `install_snapper` to false on top of every scenario, because each needs hardware or a kernel facility that belongs to the host. None of those is covered here, so nothing is known about whether the bootloader or hibernation tasks are idempotent. The harness prints the suppressed list on every run.

Two documented consequences that must not be read as regressions, and both matter more here than anywhere else. Kernel modules never build, because `/usr/lib/modules` belongs to the host, so a DKMS package can legitimately report changed on every pass while it retries a build that cannot succeed. And there is no login session, so tasks needing a live user D-Bus take their documented fallback path, which for some of them means the fallback runs again every time. Where the container is what makes a task unrepeatable, the allowlist entry has to say so, and it has to say that the task may well be idempotent on a real machine. An exemption granted for a container artefact is not evidence about hardware.

---

## Fixtures

None in the fixtures directory. The inputs are [../tier3/scenarios/08-idempotency.yaml](../tier3/scenarios/08-idempotency.yaml), the toggle files under [../../setup/ansible/group_vars/](../../setup/ansible/group_vars/), [../tier3/container_limits.yaml](../tier3/container_limits.yaml), and the allowlist at [../tier3/idempotent_changes_allowed.txt](../tier3/idempotent_changes_allowed.txt). The exact merged input is written to `effective-vars.yaml` in the run directory, and both passes receive that same file.

---

## Concurrency

- Mutates: the throwaway container's own filesystem, and nothing else on the machine under test. On the host it writes one directory under `e2e/runs/<timestamp>_<os>_idempotency/`, unique per run, holding `playbook.log` and `playbook2.log` separately, and it builds or reuses the shared image tag `installationhelper-e2e-<os>:latest`, which is the one real overlap with the other container capabilities.
- Conflicts with: no other capability test at the level of state, because each container scenario gets its own container and their filesystems cannot touch. They contend for the host Docker daemon, host disk and network bandwidth. This is the longest capability in the suite by wall time, since it is two applications of the configuration capability 60 applies once, so running it beside the other expensive scenarios on one machine is how both end up crawling and one hits its declared timeout, which counts as a fail.
- Serial: false.
