# picked-apps: e2e test

Tier 3 of the harness, scenario [../tier3/scenarios/09-picked-apps.yaml](../tier3/scenarios/09-picked-apps.yaml). Declared timeout 90 minutes, not measured yet. Reproduces `setup.sh --software none --enable install_kicad9`, a picked-apps run that asks for KiCad 9 and nothing else.

Section headings sit at level two because the `e2e-runbooks` test-spec template fixes the seven section names at that level, which overrides this repository's level-three heading rule.

---

## What this verifies

- A custom install runs when the run requests no mapped package at all. KiCad 9 is the AppImage [../../setup/ansible/roles/software_installer/tasks/custom_installs.yaml](../../setup/ansible/roles/software_installer/tasks/custom_installs.yaml) puts in `/opt/kicad9`, with one menu entry per tool in `/usr/local/share/applications` and one icon per tool, and no `software_mapping` entry. Until 2026-11-13 the custom installs sat in the block that runs only when a mapped package was requested, so the owner's run of exactly this command installed nothing, [../../docs/regression_ledger.md](../../docs/regression_ledger.md) 10.285.
- A picked-apps run leaves the machine's own configuration alone. env_variables, linux_security, systemd_boot, the system settings and full upgrade of system_core, the `/sbin` PATH file of debian_core and the package cache cleanup in the post_tasks of [../../setup/ansible/site.yaml](../../setup/ansible/site.yaml) stay out of it, because `ih_picked_apps_run` in [../../setup/ansible/group_vars/all.yaml](../../setup/ansible/group_vars/all.yaml) is true. The owner's run wrote the development environment, set mode 755 on his home directory and cleaned every package cache, 10.287 and 10.289.
- The install steps a picked app needs still run: the temporary sudo grant and its removal, the package database refresh, flatpak with the Flathub remote, the temporary installation folder and its removal, and the `fuse3` companion package the AppImage's runtime mounts with.
- The scenario reproduces what setup.sh resolves the flags into, `e2e_generate: no_software`, `install_kicad9: true` and `ih_picked_apps: "install_kicad9"`, because the harness starts setup.sh with `--profile`, beside which setup.sh refuses `--software`. [../tier1/picked_apps_scope.sh](../tier1/picked_apps_scope.sh) proves in tier 1 that setup.sh writes that `ih_picked_apps` line for those flags, so the scenario and the wizard cannot drift apart unnoticed.

---

## Prerequisites

This capability never runs on the owner's computer. Its scenario containers are privileged and share the kernel of the machine Docker runs on, and on the owner's computer they changed his kernel, entries 10.126 to 10.129 of [../../docs/regression_ledger.md](../../docs/regression_ledger.md). It runs only on a GitHub-hosted runner, dispatched with the command under Run, where the workflow runs the commands below for you. Anywhere else `e2e/run.sh --tier 3` and `e2e/tier3/container.sh` print `REFUSED` and exit 2 before any container starts, and there is no override. No other virtual machine qualifies, a local one, WSL 2 and Docker Desktop alike, by the owner's decision 79. The rule and how the machine is recognised are under "Tier 3 runs only on a GitHub-hosted runner" in [../README_E2E.md](../README_E2E.md).

On the runner the scenario driver runs inside the gate container, which `e2e/run.sh` and `e2e/tier3/container.sh` build and enter by themselves, so the runner needs a Docker daemon and nothing else.

Confirm the Docker daemon is reachable.

```bash
docker info
```

Expect a daemon summary. The container needs `--privileged` and a private cgroup namespace, never the host's, and it runs with the unit masks and the host state guard described under "What a container cannot test" in [../README_E2E.md](../README_E2E.md).

Confirm there is disk headroom.

```bash
df -h /var/lib/docker
```

Expect a few gigabytes free. The run installs the bootstrap packages and one AppImage, and none of the software set.

Confirm no container is left over from an aborted run.

```bash
docker ps -a --filter name=e2e- --format '{{.Names}}'
```

Expect empty output.

Confirm the harness still knows this scenario by name.

```bash
./e2e/run.sh --list
```

Expect a row reading `picked-apps` with its description and `timeout 90 min`.

Confirm the working tree holds exactly the change you intend to test.

```bash
git status --short setup
```

Expect only your own edits. The harness copies [../../setup/](../../setup/) into the container rather than bind-mounting it.

---

## Reset state

Nothing to reset inside the machine under test. Every run builds its own throwaway container and its own directory under `e2e/runs/`, and tears the container down at the end. Before the playbook starts, the harness seeds the per-user Flatpak cache `~/.var/app/io.github.ih_e2e.PickedAppsSentinel/cache/seeded-before-the-run` inside the container, which "Clean Flatpak per-user app caches" would delete.

Remove any leftover container the prerequisite check listed, substituting the name it printed. Skip this when the output was empty.

```bash
docker rm -f <container-name>
```

Force a rebuild of the base image, and only when the Dockerfile for the distribution you are targeting changed since the last run, [../tier3/arch.Dockerfile](../tier3/arch.Dockerfile) by default and one of the others beside it.

```bash
docker image rm installationhelper-e2e-arch:latest
```

---

## Run

One step. Run it from the repository root and wait.

```bash
./e2e/run.sh --tier 3 --scenario picked-apps
```

The command above is what a GitHub-hosted runner runs, and it exits 2 anywhere else, so dispatch the same scenario to GitHub-hosted runners. It runs stage 1 and that one stage 2 cell of [../../.github/workflows/e2e-matrix.yml](../../.github/workflows/e2e-matrix.yml), and stage 3 on macOS and Windows as well, because stage 3 always runs. CachyOS is the distribution of the owner's run. The command is the same from a Unix shell and from PowerShell.

