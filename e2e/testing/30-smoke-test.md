# smoke: e2e test

Tier 3 of the harness, scenario [../tier3/scenarios/07-smoke.yaml](../tier3/scenarios/07-smoke.yaml). Declared timeout 45 minutes, the cheapest container scenario and the one to run before a commit that touches groups, systemd units or per-distribution behaviour.

Section headings sit at level two because the `e2e-runbooks` test-spec template fixes the seven section names at that level, which overrides this repository's level-three heading rule.

---

## What this verifies

- The playbook runs to completion as a normal user escalating with sudo inside a systemd-enabled Arch container, and exits 0. Not a wizard path: this scenario turns every software toggle off with `e2e_generate: no_software` and switches back on only the seven that sit on top of a defect this project has actually shipped.
- The user ends up in the OpenRazer device group whose name Arch actually uses. Verification reads `id -nG` and asserts that `os_dict.openrazer_device_group` is in the list. This exists for the "Arch OpenRazer device group does not exist" entry in [../../docs/regression_ledger.md](../../docs/regression_ledger.md), where `groups: plugdev` was hardcoded in a shared task file, Arch has no `plugdev` group at all before or after installing OpenRazer, and `usermod -a -G plugdev` exited 6 on every Arch run while the surrounding rescue reduced it to one anonymous warning.
- The user ends up in the `docker` group. Same class of defect, same read of `id -nG`. Docker on Arch is installed by the `virtualization_config` role rather than through the OS dictionary, so the group membership is the only observable this scenario has for it.
- `tailscaled` is enabled. Verification asserts `systemctl is-enabled tailscaled.service` exits 0, which is only meaningful because the container runs real systemd as PID 1.
- The packages the enabled toggles map to are actually installed. Verification compares the expected set against `pacman -Qq` and `flatpak list --app --columns=application`, so one package silently dropped from a batch is caught. This exists for the "Pacman batch failure marked as success" ledger entry, where a two-item `failed_when` combined with AND meant any could-not-find error marked the task `ok` and silently dropped every pacman package while the playbook reported success end to end.
- Steam comes from multilib, which covers `arch_core` enabling multilib before the batched pacman install. Chkrootkit comes from the AUR, which covers `arch_core` building an AUR helper from source at all, since the base image deliberately ships no `base-devel`, no git and no helper. Polychromatic comes from Flathub, which covers `arch_core` setting up the remote.
- The temporary passwordless sudoers entry is gone. Verification asserts `/etc/sudoers.d/99-ansible-user` does not exist. This exists for the "`playbook_succeeded` reported true regardless of what the rescue actually caught" ledger entry, where the cleanup that removes that grant ran the same way whether the run had succeeded or been silently rescued. Leaving the file behind leaves NOPASSWD sudo in place permanently.

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

Expect a daemon summary. On Windows that means Docker Desktop running with WSL integration enabled. The container needs `--privileged` and the host cgroup mount, so a rootless or restricted daemon will not do.

Confirm there is disk headroom.

```bash
df -h /var/lib/docker
```

Expect several gigabytes free. The base image is small, but this scenario installs Steam out of multilib and builds an AUR package from source.

Confirm no container is left over from an aborted run.

```bash
docker ps -a --filter name=e2e-arch- --format '{{.Names}}'
```

Expect empty output. A leftover container does not collide with this run, which names its own after the scenario and the launching process id, but it holds disk and confuses the next `--collect`.

Confirm the harness still knows this scenario by name.

```bash
./e2e/run.sh --list
```

Expect a row reading `smoke` with its description and `timeout 45 min`.

Confirm the working tree holds exactly the change you intend to test.

```bash
git status --short setup
```

Expect only your own edits. The harness copies [../../setup/](../../setup/) into the container rather than bind-mounting it, so what you see here is what the run gets, and the run cannot modify it back.

---

## Reset state

Nothing to reset inside the machine under test. Every run builds its own throwaway container and its own directory under `e2e/runs/`, and tears the container down at the end.

Remove any leftover container the prerequisite check listed, substituting the name it printed. Skip this when the output was empty.

```bash
docker rm -f <container-name>
```

Force a rebuild of the base image, and only when [../tier3/arch.Dockerfile](../tier3/arch.Dockerfile) changed since the last run. The build is cached otherwise, which is deliberate.

```bash
docker image rm installationhelper-e2e-arch:latest
```

---

## Run

One step. Run it from the repository root and wait. The harness builds the image, starts the container, waits for systemd, copies `setup/` in, installs the Ansible collections, launches the playbook detached inside the container, polls for it, then verifies and tears down.

```bash
./e2e/run.sh --tier 3 --scenario smoke
```

From a PowerShell prompt on Windows, the same run inside WSL.

```powershell
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && ./e2e/run.sh --tier 3 --scenario smoke"
```

While it runs, the playbook log can be followed from any other shell, using the container name the harness printed at startup.

```bash
docker exec <container-name> tail -f /work/playbook.log
```

Every command above targets Arch, which is what `--os` defaults to. The same scenario runs on the other three families by naming one, `--os debian`, `--os ubuntu` or `--os fedora`, each with its own Dockerfile and image tag under [../tier3/](../tier3/). A run is a run of this capability whichever family it targeted, so the record has to say which, and a green Arch run is not evidence about the others. Three defects found on 2026-08-15 existed only outside Arch: locale generation running before the package that enables it, the verify play unable to render the Debian dictionary at all, and the installed-package query returning one concatenated line on both the apt and rpm families.

