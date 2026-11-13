#!/usr/bin/env bash
#
# Tier 1: a picked-apps run installs what was picked and leaves the rest of the machine alone.
#
# On 2026-11-13 the owner ran setup.sh --software none --enable install_kicad9 on his CachyOS machine.
# KiCad 9 was not installed, because the custom installs sat under the condition that a mapped
# package was requested, and the roles that run whatever is picked changed his machine instead:
# env_variables wrote ~/.config/environment.d/990-dev.conf, set mode 0755 on his home directory and
# wrote its zsh import into ~/.zshenv, outside the ~/.config/zsh layout, and the cleanup in site.yaml
# ran pacman -Sc and deleted /var/lib/snapd/cache. docs/regression_ledger.md 10.285, 10.287, 10.288
# and 10.289. So this asserts:
#
#   1. setup.sh resolves --software none --enable <key> into an ih_picked_apps line naming that key,
#      and names nothing for --software none alone, for a key enabled and disabled at once, and for
#      --software defaults with --enable. group_vars/all.yaml defaults ih_picked_apps to empty and
#      derives ih_picked_apps_run from it, and nothing else defines either.
#   2. every role site.yaml imports stays out of a picked-apps run unless the run picked it: its
#      conditions name ih_picked_apps_run, ih_env_variables_run or a key the wizard lets a user pick,
#      or every task in it does, or picked_apps_allowed.txt names it with the reason it is an install
#      step. A hidden setting such as setup_hibernate does not count as picked, because --software
#      none leaves it at its default.
#   3. every cache cleanup in the post_tasks of site.yaml reads ih_picked_apps_run, apart from the
#      tasks picked_apps_allowed.txt names.
#   4. both custom install includes of dynamic_install.yaml exist, sit in a block with a rescue, and
#      sit under no condition that reads software_installer_packages.
#   5. no file task sets a mode on non_root_home: none names it as its path, and none names a
#      variable that can be the home directory, zsh_config_dir for one, without a condition that
#      leaves the home directory out.
#   6. zsh_config_dir follows ih_zdotdir_stub, site.yaml sets that fact from ~/.zshenv in its
#      pre_tasks by the marker zdotdir_stub_marker names, and shell_zsh writes the stub under the
#      same marker, so a run with setup_zsh off still writes into ~/.config/zsh where an earlier run
#      set zsh up.
#   7. env_variables_dependent_toggles names every toggle sdk_manager installs an SDK for, every task
#      outside env_variables that writes the environment.d file is gated on a toggle it names, and
#      every task that writes it writes dev_env_file_in_use, the file the machine already uses.
#   8. a picked-apps run never runs the whole env_variables step and never its migrations, owner
#      decision 42: every task of env_unix.yaml carries not (ih_picked_apps_run | bool) as a
#      condition of its own, or picked_apps_allowed.txt names it as an env task. Such a task removes
#      nothing, writes its environment.d block only for a picked toggle and its shell import only
#      where that shell imports nothing yet, and dev_env_file_in_use picks 50-dev.conf in a
#      picked-apps run only where the pre_tasks of site.yaml found it. No lineinfile or file task with
#      state absent anywhere in the playbook is reachable in a picked-apps run, through its own
#      conditions, its block, the include of its file or the import of its role, unless
#      picked_apps_allowed.txt names it as a removal an install needs, docs/regression_ledger.md 10.326.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: a picked-apps run leaves the rest of the machine alone"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "picked apps scope"; }

SETUP_SH="${REPO_ROOT}/setup/setup.sh"
PICKED_KEY="install_kicad9"
OTHER_KEY="install_k3d"

# --- 1. setup.sh resolves the flags into ih_picked_apps ------------------------------------------
# The command is the last line --print-command prints. Each run is read-only: --print-command answers
# above every step that changes anything, as print_command_resolution.sh describes.
resolved_command() {
    local out rc=0
    out="$(bash "${SETUP_SH}" --print-command "$@" 2>&1 </dev/null)" || rc=$?
    if [[ ${rc} -ne 0 ]]; then
        printf 'EXIT %s %s\n' "${rc}" "$(tr '\n' ' ' <<<"${out}" | cut -c1-200)"
        return 0
    fi
    sed -n '$p' <<<"${out}"
}

