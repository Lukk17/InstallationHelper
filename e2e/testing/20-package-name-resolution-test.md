# package-name-resolution: e2e test

Tier 2 of the harness. A few minutes, measured at 7 minutes 57 seconds on Linux on 2026-10-15, nothing installed anywhere, and nothing run on the machine that starts it, but it talks to every real package index this repository depends on and starts three throwaway containers to reach the two that need a package index of their own.

Section headings sit at level two because the `e2e-runbooks` test-spec template fixes the seven section names at that level, which overrides this repository's level-three heading rule.

---

## What this verifies

- Every package name the playbook would hand to pacman actually exists in Arch's official repositories. Each name mapped with `manager: "pacman"` in [../../setup/ansible/vars/Archlinux.yaml](../../setup/ansible/vars/Archlinux.yaml) is resolved against `archlinux.org/packages/search/json/`, one request per name because the endpoint honours only the last `name` parameter. This exists for the "Package and repository facts that only held for one distribution" entry in [../../docs/regression_ledger.md](../../docs/regression_ledger.md), where Arch's repositories had dropped the `arduino` package entirely and the mapping had to move to Flathub, and for the `hardinfo` to `hardinfo2` rename on both Arch and Fedora named in the tier 2 script's own header.
- Every AUR name exists. All names mapped with `manager: "aur"` go out in one batched RPC v5 info request, and the set the endpoint returns is compared against the set asked for.
- Every Flathub application id exists. The flatpak ids from the Archlinux, Debian and RedHat dictionaries are merged and each is resolved against the Flathub appstream endpoint. Same ledger entry as above: the FreeCAD application id was renamed upstream and had to be corrected in three dictionaries independently, because the fact did not generalise from one distribution to the others.
- Every Homebrew formula and cask in [../../setup/ansible/vars/Darwin.yaml](../../setup/ansible/vars/Darwin.yaml) exists, including tap-qualified names. A name shaped `owner/tap/formula` is not in the core index, so it is resolved against the tap repository's own formula file instead of being reported missing. Terraform is the live example, pushed out of homebrew-core by HashiCorp's licence change.
- Every Chocolatey package id in [../../setup/ansible/vars/Windows.yaml](../../setup/ansible/vars/Windows.yaml) exists on the community feed.
- Every npm package the `ai_tools` role installs is the project it claims to be, not merely a name that resolves. The registry is asked three things and any one of them failing is a failure: the package is not deprecated, its newest version declares at least one executable, and that version is not 0.0.0. This exists because the OpenSpec mapping named `openspec`, a stub published once in 2019 at 0.0.0 with nothing executable in it, while the project actually ships as `@fission-ai/openspec`. Every other check in this repository passed, the install exited zero, and the tool was absent. The 0.0.0 test is blunt on purpose: a name squatted years ago and never touched again is the shape of the thing that got through.
- Every winget manifest id points at a file the vendor still serves. This is a separate question from the one below it, and 2026-08-25 is the day that distinction cost four hours: `REALiX.HWiNFO` and `ShiningLight.OpenSSL.Light` both had current, healthy manifests naming downloads that answer 404, and each surfaced as `0x80190194 : Not found` about an hour into a Windows run. The identifier check passed both times and was right to, because the manifest exists and only the file below it is gone. So this takes the URL from `winget show --id <id> --exact` and sends it a request. Only 404 and 410 fail the check: a timeout, a refused connection or a 403 is reported as unproven, because several vendors refuse a bare request from a data centre while serving a browser perfectly well, and treating that as a dead download would make the check cry wolf. It needs a runnable winget and skips without one, because reading eighty manifests from GitHub instead needs two authenticated API calls each and does not finish in a sensible time, measured.
- The winget packages whose newest manifest leaves the installer to a scope are exactly the ones [../tier1/winget_scoped_packages.txt](../tier1/winget_scoped_packages.txt) lists. A package belongs there when one of its installers declares `Scope: user`, or when its installers declare more than one distinct scope, counting no scope as one, or when its mapping pins a scope. Each line also names the installer type winget selects for `--scope machine`, worked out the way winget-cli v1.29.380 selects it: an installer that declares machine, or an unscoped msix, msstore, portable or font, then the architecture, then winget's default type order. On 2026-10-11 that agreed with `winget show --scope machine` for all 21 machine pins. The newest installer manifest of every mapped winget id is read from `microsoft/winget-pkgs` through `gh`, because `winget show` prints no scope, and a difference fails with the live list printed so the file can be replaced. The tier 1 check `winget_scope_pins` then requires each listed package to pin a scope. This exists for GitHub sweep run 38107292439, where Mirantis.Lens failed in the elevated wizard while its manifest offered a user and a machine installer and the mapping pinned neither, the shape Bruno.Bruno and Overwolf.CurseForge had already failed with. Measured at 1 minute 44 seconds on 2026-10-11, and skipped with a reason when `gh` is not authenticated or there is no Python 3.11 or newer.
- Every winget manifest id exists in `microsoft/winget-pkgs`. This exists for the "Windows winget product IDs that stopped resolving" ledger entry, where Google's Antigravity rebrand left `Google.Antigravity` pointing at a different product and `Ookla.Speedtest` never existed at all, only `Ookla.Speedtest.CLI` did. Bare Microsoft Store product ids are counted and skipped rather than reported missing, because they are not manifests, which is the distinction behind the "Microsoft Store product IDs need an explicit source or they abort the whole batch" entry.
- Every apt repository the playbook writes, and every signing key it downloads for one, answers for Debian 13, Ubuntu 26.04, Linux Mint 22 and 22.2, LMDE 6 and 7 and Pop!_OS 22.04. [../tier2/resolve_apt_repositories.sh](../tier2/resolve_apt_repositories.sh) asks the vendor for `<uri>/dists/<suite>/InRelease`, then `Release` when that is not there, for every line that depends on the release or the lineage, rendered by [../lib/apt_repositories.sh](../lib/apt_repositories.sh) out of the shipped task files with the facts the shipped `derive_os_facts.yaml` gives for each os-release fixture, the same rendering capability 10's `apt_vendor_repositories` asserts on. It exists because the Docker, Tailscale and HashiCorp lines carried Ansible's own release name, which is `zara` on Linux Mint 22.2 and `gigi` on LMDE 7, and all three vendors answer 404 for both. Proven on 2026-10-18 against a copy of the tree carrying the old `derive_os_facts.yaml`, `debian_repos.yaml` and `debian_core` tasks, where all four Mint and LMDE fixtures failed with 4 of 5 locations missing, among them `https://download.docker.com/linux/ubuntu/dists/zara/InRelease` and `https://pkgs.tailscale.com/stable/debian/gigi.noarmor.gpg`.
- No two packages of the default Fedora set claim the same file. [../tier2/rpm_file_conflicts.sh](../tier2/rpm_file_conflicts.sh) downloads every vendor rpm the default set installs, the `dnf_url` mappings on by default and every .rpm a role downloads under a toggle on by default, and every package the default set asks dnf for that a repository under `third_party_repositories` in [../../setup/ansible/vars/RedHat.yaml](../../setup/ansible/vars/RedHat.yaml) provides, with everything it requires from such a repository, inside a throwaway non-privileged container of the image [../tier3/fedora.Dockerfile](../tier3/fedora.Dockerfile) pins, one download per call, and lists every file of each with `rpm -qp`. All of it is read out of the shipped files by [../lib/render_dnf_sources.py](../lib/render_dnf_sources.py). It fails on a path that is not a directory and is claimed by two packages, unless the route that installs one of them leaves it out, a `dnf_url` mapping with `exclude_path`, and on a repository, download or listing that did not come back. OpenCode desktop 2.0.29 and Lens both carry `/usr/lib/.build-id/aa/c9a26d3d137c8cedbe1c3f2deab3edd8f39f43`, and dnf refused whichever came second on a real Fedora machine. Proven on 2026-10-18 against the tree before OpenCode desktop had its `exclude_path`, where it failed naming exactly that path, claimed by lens and opencode, after listing 18 vendor repository packages and 6 vendor rpms in 93 seconds. It runs only on a GitHub-hosted runner, owner decision 91, in the sweep's stage 1 job `Tier 1 checks` through `bash e2e/run.sh --tier 2 --only rpm_file_conflicts`, and anywhere else it reports one SKIP and downloads nothing, because its downloads filled the owner's Docker disk on 2026-10-22 (docs/regression_ledger.md 10.162).
- The software installer's pacman consistency check works on CachyOS. [../tier2/pacman_database_check.sh](../tier2/pacman_database_check.sh) reads the command of the task `Ask pacman whether the installed set is consistent` out of `dynamic_install.yaml` and runs it in the image [../tier3/cachyos.Dockerfile](../tier3/cachyos.Dockerfile) pins, with CachyOS's `CACHY_UPDATE_NOTICE` marker written into the local database. It fails unless a bare `pacman -Dk` still fails on the marker, the task's command finds no error and leaves the marker in place, and the same command names `readline` as missing once that record is removed. Proven on 2026-10-23: the bare `pacman -Dk` exits 1 on the marker, which is docs/regression_ledger.md 10.161.

