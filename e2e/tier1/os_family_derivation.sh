#!/usr/bin/env bash
#
# Tier 1: the playbook branches on the derived family, never on Ansible's own answer, and the
# derivation itself resolves every distribution this repository claims to support.
#
# Two halves, because the defect has two shapes.
#
# The static half. Ansible's os_family comes from one fixed table in
# ansible/module_utils/facts/system/distribution.py, and get_distribution_facts() ends with
#     distribution_facts['os_family'] = self.OS_FAMILY.get(distro, None) or distro
# so a distribution absent from that table reports its own name as its family. The Arch entry is
# exactly Archlinux, Antergos and Manjaro, so EndeavourOS and CachyOS are absent, Nobara and Bazzite
# are absent from the RedHat entry, and on any of them every os_family == '...' condition in this
# repository is false, no vars/<family>.yaml matches, and the run stops having installed nothing.
# setup/ansible/tasks/derive_os_facts.yaml derives ih_family from ID_LIKE instead, and this check
# fails the gate for any task that goes back to reading the raw fact, because the fix rots the first
# time somebody adds a task by copying an old one. Genuine exceptions live in
# os_family_reads_allowed.txt as a path plus the exact text of the line, with the reason, so an
# exception forgives one line rather than a whole file.
#
# The runtime half. The derivation is the single point of failure for every distribution, so it is
# driven against one real /etc/os-release per distribution in os_release_fixtures/ and the derived
# ih_family and ih_base are asserted per fixture, openSUSE included, which must NOT resolve to any
# of the five: silently treating it as RedHat would install the wrong packages. The play drives the
# shipped task file rather than a copy of its expressions, because two implementations of one parse
# is the wizard toggle parse desync in docs/regression_ledger.md.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/wsl_delegate.sh"

# Git Bash has no ansible-playbook, so this check re-runs itself inside WSL from there. The whole
# check moves, not just its second half, which costs nothing because the first half is grep.
delegate_to_wsl_when_no_ansible e2e/tier1/os_family_derivation.sh

TIER1_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOWLIST="${TIER1_DIR}/os_family_reads_allowed.txt"
FIXTURE_DIR="${TIER1_DIR}/os_release_fixtures"
PLAY="${TIER1_DIR}/os_family_derivation.yaml"
DERIVATION="${ANSIBLE_DIR}/tasks/derive_os_facts.yaml"
SITE="${ANSIBLE_DIR}/site.yaml"

# Four ways to reach either fact: bracket access and dotted access on ansible_facts, and the two
# top-level aliases. The trailing [^_a-z] on the distribution forms is what keeps
# ansible_distribution_release, _version and _major_version out of it: those are legitimate reads of
# a different fact, and this check is about the family and the distribution name only.
FORBIDDEN='ansible_facts\[.(os_family|distribution).\]|ansible_facts\.(os_family|distribution)([^_a-z]|$)|ansible_os_family|ansible_distribution([^_a-z]|$)'

info "Tier 1: derived OS family (ih_family, ih_base)"

# --- the exemption must not be vacuous -----------------------------------------------------------
# Everything below exempts the derivation file, so a missing or gutted derivation would make the
# static half pass by having nothing left to check. Prove it is there and still does its job first.
derivation_ok=true
[[ -f "${DERIVATION}" ]] || derivation_ok=false
if [[ "${derivation_ok}" == true ]]; then
    grep -q 'ih_family: ' "${DERIVATION}" || derivation_ok=false
    grep -q 'ih_base: ' "${DERIVATION}" || derivation_ok=false
    grep -q "ih_os_release_path | default('/etc/os-release')" "${DERIVATION}" || derivation_ok=false
    grep -q 'ID_LIKE=' "${DERIVATION}" || derivation_ok=false
    grep -q 'UBUNTU_CODENAME=' "${DERIVATION}" || derivation_ok=false
fi
if [[ "${derivation_ok}" == true ]]; then
    pass "the derivation reads /etc/os-release and sets both ih_family and ih_base"
else
    fail "setup/ansible/tasks/derive_os_facts.yaml is missing or no longer derives both facts from ID_LIKE and UBUNTU_CODENAME" \
         "everything below exempts that file, so this check would pass on an empty tree without this guard"
fi

# --- the derivation must run before the vars file named after it is loaded ------------------------
# The `|| true` on both is not decoration. common.sh sets pipefail, so a grep that matches nothing
# makes the whole pipeline exit 1, and an assignment carrying a non-zero status ends the script under
# set -e instead of reporting the check. Proven: without it, deleting the import line killed this
# script silently at that point rather than failing the check.
import_line="$(grep -n 'import_tasks: tasks/derive_os_facts.yaml' "${SITE}" | head -1 | cut -d: -f1 || true)"
vars_line="$(grep -n 'vars/{{ ih_family }}.yaml' "${SITE}" | head -1 | cut -d: -f1 || true)"
if [[ -n "${import_line}" && -n "${vars_line}" && "${import_line}" -lt "${vars_line}" ]]; then
    pass "site.yaml derives the family (line ${import_line}) before loading vars/{{ ih_family }}.yaml (line ${vars_line})"
else
    fail "site.yaml does not import the derivation before the OS dictionary it names" \
         "import at line '${import_line:-none}', dictionary load at line '${vars_line:-none}'"
fi

# --- nothing else may read the raw facts ---------------------------------------------------------
# Whole-line comments are dropped first, because this repository documents the trap it is avoiding
# in the very files that avoid it, and a check that trips over its own documentation is useless.
matches="$(
    grep -rn --include='*.yaml' --include='*.yml' -E "${FORBIDDEN}" "${ANSIBLE_DIR}" 2>/dev/null \
        | grep -v "^${DERIVATION}:" \
        | grep -vE ':[0-9]+:[[:space:]]*#' || true
)"