# --print-command quotes the command with printf %q, so the comma between two keys prints as "\,".
picked_value() { grep -oE 'ih_picked_apps=([^ \\]|\\.)*' <<<"$1" | sed -n '1{s/^ih_picked_apps=//;s/\\\(.\)/\1/g;p}' || true; }

line="$(resolved_command --software none --enable "${PICKED_KEY},${OTHER_KEY}")"
value="$(picked_value "${line}")"
if [[ "${line}" != ansible-playbook* ]]; then
    fail "--software none --enable ${PICKED_KEY},${OTHER_KEY} did not resolve to a command" "${line}"
elif [[ "${value}" == "${PICKED_KEY},${OTHER_KEY}" || "${value}" == "${OTHER_KEY},${PICKED_KEY}" ]]; then
    pass "--software none --enable ${PICKED_KEY},${OTHER_KEY} resolves to ih_picked_apps=${value}"
else
    fail "--software none --enable ${PICKED_KEY},${OTHER_KEY} does not name both keys in ih_picked_apps" \
         "ih_picked_apps=[${value}] in: ${line}"
fi

for case_args in "--software none" "--software none --enable ${PICKED_KEY} --disable ${PICKED_KEY}" "--software defaults --enable ${PICKED_KEY}"; do
    IFS=' ' read -r -a args <<<"${case_args}"
    line="$(resolved_command "${args[@]}")"
    if [[ "${line}" != ansible-playbook* ]]; then
        fail "${case_args} did not resolve to a command" "${line}"
    elif grep -q 'ih_picked_apps=' <<<"${line}"; then
        fail "${case_args} is not a picked-apps run and still names ih_picked_apps" "${line}"
    else
        pass "${case_args} is not a picked-apps run and names no ih_picked_apps"
    fi
done

# --- 2 to 7, read from the YAML ------------------------------------------------------------------
require_python "a picked-apps run leaves the rest of the machine alone" "picked apps scope"

excluded_line="$(grep -m1 '^EXCLUDED_VARS=' "${SETUP_SH}" || true)"
de_keys_line="$(grep -m1 '^DE_KEYS=' "${SETUP_SH}" || true)"
if [[ -z "${excluded_line}" || -z "${de_keys_line}" ]]; then
    fail "setup.sh no longer defines EXCLUDED_VARS and DE_KEYS, so the keys a user can pick cannot be built" \
         "one of the two was not found in ${SETUP_SH}"
    finish "picked apps scope"
fi
eval "${excluded_line}"
eval "${de_keys_line}"
export PICKED_EXCLUDED="${EXCLUDED_VARS}"
PICKED_DE_KEYS="$(printf '%s ' "${DE_KEYS[@]}")"
export PICKED_DE_KEYS

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import os
import pathlib
import re

import yaml

ANSIBLE = pathlib.Path('setup') / 'ansible'
SITE = ANSIBLE / 'site.yaml'
GROUP_VARS = ANSIBLE / 'group_vars'
ROLES = ANSIBLE / 'roles'
DYNAMIC = ROLES / 'software_installer' / 'tasks' / 'dynamic_install.yaml'
ALLOWED = pathlib.Path('e2e') / 'tier1' / 'picked_apps_allowed.txt'
CUSTOM_INCLUDES = ('custom_installs.yaml', 'macos_install.yaml')
PICKED_VARS = ('ih_picked_apps_run', 'ih_env_variables_run')
SAFE_MODULES = {'set_fact', 'debug', 'assert', 'fail', 'include_vars', 'meta'}
TASK_KEYS = ('block', 'rescue', 'always')

lines = []


def load(path):
    return yaml.safe_load(path.read_text(encoding='utf-8')) or []


def module_of(task):
    for key in task:
        if key.startswith('ansible.builtin.') or key.startswith('community.') or key in (
                'import_tasks', 'include_tasks', 'import_role', 'include_role', 'file', 'command',
                'shell', 'set_fact', 'debug', 'assert', 'fail', 'include_vars', 'meta', 'copy'):
            return key.rsplit('.', 1)[-1]
    return None


def when_text(task):
    value = task.get('when')
    if value is None:
        return ''
    if isinstance(value, list):
        return ' and '.join(str(v) for v in value)
    return str(value)


