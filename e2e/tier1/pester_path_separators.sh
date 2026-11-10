#!/usr/bin/env bash
#
# Tier 1: no Pester test expects the forward slashes of a path it built with Join-Path.
#
# On Windows, Join-Path writes every forward slash of the child it is given as a backslash, and on
# Linux it leaves them alone. A test in e2e/tier1/windows/WindowsSoftware.Tests.ps1 passed
# (Join-Path $TestDrive 'KiCad/10.0/bin/kicad.exe') to the code under test and then asked Write-Host
# for '*KiCad/10.0/bin/kicad.exe does not exist, so KiCad.KiCad is not installed*'. It passed here,
# where the gate runs Pester on Linux, and failed on the Windows runner of GitHub runs 42852802501
# and 42852810353, because the message carried backslashes, docs/regression_ledger.md 10.270.
#
# So the parser is asked, not grep. e2e/tier1/pester_path_separators.ps1 parses every
# e2e/tier1/windows/*.Tests.ps1, and inside each It block takes every string constant handed to
# Join-Path that holds a forward slash. A string of the same It block that is an operand of -eq,
# -ne, -like, -notlike, -match or -notmatch, or sits inside a Should command, its -ParameterFilter
# included, fails the check when it holds two neighbouring segments of such a child joined by a
# forward slash, compared without case as -like does. Building the expectation from the path value
# itself, "$missing" or [WildcardPattern]::Escape($missing), holds on both platforms and passes.
#
# Only the It block itself is read. A Join-Path in BeforeEach does not count, because the KiCad 9
# verification tests create the file there with a forward-slash child and rightly expect the
# forward slashes of the mapping's own %ProgramFiles%/KiCad/9.0/bin/kicad.exe in the message.
#
# The reader is first run against a planted suite and must name exactly the planted mistakes, so a
# reader that finds nothing cannot pass for a suite that holds nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/pwsh_probe.sh"

LABEL="Pester path separators"
CLAIM="no Pester test expects the forward slashes of a path it built with Join-Path"

info "Tier 1: ${CLAIM}"

PWSH="$(find_runnable_pwsh)" || true
if [[ -z "${PWSH}" ]]; then
    skip "${CLAIM}" "${PWSH_ABSENT_REASON}"
    finish "${LABEL}"
fi

READER="${E2E_ROOT}/tier1/pester_path_separators.ps1"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

cat >"${work}/planted.Tests.ps1" <<'EOF'
Describe 'planted' {
    BeforeEach {
        $script:Mapped = Join-Path $TestDrive 'KiCad/9.0/bin/kicad.exe'
    }

    It 'expects the slashes of a Join-Path child in a ParameterFilter' {
        $code = Install-Thing @{ VerifyPath = (Join-Path $TestDrive 'KiCad/10.0/bin/kicad.exe') }
        Should -Invoke Write-Host -ParameterFilter { "$Object" -like '*KiCad/10.0/bin/kicad.exe does not exist*' }
    }

    It 'expects two segments of a Join-Path child in a Should argument' {
        $missing = Join-Path $TestDrive 'nowhere/deeper/kicad.exe'
        (Get-Verdict $missing).Reason | Should -BeLike '*deeper/kicad.exe does not exist'
    }

    It 'expects the slashes of a Join-Path child in a comparison outside Should' {
        $exe = Join-Path $TestDrive 'Programs/OpenCode/OpenCode.exe'
        @($global:Calls | Where-Object { $_ -like '*programs/opencode*' }).Count | Should -Be 1
    }

    It 'builds the expectation from the path it passes' {
        $missing = Join-Path $TestDrive 'nowhere/kicad.exe'
        $absent = "*$([WildcardPattern]::Escape($missing)) does not exist*"
        (Get-Verdict $missing).Reason | Should -Be "Chocolatey lists kicad, and $missing does not exist"
        Should -Invoke Write-Host -ParameterFilter { "$Object" -like $absent }
    }

    It 'expects the slashes of a mapping path whose file BeforeEach joined' {
        (Get-Verdict $script:Mapped).Reason | Should -BeLike '*KiCad/9.0/bin/kicad.exe does not exist'
    }

    It 'matches across any separator with a wildcard' {
        $missing = Join-Path $TestDrive 'nowhere/kicad.exe'
        (Get-Verdict $missing).Reason | Should -BeLike '*nowhere*kicad.exe does not exist'
    }

    It 'writes the slashes outside any expectation and joins inside Should' {
        New-Item -ItemType File -Path "$TestDrive/Tools/tool.exe" -Force
        Get-Tool | Should -Be (Join-Path $TestDrive 'Tools/tool.exe')
    }

    It 'expects slashes of a path no Join-Path in it built' -ForEach @(@{ Reason = '*Data/x.exe*' }) {
        $other = Join-Path $TestDrive 'Other\y.exe'
        (Get-Verdict 'Data/x.exe').Reason | Should -BeLike $Reason
    }
}
EOF

