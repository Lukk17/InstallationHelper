#!/usr/bin/env bash
#
# Tier 1: a toggle whose app needs another toggle's tool brings that toggle in, and the plan says so.
#
# Debian, Ubuntu and Fedora have no gradle mapping, so Gradle comes from SDKMAN there, and SDKMAN ran
# only under install_java. A run with install_gradle on and install_java off, a picked-apps run of
# Gradle among them, installed no Gradle and no Java and reported nothing, docs/regression_ledger.md
# 10.351. Owner decision 55: on those systems install_gradle brings in SDKMAN and the default Java, and
# the plan setup.sh prints before the run names Java as brought in by Gradle. So this asserts:
#
#   1. toggle_prerequisites in group_vars/all.yaml gives install_gradle the needs
#      install_java, and every toggle it names is a toggle all.yaml declares.
#   2. site.yaml imports tasks/toggle_prerequisites.yaml in its pre_tasks after the OS dictionary and
#      under tag always, verify_install.yaml includes it after its own dictionary, the SDKMAN block of
#      sdk_manager and sdkman.yaml read ih_toggles_brought_in, and so does the list site.yaml names
#      when env_variables failed.
#   3. the shipped tasks, run with ansible-playbook against the real dictionaries: the toggle
#      prerequisites, sdk_manager with a fake SDKMAN, app_environment.yaml of software_installer, and
#      the two verification facts of verify_install.yaml. With install_gradle on and install_java off,
#      in a full run and in a picked-apps run, Debian, Ubuntu and Fedora install the default Java
#      alone, then Gradle, set the default Java, write the SDKMAN block with JAVA_HOME, the Gradle
#      block and the SDKMAN shell init, and the verification expects SDKMAN, Java and Gradle. Arch,
#      CachyOS and macOS bring nothing in and SDKMAN does nothing. install_java on installs every
#      Java version, and both toggles off install nothing.
#   4. the plan: setup.sh's own functions, under each family and os-release ID, name Java as brought
#      in by Gradle on Debian, Ubuntu and Fedora alone, and only with install_gradle on and
#      install_java off. A real setup.sh --print-command --software none --enable install_gradle in
#      this Debian container prints that line before the command, which turns install_java off and
#      names install_gradle as the picked app. Both entrypoints print it before the run starts.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd ansible-playbook
require_python "a toggle whose app needs another toggle's tool brings it in" "toggle prerequisites"

info "Tier 1: a toggle whose app needs another toggle's tool brings it in, and the plan says so"

SETUP_SH="${REPO_ROOT}/setup/setup.sh"
EXPECTED_NOTE="Java: brought in by Gradle, which needs it on this machine, so this run also installs SDKMAN and the default Java."

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

# --- 1 to 3. the data, the wiring and the shipped tasks -------------------------------------------
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
COPY = WORK / 'setup' / 'ansible'
lines = []

all_vars = yaml.safe_load((ANSIBLE / 'group_vars' / 'all.yaml').read_text(encoding='utf-8')) or {}
declared = {k for k, v in all_vars.items() if isinstance(v, bool)}
data = all_vars.get('toggle_prerequisites')

# --- 1. the data ---------------------------------------------------------------------------------
if not isinstance(data, dict) or (data.get('install_gradle') or {}).get('needs') != 'install_java':
    lines.append('FAIL group_vars/all.yaml has no toggle_prerequisites entry giving install_gradle the '
                 'needs install_java, so Gradle on Debian, Ubuntu and Fedora installs through an SDKMAN nothing '
                 'installs, docs/regression_ledger.md 10.351')
    data = {}
else:
    unknown = sorted({t for k, v in data.items() for t in (k, (v or {}).get('needs'))} - declared)
    unbrought = sorted(k for k, v in data.items() if not str((v or {}).get('brings', '')).strip())
    if unknown or unbrought:
        lines.append('FAIL toggle_prerequisites names %s, which group_vars/all.yaml does not declare, or '
                     'gives %s no brings for the plan to print'
                     % (', '.join(unknown) or 'no unknown toggle', ', '.join(unbrought) or 'every entry'))
    else:
        lines.append('OK toggle_prerequisites gives install_gradle the needs install_java, and names only '
                     'declared toggles')