def walk(tasks, chain=()):
    """Every task with the conditions of every block around it, blocks included."""
    for task in tasks or []:
        if not isinstance(task, dict):
            continue
        here = chain + (when_text(task),)
        yield task, here
        for key in TASK_KEYS:
            if key in task:
                yield from walk(task[key], here)


# --- the keys a user can pick --------------------------------------------------------------------
excluded = set(os.environ['PICKED_EXCLUDED'].split('|'))
selectable = set(os.environ['PICKED_DE_KEYS'].split())
for name in ('all.yaml', 'linux.yaml', 'macos.yaml'):
    for key, value in (load(GROUP_VARS / name) or {}).items():
        if isinstance(value, bool) and key not in excluded:
            selectable.add(key)
if len(selectable) < 20:
    lines.append('FAIL only %d keys a user can pick were read out of %s, so nothing below is proven'
                 % (len(selectable), GROUP_VARS.as_posix()))
selectable_re = re.compile(r'\b(%s)\b' % '|'.join(sorted(map(re.escape, selectable))))
picked_re = re.compile(r'\b(%s)\b' % '|'.join(PICKED_VARS))


def gated(text):
    return bool(picked_re.search(text) or selectable_re.search(text))


# --- the allowlist -------------------------------------------------------------------------------
allowed = {'role': {}, 'task': {}, 'env': {}, 'remove': {}}
for raw in ALLOWED.read_text(encoding='utf-8').splitlines():
    if not raw.strip() or raw.lstrip().startswith('#'):
        continue
    head, sep, reason = raw.partition('|')
    kind, _, name = head.strip().partition(' ')
    if not sep or not reason.strip() or kind not in allowed or not name.strip():
        lines.append('FAIL %s line is not "<role, task, env or remove> <name> | <reason>": %s' % (ALLOWED.as_posix(), raw))
        continue
    allowed[kind][name.strip()] = reason.strip()

# --- 1. one definition of each variable ---------------------------------------------------------
all_vars = load(GROUP_VARS / 'all.yaml')
if all_vars.get('ih_picked_apps', None) != '':
    lines.append('FAIL %s does not default ih_picked_apps to an empty string, so a run setup.sh did not '
                 'mark could count as a picked-apps run' % (GROUP_VARS / 'all.yaml').as_posix())
if 'ih_picked_apps' not in str(all_vars.get('ih_picked_apps_run', '')):
    lines.append('FAIL ih_picked_apps_run in %s is not derived from ih_picked_apps'
                 % (GROUP_VARS / 'all.yaml').as_posix())
definition_re = re.compile(r'^\s*-?\s*(ih_picked_apps_run|ih_env_variables_run|ih_picked_apps)\s*:', re.M)
for path in sorted(ANSIBLE.rglob('*.yaml')):
    if path == GROUP_VARS / 'all.yaml':
        continue
    for match in definition_re.finditer(path.read_text(encoding='utf-8')):
        lines.append('FAIL %s defines %s again, and the scope of a run must be decided in %s alone'
                     % (path.as_posix(), match.group(1), (GROUP_VARS / 'all.yaml').as_posix()))


# --- 2. every role in site.yaml -----------------------------------------------------------------
def role_tasks_gated(role, filename='main.yaml', seen=None):
    """True when every task the role runs, following its static imports, names a pick."""
    seen = seen or set()
    path = ROLES / role / 'tasks' / filename
    if path in seen or not path.exists():
        return path in seen
    seen.add(path)
    for task in load(path):
        if gated(when_text(task)) or module_of(task) in SAFE_MODULES:
            continue
        target = task.get('import_tasks') or task.get('ansible.builtin.import_tasks')
        if isinstance(target, str) and '{{' not in target:
            if role_tasks_gated(role, target, seen):
                continue
            return False
        if any(key in task for key in TASK_KEYS):
            if all(gated(' '.join(c)) or module_of(t) in SAFE_MODULES or any(k in t for k in TASK_KEYS)
                   for t, c in walk([task])):
                continue
        return False
    return True


