#!/usr/bin/env bash
#
# Tier 1: every workflow job that starts setup.ps1 to install runs the Windows unit tests first.
#
# The Pester suite over the Windows installer runs in this gate on Linux, through windows_pester, and on
# a Windows runner only through the shared action .github/actions/windows-pester. Until 2026-11-13 only
# the sweep's stage 1 job ran the suite on Windows, so a dispatch of the single platform workflow at its
# windows target installed the whole software set without ever running it there. The KiCad 10 test of
# docs/regression_ledger.md 10.270 passed here on Linux and failed only on the Windows runner, and the
# single platform workflow could not have seen it.
#
# So, for every job in every workflow under .github/workflows that starts setup.ps1 for anything but
# -PrintPlan or -ListSoftware, in a step of its own or in a local action it uses:
#
#   - the job runs the shared action before that step, not under continue-on-error, and no wizard step
#     after it carries an `if` with always(), failure() or cancelled(), which would run it after a
#     failed test, or
#   - a job it needs, directly or through other needs, runs the shared action, not under
#     continue-on-error. That route proves order only: whether the install is skipped after a failed
#     test is the decision of the jobs in between, as "Gate: checks passed" decides it in the sweep.
#
# And no workflow step and no other local action runs Invoke-Pester or New-PesterConfiguration itself,
# so the suite has one way of running on Windows rather than a copy per workflow that can drift. The
# shared action must still run WindowsSoftware.Tests.ps1 with the Slow and Network tags excluded.
#
# Before it reads the repository it runs its reader against planted workflows and requires it to name
# exactly the six planted defects and none of the four sound jobs, so a reader that went blind fails
# here instead of passing the real tree.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: every job that installs with setup.ps1 runs the Windows unit tests first"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "Windows unit tests before the install"; }

require_python "every job that installs with setup.ps1 runs the Windows unit tests first" "Windows unit tests before the install"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re

import yaml

SHARED_USES = './.github/actions/windows-pester'
SHARED_FILE = pathlib.Path('.github/actions/windows-pester/action.yml')
SETUP_PS1 = re.compile(r'setup[/\\]setup\.ps1')
PLAN_ONLY = re.compile(r'(?<![\w-])-(PrintPlan|ListSoftware)\b', re.IGNORECASE)
RUNS_PESTER = re.compile(r'\b(Invoke-Pester|New-PesterConfiguration)\b', re.IGNORECASE)
OVERRIDES_FAILURE = re.compile(r'\b(always|failure|cancelled)\s*\(')
EXCLUDE_TAG = re.compile(r'ExcludeTag\s*=\s*@\(([^)]*)\)')


def code_lines(body):
    return [line for line in body.splitlines() if not line.strip().startswith('#')]


def is_true(value):
    return value is True or (isinstance(value, str) and value.strip().lower() == 'true')


def steps_of(container):
    return [step for step in ((container or {}).get('steps') or []) if isinstance(step, dict)]


def local_uses(step):
    uses = step.get('uses')
    if isinstance(uses, str) and uses.startswith('./'):
        return uses.rstrip('/')
    return None


def starts_wizard(step, actions, seen=()):
    """True when the step, or a local action it uses, starts setup.ps1 for anything but a plan."""
    body = step.get('run')
    if isinstance(body, str):
        return any(SETUP_PS1.search(line) and not PLAN_ONLY.search(line) for line in code_lines(body))
    uses = local_uses(step)
    if uses is None or uses == SHARED_USES or uses in seen:
        return False
    runs = (actions.get(uses) or {}).get('runs')
    return any(starts_wizard(inner, actions, seen + (uses,)) for inner in steps_of(runs))


def runs_pester_inline(step):
    body = step.get('run')
    return isinstance(body, str) and any(RUNS_PESTER.search(line) for line in code_lines(body))


def needs_of(job):
    needs = job.get('needs')
    if isinstance(needs, str):
        return [needs]
    if isinstance(needs, list):
        return [name for name in needs if isinstance(name, str)]
    return []


def shared_step(job):
    for index, step in enumerate(steps_of(job)):
        if local_uses(step) == SHARED_USES:
            return index, step
    return None, None


