#!/usr/bin/env bash
#
# Tier 1: an app's environment variable is written only when that app's toggle is on, by the step
# that installs it, and a full run replaces the old combined block, owner decision 49.
#
# Until 2026-11-14 env_variables wrote GRADLE_USER_HOME, DOCKER_CONFIG, M2_HOME and KUBECONFIG in one
# block, ANSIBLE DEV APPS CONFIG, and the Android SDK and Flutter blocks, into
# ~/.config/environment.d/990-dev.conf in every full run, whatever the toggles said, and
# Set-WindowsDevEnvironment did the same on Windows. docs/regression_ledger.md, the section for this
# change. So this asserts, from the tree and from runs of the shipped tasks:
#
#   1. env_variables writes PROJECTS_DIR into the environment file and no other variable, and the
#      Windows table of Get-WindowsDevEnvironmentEntry shares PROJECTS_DIR and no other variable.
#   2. every other task that writes the environment file is gated, by its own condition, the include
#      of its file or the import of its role in site.yaml, on at least one install_ toggle, and only
#      on toggles env_variables_dependent_toggles names, so a picked-apps run of it imports the file.
#   3. no variable other than PATH is written by two tasks.
#   4. every variable of the Windows table is written on Linux and macOS under the same owning
#      toggles, and every variable the desktop session check of verify_install.yaml asks for is asked
#      under the toggles that write it, so the three cannot drift apart, defect class 2. A variable
#      whose app comes from a third-party repository is left out, by the step that writes it and by
#      the verification alike, when unavailable_repositories names that repository.
#   5. the environment file tasks of env_unix.yaml, run with ansible-playbook against a fixture file
#      holding the old ANSIBLE DEV APPS CONFIG block: a full run leaves no such block, none of its
#      four app variables and exactly one PROJECTS_DIR, keeps another tool's block as it was, and a
#      second full run changes nothing. A picked-apps run leaves the file exactly as it was.
#   6. roles/software_installer/tasks/app_environment.yaml, run once per owning toggle with only that
#      toggle on, writes exactly the variables the Windows table gives that toggle, each once, writes
#      nothing with every toggle off, writes only the variables of the apps still installed with
#      every toggle on and every repository it reads unavailable, and a second run with every toggle
#      on changes nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd ansible-playbook
require_python "an app's environment variable is written only when its toggle is on" "app env owners"

info "Tier 1: an app's environment variable is written only when its toggle is on, by the step that installs it"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

report_status=0
report="$("${PYTHON}" - "${REPO_ROOT}" "${work}" <<'PYEOF'
import json
import os
import pathlib
import re
import subprocess
import sys

import yaml

REPO = pathlib.Path(sys.argv[1])
WORK = pathlib.Path(sys.argv[2])
ANSIBLE = REPO / 'setup' / 'ansible'
ROLES = ANSIBLE / 'roles'
SITE = ANSIBLE / 'site.yaml'
GROUP_ALL = ANSIBLE / 'group_vars' / 'all.yaml'
VERIFY = ANSIBLE / 'verify_install.yaml'
ENV_UNIX = ROLES / 'env_variables' / 'tasks' / 'env_unix.yaml'
APP_ENV = ROLES / 'software_installer' / 'tasks' / 'app_environment.yaml'
WINDOWS = REPO / 'setup' / 'windows' / 'WindowsCustomInstalls.ps1'
MACHINE_VARIABLES = {'PROJECTS_DIR'}
RETIRED_MARKER = 'ANSIBLE DEV APPS CONFIG'
RETIRED_APP_VARIABLES = ('GRADLE_USER_HOME', 'DOCKER_CONFIG', 'M2_HOME', 'KUBECONFIG')
TASK_KEYS = ('block', 'rescue', 'always')
WRITERS = ('blockinfile', 'lineinfile')
INCLUDES = ('include_tasks', 'import_tasks')
TOGGLE = re.compile(r'\binstall_[a-z0-9_]+\b')
REPOSITORY_GUARD = re.compile(r"'([a-z0-9_]+)' not in unavailable_repositories")
ASSIGNMENT = re.compile(r'^\s*([A-Z][A-Z0-9_]*)=', re.M)
lines = []


