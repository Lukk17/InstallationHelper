# desktop-environments: e2e test

Tier 3 of the harness, scenarios [../tier3/scenarios/03-kde-full.yaml](../tier3/scenarios/03-kde-full.yaml) and [../tier3/scenarios/04-gnome-full.yaml](../tier3/scenarios/04-gnome-full.yaml). Declared timeout 300 minutes each, so this capability is two runs and up to ten hours of wall clock. Reproduces the wizard's desktop environment screen with `kde` or `gnome` chosen and the `full` action.

Section headings sit at level two because the `e2e-runbooks` test-spec template fixes the seven section names at that level, which overrides this repository's level-three heading rule.

---

## What this verifies

- The playbook installs and configures KDE Plasma when the wizard's `kde` plus `full` answers are given, and exits 0. Verification probes `pacman -Qq plasma-desktop` and asserts it exits 0, which is the only observable this suite has for the desktop environment actually arriving.
- The playbook installs and configures GNOME when the wizard's `gnome` plus `full` answers are given, and exits 0. Verification probes `pacman -Qq gnome-shell` the same way.
- The two desktop environments do not need each other. Each scenario sets its own pair of install and configure flags true and the other pair false, so a configure task that silently depends on the other desktop's packages shows up as a failure in exactly one of the two runs.
- Neither desktop environment toggle installs nothing while reporting success. Neither `kde_plasma` nor `gnome` appears in [../../setup/ansible/vars/Archlinux.yaml](../../setup/ansible/vars/Archlinux.yaml), because both are handled by their own roles rather than by the dynamic package dispatcher, so the desktop probe is the only thing standing between a broken role and a green run. This is the "Toggles enabled with no mapping and no task" class of defect from [../../docs/regression_ledger.md](../../docs/regression_ledger.md), where the user asks for software, the run reports success, and the software is absent.
- The default software set still installs alongside a full desktop environment build. Both scenarios leave the software toggles at their [../../setup/ansible/group_vars/](../../setup/ansible/group_vars/) values, so verification asserts the whole default expected set against `pacman -Qq` and `flatpak list --app --columns=application`. Same guard as the "Pacman batch failure marked as success" and "Install block rescue hides which task failed" ledger entries.
- The per-distribution group names and the systemd unit still resolve on this path, and the temporary passwordless sudoers entry is gone. `id -nG` must contain `os_dict.openrazer_device_group` and `docker`, `systemctl is-enabled tailscaled.service` must exit 0, and `/etc/sudoers.d/99-ansible-user` must not exist. Same ledger entries as capability 60.

[AGENTS.md](../../AGENTS.md) names both of these scenarios as mandatory when a change touches the desktop environment roles, which is why they are one capability rather than two: neither answer to the desktop environment question is covered until both have run.

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

Confirm there is real disk headroom, because this capability builds two containers, each with a full desktop environment plus the default software set.

```bash
df -h /var/lib/docker
```

Expect many tens of gigabytes free. Run the two scenarios one after the other rather than together if headroom is tight, and the second run's container is only created when you launch it.

Confirm no container is left over from an aborted run.

```bash
docker ps -a --filter name=e2e-arch- --format '{{.Names}}'
```

Expect empty output.

Confirm the harness still knows both scenarios by name.

```bash
./e2e/run.sh --list
```

Expect a row reading `kde-full` and a row reading `gnome-full`, each with `timeout 300 min`.

Confirm the working tree holds exactly the change you intend to test.

```bash
git status --short setup
```

Expect only your own edits. The harness copies [../../setup/](../../setup/) into the container rather than bind-mounting it.

---

## Reset state

Nothing to reset inside the machines under test. Each of the two runs builds its own throwaway container and its own directory under `e2e/runs/`, so the KDE run and the GNOME run cannot contaminate each other even when they overlap.

Remove any leftover container the prerequisite check listed, substituting the name it printed. Skip this when the output was empty.

```bash
docker rm -f <container-name>
```

Force a rebuild of the base image, and only when [../tier3/arch.Dockerfile](../tier3/arch.Dockerfile) changed since the last run. Do it before step 1, never between the two runs, so both scenarios test the same image.

```bash
docker image rm installationhelper-e2e-arch:latest
```

---

## Run

Four steps, two launches and two collections. At five hours each, neither run should be tied to the shell that started it.

Step 1. Launch the KDE run and return.

```bash
./e2e/tier3/container.sh e2e/tier3/scenarios/03-kde-full.yaml --detach
```

From a PowerShell prompt on Windows, the same launch inside WSL.

```powershell
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && ./e2e/tier3/container.sh e2e/tier3/scenarios/03-kde-full.yaml --detach"
```

Step 2. Launch the GNOME run and return. Do this immediately after step 1 only if the machine has the disk and bandwidth for two 300 minute installs at once, otherwise wait until step 3 has finished. See the Concurrency section.

```bash
./e2e/tier3/container.sh e2e/tier3/scenarios/04-gnome-full.yaml --detach
```

Follow either run from any shell, using the container name that launch printed.

```bash
docker exec <container-name> tail -f /work/playbook.log
```

