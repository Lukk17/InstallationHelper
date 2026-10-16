#!/usr/bin/env bash
#
# Tier 1: no label the bash wizard can show on its software checklist may contain a comma.
#
# pick_software in setup/setup.sh shows each toggle to `gum choose --no-limit` as "<key> | <label>"
# and hands every toggle that starts ticked over as one comma-joined --selected value. gum splits
# that value on every comma, so a label with a comma in it never matches its own line and the toggle
# shows unticked although it is on. setup_zsh was labelled "System: zsh shell, with Powerlevel10k and
# Nerd Fonts", is on by default, and pressing Enter without looking turned zsh setup off. Measured
# with gum 2.0.2: --selected="k1 | with, comma,k2 | plain" came back with only "k2 | plain" ticked.
# The owner's answer is that checklist labels carry no comma. See docs/regression_ledger.md.
#
# The keys come from wizard_toggle_keys in lib/common.sh, which drives the shipped preload_toggles,
# and each label from the shipped format_label, so this tests what the checklist really shows on
# Linux and on macOS. Every LABEL_OVERRIDES value is checked as well, because an override exists only
# to be shown, and one written for a toggle that has not reached a Linux or macOS file yet would
# otherwise pass here until the day it does. Last, every key that both LABEL_OVERRIDES and setup.ps1's
# $LabelOverrides carry must have the same label in both, because the comma rewrite changed setup.sh
# alone and left setup.ps1 showing the old text for three of them. Every non-blank, non-comment line
# of $LabelOverrides must read as a single-quoted 'key' = 'label' entry, so a double-quoted one fails
# here instead of being skipped by the comparison. And each table may carry only keys its own wizard
# can offer: LABEL_OVERRIDES keys that wizard_toggle_keys lists for linux.yaml or macos.yaml, and
# $LabelOverrides keys that setup.ps1's Get-SelectableToggle reads from all.yaml or windows.yaml and
# $ExcludedVars does not hide, because a label nobody can see is a second copy of a fact that drifts.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

SETUP_SH="${REPO_ROOT}/setup/setup.sh"
GROUP_VARS_DIR="${ANSIBLE_DIR}/group_vars"

info "Tier 1: checklist labels"

IFS=$'\n\t'

overrides_text="$(sed -n '/^declare -A LABEL_OVERRIDES=(/,/^)$/p' "${SETUP_SH}")"
format_label_text="$(sed -n '/^format_label()/,/^}/p' "${SETUP_SH}")"
if [[ -z "${overrides_text}" || -z "${format_label_text}" ]]; then
    fail "setup.sh still defines LABEL_OVERRIDES and format_label" \
         "one of them was not found in ${SETUP_SH}, so no label could be checked"
    finish "checklist labels"
fi
eval "${overrides_text}"
eval "${format_label_text}"

