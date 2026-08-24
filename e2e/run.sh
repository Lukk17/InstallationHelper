#!/usr/bin/env bash
#
# End-to-end harness entry point.
#
# Usage:
#   run.sh                          tier 1 only, the pre-commit gate (seconds)
#   run.sh --tier 1                 static checks against the working tree
#   run.sh --tier 2                 resolve every package name against real repositories
#   run.sh --tier 3 --scenario defaults     one scenario in a container
#   run.sh --tier 3 --scenario all          every scenario, sequentially (hours)
#   run.sh --tier 3 --scenario all --jobs 3 every scenario, three at a time
#   run.sh --tier 3 --scenario defaults --os debian the same scenario on another distro
#   run.sh --list                   show the scenarios and what each one covers
#   run.sh --help
#
# --jobs only affects tier 3. Each scenario gets its own throwaway container, so they
# are safe to overlap. The limit is host memory, roughly 3 GB per running scenario, and
# on Windows the ceiling is WSL's rather than the host's.
#
# --os picks the distribution, defaulting to arch. One Dockerfile per distribution in
# tier3/, and container.sh refuses a name that has none rather than quietly falling back
# to arch, because testing the wrong distribution is worse than testing nothing.
#
# Tiers 2 and 3 need a Docker daemon and a shell that can drive it. A Linux shell qualifies,
# and so does Git Bash on Windows, where docker.exe reaches Docker Desktop directly and the
# harness translates the host paths itself. WSL qualifies only when Docker Desktop has
# integration enabled for that distribution, because without it there is no socket in there
# at all. Ansible itself still only runs on Linux, so the playbook under test runs inside the
# container either way.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

TIER="1"
SCENARIO=""
JOBS="1"
OS="arch"

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
        --jobs)     shift; JOBS="${1:?--jobs needs a value}" ;;
        --jobs=*)   JOBS="${1#--jobs=}" ;;
        --os)       shift; OS="${1:?--os needs a value}" ;;
        --os=*)     OS="${1#--os=}" ;;
        *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

run_tier1() {
    local rc=0
    for check in wizard_parse toggle_coverage profile_prerequisites timeout_indirection windows_mapping windows_npm_parity windows_settings windows_phase_contract windows_pester powershell_variables powershell_splat verify_spec_parity verify_wiring failed_key_reads tolerated_failures_read os_family_derivation pinned_values pinned_values_reader manifests compose_and_docs network_retries batched_managers line_endings ansible_static; do
        bash "${E2E_ROOT}/tier1/${check}.sh" || rc=1
        echo
    done
    return ${rc}
}

run_tier2() {
    local rc=0
    bash "${E2E_ROOT}/tier2/resolve_packages.sh" || rc=1
    echo
    bash "${E2E_ROOT}/tier2/resolve_role_packages.sh" || rc=1
    echo
    bash "${E2E_ROOT}/tier2/resolve_pinned_urls.sh" || rc=1
    return ${rc}
}

# Peak resident set of one scenario container, measured with docker stats. First set from the paru
# compile at 3 GB, then corrected upward after kde-configure-only was observed at 4.79 GB during the
# software install phase, which is heavier than the compile. Used only to warn, never to refuse.
E2E_MEM_PER_JOB_GB=5

check_memory_headroom() {
    local jobs="$1" avail
    # `|| true` because there is no free(1) in Git Bash. Without it pipefail carries the 127 into
    # the assignment and set -e ends the run, so a warning that exists only to be helpful would
    # have killed every parallel tier 3 run started from that shell.
    avail="$(free -g 2>/dev/null | awk '/^Mem:/{print $7}' || true)"
    [[ -z "${avail}" ]] && return 0
    local need=$(( jobs * E2E_MEM_PER_JOB_GB ))
    if [[ "${avail}" -lt "${need}" ]]; then
        warn "${jobs} parallel jobs want about ${need} GB and this machine has ${avail} GB available."
        warn "Containers will not crash, they will swap and every scenario gets slower. Consider --jobs $(( avail / E2E_MEM_PER_JOB_GB > 0 ? avail / E2E_MEM_PER_JOB_GB : 1 ))."
        warn "On Windows the ceiling is WSL's, not the host's. Raise it with memory= in %USERPROFILE%\\.wslconfig, which needs wsl --shutdown and will stop every running container."
    else
        dim "${jobs} parallel job(s), about ${need} GB wanted, ${avail} GB available"
    fi
}

