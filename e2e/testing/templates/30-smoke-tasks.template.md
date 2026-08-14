# smoke: run tasks template

Spec: [../30-smoke-test.md](../30-smoke-test.md)

Copy this file to `../runs/<UTC-timestamp>_30-smoke-tasks.md` before starting a run. Tick boxes as you go. Anything you did beyond the spec goes under "Additional tasks I did".

Heading levels and the single horizontal rule follow the `e2e-runbooks` tasks-template, which fixes both, overriding this repository's level-three heading rule and its rule-before-every-heading rule.

## Tasks

### Prerequisites

- [ ] `uname -s` prints Linux
- [ ] `docker info` returns a daemon summary
- [ ] `df -h /var/lib/docker` shows several gigabytes free, figure recorded
- [ ] `docker ps -a --filter name=e2e-arch-` printed nothing, or the leftovers were noted
- [ ] `./e2e/run.sh --list` shows the `smoke` row with a 45 minute timeout
- [ ] `git status --short setup` shows only the change under test

### Reset state

- [ ] Any leftover container from an aborted run was removed, or there were none
- [ ] Base image rebuild decision recorded: rebuilt because the Dockerfile changed, or reused the cached image

### Run

- [ ] `./e2e/run.sh --tier 3 --scenario smoke` completed, run directory path recorded

### Expected

- [ ] `result.txt` reports `playbook_rc: 0`
- [ ] `result.txt` reports `verify_rc: 0`
- [ ] Native packages present: `steam`, `syncthing`, `tailscale`, `openrazer-daemon`, `chkrootkit`
- [ ] Flatpak application present: `app.polychromatic.controller`
- [ ] `systemctl is-enabled tailscaled.service` exited 0
- [ ] `id -nG` contains the group named by `os_dict.openrazer_device_group`
- [ ] `id -nG` contains `docker`
- [ ] `/etc/sudoers.d/99-ansible-user` does not exist
- [ ] No desktop environment assertion ran, as expected for `e2e_expect_desktop: none`
- [ ] `docker.service` unit state was read for information only, not ticked as an assertion
- [ ] The suppressed container-limits list printed by the harness was read and recorded
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
