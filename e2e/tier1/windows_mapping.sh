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
# 7, which the gate image carries. Where PowerShell is absent the
# check says so and skips rather than silently passing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# Finding a runnable pwsh is shared with windows_settings.sh. See pwsh_probe.sh.
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
# Compared: the key, manager, package id, source and scope, with "-" for no scope. Scope was
# matched and dropped while Bruno was the only entry carrying one. Thirty entries carry one since
# 2026-10-11, each pinned so winget never chooses an installer for the elevated wizard, and a
# scope the PowerShell reader lost would hand that choice straight back to winget with nothing
# here noticing. Whether each package pins the scope it needs is winget_scope_pins.sh's question.
# installer_type is compared for the same reason, with "-" for none: it decides whether winget runs
# elevated, and a type the PowerShell reader lost would send a machine-scope msix or portable install
# to an unelevated winget that refuses it.
yaml_mappings="$(
    sed -E 's/[[:space:]]+$//' "${MAPPING_YAML}" \
        | grep -E '^  [a-z0-9_]+: \{' \
        | sed -E 's/^  ([a-z0-9_]+): \{[[:space:]]*manager:[[:space:]]*"([a-z_]+)"[[:space:]]*,[[:space:]]*package:[[:space:]]*"([^"]*)"[[:space:]]*(,[[:space:]]*source:[[:space:]]*"([a-z]+)"[[:space:]]*)?(,[[:space:]]*scope:[[:space:]]*"([a-z]+)"[[:space:]]*)?(,[[:space:]]*installer_type:[[:space:]]*"([a-z]+)"[[:space:]]*)?(,[[:space:]]*client_only:[[:space:]]*(true|false)[[:space:]]*)?(,[[:space:]]*user_context:[[:space:]]*(true|false)[[:space:]]*)?(,[[:space:]]*requires_nvidia_gpu:[[:space:]]*(true|false)[[:space:]]*)?(,[[:space:]]*verify_path:[[:space:]]*"[^"]*"[[:space:]]*)?\}.*/\1\t\2\t\3\t\5\t\7\t\9/' \
        | awk -F '\t' '{ if ($4 == "") $4 = "winget"; if ($5 == "") $5 = "-"; if ($6 == "") $6 = "-"; print $1 " " $2 " " $3 " " $4 " " $5 " " $6 }' \
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

ps_script="\$ErrorActionPreference = 'Stop'
if (\$PSStyle) { \$PSStyle.OutputRendering = 'PlainText' }
. '${PS_FILE}'
\$m = Get-WindowsSoftwareMapping -WindowsMappingPath '${MAPPING_YAML}'
\$m.GetEnumerator() | Sort-Object Key | ForEach-Object {
    '{0} {1} {2} {3} {4} {5}' -f \$_.Key, \$_.Value.Manager, \$_.Value.Package, \$_.Value.Source, \$(if (\$_.Value.Scope) { \$_.Value.Scope } else { '-' }), \$(if (\$_.Value.InstallerType) { \$_.Value.InstallerType } else { '-' })
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
    pass "PowerShell and the YAML agree on all ${n_yaml} mappings, including manager, source, scope and installer type"
else
    fail "the PowerShell parser disagrees with the YAML" \
         "$(diff <(echo "${yaml_mappings}") <(echo "${ps_mappings}") | head -12 | tr '\n' ' ')"
fi

# A mapping with no toggle is dead data, and a toggle the installer will never see. The one exception is a
# mapping WindowsCustomInstalls.ps1 declares it installs itself, in $script:CustomInstallMappingKeys, read from
# that declaration so the exception lasts only while the installer still names it.
custom_mappings="$(sed -n 's/^\$script:CustomInstallMappingKeys = @(\(.*\))$/\1/p' "${REPO_ROOT}/setup/windows/WindowsCustomInstalls.ps1" | tr -d "' " | tr ',' '\n')"
orphans=()
while read -r key _ _ _; do
    [[ -z "${key}" ]] && continue
    grep -qx "${key}" <<<"${custom_mappings}" && continue
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
#
# The adapter's status is read and branched on rather than thrown away with `2>/dev/null || true`.
# Its two failures are different kinds of news, and the single message they used to share had to
# name both of them and leave the reader to work out which had happened:
#
#   PINNED_VALUES_UNUSABLE  no Python 3.11 or newer could be found. Its other meaning, an argument
#                           that is not a pin name, cannot arise here because the name asked for
#                           below is a literal. This one skips rather than fails, for the same
#                           reason the absent pwsh above skips: a tool missing from this machine is
#                           not a defect in the repository, and the pins port being unreadable at
#                           all is already a failure of e2e/tier1/pinned_values.sh, which is the
#                           check that owns that question. Failing here too would report one
#                           environment problem twice while proving nothing about the mapping.
#   PINNED_VALUES_ABSENT    nothing pins default_python, which is a real defect here, because the
#                           Windows mapping then has nothing to be held against. It fails.
#   anything else           the reader's own refusal of the file, unreadable or invalid. It fails
#                           too, and quotes what the reader said.
python_log="$(mktemp)"
pinned_status=0
pinned_python="$(pinned_value default_python 2>"${python_log}")" || pinned_status=$?
pinned_why="$(tr '\n' ' ' <"${python_log}")"
rm -f "${python_log}"

pinned_minor="$(cut -d. -f1,2 <<<"${pinned_python}")"
mapped_python="$(awk '$1 == "python" { print $3 }' <<<"${yaml_mappings}")"
mapped_minor="${mapped_python#Python.Python.}"

if [[ "${pinned_status}" -eq "${PINNED_VALUES_UNUSABLE}" ]]; then
    skip "the Windows python mapping compared against the pinned default_python" "${pinned_why}"
elif [[ "${pinned_status}" -eq "${PINNED_VALUES_ABSENT}" ]]; then
    fail "nothing pins default_python, so the Windows python mapping has nothing to agree with" \
         "${pinned_why}"
elif [[ "${pinned_status}" -ne 0 ]]; then
    fail "the pinned values reader failed with status ${pinned_status}, so the pinned default Python could not be read" \
         "${pinned_why}"
elif [[ -z "${pinned_minor}" || "${pinned_minor}" == "." ]]; then
    fail "the pinned default Python does not read as a version" \
         "pinned_value default_python answered '${pinned_python}', which carries no <major>.<minor> to compare with vars/Windows.yaml"
elif [[ "${pinned_minor}" == "${mapped_minor}" ]]; then
    pass "the Windows python mapping matches default_python (${pinned_minor})"
else
    fail "the Windows python mapping and default_python disagree" \
         "the pinned default_python is ${pinned_python} (minor ${pinned_minor}) but vars/Windows.yaml maps python to ${mapped_python}"
fi

finish "Windows mapping parse"
