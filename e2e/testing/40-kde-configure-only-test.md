# kde-configure-only: e2e test

Tier 3 of the harness, scenario [../tier3/scenarios/06-kde-configure-only.yaml](../tier3/scenarios/06-kde-configure-only.yaml). Declared timeout 90 minutes. Reproduces the wizard's desktop environment screen with `kde` chosen and the `configure` action.

Section headings sit at level two because the `e2e-runbooks` test-spec template fixes the seven section names at that level, which overrides this repository's level-three heading rule.

---

## What this verifies

- The playbook runs to completion with `install_kde_plasma: false` and `configure_kde_plasma: true`, and exits 0. This is the only wizard combination where the configure tasks cannot assume their own install step just ran, and in a container nothing installed Plasma beforehand, so the configure tasks execute against a desktop that is not there.
- A failure inside the KDE configure path does not get laundered into a green run. Verification asserts the same observable state as every other scenario, and `result.txt` records the playbook exit code separately from the verification exit code. This exists for the "Install block rescue hides which task failed" entry in [../../docs/regression_ledger.md](../../docs/regression_ledger.md), where a single `rescue` wrapped every package manager together and any failure printed one anonymous line, skipped the rest of the block, and left the play recap green, and for the "`playbook_succeeded` reported true regardless of what the rescue actually caught" entry.
- The default software set still installs while a desktop environment role is doing something unusual. This scenario sets no `e2e_generate` key, so the software toggles stay at their [../../setup/ansible/group_vars/](../../setup/ansible/group_vars/) values and verification asserts the whole default expected set against `pacman -Qq` and `flatpak list --app --columns=application`. This is the same guard as the "Pacman batch failure marked as success" ledger entry, where one wrong package name could silently drop every pacman package while the run reported success.
- The per-distribution group names still resolve on this path. `id -nG` must contain the group named by `os_dict.openrazer_device_group` and `docker`, both because those toggles are true by default. Same "Arch OpenRazer device group does not exist" ledger entry as capability 60.
- `tailscaled` is enabled, since `install_tailscale` is true by default.
- The temporary passwordless sudoers entry is gone, asserted by `stat` on `/etc/sudoers.d/99-ansible-user`.

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

Expect at least tens of gigabytes free. This scenario installs the whole default software set, which is most of what the playbook ships.

Confirm no container is left over from an aborted run.

```bash
docker ps -a --filter name=e2e- --format '{{.Names}}'
```

Expect empty output.

Confirm the harness still knows this scenario by name.

```bash
./e2e/run.sh --list
```

Expect a row reading `kde-configure-only` with its description and `timeout 90 min`.

Confirm the working tree holds exactly the change you intend to test.

```bash
git status --short setup
```

Expect only your own edits. The harness copies [../../setup/](../../setup/) into the container rather than bind-mounting it.

---

## Reset state

Nothing to reset inside the machine under test. Every run builds its own throwaway container and its own directory under `e2e/runs/`, and tears the container down at the end.

Remove any leftover container the prerequisite check listed, substituting the name it printed. Skip this when the output was empty.

```bash
docker rm -f <container-name>
```

Force a rebuild of the base image, and only when the Dockerfile for the distribution you are targeting changed since the last run, [../tier3/arch.Dockerfile](../tier3/arch.Dockerfile) by default and one of debian, ubuntu or fedora beside it.

```bash
docker image rm installationhelper-e2e-arch:latest
```

---

## Run

One step. Run it from the repository root and wait.

```bash
./e2e/run.sh --tier 3 --scenario kde-configure-only
```

The commands above and below are what a GitHub-hosted runner runs, and they exit 2 anywhere else, so dispatch the same scenario to GitHub-hosted runners. It runs stage 1 and that one stage 2 cell of [../../.github/workflows/e2e-matrix.yml](../../.github/workflows/e2e-matrix.yml), and stage 3 on macOS and Windows as well, because stage 3 always runs. The command is the same from a Unix shell and from PowerShell.

```bash
gh workflow run e2e-matrix.yml -f scenario=kde-configure-only -f distro=arch
```

```powershell
gh workflow run e2e-matrix.yml -f scenario=kde-configure-only -f distro=arch
```

While it runs, the playbook log can be followed from any other shell, using the container name the harness printed at startup.

