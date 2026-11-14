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
# So the same suite CI runs, runs here too when it can, and the same way. Not a copy of it: this check
# and the shared action .github/actions/windows-pester both start windows_pester.ps1 next to this
# file, which runs the suite with the Slow and Network tags excluded and decides whether the run
# passed. e2e/tier1/workflow_windows_pester.sh fails the gate when either of them runs Pester itself.
#
# SKIP rather than pass when pwsh is missing, because a check that quietly proves nothing is the thing
# this repository keeps paying for. A missing Pester is a failure, not a skip: the script runs only the
# Pester that gate_pester_version pins, the one the gate image carries, and this check passes only when
# the version the script reports is that pin (owner decision 53, docs/regression_ledger.md 10.348). The
# CI job stays as it is: it runs on a clean Windows runner, which is a state this machine cannot
# reproduce.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/pwsh_probe.sh"
source "${REPO_ROOT}/setup/pinned_values/pinned_values.sh"

info "Tier 1: the Windows installer unit tests"

RUNNER="${E2E_ROOT}/tier1/windows_pester.ps1"

PWSH="$(find_runnable_pwsh)" || true
if [[ -z "${PWSH}" ]]; then
    skip "the Pester suite passes" "no PowerShell 7 that runs was found here"
    finish "Windows installer unit tests"
    return 0 2>/dev/null || exit 0
fi

pester_status=0
out="$("${PWSH}" -NoProfile -NonInteractive -File "${RUNNER}" -Verbosity None 2>&1 | tr -d '\r')" || pester_status=$?

pinned="$(pinned_value gate_pester_version)" || pinned=""
version="$(sed -n 's/^PESTER version=//p' <<<"${out}" | sed -n 1p)"
counts="$(sed -n 's/^TOTALS //p' <<<"${out}" | sed -n 1p)"
verdict="$(sed -n 's/^VERDICT //p' <<<"${out}" | sed -n 1p)"
problems="$(sed -n 's/^PROBLEM \(.*\)$/\1 |/p' <<<"${out}" | tr '\n' ' ')"
count_of() { sed -n "s/.*\<${1}=\([0-9][0-9]*\).*/\1/p" <<<"${counts}"; }

if [[ "${verdict}" == pass && ( -z "${pinned}" || "${version}" != "${pinned}" ) ]]; then
    fail "the Windows installer unit tests ran under a Pester other than the pinned one, so they prove nothing about it" \
         "the script printed PESTER version=${version:-nothing}, gate_pester_version pins '${pinned:-nothing readable}'"
elif [[ "${verdict}" == pass && "${pester_status}" -eq 0 && -n "$(count_of notrunbytag)" ]]; then
    pass "the Windows installer unit tests pass under Pester ${version}, the pinned version (${counts}, the $(count_of notrunbytag) not run are the Slow and Network tagged tests this check leaves out)"
elif [[ "${verdict}" == fail ]]; then
    fail "the Windows installer unit tests did not all pass or skip" "${counts:-no totals} | ${problems}"
else
    fail "the Pester run printed no verdict this check can trust, so it proves nothing" \
         "${PWSH} exited ${pester_status}, verdict '${verdict}', totals '${counts}': $(tr '\n' ' ' <<<"${out}" | tail -c 400)"
fi

finish "Windows installer unit tests"
