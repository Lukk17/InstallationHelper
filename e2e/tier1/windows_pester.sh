#!/usr/bin/env bash
#
# Tier 1: the Pester suite over the Windows installer logic, run locally as well as in CI.
#
# The hole this closes cost a whole sweep. On 2026-08-24 the tier 1 gate passed 145 assertions here,
# the tree was pushed, and the sweep stopped at stage 1 because the Pester job failed: the plan
# builder had started reading three optional properties, and the suite hands it mappings built by
# hand without them, which under Set-StrictMode -Version Latest is a terminating error. Twenty
# seconds of local Pester would have caught it before the push, and instead the whole matrix was
# skipped and an hour went by.
#
# So the same suite CI runs, runs here too when it can. Not a copy of it: the same file, the same
# way, `Invoke-Pester` with the Slow and Network tags excluded, which is what the stage 1 job does.
#
# SKIP rather than pass when Pester or pwsh is missing, because a check that quietly proves nothing
# is the thing this repository keeps paying for. The CI job stays as it is: it runs on a clean
# Windows runner, which is a state this machine cannot reproduce.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/pwsh_probe.sh"

info "Tier 1: the Windows installer unit tests"

SUITE="${E2E_ROOT}/tier3/windows/WindowsSoftware.Tests.ps1"

if [[ ! -f "${SUITE}" ]]; then
    fail "the Pester suite is missing, so this check proves nothing" "${SUITE}"
    finish "Windows installer unit tests"
    return 0 2>/dev/null || exit 0
fi

PWSH="$(find_runnable_pwsh)" || true
if [[ -z "${PWSH}" ]]; then
    skip "the Pester suite passes" "no PowerShell 7 that runs was found here"
    finish "Windows installer unit tests"
    return 0 2>/dev/null || exit 0
fi

# The totals line is parsed rather than the exit code alone, so a suite that discovered nothing is a
# failure of this check instead of a silent zero.
out="$("${PWSH}" -NoProfile -NonInteractive -Command "
    \$ErrorActionPreference = 'Stop'
    \$m = Get-Module -ListAvailable Pester | Where-Object { \$_.Version.Major -ge 5 } |
          Sort-Object Version -Descending | Select-Object -First 1
    if (-not \$m) { Write-Output 'PESTER_ABSENT'; exit 0 }
    Import-Module \$m.Path -Force
    \$c = New-PesterConfiguration
    \$c.Run.Path = '$(host_path "${SUITE}")'
    \$c.Run.PassThru = \$true
    \$c.Filter.ExcludeTag = @('Slow', 'Network')
    \$c.Output.Verbosity = 'None'
    \$r = Invoke-Pester -Configuration \$c
    Write-Output (\"TOTALS total={0} passed={1} failed={2} skipped={3}\" -f \$r.TotalCount, \$r.PassedCount, \$r.FailedCount, \$r.SkippedCount)
    foreach (\$t in \$r.Failed) { Write-Output (\"FAILED {0}: {1}\" -f \$t.ExpandedPath, (\"\$(\$t.ErrorRecord)\" -replace '\s+', ' ')) }
" 2>&1 | tr -d '\r')"

if grep -q 'PESTER_ABSENT' <<<"${out}"; then
    skip "the Pester suite passes" "Pester 5 is not installed here, install it with: Install-Module Pester -Scope CurrentUser"
    finish "Windows installer unit tests"
    return 0 2>/dev/null || exit 0
fi

totals="$(grep -o 'TOTALS .*' <<<"${out}" | head -1)"
if [[ -z "${totals}" ]]; then
    fail "the Pester run printed no totals, so this check proves nothing" "$(tr '\n' ' ' <<<"${out}" | tail -c 400)"
elif [[ "${totals}" == *"total=0 "* ]]; then
    fail "Pester discovered no tests, which is a broken gate rather than a clean run" "${totals}"
elif [[ "${totals}" == *"failed=0 "* ]]; then
    pass "the Windows installer unit tests pass (${totals#TOTALS })"
else
    fail "the Windows installer unit tests fail, and CI would refuse the whole sweep for it" \
         "${totals#TOTALS } | $(grep '^FAILED ' <<<"${out}" | head -3 | tr '\n' ' ')"
fi

finish "Windows installer unit tests"