def load(path):
    return yaml.safe_load(path.read_text(encoding='utf-8')) or []


def when_text(task):
    value = task.get('when')
    if value is None:
        return ''
    return ' and '.join(str(v) for v in value) if isinstance(value, list) else str(value)


def walk(tasks, chain=()):
    for task in tasks or []:
        if not isinstance(task, dict):
            continue
        here = chain + (when_text(task),)
        yield task, here
        for key in TASK_KEYS:
            if key in task:
                yield from walk(task[key], here)


def module_args(task, names):
    for name in names:
        for key in ('ansible.builtin.' + name, name):
            if key in task:
                return name, task[key]
    return None, None


def include_target(task):
    _, value = module_args(task, INCLUDES)
    value = value.get('file') if isinstance(value, dict) else value
    return value if isinstance(value, str) and '{{' not in value else None


# --- the tree --------------------------------------------------------------------------------------
dependents = set(load(GROUP_ALL).get('env_variables_dependent_toggles') or [])
site_conditions = {}
for task, chain in walk(load(SITE)[0].get('tasks')):
    imported = task.get('ansible.builtin.import_role') or task.get('import_role')
    if isinstance(imported, dict):
        site_conditions[imported.get('name')] = ' and '.join(c for c in chain if c)
role_files = {role.name: {p.name: load(p) for p in sorted((role / 'tasks').glob('*.yaml'))}
              for role in sorted(ROLES.iterdir()) if (role / 'tasks').is_dir()}


def gate_paths(role, name, seen=frozenset()):
    """One condition string per way the playbook reaches roles/<role>/tasks/<name>."""
    if name == 'main.yaml':
        return [site_conditions.get(role, '')] if role in site_conditions else []
    found = []
    for other, tasks in role_files[role].items():
        for task, chain in walk(tasks):
            if include_target(task) == name and (other, name) not in seen:
                for upstream in gate_paths(role, other, seen | {(other, name)}):
                    found.append(' and '.join(c for c in chain + (upstream,) if c))
    return found


writers = []
for role, files in role_files.items():
    for name, tasks in files.items():
        for task, chain in walk(tasks):
            module, args = module_args(task, WRITERS)
            if not isinstance(args, dict) or 'dev_env_file' not in str(args.get('path', '')) \
                    or args.get('state') == 'absent':
                continue
            text = str(args.get('block', args.get('line', '')))
            variables = set(ASSIGNMENT.findall(text))
            paths = [' and '.join(c for c in chain if c) + ' and ' + p for p in gate_paths(role, name)]
            writers.append({'role': role, 'file': name, 'task': task.get('name', '(unnamed)'),
                            'variables': variables, 'paths': paths,
                            'toggles': set(TOGGLE.findall(' '.join(paths))),
                            'guards': set(REPOSITORY_GUARD.findall(' '.join(paths)))})
if len(writers) < 8:
    lines.append('FAIL only %d tasks were found writing the environment file, so nothing about them is proven'
                 % len(writers))

# --- the Windows table -----------------------------------------------------------------------------
windows_text = WINDOWS.read_text(encoding='utf-8')
start = windows_text.find('function Get-WindowsDevEnvironmentEntry')
end = windows_text.find('\nfunction ', start + 1)
function = windows_text[start:end] if start >= 0 else ''
arrays = {m.group(1): TOGGLE.findall(m.group(2)) for m in re.finditer(r'\$(\w+)\s*=\s*@\(([^)]*)\)', function)}
windows = {}
for match in re.finditer(r"^\s*&\s*\$entry\s+'Variable'\s+'(\w+)'.*?\s(''|'[a-z0-9_]+'|\$\w+)\s*$", function, re.M):
    name, owner = match.groups()
    windows[name] = set(arrays.get(owner[1:], [])) if owner.startswith('$') else set(TOGGLE.findall(owner))
if len(windows) < 8:
    lines.append('FAIL only %d variables were read out of Get-WindowsDevEnvironmentEntry in %s, so nothing about '
                 'the Windows table is proven' % (len(windows), WINDOWS.relative_to(REPO).as_posix()))