site = load(SITE)[0]
roles_seen = []
for task, chain in walk(site.get('tasks')):
    imported = task.get('ansible.builtin.import_role') or task.get('import_role')
    if not isinstance(imported, dict):
        continue
    role = imported.get('name')
    roles_seen.append(role)
    if gated(' '.join(chain)) or role in allowed['role'] or role_tasks_gated(role):
        continue
    lines.append('FAIL role %s runs in a picked-apps run whatever was picked: nothing in its conditions in '
                 '%s, and not every task in it, names ih_picked_apps_run, ih_env_variables_run or a key a '
                 'user can pick, and %s does not name it as an install step'
                 % (role, SITE.as_posix(), ALLOWED.as_posix()))
for role in allowed['role']:
    if role not in roles_seen:
        lines.append('FAIL %s names role %s, which %s does not import' % (ALLOWED.as_posix(), role, SITE.as_posix()))
if len(roles_seen) < 10:
    lines.append('FAIL only %d roles were found in %s, so nothing about them is proven'
                 % (len(roles_seen), SITE.as_posix()))

# --- 3. the cleanup in post_tasks ---------------------------------------------------------------
cleanups = [t for t in site.get('post_tasks') or [] if t.get('name') == 'Clean up after the run']
cleanup_count = 0
if len(cleanups) != 1:
    lines.append('FAIL %s has %d "Clean up after the run" blocks in its post_tasks, expected one'
                 % (SITE.as_posix(), len(cleanups)))
else:
    for task, chain in walk(cleanups[0].get('block')):
        if any(key in task for key in TASK_KEYS):
            continue
        cleanup_count += 1
        name = task.get('name', '(unnamed)')
        if picked_re.search(' '.join(chain)) or name in allowed['task']:
            continue
        lines.append('FAIL "%s" in the cleanup of %s runs in a picked-apps run, and nothing around it '
                     'reads ih_picked_apps_run' % (name, SITE.as_posix()))
    if cleanup_count < 5:
        lines.append('FAIL only %d tasks were found in the cleanup of %s, so nothing about it is proven'
                     % (cleanup_count, SITE.as_posix()))

# --- 4. the custom install includes -------------------------------------------------------------
found = {name: [] for name in CUSTOM_INCLUDES}


def find_includes(tasks, ancestors=()):
    for task in tasks or []:
        if not isinstance(task, dict):
            continue
        target = task.get('ansible.builtin.include_tasks') or task.get('include_tasks')
        if isinstance(target, dict):
            target = target.get('file')
        if isinstance(target, str) and target in found:
            found[target].append(ancestors)
        for key in TASK_KEYS:
            if key in task:
                find_includes(task[key], ancestors + (task,))


find_includes(load(DYNAMIC))
for name, places in found.items():
    if len(places) != 1:
        lines.append('FAIL %s includes %s %d times, expected once' % (DYNAMIC.as_posix(), name, len(places)))
        continue
    ancestors = places[0]
    if any('software_installer_packages' in when_text(a) for a in ancestors):
        lines.append('FAIL the include of %s in %s sits under a condition on software_installer_packages, '
                     'which counts only mapped packages, so a run that picks a custom install alone skips '
                     'it, docs/regression_ledger.md 10.285' % (name, DYNAMIC.as_posix()))
    if not ancestors or not ancestors[-1].get('rescue'):
        lines.append('FAIL the include of %s in %s is not in a block with a rescue of its own'
                     % (name, DYNAMIC.as_posix()))

# --- 5. no mode on the home directory -----------------------------------------------------------
home_valued = {'non_root_home'}
for name in ('all.yaml', 'linux.yaml', 'macos.yaml'):
    for key, value in (load(GROUP_VARS / name) or {}).items():
        text = str(value)
        if re.search(r'non_root_home\s*}}\s*$', text) or re.search(r'\belse\s+non_root_home\b(?!\s*~)', text):
            home_valued.add(key)
home_path_re = re.compile(r'^\s*{{\s*(%s)\s*}}\s*/?\s*$' % '|'.join(sorted(home_valued)))
file_tasks = 0
task_files = [SITE, ANSIBLE / 'verify_install.yaml'] + sorted((ANSIBLE / 'tasks').glob('*.yaml')) \
    + sorted(ROLES.glob('*/tasks/*.yaml'))
