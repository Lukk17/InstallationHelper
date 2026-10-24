#!/usr/bin/env bash
#
# Tier 1: tier 3 refuses to start anywhere but a GitHub-hosted runner.
#
# A tier 3 scenario container is privileged and shares the kernel of the machine Docker runs on. Run
# on the owner's computer it changed the owner's kernel four ways (docs/regression_ledger.md 10.126 to
# 10.129). The owner's decision 76 is that nothing may change his computer, and his decision 79 is that
# tier 3 runs on a GitHub-hosted runner and nowhere else, not in a virtual machine either, with no
# override.
#
# This proves the refusal three ways. It drives throwaway_machine_verdict over every kind of machine,
# including KVM, Hyper-V and VirtualBox virtual machines, WSL 2 and Docker Desktop, all of which are
# refused. It starts e2e/run.sh and e2e/tier3/container.sh for real, by every route that reaches a
# scenario container, once with this machine made to look like a bare host and once each like a KVM
# and a Hyper-V virtual machine, with a fake docker that records any call, and requires exit 2, the
# refusal text and no docker call at all. And it reads the launcher, which cannot be started from inside
# a container, for the probe that refuses a queued run before it starts.
#
# Proven on 2026-10-18 by pointing E2E_REPO_ROOT at a copy of the tree at commit 0eee74c, which failed
# 1 of 1, at that copy with only lib/throwaway_machine.sh and the gate image added, which failed 7 of 13,
# and at eight copies of the finished tree with one part of the refusal removed or weakened at a time:
# each inner call, the GitHub runner environment test, the WSL exclusion, the launcher's probe, the
# variables handed to the gate, the probe's status, and an override variable. Each one failed. Proven
# again on 2026-10-19, after decision 79, against a copy of the tree at commit 3ae27ec, whose library
# still admits a virtual machine, and against a copy of the finished tree with the virtual machine
# route put back into lib/throwaway_machine.sh. Both failed.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

RUN_SH="${REPO_ROOT}/e2e/run.sh"
CONTAINER_SH="${REPO_ROOT}/e2e/tier3/container.sh"
GATE_SH="${REPO_ROOT}/e2e/lib/gate.sh"
THROWAWAY_SH="${REPO_ROOT}/e2e/lib/throwaway_machine.sh"
GATE_DOCKERFILE="${REPO_ROOT}/e2e/gate/Dockerfile"
REFUSAL_LINE="REFUSED: tier 3 runs only on a GitHub-hosted runner, and this is not one."

info "Tier 1: tier 3 runs only on a GitHub-hosted runner"

# A route that is not refused runs the harness it was handed, and --tier all runs this check again.
# The nested copy stops here, and every route below has a time limit, so a missing refusal costs this
# check thirty seconds a route rather than a run that never ends.
if [[ "${E2E_THROWAWAY_CHECK_NESTED:-}" == 1 ]]; then
    pass "started by a route under test, so nothing is checked again"
    finish "tier 3 throwaway machines only"
fi

for required in "${RUN_SH}" "${CONTAINER_SH}" "${GATE_SH}" "${THROWAWAY_SH}" "${GATE_DOCKERFILE}"; do
    if [[ ! -f "${required}" ]]; then
        fail "a file the tier 3 refusal lives in is missing, so nothing refuses a run on a real machine" "${required}"
        finish "tier 3 throwaway machines only"
    fi
done

# --- the verdict, over every kind of machine ------------------------------------------------------
# shellcheck source=../lib/throwaway_machine.sh
source "${THROWAWAY_SH}"
if ! declare -F throwaway_machine_verdict >/dev/null || ! declare -F require_throwaway_machine >/dev/null; then
    fail "lib/throwaway_machine.sh does not define throwaway_machine_verdict and require_throwaway_machine" \
         "nothing below can be asked whether a machine may run tier 3"
    finish "tier 3 throwaway machines only"
fi

