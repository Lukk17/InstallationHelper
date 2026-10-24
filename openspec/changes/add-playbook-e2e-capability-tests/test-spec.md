# playbook e2e capability tests: spec index

Heading levels follow the `e2e-runbooks` test-spec template, which fixes the section headings at level two, overriding this repository's level-three rule.

This file is an index, not a spec. The schema gives a change one `test-spec.md`, which assumes one capability per change. This change introduces nine capabilities in one go, because the harness they describe already exists and runs, and describing one ninth of a working harness would be a false record. The per-capability specs therefore live in [../../../e2e/testing/](../../../e2e/testing/), where a sweep reads them anyway, and this file carries the audit trail: the capability set, the ordering and why it is that order, and a link to each spec.

Every linked spec has the schema's seven sections in the schema's order: What this verifies, Prerequisites, Reset state, Run, Expected, Fixtures, Concurrency.

---

## The capability set

| N | Capability | Spec | Harness invocation | Declared cost |
|---|---|---|---|---|
| 10 | wizard-toggle-parse | [10-wizard-toggle-parse-test.md](../../../e2e/testing/10-wizard-toggle-parse-test.md) | `./e2e/run.sh` | minutes, measured at 3 minutes 39 seconds |
| 20 | package-name-resolution | [20-package-name-resolution-test.md](../../../e2e/testing/20-package-name-resolution-test.md) | `./e2e/run.sh --tier 2` | minutes, measured at 7 minutes 57 seconds |
| 30 | forced-failure | [30-forced-failure-test.md](../../../e2e/testing/30-forced-failure-test.md) | `./e2e/run.sh --tier 3 --scenario forced-failure --os debian` | 90 minute timeout, measured at 46 minutes |
| 40 | kde-configure-only | [40-kde-configure-only-test.md](../../../e2e/testing/40-kde-configure-only-test.md) | `./e2e/run.sh --tier 3 --scenario kde-configure-only` | 90 minute timeout |
| 50 | live-profile | [50-live-profile-test.md](../../../e2e/testing/50-live-profile-test.md) | detached launch of `05-live-profile.yaml`, then `--collect` | 120 minute timeout |
| 60 | defaults | [60-defaults-test.md](../../../e2e/testing/60-defaults-test.md) | detached launch of `01-defaults.yaml`, then `--collect` | 180 minute timeout |
| 70 | desktop-environments | [70-desktop-environments-test.md](../../../e2e/testing/70-desktop-environments-test.md) | detached launch of `03-kde-full.yaml` and of `04-gnome-full.yaml`, then `--collect` for each | 300 minute timeout each |
| 80 | all-software | [80-all-software-test.md](../../../e2e/testing/80-all-software-test.md) | detached launch of `02-all-software.yaml`, then `--collect` | 300 minute timeout |
| 90 | idempotency | [90-idempotency-test.md](../../../e2e/testing/90-idempotency-test.md) | detached launch of `08-idempotency.yaml` with `--os debian`, then `--collect` | 300 minute timeout for two passes |

Capabilities 30 to 90 are tier 3 and run only on a GitHub-hosted runner, by the owner's decision 79. The invocations in the table are what runs there. Anywhere else, a virtual machine included, they exit 2 before any container starts, because privileged scenario containers change the kernel of the machine running them, its kernel settings, binfmt_misc table, device events and modules, and changed his (docs/regression_ledger.md 10.126 to 10.129), and the capability is dispatched instead with `gh workflow run e2e-matrix.yml -f scenario=<name> -f distro=<distribution>`. Each spec says so in the first paragraph of its Prerequisites, and each template from 30 up records where the run happened.

---

## Why this ordering

The `{N}` prefix is setup cost, cheapest first, which is also the order a sweep should run them in. For the container scenarios the cost is not a guess: it is the `e2e_timeout_minutes` value each scenario file declares, and the nine numbers are that ordering with the two static tiers in front. The numbers step by ten so a later capability can be inserted between two existing ones without renumbering anything.

Capabilities 10 and 20 come first because they are the only two cheap enough to run on every commit, and because a failure in either invalidates the container runs above them. A toggle the wizard cannot see, or a package name that no longer exists upstream, will show up in a container run as a confusing install failure hours later, having already burned the machine's evening.

Capability 30 is next because it is the cheapest container run, the only one that never installs the software set. It was the smoke capability until 68a1d84 deleted it, because every toggle smoke enabled was already true in capability 60, and forced-failure took the free number. Everything from 40 to 80 is a real wizard path, and 80 is the largest install the playbook can perform, is the most likely to exhaust host disk, and installs both desktop environments as a side effect of its generated toggle list. 90 is last because it is capability 60's configuration applied twice, which makes it the longest run in the suite by wall time.

