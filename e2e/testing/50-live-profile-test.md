# live-profile: e2e test

Tier 3 of the harness, scenario [../tier3/scenarios/05-live-profile.yaml](../tier3/scenarios/05-live-profile.yaml). Declared timeout 120 minutes. Reproduces the wizard's step 2 `profile` path with the Linux Live entry, which is the path a USB or live-session install actually takes.

Section headings sit at level two because the `e2e-runbooks` test-spec template fixes the seven section names at that level, which overrides this repository's level-three heading rule.

---

## What this verifies

- The playbook runs to completion when the wizard's profile path is used, and exits 0. The harness turns `e2e_profile: linux_live` into `-e @profiles/linux_live.yaml`, exactly what [../../setup/setup.sh](../../setup/setup.sh) does for `--profile`, rather than restating the profile's contents in the scenario file. This is the third and least exercised of the three software paths, and a break here is invisible until somebody is standing at a machine with no working system.
- The profile's overrides reach the run. [../../setup/ansible/profiles/linux_live.yaml](../../setup/ansible/profiles/linux_live.yaml) turns off heavy tooling and turns off the four toggles that make no sense on an ephemeral session, `install_tailscale`, `install_syncthing`, `install_docker` and `install_openrazer`. This exists for the "Tailscale's apt repository URL assumed the distribution name was already the codename it needed" entry in [../../docs/regression_ledger.md](../../docs/regression_ledger.md), whose same commit caught that the live USB profile never disabled Tailscale at all, so an ephemeral run added a repository and enabled a daemon on a session that could never join a tailnet.
- The container limits still outrank the profile. The harness passes the profile first and `effective-vars.yaml` second, so the suppressed toggles win over anything the profile says, which is the intended precedence and is visible in `effective-vars.yaml` in the run directory.
- The temporary passwordless sudoers entry is gone, asserted by `stat` on `/etc/sudoers.d/99-ansible-user`. Same "`playbook_succeeded` reported true regardless of what the rescue actually caught" ledger entry as the other container scenarios.
- The packages the run was actually asked for are present. Read the caveat under Expected before ticking this one: verification computes its expected set without the profile, so its native and flatpak assertions describe the default toggle set rather than the profile's.

---

## Prerequisites

Confirm the shell is Linux. On Windows this means running from inside WSL, which is also the only place Ansible runs at all.

```bash
uname -s
```

Expect `Linux`. The harness refuses tier 3 from any other platform.

Confirm the Docker daemon is reachable.

```bash
docker info
```

Expect a daemon summary. On Windows that means Docker Desktop running with WSL integration enabled. The container needs `--privileged` and the host cgroup mount.

Confirm there is disk headroom.

```bash
df -h /var/lib/docker
```

Expect several gigabytes free. The live profile is the lightest software set of the container scenarios, but it still installs browsers, a password manager and crypto tooling.

Confirm no container is left over from an aborted run.

```bash
docker ps -a --filter name=e2e-arch- --format '{{.Names}}'
```

Expect empty output.

Confirm the harness still knows this scenario by name.

```bash
./e2e/run.sh --list
```

Expect a row reading `live-profile` with its description and `timeout 120 min`.

Confirm the profile the scenario names exists, since the harness builds the path from the scenario key without checking it first.

```bash
ls setup/ansible/profiles/linux_live.yaml
```

Expect the path to print.

Confirm the working tree holds exactly the change you intend to test.

```bash
git status --short setup
```

Expect only your own edits. The harness copies [../../setup/](../../setup/) into the container rather than bind-mounting it.

---

## Reset state

Nothing to reset inside the machine under test. Every run builds its own throwaway container and its own directory under `e2e/runs/`.

Remove any leftover container the prerequisite check listed, substituting the name it printed. Skip this when the output was empty.

```bash
docker rm -f <container-name>
```

Force a rebuild of the base image, and only when [../tier3/arch.Dockerfile](../tier3/arch.Dockerfile) changed since the last run.

```bash
docker image rm installationhelper-e2e-arch:latest
```

---

## Run

Two steps, because at two hours this run should not be tied to the shell that started it. The playbook always runs detached inside the container, so an ordinary disconnect cannot throw the run away.

Step 1. Launch and return. The command prints the run directory, the container name, and the two commands to follow and to collect.

```bash
./e2e/tier3/container.sh e2e/tier3/scenarios/05-live-profile.yaml --detach
```

From a PowerShell prompt on Windows, the same launch inside WSL.

```powershell
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && ./e2e/tier3/container.sh e2e/tier3/scenarios/05-live-profile.yaml --detach"
```

Follow it from any shell, as often as you like, using the container name the launch printed.

```bash
docker exec <container-name> tail -f /work/playbook.log
```

Step 2. Wait until step 1's playbook has finished, then verify, record and tear down, substituting the run directory the launch printed. Collecting early is safe: it reports the task currently executing and exits 3 without touching anything, so repeat it rather than guessing.

```bash
./e2e/tier3/container.sh --collect e2e/runs/<run-id>
```

