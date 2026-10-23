#!/usr/bin/env bash
#
# Tier 1: the manual Windows install script and page must say what vars/Windows.yaml says.
#
# docs/manual/windows/install.ps1 and windows_manual_install.md are the by-hand route to the same
# software set the wizard installs, and nothing compared them with the mapping file. By 2026-10-11
# they had drifted in every direction at once: they still installed BillStewart.SyncthingWindowsSetup
# after the mapping had moved to Syncthing.Syncthing, still named ShiningLight.OpenSSL.Light, whose
# download answers 404, still installed the Razer Cortex Store id the mapping had dropped, missed
# fourteen packages the mapping had gained, and pinned no scope at all, so every machine pin and
# every user pin the wizard honours was left to winget on the manual route. Slack and Claude
# Desktop also needed an elevated winget for their machine-wide msix at the time, which neither
# said. Both are per user again since GitHub sweep 38130934506, and Syncthing's portable still
# needs one.
#
# Asserted, with each side read by its own expression so one mistake cannot hide on both:
#   1. the script installs exactly the mappings whose toggle is on by default, all.yaml overlaid by
#      windows.yaml, with the manager, id, source, scope, installer type and machine conditions the
#      mapping names;
#   2. the script decides what needs an elevated winget from the same installer types, and opens
#      the same Syncthing ports and writes the same logon shortcut arguments as
#      setup/windows/WindowsSoftware.ps1;
#   3. the page carries the exact install command of every mapping, scope and source included, and
#      no install command in its package tables names anything the mapping file does not;
#   4. every row whose install needs an elevated winget says so;
# and, because setup/software.md drifted the same way, that every Windows command there names a
# package the mapping file or setup/windows/WindowsCustomInstalls.ps1 installs.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

MAPPING_YAML="${ANSIBLE_DIR}/vars/Windows.yaml"
ALL_VARS="${ANSIBLE_DIR}/group_vars/all.yaml"
WINDOWS_VARS="${ANSIBLE_DIR}/group_vars/windows.yaml"
SOFTWARE_PS1="${REPO_ROOT}/setup/windows/WindowsSoftware.ps1"
MANUAL_PS1="${REPO_ROOT}/docs/manual/windows/install.ps1"
MANUAL_MD="${REPO_ROOT}/docs/manual/windows/windows_manual_install.md"

info "Tier 1: the manual Windows install against vars/Windows.yaml"

for f in "${MAPPING_YAML}" "${ALL_VARS}" "${WINDOWS_VARS}" "${SOFTWARE_PS1}" "${MANUAL_PS1}" "${MANUAL_MD}"; do
    [[ -f "${f}" ]] || { fail "a file this check compares is missing" "${f}"; finish "manual Windows install"; }
done

# --- the mapping side ------------------------------------------------------------------------------
yaml_field() { sed -nE "s/.*[{,][[:space:]]*$1:[[:space:]]*\"?([^\", }]*)\"?[[:space:]]*[,}].*/\1/p" <<<"$2"; }

declare -A default_on=()
while read -r key value; do
    default_on["${key#install_}"]="${value}"
done < <({ yaml_bool_toggles "${ALL_VARS}"; yaml_bool_toggles "${WINDOWS_VARS}"; } | grep '^install_')

# The installer types that need an elevated winget, read out of the wizard rather than restated.
admin_types="$(sed -nE "s/^\\\$script:WingetAdminInstallerTypes = @\((.*)\)$/\1/p" "${SOFTWARE_PS1}" | tr -d "' " | tr ',' '\n' | sort)"
if [[ -z "${admin_types}" ]]; then
    fail "could not read \$script:WingetAdminInstallerTypes out of WindowsSoftware.ps1" "${SOFTWARE_PS1}"
    finish "manual Windows install"
fi

