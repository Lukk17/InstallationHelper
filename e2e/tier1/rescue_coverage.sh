#!/usr/bin/env bash
#
# Tier 1: a failure in one optional step costs that step, and the run still reports it and ends failed.
#
# A read-only audit on 2026-10-10 found the same shape in five places: one step that only some of the
# software needs had no rescue of its own, so its failure skipped everything after it.
#
#   site.yaml               systemd_boot sat among the core roles with no rescue, and the
#                           env_variables rescue re-raised, so either one stopped every later role
#   sdk_manager             NVM, SDKMAN, Pyenv, FVM and the Android SDK were five includes in a row,
#                           so one failure skipped the ones after it
#   ai_tools                the same, for every AI tool
#   custom_installs.yaml    each vendor download, on Linux and on macOS, ran inside the software
#   macos_install.yaml      installer block, so one that did not answer skipped every install after it
#
# Each is its own block with a rescue now, in the shape the paru fix in arch_core set: the rescue sets
# any_role_failed, which site.yaml turns into a failed run, and names the step with an [ERROR] line,
# which callback_plugins/dual_logger.py writes to ~/installation_errors.log. A rescue without the
# first is a failure turned into a pass, and setup/ansible/AGENTS.md forbids that. A rescue without the second is a
# failure nobody can find. So this asserts, mechanically:
#
#   1. in site.yaml, every role is imported inside a block of its own whose rescue sets
#      any_role_failed and does not fail the play, except the five core roles that are critical
#      bootstrap on purpose. The [ERROR] line is not required there, because most of those rescues
#      predate it and the failed task inside the role already reaches the error log as a failure;
#   2. in sdk_manager and ai_tools, every include or import is inside a block with such a rescue;
#   3. in custom_installs.yaml and macos_install.yaml, every download sits inside a block with such a
#      rescue, a get_url or a shell or command that runs curl;
#   4. the five SDK toggles agree in the three places that list them: the sdk_manager blocks, the
#      env_variables skip list in site.yaml and the SDK reason in verify_install.yaml;
#   5. in arch_core, every step that clones an AUR helper, builds it with makepkg or installs it with
#      `pacman -U` is inside a block with such a rescue, paru and yay alike.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: every optional step has a rescue that records and names its failure"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "rescue coverage"; }

require_python "every optional step has a rescue that records and names its failure" "rescue coverage"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re

import yaml

ANSIBLE = pathlib.Path('setup') / 'ansible'
SITE = ANSIBLE / 'site.yaml'
VERIFY = ANSIBLE / 'verify_install.yaml'
SDK = ANSIBLE / 'roles' / 'sdk_manager' / 'tasks' / 'main.yaml'
AI = ANSIBLE / 'roles' / 'ai_tools' / 'tasks' / 'main.yaml'
ARCH_CORE = ANSIBLE / 'roles' / 'arch_core' / 'tasks' / 'main.yaml'
DOWNLOAD_FILES = [ANSIBLE / 'roles' / 'software_installer' / 'tasks' / 'custom_installs.yaml',
                  ANSIBLE / 'roles' / 'software_installer' / 'tasks' / 'macos_install.yaml']
CRITICAL_CORE = {'macos_core', 'arch_core', 'fedora_core', 'debian_core', 'system_core'}
CONTAINERS = {'ansible.builtin.include_tasks', 'include_tasks', 'ansible.builtin.import_tasks',
              'import_tasks'}
SDK_TOGGLES_EXPECTED = 5

lines = []
counts = {'roles': 0, 'includes': 0, 'downloads': 0, 'aur_builds': 0}


def load(path):
    try:
        return yaml.safe_load(path.read_text(encoding='utf-8'))
    except (OSError, yaml.YAMLError, UnicodeDecodeError) as exc:
        lines.append('FAIL %s could not be read, so nothing in it was checked: %s' % (path.as_posix(), exc))
        return None


def as_text(value):
    if value is None:
        return ''
    if isinstance(value, str):
        return value
    return yaml.safe_dump(value, default_flow_style=True, width=100000)


