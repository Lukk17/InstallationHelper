# playbook e2e capability tests: proposal

Heading levels follow the `e2e-runbooks` proposal template, which fixes the section headings at level two, overriding this repository's level-three rule.

Three shape deviations from the schema, stated up front so nobody has to reverse-engineer them.

1. This change introduces eight capabilities at once, not one. The harness at [../../../e2e/](../../../e2e/) already exists and runs, so the work here is describing it in the schema's shape, and describing one eighth of a working harness would be a false record. Every single-value field below is therefore a table.
2. The scaffold marker `e2e/README.md` was deliberately not created. See the Scaffold section.
3. No `run.md` is part of this change. No run has been executed through this schema yet, and writing one would fabricate a test result.

---

## Why

Every entry in [../../../docs/regression_ledger.md](../../../docs/regression_ledger.md) reached a real machine because nothing ran the playbook end to end before it shipped. A syntax check cannot tell you that `plugdev` does not exist on Arch, and reading a diff cannot tell you that a toggle installs nothing. Both of those happened, the first failing every Arch run behind an anonymous rescue warning and the second twice, with `install_putty` and `install_gradle`.

The harness that answers those questions exists, has three tiers, and is documented in [../../../e2e/README_E2E.md](../../../e2e/README_E2E.md). What it did not have is a capability-level description of what each invocation asserts, what has to be true before it starts, and what is safe to run beside it. Without that, a sweep is guesswork: nobody can tell from the outside that the live-profile scenario verifies against a toggle set the profile never applied, that the 300 minute scenarios contend for one Docker daemon, or which container limitations mean a red line in the log is not a regression. This change writes those eight descriptions and wires them into the schema so a future sweep is a checklist rather than an act of memory.

---

## What this will verify

Behaviour and persisted state only, never a log substring. The observables the harness actually reads are the installed native package set from `pacman -Qq`, the installed application set from `flatpak list --app --columns=application`, unit state from `systemctl is-enabled`, group membership from `id -nG`, and file existence from `stat` on the temporary sudoers entry. Tiers 1 and 2 add two more: the toggle key and state sets both wizards parse out of `group_vars`, and the resolution of every mapped package name against its real upstream index.

| N | Capability | What it asserts | Ledger entries it exists for |
|---|---|---|---|
| 10 | wizard-toggle-parse | Both wizards parse the same toggles out of the same YAML, nothing is dropped or malformed, every enabled toggle resolves to a mapping or a task per OS family, the no-op list has no stale entries, and the playbook parses within a two warning budget | Wizard toggle parse desync, Toggles enabled with no mapping and no task, Toggles that had already been dead for a while, the `inventory = localhost,` warning flood |
| 20 | package-name-resolution | Every pacman, AUR, Flathub, Homebrew formula, Homebrew cask, Chocolatey and winget name in the dictionaries exists upstream | Package and repository facts that only held for one distribution, Windows winget product IDs that stopped resolving, Microsoft Store product IDs need an explicit source |
| 30 | smoke | The seven historically broken toggles install, `tailscaled` is enabled, the user is in the Arch OpenRazer group and in `docker`, and the temporary sudoers grant is gone | Arch OpenRazer device group does not exist, Pacman batch failure marked as success, `playbook_succeeded` reported true regardless of what the rescue caught |
| 40 | kde-configure-only | The configure-without-install path completes and the default software set still lands | Install block rescue hides which task failed, `playbook_succeeded` reported true regardless of what the rescue caught |
| 50 | live-profile | The wizard's profile path applies `linux_live` and the run completes | Tailscale's apt repository URL entry, whose commit also caught the live profile never disabling Tailscale |
| 60 | defaults | The whole default toggle set installs with no overrides at all | Pacman batch failure marked as success, Install block rescue hides which task failed, Arch OpenRazer device group does not exist |
| 70 | desktop-environments | KDE Plasma and GNOME each install and configure on their own, asserted by a package probe per desktop | Toggles enabled with no mapping and no task, applied to two toggles the OS dictionary does not carry |
| 80 | all-software | Every mapped package on Arch installs, including toggles that ship disabled, and a stalled task fails on time | Package and repository facts that only held for one distribution, Pacman batch failure marked as success, FVM's interactive picker stalled a run for 8 hours |

---

## Setup cost class

The schema's five classes describe an HTTP service suite with fixture uploads and multi-service resets, so the fit is approximate. The real ordering driver is the setup cost the harness itself declares: a tier and, for the container scenarios, the timeout in the scenario file. The `{N}` prefixes step by ten so a later capability can be inserted without renumbering.

| N | Capability | Closest schema class | Declared cost |
|---|---|---|---|
| 10 | wizard-toggle-parse | 1: no state to reset, no fixtures | seconds |
| 20 | package-name-resolution | 2: no state, but rate-limited third-party indexes make repetition expensive | about a minute |
| 30 | smoke | 5: seeded state plus observation of an asynchronous background process | 45 minute timeout |
| 40 | kde-configure-only | 5 | 90 minute timeout |
| 50 | live-profile | 5 | 120 minute timeout |
| 60 | defaults | 5 | 180 minute timeout |
| 70 | desktop-environments | 5, twice over | 300 minute timeout each, two runs |
| 80 | all-software | 5 | 300 minute timeout |

Class 5 is the honest fit for every container scenario. The playbook runs detached inside the container writing its own log and exit code, and the harness polls for it, which is exactly seeded state plus observation of an asynchronous process.

---

## Fixtures needed

