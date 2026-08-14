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

# Locate PowerShell 7. On Windows this is pwsh.exe reached from WSL through interop.
PWSH=""
for candidate in pwsh pwsh.exe; do
    command -v "${candidate}" &>/dev/null && { PWSH="${candidate}"; break; }
done

if [[ -z "${PWSH}" ]]; then
    warn "PowerShell 7 not found, so the PowerShell side of this comparison is skipped."
    warn "On Windows run this from WSL, where pwsh.exe is reachable through interop."
    warn "Skipped, NOT passed: the parsers were not compared."
    finish "Windows mapping parse"
fi

# Windows-side paths, because pwsh.exe launched through WSL interop cannot read a /mnt path.
win_ps_file="$(command -v wslpath &>/dev/null && wslpath -w "${PS_FILE}" || echo "${PS_FILE}")"
win_mapping="$(command -v wslpath &>/dev/null && wslpath -w "${MAPPING_YAML}" || echo "${MAPPING_YAML}")"

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

finish "Windows mapping parse"