```bash
docker exec <container-name> tail -f /work/playbook.log
```

Every command above targets Arch, which is what `--os` defaults to. The same scenario runs on the other three families by naming one, `--os debian`, `--os ubuntu` or `--os fedora`, each with its own Dockerfile and image tag under [../tier3/](../tier3/). A run is a run of this capability whichever family it targeted, so the record has to say which, and a green Arch run is not evidence about the others. Three defects found on 2026-08-15 existed only outside Arch: locale generation running before the package that enables it, the verify play unable to render the Debian dictionary at all, and the installed-package query returning one concatenated line on both the apt and rpm families.

---

## Expected

The command exits 0, and `result.txt` in the run directory reports `playbook_rc: 0` and `verify_rc: 0`.

It also reports `host_isolation: 0 finding(s)`, which means the host kernel's loaded modules, swap areas and sysctls matched the record taken at boot after every pass and at collection, no masked unit ran, and systemd knew it was in a container. This holds for every scenario, the forced-failure one included, and any finding fails the run. See "What a container cannot test" in [../README_E2E.md](../README_E2E.md).

The verify log carries these assertions, each on its own PASS or FAIL line. Every container scenario runs the same [../tier3/verify.yaml](../tier3/verify.yaml), so the list is the same for all of them and only the expected sets differ. Each item names its verify task verbatim, so [../tier1/verify_spec_parity.sh](../tier1/verify_spec_parity.sh) can prove this list is complete rather than leaving it to be noticed.

Before any of them, `Assert the installed-package query returned a plausible list` checks the input to the comparison rather than the comparison itself. It fails when the query behind the native package assertion returns fewer than fifty entries, which no working Linux installation does. It exists because a format string whose newline was being discarded made that query return one concatenated blob, so every expected package was reported missing and read exactly like a playbook that had installed nothing.

1. `Assert every enabled native package is installed`, checked against `pacman -Qq`. The expected set is every toggle true in `group_vars/all.yaml` and `group_vars/linux.yaml` that [../../setup/ansible/vars/Archlinux.yaml](../../setup/ansible/vars/Archlinux.yaml) maps to `pacman` or `aur`, minus whatever the container limits turned off. A failure names the missing packages, and the tally line states how many were expected.
2. `Assert every enabled URL-installed package resolved a download location`. Some packages install from a vendor URL rather than a repository, and both dispatch tasks skip silently when that URL renders empty, so this fails the run instead of letting it look clean. The candidate set is empty on Arch, because `vars/Archlinux.yaml` maps nothing to `apt_url` or `dnf_url`. On the Debian and Ubuntu images it is the enabled subset of the five `apt_url` mappings, and on Fedora the enabled subset of the four `dnf_url` mappings, so an Arch run does not prove this one and the assertion says so by reporting how many candidates it examined.
3. `Assert every enabled flatpak application is installed`, checked against `flatpak list --app --columns=application`.
4. `Assert tailscaled is enabled when Tailscale was requested`, from `systemctl is-enabled tailscaled.service`.
5. `Assert the user is in the OpenRazer device group when OpenRazer was requested`, from `id -nG` against `os_dict.openrazer_device_group`, which is `openrazer` on Arch.
6. `Assert the user is in the docker group when Docker was requested`, from `id -nG`.
7. `Assert docker.service is enabled when Docker was requested`.
8. `Assert flatpak is installed and the Flathub remote is configured`.
9. `Assert the temporary passwordless sudoers entry was removed`, meaning `/etc/sudoers.d/99-ansible-user` does not exist.

`Assert the expected desktop environment is installed` does not run here. The scenario declares `e2e_expect_desktop: none`, so verification neither requires nor forbids `plasma-desktop`. That is deliberate: the point of this scenario is the configure path, not an install.

