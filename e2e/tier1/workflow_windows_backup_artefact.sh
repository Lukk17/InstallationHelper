#!/usr/bin/env bash
#
# Tier 1: every workflow job that starts setup.ps1 to install keeps the configuration backup it made.
#
# setup.ps1 copies every configuration file it is about to change into
# %LOCALAPPDATA%\installation-helper\backup, owner decision 40, and a hosted runner is thrown away
# when its job ends. Until 2026-11-13 no Windows job copied that folder into its artefact, so what a
# run backed up, and whether it backed up anything, could not be read after the run,
# docs/regression_ledger.md 10.334 and 10.336.
#
# So, for every job in every workflow under .github/workflows that starts setup.ps1 for anything but
# -PrintPlan or -ListSoftware, in a step of its own or in a local action it uses, the reader requires a
# later step under if: always() whose code, not a comment, names installation-helper\backup, and after
# it an actions/upload-artifact step under if: always() whose path ends in a folder that copy step
# names. Which steps start the wizard is decided by e2e/lib/windows_wizard_jobs.py, the reader
# workflow_windows_pester shares.
#
# Before it reads the repository it runs its reader against planted workflows and requires it to name
# exactly the seven planted defects and none of the two sound jobs, so a reader that went blind fails
# here instead of passing the real tree.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: every job that installs with setup.ps1 uploads the configuration backup"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "Windows backup artefact"; }

require_python "every job that installs with setup.ps1 uploads the configuration backup" "Windows backup artefact"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re
import sys

import yaml

sys.path.insert(0, 'e2e/lib')
from windows_wizard_jobs import code_lines, starts_wizard, steps_of

BACKUP = re.compile(r'installation-helper[\\/]+backup', re.IGNORECASE)
UPLOAD = 'actions/upload-artifact'


def under_always(step):
    condition = step.get('if')
    return isinstance(condition, str) and 'always()' in condition


def upload_folder(step):
    path = (step.get('with') or {}).get('path')
    if not isinstance(path, str):
        return None
    parts = [part for part in re.split(r'[\\/]', path.strip()) if part and '{{' not in part and '}}' not in part]
    return parts[-1] if parts else None


def job_problems(where, job, actions):
    """None for a job that never installs with setup.ps1, otherwise the list of what is wrong."""
    steps = steps_of(job)
    wizard_at = next((i for i, step in enumerate(steps) if starts_wizard(step, actions)), None)
    if wizard_at is None:
        return None
    copies = [i for i in range(wizard_at + 1, len(steps))
              if isinstance(steps[i].get('run'), str) and any(BACKUP.search(line) for line in code_lines(steps[i]['run']))]
    if not copies:
        return ['%s starts setup.ps1 at step %d and no later step copies %%LOCALAPPDATA%%\\installation-helper\\backup'
                % (where, wizard_at + 1)]
    copy_at = copies[0]
    problems = []
    if not under_always(steps[copy_at]):
        problems.append('%s copies the backup at step %d without if: always(), so a failed run loses it'
                        % (where, copy_at + 1))
    uploads = [i for i in range(copy_at + 1, len(steps))
               if isinstance(steps[i].get('uses'), str) and steps[i]['uses'].split('@')[0] == UPLOAD]
    if not uploads:
        problems.append('%s copies the backup at step %d and no later step uploads an artefact' % (where, copy_at + 1))
        return problems
    upload = steps[uploads[0]]
    if not under_always(upload):
        problems.append('%s uploads its artefact at step %d without if: always(), so a failed run loses the backup'
                        % (where, uploads[0] + 1))
    folder = upload_folder(upload)
    if not folder or folder not in '\n'.join(code_lines(steps[copy_at]['run'])):
        problems.append('%s uploads %s at step %d, a folder the copy at step %d does not name'
                        % (where, (upload.get('with') or {}).get('path'), uploads[0] + 1, copy_at + 1))
    return problems