for path in task_files:
    doc = load(path)
    plays = doc if path in (SITE, ANSIBLE / 'verify_install.yaml') else [{'tasks': doc}]
    for play in plays:
        for section in ('pre_tasks', 'tasks', 'post_tasks', 'handlers'):
            for task, chain in walk(play.get(section)):
                args = task.get('ansible.builtin.file') or task.get('file')
                if not isinstance(args, dict):
                    continue
                file_tasks += 1
                match = home_path_re.match(str(args.get('path', args.get('dest', ''))))
                if not match or 'mode' not in args:
                    continue
                variable = match.group(1)
                guard = re.compile(r'\b%s\s*!=\s*non_root_home\b' % re.escape(variable))
                if variable != 'non_root_home' and guard.search(' '.join(chain)):
                    continue
                lines.append('FAIL "%s" in %s sets mode %s on %s, which is or can be the home directory, '
                             'docs/regression_ledger.md 10.287'
                             % (task.get('name', '(unnamed)'), path.as_posix(), args['mode'], variable))
if file_tasks < 20:
    lines.append('FAIL only %d file tasks were read, so nothing about the home directory is proven' % file_tasks)

# --- 6. zsh_config_dir follows the stub ---------------------------------------------------------
if 'ih_zdotdir_stub' not in str(all_vars.get('zsh_config_dir', '')):
    lines.append('FAIL zsh_config_dir in %s does not read ih_zdotdir_stub, so a run with setup_zsh off writes '
                 'zsh files into the home directory where a ZDOTDIR stub sends zsh elsewhere, '
                 'docs/regression_ledger.md 10.288' % (GROUP_VARS / 'all.yaml').as_posix())
pre = site.get('pre_tasks') or []
lookups = [t for t, _ in walk(pre) if 'zdotdir_stub_marker' in str(t.get('ansible.builtin.command', ''))
           and '.zshenv' in str(t.get('ansible.builtin.command', ''))]
facts = [t for t, _ in walk(pre) if 'ih_zdotdir_stub' in (t.get('ansible.builtin.set_fact') or {})]
if len(lookups) != 1 or len(facts) != 1:
    lines.append('FAIL the pre_tasks of %s should ask ~/.zshenv for zdotdir_stub_marker once and set '
                 'ih_zdotdir_stub once, and do so %d and %d times' % (SITE.as_posix(), len(lookups), len(facts)))
stub_writers = [t for t, _ in walk(load(ROLES / 'shell_zsh' / 'tasks' / 'oh_my_zsh.yaml'))
                if 'ZDOTDIR' in str((t.get('ansible.builtin.blockinfile') or {}).get('block', ''))]
if len(stub_writers) != 1 or (stub_writers[0]['ansible.builtin.blockinfile'].get('marker')
                              != '{{ zdotdir_stub_marker }}'):
    lines.append('FAIL shell_zsh does not write the ~/.zshenv stub under {{ zdotdir_stub_marker }}, so the '
                 'stub site.yaml asks for and the stub shell_zsh writes can drift apart')

# --- 7. the apps that need env_variables ----------------------------------------------------------
dependents = set(all_vars.get('env_variables_dependent_toggles') or [])
sdk_toggles = set()
for task in load(ROLES / 'sdk_manager' / 'tasks' / 'main.yaml'):
    sdk_toggles.update(re.findall(r'\binstall_[a-z0-9_]+\b', when_text(task)))
if len(sdk_toggles) < 3:
    lines.append('FAIL only %d SDK toggles were read out of sdk_manager, so nothing about them is proven'
                 % len(sdk_toggles))
for toggle in sorted(sdk_toggles - dependents):
    lines.append('FAIL sdk_manager installs an SDK for %s, which env_variables_dependent_toggles does not '
                 'name, so a picked-apps run of it leaves out the env_variables it is put on PATH through'
                 % toggle)
site_role_conditions = {}
for task, chain in walk(site.get('tasks')):
    imported = task.get('ansible.builtin.import_role') or task.get('import_role')
    if isinstance(imported, dict):
        site_role_conditions[imported.get('name')] = ' '.join(chain)