---

## Prerequisites

Tier 2 runs inside the gate container, like every tier: `e2e/run.sh` builds [../gate/Dockerfile](../gate/Dockerfile) and runs the checks inside it, with the Docker socket mounted so the apt, dnf and pacman probe containers start beside it. curl, Python and the rest are in the image, so the host needs only Docker, network access, and optionally a `gh` login.

Confirm the Docker daemon is reachable.

```bash
docker info
```

Expect a daemon summary rather than an error. Tier 2 needs it for real now: apt and dnf cannot be asked whether a package exists without a package index, so those names are resolved inside the same pinned base images the tier 3 scenarios use, read out of the Dockerfiles so the check and the scenarios cannot drift. The containers are asked and thrown away and nothing is installed in them. On Windows that means Docker Desktop running with WSL integration enabled for the distribution you run the harness from.

Confirm `gh` is authenticated on this machine, or accept that the winget portion is skipped. The gate container has no `gh` login of its own, so for tier 2 only `e2e/run.sh` lends it yours as `GH_TOKEN`, through a read-only mounted file that the launcher deletes afterwards, never through the container's environment settings and never on a command line. A `GH_TOKEN` you exported yourself wins over it.

```bash
gh auth status
```

Expect a logged-in account. There are more winget packages in the dictionary than GitHub's hourly limit for anonymous requests, so without authentication the entire winget check is skipped with a warning that says exactly that, and the run passes while covering less than it claims. Run `gh auth login` first if you want that coverage.