def analyse(workflows, actions):
    """Returns the install jobs found and every (label, problem) pair."""
    install_jobs, problems = [], []
    for label, doc in sorted(workflows.items()):
        for name, job in ((doc or {}).get('jobs') or {}).items():
            if not isinstance(job, dict):
                continue
            found = job_problems('%s job %s' % (label, name), job, actions)
            if found is not None:
                install_jobs.append('%s:%s' % (label, name))
                problems.extend((label, text) for text in found)
    return install_jobs, problems


def planted():
    wizard = {'shell': 'pwsh', 'run': '& ./setup/setup.ps1 -NonInteractive -Software all'}
    plan = {'shell': 'pwsh', 'run': '& ./setup/setup.ps1 -NonInteractive -PrintPlan'}
    copy_body = ("$dest = Join-Path $env:RUNNER_TEMP 'wizard-logs'\n"
                 "Copy-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'installation-helper\\backup') -Destination $dest -Recurse")
    copy = {'if': 'always()', 'shell': 'pwsh', 'run': copy_body}
    upload = {'if': 'always()', 'uses': 'actions/upload-artifact@v4', 'with': {'path': '${{ runner.temp }}/wizard-logs/'}}

    def one_job(*steps):
        return {'jobs': {'install': {'runs-on': 'windows-latest', 'steps': list(steps)}}}

    workflows = {
        'no-copy.yml': one_job(wizard, upload),
        'copy-first.yml': one_job(copy, wizard, upload),
        'not-always.yml': one_job(wizard, {'shell': 'pwsh', 'run': copy_body}, upload),
        'comment-only.yml': one_job(wizard, {'if': 'always()', 'shell': 'pwsh',
                                             'run': '# keeps installation-helper\\backup\nWrite-Host wizard-logs'}, upload),
        'no-upload.yml': one_job(wizard, copy),
        'upload-not-always.yml': one_job(wizard, copy, dict(upload, **{'if': 'success()'})),
        'elsewhere.yml': one_job(wizard, copy, dict(upload, **{'with': {'path': '${{ runner.temp }}/other-logs/'}})),
        'sound.yml': one_job(wizard, copy, upload),
        'sound-plan.yml': one_job(plan),
    }
    return workflows, {}


lines = []

expected = {'no-copy.yml', 'copy-first.yml', 'not-always.yml', 'comment-only.yml', 'no-upload.yml',
            'upload-not-always.yml', 'elsewhere.yml'}
_, planted_problems = analyse(*planted())
named = {label for label, _ in planted_problems}
if named == expected and len(planted_problems) == len(expected):
    lines.append('OK the reader names exactly the seven planted defects and none of the two sound jobs')
else:
    lines.append('FAIL the reader misreads planted workflows, so nothing it says about the real ones '
                 'can be trusted :: expected one problem each in %s, got %s'
                 % (', '.join(sorted(expected)), ' | '.join(text for _, text in planted_problems) or 'none'))

workflows = {}
for path in sorted(pathlib.Path('.github/workflows').glob('*.y*ml')):
    workflows[path.as_posix()] = yaml.safe_load(path.read_text(encoding='utf-8'))
actions = {}
for path in sorted(pathlib.Path('.github/actions').glob('*/action.y*ml')):
    actions['./' + path.parent.as_posix()] = yaml.safe_load(path.read_text(encoding='utf-8'))

install_jobs, problems = analyse(workflows, actions)
if not install_jobs:
    lines.append('FAIL no workflow job starts setup.ps1 to install, so this check proves nothing :: read '
                 '%d workflow(s)' % len(workflows))
elif problems:
    lines.append('FAIL a job that installs with setup.ps1 does not upload the configuration backup it made '
                 ':: %s' % ' | '.join(text for _, text in problems))
else:
    lines.append('OK all %d job(s) that start setup.ps1 to install copy %%LOCALAPPDATA%%\\installation-helper\\backup '
                 'into the artefact they upload, even after a failure: %s' % (len(install_jobs), ', '.join(install_jobs)))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "Windows backup artefact"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) claim="${line#FAIL }"
               fail "${claim%% :: *}" "${claim#* :: }" ;;
        *)     [[ -n "${line}" ]] && fail "the Windows backup artefact check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "Windows backup artefact"
