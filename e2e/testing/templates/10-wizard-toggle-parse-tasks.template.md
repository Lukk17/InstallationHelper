# wizard-toggle-parse: run tasks template

Spec: [../10-wizard-toggle-parse-test.md](../10-wizard-toggle-parse-test.md)

Copy this file to `../runs/<UTC-timestamp>_10-wizard-toggle-parse-tasks.md` before starting a run. Tick boxes as you go. Anything you did beyond the spec goes under "Additional tasks I did".

Heading levels and the single horizontal rule follow the `e2e-runbooks` tasks-template, which fixes both, overriding this repository's level-three heading rule and its rule-before-every-heading rule.

## Tasks

### Prerequisites

- [ ] `uname -s` prints Linux
- [ ] `command -v ansible-playbook` prints a path
- [ ] `grep -V` names GNU grep, so the cross-wizard comparison is not skipped
- [ ] `git status --short setup e2e` shows only the change under test
- [ ] Noted whether yamllint is installed, and recorded which answer it gave

### Reset state

- [ ] Confirmed there is nothing to reset: this test writes no persisted state and starts no container

### Run

- [ ] `./e2e/run.sh` completed and its exit code was recorded

### Expected

- [ ] Exit code 0
- [ ] `wizard_parse`: `all.yaml` bash parse matches the YAML, line shape valid, no stray colon, no toggle dropped, both wizards see the same keys
- [ ] `wizard_parse`: `linux.yaml`, same five checks passed
- [ ] `wizard_parse`: `macos.yaml`, same five checks passed
- [ ] `wizard_parse`: `windows.yaml`, same five checks passed
- [ ] `wizard_parse`: every visible system setting has a descriptive label, and both wizards hide the same toggles
- [ ] `toggle_coverage`: passed for Debian, RedHat, Archlinux, Darwin and Windows
- [ ] `toggle_coverage`: `documented_no_ops.txt` has no stale entries
- [ ] `windows_mapping`: PowerShell and the YAML agree on every mapping including manager and source, count recorded, and whether the PowerShell half ran or reported SKIP
- [ ] `windows_mapping`: the Windows python mapping matches `default_python`
- [ ] `windows_npm_parity`: both lists name the same npm packages and each has a toggle
- [ ] `verify_spec_parity`: every verify assertion is named in all six container specs, and this spec names every tier 1 check script
- [ ] `ansible_static`: `site.yaml` parses
- [ ] `ansible_static`: syntax check emitted at most two warnings, actual count recorded
- [ ] `ansible_static`: no repository file was mistaken for an inventory source
- [ ] `ansible_static`: `verify.yaml` parses
- [ ] `ansible_static`: whether it ran locally or re-executed itself inside WSL was recorded
- [ ] yamllint result recorded, either clean or skipped with the reason
- [ ] ansible-lint findings recorded as information only

### Verdict

- [ ] Verdict: PASS / FAIL (delete the wrong one)

## Result summary

Input tokens:

Output tokens:

Start (UTC):

End (UTC):

Duration:

---

## Additional tasks I did
