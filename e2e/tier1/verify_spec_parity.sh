#!/usr/bin/env bash
#
# Tier 1: every assertion the verify play makes must be named in every container scenario's spec.
#
# Every container scenario runs one verify.yaml, so an assertion added there applies to all of them
# at once and belongs in every container spec. Two had already drifted by the time this check was
# written: "Assert docker.service is enabled when Docker was requested" and "Assert flatpak is
# installed and the Flathub remote is configured" existed in the play and were named in no spec at
# all, while 60-defaults-test.md still told the reader that the Docker unit state was collected and
# not asserted. A spec that understates what a run proves is not harmless: it is read as the
# definition of coverage, and a reader who trusts it will believe a gap exists where one does not,
# or worse, tick a box that was never checked.
#
# Matching is on the verify task name verbatim, so there is no third list to keep in step. That is
# why the specs quote the task names rather than paraphrasing them.
#
# The assertions are read from setup/ansible/verify_install.yaml, which is where they live: that
# play is what a person runs on a real machine and what the wizard runs as its last step, and
# tier3/verify.yaml is a wrapper that imports it so the container scenarios assert the same things.
# Reading the wrapper would find nothing and report no coverage gap, which is the failure mode this
# check exists to prevent.
#
# The two non-container capabilities, 10 and 20, are excluded: they are tiers 1 and 2 and never run
# the verify play at all.
#
# 30-forced-failure is included even though most of its assertions are never reached: a failed
# assertion ends the play, so that scenario stops at the second one. It runs the same verify.yaml as
# the rest, and a spec that named only the assertions it reaches would understate what the play would
# have asked, which is the same gap in a different direction. It says which ones are not reached
# instead, and the strings are all there.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

VERIFY_YAML="${ANSIBLE_DIR}/verify_install.yaml"
TESTING_DIR="${E2E_ROOT}/testing"
RUN_SH="${E2E_ROOT}/run.sh"

# Capabilities that drive a container scenario, and therefore run verify.yaml: every spec in
# testing/ but the two static tiers. Read from the folder rather than listed here, because a fixed
# list skips a spec added after it was written, defect class 19 in docs/regression_ledger.md.
CONTAINER_SPECS=()
for spec in "${TESTING_DIR}"/[0-9]*-test.md; do
    [[ -f "${spec}" ]] || continue
    spec_stem="$(basename "${spec}" -test.md)"
    case "${spec_stem}" in 10-*|20-*) continue ;; esac
    CONTAINER_SPECS+=("${spec_stem}")
done

# Capability 10 is the whole of tier 1, so its spec has to name every check tier 1 runs. It named
# three of six. windows_mapping, windows_npm_parity and this script itself were absent, so a reader
# taking that spec as the definition of tier 1 would have understood it as half its actual size.
TIER1_SPEC="${TESTING_DIR}/10-wizard-toggle-parse-test.md"

info "Tier 1: the harness against the capability specs"

[[ -f "${VERIFY_YAML}" ]] || { fail "verify_install.yaml is missing" "${VERIFY_YAML}"; finish "harness spec parity"; }
[[ -d "${TESTING_DIR}" ]] || { fail "the capability spec directory is missing" "${TESTING_DIR}"; finish "harness spec parity"; }

# Assertion task names, in file order. An assert task is one whose name starts with Assert, which is
# the convention every assertion in verify.yaml follows. The count is read from the file below rather
# than written here, because a number in a comment goes stale the first time an assertion is added.
mapfile -t assertions < <(sed -nE 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*(Assert .*)$/\1/p' "${VERIFY_YAML}")

if [[ ${#assertions[@]} -eq 0 ]]; then
    fail "no assertion task names found in verify_install.yaml, so this check cannot mean anything" \
         "expected task names beginning 'Assert ' in ${VERIFY_YAML}"
    finish "harness spec parity"
fi
pass "verify_install.yaml declares ${#assertions[@]} assertions"

for spec_stem in "${CONTAINER_SPECS[@]}"; do
    spec="${TESTING_DIR}/${spec_stem}-test.md"
    if [[ ! -f "${spec}" ]]; then
        fail "${spec_stem}: spec file missing" "${spec}"
        continue
    fi

    missing=()
    for assertion in "${assertions[@]}"; do
        grep -qF "${assertion}" "${spec}" || missing+=("${assertion}")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        pass "${spec_stem}: names all ${#assertions[@]} verify assertions"
    else
        fail "${spec_stem}: ${#missing[@]} verify assertion(s) are not named in the spec, so the spec understates what the run proves" \
             "$(printf '%s; ' "${missing[@]}")"
    fi
done

# --- every tier 3 scenario against the container specs -------------------------
# A scenario no spec links runs in the sweep with nobody's definition of what it proves. The
# picked-apps scenario was nearly added that way, docs/regression_ledger.md 10.290.
if [[ ${#CONTAINER_SPECS[@]} -eq 0 ]]; then
    fail "no container capability spec found in ${TESTING_DIR}, so no scenario can be matched to one" "${TESTING_DIR}"
fi
unlinked=()
n_scenarios=0
for scenario in "${E2E_ROOT}"/tier3/scenarios/*.yaml; do
    [[ -f "${scenario}" ]] || continue
    n_scenarios=$((n_scenarios + 1))
    linked=no
    for spec_stem in "${CONTAINER_SPECS[@]}"; do
        grep -qF "tier3/scenarios/$(basename "${scenario}")" "${TESTING_DIR}/${spec_stem}-test.md" && { linked=yes; break; }
    done
    [[ "${linked}" == yes ]] || unlinked+=("$(basename "${scenario}")")
done
if [[ ${n_scenarios} -eq 0 ]]; then
    fail "no tier 3 scenario found, so this comparison proves nothing" "${E2E_ROOT}/tier3/scenarios"
elif [[ ${#unlinked[@]} -eq 0 ]]; then
    pass "every one of ${n_scenarios} tier 3 scenarios is linked from a container capability spec"
else
    fail "${#unlinked[@]} tier 3 scenario(s) are linked from no container capability spec in ${TESTING_DIR}" \
         "$(printf '%s ' "${unlinked[@]}")"
fi

# --- capability 10 against the tier 1 script list -----------------------------
# The list is read out of run_tier1's own for loop, so adding a check to the runner without
# mentioning it in the spec fails here rather than going unnoticed.
tier1_checks="$(sed -nE 's/^[[:space:]]*for check in ([a-z0-9_ ]+); do$/\1/p' "${RUN_SH}")"

if [[ -z "${tier1_checks}" ]]; then
    fail "could not read the tier 1 check list out of run.sh, so this check cannot mean anything" \
         "expected a line of the form 'for check in a b c; do' in ${RUN_SH}"
elif [[ ! -f "${TIER1_SPEC}" ]]; then
    fail "capability 10's spec is missing" "${TIER1_SPEC}"
else
    missing_checks=()
    for check in ${tier1_checks}; do
        grep -qF "${check}" "${TIER1_SPEC}" || missing_checks+=("${check}")
    done
    n_checks="$(wc -w <<<"${tier1_checks}")"
    if [[ ${#missing_checks[@]} -eq 0 ]]; then
        pass "10-wizard-toggle-parse: names all ${n_checks} tier 1 check scripts"
    else
        fail "10-wizard-toggle-parse: ${#missing_checks[@]} tier 1 check script(s) are not named in the spec, so the spec understates what the gate runs" \
             "${missing_checks[*]}"
    fi
fi

finish "harness spec parity"