declare -A sh_offered=()
for os_file in linux macos; do
    if ! keys="$(wizard_toggle_keys "${GROUP_VARS_DIR}/all.yaml" "${GROUP_VARS_DIR}/${os_file}.yaml")"; then
        fail "${os_file}.yaml: the checklist could not be resolved, so its labels were not checked" \
             "wizard_toggle_keys returned non-zero, see the error above"
        continue
    fi

    with_comma=()
    while IFS= read -r key; do
        [[ -z "${key}" ]] && continue
        sh_offered["${key}"]=1
        label="$(format_label "${key}")"
        [[ "${label}" == *,* ]] && with_comma+=("${key} [${label}]")
    done <<<"${keys}"

    if [[ ${#with_comma[@]} -eq 0 ]]; then
        pass "${os_file}.yaml: no checklist label contains a comma ($(grep -c . <<<"${keys}") labels)"
    else
        fail "${os_file}.yaml: checklist labels contain a comma, so gum's --selected splits them and the toggle shows unticked" \
             "$(printf '%s | ' "${with_comma[@]}")"
    fi
done

override_with_comma=()
for key in "${!LABEL_OVERRIDES[@]}"; do
    [[ "${LABEL_OVERRIDES[${key}]}" == *,* ]] && override_with_comma+=("${key} [${LABEL_OVERRIDES[${key}]}]")
done
if [[ ${#LABEL_OVERRIDES[@]} -eq 0 ]]; then
    fail "setup.sh declares no label overrides, so the override half of this check proved nothing" \
         "LABEL_OVERRIDES came out empty"
elif [[ ${#override_with_comma[@]} -eq 0 ]]; then
    pass "no LABEL_OVERRIDES value contains a comma (${#LABEL_OVERRIDES[@]} overrides)"
else
    fail "LABEL_OVERRIDES values contain a comma, which gum's --selected splits" \
         "$(printf '%s | ' "${override_with_comma[@]}")"
fi

sh_dead=()
for key in "${!LABEL_OVERRIDES[@]}"; do
    [[ -n "${sh_offered[${key}]:-}" ]] || sh_dead+=("${key}")
done
if [[ ${#sh_offered[@]} -eq 0 ]]; then
    fail "the bash wizard offered no key on linux.yaml or macos.yaml, so LABEL_OVERRIDES was not checked for dead entries" \
         "wizard_toggle_keys returned nothing for either file"
elif [[ ${#sh_dead[@]} -eq 0 ]]; then
    pass "every LABEL_OVERRIDES key is one the bash wizard offers on Linux or macOS"
else
    fail "LABEL_OVERRIDES carries keys the bash wizard never offers on Linux or macOS, so their labels are never shown" \
         "$(printf '%s ' "${sh_dead[@]}" | tr ' ' '\n' | sort | tr '\n' ' ')"
fi

ps_excluded="$(sed -n '/^\$ExcludedVars = @(/,/^)$/p' "${REPO_ROOT}/setup/setup.ps1" | grep -oE "'[a-z0-9_]+'" | tr -d "'" || true)"
ps_offered="$(cat "${GROUP_VARS_DIR}/all.yaml" "${GROUP_VARS_DIR}/windows.yaml" \
    | grep -oE '^[a-z0-9_]+: (true|false)' | cut -d: -f1 \
    | grep -vxF -f <(printf '%s\n' "${ps_excluded}") | sort -u || true)"

ps_label_line="^[[:space:]]*'([a-z0-9_]+)'[[:space:]]*=[[:space:]]*'(.*)'[[:space:]]*$"
ps_dead=()
ps_override_count=0
ps_entry_lines=()
label_mismatches=()
while IFS= read -r line; do
    [[ "${line}" =~ ^[[:space:]]*(#.*)?$ ]] && continue
    ps_entry_lines+=("${line}")
    [[ "${line}" =~ ${ps_label_line} ]] || continue
    ps_override_count=$((ps_override_count + 1))
    key="${BASH_REMATCH[1]}"
    ps_label="${BASH_REMATCH[2]//\'\'/\'}"
    if ! grep -qxF "${key}" <<<"${ps_offered}"; then
        ps_dead+=("${key}")
        continue
    fi
    [[ -n "${sh_offered[${key}]:-}" ]] || continue
    [[ "${LABEL_OVERRIDES[${key}]:-${ps_label}}" == "${ps_label}" ]] \
        || label_mismatches+=("${key} [${LABEL_OVERRIDES[${key}]}] vs [${ps_label}]")
done < <(sed -n '/^\$LabelOverrides = @{/,/^}/{/^\$LabelOverrides = @{/d;/^}/d;p;}' "${REPO_ROOT}/setup/setup.ps1")

if [[ ${ps_override_count} -eq 0 ]]; then
    fail "setup.ps1 declares no label overrides that could be read, so the two wizards were not compared" \
         "\$LabelOverrides came out empty in ${REPO_ROOT}/setup/setup.ps1"
    finish "checklist labels"
fi

if [[ ${ps_override_count} -ne ${#ps_entry_lines[@]} ]]; then
    fail "setup.ps1's \$LabelOverrides has ${#ps_entry_lines[@]} entry lines but only ${ps_override_count} could be read as 'key' = 'label', so the rest were never compared" \
         "$(printf '%s | ' "${ps_entry_lines[@]}")"
else
    pass "every line of setup.ps1's \$LabelOverrides reads as a 'key' = 'label' entry (${ps_override_count} entries)"
fi

if [[ -z "${ps_offered}" ]]; then
    fail "setup.ps1 offers no key from all.yaml or windows.yaml, so \$LabelOverrides was not checked for dead entries" \
         "no boolean toggle was read from ${GROUP_VARS_DIR}/all.yaml or windows.yaml"
elif [[ ${#ps_dead[@]} -eq 0 ]]; then
    pass "every \$LabelOverrides key in setup.ps1 is one the Windows wizard offers"
else
    fail "setup.ps1's \$LabelOverrides carries keys the Windows wizard never offers, because they are in neither all.yaml nor windows.yaml or are hidden by \$ExcludedVars" \
         "$(printf '%s ' "${ps_dead[@]}")"
fi

if [[ ${#label_mismatches[@]} -eq 0 ]]; then
    pass "every key both wizards can show has the same label in setup.sh and setup.ps1"
else
    fail "setup.sh and setup.ps1 label the same toggle differently" \
         "$(printf '%s | ' "${label_mismatches[@]}")"
fi

finish "checklist labels"
