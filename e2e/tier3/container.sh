#!/usr/bin/env bash
#
# Tier 3: run one scenario end to end inside a systemd-enabled container.
#
# Usage:
#   container.sh <scenario-file>                     start, wait, verify, tear down
#   container.sh <scenario-file> --os debian         same, on a different distribution
#   container.sh <scenario-file> --detach            start and return, leaving it running
#   container.sh --collect <run-dir>                 verify and tear down a detached run
#
# --os selects the distribution image, defaulting to arch. Each one has its own
# Dockerfile in this directory and its own image tag, so switching does not rebuild the
# others. Ubuntu is a separate image from Debian even though Ansible reports the same
# os_family for both and they therefore share vars/Debian.yaml, because their package
# versions, snap support and release codenames differ, and that difference is exactly
# where a Debian-only assumption breaks.
#
# Each run gets its own container and its own directory under e2e/runs/, holding the
# exact variable file that was used, the full playbook log, the verify log, and a
# result file. Nothing is inferred after the fact.
#
# The playbook always runs detached INSIDE the container, writing its own log and exit
# code there, and this script only watches it. That matters for the long scenarios: a
# full software run takes hours, and tying it to the lifetime of whatever shell started
# it means an ordinary disconnect throws the whole run away. With --detach the container
# keeps working with nothing attached, and --collect finishes the job later from any
# shell.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_linux_docker

TIER3_DIR="${E2E_ROOT}/tier3"
E2E_USER="lukk"

MODE="wait"
SCENARIO_FILE=""
RUN_DIR=""
OS="arch"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --collect)
            MODE="collect"
            shift
            RUN_DIR="${1:?usage: container.sh --collect <run-dir>}"
            [[ -d "${RUN_DIR}" ]] || { echo "ERROR: no such run directory: ${RUN_DIR}" >&2; exit 2; }
            ;;
        --detach)   MODE="detach" ;;
        --os)       shift; OS="${1:?--os needs a value}" ;;
        --os=*)     OS="${1#--os=}" ;;
        -*)         echo "ERROR: unknown option: $1" >&2; exit 2 ;;
        *)
            SCENARIO_FILE="$1"
            [[ -f "${SCENARIO_FILE}" ]] || { echo "ERROR: no such scenario file: ${SCENARIO_FILE}" >&2; exit 2; }
            ;;
    esac
    shift
done

if [[ "${MODE}" != "collect" && -z "${SCENARIO_FILE}" ]]; then
    echo "ERROR: usage: container.sh <scenario-file> [--os <name>] [--detach] | --collect <run-dir>" >&2
    exit 2
fi