The single-command form below does the same work in the foreground and is fine when you can leave a shell open for two hours.

```bash
./e2e/run.sh --tier 3 --scenario live-profile
```

---

## Expected

`result.txt` in the run directory reports `playbook_rc: 0`. That is the primary assertion for this capability, because the question the scenario asks is whether the profile path runs at all.

The verify log carries the same assertions as every other container scenario, because they all run one [../tier3/verify.yaml](../tier3/verify.yaml) and only the expected sets differ. Each is named verbatim so [../tier1/verify_spec_parity.sh](../tier1/verify_spec_parity.sh) can prove this list is complete.

1. `Assert every enabled native package is installed`, against `pacman -Qq`.
2. `Assert every enabled flatpak application is installed`, against `flatpak list --app --columns=application`.
3. `Assert tailscaled is enabled when Tailscale was requested`. The profile turns `install_tailscale` off, so this one is skipped here, and the skip is the point: the ledger entry behind this scenario is a live profile that never disabled Tailscale at all.
4. `Assert the user is in the OpenRazer device group when OpenRazer was requested`. Also disabled by the profile, also skipped.
5. `Assert the user is in the docker group when Docker was requested`. Also disabled by the profile, also skipped.
6. `Assert docker.service is enabled when Docker was requested`. Also skipped, same reason.
7. `Assert flatpak is installed and the Flathub remote is configured`.
8. `Assert the temporary passwordless sudoers entry was removed`.

Amended 2026-08-15, because this section previously described a harness limitation that no longer exists and told the runner to expect a failure that is now a real one. What it said: [../tier3/container.sh](../tier3/container.sh) passed the profile to the playbook but not to the verify play, so verification resolved every toggle with the profile invisible to it, expected the whole of the profile's disabled list, and reported it missing. A non-zero `verify_rc` was the expected structural outcome and the runner was told to reconcile the missing list by hand against the profile.

That is fixed. `collect_and_verify` builds `verify_args` with the profile first and `effective-vars.yaml` second, the same order and the same precedence the playbook itself receives, and it says so in the run output as `Running verification (with profile linux_live)`. Verification now expects exactly what the run was asked for.

So `verify_rc: 0` is the expectation for this scenario, like every other one, and a non-empty missing list is a defect rather than an artefact. Confirmed by the run of 2026-08-15T09-12-23Z: `playbook_rc: 0`, `verify_rc: 0`, `verify_failures: none`, and a verify recap of `ok=18 changed=0 failed=0 skipped=8`. The eight skips are the assertions the profile's disabled toggles correctly make inapplicable, which is the profile reaching verification rather than being ignored by it.

`Assert the expected desktop environment is installed` does not run. The scenario declares `e2e_expect_desktop: none`.

Known container limitations. [../tier3/container_limits.yaml](../tier3/container_limits.yaml) forces `setup_hibernate`, `setup_systemd_boot`, `setup_grub`, `remove_distro_grub`, `remove_distro_systemd_boot`, `install_waydroid`, `install_virtualbox`, `install_vmware` and `install_snapper` to false on top of every scenario. Two of those matter more here than elsewhere: a live USB install is exactly where bootloader work and `boot_repair` belong, and the container cannot cover any of it. The harness prints the suppressed list on every run, and a pass here is not evidence about any entry in it.

Two documented consequences that must not be read as regressions. Kernel modules never build, because `/usr/lib/modules` belongs to the host, so anything using DKMS reports missing headers. The profile already turns OpenRazer off with exactly that reasoning written next to it, so on this scenario the effect is mostly moot. Second, there is no login session, so tasks that need a live user D-Bus take their documented fallback path.

---

## Fixtures

None. The inputs are [../tier3/scenarios/05-live-profile.yaml](../tier3/scenarios/05-live-profile.yaml), [../../setup/ansible/profiles/linux_live.yaml](../../setup/ansible/profiles/linux_live.yaml), the toggle files under [../../setup/ansible/group_vars/](../../setup/ansible/group_vars/), [../tier3/container_limits.yaml](../tier3/container_limits.yaml), and the copy of [../../setup/](../../setup/) the harness places in the container. Note that `effective-vars.yaml` in the run directory records the scenario keys and the container limits but not the profile, which is passed as a separate `-e` argument, so reconstructing the full input means reading both that file and the profile.

---

## Concurrency

- Mutates: the throwaway container's own filesystem, and nothing else on the machine under test. On the host it writes one directory under `e2e/runs/<timestamp>_live-profile/`, unique per run, and it builds or reuses the shared image tag `installationhelper-e2e-arch:latest`, which is the one real overlap with the other container capabilities and is over-declared here on purpose.
- Conflicts with: no other capability test at the level of state, because each container scenario gets its own container and their filesystems cannot touch. They do contend for the host Docker daemon, host disk and network bandwidth, and each installs gigabytes. Two hours is long enough that sharing a machine with a 300 minute scenario will push this one towards its declared timeout, and a timeout is a fail with a stated cause.
- Serial: false.
