#!/usr/bin/env bash
#
# Tier 1: every task that calls paru reads paru_available, and only one task file decides it.
#
# paru is built by arch_core and serves nothing but the Arch User Repository. Until 2026-10-10 that
# build was critical bootstrap with no rescue, and on a real CachyOS machine one failed
# "Build paru package (non-root)" ended the play before a single package was installed, pacman,
# flatpak and the npm tools included. The build is rescued now, and the run carries on, which is only
# safe if nothing afterwards calls a paru that is not there. Every consumer therefore reads one fact,
# paru_available, set by setup/ansible/tasks/paru_availability.yaml, and names its package as NOT
# installed when it is false.
#
# That is a convention, and a convention is exactly what the next consumer forgets: a new
# kewlfft.aur.aur task written the way the existing ones used to be works perfectly on every run where
# paru builds, and on the first one where it does not, it fails with "paru: command not found" in a
# role that may have no rescue, which is the defect this whole change removed. docs/regression_ledger.md defect class
# 2 is the other half: if a second place decides whether paru is usable, the playbook and the
# verification can disagree about why a package is missing.
#
# So this asserts, over every YAML file under setup/ansible:
#   1. every kewlfft.aur.aur task names `use: paru`, because there is no yay fallback by design;
#   2. every such task, and every command, shell or raw task that invokes `paru -`, has
#      paru_available in its `when`;
#   3. paru_available is set only by tasks/paru_availability.yaml, plus the arch_core rescue that
#      sets it false when the build fails;
#   4. arch_core and verify_install.yaml both include that task file;
#   5. every package a role installs through paru by name is in ih_role_aur_packages in
#      verify_install.yaml, the second, hand-written list the verification expects them from;
#   6. no task uses yay while install_yay still makes it optional, because the moment one does,
#      yay is required and must be built unconditionally.
# The consumer count is reported and must not be zero, so a rewrite that hides consumers from the
# parser fails here instead of passing over nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: every paru consumer reads paru_available, decided in one place"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "paru consumers"; }

require_python "every paru consumer reads paru_available, decided in one place" "paru consumers"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re

import yaml

ANSIBLE = pathlib.Path('setup') / 'ansible'
DECIDER = (ANSIBLE / 'tasks' / 'paru_availability.yaml').as_posix()
ARCH_CORE = (ANSIBLE / 'roles' / 'arch_core' / 'tasks' / 'main.yaml').as_posix()
VERIFY = (ANSIBLE / 'verify_install.yaml').as_posix()

AUR_MODULES = {'kewlfft.aur.aur', 'aur'}
SHELL_MODULES = {'ansible.builtin.command', 'ansible.builtin.shell', 'ansible.builtin.raw',
                 'command', 'shell', 'raw'}
PARU_CALL = re.compile(r'(^|[\s;&|(`])paru\s+-')
FACT = 'paru_available'

lines = []


