#!/usr/bin/env bash
#
# End-to-end harness entry point.
#
# Usage:
#   run.sh                          tier 1 only, the pre-commit gate (seconds)
#   run.sh --tier 1                 static checks against the working tree
#   run.sh --tier 2                 resolve every package name against real repositories
#   run.sh --tier 3 --scenario smoke        one scenario in a container
#   run.sh --tier 3 --scenario all          every scenario, sequentially (hours)
#   run.sh --list                   show the scenarios and what each one covers
#   run.sh --help
#
# Tiers 2 and 3 need Docker and a Linux shell. On Windows run this from inside WSL,
# which is also the only place the playbook itself runs.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

TIER="1"
SCENARIO=""

usage() { sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

list_scenarios() {
    printf '%-22s %s\n' "SCENARIO" "COVERS"
    for f in "${E2E_ROOT}"/tier3/scenarios/*.yaml; do
        n="$(grep -E '^e2e_scenario_name:' "${f}" | sed -E 's/^[^:]+:[[:space:]]*//' | tr -d '"')"
        d="$(grep -E '^e2e_scenario_description:' "${f}" | sed -E 's/^[^:]+:[[:space:]]*//' | tr -d '"')"
        t="$(grep -E '^e2e_timeout_minutes:' "${f}" | sed -E 's/^[^:]+:[[:space:]]*//')"
        printf '%-22s %s (timeout %s min)\n' "${n}" "${d}" "${t:-180}"
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)  usage; exit 0 ;;
        --list)     list_scenarios; exit 0 ;;
        --tier)     shift; TIER="${1:?--tier needs a value}" ;;
        --tier=*)   TIER="${1#--tier=}" ;;
        --scenario) shift; SCENARIO="${1:?--scenario needs a value}" ;;
        --scenario=*) SCENARIO="${1#--scenario=}" ;;
        *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

run_tier1() {
    local rc=0
    for check in wizard_parse toggle_coverage ansible_static; do
        bash "${E2E_ROOT}/tier1/${check}.sh" || rc=1
        echo
    done
    return ${rc}
}

run_tier2() {
    bash "${E2E_ROOT}/tier2/resolve_packages.sh"
}

run_tier3() {
    [[ -n "${SCENARIO}" ]] || { echo "ERROR: --tier 3 needs --scenario <name|all>. Try --list." >&2; exit 2; }
    local files=()
    if [[ "${SCENARIO}" == all ]]; then
        mapfile -t files < <(ls -1 "${E2E_ROOT}"/tier3/scenarios/*.yaml)
    else
        mapfile -t files < <(grep -lE "^e2e_scenario_name:[[:space:]]*\"?${SCENARIO}\"?[[:space:]]*$" \
            "${E2E_ROOT}"/tier3/scenarios/*.yaml || true)
        [[ ${#files[@]} -gt 0 ]] || { echo "ERROR: no scenario named '${SCENARIO}'. Try --list." >&2; exit 2; }
    fi

    local rc=0 failed=()
    for f in "${files[@]}"; do
        echo
        bash "${E2E_ROOT}/tier3/arch_container.sh" "${f}" || { rc=1; failed+=("$(basename "${f}")"); }
    done
    if [[ ${rc} -ne 0 ]]; then
        echo
        printf '%sScenarios that failed: %s%s\n' "${C_RED}" "${failed[*]}" "${C_OFF}"
    fi
    return ${rc}
}

case "${TIER}" in
    1)   run_tier1 ;;
    2)   require_linux_docker; run_tier2 ;;
    3)   require_linux_docker; run_tier3 ;;
    all) rc=0; run_tier1 || rc=1; require_linux_docker; run_tier2 || rc=1; run_tier3 || rc=1; exit ${rc} ;;
    *)   echo "ERROR: --tier must be 1, 2, 3 or all" >&2; exit 2 ;;
esac