unexpected=()
declare -A allowlist_hits=()
while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    file="${line%%:*}"
    rel="${file#"${REPO_ROOT}/"}"
    text="${line#*:}"; text="${text#*:}"
    forgiven=false
    if [[ -f "${ALLOWLIST}" ]]; then
        while IFS= read -r entry; do
            [[ -z "${entry}" || "${entry}" == \#* ]] && continue
            entry_path="${entry%% :: *}"
            entry_text="${entry#* :: }"
            [[ "${rel}" == "${entry_path}" ]] || continue
            [[ "${text}" == *"${entry_text}"* ]] || continue
            forgiven=true
            allowlist_hits["${entry}"]=1
            break
        done <"${ALLOWLIST}"
    fi
    [[ "${forgiven}" == true ]] && continue
    unexpected+=("${rel}:${line#*:}")
done <<<"${matches}"

if [[ ${#unexpected[@]} -eq 0 ]]; then
    pass "no task file under setup/ansible reads Ansible's own os_family or distribution"
else
    fail "${#unexpected[@]} line(s) read Ansible's own os_family or distribution instead of ih_family or ih_base" \
         "$(printf '%s | ' "${unexpected[@]}")"
fi

# --- a stale exception is its own hazard ---------------------------------------------------------
# It silently forgives a line that has since been fixed, so the next read added to that file looks
# intentional. Same reasoning as the stale no-op check in toggle_coverage.sh.
stale=()
while IFS= read -r entry; do
    [[ -z "${entry}" || "${entry}" == \#* ]] && continue
    [[ -n "${allowlist_hits[${entry}]:-}" ]] && continue
    stale+=("${entry%% :: *}")
done <"${ALLOWLIST}"

if [[ ${#stale[@]} -eq 0 ]]; then
    pass "every entry in os_family_reads_allowed.txt still matches a real line"
else
    fail "${#stale[@]} entry(ies) in os_family_reads_allowed.txt match nothing any more" "${stale[*]}"
fi

# --- every fixture must be exercised -------------------------------------------------------------
# A fixture nobody references is not a test, and the play asserting over a list that lost an entry
# would pass while proving less. Both directions are checked.
mapfile -t fixtures < <(find "${FIXTURE_DIR}" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort)
orphans=()
for f in "${fixtures[@]}"; do
    grep -qE "fixture:[[:space:]]*${f}[,[:space:]]" "${PLAY}" || orphans+=("${f}")
done
mapfile -t cases < <(grep -oE 'fixture:[[:space:]]*[a-z0-9._-]+' "${PLAY}" | sed -E 's/.*:[[:space:]]*//' | sort)
missing=()
for c in "${cases[@]}"; do
    [[ -f "${FIXTURE_DIR}/${c}" ]] || missing+=("${c}")
done

if [[ ${#fixtures[@]} -lt 10 ]]; then
    fail "only ${#fixtures[@]} os-release fixture(s) found, so this check cannot mean much" \
         "expected one per supported distribution and derivative in ${FIXTURE_DIR}"
elif [[ ${#orphans[@]} -eq 0 && ${#missing[@]} -eq 0 ]]; then
    pass "all ${#fixtures[@]} os-release fixtures are asserted by the play, and every case has a fixture"
else
    fail "fixtures and play cases do not line up" \
         "fixtures nothing asserts: ${orphans[*]:-none}; cases with no fixture: ${missing[*]:-none}"
fi

# --- run the derivation against every fixture ----------------------------------------------------
# dual_logger is this repository's stdout callback and writes ~/installation_*.log on every play.
# This is a check, not an install, so it uses the default callback and leaves those logs alone.
play_out="$(
    ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_FORCE_COLOR=0 \
        ansible-playbook -i localhost, "${PLAY}" -e ih_derivation="${DERIVATION}" 2>&1 || true
)"
summary="$(grep -oE 'IH_DERIVATION_ASSERTED cases=[0-9]+ live_family=[A-Za-z]+ live_base=[^"]*' <<<"${play_out}" | tail -1 || true)"

if [[ -z "${summary}" ]]; then
    fail "the fixture play did not finish" "$(grep -E 'fatal:|FAILED!|failed=[1-9]|ERROR' <<<"${play_out}" | head -4 | tr '\n' ' ')"
else
    asserted="$(sed -E 's/.*cases=([0-9]+).*/\1/' <<<"${summary}")"
    live_family="$(sed -E 's/.*live_family=([A-Za-z]+).*/\1/' <<<"${summary}")"
    live_base="$(sed -E 's/.*live_base=//' <<<"${summary}" | tr -d ' ')"

    assert_eq "the play asserted one case per fixture" "${#fixtures[@]}" "${asserted}"

    if grep -qE 'failed=[1-9]|fatal: .*ignoring' <<<"${play_out}"; then
        fail "the fixture play reported a failure" "$(grep -E 'fatal:|assertion|failed=' <<<"${play_out}" | head -4 | tr '\n' ' ')"
    else
        pass "every fixture derives the expected ih_family and ih_base, and openSUSE is rejected"
    fi

    # The live machine is not a fixture, so no exact pair can be asserted, but a gate that cannot
    # resolve the family of the machine it is running on has found a real defect.
    case "${live_family}" in
        Debian|RedHat|Archlinux|Darwin|Windows)
            pass "this machine resolves to ih_family=${live_family} ih_base=${live_base}" ;;
        *)
            fail "this machine resolves to ih_family='${live_family}', which is not one of the five supported families" \
                 "ih_base='${live_base}'" ;;
    esac
fi

finish "derived OS family"
