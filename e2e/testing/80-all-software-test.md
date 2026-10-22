# all-software: e2e test

Tier 3 of the harness, scenario [../tier3/scenarios/02-all-software.yaml](../tier3/scenarios/02-all-software.yaml). Declared timeout 300 minutes, and the most expensive thing in the suite. Reproduces the wizard's step 2 `customise` path followed by select-all in the checklist.

Section headings sit at level two because the `e2e-runbooks` test-spec template fixes the seven section names at that level, which overrides this repository's level-three heading rule.

---

## What this verifies

- The playbook runs to completion with every `install_` toggle forced true, and exits 0. The toggle list is generated at run time from [../../setup/ansible/group_vars/all.yaml](../../setup/ansible/group_vars/all.yaml) and [../../setup/ansible/group_vars/linux.yaml](../../setup/ansible/group_vars/linux.yaml) rather than written into the scenario file, so a newly added toggle is covered with no edit to the harness. A hand-maintained copy of that list would quietly stop covering new software, which is the silent-gap failure the whole suite exists to catch.
- Every mapped package on Arch resolves and installs, including the ones that ship disabled and are therefore exercised nowhere else. This is the only scenario that reaches a toggle whose default is false, and it is the live counterpart to the "Package and repository facts that only held for one distribution" entry in [../../docs/regression_ledger.md](../../docs/regression_ledger.md), where Arch had dropped `arduino` and the FreeCAD Flathub id had been renamed upstream.
- One bad package name cannot silently drop a whole batch. Verification compares the expected set against `pacman -Qq` and `flatpak list --app --columns=application` and names every miss. With the largest possible expected set, this is the strongest instance of the guard behind the "Pacman batch failure marked as success" entry, where a two-item `failed_when` combined with AND marked any could-not-find error as `ok`, and the "Install block rescue hides which task failed" entry, where one failure skipped the rest of the shared install block behind an anonymous warning.
- A long or stalled task fails on time instead of running forever. The scenario declares a 300 minute timeout and the harness enforces it while the playbook runs detached inside the container. This is the operational answer to the "FVM's interactive picker stalled a run for 8 hours with no signal" entry and to "A synchronous long task blocked the controller with no signal it was even alive", both of which are reachable here because the SDK and AI toggles are all on.
- The per-distribution group names and the systemd unit still resolve with everything enabled, and the temporary passwordless sudoers entry is gone. `id -nG` must contain `os_dict.openrazer_device_group` and `docker`, `systemctl is-enabled tailscaled.service` must exit 0, and `/etc/sudoers.d/99-ansible-user` must not exist. Same ledger entries as capability 60.

---

## Prerequisites

This capability never runs on the owner's computer. Its scenario containers are privileged and share the kernel of the machine Docker runs on, and on the owner's computer they changed his kernel, entries 10.126 to 10.129 of [../../docs/regression_ledger.md](../../docs/regression_ledger.md). It runs only on a GitHub-hosted runner, dispatched with the command under Run, where the workflow runs the commands below for you. Anywhere else `e2e/run.sh --tier 3` and `e2e/tier3/container.sh` print `REFUSED` and exit 2 before any container starts, and there is no override. No other virtual machine qualifies, a local one, WSL 2 and Docker Desktop alike, by the owner's decision 79. The rule and how the machine is recognised are under "Tier 3 runs only on a GitHub-hosted runner" in [../README_E2E.md](../README_E2E.md).

On the runner the scenario driver runs inside the gate container, which `e2e/run.sh` and `e2e/tier3/container.sh` build and enter by themselves, so the runner needs a Docker daemon and nothing else.

Confirm the Docker daemon is reachable.

```bash
docker info
```

Expect a daemon summary. The container needs `--privileged` and a private cgroup namespace, never the host's, and it runs with the unit masks and the host state guard described under "What a container cannot test" in [../README_E2E.md](../README_E2E.md).

Confirm there is serious disk headroom. This scenario installs everything the playbook can install on Arch, including two desktop environments, every IDE and every SDK.

```bash
df -h /var/lib/docker
```

Expect many tens of gigabytes free. A run that fills the disk halfway through produces a failure that looks like a package error and is not one.

Confirm no container is left over from an aborted run.

```bash
docker ps -a --filter name=e2e- --format '{{.Names}}'
```

Expect empty output. This matters more here than elsewhere, because a leftover container from a previous all-software attempt can be holding tens of gigabytes.

Confirm the harness still knows this scenario by name.

```bash
./e2e/run.sh --list
```

Expect a row reading `all-software` with its description and `timeout 300 min`.

Confirm the working tree holds exactly the change you intend to test.

