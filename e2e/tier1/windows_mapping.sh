#!/usr/bin/env bash
#
# Tier 1: the PowerShell Windows installer must read vars/Windows.yaml the same way the
# YAML actually says.
#
# Windows software is installed natively by setup/windows/WindowsSoftware.ps1 rather than
# by Ansible, because Ansible runs inside WSL and its facts describe the WSL distribution,
# so every task gated on Windows is skipped. The toggles and mappings stay in the YAML as
# the single source of truth and only the executor differs, which means the PowerShell
# parser is now a second reader of a file the playbook also reads. Two readers of one
# format drift. That is exactly how the bash and PowerShell wizards ended up disagreeing
# about toggle state for months. See docs/regression_ledger.md.
#
# This check extracts the mappings independently in bash and compares. It needs PowerShell
# 7, which on Windows is reachable from WSL through interop. Where PowerShell is absent the
# check says so and skips rather than silently passing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

PS_FILE="${REPO_ROOT}/setup/windows/WindowsSoftware.ps1"
MAPPING_YAML="${ANSIBLE_DIR}/vars/Windows.yaml"

info "Tier 1: Windows mapping parse"

[[ -f "${PS_FILE}" ]] || { fail "setup/windows/WindowsSoftware.ps1 is missing" "${PS_FILE}"; finish "Windows mapping parse"; }

# Independent extraction. Deliberately a different expression from the PowerShell one, so a
# mistake in one is not reproduced by the other.
yaml_mappings="$(
    sed -E 's/[[:space:]]+$//' "${MAPPING_YAML}" \
        | grep -E '^  [a-z0-9_]+: \{' \
        | sed -E 's/^  ([a-z0-9_]+): \{[[:space:]]*manager:[[:space:]]*"([a-z_]+)"[[:space:]]*,[[:space:]]*package:[[:space:]]*"([^"]*)"[[:space:]]*(,[[:space:]]*source:[[:space:]]*"([a-z]+)"[[:space:]]*)?\}.*/\1 \2 \3 \5/' \
        | awk '{ if ($4 == "") $4 = "winget"; print $1, $2, $3, $4 }' \
        | sort
)"

n_yaml="$(grep -c . <<<"${yaml_mappings}")"

# Every line that looks like a mapping must have parsed. A line that looks like one and
# silently does not is a package the user asked for and did not get.
n_looks_like="$(grep -cE '^  [a-z0-9_]+: \{' "${MAPPING_YAML}")"
assert_eq "every mapping-shaped line parses in bash" "${n_looks_like}" "${n_yaml}"

# Locate a PowerShell 7 that actually runs. `command -v pwsh.exe` is not enough: on Windows the
# first hit is often the Store app-execution-alias stub under WindowsApps, which is a zero-length
# reparse point that WSL cannot execute, and trying produces
# "pwsh.exe: line 1: MZ: command not found" as WSL reads the PE header as a script. So each
# candidate is probed by running something trivial and checking the output, rather than trusted
# because it exists.
PWSH=""
for candidate in \
    pwsh \
    "/mnt/c/Program Files/PowerShell/7/pwsh.exe" \
    "/mnt/c/Program Files/PowerShell/7-preview/pwsh.exe" \
    pwsh.exe
do
    command -v "${candidate}" &>/dev/null || [[ -x "${candidate}" ]] || continue
    if [[ "$("${candidate}" -NoProfile -NonInteractive -Command 'Write-Output E2EOK' 2>/dev/null | tr -d '\r')" == *E2EOK* ]]; then
        PWSH="${candidate}"
        break
    fi
done

if [[ -z "${PWSH}" ]]; then
    skip "PowerShell parser compared against the YAML" \
         "No runnable PowerShell 7 found from here. On this machine pwsh is installed only as a Microsoft Store app, whose WindowsApps entry is an alias stub WSL cannot execute, so run this check from Windows with pwsh directly, or install PowerShell 7 inside WSL."
    finish "Windows mapping parse"
fi

# Windows-side paths, because a Windows pwsh cannot read the POSIX path this script sees, whether
# that path came from WSL (/mnt/d/...) or from Git Bash (/d/...). Two different converters, one per
# environment, and this check only ever runs usefully in one of the two: WSL has wslpath but on this
# machine the only pwsh is a Store alias stub WSL cannot execute, while Git Bash has cygpath and a
# pwsh that runs. Handing PowerShell an unconverted path is what made it report nothing at all.
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

