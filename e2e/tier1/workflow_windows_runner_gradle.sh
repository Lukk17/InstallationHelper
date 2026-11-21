#!/usr/bin/env bash
#
# Tier 1: every workflow job that installs software with setup.ps1 first takes the runner's own Gradle and Java away.
#
# The windows-2025-vs2026 runner image installs Gradle with `Install-ChocoPackage gradle` and five Temurin
# JDKs into the hosted tool cache, with JAVA_HOME and JAVA_HOME_<version>_X64 pointing at them. So the
# Gradle-only Windows run 44334176847 printed `gradle v9.8.2 already installed.` and `Chocolatey installed
# 0/1 packages.`, and a Chocolatey install of Gradle by setup.ps1 was never proven, docs/regression_ledger.md
# 10.377. With a JDK of the image left, a Gradle-only run could not prove that the wizard brought Java in
# either.
#
# So, for every job in every workflow under .github/workflows that starts setup.ps1 for anything but
# -PrintPlan or -ListSoftware, found by e2e/lib/windows_wizard_jobs.py as workflow_windows_pester finds it,
# the job must run the local action .github/actions/remove-runner-gradle-java in a step before the first
# such wizard step, with no continue-on-error and no if on it. A wizard step whose every setup.ps1 line
# names -Software none and only -EnableKey keys that do not start with install_ installs no software, so it
# needs none. The action itself must be composite and, in code rather than in a comment, uninstall gradle
# with choco, name JAVA_HOME and GRADLE_HOME, ask Get-Command for gradle and for java and throw, with no
# step under continue-on-error.
#
# It fails when no job installs software with setup.ps1. Before it reads the repository it runs its
# readers against planted workflows and planted actions and requires them to name exactly the six planted
# workflow defects and none of the three sound jobs, and every planted action defect and nothing in the
# sound action, so a reader that went blind fails here instead of passing the real tree.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: every job that installs with setup.ps1 removes the runner's own Gradle and Java first"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "runner Gradle and Java removed"; }

require_python "every job that installs with setup.ps1 removes the runner's own Gradle and Java first" "runner Gradle and Java removed"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re
import sys

import yaml

sys.path.insert(0, 'e2e/lib')
from windows_wizard_jobs import SETUP_PS1, code_lines, local_uses, starts_wizard, steps_of

REMOVAL_USES = './.github/actions/remove-runner-gradle-java'
SOFTWARE_NONE = re.compile(r'(?<![\w-])-Software\s+none\b', re.IGNORECASE)
ENABLE_KEYS = re.compile(r'(?<![\w-])-EnableKey\s+([\w,]+)', re.IGNORECASE)
ACTION_NEEDS = (
    ('uninstalls gradle with choco', re.compile(r'\bchoco\s+uninstall\s+gradle\b')),
    ('names JAVA_HOME', re.compile(r'JAVA_HOME')),
    ('names GRADLE_HOME', re.compile(r'GRADLE_HOME')),
    ('asks Get-Command for gradle', re.compile(r'\bGet-Command\s+gradle\b')),
    ('asks Get-Command for java', re.compile(r'\bGet-Command\s+java\b')),
    ('throws', re.compile(r'^\s*throw\b')),
)


def is_true(value):
    return value is True or (isinstance(value, str) and value.strip().lower() == 'true')


def installs_no_app(step):
    """True for a wizard step whose every setup.ps1 line is -Software none with no install_ key enabled."""
    body = step.get('run')
    if not isinstance(body, str):
        return False
    wizard_lines = [line for line in code_lines(body) if SETUP_PS1.search(line)]
    if not wizard_lines:
        return False
    for line in wizard_lines:
        if not SOFTWARE_NONE.search(line):
            return False
        for keys in ENABLE_KEYS.findall(line):
            if any(key.startswith('install_') for key in keys.split(',')):
                return False
    return True


def job_problems(where, job, actions):
    """None for a job that installs no software with setup.ps1, otherwise the list of what is wrong."""
    steps = steps_of(job)
    installs = [i for i, step in enumerate(steps) if starts_wizard(step, actions) and not installs_no_app(step)]
    if not installs:
        return None
    first = installs[0]
    removals = [i for i, step in enumerate(steps) if local_uses(step) == REMOVAL_USES]
    if not removals:
        return ['%s installs with setup.ps1 at step %d and never runs %s' % (where, first + 1, REMOVAL_USES)]
    before = [i for i in removals if i < first]
    if not before:
        return ['%s runs %s at step %d, after setup.ps1 at step %d' % (where, REMOVAL_USES, removals[0] + 1, first + 1)]
    sound = [i for i in before if not is_true(steps[i].get('continue-on-error')) and steps[i].get('if') is None]
    if sound:
        return []
    step = steps[before[-1]]
    if is_true(step.get('continue-on-error')):
        return ['%s runs %s at step %d under continue-on-error, so a Gradle or a Java it could not remove '
                'does not stop the run' % (where, REMOVAL_USES, before[-1] + 1)]
    return ['%s runs %s at step %d under if: %s, so the removal can be skipped'
            % (where, REMOVAL_USES, before[-1] + 1, step.get('if'))]


def action_problems(where, action):
    """What is wrong with the removal action, an empty list when nothing is."""
    if not isinstance(action, dict):
        return ['%s is missing, so nothing removes the Gradle and the Java of the runner image' % where]
    runs = action.get('runs') or {}
    if runs.get('using') != 'composite':
        return ['%s is not a composite action' % where]
    problems = []
    code = []
    for index, step in enumerate(steps_of(runs)):
        if is_true(step.get('continue-on-error')):
            problems.append('%s runs step %d under continue-on-error' % (where, index + 1))
        if isinstance(step.get('run'), str):
            code.extend(code_lines(step['run']))
    for need, pattern in ACTION_NEEDS:
        if not any(pattern.search(line) for line in code):
            problems.append('%s never %s in its code' % (where, need))
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


