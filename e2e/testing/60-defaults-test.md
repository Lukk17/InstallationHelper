# defaults: e2e test

Tier 3 of the harness, scenario [../tier3/scenarios/01-defaults.yaml](../tier3/scenarios/01-defaults.yaml). Declared timeout 180 minutes. Reproduces the wizard's step 2 `defaults` choice with the desktop environment set to `skip`, which is what pressing Enter through the wizard gives you and what `setup.sh --non-interactive` runs.

Section headings sit at level two because the `e2e-runbooks` test-spec template fixes the seven section names at that level, which overrides this repository's level-three heading rule.

---

## What this verifies

- The playbook runs to completion with no overrides at all and exits 0. The scenario file sets no toggle of its own, so [../../setup/ansible/group_vars/](../../setup/ansible/group_vars/) is the whole input apart from the container limits. This is the configuration most users actually get, so it is the one where a silent gap costs the most.
- Every package the default toggle set asks for is installed. Verification compares the expected set against `pacman -Qq` and `flatpak list --app --columns=application` and names anything missing. This is the broadest instance of the guard behind the "Pacman batch failure marked as success" entry in [../../docs/regression_ledger.md](../../docs/regression_ledger.md), where a two-item `failed_when` combined with AND meant one could-not-find error marked the task `ok` and dropped every pacman package while the playbook reported success, and of the "Install block rescue hides which task failed" entry, where any failure inside the shared install block skipped the rest of it behind one anonymous warning.
- A toggle that is enabled by default and mapped for Arch actually resolves to a real package on Arch. This is the live counterpart to the "Package and repository facts that only held for one distribution" ledger entry, where Arch had dropped `arduino` from its repositories and the FreeCAD Flathub id had been renamed, and it is also the only coverage apt and dnf names get anywhere in the suite, which today means none, because tier 3 runs Arch only.
- The user ends up in the per-distribution device group and in `docker`. `id -nG` must contain the group named by `os_dict.openrazer_device_group` and `docker`, both toggles being true by default. Same "Arch OpenRazer device group does not exist" ledger entry, where `plugdev` was hardcoded and does not exist on Arch.
- `tailscaled` is enabled, since `install_tailscale` is true by default.
- The temporary passwordless sudoers entry is gone, asserted by `stat` on `/etc/sudoers.d/99-ansible-user`. Same "`playbook_succeeded` reported true regardless of what the rescue actually caught" ledger entry.

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

Expect at least tens of gigabytes free. This scenario installs the whole default software set, including several large downloads.

Confirm no container is left over from an aborted run.

```bash
docker ps -a --filter name=e2e-arch- --format '{{.Names}}'
```

Expect empty output.

Confirm the harness still knows this scenario by name.

```bash
./e2e/run.sh --list
```

Expect a row reading `defaults` with its description and `timeout 180 min`.

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

Force a rebuild of the base image, and only when [../tier3/arch.Dockerfile](../tier3/arch.Dockerfile) changed since the last run.

```bash
docker image rm installationhelper-e2e-arch:latest
```

---

## Run

Two steps, because three hours should not be tied to the shell that started it. The playbook always runs detached inside the container, so an ordinary disconnect cannot throw the run away.

Step 1. Launch and return. The command prints the run directory, the container name, and the two commands to follow and to collect.

```bash
./e2e/tier3/container.sh e2e/tier3/scenarios/01-defaults.yaml --detach
```

From a PowerShell prompt on Windows, the same launch inside WSL.

```powershell
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && ./e2e/tier3/container.sh e2e/tier3/scenarios/01-defaults.yaml --detach"
```

Follow it from any shell, as often as you like, using the container name the launch printed.

```bash
docker exec <container-name> tail -f /work/playbook.log
```

Step 2. Wait until step 1's playbook has finished, then verify, record and tear down, substituting the run directory the launch printed. Collecting early is safe: it reports the task currently executing and exits 3 without touching anything.

```bash
./e2e/tier3/container.sh --collect e2e/runs/<run-id>
```

