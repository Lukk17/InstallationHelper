#!/usr/bin/env bash
#
# Sourceable helper, not a check of its own. Sourced by every tier 1 check that has to run something
# in PowerShell, currently windows_mapping.sh, windows_settings.sh, powershell_variables.sh,
# pinned_values.sh and windows_pester.sh.
#
# It lives in one file because two copies of one piece of shell, one of them fixed and the other not,
# is the wizard toggle parse desync in docs/regression_ledger.md.

# find_runnable_pwsh
#
# Prints the path of a PowerShell 7 that actually runs, or nothing with a non-zero status. The
# candidate is probed by running something trivial and checking the output, rather than trusted
# because it is on PATH.
find_runnable_pwsh() {
    command -v pwsh &>/dev/null || return 1
    if [[ "$(pwsh -NoProfile -NonInteractive -Command 'Write-Output E2EOK' 2>/dev/null | tr -d '\r')" == *E2EOK* ]]; then
        printf '%s' pwsh
        return 0
    fi
    return 1
}

# The reason a check reports when find_runnable_pwsh comes back empty. Shared so every check says the
# same true thing rather than one of them going stale.
# Read by the five checks that source this file, never inside it.
# shellcheck disable=SC2034
PWSH_ABSENT_REASON="No runnable PowerShell 7 found. The gate image installs pwsh from e2e/gate/provision.sh, so this means the image did not get it: rebuild it with bash e2e/run.sh."