# Each distribution gets its own Dockerfile and image tag. Refuse an unknown name
# rather than falling back to Arch, because silently testing the wrong distribution is
# worse than not testing at all.
DOCKERFILE="${TIER3_DIR}/${OS}.Dockerfile"
IMAGE="installationhelper-e2e-${OS}:latest"
if [[ "${MODE}" != "collect" && ! -f "${DOCKERFILE}" ]]; then
    echo "ERROR: no Dockerfile for --os ${OS}. Available:" >&2
    ls -1 "${TIER3_DIR}"/*.Dockerfile 2>/dev/null | xargs -r -n1 basename | sed 's/\.Dockerfile$//; s/^/  /' >&2
    exit 2
fi

# The shared limits, then this distribution's own if it has any. A limitation is not always the
# same on every distribution even when the missing kernel facility is: OpenRazer's DKMS build
# fails identically on Arch and Fedora, and pacman's hook returns 0 while RPM treats the failed
# %posttrans as a transaction failure and takes the other three packages in the batch down with
# it. Suppressing openrazer everywhere to satisfy Fedora would have thrown away the Arch coverage
# that exists for the "Arch OpenRazer device group does not exist" ledger entry, so the
# suppression is per distribution and the shared file stays for things no container can do.
LIMITS_FILES=("${TIER3_DIR}/container_limits.yaml")
[[ -f "${TIER3_DIR}/container_limits.${OS}.yaml" ]] && LIMITS_FILES+=("${TIER3_DIR}/container_limits.${OS}.yaml")

# ---------------------------------------------------------------------------
# Start phase
# ---------------------------------------------------------------------------
start_run() {
    # An absent key is normal, not an error. Without the guard, grep's exit 1 travels
    # through pipefail into the assignment and set -e kills the run before it starts.
    scenario_get() {
        grep -E "^${1}:" "${SCENARIO_FILE}" 2>/dev/null \
            | head -1 \
            | sed -E "s/^${1}:[[:space:]]*//; s/[[:space:]]*(#.*)?$//" \
            | tr -d '"' || true
    }

    SCENARIO_NAME="$(scenario_get e2e_scenario_name)"
    SCENARIO_DESC="$(scenario_get e2e_scenario_description)"
    SCENARIO_PROFILE="$(scenario_get e2e_profile)"
    SCENARIO_GENERATE="$(scenario_get e2e_generate)"
    TIMEOUT_MIN="$(scenario_get e2e_timeout_minutes)"
    : "${SCENARIO_NAME:=$(basename "${SCENARIO_FILE}" .yaml)}"
    : "${TIMEOUT_MIN:=180}"

    RUN_ID="$(timestamp)_${OS}_${SCENARIO_NAME}"
    RUN_DIR="${RUNS_DIR}/${RUN_ID}"
    mkdir -p "${RUN_DIR}"
    # Group and other writable, because a run can be started by the queue container as root and
    # collected later from a WSL shell as an ordinary user, or the reverse. Without this the
    # collector could not even write its own log into a directory the queue had created, and the
    # run was unreachable from anywhere except the container that started it. These are throwaway
    # log directories on a mounted Windows filesystem, where the permission bits are cosmetic.
    chmod 0777 "${RUN_DIR}" 2>/dev/null || true
    CONTAINER="e2e-${OS}-${SCENARIO_NAME}-$$"
    EFFECTIVE_VARS="${RUN_DIR}/effective-vars.yaml"

    info "Scenario  : ${SCENARIO_NAME}"
    dim  "${SCENARIO_DESC}"
    info "Run dir   : ${RUN_DIR}"
    info "Timeout   : ${TIMEOUT_MIN} minutes"

    # --- effective variable file ---------------------------------------------
    # Order is the whole contract: the scenario's own keys, then any generated
    # software block, then the container limits last so they always win.
    {
        echo "---"
        echo "# Generated by container.sh for scenario ${SCENARIO_NAME}. Do not edit."
        echo "# This is the exact -e input the playbook received."
        grep -vE '^(---|e2e_generate_except:|[[:space:]]*-[[:space:]])' "${SCENARIO_FILE}" | grep -vE '^\s*$' || true
    } > "${EFFECTIVE_VARS}"

    if [[ -n "${SCENARIO_GENERATE}" ]]; then
        # Collected from the two files the wizard itself reads, so a newly added toggle
        # is picked up with no edit here. A hand-maintained copy would quietly stop
        # covering new software, which is the silent gap this suite exists to catch.
        # The wizard's EXCLUDED_VARS list is read out of setup.sh rather than restated,
        # because those keys are system settings rather than software and must not be swept
        # into a generated software set. install_system_core is the one that mattered: the
        # smoke scenario generated it as false, which disabled the entire system_core role,
        # so the scenario silently skipped the bootstrap and reported a pass over far less
        # than it appeared to cover. Exactly the kind of hole this suite exists to close, in
        # the suite itself.
        excluded_line="$(grep -m1 '^EXCLUDED_VARS=' "${REPO_ROOT}/setup/setup.sh" || true)"
        eval "${excluded_line}"

        mapfile -t all_toggles < <(
            cat "${ANSIBLE_DIR}/group_vars/all.yaml" "${ANSIBLE_DIR}/group_vars/linux.yaml" \
                | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//' \
                | grep -E '^install_[a-z0-9_]+: (true|false)$' \
                | sed -E 's/^(install_[a-z0-9_]+):.*/\1/' \
                | grep -vE "^(${EXCLUDED_VARS})$" \
                | sort -u
        )
        mapfile -t excepted < <(sed -n '/^e2e_generate_except:/,/^[a-z]/p' "${SCENARIO_FILE}" \
            | grep -E '^[[:space:]]*-[[:space:]]' | sed -E 's/^[[:space:]]*-[[:space:]]*//' | tr -d '"')

        case "${SCENARIO_GENERATE}" in
            all_software) gen_value="true"  ;;
            no_software)  gen_value="false" ;;
            *) echo "ERROR: unknown e2e_generate value '${SCENARIO_GENERATE}'" >&2; exit 2 ;;
        esac

        echo "# --- generated: e2e_generate=${SCENARIO_GENERATE} ---" >> "${EFFECTIVE_VARS}"
        skipped=()
        for t in "${all_toggles[@]}"; do
            bare="${t#install_}"
            is_excepted=false
            for e in "${excepted[@]+"${excepted[@]}"}"; do
                [[ "${e}" == "${bare}" ]] && is_excepted=true && break
            done
            if [[ "${is_excepted}" == true ]]; then skipped+=("${bare}"); continue; fi
            # A key the scenario states explicitly wins over the generated value.
            grep -qE "^${t}:" "${SCENARIO_FILE}" && continue
            # So does a container limit, appended below. Emitting it here too would
            # produce a duplicate mapping key and a warning per toggle.
            grep -qhE "^${t}:" "${LIMITS_FILES[@]}" && continue
            echo "${t}: ${gen_value}" >> "${EFFECTIVE_VARS}"
        done
        dim "generated ${#all_toggles[@]} install_ toggles as ${gen_value}"
        [[ ${#skipped[@]} -gt 0 ]] && warn "excluded from the generated set: ${skipped[*]}"
    fi

    echo "# --- container limits (always applied last) ---" >> "${EFFECTIVE_VARS}"
    for limits in "${LIMITS_FILES[@]}"; do
        grep -vE '^(---|#)' "${limits}" | { grep -vE '^\s*$' || true; } >> "${EFFECTIVE_VARS}"
    done

    warn "suppressed as impossible in a container, so NOT covered by this run:"
    grep -hE '^[a-z_]+: false$' "${LIMITS_FILES[@]}" | sed 's/^/       /' || true

    # --- container ------------------------------------------------------------
    info "Building the ${OS} base image (cached after the first run)"
    docker build -q -f "${DOCKERFILE}" -t "${IMAGE}" "${TIER3_DIR}" >/dev/null

    info "Starting the container with systemd as PID 1"
    docker run -d --name "${CONTAINER}" \
        --privileged \
        --cgroupns=host \
        -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
        --tmpfs /run --tmpfs /run/lock \
        "${IMAGE}" >/dev/null

    # Poll rather than sleep blindly, and accept `degraded`: getty and firstboot always
    # fail in a container and neither matters here.
    local state=""
    for _ in $(seq 1 30); do
        state="$(docker exec "${CONTAINER}" systemctl is-system-running 2>/dev/null || true)"
        [[ "${state}" == running || "${state}" == degraded ]] && break
        sleep 1
    done
    info "systemd state: ${state:-unknown}"
    if [[ "${state}" != running && "${state}" != degraded ]]; then
        docker rm -f "${CONTAINER}" &>/dev/null || true
        echo "systemd never came up, aborting" | tee "${RUN_DIR}/result.txt"
        exit 1
    fi

    # Copied in, not bind-mounted. A run must never be able to modify the working tree
    # it is testing.
    #
    # Every step here is checked, and the result is asserted afterwards rather than inferred
    # from an exit code. None of it was, and a real run paid for it: with the repository
    # reached over a drvfs bind mount, the daemon failed mid-archive with
    #
    #   Can't add file /repo/setup/windows/WindowsSoftware.ps1 to tar: archive/tar: missed
    #   writing 3635782 bytes
    #   error during connect: ... unexpected EOF
    #
    # and because nothing looked at that, the script carried on, launched a playbook against a
    # /work that did not exist, and left the container sitting idle. The queue would then have
    # waited out the scenario's whole timeout for a playbook.rc that was never coming. A copy
    # that half happened is the worst case, because the tree looks plausible and the run fails
    # somewhere unrelated an hour later.
    info "Copying setup/ into the container"
    local copy_failed=""
    # Retried, because the observed failure was transient. The repository reaches the queue
    # container over a drvfs bind mount, and under the load of three parallel scenarios that mount
    # stumbles: the same interop layer answers Wsl/Service/0x8007274c to unrelated calls at the
    # same moment. A stumble costs one archive, not the scenario, so long as something notices.
    # /work-setup is removed between attempts, because a partial archive left behind would make
    # the retry look like it succeeded.
    local attempt
    for attempt in 1 2 3; do
        copy_failed=""
        docker cp "${REPO_ROOT}/setup" "${CONTAINER}:/work-setup" >/dev/null 2>"${RUN_DIR}/copy.log" && break
        copy_failed="docker cp of setup/"
        warn "copying setup/ failed on attempt ${attempt} of 3, retrying"
        docker exec "${CONTAINER}" rm -rf /work-setup &>/dev/null || true
        sleep 10
    done
    if [[ -z "${copy_failed}" ]]; then
        docker exec "${CONTAINER}" bash -c "mkdir -p /work && mv /work-setup /work/setup && chown -R ${E2E_USER}:${E2E_USER} /work" \
            >>"${RUN_DIR}/copy.log" 2>&1 || copy_failed="moving setup/ into place"
    fi
    if [[ -z "${copy_failed}" ]]; then
        docker cp "${EFFECTIVE_VARS}" "${CONTAINER}:/work/effective-vars.yaml" >/dev/null 2>>"${RUN_DIR}/copy.log" || copy_failed="docker cp of effective-vars.yaml"
    fi
    if [[ -z "${copy_failed}" ]]; then
        docker cp "${TIER3_DIR}/verify.yaml" "${CONTAINER}:/work/verify.yaml" >/dev/null 2>>"${RUN_DIR}/copy.log" || copy_failed="docker cp of verify.yaml"
    fi
    if [[ -z "${copy_failed}" ]]; then
        docker exec "${CONTAINER}" chown "${E2E_USER}:${E2E_USER}" /work/effective-vars.yaml /work/verify.yaml \
            >>"${RUN_DIR}/copy.log" 2>&1 || copy_failed="chown of the copied files"
    fi

    # Assert what has to be there, because an exit code says the transfer returned, not that the
    # files arrived. site.yaml is what the playbook is, all.yaml is where every toggle lives, and
    # the file count catches a partial archive that happened to include both.
    if [[ -z "${copy_failed}" ]]; then
        local n_copied
        n_copied="$(docker exec "${CONTAINER}" bash -c \
            'test -f /work/setup/ansible/site.yaml && test -f /work/setup/ansible/group_vars/all.yaml && find /work/setup -type f | wc -l' 2>/dev/null || echo 0)"
        if [[ "${n_copied:-0}" -lt 100 ]]; then
            copy_failed="the copied tree is incomplete, ${n_copied:-0} files under /work/setup"
        else
            dim "${n_copied} files copied"
        fi
    fi

    if [[ -n "${copy_failed}" ]]; then
        docker rm -f "${CONTAINER}" &>/dev/null || true
        {
            echo "scenario:    ${SCENARIO_NAME}"
            echo "failed at:   ${copy_failed}"
            echo "why it matters: the playbook never started, so this run proves nothing. Rerun it."
            echo "detail:"
            sed 's/^/  /' "${RUN_DIR}/copy.log" 2>/dev/null | tail -20
        } | tee "${RUN_DIR}/result.txt"
        exit 1
    fi

    info "Installing Ansible collections"
    docker exec -u "${E2E_USER}" -w /work/setup/ansible "${CONTAINER}" \
        ansible-galaxy collection install -r requirements.yaml >"${RUN_DIR}/galaxy.log" 2>&1 \
        || warn "collection install failed, see ${RUN_DIR}/galaxy.log"

    # --- launch, detached inside the container --------------------------------
    local profile_arg=""
    [[ -n "${SCENARIO_PROFILE}" ]] && profile_arg="-e @profiles/${SCENARIO_PROFILE}.yaml"

    info "Launching the playbook inside the container"
    dim "ansible-playbook site.yaml -i localhost, -c local ${profile_arg} -e @/work/effective-vars.yaml"
    docker exec -d -u "${E2E_USER}" -w /work/setup/ansible \
        -e ANSIBLE_FORCE_COLOR=0 \
        "${CONTAINER}" bash -c "ansible-playbook site.yaml -i 'localhost,' -c local ${profile_arg} -e @/work/effective-vars.yaml > /work/playbook.log 2>&1; echo \$? > /work/playbook.rc"

    # Everything --collect needs, so it does not have to re-derive any of it. Values
    # are quoted because the description contains spaces and hyphens, and an unquoted
    # assignment makes `source` try to execute the second word as a command.
    cat > "${RUN_DIR}/meta.env" <<EOF
CONTAINER="${CONTAINER}"
OS="${OS}"
SCENARIO_PROFILE="${SCENARIO_PROFILE}"
SCENARIO_NAME="${SCENARIO_NAME}"
SCENARIO_DESC="${SCENARIO_DESC}"
TIMEOUT_MIN="${TIMEOUT_MIN}"
RUN_ID="${RUN_ID}"
STARTED_AT="$(timestamp)"
EOF
}

# ---------------------------------------------------------------------------
# Wait, verify, collect
# ---------------------------------------------------------------------------
wait_for_playbook() {
    local deadline=$(( $(date +%s) + TIMEOUT_MIN * 60 ))
    info "Waiting for the playbook (timeout ${TIMEOUT_MIN} minutes)"
    while true; do
        if docker exec "${CONTAINER}" test -f /work/playbook.rc 2>/dev/null; then
            return 0
        fi
        if ! docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null | grep -q true; then
            warn "the container stopped before the playbook finished"
            return 1
        fi
        if [[ $(date +%s) -gt ${deadline} ]]; then
            warn "the playbook hit the ${TIMEOUT_MIN} minute timeout"
            return 1
        fi
        sleep 15
    done
}

collect_and_verify() {
    PLAYBOOK_LOG="${RUN_DIR}/playbook.log"
    VERIFY_LOG="${RUN_DIR}/verify.log"
    RESULT_FILE="${RUN_DIR}/result.txt"

    docker cp "${CONTAINER}:/work/playbook.log" "${PLAYBOOK_LOG}" &>/dev/null || echo "(no playbook log)" > "${PLAYBOOK_LOG}"
    PLAYBOOK_RC="$(docker exec "${CONTAINER}" cat /work/playbook.rc 2>/dev/null || echo "timeout-or-killed")"
    info "Playbook exit code: ${PLAYBOOK_RC}"

    # Runs regardless of the playbook's exit code. A failed run still has state worth
    # asserting on, and knowing which parts survived is how a failure gets triaged.
    # Verification must receive exactly what the playbook received, profile included, and in
    # the same order so precedence matches. Without the profile it asserted the un-profiled
    # software set and reported dozens of packages missing on the live-profile scenario, which
    # were absent precisely because that profile turns them off. A harness that fails a run for
    # doing what it was told is worse than no harness.
    local verify_args=(/work/verify.yaml -i "localhost," -c local)
    [[ -n "${SCENARIO_PROFILE:-}" ]] && verify_args+=(-e "@profiles/${SCENARIO_PROFILE}.yaml")
    verify_args+=(-e "@/work/effective-vars.yaml")

    info "Running verification${SCENARIO_PROFILE:+ (with profile ${SCENARIO_PROFILE})}"
    set +e
    docker exec -u "${E2E_USER}" -w /work/setup/ansible \
        -e ANSIBLE_FORCE_COLOR=0 \
        "${CONTAINER}" ansible-playbook "${verify_args[@]}" >"${VERIFY_LOG}" 2>&1
    VERIFY_RC=$?
    set -e
    info "Verify exit code: ${VERIFY_RC}"

    {
        echo "scenario:      ${SCENARIO_NAME}"
        echo "description:   ${SCENARIO_DESC}"
        echo "run_id:        ${RUN_ID}"
        echo "playbook_rc:   ${PLAYBOOK_RC}"
        echo "verify_rc:     ${VERIFY_RC}"
        # ansible.cfg sets stdout_callback = dual_logger, so the output is NOT the
        # default format. The recap reads "localhost: ok=65 changed=29 ..." with no
        # column padding, failures are listed under a "FAILED (n)" banner rather than
        # on fatal: lines, and every line carries a leading timestamp. Parsing the
        # default format here produced "errors_and_failures: none found" beside a
        # non-zero exit code, which reads as a pass and is exactly the kind of
        # misleading output this harness exists to prevent.
        echo "playbook_recap:"
        local recap
        recap="$(grep -oE 'localhost: ok=[0-9]+.*$' "${PLAYBOOK_LOG}" | tail -1 || true)"
        [[ -n "${recap}" ]] && echo "  ${recap}" || echo "  (no recap line, the run did not reach the end)"

        echo "wall_time:"
        grep -oE 'PLAY RECAP — wall time.*$' "${PLAYBOOK_LOG}" | tail -1 | sed 's/^/  /' || echo "  (unknown)"

        echo "installed:"
        sed -n '/═══ INSTALLED/,/^.*═══ [A-Z]*[^I]/p' "${PLAYBOOK_LOG}" \
            | sed -E 's/^\[[0-9:]+\] //' | grep -vE '═══|^\s*$' | head -20 | sed 's/^/  /' || echo "  (none)"

        echo "failures:"
        # Everything under the FAILED banner, timestamps stripped. Reported as an
        # explicit "no FAILED section" rather than a bare "none", because a parse error
        # aborts before any task runs and produces no banner at all.
        local fails
        fails="$(sed -n '/═══ FAILED/,$p' "${PLAYBOOK_LOG}" | sed -E 's/^\[[0-9:]+\] //' \
            | grep -vE '^Playbook finished|^\s*$' | head -40 || true)"
        [[ -n "${fails}" ]] && sed 's/^/  /' <<<"${fails}" \
            || echo "  no FAILED section in the log. If the exit code is non-zero the run died before the recap, read the log directly."

        echo "verify_failures:"
        local vfails
        vfails="$(sed -n '/═══ FAILED/,$p' "${VERIFY_LOG}" 2>/dev/null | sed -E 's/^\[[0-9:]+\] //' \
            | grep -vE '^Playbook finished|^\s*$' | head -20 || true)"
        [[ -n "${vfails}" ]] && sed 's/^/  /' <<<"${vfails}" || echo "  none"

        echo "verify_recap:"
        grep -oE 'localhost: ok=[0-9]+.*$' "${VERIFY_LOG}" 2>/dev/null | tail -1 | sed 's/^/  /' || echo "  (none)"
    } > "${RESULT_FILE}"

    cat "${RESULT_FILE}"

    if [[ "${PLAYBOOK_RC}" == "0" ]]; then
        pass "${SCENARIO_NAME}: playbook completed"
    else
        fail "${SCENARIO_NAME}: playbook exited ${PLAYBOOK_RC}" "see ${PLAYBOOK_LOG}"
    fi
    if [[ ${VERIFY_RC} -eq 0 ]]; then
        pass "${SCENARIO_NAME}: verification passed"
    else
        fail "${SCENARIO_NAME}: verification failed" "see ${VERIFY_LOG}"
    fi
}

teardown() {
    docker rm -f "${CONTAINER}" &>/dev/null || true
}

# ---------------------------------------------------------------------------
case "${MODE}" in
    detach)
        start_run
        echo
        info "Detached. The container keeps running with nothing attached to it."
        info "Collect the result with:"
        echo "  ./e2e/tier3/container.sh --collect ${RUN_DIR}"
        info "Watch progress with:"
        echo "  docker exec ${CONTAINER} tail -f /work/playbook.log"
        # Machine-readable last line, so the parallel scheduler in run.sh can pick the
        # run directory up without parsing prose that may change.
        echo "E2E_RUN_DIR=${RUN_DIR}"
        exit 0
        ;;
    wait)
        start_run
        wait_for_playbook || true
        collect_and_verify
        teardown
        finish "tier 3 / ${SCENARIO_NAME}"
        ;;
    collect)
        # shellcheck disable=SC1091
        source "${RUN_DIR}/meta.env"
        info "Collecting ${SCENARIO_NAME} from ${CONTAINER}"
        if ! docker inspect "${CONTAINER}" &>/dev/null; then
            echo "ERROR: container ${CONTAINER} no longer exists, nothing to collect" >&2
            exit 2
        fi
        if ! docker exec "${CONTAINER}" test -f /work/playbook.rc 2>/dev/null; then
            warn "the playbook is still running. Current task:"
            docker exec "${CONTAINER}" bash -c "grep -E '^\[[0-9:]+\] TASK' /work/playbook.log | tail -1" 2>/dev/null || true
            info "Rerun --collect when it has finished, or watch it with:"
            echo "  docker exec ${CONTAINER} tail -f /work/playbook.log"
            exit 3
        fi
        collect_and_verify
        teardown
        finish "tier 3 / ${SCENARIO_NAME}"
        ;;
esac