10. `Assert every enabled outside-package-manager tool is installed and reachable from a plain interactive shell`. This scenario sets no `e2e_generate` key either, so every ai_tools and sdk_manager toggle stays at its default of true, and the assertion checks node, npm, nvm, pyenv, the four pinned Python builds, sdk, java, the four pinned Java majors, fvm, flutter, dart, sdkmanager, adb and the six npm-installed CLIs, each on disk and by name, at that same path, from an interactive non-login shell of `{{ non_root_user }}`'s real login shell. Same "Found on a real CachyOS machine on 2026-09-15" ledger entry as capability 60, and the same full default set, since this scenario changes nothing about the ai_tools or sdk_manager toggles.
11. `Assert the desktop session environment carries every development variable`. Linux only. It runs the systemd user environment generator as the user over `~/.config/environment.d`, which is what the user manager does at the next login, and asks for the development variables and PATH entries env_variables writes into `~/.config/environment.d/50-dev.conf`, plus NVM_DIR, SDKMAN_DIR, JAVA_HOME and PYENV_ROOT for the SDK toggles that are on, all of them here. A KDE configure run is the case the assertion was written for: Plasma takes its environment from that manager and never reads `.zshrc`.
12. `Assert exactly the selected OpenCode version is installed`. This scenario leaves `opencode_use_v1` false, so version 2 is selected. It asks two probes from [../../setup/ansible/tasks/opencode_version.yaml](../../setup/ansible/tasks/opencode_version.yaml), the same ones the role removed the other version with: whether the version 1 desktop app, the Flathub application `ai.opencode.opencode` is still installed, only when `install_opencode_desktop` is on, and whether the version 1 npm package `opencode-ai` is still installed under the LTS Node, only when `install_opencode` is on. A probe whose toggle is off is skipped and passes, a probe that could not run fails.

A gap to be honest about. The scenario file says the interesting question is whether the configure tasks fail cleanly with a readable message rather than blowing up halfway through, and states that the verify step checks it. [../tier3/verify.yaml](../tier3/verify.yaml) contains no assertion specific to the configure-only path. What actually distinguishes a clean failure from a messy one here is the playbook exit code plus the `errors_and_failures` block in `result.txt`, which the harness fills with the `fatal:`, `failed:` and `[ERROR]` lines from the log. Those lines are diagnostics for a human reading the run, not pass criteria, and a runner must not tick an assertion box for them. If the run exits 0 and the eight assertions above pass, this capability passed as specified, and the readability of any configure-path message is a judgement to record in the Result summary rather than a checkbox.

Known container limitations. [../tier3/container_limits.yaml](../tier3/container_limits.yaml) forces `setup_hibernate`, `setup_systemd_boot`, `setup_grub`, `remove_distro_grub`, `remove_distro_systemd_boot`, `install_waydroid`, `install_virtualbox`, `install_vmware` and `install_snapper` to false on top of every scenario, because each needs hardware or a kernel facility that belongs to the host. The harness prints that list on every run, and a pass here is not evidence about any of them.

Two documented consequences that must not be read as regressions. Kernel modules never build, because `/usr/lib/modules` belongs to the host, so anything using DKMS reports missing headers: with the default toggles that means `openrazer-driver-dkms` installs and its module does not build, the alpm hook still returns 0, and the recap stays green. Second, there is no login session, so tasks that need a live user D-Bus take their documented fallback path. That applies to the KDE configure tasks as much as to anything else, so a configure step that skips or degrades for want of a session is the expected outcome here, not a defect.

---

## Fixtures

None. The inputs are [../tier3/scenarios/06-kde-configure-only.yaml](../tier3/scenarios/06-kde-configure-only.yaml), the toggle files under [../../setup/ansible/group_vars/](../../setup/ansible/group_vars/), [../tier3/container_limits.yaml](../tier3/container_limits.yaml), and the copy of [../../setup/](../../setup/) the harness places in the container. The exact merged input is written to `effective-vars.yaml` in the run directory.

---

## Concurrency

- Mutates: the throwaway container's own filesystem, and nothing else on the machine under test. On the host it writes one directory under `e2e/runs/<timestamp>_kde-configure-only/`, unique per run, and it builds or reuses the shared image tag `installationhelper-e2e-arch:latest`, which is the one real overlap with the other container capabilities and is over-declared here on purpose.
- Conflicts with: no other capability test at the level of state, because each container scenario gets its own container and their filesystems cannot touch. They do contend for the host Docker daemon, host disk and network bandwidth, and each installs gigabytes. Running this alongside a 300 minute scenario will push its wall clock towards the 90 minute timeout it declares, and a timeout is a fail with a stated cause, not an inconclusive run.
- Serial: false.
