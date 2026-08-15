# defaults: run tasks template

Spec: [../60-defaults-test.md](../60-defaults-test.md)

Copy this file to `../runs/<UTC-timestamp>_60-defaults-tasks.md` before starting a run. Tick boxes as you go. Anything you did beyond the spec goes under "Additional tasks I did".

Heading levels and the single horizontal rule follow the `e2e-runbooks` tasks-template, which fixes both, overriding this repository's level-three heading rule and its rule-before-every-heading rule.

## Tasks

### Prerequisites

- [ ] `uname -s` prints Linux
- [ ] `docker info` returns a daemon summary
- [ ] `df -h /var/lib/docker` shows tens of gigabytes free, figure recorded
- [ ] `docker ps -a --filter name=e2e-arch-` printed nothing, or the leftovers were noted
- [ ] `./e2e/run.sh --list` shows the `defaults` row with a 180 minute timeout
- [ ] `git status --short setup` shows only the change under test

### Reset state

- [ ] Any leftover container from an aborted run was removed, or there were none
- [ ] Base image rebuild decision recorded: rebuilt because the Dockerfile changed, or reused the cached image

### Run

- [ ] Step 1: the detached launch returned, container name and run directory recorded
- [ ] Step 2: `--collect` ran after the playbook finished, and did not have to exit 3 more than expected

### Expected

- [ ] `result.txt` reports `playbook_rc: 0`
- [ ] `result.txt` reports `verify_rc: 0`
- [ ] Native package assertion passed, expected and missing counts recorded
- [ ] Flatpak assertion passed, expected and missing counts recorded
- [ ] `systemctl is-enabled tailscaled.service` exited 0
- [ ] `id -nG` contains the group named by `os_dict.openrazer_device_group`
- [ ] `id -nG` contains `docker`
- [ ] `/etc/sudoers.d/99-ansible-user` does not exist
- [ ] No desktop environment assertion ran, as expected for the wizard's skip answer
- [ ] `Assert docker.service is enabled when Docker was requested` passed, or was skipped because the toggle is off
- [ ] `Assert flatpak is installed and the Flathub remote is configured` passed
- [ ] The suppressed container-limits list printed by the harness was read and recorded, and the run is not being reported as full default coverage
- [ ] The DKMS module failure and the absent user-scope Syncthing unit were recognised as documented container consequences, not regressions

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