# The two facts after GitHub's three are what systemd-detect-virt --vm and the kernel release would say
# on that machine. The verdict is handed them as well, so a verdict that reads them again, as the one
# before decision 79 did, admits the virtual machines below and fails here.
# expected | GITHUB_ACTIONS | RUNNER_OS | RUNNER_ENVIRONMENT | systemd-detect-virt --vm | kernel release | which machine
VERDICT_CASES=(
    "refuse||||none|7.2.9-2-cachyos|a bare machine, as the owner's computer is"
    "refuse||||||a machine where systemd-detect-virt gave no answer"
    "refuse||||kvm|6.12.0-1-amd64|a KVM virtual machine"
    "refuse||||microsoft|6.8.0-45-generic|a Hyper-V virtual machine"
    "refuse||||oracle|6.8.0-45-generic|a VirtualBox virtual machine"
    "refuse||||vmware|6.8.0-45-generic|a VMware virtual machine"
    "refuse||||microsoft|6.6.87.2-microsoft-standard-WSL2|WSL 2, whose virtual machine is part of the computer"
    "refuse||||kvm|6.10.14-linuxkit|Docker Desktop, whose virtual machine is part of the computer"
    "refuse||||apple|6.15.11-orbstack-00360-g0d6d2b1c5c4f|OrbStack, whose virtual machine is part of the computer"
    "admit|true|Linux|github-hosted|microsoft|6.11.0-1018-azure|a GitHub-hosted Linux runner"
    "admit|true|Linux|github-hosted|none|6.11.0-1018-azure|a GitHub-hosted Linux runner whose hypervisor goes unnamed"
    "refuse|true|Linux|self-hosted|none|7.2.9-2-cachyos|a self-hosted runner on a bare machine"
    "refuse|true|||none|7.2.9-2-cachyos|a bare machine with only GITHUB_ACTIONS exported"
    "refuse|true|Linux||none|7.2.9-2-cachyos|a bare machine with GITHUB_ACTIONS and RUNNER_OS exported"
    "refuse|1|Linux|github-hosted|none|7.2.9-2-cachyos|a bare machine with GITHUB_ACTIONS=1 rather than true"
    "refuse|true|macOS|github-hosted|none|25.0.0|a GitHub-hosted macOS runner, which cannot run a Linux container"
)
wrong_verdicts=()
for case_line in "${VERDICT_CASES[@]}"; do
    IFS='|' read -r expected actions runner_os runner_environment virtualization kernel_release machine <<<"${case_line}"
    if throwaway_machine_verdict "${actions}" "${runner_os}" "${runner_environment}" "${virtualization}" "${kernel_release}" >/dev/null; then
        actual=admit
    else
        actual=refuse
    fi
    [[ "${actual}" == "${expected}" ]] || wrong_verdicts+=("${machine}: expected ${expected}, got ${actual}")
