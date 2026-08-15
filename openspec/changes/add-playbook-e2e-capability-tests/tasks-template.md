# playbook e2e capability tests: tasks-template index

Heading levels follow the `e2e-runbooks` tasks-template, which fixes the section headings at level two, overriding this repository's level-three rule.

This file is an index, not a template. The schema gives a change one `tasks-template.md`, which assumes one capability per change, and this change introduces eight. The eight real templates live in [../../../e2e/testing/templates/](../../../e2e/testing/templates/), one per spec, sharing the `{N}` prefix and capability name of the spec they mirror. Copy from there, never from here.

---

## The eight templates

| N | Capability | Spec | Template |
|---|---|---|---|
| 10 | wizard-toggle-parse | [10-wizard-toggle-parse-test.md](../../../e2e/testing/10-wizard-toggle-parse-test.md) | [10-wizard-toggle-parse-tasks.template.md](../../../e2e/testing/templates/10-wizard-toggle-parse-tasks.template.md) |
| 20 | package-name-resolution | [20-package-name-resolution-test.md](../../../e2e/testing/20-package-name-resolution-test.md) | [20-package-name-resolution-tasks.template.md](../../../e2e/testing/templates/20-package-name-resolution-tasks.template.md) |
| 30 | smoke | [30-smoke-test.md](../../../e2e/testing/30-smoke-test.md) | [30-smoke-tasks.template.md](../../../e2e/testing/templates/30-smoke-tasks.template.md) |
| 40 | kde-configure-only | [40-kde-configure-only-test.md](../../../e2e/testing/40-kde-configure-only-test.md) | [40-kde-configure-only-tasks.template.md](../../../e2e/testing/templates/40-kde-configure-only-tasks.template.md) |
| 50 | live-profile | [50-live-profile-test.md](../../../e2e/testing/50-live-profile-test.md) | [50-live-profile-tasks.template.md](../../../e2e/testing/templates/50-live-profile-tasks.template.md) |
| 60 | defaults | [60-defaults-test.md](../../../e2e/testing/60-defaults-test.md) | [60-defaults-tasks.template.md](../../../e2e/testing/templates/60-defaults-tasks.template.md) |
| 70 | desktop-environments | [70-desktop-environments-test.md](../../../e2e/testing/70-desktop-environments-test.md) | [70-desktop-environments-tasks.template.md](../../../e2e/testing/templates/70-desktop-environments-tasks.template.md) |
| 80 | all-software | [80-all-software-test.md](../../../e2e/testing/80-all-software-test.md) | [80-all-software-tasks.template.md](../../../e2e/testing/templates/80-all-software-tasks.template.md) |

---

## What each template contains

Every one mirrors its spec's Prerequisites, Reset state, Run and Expected items as checkboxes, in the spec's order, then adds a Verdict checkbox and a Result summary block with Input tokens, Output tokens, Start (UTC), End (UTC) and Duration, then an "Additional tasks I did" section for anything done off-spec.

One shape deviates from a plain mirror, because the harness behaves that way. The template for capability 70 covers two container runs, KDE and GNOME, in one record. Every assertion box is ticked twice or not at all, and one green run beside one red run is a FAIL.

A second deviation existed and has been removed. The template for capability 50 used to offer no clean tick for the native and flatpak assertions, because verification never saw the profile and those assertions were expected to report misses. The harness now passes the profile to the verify play, so those boxes are ordinary passes and the template asks for `verify_rc: 0` like every other capability. The old boxes asked the runner to reconcile a missing list by hand, which is exactly the kind of judgement call a gate should not need.

---

## Runner contract

1. Copy the matching template from [../../../e2e/testing/templates/](../../../e2e/testing/templates/) into `e2e/testing/runs/` under `<UTC-timestamp>_{N}-{capability}-tasks.md`.
2. Record Start (UTC) as the very first action, before the prerequisite checks begin.
3. Execute each task in spec order. Tick on success, write down what happened on failure.
4. Record End (UTC) once the verdict is decided.
5. Compute Duration as HH:MM:SS, wall clock for the whole test rather than for the harness invocation alone.
6. Fill the token fields with the best available estimate, or leave them blank. Do not invent a number.
7. Write the Result summary and the Verdict, PASS or FAIL. A container scenario that hit its declared timeout is a FAIL with a stated cause, not an inconclusive run.
8. Log anything done outside the spec under "Additional tasks I did".

---

## Status

No run record exists yet. Nothing in this change has been executed through the schema, which is why the change carries no `run.md`: writing one would be fabricating a test result. The full runner contract also lives in [../../../e2e/testing/runs/README.md](../../../e2e/testing/runs/README.md), which is where a runner will actually read it.
