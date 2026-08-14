# playbook e2e capability tests: spec index

Heading levels follow the `e2e-runbooks` test-spec template, which fixes the section headings at level two, overriding this repository's level-three rule.

This file is an index, not a spec. The schema gives a change one `test-spec.md`, which assumes one capability per change. This change introduces eight capabilities in one go, because the harness they describe already exists and runs, and describing one eighth of a working harness would be a false record. The per-capability specs therefore live in [../../../e2e/testing/](../../../e2e/testing/), where a sweep reads them anyway, and this file carries the audit trail: the capability set, the ordering and why it is that order, and a link to each spec.

Every linked spec has the schema's seven sections in the schema's order: What this verifies, Prerequisites, Reset state, Run, Expected, Fixtures, Concurrency.

---

## The capability set

| N | Capability | Spec | Harness invocation | Declared cost |
|---|---|---|---|---|
| 10 | wizard-toggle-parse | [10-wizard-toggle-parse-test.md](../../../e2e/testing/10-wizard-toggle-parse-test.md) | `./e2e/run.sh` | seconds |
| 20 | package-name-resolution | [20-package-name-resolution-test.md](../../../e2e/testing/20-package-name-resolution-test.md) | `./e2e/run.sh --tier 2` | about a minute |
| 30 | smoke | [30-smoke-test.md](../../../e2e/testing/30-smoke-test.md) | `./e2e/run.sh --tier 3 --scenario smoke` | 45 minute timeout |
| 40 | kde-configure-only | [40-kde-configure-only-test.md](../../../e2e/testing/40-kde-configure-only-test.md) | `./e2e/run.sh --tier 3 --scenario kde-configure-only` | 90 minute timeout |
| 50 | live-profile | [50-live-profile-test.md](../../../e2e/testing/50-live-profile-test.md) | detached launch of `05-live-profile.yaml`, then `--collect` | 120 minute timeout |
| 60 | defaults | [60-defaults-test.md](../../../e2e/testing/60-defaults-test.md) | detached launch of `01-defaults.yaml`, then `--collect` | 180 minute timeout |
| 70 | desktop-environments | [70-desktop-environments-test.md](../../../e2e/testing/70-desktop-environments-test.md) | detached launch of `03-kde-full.yaml` and of `04-gnome-full.yaml`, then `--collect` for each | 300 minute timeout each |
| 80 | all-software | [80-all-software-test.md](../../../e2e/testing/80-all-software-test.md) | detached launch of `02-all-software.yaml`, then `--collect` | 300 minute timeout |

---

## Why this ordering

The `{N}` prefix is setup cost, cheapest first, which is also the order a sweep should run them in. For the container scenarios the cost is not a guess: it is the `e2e_timeout_minutes` value each scenario file declares, and the eight numbers are that ordering with the two static tiers in front. The numbers step by ten so a later capability can be inserted between two existing ones without renumbering anything.

Capabilities 10 and 20 come first because they are the only two cheap enough to run on every commit, and because a failure in either invalidates the container runs above them. A toggle the wizard cannot see, or a package name that no longer exists upstream, will show up in a container run as a confusing install failure hours later, having already burned the machine's evening.

Capability 30 is next because it is the fast container gate, deliberately restricted to the seven toggles that sit on top of a defect this project has actually shipped. Everything from 40 up is a real wizard path, and 80 is last because it is the largest install the playbook can perform, is the most likely to exhaust host disk, and installs both desktop environments as a side effect of its generated toggle list.

---

## Why eight rather than seven

The harness has seven tier 3 scenario files, and the capability count is eight.

1. Tier 1 and tier 2 are genuinely separate capabilities. Each has its own assertions, its own prerequisites and its own cost, and neither starts a container. Folding them into a container scenario would misrepresent both what they cover and what they cost, and would hide the fact that they are the only parts of the suite anyone will run on every commit.
2. The two desktop environment scenarios, `kde-full` and `gnome-full`, are one capability. Neither answer to the wizard's desktop environment question is covered until both have run, [../../../AGENTS.md](../../../AGENTS.md) already requires them as a pair whenever the desktop roles change, and a record where one is green and the other red is a fail rather than a half pass.

Seven scenario files, minus one pairing, plus two static tiers, is eight capabilities.

---

## Assertion policy, common to all eight

Observable state only. The harness reads installed native packages with `pacman -Qq`, installed applications with `flatpak list --app --columns=application`, unit state with `systemctl is-enabled`, group membership with `id -nG`, and the temporary sudoers entry with `stat`. Tier 1 compares parsed toggle sets, and tier 2 resolves package names against upstream indexes. No assertion anywhere in the suite matches a log substring, because log wording drifts between versions and says nothing about the shape the machine ended up in. A tail of `playbook.log` is the next diagnostic step after a failed assertion, never a pass criterion.

Three things every container spec states so a reader does not mistake them for regressions. The toggles [../../../e2e/tier3/container_limits.yaml](../../../e2e/tier3/container_limits.yaml) suppresses are not covered by any run, and the harness prints that list every time. Kernel modules never build, because `/usr/lib/modules` belongs to the host, so anything using DKMS reports missing headers. And there is no login session, so tasks needing a live user D-Bus take their documented fallback path.

One thing every container spec flags as collected but not asserted: [../../../e2e/tier3/verify.yaml](../../../e2e/tier3/verify.yaml) runs `systemctl is-enabled docker.service` and registers the result, and nothing checks it. A runner reads it and does not tick it.

---

## Known divergence between a spec and the harness

Capability 50 cannot produce a clean verification today, and the spec says so rather than papering over it. [../../../e2e/tier3/arch_container.sh](../../../e2e/tier3/arch_container.sh) passes `-e @profiles/linux_live.yaml` to the playbook but not to the verify play, which receives only the effective variable file. Verification therefore resolves every toggle as though the profile were absent, so each toggle the profile disables while `group_vars` enables it is expected by verification and correctly absent from the machine. The spec's Expected section says what to compare, and how to reach a verdict in the meantime. Fixing it means passing the profile to the verify play too, which is a change against the harness and belongs in its own change, not here.

---

## Concurrency

Copied from the proposal's Concurrency profile, which each linked spec also carries in full for its own capability.

- Mutates: nothing for capabilities 10 and 20. For 30 through 80, each capability mutates its own throwaway container's filesystem and nothing else on the machine under test, plus one unique directory under `e2e/runs/` on the host, plus the shared image tag `installationhelper-e2e-arch:latest`.
- Conflicts with: for 10, any process editing [../../../setup/](../../../setup/) while it runs. For 20, a second copy of itself, always, because of upstream rate limits. For 30 through 80, nothing at the level of state, but all of them contend for the host Docker daemon, host disk and network bandwidth, and each installs gigabytes, so running several 300 minute scenarios at once will thrash a single machine even though nothing corrupts.
- Serial: false for all eight, with capability 80 treated as serial by policy on any machine not dedicated to it.