def walk(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for item in node:
            yield from walk(item)


def when_text(task):
    cond = task.get('when')
    if isinstance(cond, str):
        return cond
    if isinstance(cond, list):
        return ' and '.join(str(c) for c in cond)
    return ''


def command_text(value):
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        argv = value.get('argv')
        if isinstance(argv, list):
            return ' '.join(str(a) for a in argv)
        return str(value.get('cmd', ''))
    return ''


consumers = 0
files_read = 0
setters = set()
includes = {ARCH_CORE: False, VERIFY: False}
role_packages = {}
parsed = []


def literal_packages(aur, shell):
    """The literal package names a paru call installs, or nothing when they come from a template."""
    if aur is not None:
        name = aur.get('name') if isinstance(aur, dict) else None
        names = name if isinstance(name, list) else [name]
        return [n for n in names if isinstance(n, str) and '{{' not in n]
    words = command_text(shell).split()
    found = []
    for index, word in enumerate(words):
        if word == 'paru' and index + 1 < len(words) and words[index + 1].startswith('-S'):
            found += [w for w in words[index + 2:] if not w.startswith('-') and '{{' not in w]
            break
    return found

for path in sorted(ANSIBLE.rglob('*.yaml')):
    try:
        doc = yaml.safe_load(path.read_text(encoding='utf-8'))
    except (yaml.YAMLError, UnicodeDecodeError):
        continue
    files_read += 1
    where = path.as_posix()
    parsed.append((where, doc))
    for task in walk(doc):
        if not isinstance(task.get('name'), str):
            continue
        label = '%s :: %s' % (where, task['name'])

        set_fact = task.get('ansible.builtin.set_fact', task.get('set_fact'))
        if isinstance(set_fact, dict) and FACT in set_fact:
            setters.add(where)

        for key in ('ansible.builtin.include_tasks', 'include_tasks',
                    'ansible.builtin.import_tasks', 'import_tasks'):
            target = task.get(key)
            if isinstance(target, dict):
                target = target.get('file', '')
            if isinstance(target, str) and target.endswith('tasks/paru_availability.yaml') \
                    and where in includes:
                includes[where] = True

        aur = next((task[k] for k in AUR_MODULES if k in task), None)
        shell = next((task[k] for k in SHELL_MODULES if k in task), None)
        calls_paru = aur is not None or bool(PARU_CALL.search(command_text(shell)))
        if not calls_paru:
            continue
        consumers += 1

        if aur is not None and (not isinstance(aur, dict) or aur.get('use') != 'paru'):
            lines.append('FAIL %s installs from the Arch User Repository without `use: paru`, and '
                         'there is no fallback helper by design, so it would call a helper nothing '
                         'decides is available' % label)
        if FACT not in when_text(task):
            lines.append('FAIL %s calls paru and its `when` does not read %s, so a run whose paru '
                         'build failed calls a paru that is not there instead of reporting the '
                         'package as NOT installed' % (label, FACT))
        if '/roles/' in where:
            for package in literal_packages(aur, shell):
                role_packages[package] = label

# --- 5. every package a role installs through paru is one the verification expects ----------------
# verify_install.yaml expects mapped Arch User Repository packages through the software mapping, and
# the ones a role installs by name through a second, hand-written list, ih_role_aur_packages. A role
# that starts installing another package through paru and is not added there is never verified, and
# a run that skipped it for a missing paru would not name it.
verify_text = pathlib.Path(VERIFY).read_text(encoding='utf-8')
listed_block = re.search(r'ih_role_aur_packages:(.*?)\n\s*-\s+name:', verify_text, re.S)
listed = set(re.findall(r"'package':\s*'([^']+)'", listed_block.group(1) if listed_block else ''))
if not listed:
    lines.append('FAIL %s no longer names any package in ih_role_aur_packages, so this check cannot '
                 'compare it with the roles' % VERIFY)
for package, label in sorted(role_packages.items()):
    if package not in listed:
        lines.append('FAIL %s installs %s through paru and ih_role_aur_packages in %s does not name it, '
                     'so the verification never expects it and a run that skipped it reports nothing'
                     % (label, package, VERIFY))
if not role_packages:
    lines.append('FAIL no role installs a named package through paru, so the comparison with '
                 'ih_role_aur_packages proved nothing. Either the parser lost them or the list in %s is '
                 'now dead and should go' % VERIFY)

# --- 6. yay stays optional only while nothing uses it --------------------------------------------
# The owner's rule, recorded on 2026-10-10: nothing uses yay today, so it is optional behind
# install_yay, off by default. The moment any task uses yay, through `use: yay`, a `yay -S` or a
# `which yay` it depends on, yay is required: install_yay must be removed from the selectable toggles
# and arch_core must build yay unconditionally. The tasks inside the arch_core block that builds yay
# are the builder, not users, and are left out.
YAY_CALL = re.compile(r'(^|[\s;&|(`])yay(\s|$)')
YAY_BUILDER = 'Build and install yay'
toggle_files = sorted((ANSIBLE / 'group_vars').glob('*.yaml')) + sorted((ANSIBLE / 'profiles').glob('*.yaml'))
yay_toggle_in = [f.as_posix() for f in toggle_files
                 if re.search(r'^install_yay:', f.read_text(encoding='utf-8'), re.M)]
yay_users = []
builder_gated = False
for where, doc in parsed:
    builder_ids = set()
    for node in walk(doc):
        if node.get('name') == YAY_BUILDER and 'block' in node:
            builder_ids |= {id(inner) for inner in walk(node.get('block'))}
            builder_gated = builder_gated or 'install_yay' in when_text(node)
    for task in walk(doc):
        if id(task) in builder_ids or not isinstance(task.get('name'), str):
            continue
        aur = next((task[k] for k in AUR_MODULES if k in task), None)
        shell = next((task[k] for k in SHELL_MODULES if k in task), None)
        if (isinstance(aur, dict) and aur.get('use') == 'yay') or YAY_CALL.search(command_text(shell)):
            yay_users.append('%s :: %s' % (where, task['name']))
if yay_users and (yay_toggle_in or builder_gated):
    lines.append('FAIL %s uses yay, and yay is still optional: install_yay is declared in %s%s. The '
                 'rule is that nothing may use yay while it is optional. Once a task uses it, yay is '
                 'required, so remove install_yay from group_vars, the profiles, the wizard label and '
                 'documented_no_ops.txt, and remove the install_yay condition from the "%s" block in '
                 'roles/arch_core/tasks/main.yaml so yay is always built on the Arch family'
                 % ('; '.join(yay_users), ', '.join(yay_toggle_in) or 'no file',
                    ', and the arch_core build is gated on it' if builder_gated else '', YAY_BUILDER))

if not files_read:
    print('FAIL no YAML file under setup/ansible could be read, so this check proves nothing')
    raise SystemExit(0)

if consumers == 0:
    lines.append('FAIL no paru consumer was found at all, so this check proves nothing. Either paru '
                 'is no longer used, in which case retire this check, or the parser lost them')

unexpected = sorted(s for s in setters if s not in (DECIDER, ARCH_CORE))
if unexpected:
    lines.append('FAIL %s is set outside %s and the arch_core rescue, in %s, which is a second place '
                 'deciding whether paru is usable' % (FACT, DECIDER, ', '.join(unexpected)))
if DECIDER not in setters:
    lines.append('FAIL %s does not set %s, so every consumer reads a fact nothing decides'
                 % (DECIDER, FACT))

for where, found in sorted(includes.items()):
    if not found:
        lines.append('FAIL %s does not include tasks/paru_availability.yaml, so it decides paru '
                      'availability some other way or not at all' % where)

if not lines:
    lines.append('OK %d paru consumers across %d files all read %s, only %s decides it, and the %d '
                 'packages roles install through paru by name are all expected by the verification'
                 % (consumers, files_read, FACT, DECIDER, len(role_packages)))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "paru consumers"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "an AUR helper is used against the paru or yay rules" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the paru consumer check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "paru consumers"
