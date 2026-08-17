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

From a PowerShell prompt on Windows, the same launch inside WSL.

```powershell
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && ./e2e/tier3/container.sh e2e/tier3/scenarios/02-all-software.yaml --detach"
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

The verify log carries these assertions, each on its own PASS or FAIL line. Every container scenario runs the same [../tier3/verify.yaml](../tier3/verify.yaml), so the list is the same for all of them and only the expected sets differ. Each item names its verify task verbatim, so [../tier1/verify_spec_parity.sh](../tier1/verify_spec_parity.sh) can prove this list is complete rather than leaving it to be noticed.

Before any of them, `Assert the installed-package query returned a plausible list` checks the input to the comparison rather than the comparison itself. It fails when the query behind the native package assertion returns fewer than fifty entries, which no working Linux installation does. It exists because a format string whose newline was being discarded made that query return one concatenated blob, so every expected package was reported missing and read exactly like a playbook that had installed nothing.

1. `Assert every enabled native package is installed`, checked against `pacman -Qq`. The expected set is every entry in [../../setup/ansible/vars/Archlinux.yaml](../../setup/ansible/vars/Archlinux.yaml) mapped to `pacman` or `aur` whose toggle exists in the group_vars files, minus the container limits and minus the exclusion below. This is the largest expected set any scenario produces, and the tally line states how many were expected and how many are missing.
2. `Assert every enabled URL-installed package resolved a download location`. Some packages install from a vendor URL rather than a repository, and both dispatch tasks skip silently when that URL renders empty, so this fails the run instead of letting it look clean. The candidate set is empty on Arch, because `vars/Archlinux.yaml` maps nothing to `apt_url` or `dnf_url`. On the Debian and Ubuntu images it is the enabled subset of the five `apt_url` mappings, and on Fedora the enabled subset of the four `dnf_url` mappings, so an Arch run does not prove this one and the assertion says so by reporting how many candidates it examined.
3. `Assert every enabled flatpak application is installed`, checked against `flatpak list --app --columns=application`, again the full mapped set.
4. `Assert tailscaled is enabled when Tailscale was requested`, from `systemctl is-enabled tailscaled.service`.
5. `Assert the user is in the OpenRazer device group when OpenRazer was requested`, from `id -nG` against `os_dict.openrazer_device_group`, which is `openrazer` on Arch.
6. `Assert the user is in the docker group when Docker was requested`, from `id -nG`.
7. `Assert docker.service is enabled when Docker was requested`.
8. `Assert flatpak is installed and the Flathub remote is configured`.
9. `Assert the temporary passwordless sudoers entry was removed`, meaning `/etc/sudoers.d/99-ansible-user` does not exist.

`Assert the expected desktop environment is installed` does not run, even though this scenario installs both desktop environments. See the paragraph below.

What the generated set includes that a reader might not expect. `install_kde_plasma` and `install_gnome` match the generator's pattern and live in `group_vars/linux.yaml`, so this scenario installs both desktop environments in the same container. Their `configure_` counterparts do not match the pattern and stay at their defaults, which are false, so nothing configures either one. The scenario also declares `e2e_expect_desktop: none`, so verification asserts neither desktop even though both are installed. That is the largest single reason this run is the longest, and it is not covered by an assertion here. Capability 70 is where the desktop environments are actually asserted.

What is excluded, and why. `stable_diffusion` is named under `e2e_generate_except`, because it clones the AUTOMATIC1111 repository and pulls gigabytes of model weights, and `group_vars` ships it false for the same reason. The harness prints the exclusion on every run. Any toggle the scenario file states explicitly, and any toggle named in the container limits, also keeps its stated value rather than being generated, which is how a duplicate mapping key is avoided.


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