# --- 2. the wiring -------------------------------------------------------------------------------
def load(path):
    return yaml.safe_load(path.read_text(encoding='utf-8')) or []


def walk(node):
    if isinstance(node, list):
        for task in node:
            if isinstance(task, dict):
                yield task
                for section in ('block', 'rescue', 'always'):
                    yield from walk(task.get(section))


def target(task):
    for key in ('ansible.builtin.import_tasks', 'ansible.builtin.include_tasks', 'import_tasks', 'include_tasks'):
        value = task.get(key)
        if value is not None:
            return str(value.get('file', '')) if isinstance(value, dict) else str(value)
    return ''


def order_in(tasks, first, second):
    names = [target(t) for t in tasks]
    at_first = [i for i, n in enumerate(names) if n.endswith(first)]
    at_second = [i for i, n in enumerate(names) if n.endswith(second)]
    return bool(at_first and at_second and at_first[0] < at_second[0]), [tasks[i] for i in at_second]


site = load(ANSIBLE / 'site.yaml')[0]
ordered, imports = order_in(site.get('pre_tasks') or [], 'tasks/load_os_dict.yaml', 'tasks/toggle_prerequisites.yaml')
if not ordered or 'always' not in str(imports[0].get('tags')):
    lines.append('FAIL the pre_tasks of site.yaml do not import tasks/toggle_prerequisites.yaml after '
                 'tasks/load_os_dict.yaml under the tag always, so sdk_manager reads no answer')
verify = load(ANSIBLE / 'verify_install.yaml')[0]
ordered, _ = order_in(verify.get('pre_tasks') or [], 'tasks/load_os_dict.yaml', 'tasks/toggle_prerequisites.yaml')
if not ordered:
    lines.append('FAIL verify_install.yaml does not include tasks/toggle_prerequisites.yaml after its dictionary, so '
                 'it cannot expect what the playbook brought in')
BROUGHT = re.compile(r"'install_java'\s+in\s+ih_toggles_brought_in\b")
sdk_tasks = ANSIBLE / 'roles' / 'sdk_manager' / 'tasks'
sdkman_block = [t for t in load(sdk_tasks / 'main.yaml') if any(target(b) == 'sdkman.yaml' for b in walk(t.get('block')))]
sdkman_include = [t for t in load(sdk_tasks / 'sdkman.yaml') if target(t) == 'sdkman_unix.yaml']
for label, tasks in (('the SDKMAN block of roles/sdk_manager/tasks/main.yaml', sdkman_block),
                     ('the include in roles/sdk_manager/tasks/sdkman.yaml', sdkman_include)):
    if len(tasks) != 1 or not BROUGHT.search(str(tasks[0].get('when'))):
        lines.append('FAIL %s is not gated on install_java brought in through ih_toggles_brought_in, so Gradle on '
                     'Debian, Ubuntu and Fedora gets no SDKMAN' % label)
skip_lists = [t for t in walk(site.get('tasks')) if 'env_variables failed' in str(t)
              and isinstance(t.get('loop'), list)]
if len(skip_lists) != 1 or 'ih_toggles_brought_in' not in str(skip_lists[0].get('when')):
    lines.append('FAIL the list site.yaml names when env_variables failed does not read ih_toggles_brought_in, so '
                 'SDKMAN brought in by Gradle is skipped without being named')
if not any(l.startswith('FAIL') for l in lines):
    lines.append('OK site.yaml, verify_install.yaml, sdk_manager and the env_variables skip list all read the one '
                 'answer of tasks/toggle_prerequisites.yaml')

# --- 3. the shipped tasks ------------------------------------------------------------------------

# A copy of the playbook, so the shipped files run as they are with three changes a container needs: no
# become, because the gate runs as one user, and no async or retry, which only spend time here. Nothing
# else in them is touched.
for part in ('ansible', 'pinned_values'):
    shutil.copytree(REPO / 'setup' / part, WORK / 'setup' / part, ignore=shutil.ignore_patterns('__pycache__'))
HARNESS_ONLY = ('become', 'become_user', 'async', 'poll', 'retries', 'delay', 'until')


