#!/usr/bin/env bash
#
# Tier 1: a PolicyKit rule names the administrator group through os_dict, never as a literal.
#
# The hibernation rule linux_security writes allowed subject.isInGroup("sudo"). Arch, CachyOS and
# Fedora have no group sudo, their administrators are in wheel, so the rule never matched there
# (docs/regression_ledger.md 10.295). The group is a per-distribution fact, so it lives in
# vars/<family>.yaml as admin_group, rule 1 of setup/ansible/AGENTS.md.
#
# So this asserts, over every file under setup/ansible:
#   1. every isInGroup( argument is a Jinja expression that reads a key of os_dict, never a quoted
#      group name.
#   2. every Linux family dictionary, vars/<family>.yaml apart from Darwin and Windows, defines each
#      key those expressions read as a non-empty string. linux_security runs on Linux only.
# The count of isInGroup calls is reported and must not be zero, so a rule that moved where this
# check does not look fails here instead of passing over nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: a PolicyKit rule reads the administrator group from os_dict"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "polkit admin group"; }

require_python "a PolicyKit rule reads the administrator group from os_dict" "polkit admin group"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re

import yaml

ANSIBLE = pathlib.Path('setup') / 'ansible'
NOT_LINUX = {'Darwin', 'Windows'}
CALL = re.compile(r'isInGroup\(\s*([^)]*?)\s*\)')
OPEN, CLOSE, PREFIX = '"{{', '}}"', 'os_dict.'


def os_dict_key(argument):
    if not (argument.startswith(OPEN) and argument.endswith(CLOSE)):
        return None
    inner = argument[len(OPEN):-len(CLOSE)].strip()
    key = inner[len(PREFIX):] if inner.startswith(PREFIX) else ''
    return key if key.isidentifier() else None


lines = []
calls = 0
keys = set()
for path in sorted(p for p in ANSIBLE.rglob('*') if p.is_file()):
    try:
        text = path.read_text(encoding='utf-8')
    except (UnicodeDecodeError, OSError):
        continue
    for number, line in enumerate(text.splitlines(), 1):
        for argument in CALL.findall(line):
            calls += 1
            key = os_dict_key(argument)
            if key:
                keys.add(key)
            else:
                lines.append('FAIL %s:%d calls isInGroup(%s), which is not "{{ os_dict.<key> }}". The group '
                             'differs between distributions, sudo on Debian lineage and wheel on Arch and '
                             'Fedora, so it belongs in vars/<family>.yaml' % (path.as_posix(), number, argument))

if not calls:
    print('FAIL no isInGroup call was found under setup/ansible, so this check proved nothing. Either the '
          'hibernation rule moved where this check does not look or the reader lost it')
    raise SystemExit(0)

families = sorted(p for p in (ANSIBLE / 'vars').glob('*.yaml') if p.stem not in NOT_LINUX)
if not families:
    lines.append('FAIL no Linux family dictionary was found under setup/ansible/vars')
for path in families:
    try:
        family = yaml.safe_load(path.read_text(encoding='utf-8')) or {}
    except yaml.YAMLError as exc:
        lines.append('FAIL %s does not parse: %s' % (path.as_posix(), exc))
        continue
    for key in sorted(keys):
        value = family.get(key)
        if not isinstance(value, str) or not value.strip():
            lines.append('FAIL %s has no %s, which a PolicyKit rule reads through os_dict, so the rule would '
                         'not render on that family' % (path.as_posix(), key))

if not lines:
    lines.append('OK %d isInGroup call(s) read %s through os_dict, and the %d Linux family dictionaries %s '
                 'define it' % (calls, ', '.join(sorted(keys)), len(families),
                                ', '.join(p.stem for p in families)))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "polkit admin group"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a PolicyKit rule does not read the administrator group from os_dict" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the PolicyKit group check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "polkit admin group"
