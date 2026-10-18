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

This capability never runs on the owner's computer. Its scenario containers are privileged and share the kernel of the machine Docker runs on, and on the owner's computer they changed his kernel, entries 10.126 to 10.129 of [../../docs/regression_ledger.md](../../docs/regression_ledger.md). It runs on a GitHub-hosted runner, dispatched with the command under Run, or inside a throwaway virtual machine with Docker Engine that is deleted afterwards, where every command below works as written. Anywhere else `e2e/run.sh --tier 3` and `e2e/tier3/container.sh` print `REFUSED` and exit 2 before any container starts, and there is no override. WSL 2 and Docker Desktop do not qualify, because their virtual machine is part of the computer they run on. The rule and how the machine is recognised are under "Tier 3 runs only on a GitHub-hosted runner or in a throwaway virtual machine" in [../README_E2E.md](../README_E2E.md).

Inside the virtual machine the scenario driver runs inside the gate container, which `e2e/run.sh` and `e2e/tier3/container.sh` build and enter by themselves, so the virtual machine needs a Docker daemon and nothing else.

Confirm the Docker daemon is reachable.

```bash
docker info
```

Expect a daemon summary. The container needs `--privileged` and a private cgroup namespace, never the host's, and it runs with the unit masks and the host state guard described under "What a container cannot test" in [../README_E2E.md](../README_E2E.md).

Confirm there is disk headroom.

```bash
df -h /var/lib/docker
```

Expect at least tens of gigabytes free. This scenario installs the whole default software set, including several large downloads.

Confirm no container is left over from an aborted run.

```bash
docker ps -a --filter name=e2e- --format '{{.Names}}'
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

Force a rebuild of the base image, and only when the Dockerfile for the distribution you are targeting changed since the last run, [../tier3/arch.Dockerfile](../tier3/arch.Dockerfile) by default and one of debian, ubuntu or fedora beside it.

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

From the owner's computer, where the commands above and below exit 2, dispatch the same scenario to GitHub-hosted runners instead. It runs stage 1 and that one stage 2 cell of [../../.github/workflows/e2e-matrix.yml](../../.github/workflows/e2e-matrix.yml), and stage 3 on macOS and Windows as well, because stage 3 always runs. The command is the same from a Unix shell and from PowerShell.

```bash
gh workflow run e2e-matrix.yml -f scenario=defaults -f distro=arch
```

```powershell
gh workflow run e2e-matrix.yml -f scenario=defaults -f distro=arch
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

Every command above targets Arch, which is what `--os` defaults to. The same scenario runs on the other three families by naming one, `--os debian`, `--os ubuntu` or `--os fedora`, each with its own Dockerfile and image tag under [../tier3/](../tier3/). A run is a run of this capability whichever family it targeted, so the record has to say which, and a green Arch run is not evidence about the others. Three defects found on 2026-08-15 existed only outside Arch: locale generation running before the package that enables it, the verify play unable to render the Debian dictionary at all, and the installed-package query returning one concatenated line on both the apt and rpm families.

---

## Expected

`result.txt` in the run directory reports `playbook_rc: 0` and `verify_rc: 0`. Both are recorded independently, and verification runs whatever the playbook's exit code was, because a failed run still has state worth asserting on.

It also reports `host_isolation: 0 finding(s)`, which means the host kernel's loaded modules, swap areas and sysctls matched the record taken at boot after every pass and at collection, no masked unit ran, and systemd knew it was in a container. This holds for every scenario, the forced-failure one included, and any finding fails the run. See "What a container cannot test" in [../README_E2E.md](../README_E2E.md).

The verify log carries these assertions, each on its own PASS or FAIL line. Every container scenario runs the same [../tier3/verify.yaml](../tier3/verify.yaml), so the list is the same for all of them and only the expected sets differ. Each item names its verify task verbatim, so [../tier1/verify_spec_parity.sh](../tier1/verify_spec_parity.sh) can prove this list is complete rather than leaving it to be noticed.

Before any of them, `Assert the installed-package query returned a plausible list` checks the input to the comparison rather than the comparison itself. It fails when the query behind the native package assertion returns fewer than fifty entries, which no working Linux installation does. It exists because a format string whose newline was being discarded made that query return one concatenated blob, so every expected package was reported missing and read exactly like a playbook that had installed nothing.