writers = 0
for path in sorted(ROLES.glob('*/tasks/*.yaml')):
    role = path.parts[-3]
    for task, chain in walk(load(path)):
        args = task.get('ansible.builtin.blockinfile') or task.get('ansible.builtin.lineinfile') or {}
        if 'dev_env_file' not in str(args.get('path', '')):
            continue
        if not re.fullmatch(r'{{\s*dev_env_file_in_use\s*}}', str(args.get('path', '')).strip()):
            lines.append('FAIL "%s" in %s writes %s rather than {{ dev_env_file_in_use }}, so a picked-apps '
                         'run on a machine that keeps its environment in 50-dev.conf starts a second file '
                         'beside it' % (task.get('name', '(unnamed)'), path.as_posix(), args.get('path')))
        if role == 'env_variables':
            continue
        writers += 1
        named = set(re.findall(r'\binstall_[a-z0-9_]+\b', ' '.join(chain) + ' ' + site_role_conditions.get(role, '')))
        if role == 'sdk_manager':
            named |= sdk_toggles
        if not named & dependents:
            lines.append('FAIL "%s" in %s writes dev_env_file and is gated on no toggle '
                         'env_variables_dependent_toggles names, so a picked-apps run of it leaves out the '
                         'env_variables that makes every shell import that file'
                         % (task.get('name', '(unnamed)'), path.as_posix()))
if writers < 4:
    lines.append('FAIL only %d tasks outside env_variables were found writing dev_env_file, so nothing about '
                 'them is proven' % writers)

# --- 8. env_variables in a picked-apps run --------------------------------------------------------
ENV_UNIX = ROLES / 'env_variables' / 'tasks' / 'env_unix.yaml'
picked_out_re = re.compile(r'^\s*not\s*\(\s*ih_picked_apps_run\s*\|\s*bool\s*\)\s*$')
dependent_re = re.compile(r"'(%s)'\s+in\s+ih_picked_toggles\b" % '|'.join(sorted(map(re.escape, dependents)) or ['-']))
SHELL_MODULES = ('blockinfile', 'lineinfile')


def conditions(task):
    value = task.get('when')
    return [str(v) for v in value] if isinstance(value, list) else ([] if value is None else [str(value)])


env_tasks = [t for t, _ in walk(load(ENV_UNIX)) if not any(k in t for k in TASK_KEYS)]
env_names = {t.get('name') for t in env_tasks}
env_allowed = 0
for task in env_tasks:
    name = task.get('name', '(unnamed)')
    if any(picked_out_re.match(c) for c in conditions(task)):
        continue
    if name not in allowed['env']:
        lines.append('FAIL "%s" in %s runs in a picked-apps run, and %s does not name it as an env task a '
                     'picked app needs, owner decision 42' % (name, ENV_UNIX.as_posix(), ALLOWED.as_posix()))
        continue
    env_allowed += 1
    module = module_of(task)
    args = task.get('ansible.builtin.' + module) if module else None
    args = args if isinstance(args, dict) else {}
    when = ' and '.join(conditions(task))
    if args.get('state') == 'absent':
        lines.append('FAIL "%s" in %s removes something in a picked-apps run, and a picked-apps run never '
                     'migrates, owner decision 42' % (name, ENV_UNIX.as_posix()))
    if module in SHELL_MODULES and 'dev_env_file' in str(args.get('path', '')) and not dependent_re.search(when):
        lines.append('FAIL "%s" in %s writes the environment.d file in a picked-apps run whatever was picked: '
                     'its condition names no toggle of env_variables_dependent_toggles in ih_picked_toggles'
                     % (name, ENV_UNIX.as_posix()))
    if module in SHELL_MODULES and 'dev_env_file' not in str(args.get('path', '')) \
            and 'env_variables_imported_by' not in when:
        lines.append('FAIL "%s" in %s writes %s in a picked-apps run without asking env_variables_imported_by '
                     'whether that shell imports environment.d already' % (name, ENV_UNIX.as_posix(), args.get('path')))
for name in allowed['env']:
    if name not in env_names:
        lines.append('FAIL %s names env task "%s", which %s does not have' % (ALLOWED.as_posix(), name, ENV_UNIX.as_posix()))
if len(env_tasks) < 10:
    lines.append('FAIL only %d tasks were read out of %s, so nothing about it is proven' % (len(env_tasks), ENV_UNIX.as_posix()))
