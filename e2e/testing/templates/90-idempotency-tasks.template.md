# idempotency: run tasks template

Spec: [../90-idempotency-test.md](../90-idempotency-test.md)

Copy this file to `../runs/<UTC-timestamp>_90-idempotency-tasks.md` before starting a run. Tick boxes as you go. Anything you did beyond the spec goes under "Additional tasks I did".

Heading levels and the single horizontal rule follow the `e2e-runbooks` tasks-template, which fixes both, overriding this repository's level-three heading rule and its rule-before-every-heading rule.

## Tasks

### Prerequisites

- [ ] `uname -s` printed a shell the harness accepts, and which shell it was is recorded
- [ ] `docker info` returns a daemon summary
- [ ] `df -h /var/lib/docker` shows tens of gigabytes free, figure recorded
- [ ] `free -g` shows at least 5 GB available per concurrent scenario, or the check was knowingly skipped from Git Bash
- [ ] `docker ps -a --filter name=e2e-` printed nothing, or the leftovers were noted
- [ ] `./e2e/run.sh --list` shows the `idempotency` row with a 300 minute timeout
- [ ] `git status --short setup` shows only the change under test

### Reset state

- [ ] Any leftover container from an aborted run was removed, or there were none
- [ ] Base image rebuild decision recorded: rebuilt because the Dockerfile changed, or reused the cached image
- [ ] Nothing was reset, cleaned or touched between the two passes

### Run

- [ ] The distribution this run targeted is recorded, and it is understood that idempotency does not generalise across distributions
- [ ] Step 1: the detached launch returned, container name and run directory recorded
- [ ] Step 2: `--collect` ran after both passes had finished

### Expected

- [ ] `result.txt` reports `playbook_rc: 0`
- [ ] `result.txt` reports `second_run_rc: 0`, and it is not `never-ran`
- [ ] `result.txt` reports `verify_rc: 0`
- [ ] `second_run_changed_total` recorded
- [ ] `second_run_changed_not_allowed` is zero, and if it is not, every task it names is written into the run record
- [ ] `second_run_changed_allowed` recorded, and every exemption used was read against its reason in the allowlist
- [ ] The parsed changed count was checked against the `changed=N` figure in the recap at the end of `playbook2.log`
- [ ] Native package assertion passed, expected and missing counts recorded, which also proves the second pass removed nothing
- [ ] Flatpak assertion passed, expected and missing counts recorded
- [ ] `Assert every enabled URL-installed package resolved a download location` passed, and the candidate count is recorded
- [ ] `systemctl is-enabled tailscaled.service` exited 0
- [ ] `id -nG` contains the group named by `os_dict.openrazer_device_group`
- [ ] `id -nG` contains `docker`
- [ ] `Assert docker.service is enabled when Docker was requested` passed
- [ ] `Assert flatpak is installed and the Flathub remote is configured` passed
- [ ] `/etc/sudoers.d/99-ansible-user` does not exist
- [ ] No desktop environment assertion ran, as expected for the wizard's skip answer
- [ ] Any new allowlist entry added because of this run states which fact about the moment makes the task unrepeatable, and says whether the cause is the container rather than the task
- [ ] The suppressed container-limits list printed by the harness was read, and it is recorded that nothing is known about the idempotency of those toggles

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