---

## Expected

The command exits 0, and `result.txt` in the run directory reports `playbook_rc: 0` and `verify_rc: 0`. Either one non-zero is a fail, and both are recorded independently on purpose: verification runs whatever the playbook's exit code was, because a failed run still has state worth asserting on and knowing which parts survived is how a failure gets triaged.

The verify log carries these assertions, each on its own PASS or FAIL line. Every container scenario runs the same [../tier3/verify.yaml](../tier3/verify.yaml), so the list is the same for all of them and only the expected sets differ. Each item names its verify task verbatim, so [../tier1/verify_spec_parity.sh](../tier1/verify_spec_parity.sh) can prove this list is complete rather than leaving it to be noticed.

Before any of them, `Assert the installed-package query returned a plausible list` checks the input to the comparison rather than the comparison itself. It fails when the query behind the native package assertion returns fewer than fifty entries, which no working Linux installation does. It exists because a format string whose newline was being discarded made that query return one concatenated blob, so every expected package was reported missing and read exactly like a playbook that had installed nothing.

1. `Assert every enabled native package is installed`, checked against `pacman -Qq`. For this scenario the expected set is what [../../setup/ansible/vars/Archlinux.yaml](../../setup/ansible/vars/Archlinux.yaml) maps for `steam`, `syncthing`, `tailscale`, `openrazer` and `chkrootkit`, which resolves to `steam`, `syncthing`, `tailscale`, `openrazer-daemon` and the AUR `chkrootkit`. A failure names the missing packages.
2. `Assert every enabled flatpak application is installed`, checked against `flatpak list --app --columns=application`. For this scenario that is `app.polychromatic.controller`.
3. `Assert tailscaled is enabled when Tailscale was requested`, from `systemctl is-enabled tailscaled.service`.
4. `Assert the user is in the OpenRazer device group when OpenRazer was requested`, from `id -nG` against `os_dict.openrazer_device_group`, which is `openrazer` on Arch.
5. `Assert the user is in the docker group when Docker was requested`, from `id -nG`.
6. `Assert docker.service is enabled when Docker was requested`.
7. `Assert flatpak is installed and the Flathub remote is configured`. This scenario is where that matters most: it is the assertion for the ledger's first entry, where flatpak was installed only for Debian and RedHat while the Flathub remote-add ran on every Linux, so on Arch it shelled out to a missing binary and the run died fifteen minutes in with nothing installed. The scenario also exercises the whole of `system_core`, which is where the missing `Install flatpak (Arch)` task now lives.
8. `Assert the temporary passwordless sudoers entry was removed`, meaning `/etc/sudoers.d/99-ansible-user` does not exist.

`Assert the expected desktop environment is installed` does not run here. The scenario declares `e2e_expect_desktop: none`, so the probe is skipped rather than asserted absent.

Known container limitations. [../tier3/container_limits.yaml](../tier3/container_limits.yaml) forces `setup_hibernate`, `setup_systemd_boot`, `setup_grub`, `remove_distro_grub`, `remove_distro_systemd_boot`, `install_waydroid`, `install_virtualbox`, `install_vmware` and `install_snapper` to false on top of every scenario, because each needs hardware or a kernel facility that belongs to the host. The harness prints that list on every run. Nothing in it is covered here, and a pass is not evidence about any of them.

Two documented consequences that must not be read as regressions. Kernel modules never build, because `/usr/lib/modules` belongs to the host, so anything using DKMS reports missing headers. That is directly visible in this scenario: `openrazer-daemon` pulls `openrazer-driver-dkms`, the module build fails with a console message, the alpm hook still returns 0, and the play recap stays green. The package is installed, which is what assertion 1 checks, and the driver is not functional, which no container can check. Second, there is no login session, so tasks that need a live user D-Bus take their documented fallback path. Syncthing is in this scenario specifically to cover that branch, so a user-scope unit that is not running is the expected outcome here.

---

## Fixtures

None. The inputs are [../tier3/scenarios/07-smoke.yaml](../tier3/scenarios/07-smoke.yaml), [../tier3/container_limits.yaml](../tier3/container_limits.yaml), and the copy of [../../setup/](../../setup/) the harness places in the container. The exact merged input is written to `effective-vars.yaml` in the run directory, in the order the scenario keys first, then any generated software block, then the container limits last so they always win.

---

## Concurrency

- Mutates: the throwaway container's own filesystem, and nothing else on the machine under test. On the host it writes one directory under `e2e/runs/<timestamp>_smoke/`, which is unique per run, and it builds or reuses the shared image tag `installationhelper-e2e-arch:latest`. That shared tag is the one real overlap with the other container capabilities, and it is over-declared here on purpose: two runs starting at the same moment can both build it, which is wasteful rather than harmful because the Dockerfile is identical for both.
- Conflicts with: no other capability test at the level of state. Each container scenario gets its own container, so their filesystems cannot touch. They do contend for the host Docker daemon, host disk and network bandwidth, and every one of them installs gigabytes of packages, so running several at once slows all of them and can exhaust disk. Running several 300 minute scenarios concurrently will thrash a single machine even though nothing corrupts. This is the cheapest scenario, so when it shares a machine with a longer one, expect its wall clock to exceed the 45 minute timeout it declares and to fail on time rather than on state.
- Serial: false.