# --- 1. what env_variables writes ----------------------------------------------------------------
machine = set().union(*[w['variables'] for w in writers if w['role'] == 'env_variables']) - {'PATH'}
excess = sorted(machine - MACHINE_VARIABLES) + (['PATH'] if any(
    'PATH' in w['variables'] for w in writers if w['role'] == 'env_variables') else [])
if excess:
    lines.append('FAIL env_variables writes %s into the environment file in every full run, whether or not the app '
                 'that reads it is installed. Only %s belongs to the installer, owner decision 49'
                 % (', '.join(excess), ', '.join(sorted(MACHINE_VARIABLES))))
elif machine != MACHINE_VARIABLES:
    lines.append('FAIL env_variables no longer writes %s' % ', '.join(sorted(MACHINE_VARIABLES - machine)))
else:
    lines.append('OK env_variables writes %s and no app variable' % ', '.join(sorted(machine)))
shared = {name for name, owners in windows.items() if not owners}
if shared != MACHINE_VARIABLES:
    lines.append('FAIL Get-WindowsDevEnvironmentEntry shares %s, which a full run writes whatever the toggles say, '
                 'and only %s belongs to no app, owner decision 49'
                 % (', '.join(sorted(shared)) or 'nothing', ', '.join(sorted(MACHINE_VARIABLES))))
else:
    lines.append('OK Get-WindowsDevEnvironmentEntry shares %s and gives every other variable an owner'
                 % ', '.join(sorted(shared)))

# --- 2 and 3. every other writer is gated, and no variable is written twice ------------------------
owners = {}
guards = {}
writer_of = {}
before_writer_checks = len(lines)
for writer in writers:
    label = '"%s" in roles/%s/tasks/%s' % (writer['task'], writer['role'], writer['file'])
    for name in writer['variables'] - {'PATH'}:
        writer_of.setdefault(name, []).append(label)
    if writer['role'] == 'env_variables':
        continue
    if not writer['paths']:
        lines.append('FAIL %s is reached by no include or role import this check can follow' % label)
        continue
    ungated = [p for p in writer['paths'] if not TOGGLE.search(p)]
    undependent = [p for p in writer['paths'] if TOGGLE.search(p) and not set(TOGGLE.findall(p)) & dependents]
    if ungated:
        lines.append('FAIL %s writes %s whatever the toggles say: no condition on the way to it names an install_ '
                     'toggle' % (label, ', '.join(sorted(writer['variables'])) or 'the environment file'))
    elif undependent:
        lines.append('FAIL %s is gated only on %s, which env_variables_dependent_toggles does not name, so a '
                     'picked-apps run of it leaves out the shell import that reads the file'
                     % (label, ', '.join(sorted(writer['toggles']))))
    for name in writer['variables'] - {'PATH'}:
        owners.setdefault(name, set()).update(writer['toggles'])
        guards.setdefault(name, set()).update(writer['guards'])
    stray = sorted(k for k in writer['guards'] if 'install_' + k not in writer['toggles'])
    if stray:
        lines.append('FAIL %s reads unavailable_repositories for %s, whose install_ toggle it is not gated on'
                     % (label, ', '.join(stray)))
for name, labels in sorted(writer_of.items()):
    if len(labels) > 1:
        lines.append('FAIL %s is written by %d tasks, %s, so the file carries it twice'
                     % (name, len(labels), ' and '.join(labels)))
gated = [w for w in writers if w['role'] != 'env_variables']
if gated and not any(l.startswith('FAIL') for l in lines[before_writer_checks:]):
    lines.append('OK %d tasks outside env_variables write the environment file, each gated on its own toggle'
                 % len(gated))

# --- 4. one set of owners on Linux, macOS, Windows and in the verification ------------------------
before_owner_checks = len(lines)
for name, windows_owners in sorted(windows.items()):
    if not windows_owners:
        continue
    if owners.get(name) != windows_owners:
        lines.append('FAIL %s belongs to %s on Windows and to %s on Linux and macOS, so one side writes it for an '
                     'app the other does not' % (name, ', '.join(sorted(windows_owners)),
                                                 ', '.join(sorted(owners.get(name, set()))) or 'no toggle'))