expected_planted="planted.Tests.ps1:8: It 'expects the slashes of a Join-Path child in a ParameterFilter' expects 'KiCad/10.0' from 'KiCad/10.0/bin/kicad.exe', which Join-Path at line 7 writes with a backslash on Windows
planted.Tests.ps1:13: It 'expects two segments of a Join-Path child in a Should argument' expects 'deeper/kicad.exe' from 'nowhere/deeper/kicad.exe', which Join-Path at line 12 writes with a backslash on Windows
planted.Tests.ps1:18: It 'expects the slashes of a Join-Path child in a comparison outside Should' expects 'Programs/OpenCode' from 'Programs/OpenCode/OpenCode.exe', which Join-Path at line 17 writes with a backslash on Windows
READ files=1 its=8 joins=7 slashed=6"

status=0
planted_output="$(cd "${work}" && "${PWSH}" -NoProfile -NonInteractive -File "${READER}" planted.Tests.ps1 2>&1 | tr -d '\r')" || status=$?
if [[ ${status} -eq 0 && "${planted_output}" == "${expected_planted}" ]]; then
    pass "the reader names exactly the three planted expectations and none of the five sound It blocks"
else
    fail "the reader names exactly the three planted expectations and none of the five sound It blocks" \
         "exit ${status}. Output: ${planted_output//$'\n'/ | }"
fi

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "${LABEL}"; }

suites=()
for suite in e2e/tier1/windows/*.Tests.ps1; do
    [[ -f "${suite}" ]] && suites+=("${suite}")
done

if [[ ${#suites[@]} -eq 0 ]]; then
    fail "${CLAIM}" "no e2e/tier1/windows/*.Tests.ps1 was found, so this proves nothing"
    finish "${LABEL}"
fi

status=0
repo_output="$("${PWSH}" -NoProfile -NonInteractive -File "${READER}" "${suites[@]}" 2>&1 | tr -d '\r')" || status=$?
tally=""
findings=()
while IFS= read -r line; do
    case "${line}" in
        READ\ *) tally="${line#READ }" ;;
        "")      ;;
        *)       findings+=("${line}") ;;
    esac
done <<<"${repo_output}"

if [[ ${status} -ne 0 || -z "${tally}" ]]; then
    fail "the reader could parse ${suites[*]}" "exit ${status}: ${repo_output//$'\n'/ | }"
elif [[ "${tally}" != "files=${#suites[@]} "* || "${tally}" == *" its=0 "* || "${tally}" == *" joins=0 "* ]]; then
    fail "${CLAIM}" "the reader read too little to prove anything: ${tally}, for ${#suites[@]} suite file(s)"
elif [[ ${#findings[@]} -eq 0 ]]; then
    pass "${CLAIM} (${tally})"
else
    for finding in "${findings[@]}"; do
        fail "a Pester test expects the forward slashes of a path it built with Join-Path, which Windows writes with backslashes, so build the expectation from the path value itself" \
             "${finding}"
    done
fi

finish "${LABEL}"