done
if [[ ${#wrong_verdicts[@]} -eq 0 ]]; then
    pass "throwaway_machine_verdict answers all ${#VERDICT_CASES[@]} kinds of machine as expected, admitting only GitHub-hosted Linux runners and no virtual machine"
else
    fail "throwaway_machine_verdict answers ${#wrong_verdicts[@]} of ${#VERDICT_CASES[@]} machines wrongly" \
         "$(printf '%s; ' "${wrong_verdicts[@]}")"
fi

# Asking the machine what it is would only matter to a route that admits a virtual machine, so the
# library must not ask at all.
throwaway_code="$(grep -vE '^[[:space:]]*#' "${THROWAWAY_SH}")"
if grep -qE 'systemd-detect-virt|osrelease|/proc/' <<<"${throwaway_code}"; then
    fail "lib/throwaway_machine.sh asks the machine what it is, which only a virtual machine route needs" \
         "$(grep -nE 'systemd-detect-virt|osrelease|/proc/' <<<"${throwaway_code}" | sed -n 1,3p | tr '\n' ' ')"
else
    pass "lib/throwaway_machine.sh never asks the machine whether it is a virtual machine"
fi

# A switch somebody exports would never show in the cases above or the routes below, which run with it
# unset, so the two functions are also read for every variable they expand. Their own parameters, the
# facts they gather and GitHub's three variables are the whole of what may decide.
decision_bodies="$(sed -n '/^throwaway_machine_verdict() {/,/^}/p; /^require_throwaway_machine() {/,/^}/p' <<<"${throwaway_code}")"
ALLOWED_EXPANSIONS=(actions runner_os runner_environment kind GITHUB_ACTIONS RUNNER_OS RUNNER_ENVIRONMENT)
foreign_expansions=()
while IFS= read -r expanded; do
    [[ -z "${expanded}" ]] && continue
    allowed=no
    for name in "${ALLOWED_EXPANSIONS[@]}"; do
        [[ "${expanded}" == "${name}" ]] && allowed=yes
    done
    [[ "${allowed}" == yes ]] || foreign_expansions+=("${expanded}")
done < <(grep -oE '\$\{?!?[A-Za-z_][A-Za-z0-9_]*' <<<"${decision_bodies}" | sed -E 's/^\$\{?!?//' | sort -u)
if [[ -z "${decision_bodies}" ]]; then
    fail "throwaway_machine_verdict and require_throwaway_machine could not be read out of lib/throwaway_machine.sh" "${THROWAWAY_SH}"
elif [[ ${#foreign_expansions[@]} -eq 0 ]]; then
    pass "the decision reads nothing but GitHub's three variables, so there is no switch to override it"
else
    fail "the decision reads a variable that is not one of GitHub's three, which is an override or a second route" \
         "${foreign_expansions[*]}"
fi

# --- every route to a scenario container, started for real ---------------------------------------
# The fakes go on PATH first: a docker that records each call and fails, and a systemd-detect-virt that
# answers like the machine under test, a bare host, a KVM guest or a Hyper-V guest. GitHub's three
# variables are removed, so the answer is the same on the owner's computer and on a GitHub runner
# running this gate. Each fake has to be the one that resolves before anything is started with it.
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
docker_calls="${work_dir}/docker_calls"

# machine label | what the fake systemd-detect-virt --vm answers
MACHINES=(
    "a bare machine|none"
    "a KVM virtual machine|kvm"
    "a Hyper-V virtual machine|microsoft"
)

machine_bin() {
    printf '%s/bin-%s\n' "${work_dir}" "$1"
}

as_machine() {
    local answer="$1"
    shift
    env -u GITHUB_ACTIONS -u RUNNER_OS -u RUNNER_ENVIRONMENT PATH="$(machine_bin "${answer}"):${PATH}" NO_COLOR=1 \
        E2E_THROWAWAY_CHECK_NESTED=1 "$@"
}

for machine in "${MACHINES[@]}"; do
    answer="${machine#*|}"
    fake_bin="$(machine_bin "${answer}")"
    mkdir -p "${fake_bin}"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s"\nexit 1\n' "${docker_calls}" >"${fake_bin}/docker"
    if [[ "${answer}" == none ]]; then
        printf '#!/usr/bin/env bash\necho none\nexit 1\n' >"${fake_bin}/systemd-detect-virt"
    else
        printf '#!/usr/bin/env bash\necho %s\nexit 0\n' "${answer}" >"${fake_bin}/systemd-detect-virt"
    fi
    chmod +x "${fake_bin}/docker" "${fake_bin}/systemd-detect-virt"

    resolved_docker="$(as_machine "${answer}" bash -c 'command -v docker')"
    resolved_virt="$(as_machine "${answer}" bash -c 'command -v systemd-detect-virt')"
    answered_virt="$(as_machine "${answer}" systemd-detect-virt --vm || true)"
    if [[ "${resolved_docker}" != "${fake_bin}/docker" || "${resolved_virt}" != "${fake_bin}/systemd-detect-virt" \
          || "${answered_virt}" != "${answer}" ]]; then
        fail "the fakes for ${machine%%|*} do not resolve first, so the routes below would reach the real docker" \
             "docker -> ${resolved_docker}, systemd-detect-virt -> ${resolved_virt}, answering ${answered_virt}"
        finish "tier 3 throwaway machines only"
    fi
done
pass "the fake docker and the fake systemd-detect-virt for each of ${#MACHINES[@]} machines are the ones that resolve"

scenario_file="${REPO_ROOT}/e2e/tier3/scenarios/01-defaults.yaml"
if [[ ! -f "${scenario_file}" ]]; then
    fail "the defaults scenario file is missing, so container.sh cannot be started with a scenario" "${scenario_file}"
    finish "tier 3 throwaway machines only"
fi

ROUTES=(
    "run.sh --tier 3|${RUN_SH} --tier 3 --scenario defaults --os debian"
    "run.sh --tier=3|${RUN_SH} --tier=3 --scenario defaults --os arch"
    "run.sh --tier 3 --jobs 3|${RUN_SH} --tier 3 --scenario all --jobs 3"
    "run.sh --tier all|${RUN_SH} --tier all --scenario defaults"
    "container.sh <scenario>|${CONTAINER_SH} ${scenario_file} --os debian"
    "container.sh <scenario> --detach|${CONTAINER_SH} ${scenario_file} --os fedora --detach"
)
ROUTE_SECONDS=30
for machine in "${MACHINES[@]}"; do
    machine_name="${machine%%|*}"
    answer="${machine#*|}"
    for route in "${ROUTES[@]}"; do
        route_name="${route%%|*}"
        read -r -a route_args <<<"${route#*|}"
        : >"${docker_calls}"
        route_rc=0
        route_out="$(cd "${REPO_ROOT}" && as_machine "${answer}" timeout --kill-after=5 "${ROUTE_SECONDS}" bash "${route_args[@]}" 2>&1)" || route_rc=$?
        problems=()
        [[ ${route_rc} -eq 2 ]] || problems+=("exit ${route_rc}, not 2")
        grep -qF "${REFUSAL_LINE}" <<<"${route_out}" || problems+=("no refusal printed")
        grep -qF "gh workflow run e2e-manual.yaml" <<<"${route_out}" || problems+=("the refusal does not name the single platform workflow")
        if [[ -s "${docker_calls}" ]]; then
            problems+=("docker was called: $(head -3 "${docker_calls}" | tr '\n' ' ')")
        fi
        if [[ ${#problems[@]} -eq 0 ]]; then
            pass "${route_name} on ${machine_name} exits 2 with the refusal and never calls docker"
        else
            fail "${route_name} on ${machine_name} is not refused" \
                 "$(printf '%s; ' "${problems[@]}") output: $(tail -3 <<<"${route_out}" | tr '\n' ' ')"
        fi
    done
done

: >"${docker_calls}"
collect_out="$(cd "${REPO_ROOT}" && as_machine none timeout --kill-after=5 "${ROUTE_SECONDS}" bash "${CONTAINER_SH}" --collect "${work_dir}/no-such-run" 2>&1 || true)"
if grep -qF "${REFUSAL_LINE}" <<<"${collect_out}"; then
    fail "container.sh --collect is refused on a bare machine" \
         "it starts nothing, and refusing it leaves a scenario container nobody can collect or remove"
else
    pass "container.sh --collect, which starts nothing, is not refused"
fi

# --- the launcher, which a container cannot start -------------------------------------------------
# Comments say what the code does, so only code lines are read.
run_code="$(grep -vE '^[[:space:]]*#' "${RUN_SH}")"
container_code="$(grep -vE '^[[:space:]]*#' "${CONTAINER_SH}")"
gate_code="$(grep -vE '^[[:space:]]*#' "${GATE_SH}")"

launcher_gaps=()
grep -qxF '[[ "${GATE_TIER}" == 3 || "${GATE_TIER}" == all ]] && GATE_REQUIRES_THROWAWAY=1' <<<"${run_code}" \
    || launcher_gaps+=("run.sh does not ask the launcher for the probe on --tier 3 and --tier all")
awk '/GATE_REQUIRES_THROWAWAY=1/{set=NR} /^gate_enter /{enter=NR} END{exit !(set && enter && set < enter)}' <<<"${run_code}" \
    || launcher_gaps+=("run.sh does not set GATE_REQUIRES_THROWAWAY before gate_enter")
awk '/^GATE_REQUIRES_THROWAWAY=1$/{set=NR} /^gate_enter /{enter=NR} END{exit !(set && enter && set < enter)}' <<<"${container_code}" \
    || launcher_gaps+=("container.sh does not set GATE_REQUIRES_THROWAWAY=1 before gate_enter")

gate_enter_body="$(sed -n '/^gate_enter() {/,/^}/p' <<<"${gate_code}")"
probe_line="$(grep -nF 'gate_probe_throwaway_machine "${repo_root}"' <<<"${gate_enter_body}" | sed -n 1p | cut -d: -f1 || true)"
queue_line="$(grep -nF 'docker run -d --name "${E2E_GATE_QUEUE_NAME}"' <<<"${gate_enter_body}" | sed -n 1p | cut -d: -f1 || true)"
wait_line="$(grep -nF 'docker run --rm "${run_opts[@]}"' <<<"${gate_enter_body}" | sed -n 1p | cut -d: -f1 || true)"
if [[ -z "${probe_line}" || -z "${queue_line}" || -z "${wait_line}" ]]; then
    launcher_gaps+=("gate_enter has no probe, or no queued or waiting run to put it in front of")
elif (( probe_line > queue_line || probe_line > wait_line )); then
    launcher_gaps+=("gate_enter probes after it starts a run, so a queued tier 3 run starts before it is refused")
fi
grep -qF 'if [[ "${GATE_REQUIRES_THROWAWAY:-}" == 1 ]]; then' <<<"${gate_enter_body}" \
    || launcher_gaps+=("gate_enter does not run the probe when GATE_REQUIRES_THROWAWAY is 1")
probe_body="$(sed -n '/^gate_probe_throwaway_machine() {/,/^}/p' <<<"${gate_code}")"
grep -qF 'e2e/lib/throwaway_machine.sh' <<<"${probe_body}" && grep -qF '"${E2E_GATE_RUNNER_ENV[@]}"' <<<"${probe_body}" \
    && grep -qF '[[ ${rc} -eq 0 ]] || exit "${rc}"' <<<"${probe_body}" \
    || launcher_gaps+=("gate_probe_throwaway_machine does not run lib/throwaway_machine.sh with the runner variables and stop on its refusal")
grep -qF '"${E2E_GATE_RUNNER_ENV[@]}"' <<<"$(sed -n '/local run_opts=(/,/^    )/p' <<<"${gate_enter_body}")" \
    || launcher_gaps+=("the gate container is not handed GITHUB_ACTIONS, RUNNER_OS and RUNNER_ENVIRONMENT, so tier 3 is refused on a GitHub runner too")
grep -qxF 'E2E_GATE_RUNNER_ENV=(-e GITHUB_ACTIONS -e RUNNER_OS -e RUNNER_ENVIRONMENT)' <<<"${gate_code}" \
    || launcher_gaps+=("E2E_GATE_RUNNER_ENV does not name exactly GITHUB_ACTIONS, RUNNER_OS and RUNNER_ENVIRONMENT")

grep -qxF '    require_throwaway_machine' <<<"$(grep -A1 -xF 'if [[ "${TIER}" == 3 || "${TIER}" == all ]]; then' <<<"${run_code}")" \
    || launcher_gaps+=("run.sh does not ask require_throwaway_machine, unconditionally, for --tier 3 and --tier all")
grep -qxF '    require_throwaway_machine' <<<"$(grep -A1 -xF 'if [[ "${MODE}" != "collect" ]]; then' <<<"${container_code}")" \
    || launcher_gaps+=("container.sh does not ask require_throwaway_machine, unconditionally, for every mode but --collect")

if [[ ${#launcher_gaps[@]} -eq 0 ]]; then
    pass "the launcher probes the machine before it starts or queues a tier 3 run, and hands the probe GitHub's variables"
else
    fail "the launcher can start or queue tier 3 without asking whether the machine is thrown away" \
         "$(printf '%s; ' "${launcher_gaps[@]}")"
fi

finish "tier 3 throwaway machines only"
