# package-name-resolution: run tasks template

Spec: [../20-package-name-resolution-test.md](../20-package-name-resolution-test.md)

Copy this file to `../runs/<UTC-timestamp>_20-package-name-resolution-tasks.md` before starting a run. Tick boxes as you go. Anything you did beyond the spec goes under "Additional tasks I did".

Heading levels and the single horizontal rule follow the `e2e-runbooks` tasks-template, which fixes both, overriding this repository's level-three heading rule and its rule-before-every-heading rule.

## Tasks

### Prerequisites

- [ ] `uname -s` prints Linux
- [ ] `docker info` returns a daemon summary, since the entry point gates tier 2 behind it
- [ ] `command -v curl` prints a path
- [ ] `gh auth status` shows a logged-in account, or the winget skip was accepted and recorded
- [ ] The archlinux.org probe returned 200, so outbound access works

### Reset state

- [ ] Confirmed there is nothing to reset: this test writes no persisted state and installs nothing

### Run

- [ ] `./e2e/run.sh --tier 2` completed and its exit code was recorded

### Expected

- [ ] Exit code 0
- [ ] Arch official repositories: every pacman name resolved, count recorded
- [ ] Arch User Repository: every name resolved, count recorded
- [ ] Flathub: every application id resolved, count recorded
- [ ] Homebrew formulae: every name resolved, count recorded
- [ ] Homebrew casks: every name resolved, count recorded
- [ ] Chocolatey: every package id resolved, count recorded
- [ ] winget: every manifest id resolved, skipped Store id count recorded, or the whole check was skipped for want of authentication and that is recorded
- [ ] The apt and dnf gap warning appeared, and is understood as a stated gap rather than a pass

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
