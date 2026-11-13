#!/usr/bin/env bash
#
# Tier 1: every mention of a workflow under .github/workflows gives it the extension its file has.
#
# The workflows do not share one extension: e2e-manual.yaml ends in .yaml and the other three in .yml.
# The header of e2e-matrix.yml named the single platform workflow with .yml seven times, and nothing
# noticed, docs/regression_ledger.md 10.284 and 10.299. A name with the wrong extension sends a reader
# to a file that does not exist, and `gh workflow run` given that name finds no workflow.
#
# So every file git would ship, tracked or new, is read for a name made of the stem of a workflow
# and .yml or .yaml, and fails when that name is not the workflow's own. A file holding a null byte
# is not read. docs/regression_ledger.md is left out by name, because each entry quotes the tree of
# its own day and old ledger text is never edited.
#
# The reader is first run against a planted tree and must name exactly the planted mistakes, so a
# reader that finds nothing cannot pass for a tree that holds nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: every mention of a workflow gives it the extension its file has"

LEFT_OUT=(docs/regression_ledger.md)

if ! command -v git >/dev/null 2>&1; then
    skip "every mention of a workflow gives it the extension its file has" \
         "no git here, and only git knows which files the repository ships"
    finish "workflow file names"
fi

require_python "every mention of a workflow gives it the extension its file has" "workflow file names"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

# misnamed <workflows dir> <file>...  ->  prints "<file>:<line>: <name> ..." for each mistake, then
#                                        "READ <files read> <correct mentions>"
misnamed() {
    "${PYTHON}" -I - "$@" <<'PYEOF'
import os
import re
import sys

workflows_dir = sys.argv[1]
real = {}
for name in sorted(os.listdir(workflows_dir)):
    stem, dot, extension = name.rpartition('.')
    if dot and extension in ('yml', 'yaml'):
        real[stem] = name

if not real:
    print('NONE')
    raise SystemExit(0)

MENTION = re.compile(r'(?<![A-Za-z0-9_.-])(%s)\.(yml|yaml)(?![A-Za-z0-9_-])'
                     % '|'.join(re.escape(stem) for stem in sorted(real, key=len, reverse=True)))

read = 0
correct = 0
for path in sys.argv[2:]:
    try:
        with open(path, 'rb') as handle:
            data = handle.read()
    except OSError:
        continue
    if b'\0' in data:
        continue
    read += 1
    for number, line in enumerate(data.decode('utf-8', 'replace').split('\n'), 1):
        for found in MENTION.finditer(line):
            name = '%s.%s' % (found.group(1), found.group(2))
            if name == real[found.group(1)]:
                correct += 1
            else:
                print('%s:%d: %s, and the workflow is %s' % (path, number, name, real[found.group(1)]))
print('READ %d %d' % (read, correct))
PYEOF
}

planted="${work}/planted"
mkdir -p "${planted}/.github/workflows"
: >"${planted}/.github/workflows/alpha.yaml"
: >"${planted}/.github/workflows/beta-cell.yml"
cat >"${planted}/wrong.md" <<'EOF'
# Same rule as alpha.yml and the same reason.
See [the cell](.github/workflows/beta-cell.yaml).
gh workflow run alpha.yml -f target_platform=debian
The buffer alpha.yml's own job uses, and beta-cell.yaml.
EOF
cat >"${planted}/clean.sh" <<'EOF'
# Dispatch alpha.yaml, which calls beta-cell.yml.
gh workflow run alpha.yaml -f target_platform=windows
See .github/workflows/beta-cell.yml and alpha.yaml's own header.
my-alpha.yml, alpha.yml5, beta.yaml and gamma.yml are other files.
EOF
printf 'alpha.yml\0' >"${planted}/binary.bin"

expected_planted="wrong.md:1: alpha.yml, and the workflow is alpha.yaml
wrong.md:2: beta-cell.yaml, and the workflow is beta-cell.yml
wrong.md:3: alpha.yml, and the workflow is alpha.yaml
wrong.md:4: alpha.yml, and the workflow is alpha.yaml
wrong.md:4: beta-cell.yaml, and the workflow is beta-cell.yml
READ 2 5"

status=0
planted_output="$(cd "${planted}" && misnamed .github/workflows wrong.md clean.sh binary.bin 2>&1)" || status=$?
if [[ ${status} -eq 0 && "${planted_output}" == "${expected_planted}" ]]; then
    pass "the reader names exactly the five planted mistakes and none of the five correct mentions, other names or the binary file"
else
    fail "the reader names exactly the five planted mistakes and none of the five correct mentions, other names or the binary file" \
         "exit ${status}. Output: ${planted_output//$'\n'/ | }"
fi

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "workflow file names"; }

status=0
listing="$(git -c core.quotePath=false ls-files --cached --others --exclude-standard 2>&1)" || status=$?
if [[ ${status} -ne 0 ]]; then
    fail "git lists the files of the repository" "git ls-files exited ${status}: ${listing}"
    finish "workflow file names"
fi

files=()
while IFS= read -r path; do
    [[ -z "${path}" ]] && continue
    [[ " ${LEFT_OUT[*]} " == *" ${path} "* ]] && continue
    files+=("${path}")
done <<<"${listing}"

if [[ ${#files[@]} -eq 0 ]]; then
    fail "every mention of a workflow gives it the extension its file has" \
         "git listed no file, so this proves nothing"
    finish "workflow file names"
fi

status=0
repo_output="$(misnamed .github/workflows "${files[@]}" 2>&1)" || status=$?
read_count=""
correct_count=""
findings=()
while IFS= read -r line; do
    case "${line}" in
        NONE)    read_count=none ;;
        READ\ *) read -r _ read_count correct_count <<<"${line}" ;;
        "")      ;;
        *)       findings+=("${line}") ;;
    esac
done <<<"${repo_output}"

if [[ ${status} -ne 0 || -z "${read_count}" ]]; then
    fail "the reader could read the files of the repository" "exit ${status}: ${repo_output}"
elif [[ "${read_count}" == none ]]; then
    fail "every mention of a workflow gives it the extension its file has" \
         ".github/workflows holds no .yml or .yaml file, so this proves nothing"
elif [[ "${read_count}" -eq 0 || "${correct_count}" -eq 0 ]]; then
    fail "every mention of a workflow gives it the extension its file has" \
         "the reader read ${read_count} of the ${#files[@]} listed files and found ${correct_count} correct mentions, so this proves nothing"
elif [[ ${#findings[@]} -eq 0 ]]; then
    pass "all ${correct_count} mentions of a workflow in ${read_count} text files give it the extension its file has, the ledger left out"
else
    for finding in "${findings[@]}"; do
        fail "a file names a workflow with an extension its file does not have, so the name leads nowhere" \
             "${finding}"
    done
fi

finish "workflow file names"