```bash
git status --short setup
```

Expect only your own edits. The harness copies [../../setup/](../../setup/) into the container rather than bind-mounting it, and the generated toggle list is read from the group_vars files as they are on disk right now.

---

## Reset state

Nothing to reset inside the machine under test. Every run builds its own throwaway container and its own directory under `e2e/runs/`.

Remove any leftover container the prerequisite check listed, substituting the name it printed. Skip this when the output was empty.

```bash
docker rm -f <container-name>
```

Reclaim host disk from earlier runs before starting, since this scenario is the one most likely to run out.

```bash
docker system df
```

Force a rebuild of the base image, and only when the Dockerfile for the distribution you are targeting changed since the last run, [../tier3/arch.Dockerfile](../tier3/arch.Dockerfile) by default and one of debian, ubuntu or fedora beside it.

```bash
docker image rm installationhelper-e2e-arch:latest
```

---

## Run

Two steps. At five hours this must not be tied to the shell that started it, and the playbook always runs detached inside the container so an ordinary disconnect cannot throw the run away.

Step 1. Launch and return. The command prints the run directory, the container name, how many toggles it generated, and which ones it excluded.

```bash
./e2e/tier3/container.sh e2e/tier3/scenarios/02-all-software.yaml --detach
```

The commands above and below are what a GitHub-hosted runner runs, and they exit 2 anywhere else, so dispatch the same scenario to GitHub-hosted runners. It runs stage 1 and that one stage 2 cell of [../../.github/workflows/e2e-matrix.yml](../../.github/workflows/e2e-matrix.yml), and stage 3 on macOS and Windows as well, because stage 3 always runs. The command is the same from a Unix shell and from PowerShell.

```bash
gh workflow run e2e-matrix.yml -f scenario=all-software -f distro=arch
```

```powershell
gh workflow run e2e-matrix.yml -f scenario=all-software -f distro=arch
```

Follow it from any shell, as often as you like, using the container name the launch printed.

```bash
docker exec <container-name> tail -f /work/playbook.log
```

Step 2. Wait until step 1's playbook has finished, then verify, record and tear down, substituting the run directory the launch printed. Collecting early is safe: it reports the task currently executing and exits 3 without touching anything, so repeat it rather than guessing.

```bash
./e2e/tier3/container.sh --collect e2e/runs/<run-id>
```

Every command above targets Arch, which is what `--os` defaults to. The same scenario runs on the other three families by naming one, `--os debian`, `--os ubuntu` or `--os fedora`, each with its own Dockerfile and image tag under [../tier3/](../tier3/). A run is a run of this capability whichever family it targeted, so the record has to say which, and a green Arch run is not evidence about the others. Three defects found on 2026-08-15 existed only outside Arch: locale generation running before the package that enables it, the verify play unable to render the Debian dictionary at all, and the installed-package query returning one concatenated line on both the apt and rpm families.

---

## Expected

`result.txt` in the run directory reports `playbook_rc: 0` and `verify_rc: 0`.

It also reports two `host_isolation:` lines. The first must read `host_isolation: 0 finding(s)`, which means every host state record was written, binfmt_misc was never mounted, no masked unit ran, systemd knew it was in a container, and the host kernel's swap areas matched the record taken at boot after every pass and at collection. This holds for every scenario, the forced-failure one included, and any finding fails the run. The second lists every kernel setting and loaded module that differs from the boot record, as information only by owner decision 86, and never fails the run: it is expected to name the distribution's own `sysctl.d` defaults and the modules its packages load. That is safe only because the scenario container is privileged and changes the kernel of the machine running it, its kernel settings, binfmt_misc table, device events and modules, which is why this capability runs only on a throwaway GitHub-hosted runner and never on the owner's computer. See "What a container cannot test" in [../README_E2E.md](../README_E2E.md).

The verify log carries these assertions, each on its own PASS or FAIL line. Every container scenario runs the same [../tier3/verify.yaml](../tier3/verify.yaml), so the list is the same for all of them and only the expected sets differ. Each item names its verify task verbatim, so [../tier1/verify_spec_parity.sh](../tier1/verify_spec_parity.sh) can prove this list is complete rather than leaving it to be noticed.

Before any of them, `Assert the installed-package query returned a plausible list` checks the input to the comparison rather than the comparison itself. It fails when the query behind the native package assertion returns fewer than fifty entries, which no working Linux installation does. It exists because a format string whose newline was being discarded made that query return one concatenated blob, so every expected package was reported missing and read exactly like a playbook that had installed nothing.

