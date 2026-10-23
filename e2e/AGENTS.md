# AGENTS.md for e2e/

Rules for the test harness and for deciding which run a change owes. The harness itself is explained in [README_E2E.md](README_E2E.md). This file only says what to read and what no check catches.

### Before you work here

1. Before deciding which run a change owes, read "What to run when you change something" in [README_E2E.md](README_E2E.md). A change that touches several rows owes every row.
2. Before adding or changing a check, read "Adding a check" in [README_E2E.md](README_E2E.md), and name the new check in [testing/10-wizard-toggle-parse-test.md](testing/10-wizard-toggle-parse-test.md) and in the tier 1 table of [README_E2E.md](README_E2E.md).
3. Before dispatching a workflow or editing one under [../.github/workflows/](../.github/workflows/), read "CI matrix sweep vs single platform runs" in [README_E2E.md](README_E2E.md).
4. Before telling the owner something is verified, read [manual_test_matrix.md](manual_test_matrix.md). Bootloaders, hibernation, Snapper, Waydroid, VirtualBox and VMware are suppressed in every container, and macOS has no container tier.
5. Before adding, removing or renumbering a capability, or changing its invocation or cost, read [../openspec/AGENTS.md](../openspec/AGENTS.md).

### Rules no check catches

1. After any change under `setup/`, run the tier 1 gate from the repository root. It runs inside its own container and is the only check you run yourself:

   ```bash
   bash e2e/run.sh
   ```

2. A non-zero exit means the work is not done. Do not report success, do not commit, and do not explain the failure away.
3. A tier that cannot run is not a tier that passed. Run it from a shell where it works instead of recording the change as verified.
4. Prove a new or changed check fails against a copy of the tree carrying the defect before trusting it, then run the whole gate. When the change touches `lib/gate.sh`, `lib/host.sh` or `gate/`, start the gate from Git Bash and from WSL as well.
5. Tier 3 runs only on a GitHub-hosted runner. From the owner's computer, dispatch it:

   ```bash
   gh workflow run e2e-manual.yaml -f target_platform=debian -f software_mode=defaults
   ```

6. No workflow may start on push or on any other automatic event. Every file under `.github/workflows/` stays dispatch-only or call-only.
7. Before dispatching the sweep, check whether one is already open, because a second dispatch queues behind it and sits at `pending`:

   ```bash
   gh run list --workflow e2e-matrix.yml --limit 5
   ```

8. Watch anything long every ten minutes, and check progress rather than presence. The same status ten minutes later is a stall. The commands are in "Watching a run, every ten minutes" in [README_E2E.md](README_E2E.md).
9. A queued run must be removed before the next one starts:

   ```bash
   docker rm e2e-queue
   ```

10. A fixture that puts fake commands on `PATH` must prove every command resolves to its fake before anything runs, defect class 16 in [../docs/regression_ledger.md](../docs/regression_ledger.md).
11. If a toggle intentionally does nothing on some OS, list it with the reason in [tier1/documented_no_ops.txt](tier1/documented_no_ops.txt). The gate fails otherwise, on purpose.
