#!/usr/bin/env bash
#
# Tier 1: the native Windows system settings must agree with the toggles that select them, and the
# feature list a checker is shown must be the one the machine actually gets.
#
# setup/windows/WindowsSettings.ps1 applies the four Windows system settings natively. The
# windows_core task files that used to express them could never run, because both wizards invoke the
# playbook from inside WSL as `-i localhost, -c local`, so ansible_os_family reports Debian and every
# Windows-gated task is skipped. Those files have been deleted, so this file is the only place the
# four settings exist at all. See docs/regression_ledger.md.
#
# Three invariants matter.
#
# 1. The optional features enable_hyperv turns on are declared once, they lead with the two features
#    WSL 2 needs, and the applier is handed that declaration rather than a list of its own. Order is
#    part of the claim: the elevated child enables them in the order given, and VirtualMachinePlatform
#    and Microsoft-Windows-Subsystem-Linux are the two WSL 2 cannot start without.
#
# 2. The accessor a checker asks returns exactly that declaration. Anything else means this check and
#    the machine are looking at different lists, which is the shape of failure the deleted YAML file
#    used to stand in for.
#
# 3. Every setting key this file claims must be a real toggle, and every system-setting toggle a
#    Windows user can tick must be claimed by this file. Both directions, because a key with no
#    toggle can never be selected and a toggle with no key is ledger rule 4: a toggle is not
#    implemented until something consumes it, and install_gradle sat unimplemented behind a comment
#    claiming otherwise.
#
# The third is also where toggle_coverage.sh stops. That check reasons about install_ toggles only,
# resolving each one to a package mapping or to a task, and these four have neither and never will:
# they are system settings with no vars/Windows.yaml entry possible and one consumer, this file.
# Teaching toggle_coverage a fifth non-install shape would mean special-casing Windows inside it a
# second time, so the non-install half of Windows coverage lives here, next to the only thing that
# implements it.
#
# The two lists are asked of the file through Get-WindowsOptionalFeatureName and
# Get-WindowsSettingKey rather than parsed out of it, which is why they are exported. Asking means
# the check sees what the applier sees. It also means those comparisons need a runnable PowerShell 7,
# and where there is none they report SKIP rather than passing quietly, the same way the mapping
# check does. The two assertions that need no PowerShell are that both accessors still exist and that
# the feature declaration is what reaches the applier, so a SKIP cannot hide either.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/pwsh_probe.sh"

PS_FILE="${REPO_ROOT}/setup/windows/WindowsSettings.ps1"
SOFTWARE_PS1="${REPO_ROOT}/setup/windows/WindowsSoftware.ps1"
SETUP_PS1="${REPO_ROOT}/setup/setup.ps1"
ALL_VARS="${ANSIBLE_DIR}/group_vars/all.yaml"
WINDOWS_VARS="${ANSIBLE_DIR}/group_vars/windows.yaml"

info "Tier 1: Windows system settings"

for f in "${PS_FILE}" "${SOFTWARE_PS1}" "${SETUP_PS1}" "${ALL_VARS}" "${WINDOWS_VARS}"; do
    [[ -f "${f}" ]] || { fail "a file this check compares is missing" "${f}"; finish "Windows system settings"; }
done

# The two accessors, asserted in bash so their removal fails the gate even on a machine where the
# rest of this check skips. Deleting one and going back to parsing the dispatch would take this check
# with it, silently, which is the failure mode the whole file argues against.
missing_accessors=()
for fn in Get-WindowsSettingKey Get-WindowsOptionalFeatureName; do
    grep -qE "^function ${fn} \{" "${PS_FILE}" || missing_accessors+=("${fn}")