def walk(tasks, ancestors=()):
    if not isinstance(tasks, list):
        return
    for task in tasks:
        if not isinstance(task, dict):
            continue
        yield task, ancestors
        for key in ('block', 'rescue', 'always'):
            if key in task:
                yield from walk(task[key], ancestors + ((task, key),))


def rescue_problem(block_task, require_error_line=True):
    """Why this block's rescue is not the approved shape, or None when it is."""
    rescue = block_task.get('rescue')
    if not rescue:
        return 'has no rescue, so its failure skips everything after it'
    text = as_text(rescue)
    modules = set()
    for task, _ in walk(rescue):
        modules |= set(task)
    if 'ansible.builtin.fail' in modules or 'fail' in modules:
        return 'has a rescue that fails the play again, so its failure still skips everything after it'
    if not re.search(r'any_role_failed:\s*true', text):
        return 'has a rescue that does not set any_role_failed, so the run ends green after a failure'
    if require_error_line and '[ERROR]' not in text:
        return ('has a rescue with no [ERROR] line, so the failure never reaches '
                '~/installation_errors.log')
    return None


def rescued_ancestor(ancestors):
    """The innermost enclosing block whose `block` section holds the task, or None."""
    for task, section in reversed(ancestors):
        if section == 'block':
            return task
    return None


# --- 1. site.yaml ---------------------------------------------------------------------------------
site = load(SITE)
if site:
    tasks = []
    for play in site:
        tasks += play.get('tasks') or []
    for task, ancestors in walk(tasks):
        role = task.get('ansible.builtin.import_role', task.get('import_role'))
        if not isinstance(role, dict):
            continue
        name = role.get('name')
        counts['roles'] += 1
        if name in CRITICAL_CORE:
            continue
        holder = rescued_ancestor(ancestors)
        if holder is None or len(holder.get('block') or []) != 1:
            lines.append('FAIL site.yaml imports %s outside a block of its own, so its failure is caught '
                         'only by the outer block and every role after it is skipped' % name)
            continue
        problem = rescue_problem(holder, require_error_line=False)
        if problem:
            lines.append('FAIL site.yaml role %s %s' % (name, problem))

# --- 2. sdk_manager and ai_tools ------------------------------------------------------------------
for path in (SDK, AI):
    doc = load(path)
    if not doc:
        continue
    for task, ancestors in walk(doc):
        if not any(key in task for key in CONTAINERS):
            continue
        counts['includes'] += 1
        holder = rescued_ancestor(ancestors)
        label = '%s :: %s' % (path.as_posix(), task.get('name', '<unnamed>'))
        if holder is None:
            lines.append('FAIL %s is not inside a block with a rescue of its own, so its failure skips '
                         'every tool after it' % label)
            continue
        problem = rescue_problem(holder)
        if problem:
            lines.append('FAIL %s sits in a block that %s' % (label, problem))

# --- 3. vendor downloads --------------------------------------------------------------------------
for path in DOWNLOAD_FILES:
    doc = load(path)
    if not doc:
        continue
    for task, ancestors in walk(doc):
        shell = task.get('ansible.builtin.shell', task.get('shell',
                task.get('ansible.builtin.command', task.get('command'))))
        is_download = ('ansible.builtin.get_url' in task or 'get_url' in task
                       or re.search(r'\bcurl\b', as_text(shell)) is not None)
        if not is_download:
            continue
        counts['downloads'] += 1
        label = '%s :: %s' % (path.as_posix(), task.get('name', '<unnamed>'))
        holder = rescued_ancestor(ancestors)
        if holder is None:
            lines.append('FAIL %s downloads outside a block, so a vendor that does not answer ends the '
                         'software installer and every install after it is skipped' % label)
            continue
        problem = rescue_problem(holder)
        if problem:
            lines.append('FAIL %s sits in a block that %s' % (label, problem))

