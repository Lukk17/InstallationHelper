# e2e test runs

Each execution of a capability test drops a filled-in copy of the matching template here, named `<UTC-timestamp>_{N}-{capability}-tasks.md`. This README is tracked. The run records themselves are gitignored.

Section headings in this file sit at level two because the `e2e-runbooks` scaffold template fixes them there, which overrides this repository's level-three heading rule.

---

## Two different run directories, do not confuse them

| Directory | Written by | Contents |
|---|---|---|
| `e2e/runs/<timestamp>_<os>_<scenario>/` | the harness itself, from [../../tier3/container.sh](../../tier3/container.sh) | `effective-vars.yaml`, `playbook.log`, `verify.log`, `galaxy.log`, `copy.log`, `result.txt`, `meta.env` |
| `e2e/testing/runs/` (here) | the runner, human or agent | one markdown record per executed capability test, with the checkboxes ticked and the verdict written |

The markdown record is the audit trail of a run. The harness directory is the evidence it cites. A record that reports a container failure should name the harness run directory it read, because the effective variable file there is the only record of what the run was actually asked for.

---

## Contract

1. Specs at `../{N}-{capability}-test.md` are immutable between runs. The runner never edits them.
2. Templates at `../templates/{N}-{capability}-tasks.template.md` are immutable too. They define the checkbox list.
3. Every run starts by copying the relevant template into this directory under a UTC timestamp prefix. The runner ticks boxes as it completes each step, then fills the Result summary, the Verdict, and anything done off-spec.

---

## Naming

```text
2026-08-14T18-15-00Z_30-smoke-tasks.md
```

ISO-8601 UTC with colons replaced by hyphens, so the name is safe on Windows as well as Linux and macOS. This matches the format [../../lib/common.sh](../../lib/common.sh) already uses for harness run identifiers, so a markdown record and the harness directory it describes sort next to each other. Group every test from one sweep under the same timestamp: one timestamp is one sweep.

---

## Runner steps

1. Read the spec.
2. Copy the template from `../templates/` into this directory under a timestamped name.
3. Record `Start (UTC)` as the very first action, before the prerequisite checks begin.
4. Execute each task in spec order. Tick the box on success. On failure, write down what actually happened and keep going where the spec allows it.
5. Record `End (UTC)` once the verdict is decided.
6. Compute `Duration = End - Start` as HH:MM:SS. It is wall clock for the whole test, prerequisites and reset and run and verification together, not just the harness invocation.
7. Fill Input tokens and Output tokens with the best available estimate. Leave them blank if no number is available. Do not invent one.
8. Write the Result summary paragraph and the Verdict, PASS or FAIL.
9. Log anything done outside the spec under "Additional tasks I did".

A container scenario that hit its declared timeout is a FAIL with a stated cause, not an inconclusive run. The timeout is part of the spec.

---

## Gitignore policy

Run records here are ephemeral and gitignored. This README stays tracked. To keep a specific run as a committed audit trail, move it under a `runs/<YYYY-MM>/` subfolder and add the matching negation to the repository `.gitignore`.