1. `Assert every enabled native package is installed`, checked against `pacman -Qq`. The expected set is every entry in [../../setup/ansible/vars/Archlinux.yaml](../../setup/ansible/vars/Archlinux.yaml) mapped to `pacman` or `aur` whose toggle exists in the group_vars files, minus the container limits and minus the exclusion below. This is the largest expected set any scenario produces, and the tally line states how many were expected and how many are missing.
2. `Assert every enabled URL-installed package resolved a download location`. Some packages install from a vendor URL rather than a repository, and both dispatch tasks skip silently when that URL renders empty, so this fails the run instead of letting it look clean. The candidate set is empty on Arch, because `vars/Archlinux.yaml` maps nothing to `apt_url` or `dnf_url`. On the Debian and Ubuntu images it is the enabled subset of the five `apt_url` mappings, and on Fedora the enabled subset of the four `dnf_url` mappings, so an Arch run does not prove this one and the assertion says so by reporting how many candidates it examined.
3. `Assert every enabled flatpak application is installed`, checked against `flatpak list --app --columns=application`, again the full mapped set.
4. `Assert every enabled snap application is installed`, checked against `snap list --color=never --unicode=never`, which is asked only when a snap mapping is expected, again the full mapped set.
5. `Assert tailscaled is enabled when Tailscale was requested`, from `systemctl is-enabled tailscaled.service`.
6. `Assert the user is in the OpenRazer device group when OpenRazer was requested`, from `id -nG` against `os_dict.openrazer_device_group`, which is `openrazer` on Arch.
7. `Assert the user is in the docker group when Docker was requested`, from `id -nG`.
8. `Assert docker.service is enabled when Docker was requested`.
9. `Assert flatpak is installed and the Flathub remote is configured`.
10. `Assert the temporary passwordless sudoers entry was removed`, meaning `/etc/sudoers.d/99-ansible-user` does not exist.

`Assert the expected desktop environment is installed` does not run. The scenario declares `e2e_expect_desktop: none`, and since 2026-08-29 that is what the run actually produces. See the paragraph below.

11. `Assert every enabled outside-package-manager tool is installed and reachable from a plain interactive shell`. Every `install_` toggle is forced true here, so this is the largest set the assertion is ever asked to check: node, npm, nvm, pyenv, all four pinned Python builds, sdk, java, all four pinned Java majors, fvm, flutter, dart, sdkmanager, adb and the six npm-installed AI CLIs, each proven on disk and by name, at that same path, from an interactive non-login shell of `{{ non_root_user }}`'s real login shell. Same "Found on a real CachyOS machine on 2026-09-15" ledger entry as capability 60, and the scenario where a shell-wiring gap would cost the most, since nothing here is off to hide behind.
12. `Assert the desktop session environment carries every development variable`. Linux only. Every SDK toggle is forced true here, so it asks for the full set: the variables and PATH entries env_variables writes into `~/.config/environment.d/50-dev.conf` plus NVM_DIR, SDKMAN_DIR, JAVA_HOME and PYENV_ROOT and the JetBrains Toolbox launcher directory, `~/.local/share/JetBrains/Toolbox/scripts`, read through the systemd user environment generator exactly as the user manager reads them at the next login.
13. `Assert exactly the selected OpenCode version is installed`. `opencode_use_v1` is the one checklist toggle this scenario writes false rather than true, because `setup.sh --software all` leaves it off, by the owner's decision of 2026-10-15, and [../tier3/container.sh](../tier3/container.sh) reads that list, `ALL_SOFTWARE_KEEPS_OFF`, out of `setup.sh`. So version 2 is selected here, as in every other scenario, and no container scenario selects version 1. It asks two probes from [../../setup/ansible/tasks/opencode_version.yaml](../../setup/ansible/tasks/opencode_version.yaml), the same ones the role removed the other version with: whether the version 1 desktop app, the Flathub application `ai.opencode.opencode` is still installed, only when `install_opencode_desktop` is on, and whether the version 1 npm package `opencode-ai` is still installed under the LTS Node, only when `install_opencode` is on. Both toggles are on here, so both probes run. A probe that could not run fails. Version 1 is covered by the manual row in [../manual_test_matrix.md](../manual_test_matrix.md).

