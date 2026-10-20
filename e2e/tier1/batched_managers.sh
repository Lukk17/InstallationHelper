#!/usr/bin/env bash
#
# Tier 1: no package manager installs its whole set in one call.
#
# A batch is a single call with a single exit code. So when one package in it is unavailable, the call
# fails, and everything upstream hears that the install failed with no way to know which package
# broke, how many installed before it, or how many were never attempted.
#
# That cost this repository the entire set three times in four days:
#
#   a flatpak fetch timing out          twenty-two applications lost, on twenty of forty-eight cells
#   a deleted Tor Browser build         roughly thirty Homebrew casks lost, twice in two days
#   one Chocolatey package failing      every package in the batch reported failed
#
# For a while apt, dnf and pacman were allowed to batch, on the argument that their solvers work on
# the whole set. Both halves of that argument were tested and neither survived.
#
# The speed half was measured on 2026-08-25 in debian:trixie, twenty-two packages taken from the real
# Debian mapping, two samples each way, with apt-get update run in both and not timed:
#
#   no recommends       batched 250s and 199s        looped 278s and 244s
#   with recommends     batched 274s                 looped 264s
#
# Both shapes ended with identical package counts. Looping cost eleven and twenty-three per cent on
# the first set and saved four per cent on the second, while two identical batched runs of the first
# set differed from each other by twenty per cent. The noise is the same size as the effect, and the
# absolute figure is tens of seconds inside a scenario that runs thirty to a hundred minutes.
#
# The correctness half was real: a single solve cannot pick a library version or a virtual-package
# provider that a later package rejects, and a loop can. That is now answered where it belongs, by a
# guard. Each family asks its own package manager after the installs whether the set it produced is
# consistent, `apt-get check`, `dnf check --dependencies` and `pacman -Dk`, and names what is broken.
# A batch hid that question. A guard answers it.
#
# So there is no allowlist any more. There used to be a file of exceptions with reasons, and a file of
# exceptions is an invitation to add the next one.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: no manager installs its whole set in one call"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "batched managers"; }

DISPATCH="setup/ansible/roles/software_installer/tasks/dynamic_install.yaml"

if [[ ! -f "${DISPATCH}" ]]; then
    fail "the software installer dispatcher is missing, so this check proves nothing" "${DISPATCH}"
    finish "batched managers"
    return 0 2>/dev/null || exit 0
fi

require_python "no manager installs its whole set in one call" "batched managers"

report_status=0
report="$("${PYTHON}" - "${DISPATCH}" <<'PYEOF'
import json
import pathlib
import re
import sys

import yaml

dispatch = pathlib.Path(sys.argv[1])
text = dispatch.read_text(encoding='utf-8')
SHARED = pathlib.Path('setup/ansible/tasks/install_role_packages.yaml')
SHARED_INSTALL = re.compile(r'pacman\s+-S[a-z]*\s|apt-get\s+install|apt\s+install|dnf\s+install')

# Managers are read out of the file rather than listed here, so one added tomorrow is covered without
# anybody remembering to add it. Three shapes exist: a prebuilt list, a list filtered inline out of
# the package set, and a list an earlier set_fact derived and named after the manager.
managers = set(re.findall(r'software_installer_batches\.([a-z_]+)', text))
managers |= set(re.findall(r"selectattr\(\s*'value\.manager'\s*,\s*'equalto'\s*,\s*'([a-z_]+)'", text))
managers = sorted(managers)

if not managers:
    print('FAIL the dispatcher names no package managers, so this check proves nothing')
    raise SystemExit(0)


def leaf_tasks(node):
    """Every task mapping that is not a block. A block contains every task inside it."""
    if isinstance(node, dict):
        if any(k in node for k in ('block', 'rescue', 'always')):
            for value in node.values():
                yield from leaf_tasks(value)
            return
        yield node
        for value in node.values():
            yield from leaf_tasks(value)
    elif isinstance(node, list):
        for item in node:
            yield from leaf_tasks(item)


try:
    tasks = list(leaf_tasks(yaml.safe_load(text)))
except yaml.YAMLError as exc:
    print('FAIL the dispatcher does not parse as YAML, so this check proves nothing: %s' % exc)
    raise SystemExit(0)