def strip(node):
    if isinstance(node, dict):
        return {k: strip(v) for k, v in node.items() if k not in HARNESS_ONLY}
    if isinstance(node, list):
        return [strip(v) for v in node]
    return node


for path in list((COPY / 'roles' / 'sdk_manager' / 'tasks').glob('*.yaml')) + \
        [COPY / 'roles' / 'software_installer' / 'tasks' / 'app_environment.yaml']:
    path.write_text(yaml.safe_dump(strip(load(path)), sort_keys=False), encoding='utf-8')

# The two verification tasks this change reads, lifted as shipped, without their Linux condition.
lifted = []
for task in walk(verify.get('tasks')):
    facts = task.get('ansible.builtin.set_fact') or {}
    if isinstance(facts, dict) and ({'ih_sdkman_applies', 'ih_session_env_vars'} & set(facts)):
        lifted.append({k: v for k, v in task.items() if k != 'when'})
rows = [r for t in walk(verify.get('tasks')) for r in ((t.get('ansible.builtin.set_fact') or {}).get('ih_outside_pm_tools') or [])
        if isinstance(r, dict)]
row_toggles = {str(r.get('key')): str(r.get('toggle')) for r in rows}
if len(lifted) != 2:
    lines.append('FAIL verify_install.yaml should set ih_sdkman_applies and ih_session_env_vars in one task each, '
                 'and %d tasks were found' % len(lifted))
if row_toggles.get('sdk') != 'ih_sdkman_applies' or row_toggles.get('java') != 'ih_sdkman_applies' \
        or row_toggles.get('gradle (via SDKMAN)') != 'ih_gradle_sdkman_applies':
    lines.append('FAIL the sdk, java and gradle (via SDKMAN) rows of verify_install.yaml are not asked under '
                 'ih_sdkman_applies and ih_gradle_sdkman_applies, so a run that brought Java in is not checked '
                 'for it: %s' % json.dumps({k: row_toggles.get(k) for k in ('sdk', 'java', 'gradle (via SDKMAN)')}))

FAKE_INIT = r'''# The fake SDKMAN of e2e/tier1/toggle_prerequisites.sh
IH_FAKE_SDKMAN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk() {
    printf '%s\n' "$*" >>"${IH_FAKE_SDKMAN_ROOT}/../../sdk.log"
    case "$1 $2" in
        'install java'|'install gradle') mkdir -p "${IH_FAKE_SDKMAN_ROOT}/candidates/$2/$3/bin" ;;
        'default java') echo "Default java set to $3" ;;
    esac
}
'''
fake_bin = WORK / 'fake-bin'
fake_bin.mkdir()
(fake_bin / 'curl').write_text('#!/bin/sh\necho "fake curl of toggle_prerequisites ran" >&2\nexit 97\n', encoding='utf-8')
(fake_bin / 'curl').chmod(0o755)
env = dict(os.environ, PATH='%s:%s' % (fake_bin, os.environ.get('PATH', '')), ANSIBLE_CONFIG=str(WORK / 'empty.cfg'),
           ANSIBLE_ROLES_PATH=str(COPY / 'roles'), ANSIBLE_STDOUT_CALLBACK='default', ANSIBLE_NOCOLOR='1',
           ANSIBLE_LOCALHOST_WARNING='false', ANSIBLE_RETRY_FILES_ENABLED='false')
(WORK / 'empty.cfg').write_text('[defaults]\n', encoding='utf-8')

# Defect class 16: the one download this role can start must reach the fake, under the environment the
# runs are given, before any run starts.
resolved = subprocess.run(['bash', '-c', 'command -v curl'], env=env, capture_output=True, text=True).stdout.strip()
if resolved != str(fake_bin / 'curl'):
    lines.append('FAIL curl resolves to %s rather than the fake in %s, so no run was started' % (resolved, fake_bin))
    print('\n'.join(lines))
    sys.exit(0)