run_tier3() {
    # Windows is not a scenario on this path. Docker Desktop serves one container platform at a
    # time, so Windows containers require switching the daemon, which turns off the Linux
    # daemon this script is talking to right now. Say that instead of failing obscurely on a
    # missing Dockerfile.
    if [[ "${OS}" == "windows" ]]; then
        cat >&2 <<'EOF'
Windows tier 3 has its own entry point, driven from Windows rather than from WSL.

  pwsh e2e/tier3/Invoke-WindowsE2E.ps1

Why it is separate: Docker Desktop serves one container platform at a time, and switching to
Windows containers turns the Linux daemon off, so no Arch, Debian, Ubuntu or Fedora scenario
can run while it is switched. It also covers less than the Linux scenarios do, because winget
ships as an MSIX package and Server Core has no AppX subsystem, so 82 of the 89 Windows
mappings cannot be installed in any container. It tests the parsing and planning logic on a
clean machine, plus the Chocolatey path.
EOF
        exit 2
    fi

    [[ -n "${SCENARIO}" ]] || { echo "ERROR: --tier 3 needs --scenario <name|all>. Try --list." >&2; exit 2; }
    local files=()
    if [[ "${SCENARIO}" == all ]]; then
        mapfile -t files < <(ls -1 "${E2E_ROOT}"/tier3/scenarios/*.yaml)
    else
        # Comma-separated list accepted, so a parallel run can be aimed at the two or
        # three scenarios a change actually touches instead of every one of them.
        local name found
        IFS=',' read -ra wanted <<<"${SCENARIO}"
        for name in "${wanted[@]}"; do
            name="${name// /}"
            [[ -z "${name}" ]] && continue
            found="$(grep -lE "^e2e_scenario_name:[[:space:]]*\"?${name}\"?[[:space:]]*$" \
                "${E2E_ROOT}"/tier3/scenarios/*.yaml | head -1 || true)"
            [[ -n "${found}" ]] || { echo "ERROR: no scenario named '${name}'. Try --list." >&2; exit 2; }
            files+=("${found}")
        done
        [[ ${#files[@]} -gt 0 ]] || { echo "ERROR: --scenario matched nothing. Try --list." >&2; exit 2; }
    fi

    local rc=0 failed=()

    if [[ "${JOBS}" -le 1 ]]; then
        for f in "${files[@]}"; do
            echo
            bash "${E2E_ROOT}/tier3/container.sh" "${f}" --os "${OS}" || { rc=1; failed+=("$(basename "${f}")"); }
        done
    else
        check_memory_headroom "${JOBS}"
        # Sliding window rather than fixed batches. Scenario runtimes differ by more than a
        # factor of three, so batching would leave the 90 minute one idle waiting on a 300
        # minute one. Each scenario gets its own throwaway container, so nothing they touch
        # overlaps and they are safe to overlap in time. What they do contend for is the
        # single Docker daemon, host CPU and network bandwidth.
        # set -e is off for the whole scheduler on purpose. The readiness probe below is
        # `--collect`, which exits 3 while a scenario is still running, and under set -e that
        # non-zero status from a command substitution assignment terminates the script. It did:
        # a queue of three started two scenarios, hit the first probe, and exited 0 having
        # silently abandoned the third. A scheduler must tolerate non-zero from its probes,
        # because that is how a probe reports "not yet".
        set +e
        local -A running=()          # run dir -> scenario basename
        local queue=("${files[@]}")
        while [[ ${#queue[@]} -gt 0 || ${#running[@]} -gt 0 ]]; do
            while [[ ${#running[@]} -lt ${JOBS} && ${#queue[@]} -gt 0 ]]; do
                local f="${queue[0]}"
                queue=("${queue[@]:1}")
                local out run_dir
                out="$(bash "${E2E_ROOT}/tier3/container.sh" "${f}" --os "${OS}" --detach 2>&1)" || {
                    rc=1; failed+=("$(basename "${f}") (failed to start)")
                    printf '%s\n' "${out}" | tail -5
                    continue
                }
                run_dir="$(grep -oE '^E2E_RUN_DIR=.*$' <<<"${out}" | tail -1 | cut -d= -f2-)"
                if [[ -z "${run_dir}" ]]; then
                    rc=1; failed+=("$(basename "${f}") (no run dir reported)")
                    continue
                fi
                running["${run_dir}"]="$(basename "${f}")"
                info "started $(basename "${f}") -> ${run_dir}  [${#running[@]}/${JOBS} slots busy, ${#queue[@]} queued]"
            done

            [[ ${#running[@]} -eq 0 ]] && continue
            sleep 30

            for run_dir in "${!running[@]}"; do
                local cout crc
                # --collect exits 3 while the playbook is still going and touches
                # nothing, so it doubles as the readiness probe.
                cout="$(bash "${E2E_ROOT}/tier3/container.sh" --collect "${run_dir}" 2>&1)"
                crc=$?
                [[ ${crc} -eq 3 ]] && continue
                echo
                printf '%s\n' "${cout}"
                [[ ${crc} -ne 0 ]] && { rc=1; failed+=("${running[${run_dir}]}"); }
                unset "running[${run_dir}]"
            done
        done
        set -e
        info "queue drained: every scenario started and collected"
    fi

    if [[ ${rc} -ne 0 ]]; then
        echo
        printf '%sScenarios that failed: %s%s\n' "${C_RED}" "${failed[*]}" "${C_OFF}"
    fi
    return ${rc}
}

case "${TIER}" in
    1)   run_tier1 ;;
    2)   require_docker_host; run_tier2 ;;
    3)   require_docker_host; run_tier3 ;;
    all) rc=0; run_tier1 || rc=1; require_docker_host; run_tier2 || rc=1; run_tier3 || rc=1; exit ${rc} ;;
    *)   echo "ERROR: --tier must be 1, 2, 3 or all" >&2; exit 2 ;;
esac
