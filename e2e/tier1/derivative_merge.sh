#!/usr/bin/env bash
#
# Tier 1: the shell copy of the derivative merge rule agrees with the real one.
#
# setup/ansible/tasks/load_os_dict.yaml merges vars/derivatives/<id>.yaml over the family dictionary,
# each derivative entry replacing the family entry of the same key whole. e2e/tier2/resolve_packages.sh
# cannot run Ansible inside the image it probes, so derivative_package_names_for in
# e2e/lib/package_probe.sh restates that rule in bash, and a second copy of one rule is AGENTS.md
# defect class 2: the day the two disagree, tier 2 resolves a package set no run installs. So this
# drives the shipped loader through derivative_merge.yaml, the way os_family_derivation.sh drives
# derive_os_facts.yaml, and fails for any derivative and manager whose two package lists differ.
#
# Each derivative needs an os-release fixture in os_release_fixtures/ whose ID is the derivative's
# file name, because the family it merges over is derived from that file's ID_LIKE exactly as on a
# real machine. A derivative without one fails by name.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/package_probe.sh"
source "$(dirname "${BASH_SOURCE[0]}")/wsl_delegate.sh"

delegate_to_wsl_when_no_ansible e2e/tier1/derivative_merge.sh

TIER1_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_DIR="${TIER1_DIR}/os_release_fixtures"
VARS_DIR="${ANSIBLE_DIR}/vars"

info "Tier 1: the shell derivative merge agrees with tasks/load_os_dict.yaml"

cases=()
for f in "${VARS_DIR}"/derivatives/*.yaml; do
    [[ -f "${f}" ]] || continue
    id="$(basename "${f}" .yaml)"
    fixture="$(grep -lE "^ID=\"?${id}\"?$" "${FIXTURE_DIR}"/* 2>/dev/null | head -1 || true)"
    if [[ -z "${fixture}" ]]; then
        fail "${id}: no os-release fixture in e2e/tier1/os_release_fixtures carries ID=${id}, so its merge cannot be derived" "${f}"
        continue
    fi
    cases+=("{\"id\": \"${id}\", \"fixture\": \"$(basename "${fixture}")\"}")
done
if [[ ${#cases[@]} -eq 0 ]]; then
    fail "no derivative dictionary could be merged, so this check proves nothing" "${VARS_DIR}/derivatives"
    finish "derivative merge"
fi

play_dir="$(mktemp -d)"
trap 'rm -rf "${play_dir}"' EXIT
cp "${TIER1_DIR}/derivative_merge.yaml" "${TIER1_DIR}/derivative_merge_case.yaml" "${play_dir}/"
ln -s "${VARS_DIR}" "${play_dir}/vars"

extra="{\"ih_derivation\": \"${ANSIBLE_DIR}/tasks/derive_os_facts.yaml\", \"ih_loader\": \"${ANSIBLE_DIR}/tasks/load_os_dict.yaml\", \"ih_fixtures\": \"${FIXTURE_DIR}\", \"ih_derivative_cases\": [$(IFS=,; echo "${cases[*]}")]}"
# dual_logger is this repository's stdout callback and writes ~/installation_*.log on every play, so
# the default callback is used, as in os_family_derivation.sh.
play_out="$(
    ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_FORCE_COLOR=0 \
        ansible-playbook -i localhost, "${play_dir}/derivative_merge.yaml" -e "${extra}" 2>&1 || true
)"
if ! grep -q "IH_MERGE_DONE cases=${#cases[@]}" <<<"${play_out}"; then
    fail "the merge play did not finish" "$(grep -E 'fatal:|FAILED!|failed=[1-9]|ERROR' <<<"${play_out}" | head -4 | tr '\n' ' ')"
    finish "derivative merge"
fi

merged="$(grep -oE 'IH_MERGE id=[a-z0-9_-]+ family=[A-Za-z]+ manager=[a-z_]+ packages=[^"]*' <<<"${play_out}" | sort -u || true)"
for c in "${cases[@]}"; do
    id="$(sed -E 's/.*"id": "([^"]+)".*/\1/' <<<"${c}")"
    family="$(grep -m1 -oE "IH_MERGE id=${id} family=[A-Za-z]+" <<<"${merged}" | sed -E 's/.*family=//' || true)"
    if [[ -z "${family}" || ! -f "${VARS_DIR}/${family}.yaml" ]]; then
        fail "${id}: the merge play reported no family with a dictionary, so nothing was compared" "family '${family}'"
        continue
    fi
    managers="$( {
        grep -oE "IH_MERGE id=${id} family=[A-Za-z]+ manager=[a-z_]+" <<<"${merged}" | sed -E 's/.*manager=//'
        grep -ohE 'manager: "[a-z_]+"' "${VARS_DIR}/${family}.yaml" "${VARS_DIR}/derivatives/${id}.yaml" | sed -E 's/manager: "([a-z_]+)"/\1/'
    } | sort -u )"
    disagreements=()
    compared=0
    while IFS= read -r manager; do
        [[ -z "${manager}" ]] && continue
        compared=$((compared + 1))
        real="$(grep -E "^IH_MERGE id=${id} family=[A-Za-z]+ manager=${manager} " <<<"${merged}" | sed -E 's/.* packages=//' | tr ',' '\n' | grep -v '^$' | sort -u || true)"
        shell="$(derivative_package_names_for "${VARS_DIR}/${family}.yaml" "${VARS_DIR}/derivatives/${id}.yaml" "${manager}")"
        [[ "${real}" == "${shell}" ]] && continue
        disagreements+=("${manager}: only the loader has [$(comm -23 <(echo "${real}") <(echo "${shell}") | tr '\n' ' ')] only the shell has [$(comm -13 <(echo "${real}") <(echo "${shell}") | tr '\n' ' ')]")
    done <<<"${managers}"
    if [[ ${compared} -eq 0 ]]; then
        fail "${id}: no manager was compared, so this check proves nothing for it" "${VARS_DIR}/derivatives/${id}.yaml"
    elif [[ ${#disagreements[@]} -eq 0 ]]; then
        pass "${id}: derivative_package_names_for agrees with tasks/load_os_dict.yaml for all ${compared} managers over vars/${family}.yaml"
    else
        fail "${id}: derivative_package_names_for disagrees with tasks/load_os_dict.yaml, so tier 2 resolves a package set no run installs" \
             "$(printf '%s | ' "${disagreements[@]}")"
    fi
done

finish "derivative merge"
