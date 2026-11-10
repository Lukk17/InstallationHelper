#!/usr/bin/env bash
#
# Tier 1: every item of the numbered list of tier 1 checks starts its own line, in order.
#
# The list under "## Expected" in e2e/testing/10-wizard-toggle-parse-test.md names every check by an
# item number, and ledger entries and other pages cite a check by that number. On 2026-11-09 an edit
# to item 51 dropped the line break at its end, so the line read "... and GlassWire.GlassWire.52.
# `imported_agent_artifacts` reports ...", the rendered list had no item 52, and the description of
# that check read as the end of the one before it, docs/regression_ledger.md 10.254. Nothing failed,
# because verify_spec_parity.sh asks only whether the page names each check somewhere.
#
# So this reads every line of that section and fails on an item number followed by a check name in
# a code span anywhere but at the start of a line, on an item number at the start of a line that is
# not greater than the one before it, and on a number missing between 1 and the last item. Items keep
# their numbers when a check is deleted, so a missing number is allowed when a line of
# e2e/tier1/check_list_gaps_allowed.txt names it with the reason, and a line there whose number is
# back in the list, or lies past its last item, fails as well.
#
# The reader is first run against a planted list and must name exactly the planted faults, so a
# reader that finds nothing cannot pass for a list that holds nothing wrong.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: the numbered list of tier 1 checks"

require_python "every item of the tier 1 check list starts its own line, in order" "check list numbering"

SPEC="${REPO_ROOT}/e2e/testing/10-wizard-toggle-parse-test.md"
ALLOWED="${REPO_ROOT}/e2e/tier1/check_list_gaps_allowed.txt"
SPEC_NAME="e2e/testing/10-wizard-toggle-parse-test.md"
ALLOWED_NAME="e2e/tier1/check_list_gaps_allowed.txt"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

# list_faults <spec> <allowed>  ->  prints one line per fault, then "ITEMS <count>"
#   GLUED <line> <item>    an item number and a check name inside a line
#   ORDER <line> <item> <previous>
#   GAP <item>             a missing number no allowed line names
#   STALE <item>           an allowed number the list carries, or one past its last item
#   BADLINE <line> <text>  a line of the allowed file that is not "<number> | <why>"
#   NOSECTION              no "## Expected" heading
list_faults() {
    "${PYTHON}" -I - "$1" "$2" <<'PYEOF'
import re
import sys

ITEM = re.compile(r'([0-9]+)\. ')
GLUED = re.compile(r'(?<![0-9])([0-9]+)\. `[a-z][a-z0-9_]*`')

spec_path, allowed_path = sys.argv[1], sys.argv[2]

allowed = set()
with open(allowed_path, encoding='utf-8') as handle:
    for number, raw in enumerate(handle, 1):
        text = raw.strip()
        if not text or text.startswith('#'):
            continue
        gap, separator, why = text.partition(' | ')
        if not gap.isdigit() or not separator or not why.strip():
            print('BADLINE %d %s' % (number, text))
            continue
        allowed.add(int(gap))

with open(spec_path, encoding='utf-8') as handle:
    lines = handle.read().split('\n')

inside, seen_section, items = False, False, []
for number, line in enumerate(lines, 1):
    if line.startswith('## '):
        inside = line.strip() == '## Expected'
        seen_section = seen_section or inside
        continue
    if not inside:
        continue
    start = ITEM.match(line)
    if start:
        items.append((int(start.group(1)), number))
    for glued in GLUED.finditer(line):
        if glued.start() > 0:
            print('GLUED %d %s' % (number, glued.group(1)))

if not seen_section:
    print('NOSECTION')
print('ITEMS %d' % len(items))

previous = 0
for value, number in items:
    if value <= previous:
        print('ORDER %d %d %d' % (number, value, previous))
    previous = max(previous, value)

present = {value for value, _ in items}
last = max(present, default=0)
for gap in range(1, last + 1):
    if gap not in present and gap not in allowed:
        print('GAP %d' % gap)
for gap in sorted(allowed):
    if gap in present or gap > last:
        print('STALE %d' % gap)
PYEOF
}

cat >"${work}/spec.md" <<'EOF'
## Expected

1. `alpha` reports one thing.
2. `beta` reports another.
4. `delta` reports a fourth, after a gap the planted allowed file intends.
5. `epsilon` reports a fifth.GlassWire.6. `zeta` reports a sixth glued onto it.
8. `theta` reports an eighth.
7. `eta` reports a seventh, out of order.

