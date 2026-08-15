# all-software: run tasks template

Spec: [../80-all-software-test.md](../80-all-software-test.md)

Copy this file to `../runs/<UTC-timestamp>_80-all-software-tasks.md` before starting a run. Tick boxes as you go. Anything you did beyond the spec goes under "Additional tasks I did".

Heading levels and the single horizontal rule follow the `e2e-runbooks` tasks-template, which fixes both, overriding this repository's level-three heading rule and its rule-before-every-heading rule.

## Tasks

### Prerequisites

- [ ] `uname -s` prints Linux
- [ ] `docker info` returns a daemon summary
- [ ] `df -h /var/lib/docker` shows many tens of gigabytes free, figure recorded
- [ ] `docker ps -a --filter name=e2e-arch-` printed nothing, or the leftovers were removed before starting
- [ ] `./e2e/run.sh --list` shows the `all-software` row with a 300 minute timeout
- [ ] `git status --short setup` shows only the change under test, since the toggle list is generated from group_vars as it stands on disk

### Reset state

- [ ] Any leftover container from an aborted run was removed, or there were none
- [ ] `docker system df` was read and host disk reclaimed if it was tight, figures recorded
- [ ] Base image rebuild decision recorded: rebuilt because the Dockerfile changed, or reused the cached image

### Run

- [ ] Step 1: the detached launch returned, container name and run directory recorded, along with the generated toggle count and the excluded list the launch printed
- [ ] Step 2: `--collect` ran after the playbook finished, and did not have to exit 3 more than expected

### Expected

- [ ] `result.txt` reports `playbook_rc: 0`
- [ ] `result.txt` reports `verify_rc: 0`
- [ ] Native package assertion passed, expected and missing counts recorded, and this is the largest expected set of any scenario
- [ ] Flatpak assertion passed, expected and missing counts recorded
- [ ] `systemctl is-enabled tailscaled.service` exited 0
- [ ] `id -nG` contains the group named by `os_dict.openrazer_device_group`
- [ ] `id -nG` contains `docker`
- [ ] `/etc/sudoers.d/99-ansible-user` does not exist
- [ ] `effective-vars.yaml` confirms both `install_kde_plasma` and `install_gnome` were generated true, and understood that neither desktop is asserted here
- [ ] `stable_diffusion` appears in the excluded list the harness printed
- [ ] `Assert docker.service is enabled when Docker was requested` passed, or was skipped because the toggle is off
- [ ] `Assert flatpak is installed and the Flathub remote is configured` passed
- [ ] The suppressed container-limits list printed by the harness was read and recorded, and this run is not being reported as coverage of everything
- [ ] The DKMS module failures and the missing login session were recognised as documented container consequences, not regressions
- [ ] If the run met the ansible-core deserialization race, it was recorded as an environment failure with the upstream issue named, and re-run rather than explained away

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