lines = []
for manager in managers:
    needles = ['software_installer_batches.%s' % manager,
               "'equalto', '%s'" % manager]
    # A list a set_fact derives from the manager's mapping first, such as dnf_url_locations, is read by
    # the include of the shared install file under the fact's own name.
    derived = []
    for task in tasks:
        facts = next((v for k, v in task.items() if k == 'set_fact' or k.endswith('.set_fact')), None)
        if isinstance(facts, dict) and any(n in json.dumps(task, default=str) for n in needles[1:]):
            derived += list(facts)

    installers = []
    for task in tasks:
        if not isinstance(task.get('name'), str):
            continue
        if any(k == 'set_fact' or k.endswith('.set_fact') for k in task):
            continue
        # A debug only reports, so it cannot install anything, whatever list its message reads.
        if any(k == 'debug' or k.endswith('.debug') for k in task):
            continue
        # changed_when: false is this repository declaring a task read-only. A query is not an
        # install and must not be judged as one, which is what keeps the new consistency guards out
        # of this comparison.
        if task.get('changed_when') is False:
            continue
        body = json.dumps({k: v for k, v in task.items()
                           if k not in ('when', 'name', 'tags', 'loop_control')}, default=str)
        body = re.sub(r'\s+', ' ', body)
        loop_text = json.dumps(task.get('loop', ''), default=str)
        includes_shared = SHARED.name in body
        if any(re.sub(r'\s+', ' ', n) in body for n in needles) or manager in loop_text \
                or (includes_shared and any(name in body for name in derived)):
            installers.append(task)

    if not installers:
        lines.append('SKIP %s is named in the dispatcher and no task installs from it' % manager)
        continue

    # A manager may hand its list to setup/ansible/tasks/install_role_packages.yaml, the file the roles
    # install through, which pacman's does since 2026-10-15 so the rule for when pacman refreshes its
    # index lives in one place. An include has no loop of its own, so the file it names is read
    # instead, and every install command in it must loop.
    handed_over = []
    for t in installers:
        if 'loop' in t or 'with_items' in t:
            continue
        included = next((str(v.get('file', '') if isinstance(v, dict) else v) for k, v in t.items()
                         if k.split('.')[-1] in ('include_tasks', 'import_tasks')), None)
        if included is None or not included.endswith(SHARED.name):
            handed_over.append(t)
            continue
        if not SHARED.is_file():
            handed_over.append(t)
            continue
        shared_batches = [s['name'] for s in leaf_tasks(yaml.safe_load(SHARED.read_text(encoding='utf-8')))
                          if isinstance(s.get('name'), str) and 'loop' not in s and 'with_items' not in s
                          and SHARED_INSTALL.search(json.dumps(s, default=str))]
        if shared_batches:
            handed_over.append(dict(t, name='%s, through %s, whose %s'
                                    % (t['name'], SHARED.as_posix(), ', '.join(shared_batches))))
    if handed_over:
        names = ', '.join(t['name'] for t in handed_over)
        lines.append('FAIL %s hands its whole set to one call. One failure there loses every package '
                     'in the set and nothing can say which one broke. Loop it. Task(s): %s'
                     % (manager, names))
    else:
        lines.append('OK %s installs one package at a time' % manager)

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "batched managers"

# --- every other task under setup/ansible, roles included ----------------------------------------
# The dispatcher was looped and the roles were not. "Install Docker (Arch)" in virtualization_config
# handed docker, docker-buildx, docker-compose and iptables to one community.general.pacman call, and
# on 2026-10-15 the cachyos defaults scenario lost all four because one mirror answered 404 for one
# dependency, containerd, of one of them. docs/regression_ledger.md has the entry. So every task file is
# read: a package module (pacman, apt, dnf, package, yum, homebrew, flatpak, snap) given a literal list
# of more than one name, or a comma-separated name, with no loop, and a command, shell or raw whose
# install verb (pacman -S, apt-get install, apt install, dnf install, yay -S, paru -S, brew install,
# flatpak install, snap install, and sdkmanager, whose packages follow the command itself) is followed by
# more than one package. sdkmanager handed platforms, build-tools and platform-tools to one call until
# 2026-10-20, and one bad Platform-Tools download failed the Pop!_OS KDE configure cell of sweep run
# 39260381281 with nothing able to say the other two had installed. A template counts as one package
# only when it names item, so {{ apt_raw_flags }} is not mistaken for one. A removal is not an install.
#
# A package module whose name is a template is read too, because a template can build the list the
# literal check cannot see: "{{ ['git', 'base-devel'] + ... }}" for the paru build, a list derived from
# the installed kernels for the DKMS headers, "{{ ['kernel-devel', 'kernel-headers'] }}" for OpenRazer
# on Fedora. All three batched unseen until 2026-10-15. A template that builds a list literal, ends in
# `| list`, or names a variable whose definition in the task's own vars does either, counts as a batch.
# A template that yields one name, such as the GNOME metapackage chosen by distribution, does not.
# The same goes for a command: a template after the install verb that joins a list, such as
# `pacman -S {{ role_packages | join(' ') }}`, is a batch the literal reading cannot see, measured on
# 2026-10-15 by planting exactly that in a copy of install_role_packages.yaml, which this section
# then passed.
#
# Twenty-seven role tasks batched when this was extended to the roles, and they were listed in a file
# of pending tasks while the owner decided. The decision was to convert every one, and they now go
# through setup/ansible/tasks/install_role_packages.yaml, one package per call. The file went with
# them, and this check is back to having no allowance file. The CachyOS 32-bit graphics alignment was
# the last exception, written into this check while the owner decided, and it went on 2026-10-15 once
# two calls were measured in cachyos/cachyos-v3 to work in either order, each rc 0 with `pacman -Dk`
# clean. There is no exception now, and none is to be added.
role_status=0
role_report="$("${PYTHON}" - setup/ansible <<'PYEOF'
import pathlib
import re
import sys

