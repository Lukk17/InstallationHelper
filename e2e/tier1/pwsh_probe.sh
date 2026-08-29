#!/usr/bin/env bash
#
# Sourceable helper, not a check of its own. Sourced by every tier 1 check that has to run something
# in PowerShell, currently windows_mapping.sh and windows_settings.sh.
#
# It lives in one file for the reason wsl_delegate.sh does: two copies of one piece of shell, one of
# them fixed and the other not, is the wizard toggle parse desync in docs/regression_ledger.md. The
# probe below is subtle enough that a second hand-written copy would have been the weaker one.

# find_runnable_pwsh
#
# Prints the path of a PowerShell 7 that actually runs, or nothing with a non-zero status.
#
# `command -v pwsh.exe` is not enough: on Windows the first hit is often the Store
# app-execution-alias stub under WindowsApps, and whether WSL can execute one is a property of the
# Windows build rather than something to assume. It ran on 2026-08-20 and it has failed before, with
# "pwsh.exe: line 1: MZ: command not found" as WSL reads the PE header as
# a script. So each candidate is probed by running something trivial and checking the output, rather
# than trusted because it exists.
find_runnable_pwsh() {
    local candidate
    for candidate in \
        pwsh \
        "/mnt/c/Program Files/PowerShell/7/pwsh.exe" \
        "/mnt/c/Program Files/PowerShell/7-preview/pwsh.exe" \
        pwsh.exe
    do
        command -v "${candidate}" &>/dev/null || [[ -x "${candidate}" ]] || continue
        if [[ "$("${candidate}" -NoProfile -NonInteractive -Command 'Write-Output E2EOK' 2>/dev/null | tr -d '\r')" == *E2EOK* ]]; then
            printf '%s' "${candidate}"
            return 0
        fi
    done
    return 1
}

# The reason a check reports when find_runnable_pwsh comes back empty. Shared so both checks say the
# same true thing about this machine rather than one of them going stale.
# Read by the five checks that source this file, never inside it.
# shellcheck disable=SC2034
PWSH_ABSENT_REASON="No runnable PowerShell 7 found from here. Every candidate was tried by running it, not by finding it on PATH. On this machine pwsh is installed only as a Microsoft Store app, and its WindowsApps alias does run from WSL when Windows lets it, so this message means it did not this time: run this check from Windows with pwsh directly, or install PowerShell 7 inside WSL."

# to_windows_path <posix path>
#
# Windows-side path, because a Windows pwsh cannot read the POSIX path these scripts see, whether that
# path came from WSL (/mnt/d/...) or from Git Bash (/d/...). Two different converters, one per
# environment, and a check only ever runs usefully in one of the two: WSL has wslpath but on this
# machine the only pwsh is a Store alias stub WSL cannot execute, while Git Bash has cygpath and a
# pwsh that runs. Handing PowerShell an unconverted path is what made the mapping check report
# nothing at all.
to_windows_path() {
    local p="$1"
    if command -v wslpath &>/dev/null; then
        wslpath -w "${p}"
    elif command -v cygpath &>/dev/null; then
        cygpath -w "${p}"
    else
        printf '%s' "${p}"
    fi
}