expected_script=() expected_commands=() elevated_ids=()
declare -A mapped_command=()
while IFS= read -r line; do
    key="$(sed -nE 's/^  ([a-z0-9_]+):.*/\1/p' <<<"${line}")"
    manager="$(yaml_field manager "${line}")"
    package="$(yaml_field package "${line}")"
    source_name="$(yaml_field source "${line}")"
    scope="$(yaml_field scope "${line}")"
    kind="$(yaml_field installer_type "${line}")"
    client="$(yaml_field client_only "${line}")"
    nvidia="$(yaml_field requires_nvidia_gpu "${line}")"

    if [[ "${manager}" == "winget" ]]; then
        command="winget install -e --id ${package}"
        [[ -n "${source_name}" ]] && command+=" --source ${source_name}"
        [[ -n "${scope}" ]] && command+=" --scope ${scope}"
        if [[ "${scope}" == "machine" ]] && grep -qxF "${kind}" <<<"${admin_types}"; then
            elevated_ids+=("${package}")
        fi
    else
        command="choco install -y ${package}"
    fi
    expected_commands+=("${command}")
    mapped_command["${command}"]=1

    if [[ "${default_on[${key}]:-false}" == "true" ]]; then
        expected_script+=("${manager}|${package}|${source_name}|${scope}|${kind}|${client:-false}|${nvidia:-false}")
    fi
done < <(tr -d '\r' <"${MAPPING_YAML}" | grep -E '^  [a-z0-9_]+: \{')