play = [{
    'hosts': 'localhost', 'connection': 'local', 'gather_facts': True, 'gather_subset': ['min'],
    'vars_files': ['group_vars/all.yaml'],
    'tasks': [
        {'name': 'Load the dictionary', 'ansible.builtin.include_tasks': 'tasks/load_os_dict.yaml'},
        {'name': 'Decide what is brought in', 'ansible.builtin.include_tasks': 'tasks/toggle_prerequisites.yaml'},
        {'name': 'Run sdk_manager', 'ansible.builtin.include_role': {'name': 'sdk_manager'}},
        {'name': 'Run the app environment', 'ansible.builtin.include_tasks': 'roles/software_installer/tasks/app_environment.yaml'},
    ] + lifted + [
        {'name': 'Record the answers', 'ansible.builtin.copy': {'dest': '{{ ih_case_dir }}/facts.json', 'content': (
            '{{ {"brought_in": ih_toggles_brought_in, "picked": ih_picked_apps_run | bool,'
            ' "env_run": ih_env_variables_run | bool, "sdkman": ih_sdkman_applies | bool,'
            ' "gradle": ih_gradle_sdkman_applies | bool, "session": ih_session_env_vars,'
            ' "path": ih_session_path_entries, "failed": any_role_failed | default(false),'
            ' "every_java": [java11_id, java17_id, java21_id, java25_id], "default_java": default_java,'
            ' "gradle_id": gradle_id} | to_json }}')}},
    ],
}]
(COPY / 'toggle_prerequisites_play.yaml').write_text(yaml.safe_dump(play, sort_keys=False), encoding='utf-8')

CASES = [
    # name, family, os-release ID, lineage, java, gradle, picked, brought in
    ('debian full', 'Debian', 'debian', 'debian', False, True, False, True),
    ('debian picked', 'Debian', 'debian', 'debian', False, True, True, True),
    ('ubuntu picked', 'Debian', 'ubuntu', 'ubuntu', False, True, True, True),
    ('fedora full', 'RedHat', 'fedora', 'fedora', False, True, False, True),
    ('fedora picked', 'RedHat', 'fedora', 'fedora', False, True, True, True),
    ('arch picked', 'Archlinux', 'arch', 'arch', False, True, True, False),
    ('cachyos picked', 'Archlinux', 'cachyos', 'arch', False, True, True, False),
    ('macos picked', 'Darwin', '', 'darwin', False, True, True, False),
    ('debian full with install_java', 'Debian', 'debian', 'debian', True, True, False, False),
    ('debian full with both off', 'Debian', 'debian', 'debian', False, False, False, False),
]
procs = {}
for name, family, os_id, base, java, gradle, picked, _ in CASES:
    case = WORK / name.replace(' ', '-')
    home = case / 'home'
    sdkman = home / '.sdkman'
    (sdkman / 'bin').mkdir(parents=True)
    (sdkman / 'var').mkdir()
    (home / '.config' / 'environment.d').mkdir(parents=True)
    (home / '.config' / 'zsh').mkdir()
    (sdkman / 'bin' / 'sdkman-init.sh').write_text(FAKE_INIT, encoding='utf-8')
    (sdkman / 'var' / 'version').write_text('fixture\n', encoding='utf-8')
    (sdkman / 'var' / 'version_native').write_text('fixture\n', encoding='utf-8')
    probe = subprocess.run(['bash', '-c', 'source "$1" && declare -f sdk && sdk probe', '-', str(sdkman / 'bin' / 'sdkman-init.sh')],
                           env=env, capture_output=True, text=True)
    probe_log = case / 'sdk.log'
    probe_logged = probe_log.is_file() and probe_log.read_text(encoding='utf-8') == 'probe\n'
    if 'IH_FAKE_SDKMAN_ROOT' not in probe.stdout or not probe_logged:
        lines.append('FAIL %s: the fixture sdkman-init.sh does not define the fake sdk, or its calls do not reach %s, '
                     'so no run was started' % (name, probe_log))
        continue
    probe_log.unlink()
    extra = dict(ih_family=family, ih_os_release_id=os_id, ih_base=base, ih_timeout='timeout',
                 non_root_home=str(home), non_root_user=os.environ.get('USER', 'root'), setup_zsh=True,
                 install_java=java, install_gradle=gradle, install_nodejs=False, install_python=False,
                 install_flutter=False, install_android_sdk=False, install_docker=False, install_maven=False,
                 install_kubectl=False, install_minikube=False, install_k3d=False, install_helm=False,
                 install_lens=False, install_jetbrains_toolbox=False, ih_picked_apps='install_gradle' if picked else '', ih_case_dir=str(case))
    (case / 'extra.json').write_text(json.dumps(extra), encoding='utf-8')
    procs[name] = (case, subprocess.Popen(
        ['ansible-playbook', '-i', 'localhost,', str(COPY / 'toggle_prerequisites_play.yaml'), '-e', '@' + str(case / 'extra.json')],
        cwd=WORK, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True))


