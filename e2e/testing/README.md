# e2e testing guide

Capability specs for the end-to-end harness that lives one directory up. Each `{N}-{capability}-test.md` file here is the immutable spec for one capability: what it verifies, what has to be true before it starts, how to invoke it, and what observable state proves it passed. The paired run-record templates live in [templates](templates), and executed run records land in [runs](runs).

Section headings in this file sit at level two because the `e2e-runbooks` scaffold template fixes them there, which overrides this repository's level-three heading rule.

---

## Deviation from the schema scaffold, read this before scaffolding again

The `e2e-runbooks` schema at [../../openspec/schemas/e2e-runbooks/schema.yaml](../../openspec/schemas/e2e-runbooks/schema.yaml) uses the presence of `e2e/README.md` as its "already scaffolded" marker, and its scaffold step would create that file. This project does not have it and will not get it.

1. This repository names a top-level directory's hub page `README_<DIR>.md`, and [../README_E2E.md](../README_E2E.md) already exists. It is the hub for everything under [../](../), it is far richer than the scaffold template, and two competing hub documents in one directory would be worse than the missing marker.
2. So the scaffold marker `e2e/README.md` is intentionally absent. Its absence is not an unscaffolded tree. The scaffold has already run, and it must not be re-run.
3. The four scaffolded README files that do exist are this one, [../fixtures/README.md](../fixtures/README.md), [templates/README.md](templates/README.md) and [runs/README.md](runs/README.md). The `.gitignore` entry for `e2e/testing/runs/*.md` with its `!e2e/testing/runs/README.md` negation is in place at the repository root, appended below the pre-existing `e2e/runs/` line, which covers the harness's own run directories and is a different thing. Only the comment wording above those two patterns differs from the schema's snippet, to keep the repository's no-semicolon prose rule.
4. The scaffold templates were adapted rather than copied verbatim, because the originals describe an HTTP service suite with an API client and canary upload fixtures. This project's capability under test is an Ansible playbook, so the client is a shell script and the assertions are installed package sets, systemd unit state and group membership. The contract the templates impose (immutable spec, immutable template, timestamped run record, behaviour-only assertions) is unchanged.

---

## Format

Every `{N}-{capability}-test.md` file uses the same seven fixed sections, in this order.

1. What this verifies. Bullet list of behaviours, each anchored to the defect in [../../docs/regression_ledger.md](../../docs/regression_ledger.md) that motivated it.
2. Prerequisites. Concrete check commands the runner executes before starting. Each command is its own code block, and the prose around it states what success looks like.
3. Reset state. One command per code block, in execution order, or a plain statement that the test writes no persisted state.
4. Run. One or more numbered steps, each a single harness invocation. A multi-step test waits for the previous step to finish before starting the next.
5. Expected. Observable-state assertions only: installed package sets, `systemctl is-enabled` output, group membership, file existence. Never log substrings, because log wording drifts between versions and says nothing about the shape the machine ended up in.
6. Fixtures. Files the test reads.
7. Concurrency. The `Mutates`, `Conflicts with` and `Serial` fields a sweep orchestrator reads before deciding what runs in parallel.

Each spec has a matching `{N}-{capability}-tasks.template.md` in [templates](templates). The runner never edits a spec or a template. It copies the template into [runs](runs) under a timestamped name, ticks boxes there, and records the verdict there.

---

## Test order

The `{N}` prefix is setup cost, cheapest first, which is also the order a sweep should run them in. The numbers step by ten so a later capability can be inserted between two existing ones without renumbering anything.

| N | Capability | Harness invocation | Declared cost |
|---|---|---|---|
| 10 | [wizard-toggle-parse](10-wizard-toggle-parse-test.md) | `./e2e/run.sh` | seconds |
| 20 | [package-name-resolution](20-package-name-resolution-test.md) | `./e2e/run.sh --tier 2` | about a minute |
| 30 | [forced-failure](30-forced-failure-test.md) | `./e2e/run.sh --tier 3 --scenario forced-failure` | 90 minute timeout, measured at 46 minutes |
| 40 | [kde-configure-only](40-kde-configure-only-test.md) | `./e2e/run.sh --tier 3 --scenario kde-configure-only` | 90 minute timeout |
| 50 | [live-profile](50-live-profile-test.md) | `./e2e/run.sh --tier 3 --scenario live-profile` | 120 minute timeout |
| 60 | [defaults](60-defaults-test.md) | `./e2e/run.sh --tier 3 --scenario defaults` | 180 minute timeout |
| 70 | [desktop-environments](70-desktop-environments-test.md) | `--scenario kde-full` then `--scenario gnome-full` | 300 minute timeout each |
| 80 | [all-software](80-all-software-test.md) | `./e2e/run.sh --tier 3 --scenario all-software` | 300 minute timeout |
| 90 | [idempotency](90-idempotency-test.md) | `./e2e/run.sh --tier 3 --scenario idempotency` | 300 minute timeout for two passes |

Capabilities 10 and 20 are the two static tiers. They start no container, install nothing, and are the only two that are cheap enough to run on every commit. Everything from 30 up runs the real playbook inside a throwaway container, on Arch unless `--os` names another distribution.

Two of these numbers need a word of explanation.

Capability 30 was the smoke test until it was removed, because every toggle it enabled was already true in capability 60, which made it the same test with most of the toggles taken away. The number was left free rather than reused, and it is now the forced-failure capability, which is the cheapest container run in the suite and therefore belongs exactly where 30 sits. The four run records that already name 30 carry `30-smoke` in their filenames, so they still point unambiguously at the capability they were written against.

Capability 90 is the next free number after 80, and idempotency belongs at the end because it is the most expensive: it is capability 60's configuration applied twice.

---

## Cross-cutting conventions

Pass criteria are observable state only. The harness reads installed packages from `pacman -Qq` and `flatpak list --app --columns=application`, unit state from `systemctl is-enabled`, group membership from `id -nG`, and file existence with `stat`. A tail of `playbook.log` is the next diagnostic step after a failed assertion, never a pass criterion.

Tiers 2 and 3 need a Linux shell with a working Docker socket. On Windows that means running from inside WSL, which is also the only place the playbook itself runs at all.

Every container run writes a directory under `e2e/runs/`, which is gitignored, holding `effective-vars.yaml`, `playbook.log`, `verify.log` and `result.txt`. Keep that directory when reporting a failure. The effective variable file is the only record of what the run was actually asked for.

---

## Adding a new capability

Create the change with the schema, then fill the artifacts.

```bash
openspec new change "add-<capability>-test" --schema e2e-runbooks
```

Write the spec here and its run-record template in [templates](templates), pick the next free `{N}` by setup cost, and add the row to the table above. Do not re-run the scaffold step: see the deviation section at the top of this file.
