# forced-failure: run tasks template

Spec: [../30-forced-failure-test.md](../30-forced-failure-test.md)

Copy this file to `../runs/<UTC-timestamp>_30-forced-failure-tasks.md` before starting a run. Tick boxes as you go. Anything you did beyond the spec goes under "Additional tasks I did".

Heading levels and the single horizontal rule follow the `e2e-runbooks` tasks-template, which fixes both, overriding this repository's level-three heading rule and its rule-before-every-heading rule.

## Tasks

### Prerequisites

- [ ] `uname -s` printed a shell the harness accepts, and which shell it was is recorded
- [ ] `docker info` returns a daemon summary
- [ ] `df -h /var/lib/docker` shows several gigabytes free, figure recorded
- [ ] `docker ps -a --filter name=e2e-` printed nothing, or the leftovers were noted
- [ ] `./e2e/run.sh --list` shows the `forced-failure` row with a 90 minute timeout
- [ ] `git status --short setup` shows only the change under test

### Reset state

- [ ] Any leftover container from an aborted run was removed, or there were none
- [ ] Base image rebuild decision recorded: rebuilt because the Dockerfile changed, or reused the cached image

### Run

- [ ] The distribution this run targeted is recorded, and it is understood that a pass on one is not evidence about the others
- [ ] The run finished and was collected, either in the foreground or with `--collect`

### Expected

- [ ] `result.txt` reports a non-zero `playbook_rc`, and the value is recorded
- [ ] `result.txt` reports a non-zero `verify_rc`, and the value is recorded
- [ ] The harness reported `the playbook exited <n>, so the failure reached the exit code`
- [ ] The harness reported `the terminal summary names a failing task`, and the task it named is recorded
- [ ] The harness reported `the error log names the same failing task`
- [ ] The harness reported `verification refused and named the missing packages`
- [ ] `Assert the installed-package query returned a plausible list` passed, so the run failed because nothing was installed rather than because the query broke
- [ ] `Assert every enabled native package is installed` failed, and the applications it named are recorded
- [ ] The assertions after it were not reached, and that was recorded as not reached rather than as passed
- [ ] `Assert the expected desktop environment is installed` did not run, as expected for `e2e_expect_desktop: none`
- [ ] The `[ERROR] Install step ... failed` line was read, and whether it names the batch and explains that a batch is one call is recorded as a judgement
- [ ] `effective-vars.yaml` was checked to confirm the injected `software_installer_batches` value reached the playbook
- [ ] It is understood that this capability says nothing about whether any software installs correctly

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
