# live-profile: run tasks template

Spec: [../50-live-profile-test.md](../50-live-profile-test.md)

Copy this file to `../runs/<UTC-timestamp>_50-live-profile-tasks.md` before starting a run. Tick boxes as you go. Anything you did beyond the spec goes under "Additional tasks I did".

Heading levels and the single horizontal rule follow the `e2e-runbooks` tasks-template, which fixes both, overriding this repository's level-three heading rule and its rule-before-every-heading rule.

## Tasks

### Prerequisites

- [ ] `uname -s` prints Linux
- [ ] `docker info` returns a daemon summary
- [ ] `df -h /var/lib/docker` shows several gigabytes free, figure recorded
- [ ] `docker ps -a --filter name=e2e-arch-` printed nothing, or the leftovers were noted
- [ ] `./e2e/run.sh --list` shows the `live-profile` row with a 120 minute timeout
- [ ] `ls setup/ansible/profiles/linux_live.yaml` printed the path
- [ ] `git status --short setup` shows only the change under test

### Reset state

- [ ] Any leftover container from an aborted run was removed, or there were none
- [ ] Base image rebuild decision recorded: rebuilt because the Dockerfile changed, or reused the cached image

### Run

- [ ] Step 1: the detached launch returned, container name and run directory recorded
- [ ] Step 2: `--collect` ran after the playbook finished, and did not have to exit 3 more than expected

### Expected

- [ ] `result.txt` reports `playbook_rc: 0`
- [ ] `result.txt` reports `verify_rc: 0`, with the value stated rather than assumed
- [ ] The verify output line reads `Running verification (with profile linux_live)`, confirming verification saw the profile
- [ ] The native assertion passed with no missing list
- [ ] The flatpak assertion passed with no missing list
- [ ] The tailscaled, OpenRazer group and docker group assertions each either passed or were skipped because the profile disabled the toggle, and the skip count in the verify recap accounts for every one of them
- [ ] `/etc/sudoers.d/99-ansible-user` does not exist
- [ ] `effective-vars.yaml` was read, and the container limits are visibly last so they outrank the profile
- [ ] No desktop environment assertion ran, as expected for `e2e_expect_desktop: none`
- [ ] `Assert docker.service is enabled when Docker was requested` passed, or was skipped because the toggle is off
- [ ] `Assert flatpak is installed and the Flathub remote is configured` passed
- [ ] The suppressed container-limits list printed by the harness was read and recorded, including the bootloader entries that matter most on a live install
- [ ] The DKMS module failure and the missing login session were recognised as documented container consequences, not regressions

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
