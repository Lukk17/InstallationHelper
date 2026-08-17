#!/usr/bin/env bash
#
# Tier 1: every assertion the verify play makes must be named in every container scenario's spec.
#
# All six container scenarios run one verify.yaml, so an assertion added there applies to all of
# them at once and belongs in all six specs. Two had already drifted by the time this check was
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
# The two non-container capabilities, 10 and 20, are excluded: they are tiers 1 and 2 and never run
# the verify play at all.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

VERIFY_YAML="${E2E_ROOT}/tier3/verify.yaml"
TESTING_DIR="${E2E_ROOT}/testing"
RUN_SH="${E2E_ROOT}/run.sh"

# Capabilities that drive a container scenario, and therefore run verify.yaml.
CONTAINER_SPECS=(30-smoke 40-kde-configure-only 50-live-profile 60-defaults 70-desktop-environments 80-all-software)

# Capability 10 is the whole of tier 1, so its spec has to name every check tier 1 runs. It named
# three of six. windows_mapping, windows_npm_parity and this script itself were absent, so a reader
# taking that spec as the definition of tier 1 would have understood it as half its actual size.
TIER1_SPEC="${TESTING_DIR}/10-wizard-toggle-parse-test.md"

info "Tier 1: the harness against the capability specs"

[[ -f "${VERIFY_YAML}" ]] || { fail "verify.yaml is missing" "${VERIFY_YAML}"; finish "harness spec parity"; }
[[ -d "${TESTING_DIR}" ]] || { fail "the capability spec directory is missing" "${TESTING_DIR}"; finish "harness spec parity"; }

# Assertion task names, in file order. An assert task is one whose name starts with Assert, which is
# the convention every assertion in verify.yaml follows. The count is read from the file below rather
# than written here, because a number in a comment goes stale the first time an assertion is added.
mapfile -t assertions < <(sed -nE 's/^[[:space:]]*-[[:space:]]*name:[[:space:]]*(Assert .*)$/\1/p' "${VERIFY_YAML}")

if [[ ${#assertions[@]} -eq 0 ]]; then
    fail "no assertion task names found in verify.yaml, so this check cannot mean anything" \
         "expected task names beginning 'Assert ' in ${VERIFY_YAML}"
    finish "harness spec parity"
fi
pass "verify.yaml declares ${#assertions[@]} assertions"

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

# --- capability 10 against the tier 1 script list -----------------------------
# The list is read out of run_tier1's own for loop, so adding a check to the runner without
# mentioning it in the spec fails here rather than going unnoticed.
tier1_checks="$(sed -nE 's/^[[:space:]]*for check in ([a-z_ ]+); do$/\1/p' "${RUN_SH}")"

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
