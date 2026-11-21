#!/usr/bin/env bash
#
# Tier 1: a picked-apps run does only the base work a picked app needs, owner decision 42.
#
# GitHub runs 44334156821, 44334164246 and 44334171501 of commit c16836b ran setup.sh --software none
# --enable install_gradle on Debian, Ubuntu and Fedora. Gradle needs SDKMAN and the default Java there,
# and the run also installed gnupg, flatpak, git and locales on Debian and Ubuntu, enabled contrib and
# non-free on Debian, installed iptables-nft, flatpak, patch, git and glibc-langpack-pl on Fedora, and
# added the Flathub remote on all three, docs/regression_ledger.md 10.363. So this asserts:
#
#   1. picked_apps_base_needs in group_vars/all.yaml names only toggles group_vars declares and managers
#      the dictionaries use, besides repository and custom. Every package of companion_packages.system_core
#      in every vars/<family>.yaml and derivative, every package of a literal list debian_core and
#      arch_core install under no toggle, and contrib-non-free, multilib and paru are keys of it, and
#      every key is read by system_core's list or by a condition '<key>' in ih_base_needed.
#   2. the shipped base work, lifted from system_core, debian_core and arch_core and run with
#      ansible-playbook against the real dictionaries: every top-level package install of those three
#      roles, the contrib and non-free sources, the Flathub remote, multilib and the paru build. A
#      picked-apps run of Gradle installs unzip, zip, curl and the certificates on Debian and Ubuntu,
#      unzip and zip on Fedora, and nothing on Arch, CachyOS and macOS, and does none of the rest. A
#      picked Flatpak app adds flatpak and Flathub, a picked pacman app with multilib in its needs enables
#      multilib, and a picked Arch User Repository app builds paru. A full run does all of it.
#   3. verify_install.yaml asks for flatpak and the Flathub remote only when ih_base_needed holds flatpak.
#   4. every task in the roles, the shared tasks and site.yaml that calls git, curl, gpg, unzip or zip,
#      through a command, a shell, the git module or an unarchive of a .zip, and can run in a
#      picked-apps run, sits under a toggle the entry of that tool in picked_apps_base_needs names, or a
#      toggle whose companion_packages install the tool, through its own conditions, its block, the
#      include of its file or the import of its role. Otherwise picked_apps_base_needs_allowed.txt names
#      it with the reason the tool is there anyway. A stale line of that file fails too.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd ansible-playbook
require_python "a picked-apps run does only the base work a picked app needs" "picked apps base needs"

info "Tier 1: a picked-apps run does only the base work a picked app needs"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

report_status=0
report="$("${PYTHON}" - "${REPO_ROOT}" "${work}" <<'PYEOF'
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

import yaml

REPO = pathlib.Path(sys.argv[1])
WORK = pathlib.Path(sys.argv[2])
ANSIBLE = REPO / 'setup' / 'ansible'
ROLES = ANSIBLE / 'roles'
SITE = ANSIBLE / 'site.yaml'
GROUP_VARS = ANSIBLE / 'group_vars'
VARS = ANSIBLE / 'vars'
VERIFY = ANSIBLE / 'verify_install.yaml'
ALLOWED = REPO / 'e2e' / 'tier1' / 'picked_apps_base_needs_allowed.txt'
BASE_ROLES = {'system_core': ROLES / 'system_core' / 'tasks' / 'base_utils.yaml',
              'debian_core': ROLES / 'debian_core' / 'tasks' / 'main.yaml',
              'arch_core': ROLES / 'arch_core' / 'tasks' / 'main.yaml'}
FAMILY_ROLES = {'Debian': ('system_core', 'debian_core'), 'RedHat': ('system_core',),
                'Archlinux': ('system_core', 'arch_core'), 'Darwin': ()}
WORK_TASKS = {'contrib': 'Enable contrib and non-free Debian repositories',
              'flathub': 'Add Flathub repository (Linux)',
              'multilib': 'Enable multilib repository in /etc/pacman.conf (Arch)',
              'paru': 'Build and install paru'}
TASK_KEYS = ('block', 'rescue', 'always')
TOGGLE = re.compile(r'\b((?:install|setup|configure)_[a-z0-9_]+)\b')
PICKED_OUT = re.compile(r'^\s*not\s*\(\s*ih_picked_apps_run\s*\|\s*bool\s*\)\s*$')
TOOLS = {
    'git': re.compile(r'(?:^|[\s;|&(`"\'])git\s'),
    'curl': re.compile(r'(?:^|[\s;|&(`"\'])curl\s'),
    'gnupg': re.compile(r'(?:^|[\s;|&(`"\'])gpg\s'),
    'unzip': re.compile(r'(?:^|[\s;|&(`"\'])unzip\s'),
    'zip': re.compile(r'(?:^|[\s;|&(`"\'])zip\s'),
}
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