SOUND_BODY = ("$ErrorActionPreference = 'Stop'\n"
              "# choco uninstall gradle in a comment does not count\n"
              "choco uninstall gradle --yes --no-progress\n"
              "$names = '^(JAVA_HOME(_\\w+)?|GRADLE_HOME)$'\n"
              "$gradle = Get-Command gradle -ErrorAction SilentlyContinue\n"
              "$java = Get-Command java -ErrorAction SilentlyContinue\n"
              "if ($gradle -or $java) {\n"
              "  throw 'still there'\n"
              "}\n")


def composite(body, **extra):
    return {'runs': {'using': 'composite', 'steps': [dict({'shell': 'pwsh', 'run': body}, **extra)]}}


def planted():
    wizard = {'shell': 'pwsh', 'run': '& ./setup/setup.ps1 -NonInteractive -AllowAdministrator -Software all'}
    picked = {'shell': 'pwsh', 'run': '& ./setup/setup.ps1 -NonInteractive -Software none -EnableKey install_gradle'}
    settings = {'shell': 'pwsh', 'run': '& ./setup/setup.ps1 -NonInteractive -Software none -EnableKey setup_wsl,enable_hyperv'}
    plan = {'shell': 'pwsh', 'run': '& ./setup/setup.ps1 -NonInteractive -PrintPlan'}
    removal = {'uses': REMOVAL_USES}
    hidden = {'uses': './.github/actions/hidden-wizard'}

    def one_job(*steps):
        return {'jobs': {'install': {'runs-on': 'windows-latest', 'steps': list(steps)}}}

    workflows = {
        'missing.yml': one_job(wizard),
        'after.yml': one_job(wizard, removal),
        'soft.yml': one_job(dict(removal, **{'continue-on-error': True}), wizard),
        'conditional.yml': one_job(dict(removal, **{'if': "runner.os == 'Windows'"}), wizard),
        'picked-gradle.yml': one_job(picked),
        'hidden.yml': one_job(hidden),
        'sound.yml': one_job(removal, wizard),
        'sound-settings.yml': one_job(settings),
        'sound-plan.yml': one_job(plan),
    }
    actions = {
        './.github/actions/hidden-wizard': {'runs': {'using': 'composite', 'steps': [dict(wizard)]}},
        REMOVAL_USES: composite(SOUND_BODY),
    }
    return workflows, actions


def planted_actions():
    return {
        'sound': composite(SOUND_BODY),
        'missing': None,
        'node': {'runs': {'using': 'node24', 'main': 'index.js'}},
        'comment-only': composite('\n'.join('# ' + line for line in SOUND_BODY.splitlines())),
        'no-java': composite(SOUND_BODY.replace('Get-Command java', 'Get-Item java')),
        'soft': composite(SOUND_BODY, **{'continue-on-error': True}),
    }


lines = []

expected = {'missing.yml', 'after.yml', 'soft.yml', 'conditional.yml', 'picked-gradle.yml', 'hidden.yml'}
_, planted_problems = analyse(*planted())
named = {label for label, _ in planted_problems}
if named == expected and len(planted_problems) == len(expected):
    lines.append('OK the job reader names exactly the six planted defects and none of the three sound jobs')
else:
    lines.append('FAIL the job reader misreads planted workflows, so nothing it says about the real ones can be '
                 'trusted :: expected one problem each in %s, got %s'
                 % (', '.join(sorted(expected)), ' | '.join(text for _, text in planted_problems) or 'none'))

misread = []
for label, action in sorted(planted_actions().items()):
    found = action_problems(label, action)
    if (label == 'sound') == bool(found):
        misread.append('%s: %s' % (label, '; '.join(found) or 'no problem'))
if misread:
    lines.append('FAIL the action reader misreads planted actions, so nothing it says about the real one can be '
                 'trusted :: %s' % ' | '.join(misread))
else:
    lines.append('OK the action reader finds a problem in each of the five planted actions and none in the sound one')

workflows = {}
for path in sorted(pathlib.Path('.github/workflows').glob('*.y*ml')):
    workflows[path.as_posix()] = yaml.safe_load(path.read_text(encoding='utf-8'))
actions = {}
for path in sorted(pathlib.Path('.github/actions').glob('*/action.y*ml')):
    actions['./' + path.parent.as_posix()] = yaml.safe_load(path.read_text(encoding='utf-8'))

found = action_problems(REMOVAL_USES, actions.get(REMOVAL_USES))
if found:
    lines.append('FAIL the action that removes the runner image\'s Gradle and Java does not do it :: %s'
                 % ' | '.join(found))
else:
    lines.append('OK %s uninstalls the Chocolatey gradle, clears JAVA_HOME and GRADLE_HOME and throws when '
                 'Get-Command still finds gradle or java' % REMOVAL_USES)

install_jobs, problems = analyse(workflows, actions)
if not install_jobs:
    lines.append('FAIL no workflow job installs software with setup.ps1, so this check proves nothing :: read '
                 '%d workflow(s)' % len(workflows))
elif problems:
    lines.append('FAIL a job installs with setup.ps1 while the runner image still holds its own Gradle and Java '
                 ':: %s' % ' | '.join(text for _, text in problems))
else:
    lines.append('OK all %d job(s) that install with setup.ps1 run %s before the wizard: %s'
                 % (len(install_jobs), REMOVAL_USES, ', '.join(install_jobs)))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "runner Gradle and Java removed"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) claim="${line#FAIL }"
               fail "${claim%% :: *}" "${claim#* :: }" ;;
        *)     [[ -n "${line}" ]] && fail "the runner Gradle and Java check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "runner Gradle and Java removed"