---

## Why nine rather than eight

The harness has eight tier 3 scenario files, and the capability count is nine.

1. Tier 1 and tier 2 are genuinely separate capabilities. Each has its own assertions, its own prerequisites and its own cost, and neither starts a container. Folding them into a container scenario would misrepresent both what they cover and what they cost, and would hide the fact that they are the only parts of the suite anyone will run on every commit.
2. The two desktop environment scenarios, `kde-full` and `gnome-full`, are one capability. Neither answer to the wizard's desktop environment question is covered until both have run, [../../../AGENTS.md](../../../AGENTS.md) already requires them as a pair whenever the desktop roles change, and a record where one is green and the other red is a fail rather than a half pass.

Eight scenario files, minus one pairing, plus two static tiers, is nine capabilities.

---

## Assertion policy, common to all nine

Observable state only. The harness reads installed native packages with `pacman -Qq`, installed applications with `flatpak list --app --columns=application`, installed snaps with `snap list --color=never --unicode=never` when a snap mapping is expected, unit state with `systemctl is-enabled`, group membership with `id -nG`, and the temporary sudoers entry with `stat`. Tier 1 compares parsed toggle sets, and tier 2 resolves package names against upstream indexes. No assertion anywhere in the suite matches a log substring, because log wording drifts between versions and says nothing about the shape the machine ended up in. A tail of `playbook.log` is the next diagnostic step after a failed assertion, never a pass criterion.

Two capabilities read more than machine state, and each spec says so in its own Expected section. Capability 30 is about the reporting path rather than the machine, so it asserts on the exit codes, the task names in the terminal `FAILED (n)` summary and in `installation_errors.log`, and named skip lines in `playbook.log`. Capability 90 reads which tasks reported changed on the second pass, which is the playbook's own per-task boolean rather than prose, and asserts on task identity and the count, never on a message.

Four things every container spec states so a reader does not mistake them for regressions. The toggles [../../../e2e/tier3/container_limits.yaml](../../../e2e/tier3/container_limits.yaml) suppresses are not covered by any run, and the harness prints that list every time. Kernel modules never build, because `/usr/lib/modules` belongs to the host, so anything using DKMS reports missing headers. And there is no login session, so tasks needing a live user D-Bus take their documented fallback path. And `result.txt` carries two `host_isolation:` lines: the first, findings that fail the run, must read `0 finding(s)`, and the second lists every kernel setting and loaded module that differs from the boot record as information only, by owner decision 86, so a list there is expected and never a failure.

One thing every container spec flags as collected but not asserted: [../../../e2e/tier3/verify.yaml](../../../e2e/tier3/verify.yaml) runs `systemctl is-enabled docker.service` and registers the result, and nothing checks it. A runner reads it and does not tick it.

---

## Known divergence between a spec and the harness

Capability 50 could not produce a clean verification when this index was written, and both this note and the spec's Expected section have been amended now that it can. [../../../e2e/tier3/container.sh](../../../e2e/tier3/container.sh) passed `-e @profiles/linux_live.yaml` to the playbook but not to the verify play, so verification resolved every toggle as though the profile were absent and reported the profile's whole disabled list as missing. `collect_and_verify` now builds the verify arguments with the profile first and the effective variable file second, matching what the playbook receives, and announces it as `Running verification (with profile linux_live)`. The run of 2026-08-15T09-12-23Z came back `playbook_rc: 0`, `verify_rc: 0`, `verify_failures: none`, so `verify_rc: 0` is the expectation for this capability like every other, and a missing list is a defect rather than an artefact.

---

## Concurrency

Copied from the proposal's Concurrency profile, which each linked spec also carries in full for its own capability.

- Mutates: nothing for capabilities 10 and 20. For 30 through 90, each capability mutates its own throwaway container's filesystem and nothing else on the machine under test, plus one unique directory under `e2e/runs/` on the host, plus the shared image tag `installationhelper-e2e-<os>:latest`, which is `installationhelper-e2e-arch:latest` for 40 through 80.
- Conflicts with: for 10, any process editing [../../../setup/](../../../setup/) while it runs. For 20, a second copy of itself, always, because of upstream rate limits. For 30 through 90, nothing at the level of state, but all of them contend for the host Docker daemon, host disk and network bandwidth, and each installs gigabytes, so running several 300 minute scenarios at once will thrash a single machine even though nothing corrupts.
- Serial: false for all nine, with capability 80 treated as serial by policy on any machine not dedicated to it.