def module(task, names):
    for name in names:
        for key in ('ansible.builtin.' + name, name):
            if key in task:
                return task[key]
    return None


def include_file(task):
    value = module(task, ('include_tasks', 'import_tasks'))
    value = value.get('file') if isinstance(value, dict) else value
    return value if isinstance(value, str) else None


def picked_out(text):
    return any(PICKED_OUT.match(piece) for piece in re.split(r'\s+and\s+', text))


# --- 1. the data ---------------------------------------------------------------------------------
all_vars = load(GROUP_VARS / 'all.yaml')
declared = set()
for name in ('all.yaml', 'linux.yaml', 'macos.yaml'):
    declared |= {k for k, v in (load(GROUP_VARS / name) or {}).items() if isinstance(v, bool)}
dictionaries = {p: load(p) for p in sorted(VARS.glob('*.yaml')) + sorted((VARS / 'derivatives').glob('*.yaml'))}
managers = {'repository', 'custom'}
for data in dictionaries.values():
    for entry in (data.get('software_mapping') or {}).values():
        if isinstance(entry, dict) and entry.get('manager'):
            managers.add(str(entry['manager']))
needs = all_vars.get('picked_apps_base_needs')
if not isinstance(needs, dict) or not needs:
    lines.append('FAIL group_vars/all.yaml has no picked_apps_base_needs, so nothing says which base work a picked '
                 'app needs and a picked-apps run does all of it, docs/regression_ledger.md 10.363')
    needs = {}
problems = []
for key, entry in needs.items():
    if not isinstance(entry, dict) or set(entry) - {'toggles', 'managers'} \
            or any(not isinstance(entry.get(f, []), list) for f in ('toggles', 'managers')):
        problems.append('%s is not a map of a toggles list and a managers list' % key)
        continue
    unknown_toggles = sorted(set(entry.get('toggles', [])) - declared)
    unknown_managers = sorted(set(entry.get('managers', [])) - managers)
    if unknown_toggles or unknown_managers:
        problems.append('%s names %s' % (key, ', '.join(unknown_toggles + unknown_managers)))
system_core = set()
for path, data in dictionaries.items():
    system_core |= set(((data.get('companion_packages') or {}).get('system_core')) or [])
literal = set()
role_text = {}
for role, path in BASE_ROLES.items():
    role_text[role] = path.read_text(encoding='utf-8')
    for task in load(path):
        if not isinstance(task, dict) or not str(include_file(task) or '').endswith('tasks/install_role_packages.yaml'):
            continue
        packages = (task.get('vars') or {}).get('role_packages')
        if isinstance(packages, list) and not TOGGLE.search(when_text(task)):
            literal |= set(packages)
for key in sorted(system_core | literal | {'contrib-non-free', 'multilib', 'paru'}):
    if key not in needs:
        problems.append('%s is base work a picked-apps run can do and has no entry' % key)
for key in needs:
    read_by = key in system_core or any("'%s' in ih_base_needed" % key in t for t in role_text.values())
    if not read_by:
        problems.append('%s is read by no system_core list and by no condition \'%s\' in ih_base_needed' % (key, key))
if needs and problems:
    lines.append('FAIL picked_apps_base_needs in group_vars/all.yaml: %s' % '; '.join(problems))
elif needs:
    lines.append('OK picked_apps_base_needs has an entry for each piece of base work, each one read, naming only '
                 'declared toggles and known managers')

# --- 3. the verification -------------------------------------------------------------------------
verify_tasks = {t.get('name'): c for t, c in walk(load(VERIFY)[0].get('tasks'))}
for name in ('List the configured flatpak remotes', 'Assert flatpak is installed and the Flathub remote is configured'):
    if "'flatpak' in ih_base_needed" not in ' and '.join(verify_tasks.get(name, ('',))):
        lines.append('FAIL "%s" in verify_install.yaml is not asked only when ih_base_needed holds flatpak, so a '
                     'picked-apps run that rightly added no Flathub fails its verification' % name)

# --- 2. the shipped base work --------------------------------------------------------------------
for part in ('ansible', 'pinned_values'):
    shutil.copytree(REPO / 'setup' / part, WORK / 'setup' / part, ignore=shutil.ignore_patterns('__pycache__'))