def upstream_runs_tests(name, jobs):
    queue, seen = needs_of(jobs[name]), set()
    while queue:
        other = queue.pop()
        if other in seen or not isinstance(jobs.get(other), dict):
            continue
        seen.add(other)
        _, step = shared_step(jobs[other])
        if step is not None and not is_true(step.get('continue-on-error')):
            return True
        queue.extend(needs_of(jobs[other]))
    return False


def job_problems(label, name, jobs, actions):
    """None for a job that never installs with setup.ps1, otherwise the list of what is wrong."""
    steps = steps_of(jobs[name])
    wizard_at = next((i for i, step in enumerate(steps) if starts_wizard(step, actions)), None)
    if wizard_at is None:
        return None
    where = '%s job %s' % (label, name)
    tests_at, tests = shared_step(jobs[name])
    if tests_at is None:
        if upstream_runs_tests(name, jobs):
            return []
        return ['%s starts setup.ps1 to install at step %d and runs %s neither before it nor in a '
                'job it needs' % (where, wizard_at + 1, SHARED_USES)]
    problems = []
    if tests_at > wizard_at:
        problems.append('%s runs %s at step %d, after it starts setup.ps1 to install at step %d'
                        % (where, SHARED_USES, tests_at + 1, wizard_at + 1))
    if is_true(tests.get('continue-on-error')):
        problems.append('%s runs %s under continue-on-error, so a failed test does not stop the install'
                        % (where, SHARED_USES))
    for index in range(tests_at + 1, len(steps)):
        condition = steps[index].get('if')
        if (starts_wizard(steps[index], actions) and isinstance(condition, str)
                and OVERRIDES_FAILURE.search(condition)):
            problems.append('%s starts setup.ps1 at step %d under if: %s, which runs it after a failed test'
                            % (where, index + 1, condition))
    return problems


def analyse(workflows, actions):
    """Returns the install jobs found and every (label, problem) pair."""
    install_jobs, problems = [], []
    for label, doc in sorted(workflows.items()):
        jobs = {name: job for name, job in ((doc or {}).get('jobs') or {}).items() if isinstance(job, dict)}
        for name in jobs:
            found = job_problems(label, name, jobs, actions)
            if found is not None:
                install_jobs.append('%s:%s' % (label, name))
                problems.extend((label, text) for text in found)
            for index, step in enumerate(steps_of(jobs[name])):
                if runs_pester_inline(step):
                    problems.append((label, '%s job %s runs Pester itself at step %d instead of calling %s'
                                     % (label, name, index + 1, SHARED_USES)))
    for uses, doc in sorted(actions.items()):
        if uses == SHARED_USES:
            continue
        for index, step in enumerate(steps_of((doc or {}).get('runs'))):
            if runs_pester_inline(step):
                problems.append((uses, 'the action %s runs Pester itself at step %d instead of calling %s'
                                 % (uses, index + 1, SHARED_USES)))
    return install_jobs, problems


def planted():
    wizard = {'shell': 'pwsh', 'run': '& ./setup/setup.ps1 -NonInteractive -Software all'}
    tests = {'uses': SHARED_USES}
    checkout = {'uses': 'actions/checkout@v4'}

    def one_job(*steps, **extra):
        return {'jobs': {'install': dict({'runs-on': 'windows-latest', 'steps': list(steps)}, **extra)}}

    workflows = {
        'no-tests.yml': one_job(checkout, wizard),
        'late.yml': one_job(checkout, wizard, tests),
        'soft.yml': one_job(checkout, dict(tests, **{'continue-on-error': True}), wizard),
        'always.yml': one_job(checkout, tests, dict(wizard, **{'if': 'always()'})),
        'inline.yml': one_job(checkout, {'shell': 'pwsh', 'run': '$r = Invoke-Pester -Path x'}),
        'hidden.yml': one_job(checkout, {'uses': './.github/actions/wrapper'}),
        'sound-steps.yml': one_job(checkout, tests, wizard),
        'sound-needs.yml': {'jobs': {
            'unit': {'runs-on': 'windows-latest', 'steps': [checkout, tests]},
            'gate': {'runs-on': 'ubuntu-latest', 'needs': 'unit', 'if': 'always()', 'steps': []},
            'install': {'runs-on': 'windows-latest', 'needs': ['gate'],
                        'if': "!cancelled() && needs.gate.outputs.ok == 'true'", 'steps': [checkout, wizard]},
        }},
        'sound-plan.yml': one_job(checkout, {'shell': 'pwsh',
                                             'run': '& ./setup/setup.ps1 -NonInteractive -PrintPlan\n'
                                                    'if ($LASTEXITCODE -ne 0) { throw "setup.ps1 exited" }'}),
        'sound-comment.yml': one_job(checkout, {'shell': 'pwsh',
                                                'run': '# setup/setup.ps1 runs in another job\nWrite-Host ok'}),
    }
    actions = {'./.github/actions/wrapper': {'runs': {'using': 'composite', 'steps': [wizard]}}}
    return workflows, actions


