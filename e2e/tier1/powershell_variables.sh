#!/usr/bin/env bash
#
# Tier 1: no PowerShell file reads a variable that nothing ever assigns.
#
# Written after the Windows settings phase died on every run in the sweep of 2026-08-22 with
# "The variable '$installationType' cannot be retrieved because it has not been set". The Server SKU
# change of the day before interpolated that variable into the elevated child script it builds, and
# nothing anywhere defined it. Set-StrictMode -Version Latest, which every file here sets on
# purpose, turns reading an unset variable into a terminating error, so the wizard stopped before
# enabling a single feature.
#
# Nothing caught it. The file parses, PSScriptAnalyzer has no rule for reading an undefined
# variable, the Pester unit tests never reach that function because it shells out to an elevated
# child, and the tier 1 Windows checks read the mapping and the toggles rather than the code path.
# Only a real Windows runner found it, and only because stage 3 was finally allowed to run.
#
# So this asks PowerShell's own parser instead of guessing with grep. Every *.ps1 under setup/ is
# parsed to an abstract syntax tree, which is the structured form the language itself works from,
# every variable read is collected, and any name that no assignment, parameter, foreach, data
# statement or [ref] argument in the same file ever binds is reported with its line.
#
# What it deliberately does not flag:
#   - automatic variables, the ones PowerShell provides itself, listed by name below
#   - drive-qualified reads such as $env:PATH, which come from outside the file by definition
#   - scope prefixes, so $script:Foo counts as assigned when Foo is assigned anywhere in the file
#
# It is a per-file check, not a whole-program one. A variable assigned in one file and read in
# another would be a false positive, and there is none today because these files communicate
# through function parameters and return values rather than through shared state. If that ever
# changes, widen the assignment set rather than deleting the check.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/pwsh_probe.sh"

info "Tier 1: PowerShell variables are assigned before they are read"

PWSH="$(find_runnable_pwsh)" || true
if [[ -z "${PWSH}" ]]; then
    skip "no PowerShell file reads an unassigned variable" \
         "no PowerShell 7 that runs was found here, and only its own parser can answer this"
    finish "PowerShell variables are assigned before they are read"
    return 0 2>/dev/null || exit 0
fi

probe_script="$(dirname "${BASH_SOURCE[0]}")/powershell_variables.ps1"
out="$("${PWSH}" -NoProfile -NonInteractive -File "$(host_path "${probe_script}")" \
        "$(host_path "${REPO_ROOT}/setup")" 2>&1 | tr -d '\r')"

if [[ "${out}" == "clean" ]]; then
    pass "every variable read in setup/**/*.ps1 is assigned somewhere in its own file"
elif [[ -z "${out}" ]]; then
    fail "the PowerShell probe printed nothing, so this check proved nothing" \
         "expected either 'clean' or a list of findings from ${probe_script}"
else
    fail "$(grep -c . <<<"${out}") PowerShell variable read(s) with no assignment behind them" \
         "$(tr '\n' ' ' <<<"${out}")"
fi

finish "PowerShell variables are assigned before they are read"