COPY = WORK / 'setup' / 'ansible'
lifted = []
found_work = set()
for role, path in BASE_ROLES.items():
    for task in load(path):
        if not isinstance(task, dict):
            continue
        name = task.get('name', '(unnamed)')
        is_install = str(include_file(task) or '').endswith('tasks/install_role_packages.yaml')
        if not is_install and name not in WORK_TASKS.values():
            continue
        found_work |= {name} & set(WORK_TASKS.values())
        task_vars = {'ih_lift_role': role, 'ih_lift_task': name}
        if is_install:
            task_vars['ih_lift_packages'] = (task.get('vars') or {}).get('role_packages', [])
        lifted.append({'name': 'Lifted %s: %s' % (role, name), 'vars': task_vars,
                       'ansible.builtin.set_fact': {'ih_lifted': (
                           "{{ ih_lifted + [{'role': ih_lift_role, 'task': ih_lift_task, "
                           "'packages': ih_lift_packages | default([]) | list}] }}")},
                       **({'when': task['when']} if 'when' in task else {})})
missing_work = sorted(set(WORK_TASKS.values()) - found_work)
if missing_work:
    lines.append('FAIL the base roles have no top-level task named %s, so this check cannot run it'
                 % ', '.join('"%s"' % n for n in missing_work))
play = [{
    'hosts': 'localhost', 'connection': 'local', 'gather_facts': True, 'gather_subset': ['min'],
    'vars_files': ['group_vars/all.yaml'],
    'tasks': [
        {'name': 'Load the dictionary', 'ansible.builtin.include_tasks': 'tasks/load_os_dict.yaml'},
        {'name': 'Decide what is brought in', 'ansible.builtin.include_tasks': 'tasks/toggle_prerequisites.yaml'},
        {'name': 'Start the record', 'ansible.builtin.set_fact': {'ih_lifted': []}},
    ] + lifted + [
        {'name': 'Record the answers', 'ansible.builtin.copy': {'dest': '{{ ih_case_dir }}/facts.json', 'content': (
            '{{ {"needed": ih_base_needed, "lifted": ih_lifted} | to_json }}')}},
    ],
}]
(COPY / 'picked_apps_base_needs_play.yaml').write_text(yaml.safe_dump(play, sort_keys=False), encoding='utf-8')
(WORK / 'empty.cfg').write_text('[defaults]\n', encoding='utf-8')
env = dict(os.environ, ANSIBLE_CONFIG=str(WORK / 'empty.cfg'), ANSIBLE_STDOUT_CALLBACK='default', ANSIBLE_NOCOLOR='1',
           ANSIBLE_LOCALHOST_WARNING='false', ANSIBLE_RETRY_FILES_ENABLED='false')


def first_key(family, manager):
    for key, entry in (load(VARS / ('%s.yaml' % family)).get('software_mapping') or {}).items():
        toggle = 'install_' + key
        if isinstance(entry, dict) and entry.get('manager') == manager and toggle in declared \
                and not any(toggle in (e or {}).get('toggles', []) for e in needs.values()):
            return toggle
    return None


