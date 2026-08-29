#!/usr/bin/env bash
#
# Tier 1: every shell script in the repository must parse.
#
# Nothing had ever run `bash -n` over setup/setup.sh, which is roughly 1350 lines of the only code
# that decides what a Linux or macOS machine installs. Every PowerShell file under setup/ already
# gets a real syntax-tree parse in e2e/tier1/powershell_variables.ps1, so the shell half of the same
# repository was the half with no parser pointed at it at all. A parse error in a wizard is not a
# subtle defect: the script dies at the first line the reader never reaches, and on a live USB there
# is nothing to fall back to.
#
# The scripts are found by extension and by shebang rather than from a list, because a list is a
# thing somebody has to remember to add to, and the script added tomorrow is exactly the one nobody
# has run yet. Finding nothing is a failure rather than a pass, since a scan over an empty set is
# indistinguishable from a scan that found no problem.
#
# ShellCheck is the second half and is optional, reported the way ansible_static.sh reports yamllint
# and ansible-lint. It catches the class `bash -n` cannot see, an unquoted expansion or a read of a
# variable that was never set, and both of those have cost this repository a run. Making the gate
# depend on a tool that may not be installed would mean the gate quietly stops running, so its
# absence is named as a SKIP instead of being counted as a pass.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: shell script syntax"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "shell syntax"; }

# A file counts as a shell script when its name says so or when its first line does. The shebang
# half is what covers a script with no extension, which this repository does not have today and is
# one commit away from having.
#
# The walk is done in Python rather than in a find pipeline because the shebang half has to open
# every file in the tree, and one process per file costs about two minutes under Git Bash on
# Windows for a tree this size. One interpreter reading the first line of each file answers in well
# under a second, which is what keeps this inside the seconds tier 1 is allowed.
SCRIPTS=()
while IFS= read -r candidate; do
    [[ -n "${candidate}" ]] && SCRIPTS+=("${candidate}")
done < <("${PYTHON:-python}" - . <<'PYEOF'
import os
import re
import sys

PRUNED = {'.git', 'node_modules', '.venv', '__pycache__'}
SHEBANG = re.compile(rb'^#!.*[ /](ba)?sh([ \t]|$)')

found = []
for directory, subdirectories, filenames in os.walk(sys.argv[1]):
    subdirectories[:] = [d for d in subdirectories if d not in PRUNED]
    for filename in filenames:
        path = os.path.join(directory, filename)
        relative = './' + os.path.relpath(path, sys.argv[1]).replace(os.sep, '/')
        if filename.endswith(('.sh', '.bash')):
            found.append(relative)
            continue
        try:
            with open(path, 'rb') as handle:
                first_line = handle.readline(512).rstrip(b'\r\n')
        except OSError:
            continue
        if SHEBANG.match(first_line):
            found.append(relative)

# Written as bytes rather than printed. On Windows a text-mode print turns every newline into a
# carriage return and a newline, the reader here compares whole paths, and `./setup/setup.sh\r` is
# not a file. That cost this check one debugging round on the day it was written.
sys.stdout.buffer.write(('\n'.join(sorted(found)) + '\n').encode('utf-8'))
PYEOF
)

if [[ ${#SCRIPTS[@]} -eq 0 ]]; then
    fail "no shell script was found anywhere in the repository, so this check proves nothing" \
         "searched ${REPO_ROOT} by extension and by shebang"
    finish "shell syntax"
fi

# --- the four places that must always contribute ------------------------------
# A finder that silently stopped seeing one directory would leave the tally looking healthy while
# the file that matters went unparsed, so each area the wizard actually lives in is named. These are
# locations rather than filenames, except for the two single files that are the point of the check.
area_count() {
    local prefix="$1" n=0 script
    for script in "${SCRIPTS[@]}"; do
        [[ "${script}" == "${prefix}"* ]] && n=$((n + 1))
    done
    printf '%s\n' "${n}"
}

for required in ./setup/setup.sh ./setup/pinned_values/pinned_values.sh; do
    found=false
    for script in "${SCRIPTS[@]}"; do
        [[ "${script}" == "${required}" ]] && { found=true; break; }
    done
    if [[ "${found}" == true ]]; then
        pass "${required#./} is in the set this check parses"
    else
        fail "${required#./} was not picked up, so the file this check exists for is not being parsed" \
             "the finder returned ${#SCRIPTS[@]} scripts and none of them was ${required}"
    fi
done

for area in ./e2e/ ./docs/manual/; do
    n="$(area_count "${area}")"
    if [[ "${n}" -gt 0 ]]; then
        pass "${area#./} contributes ${n} script(s) to the parse"
    else
        fail "${area#./} contributed no script, so nothing there is being parsed" \
             "the finder returned ${#SCRIPTS[@]} scripts and none of them was under ${area}"
    fi
done

# --- bash -n over every one of them -------------------------------------------
broken=()
for script in "${SCRIPTS[@]}"; do
    if ! output="$(bash -n "${script}" 2>&1)"; then
        broken+=("${script#./}: $(head -2 <<<"${output}" | tr '\n' ' ')")
    fi
done

if [[ ${#broken[@]} -eq 0 ]]; then
    pass "all ${#SCRIPTS[@]} shell scripts parse under bash -n"
else
    for entry in "${broken[@]}"; do
        fail "a shell script does not parse, so it dies before its first line runs" "${entry}"
    done
fi

# --- ShellCheck, when it is installed -----------------------------------------
if command -v shellcheck &>/dev/null; then
    findings="$(shellcheck --severity=warning --format=gcc "${SCRIPTS[@]}" 2>&1 || true)"
    if [[ -z "${findings}" ]]; then
        pass "shellcheck reports nothing at severity warning across ${#SCRIPTS[@]} scripts"
    else
        fail "shellcheck reports findings at severity warning" \
             "$(grep -c . <<<"${findings}") line(s), first five: $(head -5 <<<"${findings}" | tr '\n' ' ')"
    fi
else
    skip "shellcheck runs at severity warning over every shell script" \
         "shellcheck is not installed, so the half of this check that catches an unquoted expansion did not run. Install with: sudo apt-get install shellcheck, or dnf install ShellCheck, or brew install shellcheck, or winget install koalaman.shellcheck"
fi

finish "shell syntax"