done
if [[ ${#missing_accessors[@]} -eq 0 ]]; then
    pass "WindowsSettings.ps1 still exports both lists a checker can ask for"
else
    fail "WindowsSettings.ps1 no longer exports every list this check asks it for, so nothing can compare them" \
         "${missing_accessors[*]}"
    finish "Windows system settings"
fi

# --- invariant 1: one declaration, in the right order, and it is what the applier is handed -------
# Read out of the declared array rather than by matching feature names, so a name added to it that
# this check does not recognise still counts instead of vanishing. The call sites are checked in the
# same assertion because a declaration nothing passes on is decoration: Enable-WindowsFeatureSet
# takes -FeatureName, so a second literal list at the call site would enable something else entirely
# while every other assertion here still passed.
declared_features="$(
    sed -n '/^\$script:OptionalFeatureNames = @($/,/^)$/p' "${PS_FILE}" \
        | sed -nE "s/^[[:space:]]+'([^']+)'[[:space:]]*$/\1/p"
)"
n_declared="$(grep -c . <<<"${declared_features}" || true)"

# Call sites only, so the function definition and any prose mentioning it are excluded.
mapfile -t feature_callsites < <(
    grep -nE 'Enable-WindowsFeatureSet' "${PS_FILE}" \
        | grep -vE ':[[:space:]]*#' \
        | grep -vE ':function Enable-WindowsFeatureSet \{'
)

feature_problems=()
[[ "${n_declared}" -ge 2 ]] || feature_problems+=("the declared feature list has ${n_declared} entries")
[[ "$(sed -n 1p <<<"${declared_features}")" == 'VirtualMachinePlatform' ]] \
    || feature_problems+=("VirtualMachinePlatform is not first")
[[ "$(sed -n 2p <<<"${declared_features}")" == 'Microsoft-Windows-Subsystem-Linux' ]] \
    || feature_problems+=("Microsoft-Windows-Subsystem-Linux is not second")
[[ ${#feature_callsites[@]} -gt 0 ]] || feature_problems+=("nothing calls Enable-WindowsFeatureSet")
for line in "${feature_callsites[@]}"; do
    [[ "${line}" == *'Enable-WindowsFeatureSet -FeatureName (Get-WindowsOptionalFeatureName)'* ]] \
        || feature_problems+=("a call site passes something other than the declaration: ${line}")
done

if [[ ${#feature_problems[@]} -eq 0 ]]; then
    pass "the ${n_declared} optional features are declared once, WSL 2's two lead them, and every call site enables that declaration"
else
    fail "the optional feature declaration and what gets enabled do not line up" "${feature_problems[*]}"
    finish "Windows system settings"
fi

PWSH="$(find_runnable_pwsh || true)"

if [[ -z "${PWSH}" ]]; then
    skip "WindowsSettings.ps1's accessors compared against the declaration and the toggles" "${PWSH_ABSENT_REASON}"
    finish "Windows system settings"
fi

# Both files are dot-sourced, in the order setup.ps1 uses, because WindowsSettings.ps1 documents that
# it reads toggles through Get-WindowsGroupVarToggle in WindowsSoftware.ps1. Loading it the way the
# wizard loads it means this check cannot pass on a file the wizard could not load.
#
# Paths are interpolated into the script text rather than passed as environment variables, because a
# WSL environment variable does not reach a Windows process unless it is listed in WSLENV. Each item
# is printed on its own prefixed line so the order survives.
ps_script="\$ErrorActionPreference = 'Stop'
if (\$PSStyle) { \$PSStyle.OutputRendering = 'PlainText' }
. '$(to_windows_path "${SOFTWARE_PS1}")'
. '$(to_windows_path "${PS_FILE}")'
foreach (\$n in (Get-WindowsOptionalFeatureName)) { 'E2E_FEATURE ' + \$n }
foreach (\$k in (Get-WindowsSettingKey)) { 'E2E_KEY ' + \$k }"

ps_raw="$("${PWSH}" -NoProfile -NonInteractive -Command "${ps_script}" 2>&1 | tr -d '\r' || true)"
ps_features="$(sed -n 's/^E2E_FEATURE //p' <<<"${ps_raw}")"
ps_keys="$(sed -n 's/^E2E_KEY //p' <<<"${ps_raw}")"

if [[ -z "${ps_features}" || -z "${ps_keys}" ]]; then
    fail "the WindowsSettings.ps1 accessors returned nothing" "$(head -5 <<<"${ps_raw}" | tr '\n' ' ')"
    finish "Windows system settings"
fi

# --- invariant 2: the accessor returns the declaration ------------------------------------------
# Order is compared as well as membership, because the elevated child enables them in the order
# given. This is the successor to the comparison against windows_core/tasks/windows_features.yaml,
# which was deleted with the rest of the unreachable Windows Ansible: the second list is now the
# file's own declaration, so what this catches is an accessor that filters, reorders or answers with
# something else entirely, which is the only way the applier and a checker can still disagree.
if [[ "${declared_features}" == "${ps_features}" ]]; then
    pass "Get-WindowsOptionalFeatureName returns the ${n_declared} declared optional features, in the declared order"
else
    fail "Get-WindowsOptionalFeatureName and the declaration in the same file disagree about the optional features enable_hyperv turns on" \
         "$(diff <(echo "${declared_features}") <(echo "${ps_features}") | head -12 | tr '\n' ' ')"
fi
# --- invariant 2, forward: every declared key is a real toggle ---------------------------------
# The pair of files is all.yaml overlaid by windows.yaml, which is what Get-WindowsGroupVarToggle
# reads and the precedence the playbook and both wizards use. windows.yaml alone would be the wrong
# question: set_custom_wallpaper is cross-platform and lives in all.yaml, so asking only the
# Windows file would report a defect on a correct tree.
declared_toggles="$(
    {
        yaml_bool_toggles "${ALL_VARS}"
        yaml_bool_toggles "${WINDOWS_VARS}"
    } | awk '{ print $1 }' | sort -u
)"

no_toggle=()
while IFS= read -r key; do
    [[ -z "${key}" ]] && continue
    grep -qxF "${key}" <<<"${declared_toggles}" || no_toggle+=("${key}")
done <<<"${ps_keys}"

if [[ ${#no_toggle[@]} -eq 0 ]]; then
    pass "all $(grep -c . <<<"${ps_keys}") setting keys are boolean toggles in group_vars all.yaml or windows.yaml"
else
    fail "WindowsSettings.ps1 claims setting keys that no group_vars toggle defines, so nothing can ever select them" \
         "${no_toggle[*]}"
fi

# --- invariant 2, reverse: every visible system-setting toggle is claimed ----------------------
# A system setting is a boolean toggle whose key does not start with install_, and visible means the
# wizard shows it: $ExcludedVars is read out of setup.ps1 rather than restated, and wizard_parse.sh
# separately proves the bash wizard hides the same set. allow_callback_failure is in that list, which
# is correct, since it is a logging switch rather than a machine setting.
ps_excluded="$(
    sed -n '/^\$ExcludedVars = @(/,/^)$/p' "${SETUP_PS1}" \
        | grep -oE "'[a-z0-9_]+'" | tr -d "'" | sort -u
)"

if [[ -z "${ps_excluded}" ]]; then
    fail "could not read \$ExcludedVars out of setup.ps1, so which settings are visible cannot be decided" \
         "expected a \$ExcludedVars = @( ... ) block in ${SETUP_PS1}"
    finish "Windows system settings"
fi

visible_settings="$(
    {
        yaml_bool_toggles "${ALL_VARS}"
        yaml_bool_toggles "${WINDOWS_VARS}"
    } | awk '{ if ($1 !~ /^install_/) print $1 }' \
      | grep -vxF "${ps_excluded}" \
      | sort -u || true
)"

sorted_keys="$(sort -u <<<"${ps_keys}")"

if [[ "${visible_settings}" == "${sorted_keys}" ]]; then
    pass "every system-setting toggle a Windows user can tick is applied by WindowsSettings.ps1 ($(grep -c . <<<"${sorted_keys}") of them)"
else
    fail "the Windows system-setting toggles and WindowsSettings.ps1 do not cover each other, so a toggle installs nothing or a key cannot be reached" \
         "$(diff <(echo "${visible_settings}") <(echo "${sorted_keys}") | tr '\n' ' ')"
fi

# --- every declared key is actually applied ----------------------------------------------------
# The declared list is what a checker asks, so a key in it that the applier never branches on would
# make this whole check agree with a file that does nothing. That is ledger rule 4 again, from the
# checker's side.
undispatched=()
while IFS= read -r key; do
    [[ -z "${key}" ]] && continue
    grep -qF "& \$wanted '${key}'" "${PS_FILE}" || undispatched+=("${key}")
done <<<"${ps_keys}"

if [[ ${#undispatched[@]} -eq 0 ]]; then
    pass "every declared setting key is applied by Invoke-WindowsSystemSetting"
else
    fail "setting keys are declared and never applied, so the toggle is offered and does nothing" \
         "${undispatched[*]}"
fi

finish "Windows system settings"
