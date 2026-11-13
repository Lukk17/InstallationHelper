#!/usr/bin/env bash
#
# Tier 1: the "Run records" table of e2e/README_E2E.md names every file a tier 3 run directory holds,
# and nothing else.
#
# The table named five of the files e2e/tier3/container.sh writes into a run directory, and fourteen
# more had no row, docs/regression_ledger.md 10.297. So this reads every path container.sh writes
# under ${RUN_DIR}/, resolves a ${name} after it through the `for name in ...` loop that sets it, and
# requires a row for each, and a file for each row. A path whose variable it cannot resolve fails,
# and so does finding no path or no row, because a reader that stopped finding them would otherwise
# pass over nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: the Run records table names every file of a tier 3 run directory"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "run records table"; }

require_python "the Run records table names every file of a tier 3 run directory" "run records table"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re

CONTAINER = pathlib.Path('e2e') / 'tier3' / 'container.sh'
README = pathlib.Path('e2e') / 'README_E2E.md'
WRITTEN = re.compile(r'\$\{RUN_DIR\}/(\$\{[A-Za-z_][A-Za-z0-9_]*\}|[A-Za-z0-9_.-]+)')
ROW = re.compile(r'^\|\s*([^|]+?)\s*\|')

lines = []
script = CONTAINER.read_text(encoding='utf-8')
written = set()
for match in WRITTEN.finditer(script):
    target = match.group(1)
    if not target.startswith('${'):
        written.add(target)
        continue
    name = target[2:-1]
    loop = re.search(r'\bfor\s+%s\s+in\s+([^;\n]+);' % re.escape(name), script)
    if not loop:
        lines.append('FAIL %s writes ${RUN_DIR}/%s and no `for %s in ...` loop says what it is, so this '
                     'check cannot name the file' % (CONTAINER.as_posix(), target, name))
        continue
    written.update(loop.group(1).split())

if not written:
    print('FAIL no ${RUN_DIR}/ path was found in %s, so this check proved nothing' % CONTAINER.as_posix())
    raise SystemExit(0)

text = README.read_text(encoding='utf-8')
if '\n### Run records\n' not in text:
    print('FAIL %s has no "### Run records" section' % README.as_posix())
    raise SystemExit(0)
section = text.split('\n### Run records\n', 1)[1].split('\n### ', 1)[0]
rows = set()
for line in section.splitlines():
    match = ROW.match(line)
    if match and match.group(1) not in ('File', '---'):
        rows.add(match.group(1).rstrip('/'))

if not rows:
    lines.append('FAIL the Run records table in %s has no row' % README.as_posix())
for name in sorted(written - rows):
    lines.append('FAIL %s writes %s into the run directory and the Run records table in %s has no row '
                 'for it' % (CONTAINER.as_posix(), name, README.as_posix()))
for name in sorted(rows - written):
    lines.append('FAIL the Run records table in %s has a row for %s, which %s never writes into the run '
                 'directory' % (README.as_posix(), name, CONTAINER.as_posix()))

if not lines:
    lines.append('OK the Run records table names the %d files and folders %s writes into a run directory, '
                 'and no other' % (len(written), CONTAINER.as_posix()))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "run records table"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "the Run records table does not match the run directory" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the Run records table check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "run records table"
