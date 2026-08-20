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
# Finding a runnable pwsh and converting a path for it are shared with windows_settings.sh, and both
# are fiddly enough that a second copy would be the one that rots. See pwsh_probe.sh.
source "$(dirname "${BASH_SOURCE[0]}")/pwsh_probe.sh"
# The pinned default Python compared at the bottom of this file is read through the shell end of
# the pinned values port, which is the only thing allowed to read the pins. See setup/pinned_values.
source "${REPO_ROOT}/setup/pinned_values/pinned_values.sh"

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

PWSH="$(find_runnable_pwsh || true)"

if [[ -z "${PWSH}" ]]; then
    skip "PowerShell parser compared against the YAML" "${PWSH_ABSENT_REASON}"
    finish "Windows mapping parse"
fi

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
#
# default_python is pinned as a reference to one of the python<minor>_id pins, and the port
# resolves it, so this is one lookup rather than the two-step dereference it used to be.
pinned_python="$(pinned_value default_python 2>/dev/null || true)"
pinned_minor="$(cut -d. -f1,2 <<<"${pinned_python}")"
mapped_python="$(awk '$1 == "python" { print $3 }' <<<"${yaml_mappings}")"
mapped_minor="${mapped_python#Python.Python.}"

if [[ -z "${pinned_minor}" || "${pinned_minor}" == "." ]]; then
    fail "could not read the pinned default Python" \
         "pinned_value default_python answered '${pinned_python}', so either nothing pins it or no Python 3.11 or newer is on PATH for the reader"
elif [[ "${pinned_minor}" == "${mapped_minor}" ]]; then
    pass "the Windows python mapping matches default_python (${pinned_minor})"
else
    fail "the Windows python mapping and default_python disagree" \
         "the pinned default_python is ${pinned_python} (minor ${pinned_minor}) but vars/Windows.yaml maps python to ${mapped_python}"
fi

finish "Windows mapping parse"