def block_of(text, label):
    found = re.findall(r'^# BEGIN ANSIBLE %s\n(.*?)^# END ANSIBLE %s\n' % (label, label), text, re.M | re.S)
    return found[0] if len(found) == 1 else None


for name, family, os_id, base, java, gradle, picked, brought in CASES:
    if name not in procs:
        continue
    case, proc = procs[name]
    output = proc.communicate()[0]
    if proc.returncode != 0 or not (case / 'facts.json').is_file():
        lines.append('FAIL %s: ansible-playbook exited %d before it recorded its answers: %s'
                     % (name, proc.returncode, ' '.join(output.split()[-60:])))
        continue
    facts = json.loads((case / 'facts.json').read_text(encoding='utf-8'))
    home = case / 'home'
    log = (case / 'sdk.log').read_text(encoding='utf-8').splitlines() if (case / 'sdk.log').is_file() else []
    env_file = home / '.config' / 'environment.d' / '990-dev.conf'
    env_text = env_file.read_text(encoding='utf-8') if env_file.is_file() else ''
    rc_paths = [home / '.bashrc', home / '.config' / 'zsh' / '.zshrc']
    rc_texts = [p.read_text(encoding='utf-8') if p.is_file() else '' for p in rc_paths]
    sdkman_env = block_of(env_text, 'SDKMAN ENVIRONMENT')
    gradle_env = block_of(env_text, 'GRADLE ENVIRONMENT')
    init_blocks = [block_of(t, 'SDKMAN SHELL INIT') for t in rc_texts]
    problems = []
    if facts['picked'] != picked:
        problems.append('ih_picked_apps_run is %s' % facts['picked'])
    if facts['failed']:
        problems.append('a rescue of sdk_manager fired')
    if facts['brought_in'] != (['install_java'] if brought else []):
        problems.append('ih_toggles_brought_in is %s' % facts['brought_in'])
    sdkman_on = java or brought
    expected_log = ([' '.join(('install java', j)) for j in (facts['every_java'] if java else [facts['default_java']])] if sdkman_on else []) \
        + (['install gradle %s' % facts['gradle_id']] if sdkman_on and gradle and family in ('Debian', 'RedHat') else []) \
        + (['default java %s' % facts['default_java']] if sdkman_on else [])
    if log != expected_log:
        problems.append('SDKMAN was asked for %s, expected %s' % (log or 'nothing', expected_log or 'nothing'))
    if sdkman_on:
        if not sdkman_env or 'JAVA_HOME=${HOME}/.sdkman/candidates/java/current' not in sdkman_env:
            problems.append('the environment file holds no SDKMAN block with JAVA_HOME')
        if not all(init_blocks):
            problems.append('%s has no SDKMAN shell init block' % ', '.join(str(p.relative_to(home))
                                                                          for p, b in zip(rc_paths, init_blocks) if not b))
    elif sdkman_env or any(init_blocks):
        problems.append('SDKMAN was wired in, though nothing asked for it')
    if gradle and (not gradle_env or 'GRADLE_USER_HOME=' not in gradle_env):
        problems.append('the environment file holds no GRADLE_USER_HOME block')
    if gradle and not facts['env_run']:
        problems.append('ih_env_variables_run is false, so no shell imports the environment file')
    if facts['sdkman'] != sdkman_on or facts['gradle'] != (gradle and family in ('Debian', 'RedHat')):
        problems.append('the verification expects SDKMAN and Java %s and an SDKMAN Gradle %s'
                        % (facts['sdkman'], facts['gradle']))
    for variable in ('SDKMAN_DIR', 'JAVA_HOME'):
        if (variable in facts['session']) != sdkman_on:
            problems.append('the desktop session check asks for %s: %s' % (variable, variable in facts['session']))
    if (str(home / '.sdkman' / 'candidates' / 'java' / 'current' / 'bin') in facts['path']) != sdkman_on:
        problems.append('the desktop session check asks for SDKMAN Java on PATH: %s' % (not sdkman_on))
    if problems:
        lines.append('FAIL %s, install_java %s and install_gradle %s: %s'
                     % (name, str(java).lower(), str(gradle).lower(), '; '.join(problems)))
    else:
        lines.append('OK %s, install_java %s and install_gradle %s: %s'
                     % (name, str(java).lower(), str(gradle).lower(),
                        ('brings in install_java, installs %s, sets it as default, writes JAVA_HOME and '
                         'GRADLE_USER_HOME and the SDKMAN shell init, and the verification expects SDKMAN, '
                         'Java and Gradle' % ', '.join(l.split()[-1] for l in log if l.startswith('install')))
                        if brought else ('SDKMAN asked for %s' % (', '.join(log) or 'nothing'))))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "toggle prerequisites"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a toggle whose app needs another toggle's tool does not bring it in" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the toggle prerequisites check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

