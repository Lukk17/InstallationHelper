#!/usr/bin/env bash
#
# Tier 1: --list-software must name exactly the toggles the wizard offers, and their real state.
#
# --list-software is the answer the wizard gives when --enable or --disable refuses a key: the error
# message ends with "Run setup.sh --list-software for the keys it does offer". So it is the only
# published description of what a scripted run may ask for, and a key missing from it is a key
# nobody can discover, while a key in it that the wizard does not actually offer sends the reader
# straight into a refusal.
#
# The state column matters as much as the names. group_vars/all.yaml and the per-OS file can
# disagree about the same toggle, and the per-OS file is what the playbook acts on, because
# site.yaml loads all.yaml as a vars_files entry and the per-OS file through include_vars, which
# outranks play vars. The wizard read those two in the wrong order once, and install_claude_desktop
# was listed as on while a defaults run installed nothing. That is why the expected state here is
# built with the per-OS value winning rather than with whichever spelling comes first.
#
# The expected set is built from the same source of truth e2e/tier1/wizard_parse.sh uses, which is
# the YAML read through yaml_bool_toggles in e2e/lib/common.sh, minus EXCLUDED_VARS taken out of
# setup.sh itself. The four desktop keys are removed because preload_toggles keeps them off the
# checklist and gives them a screen of their own. Nothing here restates a toggle name.
#
# Nothing changes the machine. --list-software answers at line 1391 of setup.sh and exits, above
# prepare_become_password, ensure_ansible and system_upgrade.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: --list-software"

SETUP_SH="${REPO_ROOT}/setup/setup.sh"
GROUP_VARS_DIR="${ANSIBLE_DIR}/group_vars"

if [[ ! -f "${SETUP_SH}" ]]; then
    fail "the wizard is missing, so this check proves nothing" "${SETUP_SH}"
    finish "list-software"
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

# --- which group_vars files the wizard would read ----------------------------
# detect_os is taken out of setup.sh and run rather than reimplemented, so this check asks the same
# question the wizard asks and gets the same answer on macOS as on Linux.
# Both are read by detect_os, which is eval'd out of setup.sh below and which shellcheck
# cannot see into.
# shellcheck disable=SC2034
LINUX_VARS="${GROUP_VARS_DIR}/linux.yaml"
# shellcheck disable=SC2034
MACOS_VARS="${GROUP_VARS_DIR}/macos.yaml"

detect_os_text="$(sed -n '/^detect_os()/,/^}/p' "${SETUP_SH}")"
excluded_line="$(grep -m1 '^EXCLUDED_VARS=' "${SETUP_SH}" || true)"
de_keys_line="$(grep -m1 '^DE_KEYS=' "${SETUP_SH}" || true)"

if [[ -z "${detect_os_text}" || -z "${excluded_line}" || -z "${de_keys_line}" ]]; then
    fail "setup.sh no longer defines detect_os, EXCLUDED_VARS and DE_KEYS, so the expected list cannot be built" \
         "one of the three was not found in ${SETUP_SH}"
    finish "list-software"
fi

eval "${excluded_line}"
eval "${de_keys_line}"
eval "${detect_os_text}"
detect_os

de_pattern="$(printf '%s|' "${DE_KEYS[@]}")"
de_pattern="${de_pattern%|}"

selectable_toggles() {
    yaml_bool_toggles "$1" \
        | grep -vE "^(${EXCLUDED_VARS}) " \
        | grep -vE "^(${de_pattern}) "
}

# The expected list, in the order preload_toggles builds it: every key all.yaml declares, in that
# file's order, followed by the keys only the per-OS file declares. The state is the per-OS one
# wherever both files carry the key, because that is the one the playbook acts on.
EXPECTED="$(awk '
    NR == FNR { os_state[$1] = $2; os_order[++os_count] = $1; next }
    {
        seen[$1] = 1
        print $1, ($1 in os_state ? os_state[$1] : $2)
    }
    END {
        for (i = 1; i <= os_count; i++)
            if (!(os_order[i] in seen))
                print os_order[i], os_state[os_order[i]]
    }' \
    <(selectable_toggles "${OS_VARS_FILE}") \
    <(selectable_toggles "${GROUP_VARS_DIR}/all.yaml") \
    | sed 's/ true$/ ON/; s/ false$/ OFF/')"

