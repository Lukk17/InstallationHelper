#!/usr/bin/env bash
#
# Tier 1: nothing splats an array into a PowerShell command.
#
# PowerShell has two splat forms and they do completely different things. A hashtable splat binds by
# NAME, which is what everyone thinks they are writing. An array splat supplies POSITIONAL arguments:
# the strings keep their leading dashes and are handed to the parameters in declaration order.
#
# So this, which reads like a correct command line:
#
#   $psArgs = @('-NonInteractive', '-AllowAdministrator', '-Software', 'all')
#   & ./setup/setup.ps1 @psArgs
#
# binds "-NonInteractive" to the first positional parameter and "-AllowAdministrator" to the second.
# In the wizard those are $Profile and $Software, and $Software carries a ValidateSet, so the run
# died in sixteen seconds with an error that named neither switch:
#
#   Cannot validate argument on parameter 'Software'. The argument "-AllowAdministrator" does not
#   belong to the set "defaults,all,none" specified by the ValidateSet attribute.
#
# That is from run 32762695978, the first time anybody dispatched the manual workflow at its Windows
# target. The matrix workflow never hit it because it passes its arguments inline. So the defect sat
# in a dispatch path nothing exercised, which is exactly the kind this gate exists to find without
# waiting for someone to try it.
#
# The rule is mechanical: if a variable is assigned an array literal and that same variable is later
# splatted, that is the broken form. A hashtable literal is fine, an array used as a plain argument
# is fine, and a splat of something this check cannot see the assignment for is reported as
# unproven rather than passed.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: nothing splats an array into a PowerShell command"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "PowerShell splats"; }

report="$("${PYTHON:-python}" - <<'PYEOF'
import pathlib
import re

# Both places PowerShell is written here: the wizard and its modules, and the workflow steps that
# drive them. A workflow is not a .ps1 file, so an abstract syntax tree cannot reach it, and this is
# a text rule that reads the same in both.
targets = sorted(pathlib.Path('setup').rglob('*.ps1'))
targets += sorted(pathlib.Path('.github/workflows').glob('*.yml'))
targets += sorted(pathlib.Path('.github/workflows').glob('*.yaml'))
targets += sorted(pathlib.Path('e2e').rglob('*.ps1'))

assign_array = re.compile(r'\$(\w+)\s*=\s*@\(')
assign_hash = re.compile(r'\$(\w+)\s*=\s*@\{')
splat = re.compile(r'(?<![\w$])@(\w+)\b')

checked = 0
offenders = []
splats_seen = 0

for path in targets:
    try:
        text = path.read_text(encoding='utf-8')
    except (OSError, UnicodeDecodeError):
        continue
    checked += 1

    arrays = set(assign_array.findall(text))
    hashes = set(assign_hash.findall(text))

    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if stripped.startswith('#'):
            continue
        for name in splat.findall(line):
            # An @ before a word is only a splat when it is an argument. In a here-string terminator
            # or an email address it is not, and neither of those carries a name this repository
            # also assigns to.
            if name not in arrays and name not in hashes:
                continue
            splats_seen += 1
            if name in arrays and name not in hashes:
                offenders.append('%s:%d splats $%s, which is assigned an array literal, so its '
                                 'arguments bind by position rather than by name'
                                 % (path.as_posix(), line_no, name))

if checked == 0:
    print('FAIL no PowerShell or workflow file was read, so this check proves nothing')
elif splats_seen == 0:
    print('SKIP %d file(s) read and none of them splats anything, so nothing was proven' % checked)
elif offenders:
    print('FAIL ' + ' | '.join(offenders))
else:
    print('OK %d splat(s) across %d file(s), every one of them a hashtable' % (splats_seen, checked))
PYEOF
)"

case "${report}" in
    OK*)   pass "${report#OK }" ;;
    SKIP*) skip "every splat binds by name" "${report#SKIP }" ;;
    *)     fail "an array is splatted into a PowerShell command, so its arguments bind by position" \
                "${report#FAIL }" ;;
esac

finish "PowerShell splats"