import yaml

root = pathlib.Path(sys.argv[1])

MODULES = {'pacman', 'community.general.pacman', 'apt', 'ansible.builtin.apt', 'dnf',
           'ansible.builtin.dnf', 'package', 'ansible.builtin.package', 'yum', 'ansible.builtin.yum',
           'homebrew', 'community.general.homebrew', 'homebrew_cask', 'community.general.homebrew_cask',
           'flatpak', 'community.general.flatpak', 'snap', 'community.general.snap'}
SHELLS = {'command', 'ansible.builtin.command', 'shell', 'ansible.builtin.shell', 'raw',
          'ansible.builtin.raw'}
INSTALL = re.compile(r'(pacman\s+-S[a-z]*|apt-get\s+install|apt\s+install|dnf\s+install|yay\s+-S[a-z]*'
                     r'|paru\s+-S[a-z]*|brew\s+install|flatpak\s+install|snap\s+install|sdkmanager)(?=\s|$)')
END_OF_COMMAND = re.compile(r'\n|\||&&|;|\d*[<>]|\$\(')
TOKEN = re.compile(r'"?\{\{.*?\}\}"?|"[^"\n]*"|\'[^\'\n]*\'|\S+')
PURE_TEMPLATE = re.compile(r'^["\']?\{\{.*\}\}["\']?$')


def tasks(node):
    if isinstance(node, dict):
        if any(k in node for k in ('block', 'rescue', 'always')):
            for k in ('block', 'rescue', 'always'):
                yield from tasks(node.get(k))
            return
        yield node
    elif isinstance(node, list):
        for item in node:
            yield from tasks(item)


def command_batches(text):
    text = text.replace('\\\n', ' ')
    # A template's own filter pipe is not a shell pipe, so each template is set aside before the
    # command is cut at the first shell operator, and put back in its token afterwards.
    templates = re.findall(r'\{\{.*?\}\}', text)
    for index, template in enumerate(templates):
        text = text.replace(template, '\x00%d\x00' % index, 1)
    # A semicolon inside quotes is part of an argument, not the end of the command: sdkmanager names
    # its packages "platforms;android-36" and "build-tools;36.0.0".
    text = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', lambda m: m.group(0).replace(';', '\x01'), text)
    found = []
    for match in INSTALL.finditer(text):
        rest = END_OF_COMMAND.split(text[match.end():])[0]
        rest = re.sub('\x00(\\d+)\x00', lambda m: templates[int(m.group(1))], rest).replace('\x01', ';')
        tokens = TOKEN.findall(rest)
        joined = [t for t in tokens if '{{' in t and re.search(r'\|\s*join\b', t)]
        if joined:
            found.append(['the list joined by %s' % joined[0].strip('"')])
            continue
        names = [t for t in tokens
                 if not t.startswith('-') and (not PURE_TEMPLATE.match(t) or 'item' in t)]
        if match.group(1).startswith('flatpak') and len(names) > 1:
            names = names[1:]
        if len(names) > 1:
            found.append(names)
    return found


LIST_TEMPLATE = re.compile(r'\[[^\]]*,[^\]]*\]|\|\s*list\b')


