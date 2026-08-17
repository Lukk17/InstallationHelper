#!/usr/bin/env bash
#
# Tier 1: the wizard's toggle parse must agree with the YAML, in both wizards.
#
# This exists because read_boolean_toggles in setup.sh once used an end-anchored
# state substitution, so any group_vars line carrying a trailing comment reached
# the caller unconverted. The key kept its colon, the state became the last word of
# the comment, and 15 toggles silently rendered as unchecked and uncontrollable.
# setup.ps1 was never affected, which is why this checks both: two hand-written
# parses of the same file format will drift unless something compares them.
# See docs/regression_ledger.md.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

SETUP_SH="${REPO_ROOT}/setup/setup.sh"
SETUP_PS1="${REPO_ROOT}/setup/setup.ps1"
GROUP_VARS_DIR="${ANSIBLE_DIR}/group_vars"

info "Tier 1: wizard toggle parse"

# Pull EXCLUDED_VARS and read_boolean_toggles straight out of setup.sh rather than
# restating them here, so this check tests the shipped code and cannot drift from it.
excluded_line="$(grep -m1 '^EXCLUDED_VARS=' "${SETUP_SH}" || true)"
if [[ -z "${excluded_line}" ]]; then
    fail "setup.sh defines EXCLUDED_VARS" "no EXCLUDED_VARS assignment found"
    finish "wizard parse"
fi
eval "${excluded_line}"

fn_text="$(sed -n '/^read_boolean_toggles()/,/^}/p' "${SETUP_SH}")"
if [[ -z "${fn_text}" ]]; then
    fail "setup.sh defines read_boolean_toggles" "function body not found"
    finish "wizard parse"
fi
eval "${fn_text}"

# The regex setup.ps1 actually uses, read from the file so a change there is caught.
#
# The pattern that finds it matches any character class rather than one specific spelling, because it
# used to require `[a-z_]+` literally. When the wizards were widened to allow a digit in a toggle name,
# a legitimate fix, this extraction stopped matching, the comparison for all four files was skipped,
# and the gate reported green with four assertions silently not running. That is the failure mode this
# whole directory exists to prevent, produced by the check itself.
ps_regex="$(grep -oP "(?<=-match ')[^']*\(true\|false\)[^']*(?=')" "${SETUP_PS1}" | head -1 || true)"

# A failure, not a warning. A check that cannot run must not be able to report success: the point of
# reading the expression out of the file is to catch a change there, so failing to find it is exactly
# the case that needs to be loud.
if [[ -z "${ps_regex}" ]]; then
    fail "could not locate the toggle regex in setup.ps1, so the cross-wizard comparison cannot run" \
         "looked for a -match pattern containing (true|false) in ${SETUP_PS1}"
fi