Step 3. Wait until the KDE playbook has finished, then verify, record and tear down, substituting the run directory step 1 printed. Collecting early is safe: it reports the task currently executing and exits 3 without touching anything.

```bash
./e2e/tier3/container.sh --collect e2e/runs/<kde-run-id>
```

Step 4. The same for the GNOME run, using the run directory step 2 printed.

```bash
./e2e/tier3/container.sh --collect e2e/runs/<gnome-run-id>
```

---

## Expected

Both runs must pass for this capability to pass. One green and one red is a FAIL, and the Result summary must say which.

For each run, `result.txt` in its own run directory reports `playbook_rc: 0` and `verify_rc: 0`.

The verify log of each run carries these assertions, each on its own PASS or FAIL line. Every container scenario runs the same [../tier3/verify.yaml](../tier3/verify.yaml), so the list is the same for all of them and only the expected sets differ. Each item names its verify task verbatim, so [../tier1/verify_spec_parity.sh](../tier1/verify_spec_parity.sh) can prove this list is complete rather than leaving it to be noticed.

1. `Assert every enabled native package is installed`, checked against `pacman -Qq`. The expected set is the default toggle set mapped to `pacman` or `aur` in `vars/Archlinux.yaml`, minus whatever the container limits turned off. The desktop environment packages are not part of this set, since neither desktop toggle is in the dictionary.
2. `Assert every enabled flatpak application is installed`, checked against `flatpak list --app --columns=application`.
3. `Assert tailscaled is enabled when Tailscale was requested`, from `systemctl is-enabled tailscaled.service`.
4. `Assert the user is in the OpenRazer device group when OpenRazer was requested`, from `id -nG` against `os_dict.openrazer_device_group`, which is `openrazer` on Arch.
5. `Assert the user is in the docker group when Docker was requested`, from `id -nG`.
6. `Assert docker.service is enabled when Docker was requested`.
7. `Assert flatpak is installed and the Flathub remote is configured`.
8. `Assert the temporary passwordless sudoers entry was removed`, meaning `/etc/sudoers.d/99-ansible-user` does not exist.
9. `Assert the expected desktop environment is installed`. In the KDE run the probe is `pacman -Qq plasma-desktop`, in the GNOME run it is `pacman -Qq gnome-shell`, and the assertion requires exit 0. This is the one assertion that separates this capability from capability 60, and the only scenario pair where it runs at all.

Note what assertion 9 does not cover. It proves the desktop environment's main package is present, and nothing more. Whether the configure half of the `full` action actually applied a setting is not asserted anywhere, and could not be in a container without a session: the two runs turn `configure_kde_plasma` and `configure_gnome` on, so those tasks execute and their failures would surface as a non-zero playbook exit code, but a configure task that succeeds while writing the wrong value passes here. Record any configure oddity you see in the log under the Result summary rather than as a ticked assertion.

Known container limitations. [../tier3/container_limits.yaml](../tier3/container_limits.yaml) forces `setup_hibernate`, `setup_systemd_boot`, `setup_grub`, `remove_distro_grub`, `remove_distro_systemd_boot`, `install_waydroid`, `install_virtualbox`, `install_vmware` and `install_snapper` to false on top of every scenario, because each needs hardware or a kernel facility that belongs to the host. The harness prints that list on every run, and a pass here is not evidence about any entry in it.

Two documented consequences that must not be read as regressions, and both bite harder on a desktop environment run than anywhere else. Kernel modules never build, because `/usr/lib/modules` belongs to the host, so anything using DKMS reports missing headers, which is the "Arch OpenRazer kernel module never builds" ledger entry. And there is no login session, so tasks that need a live user D-Bus take their documented fallback path: a desktop environment configured with no session to apply it to is the normal outcome here, and neither the KDE nor the GNOME configure step can be judged by whether the desktop looks right, because nothing ever renders.

---

## Fixtures

None. The inputs are the two scenario files, the toggle files under [../../setup/ansible/group_vars/](../../setup/ansible/group_vars/), [../tier3/container_limits.yaml](../tier3/container_limits.yaml), and the copy of [../../setup/](../../setup/) the harness places in each container. Each run writes its own `effective-vars.yaml`, and the two differ only in the four desktop environment flags.

---

## Concurrency

- Mutates: each run's own throwaway container filesystem, and nothing else on the machines under test. On the host each writes its own directory under `e2e/runs/<timestamp>_kde-full/` and `e2e/runs/<timestamp>_gnome-full/`, and both build or reuse the shared image tag `installationhelper-e2e-arch:latest`, which is the one real overlap and is over-declared here on purpose.
- Conflicts with: nothing at the level of state, not even its own sibling run. The KDE container and the GNOME container are separate machines as far as the playbook is concerned. What they do share is the host Docker daemon, host disk and network bandwidth, and each one installs gigabytes including a full desktop environment. Running both at once is the heaviest thing this suite can ask of a machine, and two concurrent 300 minute installs will thrash a single host even though nothing corrupts: expect both to slow down, and expect a timeout, which counts as a fail, well before you expect corruption. On anything other than a dedicated machine with fast disk and plenty of headroom, run step 1 and step 3 first, then step 2 and step 4.
- Serial: false.