# --- 4. the plan ---------------------------------------------------------------------------------
functions_text="$(sed -n '/^format_label()/,/^}/p;/^read_boolean_toggles()/,/^}/p;/^software_mapping_managers()/,/^}/p;/^toggle_prerequisite_entries()/,/^}/p;/^effective_toggle()/,/^}/p;/^brought_in_entries()/,/^}/p;/^prerequisite_notes()/,/^}/p' "${SETUP_SH}")"
labels_text="$(sed -n '/^declare -A LABEL_OVERRIDES=(/,/^)$/p' "${SETUP_SH}")"
excluded_text="$(grep -m1 '^EXCLUDED_VARS=' "${SETUP_SH}" || true)"
missing=()
for name in format_label read_boolean_toggles software_mapping_managers toggle_prerequisite_entries effective_toggle brought_in_entries prerequisite_notes; do
    grep -q "^${name}() {" <<<"${functions_text}" || missing+=("${name}")
done
if [[ ${#missing[@]} -gt 0 || -z "${labels_text}" || -z "${excluded_text}" ]]; then
    fail "setup.sh defines the functions that print the plan's prerequisite line" \
         "not found: ${missing[*]:-the label table or EXCLUDED_VARS}, so the plan cannot name what a toggle brings in"
    finish "toggle prerequisites"
fi

IFS=$'\n\t'
eval "${excluded_text}"
eval "${labels_text}"
eval "${functions_text}"
# Read by the functions eval'd out of setup.sh, which shellcheck cannot see.
# shellcheck disable=SC2034
ALL_VARS="${ANSIBLE_DIR}/group_vars/all.yaml"
# shellcheck disable=SC2034
OPT_PROFILE=""
# The state the checklist preloads, which these cases override, so a case that forgot a key reads false.
# shellcheck disable=SC2034
PRELOADED_KEYS=()
# shellcheck disable=SC2034
PRELOADED_ITEMS=()

plan_problems=()
plan_cases=0
for target in Debian:debian:yes Debian:ubuntu:yes RedHat:fedora:yes Archlinux:arch:no Archlinux:cachyos:no Darwin::no; do
    OS_FAMILY="${target%%:*}"
    rest="${target#*:}"
    OS_RELEASE_ID="${rest%%:*}"
    brings="${rest#*:}"
    for selection in "install_gradle=true install_java=false" "install_gradle=true install_java=true" "install_gradle=false install_java=false"; do
        plan_cases=$((plan_cases + 1))
        IFS=' ' read -r -a overrides <<<"${selection}"
        got="$(prerequisite_notes "${overrides[@]}")"
        expected=""
        [[ "${brings}" == yes && "${selection}" == "install_gradle=true install_java=false" ]] && expected="${EXPECTED_NOTE}"
        [[ "${got}" == "${expected}" ]] \
            || plan_problems+=("${OS_FAMILY} ${OS_RELEASE_ID:-without an ID}, ${selection}: printed [${got}], expected [${expected}]")
    done
done
# A defaults run passes no key=value line, so the preloaded group_vars state decides.
OS_FAMILY=Debian OS_RELEASE_ID=debian
# shellcheck disable=SC2034
PRELOADED_KEYS=(install_java install_gradle)
# shellcheck disable=SC2034
PRELOADED_ITEMS=(install_java Java OFF install_gradle Gradle ON)
got="$(prerequisite_notes)"
plan_cases=$((plan_cases + 1))
[[ "${got}" == "${EXPECTED_NOTE}" ]] || plan_problems+=("Debian, group_vars with install_java off and install_gradle on: printed [${got}]")

if [[ ${#plan_problems[@]} -eq 0 ]]; then
    pass "the plan names Java as brought in by Gradle on Debian, Ubuntu and Fedora with install_java off, and nowhere else, ${plan_cases} cases"
else
    fail "the plan names what a toggle brings in on exactly the systems the playbook brings it in on" "$(printf '%s; ' "${plan_problems[@]}")"
fi

non_interactive_text="$(sed -n '/^run_non_interactive()/,/^}/p' "${SETUP_SH}")"
interactive_text="$(sed -n '/^main_interactive()/,/^}/p' "${SETUP_SH}")"
confirm_text="$(sed -n '/^confirm_run()/,/^}/p' "${SETUP_SH}")"
print_text="$(sed -n '/^if \[\[ "${OPT_PRINT_COMMAND}" == true \]\]; then/,/^fi/p' "${SETUP_SH}")"
if grep -qE '^[[:space:]]*say_prerequisite_notes "\$\{OVERRIDE_VARS' <<<"${non_interactive_text}" \
        && grep -qE '^[[:space:]]*say_prerequisite_notes "\$\{OVERRIDE_VARS' <<<"${print_text}" \
        && grep -qE 'notes="\$\(prerequisite_notes "\$\{all_extra' <<<"${interactive_text}" \
        && grep -qE 'confirm_run "\$\{display_cmd\}" "\$\{notes\}"' <<<"${interactive_text}" \
        && grep -qE 'gum style .*"\$\{notes\}"' <<<"${confirm_text}"; then
    pass "the non-interactive run, --print-command and the interactive confirmation screen print the plan's prerequisite lines before the run"
else
    fail "every way into setup.sh prints the plan's prerequisite lines before the run" \
         "run_non_interactive, the --print-command block or main_interactive with confirm_run no longer passes the run's selection to the prerequisite lines"
fi

# The real wizard in this Debian container, the picked-apps run the owner chose the rule for.
rc=0
out="$(bash "${SETUP_SH}" --print-command --software none --enable install_gradle 2>&1 </dev/null)" || rc=$?
command_line="$(sed -n '$p' <<<"${out}")"
if [[ ${rc} -eq 0 ]] && grep -qxF "  >> ${EXPECTED_NOTE}" <<<"${out}" \
        && grep -q 'install_gradle=true' <<<"${command_line}" && grep -q 'install_java=false' <<<"${command_line}" \
        && grep -q 'ih_picked_apps=install_gradle' <<<"${command_line}"; then
    pass "setup.sh --print-command --software none --enable install_gradle on Debian names Java as brought in by Gradle before the command"
else
    fail "setup.sh --print-command --software none --enable install_gradle on Debian names Java as brought in by Gradle" \
         "exit ${rc}, output: $(tr '\n' ' ' <<<"${out}" | cut -c1-400)"
fi
rc=0
out="$(bash "${SETUP_SH}" --print-command --software none --enable install_gradle,install_java 2>&1 </dev/null)" || rc=$?
if [[ ${rc} -eq 0 ]] && ! grep -qF 'brought in by' <<<"${out}"; then
    pass "setup.sh --print-command with install_java picked as well names nothing as brought in"
else
    fail "setup.sh --print-command with install_java picked as well names nothing as brought in" \
         "exit ${rc}, output: $(tr '\n' ' ' <<<"${out}" | cut -c1-400)"
fi

finish "toggle prerequisites"