verify_text = VERIFY.read_text(encoding='utf-8')
session = re.search(r'ih_session_env_vars:\s*>-\s*\n(.*?)\n\s*ih_session_path_entries:', verify_text, re.S)
asked = {}
asked_guards = {}
for match in re.finditer(r"\(\[('[^\]]+)\]\s*if\s*\((.*?)\)\s*else\s*\[\]\)", session.group(1) if session else '', re.S):
    for name in re.findall(r"'([A-Z][A-Z0-9_]*)'", match.group(1)):
        asked[name] = set(TOGGLE.findall(match.group(2)))
        asked_guards[name] = set(REPOSITORY_GUARD.findall(match.group(2)))
if len(asked) < 8:
    lines.append('FAIL only %d variables were read out of ih_session_env_vars in %s, so the desktop session check is '
                 'not proven to ask under the right toggles' % (len(asked), VERIFY.relative_to(ANSIBLE).as_posix()))
for name, toggles in sorted(asked.items()):
    if owners.get(name) != toggles:
        lines.append('FAIL %s asks the desktop session for %s under %s, and it is written under %s'
                     % (VERIFY.relative_to(ANSIBLE).as_posix(), name, ', '.join(sorted(toggles)) or 'no toggle',
                        ', '.join(sorted(owners.get(name, set()))) or 'no toggle'))
if not any(l.startswith('FAIL') for l in lines[before_owner_checks:]):
    lines.append('OK %d Windows variables and %d variables the verification asks for agree with the toggles that '
                 'write them' % (len(windows), len(asked)))
guarded = {n: g for n, g in guards.items() if g}
guard_mismatches = 0
for name in sorted(set(asked) | set(guarded)):
    if guards.get(name, set()) != asked_guards.get(name, set()):
        lines.append('FAIL %s asks the desktop session for %s unless unavailable_repositories names %s, and it is '
                     'written unless it names %s, so a run whose repository could not be added fails or passes '
                     'wrongly' % (VERIFY.relative_to(ANSIBLE).as_posix(), name,
                                  ', '.join(sorted(asked_guards.get(name, set()))) or 'nothing',
                                  ', '.join(sorted(guards.get(name, set()))) or 'nothing'))
        guard_mismatches += 1
if guarded and not guard_mismatches:
    lines.append('OK %s are left out when the repository of their app could not be added, read the same way by '
                 'the step that writes them and by the verification' % ', '.join(sorted(guarded)))


# --- 5 and 6. runs of the shipped tasks ------------------------------------------------------------
def strip_become(node):
    if isinstance(node, dict):
        return {k: strip_become(v) for k, v in node.items() if k not in ('become', 'become_user')}
    if isinstance(node, list):
        return [strip_become(v) for v in node]
    return node


def run(tasks, extra, label):
    (WORK / 'tasks.yaml').write_text(yaml.safe_dump(strip_become(tasks), sort_keys=False), encoding='utf-8')
    (WORK / 'extra.json').write_text(json.dumps(extra), encoding='utf-8')
    (WORK / 'play.yaml').write_text(yaml.safe_dump([{
        'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
        'tasks': [{'name': label, 'ansible.builtin.include_tasks': str(WORK / 'tasks.yaml')}],
    }], sort_keys=False), encoding='utf-8')
    env = dict(os.environ, ANSIBLE_STDOUT_CALLBACK='default', ANSIBLE_NOCOLOR='1', ANSIBLE_FORCE_COLOR='0',
               ANSIBLE_LOCALHOST_WARNING='false', ANSIBLE_RETRY_FILES_ENABLED='false')
    done = subprocess.run(['ansible-playbook', '-i', 'localhost,', str(WORK / 'play.yaml'),
                           '-e', '@' + str(WORK / 'extra.json')],
                          cwd=WORK, env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True)
    if done.returncode != 0:
        lines.append('FAIL %s failed: %s' % (label, ' '.join(
            l.strip() for l in (done.stdout + done.stderr).splitlines()
            if l.startswith(('fatal', 'failed', 'ERROR')))[:600]))
    return done.returncode == 0


def read(path):
    return path.read_text(encoding='utf-8') if path.is_file() else None


def assigned(text, name):
    return len(re.findall(r'^%s=' % re.escape(name), text or '', re.M))


group_all = load(GROUP_ALL)
base = {'non_root_user': os.environ.get('USER', 'root'), 'projects_dir': '/home/someone/Projects',
        'android_home': '/home/someone/Android/Sdk', 'ih_picked_toggles': []}