Outbound network access to the indexes and to the container registry is not probed from this machine, because a probe is a test and tests run only in a container. The run itself names every URL it could not reach: a blocked or captive network turns every name into a failure that says it could not be checked, and a registry it cannot reach turns the apt and dnf halves into a skip that says so.

---

## Reset state

None. This test writes no persisted state and installs nothing. It performs read-only requests against third-party indexes, and starts throwaway probe containers, one per apt, dnf or pacman image, each removed as soon as it has answered, beside the gate container, which is removed when the run ends.

---

## Run

Run tier 2 from the repository root. The same command works from a Linux shell, from Git Bash and from WSL.

```bash
bash e2e/run.sh --tier 2
```

From a PowerShell prompt on Windows, the same run through WSL.

```powershell
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && bash e2e/run.sh --tier 2"
```

Wait for the process to exit. Every index is checked before anything fails, so one dead package name does not hide the rest.

---

## Expected

The process exits 0. A non-zero exit means at least one index reported a name it does not have, and the tally at the end lists the failing checks by name.

Eight check results, one per index group. Arch official repositories, the Arch User Repository, Flathub, Homebrew formulae, Homebrew casks, Chocolatey, winget and npm. winget also reports the files its manifests point at and the packages that need a scope pinned, each as a result of its own. Each pass states how many names resolved. Each failure states how many of how many do not exist and names them, so the output is a work list rather than a verdict. A name is called missing only when the index answers 404 or 410, or for Arch an empty results list. A lookup that never gets a definite answer is a failure of its own, `could not be checked`, naming the URL and what came back, so a network fault is never reported as a missing name.

The Fedora file conflict check follows as two results, one that every vendor repository answered and every package of the set downloaded, naming how many, and one that no file is claimed by two packages, naming how many files were compared, or naming every path and the packages that claim it.

The apt repository locations follow as one more result per os-release fixture, seven of them, each reading `<fixture>: all <n> repository and key locations resolve`, or naming every location that answered 404 or 410.

The winget line reports how many entries were skipped as Microsoft Store product ids rather than manifests, and that number is expected to be non-zero while Store entries are mapped. When `gh` is not authenticated, the winget line is a warning and no assertion is recorded for it at all.

Every lookup that gets no definite answer, a timeout, a 5xx, a 429, or a transient empty body from `archlinux.org`, is asked up to four times with a growing pause, through `http_ask` in [../lib/http_ask.sh](../lib/http_ask.sh), and is then reported as not checked rather than missing. That retry is load-bearing: without it the check once reported eleven perfectly real packages as missing, all at the alphabetical tail where the throttle kicked in.

apt and dnf used to be the stated gap here, and they are not any more. Both are resolved inside a pinned base image, Debian and Ubuntu separately because their answers differ, and the names that only exist once the playbook adds a vendor repository are forgiven by name and reason in [../tier2/runtime_repo_packages.txt](../tier2/runtime_repo_packages.txt), which is itself checked for entries that have gone stale in either direction.

What a pass still does not close. This capability proves a name exists upstream, not that the toggle behind it is wired up, which is capability 10's job, and not that the package installs and functions, which is capability 30 and above. A templated name, one built from a variable at run time, is counted and warned about rather than resolved, because resolving it would mean rendering the playbook.

Container limitations do not apply to this capability, even though containers now start. Nothing is installed in them and no service runs, so nothing in [../tier3/container_limits.yaml](../tier3/container_limits.yaml) is suppressed, and neither documented container consequence, the kernel modules that cannot build and the missing login session, is in play when the only question asked is whether a package name exists in an index.

---

## Fixtures

None. The inputs are the five per-distribution dictionaries under [../../setup/ansible/vars/](../../setup/ansible/vars/), read straight from the working tree. The indexes on the other end are live third-party services, not fixtures, which is why a network fault and a genuine rename look similar in the output and why the retry above exists.

---

## Concurrency

- Mutates: none. Every request is a read against a third-party index, and nothing is written to the repository or to the machine.
- Conflicts with: a second copy of itself, always. `archlinux.org` throttles a burst of sequential requests and answers with an empty body rather than a 404, two copies double the burst, and the retry that hides the throttle for one copy will not hide it for two. GitHub's API limit is shared per account, so a concurrent copy eats the same budget the winget check needs. Run it alone and let it take its minute. It has no conflict with capabilities 30 through 80 beyond bandwidth, and none at all with capability 10.
- Serial: false. It can run alongside other capabilities, just never alongside another copy of itself.