aur_pick = first_key('Archlinux', 'aur') or 'install_brave'
ALL = sorted(needs)
CASES = [
    # name, family, os-release ID, lineage, picked toggle or None for a full run, needed, packages, work
    ('debian picked gradle', 'Debian', 'debian', 'debian', 'install_gradle',
     {'ca-certificates', 'curl', 'unzip', 'zip'}, {'unzip', 'zip', 'curl', 'ca-certificates'}, set()),
    ('ubuntu picked gradle', 'Debian', 'ubuntu', 'ubuntu', 'install_gradle',
     {'ca-certificates', 'curl', 'unzip', 'zip'}, {'unzip', 'zip', 'curl', 'ca-certificates'}, set()),
    ('fedora picked gradle', 'RedHat', 'fedora', 'fedora', 'install_gradle',
     {'ca-certificates', 'curl', 'unzip', 'zip'}, {'unzip', 'zip'}, set()),
    ('arch picked gradle', 'Archlinux', 'arch', 'arch', 'install_gradle', set(), set(), set()),
    ('cachyos picked gradle', 'Archlinux', 'cachyos', 'arch', 'install_gradle', set(), set(), set()),
    ('macos picked gradle', 'Darwin', '', 'darwin', 'install_gradle', set(), set(), set()),
    ('debian picked steam, a Flatpak there', 'Debian', 'debian', 'debian', 'install_steam',
     {'flatpak', 'ca-certificates', 'multilib'}, {'flatpak', 'ca-certificates'}, {'flathub'}),
    ('arch picked steam, a pacman package from multilib', 'Archlinux', 'arch', 'arch', 'install_steam',
     {'multilib'}, set(), {'multilib'}),
    ('arch picked %s, an Arch User Repository package' % aur_pick[len('install_'):], 'Archlinux', 'arch', 'arch',
     aur_pick, {'paru'}, set(), {'paru'}),
    ('debian full', 'Debian', 'debian', 'debian', None, set(ALL),
     {'flatpak', 'unzip', 'zip', 'git', 'locales', 'curl', 'gnupg', 'ca-certificates'}, {'contrib', 'flathub'}),
    ('fedora full', 'RedHat', 'fedora', 'fedora', None, set(ALL),
     {'iptables-nft', 'flatpak', 'unzip', 'zip', 'patch', 'git', 'glibc-langpack-pl'}, {'flathub'}),
    ('arch full', 'Archlinux', 'arch', 'arch', None, set(ALL),
     {'flatpak', 'unzip', 'zip', 'git'}, {'flathub', 'multilib', 'paru'}),
]
procs = {}
for name, family, os_id, base, picked, _, _, _ in CASES if needs and not missing_work else []:
    case = WORK / re.sub(r'[^a-z0-9]+', '-', name)
    case.mkdir()
    extra = dict(ih_family=family, ih_os_release_id=os_id, ih_base=base, ih_timeout='timeout',
                 ih_picked_apps=picked or '', install_java=False, install_snapd=False, install_yay=False,
                 ih_snapd_with_system=True, multilib_already_enabled={'rc': 1}, ih_case_dir=str(case))
    if picked:
        prerequisites = all_vars.get('toggle_prerequisites') or {}
        extra.update({t: False for k, v in prerequisites.items() for t in (k, (v or {}).get('needs')) if t})
        extra[picked] = True
    (case / 'extra.json').write_text(json.dumps(extra), encoding='utf-8')
    procs[name] = (case, subprocess.Popen(
        ['ansible-playbook', '-i', 'localhost,', str(COPY / 'picked_apps_base_needs_play.yaml'),
         '-e', '@' + str(case / 'extra.json')],
        cwd=WORK, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True))
for name, family, os_id, base, picked, needed, packages, work_done in CASES:
    if name not in procs:
        continue
    case, proc = procs[name]
    output = proc.communicate()[0]
    if proc.returncode != 0 or not (case / 'facts.json').is_file():
        lines.append('FAIL %s: ansible-playbook exited %d before it recorded its answers: %s'
                     % (name, proc.returncode, ' '.join(output.split()[-60:])))
        continue
    facts = json.loads((case / 'facts.json').read_text(encoding='utf-8'))
    ran = [r for r in facts['lifted'] if r['role'] in FAMILY_ROLES[family]]
    got_packages = {p for r in ran for p in r['packages']}
    got_work = {k for k, v in WORK_TASKS.items() if any(r['task'] == v for r in ran)}
    wrong = []
    if set(facts['needed']) != needed:
        wrong.append('ih_base_needed is %s, expected %s' % (sorted(facts['needed']), sorted(needed)))
    if got_packages != packages:
        wrong.append('installs %s, expected %s' % (sorted(got_packages) or 'nothing', sorted(packages) or 'nothing'))
    if got_work != work_done:
        wrong.append('does %s, expected %s' % (', '.join(sorted(got_work)) or 'no other base work',
                                               ', '.join(sorted(work_done)) or 'no other base work'))
    if wrong:
        lines.append('FAIL %s: %s, docs/regression_ledger.md 10.363' % (name, '; '.join(wrong)))
    else:
        lines.append('OK %s: installs %s and does %s' % (name, ', '.join(sorted(packages)) or 'no base package',
                                                         ', '.join(sorted(work_done)) or 'no other base work'))

# --- 4. every caller of a base tool --------------------------------------------------------------
companion_toggles = {}
for data in dictionaries.values():
    for key, packages in (data.get('companion_packages') or {}).items():
        if key == 'system_core':
            continue
        toggle = key if TOGGLE.fullmatch(key) else 'install_' + key
        for package in packages or []:
            companion_toggles.setdefault(package, set()).add(toggle)