win_ps_file="$(to_windows_path "${PS_FILE}")"
win_mapping="$(to_windows_path "${MAPPING_YAML}")"

# Paths are interpolated into the script text rather than passed as environment variables,
# because a WSL environment variable does not reach a Windows process unless it is listed in
# WSLENV, so the env-var version silently handed PowerShell an empty path. Single-quoted
# PowerShell strings take the backslashes literally, which is what a Windows path needs.
ps_script="\$ErrorActionPreference = 'Stop'
if (\$PSStyle) { \$PSStyle.OutputRendering = 'PlainText' }
. '${win_ps_file}'
\$m = Get-WindowsSoftwareMapping -WindowsMappingPath '${win_mapping}'
\$m.GetEnumerator() | Sort-Object Key | ForEach-Object {
    '{0} {1} {2} {3}' -f \$_.Key, \$_.Value.Manager, \$_.Value.Package, \$_.Value.Source
}"

ps_raw="$("${PWSH}" -NoProfile -NonInteractive -Command "${ps_script}" 2>&1 | tr -d '\r' || true)"
ps_mappings="$(grep -E '^[a-z0-9_]+ [a-z_]+ ' <<<"${ps_raw}" | sort || true)"

if [[ -z "${ps_mappings}" ]]; then
    fail "the PowerShell parser returned nothing" "$(head -5 <<<"${ps_raw}" | tr '\n' ' ')"
    finish "Windows mapping parse"
fi

n_ps="$(grep -c . <<<"${ps_mappings}")"
assert_eq "PowerShell parses the same number of mappings as the YAML has" "${n_yaml}" "${n_ps}"

if [[ "${yaml_mappings}" == "${ps_mappings}" ]]; then
    pass "PowerShell and the YAML agree on all ${n_yaml} mappings, including manager and source"
else
    fail "the PowerShell parser disagrees with the YAML" \
         "$(diff <(echo "${yaml_mappings}") <(echo "${ps_mappings}") | head -12 | tr '\n' ' ')"
fi

# A mapping with no toggle is dead data, and a toggle the installer will never see.
orphans=()
while read -r key _ _ _; do
    [[ -z "${key}" ]] && continue
    grep -qE "^install_${key}:" "${ANSIBLE_DIR}/group_vars/all.yaml" "${ANSIBLE_DIR}/group_vars/windows.yaml" \
        || orphans+=("${key}")
done <<<"${yaml_mappings}"

if [[ ${#orphans[@]} -eq 0 ]]; then
    pass "every Windows mapping has a matching install toggle"
else
    fail "Windows mappings with no install_ toggle anywhere, so nothing can ever select them" "${orphans[*]}"
fi

# Windows has no Pyenv, so install_python resolves to one interpreter chosen to match the pinned
# default. Two places now name a Python minor version and nothing kept them together: bumping
# default_python to 3.12 would leave Windows silently installing 3.11 while every other platform
# moved. This is the same two-sources-of-truth shape as the wizard toggle desync.
VERSIONS_FILE="${ANSIBLE_DIR}/group_vars/versions.yaml"
default_python_ref="$(grep -E '^default_python:' "${VERSIONS_FILE}" | sed -E 's/.*\{\{ *([a-z0-9_]+) *\}\}.*/\1/')"
pinned_python="$(grep -E "^${default_python_ref}:" "${VERSIONS_FILE}" | sed -E 's/^[^:]+:[[:space:]]*"?([^"]*)"?.*/\1/')"
pinned_minor="$(cut -d. -f1,2 <<<"${pinned_python}")"
mapped_python="$(awk '$1 == "python" { print $3 }' <<<"${yaml_mappings}")"
mapped_minor="${mapped_python#Python.Python.}"

if [[ -z "${pinned_minor}" || "${pinned_minor}" == "." ]]; then
    fail "could not read the pinned default Python out of versions.yaml" \
         "default_python points at '${default_python_ref}', which resolved to '${pinned_python}'"
elif [[ "${pinned_minor}" == "${mapped_minor}" ]]; then
    pass "the Windows python mapping matches default_python (${pinned_minor})"
else
    fail "the Windows python mapping and default_python disagree" \
         "versions.yaml default_python is ${pinned_python} (minor ${pinned_minor}) but vars/Windows.yaml maps python to ${mapped_python}"
fi

finish "Windows mapping parse"
