#!/usr/bin/env bash
#
# Tier 1: the wizard and the container harness must resolve the same software selection.
#
# This used to be two implementations of one rule, which is defect class 2 in AGENTS.md, sitting
# inside the harness meant to catch that class. setup.sh decides what the software set is in
# software_override_vars, working from the keys preload_toggles collected, and container.sh decided
# it again by sweeping install_ toggles out of group_vars/all.yaml and group_vars/linux.yaml. The
# two disagreed in both directions: the sweep could not see the four system settings whose names do
# not begin with install_, and it swept up the two desktop keys the wizard keeps off the checklist.
# container.sh now calls wizard_toggle_keys in e2e/lib/common.sh, which evaluates the functions
# setup.sh ships, so there is one rule and the harness reads it.
#
# The comparison stays, because the coupling can be undone by one paste. Both sides are driven here
# rather than restated: the wizard side evaluates the shipped functions through this file's own
# extraction, and the container side evaluates whatever container.sh actually does. Two independent
# routes to one rule is the point. A check that reached the answer the same way the harness does
# would agree with it by construction and could never fail. Restating a rule inside the check that
# guards it is the same defect wearing a different hat.
#
# Two cases are compared, because a selection is a set of keys and a value for each:
#
#   all        the wizard's --software all against the container's e2e_generate: all_software
#   defaults   the wizard's --software defaults against what the playbook reads from group_vars
#              when a scenario generates nothing, which is the per-OS value
#
# The comparison is pinned to Linux on the wizard side, because group_vars/linux.yaml is the only
# per-OS file container.sh reads.
#
# Divergences that are known and not yet reconciled are listed in selection_parity_allowed.txt with
# the side that offers the key and what the divergence costs. That file is empty of entries today,
# and it stays because a divergence has to have somewhere to be admitted before anybody is tempted
# to hide one. It is not a way to make this check quiet: a divergence that is not listed fails, a
# listed toggle that has stopped diverging in the direction it claims fails too, and a key both
# sides offer while resolving it to different values has no listing at all.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

SETUP_SH="${REPO_ROOT}/setup/setup.sh"
# Reached through REPO_ROOT rather than E2E_ROOT, because container.sh is one of the two things this
# check judges. E2E_REPO_ROOT points at the tree under test, and a check that read its own copy of
# the file instead would keep passing over a mutated tree, which is how a check gets shipped that
# cannot fail.
CONTAINER_SH="${REPO_ROOT}/e2e/tier3/container.sh"
GROUP_VARS_DIR="${ANSIBLE_DIR}/group_vars"
ALLOWED_FILE="${E2E_ROOT}/tier1/selection_parity_allowed.txt"

# Every list below is sorted and then compared with comm, and those two only agree while they are
# using the same collation, which otherwise varies with whatever locale the shell happens to carry.
export LC_ALL=C

info "Tier 1: wizard and container harness resolve the same software selection"

for f in "${SETUP_SH}" "${CONTAINER_SH}" "${GROUP_VARS_DIR}/all.yaml" "${GROUP_VARS_DIR}/linux.yaml"; do
    if [[ ! -f "${f}" ]]; then
        fail "a file this comparison needs is missing, so it proves nothing" "${f}"
        finish "selection parity"
    fi
done

# --- the divergences that are already written down ----------------------------------------------
declare -A ALLOWED_SIDE=()
declare -A OBSERVED_SIDE=()

if [[ ! -f "${ALLOWED_FILE}" ]]; then
    fail "the file that records the known divergences is missing" \
         "${ALLOWED_FILE}, so every divergence below is reported as unlisted"