## Fixtures

1. A list in another section is not read.
EOF
cat >"${work}/allowed.txt" <<'EOF'
# planted
3 | deleted on purpose
5 | carried by the list, so stale
9 | past the last item, so stale
EOF

expected_planted="GLUED 6 6
ITEMS 6
ORDER 8 7 8
GAP 6
STALE 5
STALE 9"

status=0
planted_output="$(list_faults "${work}/spec.md" "${work}/allowed.txt" 2>&1)" || status=$?
if [[ ${status} -eq 0 && "${planted_output}" == "${expected_planted}" ]]; then
    pass "the reader names exactly the planted glued item, the item out of order, the unintended gap and the two stale allowed lines"
else
    fail "the reader names exactly the planted glued item, the item out of order, the unintended gap and the two stale allowed lines" \
         "exit ${status}. Output: ${planted_output//$'\n'/ | }"
fi

for input in "${SPEC}" "${ALLOWED}"; do
    if [[ ! -f "${input}" ]]; then
        fail "the tier 1 check list and its allowed gaps can be read" "${input#"${REPO_ROOT}/"} is missing"
        finish "check list numbering"
    fi
done

status=0
report="$(list_faults "${SPEC}" "${ALLOWED}" 2>&1)" || status=$?
assert_python_ran "${status}" "check list numbering"

items=""
glued=() order=() gaps=() stale=() badlines=() nosection=0 unknown=()
while IFS= read -r line; do
    read -r kind first second third <<<"${line}"
    case "${kind}" in
        ITEMS)     items="${first}" ;;
        GLUED)     glued+=("line ${first} of ${SPEC_NAME} carries item ${second} after the text before it, so the rendered list has no item ${second}") ;;
        ORDER)     order+=("line ${first} of ${SPEC_NAME} carries item ${second} after item ${third}") ;;
        GAP)       gaps+=("item ${first} is missing from ${SPEC_NAME} and no line of ${ALLOWED_NAME} intends it") ;;
        STALE)     stale+=("${ALLOWED_NAME} intends item ${first} to be missing, and the list carries it or ends before it") ;;
        BADLINE)   badlines+=("line ${first} of ${ALLOWED_NAME} is not '<number> | <why>': ${line#BADLINE "${first}" }") ;;
        NOSECTION) nosection=1 ;;
        "")        ;;
        *)         unknown+=("${line}") ;;
    esac
done <<<"${report}"

if [[ ${nosection} -eq 1 || -z "${items}" || "${items}" -eq 0 ]]; then
    fail "the tier 1 check list holds items" "no numbered item found under '## Expected' in ${SPEC_NAME}, so this proves nothing. Output: ${report//$'\n'/ | }"
    finish "check list numbering"
fi

for finding in "${unknown[@]+"${unknown[@]}"}"; do
    fail "the reader printed only lines this check understands" "${finding}"
done

if [[ ${#glued[@]} -eq 0 ]]; then
    pass "every one of the ${items} items of the tier 1 check list starts its own line"
else
    for finding in "${glued[@]}"; do
        fail "an item of the tier 1 check list starts inside the line before it, so put the line break back" "${finding}"
    done
fi

if [[ ${#order[@]} -eq 0 ]]; then
    pass "the item numbers of the tier 1 check list rise in order"
else
    for finding in "${order[@]}"; do
        fail "an item of the tier 1 check list is out of order or repeats a number" "${finding}"
    done
fi

if [[ ${#gaps[@]} -eq 0 ]]; then
    pass "every number missing from the tier 1 check list is intended by a line of ${ALLOWED_NAME}"
else
    for finding in "${gaps[@]}"; do
        fail "a number is missing from the tier 1 check list without a reason" "${finding}"
    done
fi

if [[ ${#stale[@]} -eq 0 && ${#badlines[@]} -eq 0 ]]; then
    pass "every line of ${ALLOWED_NAME} names a number still missing from the list, with a reason"
else
    for finding in "${stale[@]+"${stale[@]}"}" "${badlines[@]+"${badlines[@]}"}"; do
        fail "a line of ${ALLOWED_NAME} excuses nothing or cannot be read" "${finding}"
    done
fi

finish "check list numbering"
