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
- [ ] `all.yaml`: bash parse matches the YAML, line shape valid, no stray colon, no toggle dropped, both wizards see the same keys
- [ ] `linux.yaml`: same five checks passed
- [ ] `macos.yaml`: same five checks passed
- [ ] `windows.yaml`: same five checks passed
- [ ] Toggle coverage passed for Debian, RedHat, Archlinux, Darwin and Windows
- [ ] `documented_no_ops.txt` has no stale entries
- [ ] `site.yaml` parses
- [ ] Syntax check emitted at most two warnings, actual count recorded
- [ ] No repository file was mistaken for an inventory source
- [ ] `verify.yaml` parses
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
