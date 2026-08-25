# package-name-resolution: e2e test

Tier 2 of the harness. A few minutes, nothing installed anywhere, but it talks to every real package index this repository depends on and starts three throwaway containers to reach the two that need a package index of their own.

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
- Every winget manifest id exists in `microsoft/winget-pkgs`. This exists for the "Windows winget product IDs that stopped resolving" ledger entry, where Google's Antigravity rebrand left `Google.Antigravity` pointing at a different product and `Ookla.Speedtest` never existed at all, only `Ookla.Speedtest.CLI` did. Bare Microsoft Store product ids are counted and skipped rather than reported missing, because they are not manifests, which is the distinction behind the "Microsoft Store product IDs need an explicit source or they abort the whole batch" entry.

---

## Prerequisites

Confirm the shell is Linux. On Windows this means running from inside WSL.

```bash
uname -s
```

Expect `Linux`. The harness refuses tier 2 from any other platform with an instruction to use WSL.

Confirm the Docker daemon is reachable.

```bash
docker info
```

Expect a daemon summary rather than an error. Tier 2 needs it for real now: apt and dnf cannot be asked whether a package exists without a package index, so those names are resolved inside the same pinned base images the tier 3 scenarios use, read out of the Dockerfiles so the check and the scenarios cannot drift. The containers are asked and thrown away and nothing is installed in them. On Windows that means Docker Desktop running with WSL integration enabled for the distribution you run the harness from.

Confirm curl is installed.

```bash
command -v curl
```

Expect a path. Without it the check exits 2 before running any assertion.

Confirm `gh` is authenticated, or accept that the winget portion is skipped.

```bash
gh auth status
```

Expect a logged-in account. There are more winget packages in the dictionary than GitHub's hourly limit for anonymous requests, so without authentication the entire winget check is skipped with a warning that says exactly that, and the run passes while covering less than it claims. Run `gh auth login` first if you want that coverage.

Confirm outbound network access to the indexes and to the container registry. A blocked or captive network turns every name into a missing name, and a registry it cannot reach turns the apt and dnf halves into a skip that says so.

```bash
curl -s -o /dev/null -w '%{http_code}\n' --max-time 20 https://archlinux.org/packages/search/json/?name=bash
```

Expect `200`.

---

## Reset state

None. This test writes no persisted state and installs nothing. It performs read-only requests against third-party indexes, and starts three throwaway containers, one per apt or dnf family, each removed as soon as it has answered.

---

## Run

Run tier 2 from the repository root.

```bash
./e2e/run.sh --tier 2
```

From a PowerShell prompt on Windows, the same run inside WSL.

```powershell
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && ./e2e/run.sh --tier 2"
```

Wait for the process to exit. Every index is checked before anything fails, so one dead package name does not hide the rest.

---

## Expected

The process exits 0. A non-zero exit means at least one index reported a name it does not have, and the tally at the end lists the failing checks by name.

Eight check results, one per index group. Arch official repositories, the Arch User Repository, Flathub, Homebrew formulae, Homebrew casks, Chocolatey, winget and npm. Each pass states how many names resolved. Each failure states how many of how many do not exist and names them, so the output is a work list rather than a verdict.

The winget line reports how many entries were skipped as Microsoft Store product ids rather than manifests, and that number is expected to be non-zero while Store entries are mapped. When `gh` is not authenticated, the winget line is a warning and no assertion is recorded for it at all.

A transient empty body from `archlinux.org` is retried up to three times with a growing pause before a name is called missing. That retry is load-bearing: without it the check once reported eleven perfectly real packages as missing, all at the alphabetical tail where the throttle kicked in.

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