What the generated set is, and what it stopped being. The set is the wizard's checklist, resolved by `wizard_toggle_keys` in [../lib/common.sh](../lib/common.sh), which evaluates the functions `setup.sh` ships. Until 2026-08-29 the harness swept `^install_` out of `group_vars/all.yaml` and `group_vars/linux.yaml` for itself, which is the same rule implemented twice, and the two answers differed in both directions. The visible half was here: `install_kde_plasma` and `install_gnome` matched the sweep's pattern, so this scenario installed both desktop environments into one container while declaring `e2e_expect_desktop: none`, a machine no wizard run can produce, and it was the largest single reason this run was the longest. The wizard drops those two keys because the desktop environment has a screen of its own where exactly one is chosen, so they are no longer generated, and this scenario now installs no desktop at all unless a scenario names one, which capabilities 70 and 40 are the place that happens. The quieter half went the other way: the sweep could not see `set_custom_wallpaper`, `setup_tmpfs`, `setup_zsh` and `toggle_wayland_nvidia`, whose names do not begin with `install_`, so they were never part of a generated set. They are now generated true here. Three of them were already true in `group_vars` and therefore already ran in every scenario, since nothing in the harness ever wrote them. `toggle_wayland_nvidia` is the only one whose value this changes, and nothing in the playbook consumes it, so enabling it does nothing until something does. The `configure_` counterparts of the desktop keys are checklist keys the wizard drops as well, so nothing configures either desktop here either.

The declared ceiling of 300 minutes is unchanged, deliberately. Dropping two desktop environments should take a large bite out of the run, but nobody has measured the new number, and a ceiling lowered on an expectation is how a slow cell starts being killed for being slow. Lower it after a measured run, not before.

What is excluded, and why. `opencode_use_v1` is written false rather than true, for the reason capability 12 gives, and the harness reads that from `setup.sh` rather than from this scenario. `stable_diffusion` is named under `e2e_generate_except`, because it clones the AUTOMATIC1111 repository and pulls gigabytes of model weights, and `group_vars` ships it false for the same reason. The harness prints the exclusion on every run. Any toggle the scenario file states explicitly, and any toggle named in the container limits, also keeps its stated value rather than being generated, which is how a duplicate mapping key is avoided.


Known container limitations. [../tier3/container_limits.yaml](../tier3/container_limits.yaml) forces `setup_hibernate`, `setup_systemd_boot`, `setup_grub`, `remove_distro_grub`, `remove_distro_systemd_boot`, `install_waydroid`, `install_virtualbox`, `install_vmware` and `install_snapper` to false on top of every scenario, because each needs hardware or a kernel facility that belongs to the host. That list matters most here, because this is the scenario whose name most invites the reading that everything was covered: it was not, and the harness prints the suppressed list on every run precisely so nobody makes that mistake.

Two documented consequences that must not be read as regressions. Kernel modules never build, because `/usr/lib/modules` belongs to the host, so anything using DKMS reports missing headers, which with everything enabled means every DKMS package in the set, not only OpenRazer. Second, there is no login session, so tasks that need a live user D-Bus take their documented fallback path.

One upstream failure mode worth recognising on this scenario specifically. [AGENTS.md](../../AGENTS.md) documents an ansible-core 2.19 and 2.20 race that raises `Module result deserialization failed: No start of json char found`, triggered most often on modules running longer than five to seven minutes. This is the longest run in the suite, so it is the likeliest place to meet it. It is an upstream defect, not a playbook regression, and the mitigations are already in the repository: the tmp directories are moved out of `/tmp` in `ansible.cfg`, and the batched apt and flatpak installs use `raw` on Debian. Record it as an environment failure with the upstream issue named, and re-run.

---

## Fixtures

None. The inputs are [../tier3/scenarios/02-all-software.yaml](../tier3/scenarios/02-all-software.yaml), the two group_vars files the toggle list is generated from, [../tier3/container_limits.yaml](../tier3/container_limits.yaml), and the copy of [../../setup/](../../setup/) the harness places in the container. The generated list is not a fixture and must never become one: it is written into `effective-vars.yaml` in the run directory, which is the only record of what this run was actually asked for.

---

## Concurrency

- Mutates: the throwaway container's own filesystem, and nothing else on the machine under test. On the host it writes one directory under `e2e/runs/<timestamp>_all-software/`, unique per run, and it builds or reuses the shared image tag `installationhelper-e2e-arch:latest`, which is the one real overlap with the other container capabilities and is over-declared here on purpose.
- Conflicts with: no other capability test at the level of state, because each container scenario gets its own container and their filesystems cannot touch. In practice this one conflicts with everything for resources. It is the largest install in the suite, it saturates network bandwidth and disk for hours, and it is the scenario most likely to exhaust host disk on its own. Running it beside another 300 minute scenario will thrash a single machine even though nothing corrupts, and the realistic outcome is that one of the two hits its declared timeout, which counts as a fail. Give this one the machine.
- Serial: false in the schema's sense, since nothing it touches is shared state. Treat it as serial by policy on any machine that is not dedicated to it.
