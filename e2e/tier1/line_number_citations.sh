#!/usr/bin/env bash
#
# Tier 1: nothing under e2e/, setup/ or docs/ locates code in setup.sh or setup.ps1 by line number.
#
# The header comments of list_software.sh and print_command_resolution.sh, written in bd7191f on
# 2026-08-29, sent the reader to two line numbers of setup.sh, 1391 and 1402. Every later edit above
# those lines moved the code away from the numbers, and by 2026-11-09 the two blocks started at 1575
# and 1586, so a reader who followed either number landed in unrelated code,
# docs/regression_ledger.md 10.253. A line number of a file that changes every week is stale from the
# next edit on. Name the function or the block instead.
#
# Two shapes are read, in any case and with or without the path in front of the script: a line or
# lines followed by "of" or "in" and the script, and the script followed by a colon, "#L", "line" or
# "at line" and a number. Every file git would ship under the three folders is read, tracked or new,
# apart from a file holding a null byte, which git treats as binary.
#
# Two files are left out by name. docs/regression_ledger.md, because each entry records the tree of
# its own day and quotes what a tool printed then, a ShellCheck warning with its line among them, and
# entry 10.253 quotes the very comments it fixed. Old ledger text is never edited, so a citation there
# is evidence rather than a pointer. And this script, whose planted lines below are citations on
# purpose.
#
# The reader is first run against a planted tree and must name exactly the planted citations, so a
# reader that finds nothing cannot pass for a tree that holds nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: no file locates code in setup.sh or setup.ps1 by line number"

LEFT_OUT=(docs/regression_ledger.md e2e/tier1/line_number_citations.sh)

if ! command -v git >/dev/null 2>&1; then
    skip "no file under e2e/, setup/ or docs/ cites a line number of setup.sh or setup.ps1" \
         "no git here, and only git knows which files the repository ships"
    finish "line number citations"
fi

require_python "no file under e2e/, setup/ or docs/ cites a line number of setup.sh or setup.ps1" "line number citations"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

# citations <file>...  ->  prints "<file>:<line>: <citation>" for each citation, then "READ <count>"
citations() {
    "${PYTHON}" -I - "$@" <<'PYEOF'
import re
import sys

SCRIPT = r'(?:[A-Za-z0-9_./-]*/)?setup\.(?:sh|ps1)\b'
SHAPES = (
    re.compile(r'\blines? [0-9]+(?:[ ,]+(?:and |to |or )?[0-9]+)*,? (?:of|in) ' + SCRIPT, re.IGNORECASE),
    re.compile(r'\bsetup\.(?:sh|ps1)(?::|#L|,? lines? |,? at lines? )[0-9]+', re.IGNORECASE),
)

read = 0
for path in sys.argv[1:]:
    try:
        with open(path, 'rb') as handle:
            data = handle.read()
    except OSError:
        continue
    if b'\0' in data:
        continue
    read += 1
    for number, line in enumerate(data.decode('utf-8', 'replace').split('\n'), 1):
        for shape in SHAPES:
            found = shape.search(line)
            if found:
                print('%s:%d: %s' % (path, number, found.group(0)))
                break
print('READ %d' % read)
PYEOF
}

planted="${work}/planted"
mkdir -p "${planted}"
cat >"${planted}/cites.sh" <<'EOF'
# --list-software answers at line 1391 of setup.sh and exits.
# --print-command answers at setup.sh:1402.
# The wizard calls them at lines 1600, 1605 and 1622 of setup/setup.sh.
See [the module install](../../setup/setup.ps1#L937).
Setup.ps1 line 88 sets the label table.
The refusal sits in line 12 in ../setup/setup.sh.
EOF
cat >"${planted}/clean.md" <<'EOF'
setup.sh exits 2 before it reads a toggle.
See line 1124 of docs/regression_ledger.md.
Never write `line <N> of setup.sh`, name the function.
The first 2 lines of setup.sh are its shebang and a comment.
See line 3 of setup.shell, which is another file.
EOF
printf 'line 5 of setup.sh\0' >"${planted}/binary.bin"

expected_planted="cites.sh:1: line 1391 of setup.sh
cites.sh:2: setup.sh:1402
cites.sh:3: lines 1600, 1605 and 1622 of setup/setup.sh
cites.sh:4: setup.ps1#L937
cites.sh:5: Setup.ps1 line 88
cites.sh:6: line 12 in ../setup/setup.sh
READ 2"

status=0
planted_output="$(cd "${planted}" && citations cites.sh clean.md binary.bin 2>&1)" || status=$?
if [[ ${status} -eq 0 && "${planted_output}" == "${expected_planted}" ]]; then
    pass "the reader names exactly the six planted citations and reads neither the clean lines nor the binary file as one"
else
    fail "the reader names exactly the six planted citations and reads neither the clean lines nor the binary file as one" \
         "exit ${status}. Output: ${planted_output//$'\n'/ | }"
fi

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "line number citations"; }

status=0
listing="$(git -c core.quotePath=false ls-files --cached --others --exclude-standard -- e2e setup docs 2>&1)" || status=$?
if [[ ${status} -ne 0 ]]; then
    fail "git lists the files under e2e/, setup/ and docs/" "git ls-files exited ${status}: ${listing}"
    finish "line number citations"
fi

files=()
while IFS= read -r path; do
    [[ -z "${path}" ]] && continue
    [[ " ${LEFT_OUT[*]} " == *" ${path} "* ]] && continue
    files+=("${path}")
done <<<"${listing}"

if [[ ${#files[@]} -eq 0 ]]; then
    fail "no file under e2e/, setup/ or docs/ cites a line number of setup.sh or setup.ps1" \
         "git listed no file under the three folders, so this proves nothing"
    finish "line number citations"
fi

status=0
repo_output="$(citations "${files[@]}" 2>&1)" || status=$?
read_count=""
findings=()
while IFS= read -r line; do
    case "${line}" in
        READ\ *) read_count="${line#READ }" ;;
        "")      ;;
        *)       findings+=("${line}") ;;
    esac
done <<<"${repo_output}"

if [[ ${status} -ne 0 || -z "${read_count}" ]]; then
    fail "the reader could read the files under e2e/, setup/ and docs/" "exit ${status}: ${repo_output}"
elif [[ "${read_count}" -eq 0 ]]; then
    fail "no file under e2e/, setup/ or docs/ cites a line number of setup.sh or setup.ps1" \
         "the reader read none of the ${#files[@]} listed files, so this proves nothing"
elif [[ ${#findings[@]} -eq 0 ]]; then
    pass "none of the ${read_count} text files under e2e/, setup/ and docs/ cites a line number of setup.sh or setup.ps1, the ledger and this check left out"
else
    for finding in "${findings[@]}"; do
        fail "a file locates code in setup.sh or setup.ps1 by line number, which the next edit above it makes wrong, so name the function or the block" \
             "${finding}"
    done
fi

finish "line number citations"