def builds_a_list(template, task_vars):
    template = template.strip()
    inner = template[2:-2].strip() if template.startswith('{{') and template.endswith('}}') else ''
    named = task_vars.get(inner) if inner.isidentifier() else None
    if isinstance(named, list):
        return len(named) > 1
    if isinstance(named, str):
        template = named
    return bool(LIST_TEMPLATE.search(template))


def batches_of(task):
    if 'loop' in task or 'with_items' in task:
        return []
    found = []
    task_vars = task.get('vars') if isinstance(task.get('vars'), dict) else {}
    for key, value in task.items():
        if key in MODULES and isinstance(value, dict) and value.get('state') != 'absent':
            name = value.get('name', value.get('pkg'))
            if isinstance(name, list) and len(name) > 1:
                found.append([str(n) for n in name])
            elif isinstance(name, str) and '{{' not in name and ',' in name:
                found.append(name.split(','))
            elif isinstance(name, str) and '{{' in name and builds_a_list(name, task_vars):
                found.append(['the list built by %s' % name.strip()])
        if key in SHELLS:
            text = value if isinstance(value, str) else (
                (value.get('cmd') or value.get('_raw_params') or '') if isinstance(value, dict) else '')
            found.extend(command_batches(str(text)))
    return found


lines = []
read = 0
for path in sorted(root.rglob('*.yaml')):
    try:
        doc = yaml.safe_load(path.read_text(encoding='utf-8'))
    except (yaml.YAMLError, UnicodeDecodeError):
        continue
    for task in tasks(doc):
        if not isinstance(task, dict) or not isinstance(task.get('name'), str):
            continue
        read += 1
        for names in batches_of(task):
            label = '%s :: %s' % (path.as_posix(), task['name'])
            if len(names) == 1:
                lines.append('FAIL %s hands %s to one call, so one unavailable package loses them all. '
                             'Install them one at a time through setup/ansible/tasks/'
                             'install_role_packages.yaml.' % (label, names[0]))
                continue
            lines.append('FAIL %s hands %s to one call, so one unavailable package loses all %d. '
                         'Install them one at a time through setup/ansible/tasks/'
                         'install_role_packages.yaml, or for a manager it does not serve, such as '
                         'sdkmanager, with a loop of one package per call.'
                         % (label, ', '.join(names), len(names)))

if not read:
    print('FAIL no task was read under %s, so this check proves nothing' % root.as_posix())
    raise SystemExit(0)
if not lines:
    lines.append('OK no task outside the dispatcher hands several packages to one call (%d tasks read)'
                 % read)
print('\n'.join(lines))
PYEOF
)" || role_status=$?
assert_python_ran "${role_status}" "batched managers"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a task outside the dispatcher installs several packages in one call" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the batched task check printed something unexpected" "${line}" ;;
    esac
done <<<"${role_report}"

# --- the manual install scripts under docs/manual ------------------------------------------------
# docs/manual/<os>/install.sh and docs/manual/windows/install.ps1 are the by-hand route to the same
# software set, and until 2026-10-15 four of the five handed each package manager its whole list in one
# call under `set -euo pipefail`. Measured that day in homebrew/brew: `brew install hello dart` printed
# `No available formula with the name "dart"`, exited 1 and left no hello, so one bad name in the macOS
# script installed nothing at all (docs/regression_ledger.md 10.25). So every install call in those
# scripts is read, whatever wraps it: an install verb followed by more than one package, or by a list
# expanded in place ("${LIST[@]}" in shell, @list in PowerShell), fails. A line whose command is printf,
# echo, log or Write-Host only prints an instruction, and a $( ) subexpression counts as one argument.
# There is no allowance file. The CachyOS mesa replacement was the one call that looked as if it had to
# stay a transaction, and it was measured in cachyos/cachyos-v3 to work as two calls, mesa-git first.
MANUAL_DIR="${REPO_ROOT}/docs/manual"
manual_status=0
manual_report="$("${PYTHON}" - "${MANUAL_DIR}" <<'PYEOF'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
scripts = sorted(root.glob('*/install.sh')) + sorted(root.glob('*/install.ps1'))
pages = sorted(root.rglob('*.md'))
if not scripts:
    print('FAIL no install.sh or install.ps1 was found under %s, so this check proves nothing' % root.as_posix())
    raise SystemExit(0)

INSTALL = re.compile(r'(?<![\w-])(pacman\s+-S[a-z]*|apt-get\s+install|apt\s+install|dnf\s+install'
                     r'|yum\s+install|yay\s+-S[a-z]*|paru\s+-S[a-z]*|brew\s+install|flatpak\s+install'
                     r'|snap\s+install|rpm\s+(?:-i|--install)|choco\s+install|winget\s+install)(?=\s|$)')