for f in "${GROUP_VARS_DIR}"/all.yaml "${GROUP_VARS_DIR}"/linux.yaml \
         "${GROUP_VARS_DIR}"/macos.yaml "${GROUP_VARS_DIR}"/windows.yaml; do
    name="$(basename "${f}")"

    # Independent truth: every boolean toggle in the file, comments stripped,
    # minus the ones the wizard deliberately hides.
    truth="$(yaml_bool_toggles "${f}" \
        | grep -vE "^(${EXCLUDED_VARS}) " \
        | awk '{print $1, ($2 == "true" ? "ON" : "OFF")}' | sort)"

    actual="$(read_boolean_toggles "${f}" | sort)"

    if [[ "${truth}" == "${actual}" ]]; then
        pass "${name}: setup.sh parse matches the YAML ($(wc -l <<<"${truth}") toggles)"
    else
        fail "${name}: setup.sh parse disagrees with the YAML" \
             "$(diff <(echo "${truth}") <(echo "${actual}") | head -20 | tr '\n' ' ')"
    fi

    # Shape check. A desynced line is what produced "install_tailscale:" as a key.
    #
    # Every toggle pattern in this file allows a digit, and that was not always true. Three patterns
    # here, one in lib/common.sh and one in each wizard all read `[a-z_]+`, so `install_k3d` was
    # invisible to the two wizards and to this check at once. The check could not catch it because its
    # independent truth used the same expression, which is the worst arrangement available: a gap that
    # a gate reports as covered. Widening one of them without the others turns that silent gap into a
    # loud disagreement here, which is how this was found.
    malformed="$(read_boolean_toggles "${f}" | grep -vcE '^[a-z0-9_]+ (ON|OFF)$' || true)"
    assert_eq "${name}: every emitted line is '<key> ON|OFF'" "0" "${malformed}"

    colons="$(read_boolean_toggles "${f}" | grep -c ':' || true)"
    assert_eq "${name}: no key carries a stray colon" "0" "${colons}"

    # Nothing may silently vanish. A toggle the wizard cannot see is a toggle the
    # user cannot control, which is the same failure wearing a different hat.
    n_truth="$(grep -c . <<<"${truth}" || true)"
    n_actual="$(grep -c . <<<"${actual}" || true)"
    assert_eq "${name}: no toggle dropped between YAML and wizard" "${n_truth}" "${n_actual}"

    # Both wizards must see the same keys.
    if [[ -n "${ps_regex}" ]]; then
        ps_keys="$(sed -E 's/[[:space:]]+$//' "${f}" \
            | grep -E "${ps_regex}" \
            | sed -E 's/^([a-z0-9_]+):.*/\1/' \
            | grep -vE "^(${EXCLUDED_VARS})$" | sort -u)"
        sh_keys="$(read_boolean_toggles "${f}" | awk '{print $1}' | sort -u)"
        if [[ "${ps_keys}" == "${sh_keys}" ]]; then
            pass "${name}: setup.sh and setup.ps1 see the same toggle keys"
        else
            fail "${name}: the two wizards disagree on which toggles exist" \
                 "$(diff <(echo "${sh_keys}") <(echo "${ps_keys}") | head -10 | tr '\n' ' ')"
        fi
    fi
done

# --- effective state across the two files ------------------------------------
# A toggle can appear in both group_vars/all.yaml and a per-OS file with different values, and then the
# only question that matters is which one the user is shown. site.yaml loads all.yaml as a vars_files
# entry and the per-OS file through include_vars, and include_vars outranks play vars, so the per-OS
# value is what the playbook acts on. Both wizards read all.yaml first and kept the first spelling, so
# both showed the wrong state: install_claude_desktop reads true in all.yaml and false in linux.yaml, so
# the Linux checklist offered it as ON while a defaults run installed nothing, and the Windows checklist
# did the same for two packages. Worse than a wrong label: opening the checklist and confirming passes
# every state as an extra variable, which outranks everything, so the same toggle installed on one path
# and not on the other.
#
# This drives the shipped preload_toggles rather than restating its layering, which is the same reason
# EXCLUDED_VARS and read_boolean_toggles are extracted above. It runs the function once per OS file, so
# the assertion covers macOS and Windows from a Linux gate rather than only the machine's own family.
# Extracted here rather than at its other use below, because format_label reads it and preload_toggles
# calls format_label. Without the declaration in scope, bash treats the subscript as arithmetic and dies
# with "install_chrome: unbound variable" under set -u, which is how this was found.
eval "$(sed -n '/^declare -A LABEL_OVERRIDES=(/,/^)$/p' "${SETUP_SH}")"

preload_text="$(sed -n '/^preload_toggles()/,/^}/p' "${SETUP_SH}")"
de_keys_line="$(grep -m1 '^DE_KEYS=' "${SETUP_SH}" || true)"
is_de_text="$(sed -n '/^is_de_key()/,/^}/p' "${SETUP_SH}")"
format_label_text="$(sed -n '/^format_label()/,/^}/p' "${SETUP_SH}")"

if [[ -z "${preload_text}" || -z "${de_keys_line}" || -z "${is_de_text}" || -z "${format_label_text}" ]]; then
    fail "setup.sh still defines preload_toggles and the helpers it needs" \
         "one of preload_toggles, DE_KEYS, is_de_key or format_label was not found, so the effective-state assertion cannot run"