else
    allow_malformed=()
    while IFS= read -r allow_line; do
        allow_line="${allow_line#"${allow_line%%[![:space:]]*}"}"
        [[ -z "${allow_line}" || "${allow_line}" == '#'* ]] && continue
        allow_toggle="${allow_line%% *}"; allow_rest="${allow_line#* }"
        allow_side="${allow_rest%% *}";   allow_reason="${allow_rest#* }"
        if [[ "${allow_side}" != wizard && "${allow_side}" != container ]] \
           || [[ -z "${allow_reason}" || "${allow_reason}" == "${allow_side}" ]]; then
            allow_malformed+=("${allow_line}")
            continue
        fi
        ALLOWED_SIDE["${allow_toggle}"]="${allow_side}"
    done <"${ALLOWED_FILE}"

    if [[ ${#allow_malformed[@]} -gt 0 ]]; then
        fail "a line in the allow file is not '<toggle> <wizard|container> <what it costs>'" \
             "$(printf '[%s] ' "${allow_malformed[@]}")"
    fi
fi

# The coupling that replaced the duplication, asserted rather than assumed. container.sh no longer
# decides the software set: it calls wizard_toggle_keys, and that function evaluates the functions
# setup.sh ships. Both halves are checked, because either one can be undone on its own. A sweep
# pasted back into container.sh would resolve a set again, and a wizard_toggle_keys that stopped
# reading setup.sh would be a third copy of the rule wearing the shared reader's name.
COMMON_SH="${REPO_ROOT}/e2e/lib/common.sh"
container_sweep="$(sed -n '/mapfile -t all_toggles < <(/,/^        )$/p' "${CONTAINER_SH}")"
if grep -q 'wizard_toggle_keys' <<<"${container_sweep}"; then
    pass "container.sh takes its generated set from wizard_toggle_keys rather than resolving one itself"
else
    fail "container.sh resolves the generated software set itself again" \
         "the block at 'mapfile -t all_toggles' no longer calls wizard_toggle_keys, so the rule is implemented twice again, which is the defect this check exists for"
fi

if sed -n '/^wizard_toggle_keys()/,/^}/p' "${COMMON_SH}" | grep -q 'setup/setup\.sh'; then
    pass "wizard_toggle_keys still reads the rule out of setup.sh rather than keeping its own copy"
else
    fail "wizard_toggle_keys no longer reads setup/setup.sh" \
         "the shared reader now carries its own copy of the wizard's rule, which is the duplication it was written to remove"
fi

# --- the wizard's answer -----------------------------------------------------------------------
#
# Driven in a subshell under setup.sh's own IFS, because that file sets IFS to newline and tab at
# the top and some of its expansions depend on it. Everything the extracted functions reach for is
# extracted too, so nothing here is a paraphrase of the shipped rule.
wizard_selection() {
    local baseline="$1"
    (
        IFS=$'\n\t'
        local piece
        for piece in "$(grep -m1 '^EXCLUDED_VARS=' "${SETUP_SH}")" \
                     "$(grep -m1 '^DE_KEYS=' "${SETUP_SH}")" \
                     "$(sed -n '/^declare -A LABEL_OVERRIDES=(/,/^)$/p' "${SETUP_SH}")" \
                     "$(sed -n '/^format_label()/,/^}/p' "${SETUP_SH}")" \
                     "$(sed -n '/^is_de_key()/,/^}/p' "${SETUP_SH}")" \
                     "$(sed -n '/^read_boolean_toggles()/,/^}/p' "${SETUP_SH}")" \
                     "$(sed -n '/^preload_toggles()/,/^}/p' "${SETUP_SH}")" \
                     "$(grep -m1 '^split_key_list()' "${SETUP_SH}")" \
                     "$(sed -n '/^software_override_vars()/,/^}/p' "${SETUP_SH}")"; do
            [[ -z "${piece}" ]] && return 1
            eval "${piece}"
        done

        # The next four lines feed preload_toggles and software_override_vars, both eval'd out of
        # setup.sh in the loop above, so shellcheck sees assignments with no reader.
        # shellcheck disable=SC2034
        ALL_VARS="${GROUP_VARS_DIR}/all.yaml"
        # shellcheck disable=SC2034
        OS_VARS_FILE="${GROUP_VARS_DIR}/linux.yaml"
        # shellcheck disable=SC2034
        PRELOADED_ITEMS=(); PRELOADED_KEYS=()
        preload_toggles
        [[ ${#PRELOADED_KEYS[@]} -eq 0 ]] && return 1

        # shellcheck disable=SC2034
        OPT_SOFTWARE="${baseline}"
        # shellcheck disable=SC2034
        OPT_ENABLE=""
        # shellcheck disable=SC2034
        OPT_DISABLE=""
        software_override_vars | sort
    )
}

# --- the container harness's answer ------------------------------------------------------------
#
# The sweep is lifted out of container.sh verbatim, so it keeps whatever that file actually does,
# whether that is a call to the shared reader or a set it resolves for itself. It runs under the
# default IFS, which is what container.sh runs under, and its keys are paired with the value that
# scenario shape would hand the playbook.
container_selection() {
    local baseline="$1"
    (
        local sweep resolved key value
        # Seeded before the sweep runs, and deliberately not required. The sweep container.sh ships
        # today reads the wizard through wizard_toggle_keys and needs nothing from here, but a sweep
        # that resolved a set for itself again would reach for EXCLUDED_VARS, and under set -u that
        # is a shell error rather than a comparison. This check has to be able to evaluate the
        # regression it exists to catch, or it reports a broken check where the tree has a defect.
        # Read only by the sweep eval'd below, which shellcheck cannot see.
        # shellcheck disable=SC2034
        EXCLUDED_VARS=""
        eval "$(grep -m1 '^EXCLUDED_VARS=' "${SETUP_SH}" || true)"

        sweep="$(sed -n '/mapfile -t all_toggles < <(/,/^        )$/p' "${CONTAINER_SH}")"
        [[ -z "${sweep}" ]] && return 1
        eval "${sweep}"
        # all_toggles is declared by the sweep eval'd on the line above.
        # shellcheck disable=SC2154
        [[ ${#all_toggles[@]} -eq 0 ]] && return 1

        # A scenario that generates all_software writes true for every key it swept. A scenario that
        # generates nothing writes no software block at all, so the playbook reads group_vars, where
        # the per-OS file outranks all.yaml because site.yaml loads it through include_vars. That
        # resolution is read straight from the YAML by the harness's own reader rather than through
        # either implementation, so it cannot inherit a mistake from the side it is judging.
        resolved="$( { yaml_bool_toggles "${GROUP_VARS_DIR}/all.yaml"
                       yaml_bool_toggles "${GROUP_VARS_DIR}/linux.yaml"; } \
                     | awk '{ state[$1] = $2 } END { for (k in state) print k "=" state[k] }' )"

        for key in "${all_toggles[@]}"; do
            if [[ "${baseline}" == "all" ]]; then
                value="true"
            else
                value="$(grep -m1 -- "^${key}=" <<<"${resolved}" | cut -d= -f2)"
                [[ -z "${value}" ]] && value="MISSING"
            fi
            printf '%s=%s\n' "${key}" "${value}"
        done | sort
    )
}

COMPARED=0
for baseline in all defaults; do
    wizard="$(wizard_selection "${baseline}" || true)"
    container="$(container_selection "${baseline}" || true)"

    # An assertion over an empty set passes and looks exactly like one that found no problem, which
    # is checklist item 11 in docs/regression_ledger.md. Neither side is allowed to be empty.
    if [[ -z "${wizard}" ]]; then
        fail "the wizard resolved no selection for --software ${baseline}, so this comparison proves nothing" \
             "one of EXCLUDED_VARS, DE_KEYS, LABEL_OVERRIDES, format_label, is_de_key, read_boolean_toggles, preload_toggles, split_key_list or software_override_vars was not found in ${SETUP_SH}"
        continue
    fi
    if [[ -z "${container}" ]]; then
        fail "the container harness resolved no selection for ${baseline}, so this comparison proves nothing" \
             "the 'mapfile -t all_toggles' sweep was not found in ${CONTAINER_SH}, or it produced no toggles"
        continue
    fi

    wizard_keys="$(cut -d= -f1 <<<"${wizard}" | sort)"
    container_keys="$(cut -d= -f1 <<<"${container}" | sort)"

    only_wizard="$(comm -23 <(printf '%s\n' "${wizard_keys}") <(printf '%s\n' "${container_keys}") | tr '\n' ' ')"
    only_container="$(comm -13 <(printf '%s\n' "${wizard_keys}") <(printf '%s\n' "${container_keys}") | tr '\n' ' ')"

    # A key both sides claim but disagree about the value of is the quieter half of the same defect,
    # because the two sets look identical in a count and the run still installs something else.
    # Paired with awk rather than with join, because join judges its inputs against the collation of
    # the current locale and refuses a list that sort produced under a different one.
    differing="$(awk -F= '
        NR == FNR { wizard_value[$1] = $2; next }
        ($1 in wizard_value) && wizard_value[$1] != $2 {
            printf "%s wizard=%s container=%s ", $1, wizard_value[$1], $2
        }
    ' <(printf '%s\n' "${wizard}") <(printf '%s\n' "${container}"))"

    shared_count="$(comm -12 <(printf '%s\n' "${wizard_keys}") <(printf '%s\n' "${container_keys}") | grep -c . || true)"
    if [[ "${shared_count}" -eq 0 ]]; then
        fail "the two selections share no key at all for ${baseline}, so the comparison is meaningless" \
             "the wizard produced $(grep -c . <<<"${wizard}") keys and the container harness produced $(grep -c . <<<"${container}")"
        continue
    fi

    COMPARED=$(( COMPARED + 1 ))

    # Every divergence is recorded before it is judged, and recorded on both passes through this
    # loop, so the stale assertion below is answered by everything that actually diverged rather than
    # by whatever the last baseline happened to find.
    unlisted_wizard=""
    for toggle in ${only_wizard}; do
        OBSERVED_SIDE["${toggle}"]="wizard"
        [[ "${ALLOWED_SIDE[${toggle}]:-}" == "wizard" ]] || unlisted_wizard+="${toggle} "
    done

    unlisted_container=""
    for toggle in ${only_container}; do
        OBSERVED_SIDE["${toggle}"]="container"
        [[ "${ALLOWED_SIDE[${toggle}]:-}" == "container" ]] || unlisted_container+="${toggle} "
    done

    # A value disagreement is never forgiven, so it is not consulted against the allow file at all.
    if [[ -z "${unlisted_wizard}" && -z "${unlisted_container}" && -z "${differing}" ]]; then
        listed_count="$(wc -w <<<"${only_wizard} ${only_container}")"
        if [[ "${listed_count}" -eq 0 ]]; then
            pass "${baseline}: both implementations resolve the same ${shared_count} toggles to the same values"
        else
            pass "${baseline}: the ${shared_count} shared toggles resolve to the same values, and the ${listed_count} key(s) only one side offers are listed in $(basename "${ALLOWED_FILE}") with what that costs"
        fi
        continue
    fi

    detail=""
    [[ -n "${unlisted_wizard}" ]]    && detail+="only the wizard offers, unlisted: ${unlisted_wizard}| "
    [[ -n "${unlisted_container}" ]] && detail+="only the container harness generates, unlisted: ${unlisted_container}| "
    [[ -n "${differing}" ]]          && detail+="same key, different value: ${differing}| "
    detail+="either reconcile the two, or add a line to $(basename "${ALLOWED_FILE}") saying which side offers the key and what the divergence costs"
    fail "${baseline}: the wizard and the container harness resolve different software selections" "${detail}"
done

# --- the allow file cannot outlive its reasons --------------------------------------------------
#
# A listed toggle that both sides now agree about, or that has started diverging the other way, is a
# line that forgives something nobody has looked at. That is worse than no allow file, because the
# next reader takes it as a description of the disagreement and it no longer is one. Asked only when
# a comparison actually ran, so a wizard or a sweep that could not be read fails once above rather
# than a second time here as an entire file of phantom stale entries.
if [[ "${COMPARED}" -gt 0 && ${#ALLOWED_SIDE[@]} -gt 0 ]]; then
    stale=""
    while IFS= read -r toggle; do
        observed="${OBSERVED_SIDE[${toggle}]:-none}"
        [[ "${observed}" == "${ALLOWED_SIDE[${toggle}]}" ]] && continue
        if [[ "${observed}" == none ]]; then
            stale+="${toggle} is listed as offered only by the ${ALLOWED_SIDE[${toggle}]} side and both sides now offer it | "
        else
            stale+="${toggle} is listed as offered only by the ${ALLOWED_SIDE[${toggle}]} side and is now offered only by the ${observed} side | "
        fi
    done < <(printf '%s\n' "${!ALLOWED_SIDE[@]}" | sort)

    if [[ -z "${stale}" ]]; then
        pass "all ${#ALLOWED_SIDE[@]} listed divergences still diverge in the direction $(basename "${ALLOWED_FILE}") claims"
    else
        fail "a divergence listed in $(basename "${ALLOWED_FILE}") is not there any more, so the file forgives something nobody has looked at" \
             "delete the line: ${stale}"
    fi
fi

finish "selection parity"
