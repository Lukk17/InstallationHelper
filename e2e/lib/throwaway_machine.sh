#!/usr/bin/env bash
#
# Tier 3 runs only on a GitHub-hosted runner. Sourced by lib/gate.sh, and executed directly only inside
# the gate container, by gate_enter's probe, which is how the launcher learns the answer before it starts
# the run or queues it.
#
# A tier 3 scenario container is privileged, and privileged means it shares the kernel of whatever
# runs the Docker daemon. On the owner's computer that is the owner's own kernel, and four runs changed
# it (docs/regression_ledger.md 10.126 to 10.129). The owner's decision 76 is that nothing may change his
# computer, and his decision 79 is that tier 3 runs only on a GitHub-hosted runner. So there is one
# machine tier 3 may run on and no override for any other:
#
#   a GitHub-hosted runner   GITHUB_ACTIONS=true, RUNNER_OS=Linux and RUNNER_ENVIRONMENT=github-hosted,
#                            all three, which the runner sets for every step and nobody exports by
#                            accident. A self-hosted runner says self-hosted and does not qualify, and
#                            no other virtual machine qualifies, whatever its hypervisor.
#
# Exit codes, when executed: 0 on a GitHub-hosted Linux runner, 2 on any other machine.

# throwaway_machine_verdict <GITHUB_ACTIONS> <RUNNER_OS> <RUNNER_ENVIRONMENT>
# Prints which kind of machine the facts describe and returns 0, or returns 1. Pure, so the tier 1
# check drives every case without a machine of each kind.
throwaway_machine_verdict() {
    local actions="$1" runner_os="$2" runner_environment="$3"

    if [[ "${actions}" == true && "${runner_os}" == Linux && "${runner_environment}" == github-hosted ]]; then
        printf 'a GitHub-hosted Actions runner\n'
        return 0
    fi

    return 1
}

# require_throwaway_machine  ->  returns on a GitHub-hosted Linux runner, exits 2 on any other machine
require_throwaway_machine() {
    if ! e2e_inside_gate; then
        echo "ERROR: require_throwaway_machine answers only inside the gate container, never on the machine that started it" >&2
        exit 2
    fi

    local kind

    if kind="$(throwaway_machine_verdict "${GITHUB_ACTIONS:-}" "${RUNNER_OS:-}" "${RUNNER_ENVIRONMENT:-}")"; then
        printf '>> tier 3 may run here, because this is %s\n' "${kind}"
        return 0
    fi

    cat >&2 <<EOF
REFUSED: tier 3 runs only on a GitHub-hosted runner, and this is not one. No scenario container was
started. A scenario container is privileged and changes the kernel of the machine Docker runs on, so
on this machine it would change this machine.

What this machine answered:
  GitHub runner variables   GITHUB_ACTIONS=${GITHUB_ACTIONS:-unset} RUNNER_OS=${RUNNER_OS:-unset} RUNNER_ENVIRONMENT=${RUNNER_ENVIRONMENT:-unset}

Run it on a GitHub-hosted runner instead. One distribution, one scenario:

    gh workflow run e2e-manual.yaml -f target_platform=debian -f software_mode=defaults

Every scenario on every distribution, which takes hours:

    gh workflow run e2e-matrix.yml

No other virtual machine counts, a local one, WSL 2 or Docker Desktop alike, and neither does a
self-hosted runner. There is no override.
EOF
    exit 2
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    # shellcheck source=host.sh
    source "$(dirname "${BASH_SOURCE[0]}")/host.sh"
    require_throwaway_machine
fi
