"""Which workflow steps start setup.ps1 to install, read one way by every check that asks.

Used by e2e/tier1/workflow_windows_pester.sh, e2e/tier1/workflow_windows_backup_artefact.sh and
e2e/tier1/workflow_windows_runner_gradle.sh, which import it from e2e/lib with the repository root as the
working directory.
"""
import re

SHARED_USES = './.github/actions/windows-pester'
SETUP_PS1 = re.compile(r'setup[/\\]setup\.ps1')
PLAN_ONLY = re.compile(r'(?<![\w-])-(PrintPlan|ListSoftware)\b', re.IGNORECASE)


def code_lines(body):
    """The lines of a run body that are not comments."""
    return [line for line in body.splitlines() if not line.strip().startswith('#')]


def steps_of(container):
    """The steps of a job or of a composite action's runs block, dictionaries only."""
    return [step for step in ((container or {}).get('steps') or []) if isinstance(step, dict)]


def local_uses(step):
    """The path of the local action a step uses, or None."""
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