if group_all.get('projects_dir_env_marker'):
    base['projects_dir_env_marker'] = group_all['projects_dir_env_marker']
other_block = '# BEGIN ANSIBLE SDKMAN ENVIRONMENT\nSDKMAN_DIR=${HOME}/.sdkman\n# END ANSIBLE SDKMAN ENVIRONMENT\n'
retired_block = ('# BEGIN %s\nGRADLE_USER_HOME=${HOME}/apps_config/.gradle\nDOCKER_CONFIG=${HOME}/apps_config/.docker\n'
                 'M2_HOME=${HOME}/apps_config/.m2\nKUBECONFIG=${HOME}/apps_config/.kube/config\n'
                 '# Where source checkouts live\nPROJECTS_DIR="/home/someone/Old"\n# END %s\n'
                 % (RETIRED_MARKER, RETIRED_MARKER))
runs = 0

env_tasks = [t for t in load(ENV_UNIX) if isinstance(t, dict)
             and 'dev_env_file' in str((module_args(t, WRITERS)[1] or {}).get('path', ''))]
if not env_tasks:
    lines.append('FAIL %s has no task that writes the environment file, so the migration cannot be run'
                 % ENV_UNIX.relative_to(ANSIBLE).as_posix())
for picked in (False, True):
    kind = 'picked-apps' if picked else 'full'
    home = WORK / ('env-%s' % kind)
    home.mkdir()
    env_file = home / '990-dev.conf'
    fixture = other_block + retired_block
    env_file.write_text(fixture, encoding='utf-8')
    extra = dict(base, non_root_home=str(home), dev_env_file_in_use=str(env_file), ih_picked_apps_run=picked,
                 ih_picked_toggles=['install_android_sdk', 'install_flutter', 'install_docker'] if picked else [])
    if not env_tasks or not run(env_tasks, extra, 'a %s run of the env_unix.yaml tasks' % kind):
        continue
    runs += 1
    text = read(env_file)
    if picked:
        if text != fixture:
            lines.append('FAIL a picked-apps run of the env_unix.yaml tasks changed the environment file, and such a '
                         'run never migrates and writes no block of an app, owner decisions 42 and 49')
        else:
            lines.append('OK a picked-apps run of the env_unix.yaml tasks left the environment file as it was')
        continue
    left = [n for n in RETIRED_APP_VARIABLES if assigned(text, n)] + \
           [n for n in ('ANDROID_HOME', 'PUB_CACHE') if assigned(text, n)]
    if RETIRED_MARKER in text:
        lines.append('FAIL a full run left the old %s block in the environment file' % RETIRED_MARKER)
    if left:
        lines.append('FAIL a full run of the env_unix.yaml tasks leaves %s in the environment file, with no app '
                     'installed' % ', '.join(left))
    if assigned(text, 'PROJECTS_DIR') != 1 or 'PROJECTS_DIR="%s"' % base['projects_dir'] not in text:
        lines.append('FAIL a full run left %d PROJECTS_DIR lines, expected exactly one naming %s'
                     % (assigned(text, 'PROJECTS_DIR'), base['projects_dir']))
    if other_block not in text:
        lines.append('FAIL a full run of the env_unix.yaml tasks changed the SDKMAN block beside the old one')
    if RETIRED_MARKER not in text and not left and assigned(text, 'PROJECTS_DIR') == 1 and other_block in text:
        lines.append('OK a full run replaced the old %s block with one PROJECTS_DIR and kept the SDKMAN block'
                     % RETIRED_MARKER)
    if run(env_tasks, extra, 'a second full run of the env_unix.yaml tasks'):
        runs += 1
        if read(env_file) != text:
            lines.append('FAIL a second full run of the env_unix.yaml tasks changed the environment file again')
        else:
            lines.append('OK a second full run of the env_unix.yaml tasks changed nothing')

app_tasks = load(APP_ENV) if APP_ENV.is_file() else []
if not app_tasks:
    lines.append('FAIL %s is missing or empty, so nothing writes GRADLE_USER_HOME, DOCKER_CONFIG, M2_HOME or '
                 'KUBECONFIG for the app that installs it' % APP_ENV.relative_to(ANSIBLE).as_posix())