# --- 5. AUR helper builds in arch_core ------------------------------------------------------------
# arch_core is critical bootstrap and site.yaml gives it no rescue, so a step inside it that reaches
# aur.archlinux.org or builds from there ends the play unless a block of its own rescues it. paru was
# rescued after it did that on a real CachyOS machine on 2026-10-10, and yay was left with the same
# failure mode the same day. Every git clone, makepkg and `pacman -U` in the file is held to it.
arch_doc = load(ARCH_CORE)
if arch_doc:
    for task, ancestors in walk(arch_doc):
        shell = as_text(task.get('ansible.builtin.shell', task.get('shell',
                        task.get('ansible.builtin.command', task.get('command')))))
        is_build_step = ('ansible.builtin.git' in task or 'git' in task
                         or re.search(r'\bmakepkg\b|\bpacman\s+-U\b', shell) is not None)
        if not is_build_step:
            continue
        counts['aur_builds'] += 1
        label = '%s :: %s' % (ARCH_CORE.as_posix(), task.get('name', '<unnamed>'))
        holder = rescued_ancestor(ancestors)
        if holder is None:
            lines.append('FAIL %s builds an AUR helper outside a block with a rescue, and arch_core has '
                         'no rescue in site.yaml, so its failure ends the play before anything is '
                         'installed' % label)
            continue
        problem = rescue_problem(holder)
        if problem:
            lines.append('FAIL %s sits in a block that %s' % (label, problem))

# --- 4. the SDK toggles agree ---------------------------------------------------------------------
sdk_doc = load(SDK) or []
sdk_toggles = set()
for task in sdk_doc:
    sdk_toggles |= set(re.findall(r'\binstall_[a-z_]+\b', as_text(task.get('when'))))
site_toggles = set()
for task, _ in walk([t for play in (site or []) for t in (play.get('tasks') or [])]):
    if 'env_variables failed' in as_text(task) and isinstance(task.get('loop'), list):
        site_toggles |= {item.get('toggle') for item in task['loop'] if isinstance(item, dict)}
verify_toggles = set()
verify = load(VERIFY) or []
for play in verify:
    for task, _ in walk(play.get('tasks') or []):
        set_fact = task.get('ansible.builtin.set_fact', task.get('set_fact'))
        if isinstance(set_fact, dict) and isinstance(set_fact.get('ih_sdk_toggles'), list):
            verify_toggles |= set(set_fact['ih_sdk_toggles'])
if len(sdk_toggles) != SDK_TOGGLES_EXPECTED:
    lines.append('FAIL %s gates %d SDK blocks on toggles, expected %d: %s'
                 % (SDK.as_posix(), len(sdk_toggles), SDK_TOGGLES_EXPECTED, ', '.join(sorted(sdk_toggles))))
for where, toggles in (('the env_variables skip list in site.yaml', site_toggles),
                       ('ih_sdk_toggles in verify_install.yaml', verify_toggles)):
    if toggles != sdk_toggles:
        lines.append('FAIL %s names %s while sdk_manager gates on %s, so an SDK skipped for '
                     'env_variables is not named, or is named for nothing'
                     % (where, ', '.join(sorted(toggles)) or 'nothing', ', '.join(sorted(sdk_toggles))))

for what, minimum in (('roles', 10), ('includes', 12), ('downloads', 8), ('aur_builds', 6)):
    if counts[what] < minimum:
        lines.append('FAIL only %d %s were found, fewer than the %d there are, so the parser lost them'
                     % (counts[what], what, minimum))

if not lines:
    lines.append('OK %d roles, %d SDK and AI tool includes, %d vendor downloads and %d AUR helper build '
                 'steps each fail inside a rescue that records and names the failure, and the %d SDK '
                 'toggles agree in all three places' % (counts['roles'], counts['includes'], counts['downloads'],
                                                        counts['aur_builds'], len(sdk_toggles)))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "rescue coverage"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "an optional step can still stop everything after it, or fail without a trace" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the rescue coverage check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "rescue coverage"