```bash
gh workflow run e2e-matrix.yml -f scenario=picked-apps -f distro=cachyos
```

```powershell
gh workflow run e2e-matrix.yml -f scenario=picked-apps -f distro=cachyos
```

While it runs, the playbook log can be followed from any other shell, using the container name the harness printed at startup.

```bash
docker exec <container-name> tail -f /work/playbook.log
```

The sweep runs this scenario on all six distributions, Debian, Ubuntu, Pop!_OS, Fedora, Arch and CachyOS, each as its own stage 2 job named `<Distro> picked apps`. A run is a run of this capability whichever distribution it targeted, so the record has to say which.

---

## Expected

The command exits 0, and `result.txt` in the run directory reports `playbook_rc: 0` and `verify_rc: 0`. It also reports the two `host_isolation:` lines every container scenario reports, and the first must read `host_isolation: 0 finding(s)`. The second lists kernel settings and modules that differ from the boot record as information only, by owner decision 86.

The harness asks two things of the container's disk after the run, each on its own PASS or FAIL line, because a skipped step leaves no line in the log to read:

- `the per-user Flatpak cache seeded before the run is still there, so the cleanup in site.yaml stayed out of this picked-apps run`.
- `~/.config/environment.d/990-dev.conf does not exist, so env_variables stayed out of this picked-apps run`.

The verify log carries these assertions, each on its own PASS or FAIL line. Every container scenario runs the same [../tier3/verify.yaml](../tier3/verify.yaml), so the list is the same for all of them and only the expected sets differ. Each item names its verify task verbatim, so [../tier1/verify_spec_parity.sh](../tier1/verify_spec_parity.sh) can prove this list is complete.

Before any of them, `Assert the installed-package query returned a plausible list` checks that the query behind the native package assertion returned at least fifty entries, which the base image alone does.

1. `Assert every enabled native package is installed`. The expected set is the `fuse3` companion package of KiCad 9, because every software key but `install_kicad9` is off.
2. `Assert every enabled URL-installed package resolved a download location`. No candidate here, since no mapped package is on.
3. `Assert every enabled flatpak application is installed`. The expected set is empty.
4. `Assert every enabled snap application is installed`, asked only when a snap mapping is expected, so it is skipped and passes.
5. `Assert tailscaled is enabled when Tailscale was requested`, skipped because the toggle is off.
6. `Assert the user is in the OpenRazer device group when OpenRazer was requested`, skipped because the toggle is off.
7. `Assert the user is in the docker group when Docker was requested`, skipped because the toggle is off.
8. `Assert docker.service is enabled when Docker was requested`, skipped because the toggle is off.
9. `Assert flatpak is installed and the Flathub remote is configured`. system_core still installs flatpak and adds Flathub in a picked-apps run, because the installs use them.
10. `Assert the temporary passwordless sudoers entry was removed`, meaning `/etc/sudoers.d/99-ansible-user` does not exist. The removal is in the `always` section of the post_tasks and runs in every run.
11. `Assert every enabled outside-package-manager tool is installed and reachable from a plain interactive shell`. The one enabled entry is `kicad9`: the AppImage at `/opt/kicad9/` under its versioned name is executable, and for every tool in `kicad9_launchers` its menu entry `kicad9-<tool>.desktop` is in `/usr/local/share/applications` and its icon `kicad9-<tool>.svg` is in `/usr/local/share/icons/hicolor/scalable/apps`. This is the line that read `kicad9 MISSING` in the owner's run. On a processor other than x86_64 the entry is left out, because KiCad builds its Linux AppImage for x86_64 only.
12. `Assert the desktop session environment carries every development variable`. Linux only. It asks for nothing here, because `ih_env_variables_run` is false and verify_install.yaml asks for the env_variables variables only when env_variables ran, and no SDK toggle is on.
13. `Assert the command line package @opencode/cli replaces is gone`, skipped because `install_opencode` is off.

`Assert the expected desktop environment is installed` does not run here. The scenario declares `e2e_expect_desktop: none`, so verification neither requires nor forbids `plasma-desktop`.

Known container limitations. [../tier3/container_limits.yaml](../tier3/container_limits.yaml) forces `setup_hibernate`, `setup_systemd_boot`, `setup_grub`, `remove_distro_grub`, `remove_distro_systemd_boot`, `install_waydroid`, `install_virtualbox`, `install_vmware` and `install_snapper` to false on top of every scenario. So this run cannot show that linux_security and systemd_boot stay out of a picked-apps run on their own: here their settings are off anyway. Tier 1 proves it instead, in [../tier1/picked_apps_scope.sh](../tier1/picked_apps_scope.sh). There is no login session either, so no menu entry is opened, and an entry that exists but does not start KiCad is not caught here.

---

## Fixtures

None. The inputs are [../tier3/scenarios/09-picked-apps.yaml](../tier3/scenarios/09-picked-apps.yaml), the toggle files under [../../setup/ansible/group_vars/](../../setup/ansible/group_vars/), [../tier3/container_limits.yaml](../tier3/container_limits.yaml), and the copy of [../../setup/](../../setup/) the harness places in the container. The exact merged input is written to `effective-vars.yaml` in the run directory.

---

## Concurrency

- Mutates: the throwaway container's own filesystem, and nothing else on the machine under test. On the host it writes one directory under `e2e/runs/<timestamp>_picked-apps/`, unique per run, and it builds or reuses the shared image tag `installationhelper-e2e-<os>:latest`, which is the one real overlap with the other container capabilities and is over-declared here on purpose.
- Conflicts with: no other capability test at the level of state, because each container scenario gets its own container. They contend for the host Docker daemon, host disk and network bandwidth, which on a GitHub-hosted runner each job has to itself.
- Serial: false.