app_variables = {n: o for n, o in windows.items() if n in RETIRED_APP_VARIABLES}
app_toggles = sorted(set().union(*app_variables.values()) if app_variables else set())
off = {t: False for t in app_toggles}
cases = [('every toggle off', {})] + [('only %s on' % t, {t: True}) for t in app_toggles]
for label, on in cases if app_tasks else []:
    home = WORK / ('app-%s' % label.replace(' ', '-'))
    home.mkdir()
    env_file = home / '990-dev.conf'
    extra = {**base, **off, **on, "non_root_home": str(home), "dev_env_file_in_use": str(env_file),
             "ih_picked_apps_run": False}
    if not run(app_tasks, extra, 'app_environment.yaml with %s' % label):
        continue
    runs += 1
    text = read(env_file) or ''
    expected = {n for n, o in app_variables.items() if set(on) & o}
    wrong = sorted(n for n in RETIRED_APP_VARIABLES if assigned(text, n) != (1 if n in expected else 0))
    if wrong:
        lines.append('FAIL app_environment.yaml with %s writes %s wrongly: expected exactly %s'
                     % (label, ', '.join('%s %d times' % (n, assigned(text, n)) for n in wrong),
                        ', '.join(sorted(expected)) or 'nothing'))
    else:
        lines.append('OK app_environment.yaml with %s writes %s' % (label, ', '.join(sorted(expected)) or 'nothing'))
unavailable = sorted(set().union(*[w['guards'] for w in writers if w['file'] == APP_ENV.name]))
if app_tasks and not unavailable:
    lines.append('FAIL %s reads unavailable_repositories nowhere, so it writes the variable of an app whose '
                 'third-party repository could not be added and which was never installed'
                 % APP_ENV.relative_to(ANSIBLE).as_posix())
if app_tasks and unavailable:
    home = WORK / 'app-every-repository-unavailable'
    home.mkdir()
    env_file = home / '990-dev.conf'
    extra = {**base, **{t: True for t in app_toggles}, "non_root_home": str(home), "dev_env_file_in_use": str(env_file),
             "ih_picked_apps_run": False, "unavailable_repositories": {k: {'vendor': k} for k in unavailable}}
    if run(app_tasks, extra, 'app_environment.yaml with every toggle on and every repository unavailable'):
        runs += 1
        text = read(env_file) or ''
        installed = {t for t in app_toggles if t[len('install_'):] not in unavailable}
        expected = {n for n, o in app_variables.items() if o & installed}
        wrong = sorted(n for n in app_variables if assigned(text, n) != (1 if n in expected else 0))
        if wrong:
            lines.append('FAIL app_environment.yaml with the %s repositories unavailable writes %s wrongly: expected '
                         'exactly %s' % (', '.join(unavailable), ', '.join(wrong), ', '.join(sorted(expected)) or 'nothing'))
        else:
            lines.append('OK app_environment.yaml with the %s repositories unavailable writes only %s'
                         % (', '.join(unavailable), ', '.join(sorted(expected)) or 'nothing'))
if app_tasks:
    home = WORK / 'app-every-toggle-on'
    home.mkdir()
    env_file = home / '990-dev.conf'
    extra = {**base, **{t: True for t in app_toggles}, "non_root_home": str(home), "dev_env_file_in_use": str(env_file),
             "ih_picked_apps_run": False}
    if run(app_tasks, extra, 'app_environment.yaml with every toggle on'):
        first = read(env_file)
        if run(app_tasks, extra, 'a second run of app_environment.yaml with every toggle on'):
            runs += 2
            if read(env_file) != first or any(assigned(first, n) != 1 for n in app_variables):
                lines.append('FAIL a second run of app_environment.yaml with every toggle on changed the file, or a '
                             'variable is not there exactly once')
            else:
                lines.append('OK a second run of app_environment.yaml with every toggle on changed nothing')
if runs < 12:
    lines.append('FAIL only %d runs of the shipped tasks were made, so nothing about them is proven' % runs)
print('\n'.join(line for line in lines if line))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "app env owners"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "an app's environment variable is written without its toggle" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the app env owners check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "app env owners"
