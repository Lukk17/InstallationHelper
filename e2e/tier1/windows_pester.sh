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
# way, `Invoke-Pester` with the Slow and Network tags excluded, which is what the shared action
# .github/actions/windows-pester does on a Windows runner for the stage 1 job and the single platform
# workflow.
#
# SKIP rather than pass when Pester or pwsh is missing, because a check that quietly proves nothing
# is the thing this repository keeps paying for. The CI job stays as it is: it runs on a clean
# Windows runner, which is a state this machine cannot reproduce.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/pwsh_probe.sh"

info "Tier 1: the Windows installer unit tests"

SUITE="${E2E_ROOT}/tier1/windows/WindowsSoftware.Tests.ps1"

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
pester_status=0
out="$("${PWSH}" -NoProfile -NonInteractive -Command "
    \$ErrorActionPreference = 'Stop'
    \$m = Get-Module -ListAvailable Pester | Where-Object { \$_.Version.Major -ge 5 } |
          Sort-Object Version -Descending | Select-Object -First 1
    if (-not \$m) { Write-Output 'PESTER_ABSENT'; exit 0 }
    Import-Module \$m.Path -Force
    \$excludedTags = @('Slow', 'Network')
    \$c = New-PesterConfiguration
    \$c.Run.Path = '${SUITE}'
    \$c.Run.PassThru = \$true
    \$c.Filter.ExcludeTag = \$excludedTags
    \$c.Output.Verbosity = 'None'
    \$r = Invoke-Pester -Configuration \$c
    \$notRunByTag = 0
    foreach (\$t in @(\$r.Tests | Where-Object { \$_.Result -eq 'NotRun' })) {
        \$tags = @(\$t.Tag)
        for (\$b = \$t.Block; \$b; \$b = \$b.Parent) { \$tags += \$b.Tag }
        if (@(\$tags | Where-Object { \$_ -in \$excludedTags }).Count -gt 0) { \$notRunByTag++ }
        else { Write-Output (\"NOTRUN {0}\" -f \$t.ExpandedPath) }
    }
    foreach (\$t in @(\$r.Tests | Where-Object { \$_.Result -eq 'Inconclusive' })) { Write-Output (\"INCONCLUSIVE {0}\" -f \$t.ExpandedPath) }
    foreach (\$b in \$r.FailedBlocks) { Write-Output (\"FAILEDBLOCK {0}: {1}\" -f (\$b.Path -join '.'), (\"\$(\$b.ErrorRecord)\" -replace '\s+', ' ')) }
    foreach (\$k in \$r.FailedContainers) { Write-Output (\"FAILEDCONTAINER {0}: {1}\" -f \$k.Item, (\"\$(\$k.ErrorRecord)\" -replace '\s+', ' ')) }
    Write-Output (\"TOTALS total={0} passed={1} failed={2} skipped={3} notrun={4} inconclusive={5} failedblocks={6} failedcontainers={7} notrunbytag={8}\" -f \$r.TotalCount, \$r.PassedCount, \$r.FailedCount, \$r.SkippedCount, \$r.NotRunCount, \$r.InconclusiveCount, \$r.FailedBlocksCount, \$r.FailedContainersCount, \$notRunByTag)
    foreach (\$t in \$r.Failed) { Write-Output (\"FAILED {0}: {1}\" -f \$t.ExpandedPath, (\"\$(\$t.ErrorRecord)\" -replace '\s+', ' ')) }
" 2>&1 | tr -d '\r')" || pester_status=$?

if grep -q 'PESTER_ABSENT' <<<"${out}"; then
    skip "the Pester suite passes" "Pester 5 is not installed here, install it with: Install-Module Pester -Scope CurrentUser"
    finish "Windows installer unit tests"
    return 0 2>/dev/null || exit 0
fi

# `|| true` because grep exits 1 when it matches nothing, and under pipefail that status would end
# the script on this assignment, which is the branch below never running rather than a quiet pass.
totals="$(grep -o 'TOTALS .*' <<<"${out}" | sed -n 1p || true)"
counts="${totals#TOTALS }"
count_of() { sed -n "s/.*\<${1}=\([0-9][0-9]*\).*/\1/p" <<<"${counts}"; }
lines_of() { grep "^${1} " <<<"${out}" | tr '\n' ' ' || true; }

missing_counts=""
for name in total passed failed skipped notrun inconclusive failedblocks failedcontainers notrunbytag; do
    [[ -n "$(count_of "${name}")" ]] || missing_counts+=" ${name}"
done

if [[ -z "${totals}" ]]; then
    fail "the Pester run printed no totals, so this check proves nothing" \
         "${PWSH} exited ${pester_status}: $(tr '\n' ' ' <<<"${out}" | tail -c 400)"
elif [[ -n "${missing_counts}" ]]; then
    fail "the Pester totals lack a count, so this check proves nothing" "missing:${missing_counts} | ${counts}"
elif (( $(count_of total) == 0 )); then
    fail "Pester discovered no tests, which is a broken gate rather than a clean run" "${counts}"
else
    problems=()
    (( $(count_of failed) == 0 )) ||
        problems+=("$(count_of failed) failed, and CI would refuse the whole sweep for it: $(lines_of FAILED)")
    (( $(count_of failedblocks) == 0 && $(count_of failedcontainers) == 0 )) ||
        problems+=("a BeforeAll, an AfterAll or a whole test file failed, so the tests under it never ran: $(lines_of FAILEDBLOCK)$(lines_of FAILEDCONTAINER)")
    (( $(count_of notrun) == $(count_of notrunbytag) )) ||
        problems+=("$(( $(count_of notrun) - $(count_of notrunbytag) )) did not run although no Slow or Network tag leaves them out: $(lines_of NOTRUN)")
    (( $(count_of inconclusive) == 0 )) ||
        problems+=("$(count_of inconclusive) ended inconclusive, which proves nothing: $(lines_of INCONCLUSIVE)")
    (( $(count_of passed) + $(count_of failed) + $(count_of skipped) + $(count_of notrun) + $(count_of inconclusive) == $(count_of total) )) ||
        problems+=("passed, failed, skipped, not run and inconclusive do not make the total, so a test ended in a result this check does not read")
    if (( ${#problems[@]} == 0 )); then
        pass "the Windows installer unit tests pass (${counts}, the $(count_of notrunbytag) not run are the Slow and Network tagged tests this check leaves out)"
    else
        fail "the Windows installer unit tests did not all pass or skip" "${counts} | $(printf '%s | ' "${problems[@]}")"
    fi
fi

finish "Windows installer unit tests"
