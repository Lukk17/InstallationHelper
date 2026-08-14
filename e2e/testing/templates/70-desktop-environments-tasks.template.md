# desktop-environments: run tasks template

Spec: [../70-desktop-environments-test.md](../70-desktop-environments-test.md)

Copy this file to `../runs/<UTC-timestamp>_70-desktop-environments-tasks.md` before starting a run. Tick boxes as you go. Anything you did beyond the spec goes under "Additional tasks I did".

This capability is two runs, KDE and GNOME. Both must pass. One record covers both, so every assertion below is ticked twice or not at all.

Heading levels and the single horizontal rule follow the `e2e-runbooks` tasks-template, which fixes both, overriding this repository's level-three heading rule and its rule-before-every-heading rule.

## Tasks

### Prerequisites

- [ ] `uname -s` prints Linux
- [ ] `docker info` returns a daemon summary
- [ ] `df -h /var/lib/docker` shows many tens of gigabytes free, figure recorded
- [ ] `docker ps -a --filter name=e2e-arch-` printed nothing, or the leftovers were noted
- [ ] `./e2e/run.sh --list` shows both the `kde-full` and the `gnome-full` row, each with a 300 minute timeout
- [ ] `git status --short setup` shows only the change under test

### Reset state

- [ ] Any leftover container from an aborted run was removed, or there were none
- [ ] Base image rebuild decision recorded, and taken before step 1 so both runs use the same image

### Run

- [ ] Step 1: the KDE launch returned, container name and run directory recorded
- [ ] Step 2: the GNOME launch returned, container name and run directory recorded, and the decision to overlap or serialise the two runs is stated
- [ ] Step 3: `--collect` on the KDE run directory completed
- [ ] Step 4: `--collect` on the GNOME run directory completed

### Expected

- [ ] KDE run: `result.txt` reports `playbook_rc: 0` and `verify_rc: 0`
- [ ] GNOME run: `result.txt` reports `playbook_rc: 0` and `verify_rc: 0`
- [ ] Both runs: native package assertion passed, expected and missing counts recorded per run
- [ ] Both runs: flatpak assertion passed, counts recorded per run
- [ ] Both runs: `systemctl is-enabled tailscaled.service` exited 0
- [ ] Both runs: `id -nG` contains the group named by `os_dict.openrazer_device_group`
- [ ] Both runs: `id -nG` contains `docker`
- [ ] Both runs: `/etc/sudoers.d/99-ansible-user` does not exist
- [ ] KDE run: `pacman -Qq plasma-desktop` exited 0
- [ ] GNOME run: `pacman -Qq gnome-shell` exited 0
- [ ] Understood that the configure half of the `full` action is not asserted, and any configure oddity was recorded in the Result summary rather than ticked
- [ ] `docker.service` unit state was read for information only in both runs, not ticked as an assertion
- [ ] The suppressed container-limits list printed by each run was read and recorded
- [ ] The DKMS module failure and the missing login session were recognised as documented container consequences, not regressions, and no judgement was made about how either desktop looks

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