1. `Assert every enabled native package is installed`, checked against `pacman -Qq`. The expected set is every toggle true in `group_vars/all.yaml` and `group_vars/linux.yaml` that [../../setup/ansible/vars/Archlinux.yaml](../../setup/ansible/vars/Archlinux.yaml) maps to `pacman` or `aur`, minus whatever the container limits turned off. The tally line states how many were expected and how many are missing, and a failure names them.
2. `Assert every enabled URL-installed package resolved a download location`. Some packages install from a vendor URL rather than a repository, and both dispatch tasks skip silently when that URL renders empty, so this fails the run instead of letting it look clean. The candidate set is empty on Arch, because `vars/Archlinux.yaml` maps nothing to `apt_url` or `dnf_url`. On the Debian and Ubuntu images it is the enabled subset of the five `apt_url` mappings, and on Fedora the enabled subset of the four `dnf_url` mappings, so an Arch run does not prove this one and the assertion says so by reporting how many candidates it examined.
3. `Assert every enabled flatpak application is installed`, checked against `flatpak list --app --columns=application`.
4. `Assert tailscaled is enabled when Tailscale was requested`, from `systemctl is-enabled tailscaled.service`.
5. `Assert the user is in the OpenRazer device group when OpenRazer was requested`, from `id -nG` against `os_dict.openrazer_device_group`, which is `openrazer` on Arch.
6. `Assert the user is in the docker group when Docker was requested`, from `id -nG`.
7. `Assert docker.service is enabled when Docker was requested`.
8. `Assert flatpak is installed and the Flathub remote is configured`. This is the assertion for the ledger's first entry, where flatpak was installed only for Debian and RedHat while the Flathub remote-add ran on every Linux, so on Arch it shelled out to a missing binary.
9. `Assert the temporary passwordless sudoers entry was removed`, meaning `/etc/sudoers.d/99-ansible-user` does not exist.

`Assert the expected desktop environment is installed` does not run here. The scenario declares `e2e_expect_desktop: none`, which is the wizard's `skip` answer, and both `install_kde_plasma` and `install_gnome` are false by default.

10. `Assert every enabled outside-package-manager tool is installed and reachable from a plain interactive shell`. Every toggle in the ai_tools and sdk_manager roles is true by default, so this checks node, npm, nvm, pyenv, the four pinned Python builds, sdk, java, the four pinned Java majors, fvm, flutter, dart, sdkmanager, adb and the six npm-installed CLIs (Claude Code, OpenCode, OpenSpec, Codex, Grok, Bruno CLI), each on two independent axes: present on disk at the path its own installer used, and resolvable by name, at that same path, from an interactive non-login shell of `{{ non_root_user }}`'s real login shell, read from `getent passwd`, the shell a plain terminal actually opens. A second, non-failing probe repeats the same check as a login shell, so a tool reachable only there is reported rather than hidden. This is the assertion a real CachyOS run on 2026-09-15 needed and did not have: all six AI CLIs installed cleanly and reported CHANGED, and every one of them was unreachable from the owner's zsh login shell because NVM's own installer wired itself into `~/.bashrc` only, and this play's own verification printed a clean tally and exited 0 regardless. On a real Arch and CachyOS run on 2026-09-17, the same assertion caught a second, distinct defect this way: `shell_zsh`'s Oh My Zsh install overwrites `~/.zshrc` after `env_variables` wrote the PATH block into it, which made fvm, sdkmanager and adb unreachable regardless of shell flavour, and separately proved that FVM's own Flutter SDK is never added to PATH at all. Recorded as the "Found on a real CachyOS machine on 2026-09-15" entries in [../../docs/regression_ledger.md](../../docs/regression_ledger.md).
11. `Assert the desktop session environment carries every development variable`. Linux only. It runs the systemd user environment generator as the user over `~/.config/environment.d`, which is what the user manager does at the next login, and asks for the variables and PATH entries env_variables writes into `~/.config/environment.d/50-dev.conf`, plus NVM_DIR, SDKMAN_DIR, JAVA_HOME and PYENV_ROOT, since every SDK toggle is on by default, and the JetBrains Toolbox launcher directory, `~/.local/share/JetBrains/Toolbox/scripts`, since `install_jetbrains_toolbox` is on by default too and the container tier no longer switches it off. The shell probes above cannot see this: on 2026-10-13 every one of them passed on the owner's machine while Plasma carried none of those variables.
12. `Assert exactly the selected OpenCode version is installed`. This scenario leaves `opencode_use_v1` false, so version 2 is selected. It asks two probes from [../../setup/ansible/tasks/opencode_version.yaml](../../setup/ansible/tasks/opencode_version.yaml), the same ones the role removed the other version with: whether the version 1 desktop app, the Flathub application `ai.opencode.opencode` is still installed, only when `install_opencode_desktop` is on, and whether the version 1 npm package `opencode-ai` is still installed under the LTS Node, only when `install_opencode` is on. A probe whose toggle is off is skipped and passes, a probe that could not run fails.

A note on Docker, because assertions 5 and 6 are the whole of its coverage. Docker on Arch is installed by the `virtualization_config` role rather than through the OS dictionary, so it is absent from the expected native set and neither group membership nor unit state would catch a broken package.

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