allowed = {}
for raw in ALLOWED.read_text(encoding='utf-8').splitlines() if ALLOWED.is_file() else []:
    if not raw.strip() or raw.lstrip().startswith('#'):
        continue
    parts = [p.strip() for p in raw.split('|')]
    if len(parts) != 3 or not all(parts) or parts[0] not in TOOLS:
        lines.append('FAIL %s line is not "<git, curl, gnupg, unzip or zip> | <task name> | <reason>": %s'
                     % (ALLOWED.relative_to(REPO).as_posix(), raw))
        continue
    allowed[(parts[0], parts[1])] = parts[2]
files = [SITE] + sorted((ANSIBLE / 'tasks').glob('*.yaml')) + sorted(ROLES.glob('*/tasks/*.yaml'))
found = {}
for path in files:
    doc = load(path)
    plays = doc if path == SITE else [{'tasks': doc}]
    found[path] = [(t, ' and '.join(c for c in chain if c)) for play in plays
                   for section in ('pre_tasks', 'tasks', 'post_tasks', 'handlers') for t, chain in walk(play.get(section))]
includers = {}
for path, tasks in found.items():
    for task, chain in tasks:
        imported = module(task, ('import_role', 'include_role'))
        if isinstance(imported, dict) and imported.get('name'):
            target = ROLES / imported['name'] / 'tasks' / ('%s.yaml' % imported.get('tasks_from', 'main'))
            includers.setdefault(target, []).append((path, chain))
        target = include_file(task)
        if target:
            target = target.replace('{{ playbook_dir }}/', '')
            if '{{' in target:
                continue
            resolved = ANSIBLE / target if target.startswith('tasks/') else path.parent / target
            includers.setdefault(resolved, []).append((path, chain))


def contexts(path, depth=0):
    if depth > 8 or not includers.get(path):
        return ['']
    return [' and '.join(p for p in (chain, outer) if p)
            for source, chain in includers[path] for outer in contexts(source, depth + 1)]


def tools_of(task):
    used = set()
    if module(task, ('git',)) is not None:
        used.add('git')
    archive = module(task, ('unarchive',))
    if isinstance(archive, dict) and str(archive.get('src', '')).lower().endswith('.zip'):
        used.add('unzip')
    for value in (module(task, ('command',)), module(task, ('shell',)), module(task, ('raw',))):
        if isinstance(value, dict):
            value = value.get('cmd') or value.get('argv') or value.get('_raw_params') or ''
        if isinstance(value, list):
            value = ' '.join(str(v) for v in value) + ' '
        if isinstance(value, str):
            used |= {tool for tool, pattern in TOOLS.items() if pattern.search(value + ' ')}
    return used


callers = 0
seen_allowed = set()
for path, tasks in found.items():
    outer = contexts(path)
    for task, chain in tasks:
        for tool in sorted(tools_of(task)):
            callers += 1
            name = task.get('name', '(unnamed)')
            satisfying = set((needs.get(tool) or {}).get('toggles', [])) | companion_toggles.get(tool, set())
            texts = [' and '.join(p for p in (chain, o) if p) for o in outer]
            unmet = [t for t in texts if not picked_out(t) and not (set(TOGGLE.findall(t)) & satisfying)]
            if not unmet:
                continue
            if (tool, name) in allowed:
                seen_allowed.add((tool, name))
                continue
            lines.append('FAIL "%s" in %s calls %s and can run in a picked-apps run under %s, and neither '
                         'picked_apps_base_needs.%s in group_vars/all.yaml nor a companion list of it names such a '
                         'toggle, and %s does not name it, docs/regression_ledger.md 10.363'
                         % (name, path.relative_to(REPO).as_posix(), tool,
                            ', '.join(sorted(set(TOGGLE.findall(' '.join(unmet))))) or 'no toggle at all', tool,
                            ALLOWED.relative_to(REPO).as_posix()))
for tool, name in sorted(set(allowed) - seen_allowed):
    lines.append('FAIL %s names "%s" for %s, and no task of that name calls %s outside the toggles that need it'
                 % (ALLOWED.relative_to(REPO).as_posix(), name, tool, tool))
if callers < 30:
    lines.append('FAIL only %d calls of git, curl, gpg, unzip or zip were read out of the playbook, so nothing about '
                 'them is proven' % callers)
elif not any(l.startswith('FAIL') and 'calls' in l for l in lines):
    lines.append('OK each of the %d calls of git, curl, gpg, unzip or zip sits under a toggle that needs the tool, '
                 'or %s says why the tool is there' % (callers, ALLOWED.relative_to(REPO).as_posix()))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "picked apps base needs"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a picked-apps run does base work no picked app needs" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the picked apps base needs check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "picked apps base needs"