None, for any of the eight. The inputs are the working tree itself: the toggle files under [../../../setup/ansible/group_vars/](../../../setup/ansible/group_vars/), the per-distribution dictionaries under [../../../setup/ansible/vars/](../../../setup/ansible/vars/), the profiles, and the scenario files under [../../../e2e/tier3/scenarios/](../../../e2e/tier3/scenarios/). Copying any of those into `e2e/fixtures/` would create a second source of truth that drifts, which is the failure this suite exists to catch. [../../../e2e/fixtures/README.md](../../../e2e/fixtures/README.md) records that, and names the two cases that would justify a real fixture later.

---

## Concurrency profile

- Mutates: nothing for capabilities 10 and 20, which are read-only against the working tree and against six third-party indexes. Over-declared for 10: `~/.ansible/tmp` and the fact cache, because the syntax check writes there. For 30 through 80, each capability mutates its own throwaway container's filesystem and nothing else on the machine under test, plus one unique directory under `e2e/runs/` on the host, plus the shared image tag `installationhelper-e2e-arch:latest` that all six build or reuse.
- Conflicts with: for 10, any process editing [../../../setup/](../../../setup/) while it runs, because the working tree is its input. For 20, a second copy of itself, always: `archlinux.org` throttles a burst and answers with an empty body rather than a 404, and GitHub's API budget is shared per account. For 30 through 80, nothing at the level of state, because separate containers cannot touch each other's filesystems. What they do share is the host Docker daemon, host disk and network bandwidth, and each installs gigabytes. Running several 300 minute scenarios at once will thrash a single machine even though nothing corrupts, and the realistic failure is a declared timeout, which counts as a fail, not corruption.
- Serial: false for all eight. Capability 80 should be treated as serial by policy on any machine not dedicated to it, which is a scheduling choice rather than a state constraint.

---

## API client invocation

There is no HTTP client here, because the capability under test is an Ansible playbook rather than a service. The client is the harness, and every capability names exactly one invocation.

| N | Invocation |
|---|---|
| 10 | `./e2e/run.sh` |
| 20 | `./e2e/run.sh --tier 2` |
| 30 | `./e2e/run.sh --tier 3 --scenario smoke` |
| 40 | `./e2e/run.sh --tier 3 --scenario kde-configure-only` |
| 50 | `./e2e/tier3/container.sh e2e/tier3/scenarios/05-live-profile.yaml --detach`, then `--collect` |
| 60 | `./e2e/tier3/container.sh e2e/tier3/scenarios/01-defaults.yaml --detach`, then `--collect` |
| 70 | the same detached pair for `03-kde-full.yaml` and for `04-gnome-full.yaml` |
| 80 | `./e2e/tier3/container.sh e2e/tier3/scenarios/02-all-software.yaml --detach`, then `--collect` |

Anything above two hours uses the detached form on purpose. The playbook always runs detached inside the container, so a run is not tied to the shell that started it and an ordinary disconnect cannot throw hours of work away.

Prerequisites the invocation cannot supply for itself: a Linux shell with a working Docker socket, which on Windows means running from inside WSL, and an authenticated `gh` for the winget portion of capability 20, without which that one check is skipped with a warning and the run passes while covering less.

---

## Number assignment

N: 10, 20, 30, 40, 50, 60, 70 and 80, assigned in the table above. Cheapest first, which is also the order a sweep should run them in.

Two notes on the count. Tiers 1 and 2 are separate capabilities rather than part of a container scenario, because they have their own assertions and their own cost, and folding them in would misrepresent both. The two desktop environment scenarios are one capability rather than two, because neither answer to the wizard's desktop question is covered until both have run, and [../../../AGENTS.md](../../../AGENTS.md) already requires them as a pair.

---

## Scaffold

The schema's scaffold step ran once, with one deliberate deviation.

Created: [../../../e2e/fixtures/README.md](../../../e2e/fixtures/README.md), [../../../e2e/testing/README.md](../../../e2e/testing/README.md), [../../../e2e/testing/templates/README.md](../../../e2e/testing/templates/README.md), [../../../e2e/testing/runs/README.md](../../../e2e/testing/runs/README.md), and the `.gitignore` entry that ignores `e2e/testing/runs/*.md` while keeping that directory's README tracked, appended below the pre-existing `e2e/runs/` line, which covers the harness's own run directories and is a different thing.

Not created: `e2e/README.md`, which is the schema's "already scaffolded" marker. This repository names a top-level directory's hub page `README_<DIR>.md`, and [../../../e2e/README_E2E.md](../../../e2e/README_E2E.md) already exists and is far richer than the scaffold template. Two competing hub documents in one directory would be worse than a missing marker. The absence is recorded at the top of [../../../e2e/testing/README.md](../../../e2e/testing/README.md), with an explicit instruction not to re-run the scaffold, because an agent reading only the schema will otherwise try.

The four README files were adapted rather than copied byte for byte, since the originals describe an HTTP service suite with an API client and canary upload fixtures. The contract they impose is unchanged: immutable spec, immutable template, timestamped run record, behaviour-only assertions.

---

## Next steps

1. The eight specs are written to [../../../e2e/testing/](../../../e2e/testing/) as `{N}-{capability}-test.md`, and indexed by [test-spec.md](test-spec.md) in this directory.
2. The eight run-record templates are written to [../../../e2e/testing/templates/](../../../e2e/testing/templates/) as `{N}-{capability}-tasks.template.md`, and indexed by [tasks-template.md](tasks-template.md) in this directory.
3. No run record exists yet. The first execution produces `e2e/testing/runs/<UTC-timestamp>_{N}-{capability}-tasks.md` from the matching template, and only then is there anything to write into a `run.md`.
4. Capability 50 needs a harness fix before its verification can be clean: [../../../e2e/tier3/container.sh](../../../e2e/tier3/container.sh) passes the profile to the playbook but not to the verify play, so verification resolves toggles as though the profile were absent. The spec documents how to judge the run in the meantime. The fix belongs in a separate change against the harness, not here.