else
    eval "${de_keys_line}"
    eval "${is_de_text}"
    eval "${format_label_text}"
    eval "${preload_text}"

    for os_file in linux macos windows; do
        differing="$(join -j1 \
            <(read_boolean_toggles "${GROUP_VARS_DIR}/all.yaml" | sort) \
            <(read_boolean_toggles "${GROUP_VARS_DIR}/${os_file}.yaml" | sort) \
            | awk '$2 != $3 {print $1, $3}')"

        # No differing toggle is a valid state and must not read as a pass, so it says so instead.
        if [[ -z "${differing}" ]]; then
            pass "${os_file}.yaml: no toggle contradicts all.yaml, so precedence cannot be observed here"
            continue
        fi

        ALL_VARS="${GROUP_VARS_DIR}/all.yaml" OS_VARS_FILE="${GROUP_VARS_DIR}/${os_file}.yaml"
        PRELOADED_ITEMS=(); PRELOADED_KEYS=()
        preload_toggles

        wrong=()
        while read -r key expected; do
            [[ -z "${key}" ]] && continue
            for (( i=0; i<${#PRELOADED_KEYS[@]}; i++ )); do
                if [[ "${PRELOADED_KEYS[$i]}" == "${key}" ]]; then
                    actual="${PRELOADED_ITEMS[$((i*3+2))]}"
                    [[ "${actual}" == "${expected}" ]] || wrong+=("${key} shown ${actual}, playbook uses ${expected}")
                    break
                fi
            done
        done <<<"${differing}"

        if [[ ${#wrong[@]} -eq 0 ]]; then
            pass "${os_file}.yaml: the wizard shows the per-OS value the playbook acts on ($(grep -c . <<<"${differing}") contradicting toggles)"
        else
            fail "${os_file}.yaml: the wizard shows a state the playbook does not act on" "${wrong[*]}"
        fi
    done
fi

# A toggle whose key does not begin with install_ is a system setting rather than a
# piece of software, and the default label is just the key with its prefix stripped and
# underscores swapped for spaces. That renders setup_zsh as "Zsh", which sits next to
# "Chrome" in the same list and tells the user nothing about which one reconfigures
# their shell. Any such toggle that reaches the checklist must carry an explicit label.
eval "$(sed -n '/^declare -A LABEL_OVERRIDES=(/,/^)$/p' "${SETUP_SH}")"
missing_labels=()
for f in "${GROUP_VARS_DIR}"/all.yaml "${GROUP_VARS_DIR}"/linux.yaml \
         "${GROUP_VARS_DIR}"/macos.yaml "${GROUP_VARS_DIR}"/windows.yaml; do
    while read -r key _; do
        [[ -z "${key}" || "${key}" == install_* ]] && continue
        # The four desktop environment keys never reach the checklist. preload_toggles
        # filters them out because the wizard gives them a dedicated screen with its own
        # install-versus-configure choice.
        [[ "${key}" == configure_kde_plasma || "${key}" == configure_gnome ]] && continue
        [[ -n "${LABEL_OVERRIDES[${key}]:-}" ]] && continue
        missing_labels+=("${key}")
    done < <(read_boolean_toggles "${f}")
done
if [[ ${#missing_labels[@]} -eq 0 ]]; then
    pass "every visible system setting has a descriptive label"
else
    fail "system settings reach the checklist with no descriptive label" \
         "$(printf '%s ' "${missing_labels[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
fi

# The two wizards must hide exactly the same keys, or one lets the user change something
# the other refuses to show. Compared as sets, order irrelevant.
sh_excluded="$(tr '|' '\n' <<<"${EXCLUDED_VARS}" | sort -u)"
ps_excluded="$(sed -n '/^\$ExcludedVars = @(/,/^)$/p' "${SETUP_PS1}" \
    | grep -oE "'[a-z0-9_]+'" | tr -d "'" | sort -u)"
if [[ "${sh_excluded}" == "${ps_excluded}" ]]; then
    pass "both wizards hide the same toggles ($(grep -c . <<<"${sh_excluded}") keys)"
else
    fail "the two wizards hide different toggles" \
         "$(diff <(echo "${sh_excluded}") <(echo "${ps_excluded}") | tr '\n' ' ')"
fi

finish "wizard parse"
