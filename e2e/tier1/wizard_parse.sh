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
ps_regex="$(grep -oP "(?<=-match ')\^\(\[a-z_\]\+\): \(true\|false\)(?=')" "${SETUP_PS1}" | head -1 || true)"
if [[ -z "${ps_regex}" ]]; then
    warn "could not locate the toggle regex in setup.ps1, skipping the cross-wizard comparison"
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
    malformed="$(read_boolean_toggles "${f}" | grep -vcE '^[a-z_]+ (ON|OFF)$' || true)"
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
            | sed -E 's/^([a-z_]+):.*/\1/' \
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

finish "wizard parse"