if [[ -z "${EXPECTED}" ]]; then
    fail "no selectable toggle was read out of group_vars, so this check proves nothing" \
         "read nothing from ${GROUP_VARS_DIR}/all.yaml and ${OS_VARS_FILE}"
    finish "list-software"
fi

# --- what the wizard prints ----------------------------------------------------
rc=0
bash "${SETUP_SH}" --list-software >"${WORK_DIR}/out" 2>"${WORK_DIR}/err" </dev/null || rc=$?

if [[ "${rc}" -ne 0 ]]; then
    fail "--list-software did not answer" \
         "exited ${rc}: $(tr '\n' ' ' <"${WORK_DIR}/err" | cut -c1-200)"
    finish "list-software"
fi

# Everything above the list is the wizard's own progress reporting, and the list is every line whose
# first field is a toggle name and whose second is the state. Anchored on that shape rather than on
# a line count, which would break the moment a line of reporting is added or removed.
ACTUAL="$(awk '$1 ~ /^[a-z0-9_]+$/ && ($2 == "ON" || $2 == "OFF") { print $1, $2 }' "${WORK_DIR}/out")"

if [[ -z "${ACTUAL}" ]]; then
    fail "--list-software printed no toggle at all, so this check proves nothing" \
         "$(grep -c . <"${WORK_DIR}/out") lines of output, none of them shaped '<key> ON|OFF <label>'"
    finish "list-software"
fi

# --- the names ------------------------------------------------------------------
expected_keys="$(awk '{print $1}' <<<"${EXPECTED}" | sort)"
actual_keys="$(awk '{print $1}' <<<"${ACTUAL}" | sort)"

if [[ "${expected_keys}" == "${actual_keys}" ]]; then
    pass "--list-software names exactly the $(grep -c . <<<"${expected_keys}") toggles group_vars declares"
else
    missing="$(comm -23 <(echo "${expected_keys}") <(echo "${actual_keys}") | tr '\n' ' ')"
    extra="$(comm -13 <(echo "${expected_keys}") <(echo "${actual_keys}") | tr '\n' ' ')"
    fail "--list-software does not name the toggle set group_vars declares" \
         "not listed: ${missing:-none} | listed but not declared: ${extra:-none}"
fi

# --- the order ------------------------------------------------------------------
# A duplicate key would survive the set comparison above and would put the same application on the
# checklist twice, so the ordered lists are compared as well.
if [[ "$(awk '{print $1}' <<<"${EXPECTED}")" == "$(awk '{print $1}' <<<"${ACTUAL}")" ]]; then
    pass "--list-software lists them in the order the wizard builds, all.yaml first then per-OS additions"
else
    fail "--list-software lists the toggles in a different order or lists one of them twice" \
         "$(diff <(awk '{print $1}' <<<"${EXPECTED}") <(awk '{print $1}' <<<"${ACTUAL}") | head -10 | tr '\n' ' ')"
fi

# --- the states -----------------------------------------------------------------
if [[ "${EXPECTED}" == "${ACTUAL}" ]]; then
    pass "every state printed is the one the playbook would act on, per-OS value winning"
else
    fail "--list-software prints a state the playbook would not act on" \
         "$(diff <(echo "${EXPECTED}") <(echo "${ACTUAL}") | head -10 | tr '\n' ' ')"
fi

# --- the labels -----------------------------------------------------------------
# The third column is what the checklist shows a person. An empty one is a row nobody can read.
unlabelled="$(awk '$1 ~ /^[a-z0-9_]+$/ && ($2 == "ON" || $2 == "OFF") && NF < 3 { print $1 }' "${WORK_DIR}/out")"
if [[ -z "${unlabelled}" ]]; then
    pass "every listed toggle carries a label"
else
    fail "a listed toggle has no label, so the list says nothing about what it installs" \
         "$(tr '\n' ' ' <<<"${unlabelled}")"
fi

finish "list-software"