The single-command form below does the same work in the foreground and is fine when you can leave a shell open for three hours.

```bash
./e2e/run.sh --tier 3 --scenario defaults
```

---

## Expected

`result.txt` in the run directory reports `playbook_rc: 0` and `verify_rc: 0`. Both are recorded independently, and verification runs whatever the playbook's exit code was, because a failed run still has state worth asserting on.

The verify log carries these assertions, each on its own PASS or FAIL line.

1. Every enabled native package is installed, checked against `pacman -Qq`. The expected set is every toggle true in `group_vars/all.yaml` and `group_vars/linux.yaml` that [../../setup/ansible/vars/Archlinux.yaml](../../setup/ansible/vars/Archlinux.yaml) maps to `pacman` or `aur`, minus whatever the container limits turned off. The tally line states how many were expected and how many are missing, and a failure names them.
2. Every enabled flatpak application is installed, checked against `flatpak list --app --columns=application`.
3. `systemctl is-enabled tailscaled.service` exits 0.
4. `id -nG` for the invoking user contains `os_dict.openrazer_device_group`, which is `openrazer` on Arch.
5. `id -nG` contains `docker`.
6. `/etc/sudoers.d/99-ansible-user` does not exist.

No desktop environment assertion runs. The scenario declares `e2e_expect_desktop: none`, which is the wizard's `skip` answer, and both `install_kde_plasma` and `install_gnome` are false by default.

One thing is collected but not asserted: verification runs `systemctl is-enabled docker.service` and registers the result, and nothing checks it. Docker on Arch is installed by the `virtualization_config` role rather than through the OS dictionary, so it is also absent from the expected native set, and the `docker` group membership in assertion 5 is the only pass criterion this suite has for it.

Known container limitations. [../tier3/container_limits.yaml](../tier3/container_limits.yaml) forces `setup_hibernate`, `setup_systemd_boot`, `setup_grub`, `remove_distro_grub`, `remove_distro_systemd_boot`, `install_waydroid`, `install_virtualbox`, `install_vmware` and `install_snapper` to false on top of every scenario, because each needs hardware or a kernel facility that belongs to the host. The harness prints that list on every run. None of it is covered here, and this scenario is exactly where a reader is most likely to mistake a green run for full default coverage, so read the printed list.

Two documented consequences that must not be read as regressions. Kernel modules never build, because `/usr/lib/modules` belongs to the host, so anything using DKMS reports missing headers: with the default toggles that means `openrazer-driver-dkms` installs and its module does not build, the alpm hook still returns 0, and the recap stays green, which is the "Arch OpenRazer kernel module never builds" ledger entry in action. Second, there is no login session, so tasks that need a live user D-Bus take their documented fallback path, which is why Syncthing's user-scope unit is not running at the end of a container run.

---

## Fixtures

None. The inputs are [../tier3/scenarios/01-defaults.yaml](../tier3/scenarios/01-defaults.yaml), the toggle files under [../../setup/ansible/group_vars/](../../setup/ansible/group_vars/), [../tier3/container_limits.yaml](../tier3/container_limits.yaml), and the copy of [../../setup/](../../setup/) the harness places in the container. The exact merged input is written to `effective-vars.yaml` in the run directory.

---

## Concurrency

- Mutates: the throwaway container's own filesystem, and nothing else on the machine under test. On the host it writes one directory under `e2e/runs/<timestamp>_defaults/`, unique per run, and it builds or reuses the shared image tag `installationhelper-e2e-arch:latest`, which is the one real overlap with the other container capabilities and is over-declared here on purpose.
- Conflicts with: no other capability test at the level of state, because each container scenario gets its own container and their filesystems cannot touch. They do contend for the host Docker daemon, host disk and network bandwidth, and each installs gigabytes. At three hours this is one of the four expensive scenarios, and running several of those at once will thrash a single machine even though nothing corrupts: the likely outcome is that both runs crawl and one hits its declared timeout, which counts as a fail.
- Serial: false.