if [[ ${#expected_commands[@]} -eq 0 ]]; then
    fail "no mapping could be read out of vars/Windows.yaml, so nothing here means anything" "${MAPPING_YAML}"
    finish "manual Windows install"
fi

# --- 1. the script's package list ------------------------------------------------------------------
ps_value() { sed -nE "s/.*[{;][[:space:]]*$1 = '([^']*)'.*/\1/p" <<<"$2"; }
ps_flag() { if grep -qE "[{;][[:space:]]*$1 = \\\$true" <<<"$2"; then echo true; else echo false; fi; }

actual_script=()
while IFS= read -r line; do
    actual_script+=("$(ps_value Manager "${line}")|$(ps_value Id "${line}")|$(ps_value Source "${line}")|$(ps_value Scope "${line}")|$(ps_value InstallerType "${line}")|$(ps_flag ClientOnly "${line}")|$(ps_flag RequiresNvidiaGpu "${line}")")
done < <(tr -d '\r' <"${MANUAL_PS1}" | sed -n '/^\$Packages = @($/,/^)$/p' | grep -E '^[[:space:]]+@\{')

if [[ ${#actual_script[@]} -eq 0 ]]; then
    fail "no package line could be read out of the \$Packages table in install.ps1, so this check proves nothing" "${MANUAL_PS1}"
else
    script_diff="$(diff <(printf '%s\n' "${expected_script[@]}" | sort) <(printf '%s\n' "${actual_script[@]}" | sort) || true)"
    if [[ -z "${script_diff}" ]]; then
        pass "install.ps1 installs exactly the ${#expected_script[@]} mappings on by default, with the id, source, scope, installer type and conditions vars/Windows.yaml names"
    else
        fail "install.ps1 and the default-on mappings in vars/Windows.yaml disagree (< mapping, > script; manager|id|source|scope|installer_type|client_only|requires_nvidia_gpu)" \
             "$(grep -E '^[<>]' <<<"${script_diff}" | tr '\n' ' ')"
    fi
fi

# --- 2. the elevation rule and the Syncthing steps -------------------------------------------------
script_types="$(sed -nE "s/^\\\$WingetAdminInstallerTypes = @\((.*)\)$/\1/p" "${MANUAL_PS1}" | tr -d "' " | tr ',' '\n' | sort)"
assert_eq "install.ps1 sends the same installer types to an elevated winget as the wizard" \
    "$(tr '\n' ' ' <<<"${admin_types}")" "$(tr '\n' ' ' <<<"${script_types}")"

rules_of() { grep -oE "Name = 'InstallationHelper-Syncthing-[A-Z]+-[0-9]+'; Protocol = '[A-Z]+'; Port = [0-9]+" "$1" | sort; }
wizard_rules="$(rules_of "${SOFTWARE_PS1}")"
if [[ -n "${wizard_rules}" && "${wizard_rules}" == "$(rules_of "${MANUAL_PS1}")" ]]; then
    pass "install.ps1 opens the same $(grep -c . <<<"${wizard_rules}") Syncthing firewall rules as the wizard"
else
    fail "install.ps1 and the wizard disagree about Syncthing's firewall rules" \
         "wizard: $(tr '\n' ' ' <<<"${wizard_rules}") script: $(rules_of "${MANUAL_PS1}" | tr '\n' ' ')"
fi

startup_of() { sed -nE "s/^\\\$(script:)?SyncthingStartupArguments = '([^']*)'$/\2/p" "$1"; }
wizard_startup="$(startup_of "${SOFTWARE_PS1}")"
if [[ -n "${wizard_startup}" && "${wizard_startup}" == "$(startup_of "${MANUAL_PS1}")" ]] \
    && grep -qF -- "\$s.Arguments = '${wizard_startup}'" "${MANUAL_MD}"; then
    pass "install.ps1 and the page start Syncthing at logon with the wizard's arguments, ${wizard_startup}"
else
    fail "the Syncthing logon shortcut arguments differ between the wizard, install.ps1 and the page" \
         "wizard: '${wizard_startup}' script: '$(startup_of "${MANUAL_PS1}")'"
fi

# --- 3. the page's commands ------------------------------------------------------------------------
missing_rows=()
for command in "${expected_commands[@]}"; do
    grep -qF -- "\`${command}\`" "${MANUAL_MD}" || missing_rows+=("${command}")
done
if [[ ${#missing_rows[@]} -eq 0 ]]; then
    pass "the page carries the exact install command of all ${#expected_commands[@]} mappings, scope and source included"
else
    fail "the page is missing the install command of mappings, or gives it without the scope or source the mapping pins" \
         "$(printf '%s | ' "${missing_rows[@]}")"
fi

# Only the package tables, which end where the toolchain section begins. That section lists what
# setup/windows/WindowsCustomInstalls.ps1 and WindowsNpmTools.ps1 install, which is not a mapping.
stray_rows=()
while IFS= read -r command; do
    [[ -n "${command}" && ! -v "mapped_command[${command}]" ]] && stray_rows+=("${command}")
done < <(sed '/^## Developer toolchain/,$d' "${MANUAL_MD}" | grep -oE '`(winget install -e --id|choco install -y) [^`]*`' | tr -d '`')
if [[ ${#stray_rows[@]} -eq 0 ]]; then
    pass "no install command in the page's package tables names a package or a flag vars/Windows.yaml does not"
else
    fail "the page installs packages, or uses flags, that vars/Windows.yaml does not map" "$(printf '%s | ' "${stray_rows[@]}")"
fi

# setup/software.md carries a Windows column of the same commands without the scope, which its own
# introduction explains, and it had drifted the same way: OpenSSL, HWiNFO and GlassWire still named
# the winget ids the mapping had left. A Windows command there must name a mapped package, or one
# setup/windows/WindowsCustomInstalls.ps1 installs by id.
declare -A known_package=()
while IFS= read -r command; do known_package["${command##* }"]=1; done < <(printf '%s\n' "${expected_commands[@]}" | sed -E 's/ --(source|scope) [a-z]+//g')
while IFS= read -r package; do known_package["${package}"]=1; done < <(grep -oE "PackageId '[^']+'" "${REPO_ROOT}/setup/windows/WindowsCustomInstalls.ps1" | sed -E "s/PackageId '//; s/'$//")
SOFTWARE_MD="${REPO_ROOT}/setup/software.md"
unknown=()
while IFS= read -r package; do
    [[ -n "${package}" && ! -v "known_package[${package}]" ]] && unknown+=("${package}")
done < <(grep -oE '`(winget install -e --id|choco install -y) [^ `]+' "${SOFTWARE_MD}" | sed -E 's/.* //')
if [[ ${#unknown[@]} -eq 0 ]]; then
    pass "every Windows command in setup/software.md names a package vars/Windows.yaml maps or WindowsCustomInstalls.ps1 installs"
else
    fail "setup/software.md gives Windows commands for packages nothing installs" "${unknown[*]}"
fi

# --- 4. the rows that need an elevated winget say so -----------------------------------------------
unsaid=()
for package in "${elevated_ids[@]}"; do
    grep -qF 'elevated PowerShell' <<<"$(grep -F -- "--id ${package} --scope machine\`" "${MANUAL_MD}")" || unsaid+=("${package}")
done
if [[ ${#elevated_ids[@]} -eq 0 ]]; then
    fail "no mapping needs an elevated winget, which cannot be true while Syncthing is a machine-wide portable" "${MAPPING_YAML}"
elif [[ ${#unsaid[@]} -eq 0 ]]; then
    pass "every one of the ${#elevated_ids[@]} rows whose install needs an elevated winget says so"
else
    fail "rows whose machine-wide install needs an elevated winget do not say so" "${unsaid[*]}"
fi

finish "manual Windows install"