lines = []

expected = {'no-tests.yml', 'late.yml', 'soft.yml', 'always.yml', 'inline.yml', 'hidden.yml'}
_, planted_problems = analyse(*planted())
named = {label for label, _ in planted_problems}
if named == expected and len(planted_problems) == len(expected):
    lines.append('OK the reader names exactly the six planted defects and none of the four sound jobs')
else:
    lines.append('FAIL the reader misreads planted workflows, so nothing it says about the real ones '
                 'can be trusted :: expected one problem each in %s, got %s'
                 % (', '.join(sorted(expected)), ' | '.join(text for _, text in planted_problems) or 'none'))

shared = None
if SHARED_FILE.exists():
    shared = yaml.safe_load(SHARED_FILE.read_text(encoding='utf-8'))
runs = (shared or {}).get('runs') if isinstance(shared, dict) else None
bodies = '\n'.join('\n'.join(code_lines(step['run'])) for step in steps_of(runs)
                   if isinstance(step.get('run'), str))
excluded = EXCLUDE_TAG.search(bodies)
if not isinstance(runs, dict) or runs.get('using') != 'composite':
    lines.append('FAIL the shared action is not a composite action :: %s is missing or does not say '
                 'using: composite' % SHARED_FILE.as_posix())
elif not RUNS_PESTER.search(bodies) or 'WindowsSoftware.Tests.ps1' not in bodies:
    lines.append('FAIL the shared action does not run the Windows unit tests :: %s runs no Invoke-Pester '
                 'over e2e/tier1/windows/WindowsSoftware.Tests.ps1' % SHARED_FILE.as_posix())
elif not excluded or "'Slow'" not in excluded.group(1) or "'Network'" not in excluded.group(1):
    lines.append('FAIL the shared action runs the tests that install something :: %s does not set '
                 "ExcludeTag to @('Slow', 'Network'), so the Chocolatey bootstrap would run before the "
                 'install it is meant to stop' % SHARED_FILE.as_posix())
else:
    lines.append('OK %s runs WindowsSoftware.Tests.ps1 without the Slow and Network tagged tests'
                 % SHARED_FILE.as_posix())

workflows = {}
for path in sorted(pathlib.Path('.github/workflows').glob('*.y*ml')):
    workflows[path.as_posix()] = yaml.safe_load(path.read_text(encoding='utf-8'))
actions = {}
for path in sorted(pathlib.Path('.github/actions').glob('*/action.y*ml')):
    actions['./' + path.parent.as_posix()] = yaml.safe_load(path.read_text(encoding='utf-8'))

install_jobs, problems = analyse(workflows, actions)
if not workflows:
    lines.append('FAIL no workflow was read, so this check proves nothing :: .github/workflows holds no '
                 '.yml or .yaml file')
elif not install_jobs:
    lines.append('FAIL no workflow job starts setup.ps1 to install, so this check proves nothing :: read '
                 '%d workflow(s)' % len(workflows))
elif problems:
    lines.append('FAIL a job starts setup.ps1 to install without the Windows unit tests stopping it first, '
                 'or a workflow runs Pester outside the shared action :: %s'
                 % ' | '.join(text for _, text in problems))
else:
    lines.append('OK all %d job(s) that start setup.ps1 to install run %s first, and no workflow runs '
                 'Pester outside it: %s' % (len(install_jobs), SHARED_USES, ', '.join(install_jobs)))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "Windows unit tests before the install"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) claim="${line#FAIL }"
               fail "${claim%% :: *}" "${claim#* :: }" ;;
        *)     [[ -n "${line}" ]] && fail "the Windows unit tests check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "Windows unit tests before the install"
