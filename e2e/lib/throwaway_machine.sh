#!/usr/bin/env bash
#
# Tier 3 runs only on a machine that is thrown away afterwards. Sourced by lib/gate.sh, and executed
# directly only inside the gate container, by gate_enter's probe, which is how the launcher learns the
# answer before it starts the run or queues it.
#
# A tier 3 scenario container is privileged, and privileged means it shares the kernel of whatever
# runs the Docker daemon. On the owner's computer that is the owner's own kernel, and four runs changed
# it (docs/regression_ledger.md 10.126 to 10.129). The owner's decision 76: "nothing can do changes to
# my computer ! so vm or github action". So there are two machines tier 3 may run on and no override
# for any other:
#
#   a GitHub-hosted runner   GITHUB_ACTIONS=true, RUNNER_OS=Linux and RUNNER_ENVIRONMENT=github-hosted,
#                            all three, which the runner sets for every step and nobody exports by
#                            accident. A self-hosted runner says self-hosted and does not qualify.
#   a virtual machine        systemd-detect-virt --vm names a hypervisor. It reads the CPU's hypervisor
#                            leaf and the firmware tables, which a non-privileged container sees as well
#                            as the machine does, so the gate container can answer without touching the
#                            machine. The virtual machines WSL 2 and Docker Desktop run the daemon in are
#                            excluded by their kernel names, because they are part of the computer they
#                            run on and are not thrown away.
#
# Exit codes, when executed: 0 on a machine tier 3 may run on, 2 on any other.

# throwaway_machine_verdict <GITHUB_ACTIONS> <RUNNER_OS> <RUNNER_ENVIRONMENT> <virtualization> <kernel release>
# Prints which kind of throwaway machine the facts describe and returns 0, or returns 1. Pure, so the
# tier 1 check drives every case without a machine of each kind.
throwaway_machine_verdict() {
    local actions="$1" runner_os="$2" runner_environment="$3" virtualization="$4" kernel_release="$5"

    if [[ "${actions}" == true && "${runner_os}" == Linux && "${runner_environment}" == github-hosted ]]; then
        printf 'a GitHub-hosted Actions runner\n'
        return 0
    fi

    if [[ -z "${virtualization}" || "${virtualization}" == none ]]; then
        return 1
    fi

    case "${kernel_release,,}" in
        *microsoft*|*wsl*|*linuxkit*|*orbstack*) return 1 ;;
    esac

    printf 'a virtual machine (%s)\n' "${virtualization}"
}

# require_throwaway_machine  ->  returns on a machine tier 3 may run on, exits 2 on any other
require_throwaway_machine() {
    if ! e2e_inside_gate; then
        echo "ERROR: require_throwaway_machine answers only inside the gate container, never on the machine that started it" >&2
        exit 2
    fi

    local virtualization kernel_release kind
    virtualization="$(systemd-detect-virt --vm 2>/dev/null || true)"
    kernel_release="$(cat /proc/sys/kernel/osrelease 2>/dev/null || true)"

    if kind="$(throwaway_machine_verdict "${GITHUB_ACTIONS:-}" "${RUNNER_OS:-}" "${RUNNER_ENVIRONMENT:-}" "${virtualization}" "${kernel_release}")"; then
        printf '>> tier 3 may run here, because this is %s\n' "${kind}"
        return 0
    fi

    cat >&2 <<EOF
REFUSED: tier 3 runs only on a GitHub-hosted runner or inside a throwaway virtual machine, and this is
neither. No scenario container was started. A scenario container is privileged and changes the kernel
of the machine Docker runs on, so on this machine it would change this machine.

What this machine answered:
  GitHub runner variables   GITHUB_ACTIONS=${GITHUB_ACTIONS:-unset} RUNNER_OS=${RUNNER_OS:-unset} RUNNER_ENVIRONMENT=${RUNNER_ENVIRONMENT:-unset}
  systemd-detect-virt --vm  ${virtualization:-no answer}
  kernel release            ${kernel_release:-no answer}

Run it on a GitHub-hosted runner instead. One distribution, one scenario:

    gh workflow run e2e-manual.yaml -f target_platform=debian -f software_mode=defaults

Every scenario on every distribution, which takes hours:

    gh workflow run e2e-matrix.yml

Or copy the repository into a throwaway virtual machine with Docker, run the same command there, and
delete the machine afterwards. WSL 2 and Docker Desktop do not count, because their virtual machine
is part of this computer and is not thrown away. There is no override.
EOF
    exit 2
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    # shellcheck source=host.sh
    source "$(dirname "${BASH_SOURCE[0]}")/host.sh"
    require_throwaway_machine
fi