in_use = str(all_vars.get('dev_env_file_in_use', ''))
if not all(word in in_use for word in ('dev_env_file_retired', 'ih_picked_apps_run', 'ih_dev_env_file_retired_present')):
    lines.append('FAIL dev_env_file_in_use in %s does not choose 50-dev.conf by ih_picked_apps_run and '
                 'ih_dev_env_file_retired_present, so a picked-apps run cannot write into the file the machine '
                 'already uses' % (GROUP_VARS / 'all.yaml').as_posix())
retired_facts = [t for t, _ in walk(pre) if 'ih_dev_env_file_retired_present' in (t.get('ansible.builtin.set_fact') or {})]
if len(retired_facts) != 1:
    lines.append('FAIL the pre_tasks of %s set ih_dev_env_file_retired_present %d times, expected once'
                 % (SITE.as_posix(), len(retired_facts)))


# Every removal of a line or a file that a picked-apps run can reach, in any role or task file.
def picked_out(*texts):
    return any(picked_out_re.match(piece) for text in texts for piece in re.split(r'\s+and\s+', text))


def include_target(task):
    for key in ('ansible.builtin.include_tasks', 'include_tasks', 'ansible.builtin.import_tasks', 'import_tasks'):
        value = task.get(key)
        value = value.get('file') if isinstance(value, dict) else value
        if isinstance(value, str) and '{{' not in value.replace('{{ playbook_dir }}/', ''):
            return value.replace('{{ playbook_dir }}/', '')
    return None


removal_files = [SITE] + sorted((ANSIBLE / 'tasks').glob('*.yaml')) + sorted(ROLES.glob('*/tasks/*.yaml'))
file_tasks_of = {}
for path in removal_files:
    doc = load(path)
    plays = doc if path == SITE else [{'tasks': doc}]
    file_tasks_of[path] = [(t, c) for play in plays for section in ('pre_tasks', 'tasks', 'post_tasks')
                           for t, c in walk(play.get(section))]
includers = {}
for path, found in file_tasks_of.items():
    for task, chain in found:
        target = include_target(task)
        if target is None:
            continue
        resolved = ANSIBLE / target if target.startswith('tasks/') else path.parent / target
        includers.setdefault(resolved, []).append((path, chain))
guarded = {}
for role, condition in site_role_conditions.items():
    if picked_out(condition):
        guarded[ROLES / role / 'tasks' / 'main.yaml'] = True
for _ in range(10):
    for path in removal_files:
        if path not in guarded and includers.get(path) and all(
                picked_out(*chain) or guarded.get(source, False) for source, chain in includers[path]):
            guarded[path] = True
removals = []
for path, found in file_tasks_of.items():
    for task, chain in found:
        module = module_of(task)
        args = (task.get('ansible.builtin.' + module) or task.get(module)) if module in ('lineinfile', 'file') else None
        if not isinstance(args, dict) or args.get('state') != 'absent':
            continue
        removals.append(task.get('name', '(unnamed)'))
        if picked_out(*chain) or guarded.get(path, False) or task.get('name') in allowed['remove']:
            continue
        lines.append('FAIL "%s" in %s removes a line or a file in a picked-apps run, and nothing around it reads '
                     'not (ih_picked_apps_run | bool) and %s does not name it as a removal an install needs'
                     % (task.get('name', '(unnamed)'), path.as_posix(), ALLOWED.as_posix()))
for name in allowed['remove']:
    if name not in removals:
        lines.append('FAIL %s names removal "%s", which no lineinfile or file task with state absent carries'
                     % (ALLOWED.as_posix(), name))
if len(removals) < 15:
    lines.append('FAIL only %d removals were read, so nothing about them is proven' % len(removals))

if not lines:
    lines.append('OK %d roles, %d cleanup tasks, both custom install includes, %d file tasks, %d tasks that '
                 'write the environment.d file and %d tasks of env_variables keep a picked-apps run to what it '
                 'picked, %d of them named as env tasks, none of the %d removals of a line or a file reaches a '
                 'picked-apps run unless the allowed list names it, and %d keys a user can pick were read'
                 % (len(roles_seen), cleanup_count, file_tasks, writers, len(env_tasks), env_allowed, len(removals), len(selectable)))
print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "picked apps scope"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a picked-apps run reaches beyond what it picked" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the picked apps check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "picked apps scope"
