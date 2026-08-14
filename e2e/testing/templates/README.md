# e2e run-record templates

One `{N}-{capability}-tasks.template.md` per spec. Each is the checkbox template a runner copies into [../runs](../runs) at the start of every execution.

Section headings in this file sit at level two because the `e2e-runbooks` scaffold template fixes them there, which overrides this repository's level-three heading rule.

---

## Relationship to the specs

The specs live one level up, directly under [..](..), as `{N}-{capability}-test.md`. This directory holds only the run-record templates that mirror them, one per spec, sharing the same `{N}` prefix and capability name.

| N | Spec | Template |
|---|---|---|
| 10 | [../10-wizard-toggle-parse-test.md](../10-wizard-toggle-parse-test.md) | [10-wizard-toggle-parse-tasks.template.md](10-wizard-toggle-parse-tasks.template.md) |
| 20 | [../20-package-name-resolution-test.md](../20-package-name-resolution-test.md) | [20-package-name-resolution-tasks.template.md](20-package-name-resolution-tasks.template.md) |
| 30 | [../30-smoke-test.md](../30-smoke-test.md) | [30-smoke-tasks.template.md](30-smoke-tasks.template.md) |
| 40 | [../40-kde-configure-only-test.md](../40-kde-configure-only-test.md) | [40-kde-configure-only-tasks.template.md](40-kde-configure-only-tasks.template.md) |
| 50 | [../50-live-profile-test.md](../50-live-profile-test.md) | [50-live-profile-tasks.template.md](50-live-profile-tasks.template.md) |
| 60 | [../60-defaults-test.md](../60-defaults-test.md) | [60-defaults-tasks.template.md](60-defaults-tasks.template.md) |
| 70 | [../70-desktop-environments-test.md](../70-desktop-environments-test.md) | [70-desktop-environments-tasks.template.md](70-desktop-environments-tasks.template.md) |
| 80 | [../80-all-software-test.md](../80-all-software-test.md) | [80-all-software-tasks.template.md](80-all-software-tasks.template.md) |

---

## Contract

1. Templates are immutable between runs. A runner never edits one in place.
2. Each template mirrors its spec's Prerequisites, Reset state, Run and Expected items as checkboxes, then adds a Verdict checkbox, a Result summary block with Input tokens, Output tokens, Start (UTC), End (UTC) and Duration, and an "Additional tasks I did" section for anything done off-spec.
3. To run a test, copy the matching template into [../runs](../runs) with a UTC timestamp prefix, then tick boxes and fill results in that copy, never here.
4. When a spec changes, change its template in the same commit. A template that no longer mirrors its spec produces run records that tick boxes for assertions nobody made.

See [../runs/README.md](../runs/README.md) for the full runner contract.
