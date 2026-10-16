#!/usr/bin/env bash
#
# Tier 1: the OpenSpec change for the capability tests lists the same capabilities as the index.
#
# e2e/testing/README.md is the index of capability specs, one row per number. The change that created
# them, openspec/changes/add-playbook-e2e-capability-tests, repeats that list in tables of its own, in
# test-spec.md, proposal.md and tasks-template.md, and nothing compared them. So when capability 30 was
# turned from smoke into forced-failure and capability 90, idempotency, was added, the index changed
# and the change did not: its tables still described 30 as smoke and had no row for 90. See
# docs/regression_ledger.md.
#
# Every markdown table in those three files whose first column is N is read. A table with a Capability
# column must name the same set of number and name pairs as the index, and one without it, the
# invocation table in proposal.md, must carry the same numbers. A file with no such table fails too,
# because a comparison against nothing proves nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: the capability-tests change lists the same capabilities as the index"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "capability index parity"; }

require_python "the capability-tests change lists the same capabilities as the index" "capability index parity"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re

INDEX = pathlib.Path('e2e/testing/README.md')
CHANGE = pathlib.Path('openspec/changes/add-playbook-e2e-capability-tests')
COPIES = [CHANGE / 'test-spec.md', CHANGE / 'proposal.md', CHANGE / 'tasks-template.md']
LINK = re.compile(r'\[([^\]]*)\]\([^)]*\)')


def cells(line):
    return [LINK.sub(r'\1', c).strip().strip('`') for c in line.strip().strip('|').split('|')]


def tables(path):
    """Every table whose first header cell is N, as (header, rows), with line numbers on the rows."""
    lines = path.read_text(encoding='utf-8').splitlines()
    found = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith('|') and cells(line)[0] == 'N' and i + 1 < len(lines) and set(lines[i + 1].replace('|', '').strip()) <= set('-: '):
            header = cells(line)
            rows = []
            i += 2
            while i < len(lines) and lines[i].startswith('|'):
                rows.append((i + 1, cells(lines[i])))
                i += 1
            found.append((header, rows))
        else:
            i += 1
    return found


def pairs(header, rows):
    column = header.index('Capability')
    return {(row[0], row[column]) for _, row in rows}


for path in [INDEX] + COPIES:
    if not path.is_file():
        print('FAIL\t{}\tthe file is missing'.format(path))
        raise SystemExit

index_tables = [t for t in tables(INDEX) if 'Capability' in t[0]]
if len(index_tables) != 1 or not index_tables[0][1]:
    print('FAIL\t{}\texpected exactly one capability table with rows, found {}'.format(INDEX, len(index_tables)))
    raise SystemExit
expected = pairs(*index_tables[0])
expected_numbers = {n for n, _ in expected}

compared = 0
for path in COPIES:
    found = tables(path)
    if not found:
        print('FAIL\t{}\tno table whose first column is N, so nothing here can be compared'.format(path))
        continue
    for header, rows in found:
        compared += 1
        first = rows[0][0] if rows else 0
        where = '{}:{}'.format(path, first)
        if 'Capability' in header:
            got = pairs(header, rows)
            for n, name in sorted(got - expected):
                print('FAIL\t{}\tlists {} {}, which the index does not'.format(where, n, name))
            for n, name in sorted(expected - got):
                print('FAIL\t{}\tlacks {} {}, which the index lists'.format(where, n, name))
        else:
            got = {row[0] for _, row in rows}
            for n in sorted(got - expected_numbers):
                print('FAIL\t{}\tlists capability {}, which the index does not'.format(where, n))
            for n in sorted(expected_numbers - got):
                print('FAIL\t{}\tlacks capability {}, which the index lists'.format(where, n))
print('COMPARED\t{}\t{}'.format(compared, len(expected)))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "capability index parity"

failures="$(grep '^FAIL' <<<"${report}" || true)"
compared="$(awk -F'\t' '$1 == "COMPARED" {print $2 " tables against " $3 " capabilities"}' <<<"${report}")"
if [[ -z "${failures}" && -n "${compared}" ]]; then
    pass "every capability table in the change matches e2e/testing/README.md, ${compared}"
else
    while IFS=$'\t' read -r _ where why; do
        fail "the capability-tests change disagrees with e2e/testing/README.md" "${where}: ${why}"
    done <<<"${failures}"
fi

finish "capability index parity"