# Options whose next word is their value rather than a package: winget's --scope machine and --source
# msstore in the Windows guide, apt's -o Dpkg::..., pacman's --overwrite. --id is not here, because
# its value is the package.
VALUE_OPTIONS = {'--scope', '--source', '-s', '--version', '-v', '--override', '--location',
                 '--architecture', '-o', '--overwrite', '--channel'}
SEGMENT = re.compile(r'\|\||&&|;|\|')
END_OF_ARGUMENTS = re.compile(r'\d*[<>]')
PRINTERS = {'printf', 'echo', 'log', 'Write-Host', 'Write-Step', 'Write-Output'}
LIST_EXPANSION = re.compile(r'\[[@*]\]|^"?@[A-Za-z_]')


def collapse_subexpressions(text):
    """Replace every balanced $( ... ) with one placeholder, so its inside is one argument."""
    out, i = [], 0
    while i < len(text):
        if text.startswith('$(', i):
            depth, j = 1, i + 2
            while j < len(text) and depth:
                depth += {'(': 1, ')': -1}.get(text[j], 0)
                j += 1
            out.append('SUBEXPRESSION')
            i = j
        else:
            out.append(text[i])
            i += 1
    return ''.join(out)


INLINE_CODE = re.compile(r'`([^`\n]+)`')


def logical_lines(path):
    """(line number, command line) for a script, and for a page every line of a fenced block and every
    inline code span outside one, which is where the guides put a command a reader copies."""
    text = path.read_text(encoding='utf-8')
    if path.suffix == '.md':
        fenced = False
        for number, line in enumerate(text.split('\n'), 1):
            stripped = line.strip()
            if stripped.startswith('```'):
                fenced = not fenced
                continue
            if fenced:
                if stripped and not stripped.startswith('#'):
                    yield number, collapse_subexpressions(stripped)
                continue
            for span in INLINE_CODE.findall(line):
                yield number, collapse_subexpressions(span.replace('\\|', '|'))
        return
    if path.suffix == '.ps1':
        text = re.sub(r'<#.*?#>', lambda m: '\n' * m.group(0).count('\n'), text, flags=re.S)
        text = text.replace('`\n', ' \n')
    else:
        text = text.replace('\\\n', ' \n')
    for number, line in enumerate(text.split('\n'), 1):
        stripped = line.strip()
        if stripped and not stripped.startswith('#'):
            yield number, collapse_subexpressions(stripped)


lines = []
for script in scripts + pages:
    label = script.relative_to(root.parent.parent).as_posix()
    calls = 0
    batched = 0
    for number, line in logical_lines(script):
        for segment in SEGMENT.split(line):
            words = segment.split()
            if not words or words[0] in PRINTERS or words[0][0] in '\'"':
                continue
            for match in INSTALL.finditer(segment):
                calls += 1
                rest = END_OF_ARGUMENTS.split(segment[match.end():])[0]
                words = rest.split()
                names = [w for i, w in enumerate(words) if not w.lstrip('"\'').startswith('-')
                         and not (i and words[i - 1] in VALUE_OPTIONS)]
                if match.group(1).startswith('flatpak') and len(names) > 1:
                    names = names[1:]
                if len(names) > 1 or any(LIST_EXPANSION.search(n) for n in names):
                    batched += 1
                    lines.append('FAIL %s:%d hands %s to one %s call, so one package that fails loses all '
                                 'of them. Loop it, one package per call: %s'
                                 % (label, number, ' '.join(names), match.group(1).split()[0],
                                    segment.strip()))
    if not calls and script.suffix != '.md':
        lines.append('FAIL %s has no install call this check recognises, so it proves nothing about it'
                     % label)
    elif not calls:
        continue
    elif not batched:
        lines.append('OK %s installs one package per call (%d install calls read)' % (label, calls))
print('\n'.join(lines))
PYEOF
)" || manual_status=$?
assert_python_ran "${manual_status}" "batched managers"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a manual install script installs several packages in one call" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the manual install script check printed something unexpected" "${line}" ;;
    esac
done <<<"${manual_report}"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        SKIP*) skip "every manager installs one package at a time" "${line#SKIP }" ;;
        FAIL*) fail "a manager installs its whole set in one call" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the batched manager check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "batched managers"
