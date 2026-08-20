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
# Two scenario keys change what this script does rather than what the playbook installs, and both
# are read out of the scenario file below:
#
#   e2e_run_twice: true       run the same command a second time once the first pass exits 0, and
#                             assert the second pass reports no changed task that is not named, with
#                             a reason, in idempotent_changes_allowed.txt beside this file.
#   e2e_expect_failure: true  the scenario breaks the run on purpose, so the verdicts invert: a
#                             non-zero exit code is the pass, and the failure has to be named in the
#                             terminal summary, in the error log the run writes, and by the
#                             verification, which must refuse rather than report a clean machine.
#
# The playbook always runs detached INSIDE the container, writing its own log and exit
# code there, and this script only watches it. That matters for the long scenarios: a
# full software run takes hours, and tying it to the lifetime of whatever shell started
# it means an ordinary disconnect throws the whole run away. With --detach the container
# keeps working with nothing attached, and --collect finishes the job later from any
# shell.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_docker_host

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

# Tasks allowed to report changed on a second pass, each with the reason it cannot be repeatable.
# Read only by the e2e_run_twice path below. It sits here rather than under tier1/ because tier 1
# never runs a playbook and so can never consult it, and next to container_limits.yaml because the
# two files answer the same shape of question: what this tier deliberately does not hold the
# playbook to, stated in one place instead of being argued about per run.
IDEMPOTENCY_ALLOWLIST="${TIER3_DIR}/idempotent_changes_allowed.txt"

# Every task name the log says reported changed, in log order, one per line.
#
# ansible.cfg sets stdout_callback = dual_logger, so this reads that format and not Ansible's own: a
# task header is "[HH:MM:SS] TASK [role : name]" and its result is "[HH:MM:SS] 1.2s CHANGED:
# [localhost]". Only the task-level line ever says CHANGED, because the per-item hook renders
# INSTALLED, present, absent or TOLERATED instead, so this counts tasks and never loop items. A task
# header with no result line at all is a task that was skipped, and the pending name is simply
# replaced by the next header rather than being attributed to it.
changed_task_names() {
    awk '
        /TASK \[/     { task = $0; sub(/^.*TASK \[/, "", task); sub(/\]$/, "", task); next }
        /CHANGED: \[/ { if (task != "") { print task; task = "" } }
    ' "$1"
}

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
    SCENARIO_RUN_TWICE="$(scenario_get e2e_run_twice)"
    SCENARIO_EXPECT_FAILURE="$(scenario_get e2e_expect_failure)"
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
    #
    # A scenario key that a limits file will also set is dropped here rather than written twice.
    # Emitting both worked, because a duplicate mapping key resolves to the last one and the limits
    # come last, but it made Ansible print `[WARNING]: Found duplicate mapping key
    # 'install_openrazer'` on every Fedora run, and leaning on duplicate-key resolution is leaning
    # on parser behaviour that YAML itself calls an error. The generated block below already had
    # this guard and the scenario's own keys did not.
    #
    # The key pattern allows digits, matching the toggle pattern in the generated block below. A
    # limits key is a toggle name and toggle names are allowed to carry a digit, so the earlier
    # `[a-z_]+` would have read past a key like install_kde5 without seeing it and the dedupe would
    # have silently stopped working for that one key alone. No limits file carries such a key today,
    # which is exactly why the two patterns were allowed to drift apart.
    limits_keys="$(grep -hE '^[a-z0-9_]+:' "${LIMITS_FILES[@]}" | cut -d: -f1 | sort -u)"
    {
        echo "---"
        echo "# Generated by container.sh for scenario ${SCENARIO_NAME}. Do not edit."
        echo "# This is the exact -e input the playbook received."
        grep -vE '^(---|e2e_generate_except:|[[:space:]]*-[[:space:]])' "${SCENARIO_FILE}" \
            | grep -vE '^\s*$' \
            | while IFS= read -r line; do
                  key="${line%%:*}"
                  if grep -qx -- "${key}" <<<"${limits_keys}"; then
                      echo "# ${line}    <- overridden by a container limit below"
                  else
                      printf '%s\n' "${line}"
                  fi
              done || true
    } > "${EFFECTIVE_VARS}"

    if [[ -n "${SCENARIO_GENERATE}" ]]; then
        # Collected from the two files the wizard itself reads, so a newly added toggle
        # is picked up with no edit here. A hand-maintained copy would quietly stop
        # covering new software, which is the silent gap this suite exists to catch.
        # The wizard's EXCLUDED_VARS list is read out of setup.sh rather than restated,
        # because those keys are system settings rather than software and must not be swept
        # into a generated software set. install_system_core is the one that mattered: the
        # smoke scenario, since removed, generated it as false, which disabled the entire
        # system_core role, so that scenario silently skipped the bootstrap and reported a
        # pass over far less than it appeared to cover. Exactly the kind of hole this suite
        # exists to close, in the suite itself.
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
    # Digits allowed here for the same reason as the dedupe pattern above. This list is the only
    # place a run states what it does not cover, so a suppressed toggle whose name carries a digit
    # would be turned off and never named, which is the silent gap the warning exists to prevent.
    grep -hE '^[a-z0-9_]+: false$' "${LIMITS_FILES[@]}" | sed 's/^/       /' || true

    # --- container ------------------------------------------------------------
    info "Building the ${OS} base image (cached after the first run)"
    # Both the Dockerfile and the build context name a location on this machine, so both go
    # through host_path. The mounts and working directories further down do not, because those
    # name locations inside the container.
    docker build -q -f "$(host_path "${DOCKERFILE}")" -t "${IMAGE}" "$(host_path "${TIER3_DIR}")" >/dev/null

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

    # One exit for every way the start phase can fail before the playbook is running. Written once
    # because there are two callers, the copy steps and the launch below, and a second hand-written
    # copy of it would be free to forget the `docker rm -f`. That removal is the part that matters:
    # the run whose copy failed unnoticed left a container sitting idle with nothing working inside
    # it, which reads to anyone looking at `docker ps` as a scenario still in progress.
    abort_before_playbook() {
        local what="$1"
        local detail_log="$2"
        docker rm -f "${CONTAINER}" &>/dev/null || true
        {
            echo "scenario:    ${SCENARIO_NAME}"
            echo "failed at:   ${what}"
            echo "why it matters: the playbook never started, so this run proves nothing. Rerun it."
            echo "detail:"
            sed 's/^/  /' "${detail_log}" 2>/dev/null | tail -20
        } | tee "${RUN_DIR}/result.txt"
        exit 1
    }

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
    #
    # Each attempt appends to copy.log and announces itself first, so three failures read as three
    # failures. Redirecting with a single `>` truncated the log on every attempt, which meant a
    # scenario that stumbled twice and then succeeded left a log holding only the successful
    # attempt's empty stderr, and one that failed all three left only the last message with nothing
    # to say the earlier two had the same cause or a different one. Every other step in this block
    # already appends.
    local attempt
    for attempt in 1 2 3; do
        copy_failed=""
        echo "=== attempt ${attempt} of 3: docker cp of setup/ ===" >>"${RUN_DIR}/copy.log"
        docker cp "$(host_path "${REPO_ROOT}/setup")" "${CONTAINER}:/work-setup" >/dev/null 2>>"${RUN_DIR}/copy.log" && break
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
        docker cp "$(host_path "${EFFECTIVE_VARS}")" "${CONTAINER}:/work/effective-vars.yaml" >/dev/null 2>>"${RUN_DIR}/copy.log" || copy_failed="docker cp of effective-vars.yaml"
    fi
    if [[ -z "${copy_failed}" ]]; then
        docker cp "$(host_path "${TIER3_DIR}/verify.yaml")" "${CONTAINER}:/work/verify.yaml" >/dev/null 2>>"${RUN_DIR}/copy.log" || copy_failed="docker cp of verify.yaml"
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
        abort_before_playbook "${copy_failed}" "${RUN_DIR}/copy.log"
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

    # One command string, run once or twice.
    #
    # The second pass is the whole of the idempotency scenario. playbook.rc is written last, after
    # whichever pass was the final one, and that is deliberate rather than incidental:
    # wait_for_playbook and the --collect readiness probe both decide "this run is over" by the
    # existence of that one file, so writing it at the end makes both of them cover both passes with
    # no change to either, and the scenario's own timeout budgets the pair. The first pass keeps its
    # own exit code, captured into rc1 before anything else can overwrite $?.
    #
    # The second pass only runs when the first one exited 0. A first pass that failed leaves nothing
    # to say about idempotency, and collect_and_verify reports that as a failed scenario rather than
    # reading an absent playbook2.rc as "the second pass changed nothing".
    #
    # The error log is copied out while it still belongs to the pass that wrote it.
    # callback_plugins/dual_logger.py opens installation_errors.log with mode "w", so a second pass
    # truncates the first pass's copy, and the forced-failure scenario asserts on that file by name.
    # The tilde form resolves the home directory through the passwd database, which is what the
    # callback plugin itself does, rather than through HOME, which docker exec -u does not set.
    local play_cmd="ansible-playbook site.yaml -i 'localhost,' -c local ${profile_arg} -e @/work/effective-vars.yaml"
    local launch_script="${play_cmd} > /work/playbook.log 2>&1; rc1=\$?"
    launch_script+="; cp -f ~${E2E_USER}/installation_errors.log /work/installation_errors.log 2>/dev/null || true"
    if [[ "${SCENARIO_RUN_TWICE}" == "true" ]]; then
        info "This scenario runs the playbook twice, and the second pass must change nothing"
        launch_script+="; if [ \"\${rc1}\" -eq 0 ]; then ${play_cmd} > /work/playbook2.log 2>&1"
        launch_script+="; echo \$? > /work/playbook2.rc"
        launch_script+="; cp -f ~${E2E_USER}/installation_errors.log /work/installation_errors2.log 2>/dev/null || true; fi"
    fi
    launch_script+="; echo \"\${rc1}\" > /work/playbook.rc"
    # Checked, not inferred. This was the last step in the start phase whose result nothing looked
    # at, and it is the one step where an unnoticed failure is worst: `docker exec -d` returns
    # non-zero when the exec cannot be created at all, and under set -e that killed start_run on the
    # spot, before meta.env was written. What that leaves behind is a container still running with no
    # playbook in it and a run directory that --collect refuses, because meta.env is the only place
    # the container name is recorded. So the failure is routed through the same reporting path the
    # copy steps use: the container goes, and result.txt says in words that the run proves nothing.
    if ! docker exec -d -u "${E2E_USER}" -w /work/setup/ansible \
        -e ANSIBLE_FORCE_COLOR=0 \
        "${CONTAINER}" bash -c "${launch_script}" \
        >/dev/null 2>"${RUN_DIR}/launch.log"; then
        abort_before_playbook "launching the playbook, docker exec -d would not start it" "${RUN_DIR}/launch.log"
    fi

    # Everything --collect needs, so it does not have to re-derive any of it. Values
    # are quoted because the description contains spaces and hyphens, and an unquoted
    # assignment makes `source` try to execute the second word as a command.
    cat > "${RUN_DIR}/meta.env" <<EOF
CONTAINER="${CONTAINER}"
OS="${OS}"
SCENARIO_PROFILE="${SCENARIO_PROFILE}"
SCENARIO_NAME="${SCENARIO_NAME}"
SCENARIO_DESC="${SCENARIO_DESC}"
SCENARIO_RUN_TWICE="${SCENARIO_RUN_TWICE}"
SCENARIO_EXPECT_FAILURE="${SCENARIO_EXPECT_FAILURE}"
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

    SECOND_LOG="${RUN_DIR}/playbook2.log"
    ERRORS_LOG="${RUN_DIR}/installation_errors.log"

    docker cp "${CONTAINER}:/work/playbook.log" "$(host_path "${PLAYBOOK_LOG}")" &>/dev/null || echo "(no playbook log)" > "${PLAYBOOK_LOG}"
    PLAYBOOK_RC="$(docker exec "${CONTAINER}" cat /work/playbook.rc 2>/dev/null || echo "timeout-or-killed")"
    info "Playbook exit code: ${PLAYBOOK_RC}"

    # The error log the run writes for a person to read afterwards, kept with the run rather than
    # left inside a container that is about to be removed. Collected for every scenario, not only the
    # one that asserts on it: it is four lines on a failed run and empty on a clean one, and the run
    # record is the only place a failure can still be read once the container is gone.
    docker cp "${CONTAINER}:/work/installation_errors.log" "$(host_path "${ERRORS_LOG}")" &>/dev/null \
        || echo "(no installation_errors.log was copied out of the container)" > "${ERRORS_LOG}"

    # --- the second pass, for a scenario that asked for one ----------------------
    # Parsed here rather than inside the container, because the log is already on this side and the
    # allowlist lives in the working tree, which the container deliberately cannot see.
    SECOND_RC="not-requested"
    SECOND_CHANGED=()
    SECOND_EXCUSED=()
    SECOND_UNEXPECTED=()
    if [[ "${SCENARIO_RUN_TWICE:-}" == "true" ]]; then
        docker cp "${CONTAINER}:/work/playbook2.log" "$(host_path "${SECOND_LOG}")" &>/dev/null \
            || echo "(no second playbook log, so the second pass never started)" > "${SECOND_LOG}"
        SECOND_RC="$(docker exec "${CONTAINER}" cat /work/playbook2.rc 2>/dev/null || echo "never-ran")"
        info "Second pass exit code: ${SECOND_RC}"

        mapfile -t SECOND_CHANGED < <(changed_task_names "${SECOND_LOG}")

        # The allowlist holds "<task name> | <reason>", so the reason travels with the exception
        # instead of living in a commit message nobody reads. An entry with no reason is rejected
        # rather than honoured: an unexplained exception is how an allowlist becomes a place to hide
        # a defect, which is the one thing this scenario cannot afford.
        local allow_names=() allow_line name
        if [[ -f "${IDEMPOTENCY_ALLOWLIST}" ]]; then
            while IFS= read -r allow_line; do
                [[ "${allow_line}" =~ ^[[:space:]]*(#|$) ]] && continue
                if [[ "${allow_line}" != *"|"* ]]; then
                    warn "ignoring an allowlist line with no reason after the pipe: ${allow_line}"
                    continue
                fi
                name="${allow_line%%|*}"
                name="$(sed -E 's/[[:space:]]+$//' <<<"${name}")"
                [[ -n "${name}" ]] && allow_names+=("${name}")
            done < "${IDEMPOTENCY_ALLOWLIST}"
        else
            warn "no allowlist at ${IDEMPOTENCY_ALLOWLIST}, so every changed task counts against the run"
        fi

        local t
        for t in "${SECOND_CHANGED[@]+"${SECOND_CHANGED[@]}"}"; do
            if printf '%s\n' "${allow_names[@]+"${allow_names[@]}"}" | grep -qxF -- "${t}"; then
                SECOND_EXCUSED+=("${t}")
            else
                SECOND_UNEXPECTED+=("${t}")
            fi
        done
    fi

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
        # Same three-way report as the playbook side above, and for the same reason. The verify play
        # can die before it reaches any assertion, on a parse error or an undefined variable in a
        # pre_task, and then it emits no FAILED banner at all. Printing a bare "none" there made a
        # crashed verification identical in result.txt to a clean one, which is the misleading output
        # this harness exists to prevent, so a non-zero exit code with no banner is said out loud.
        local vfails
        vfails="$(sed -n '/═══ FAILED/,$p' "${VERIFY_LOG}" 2>/dev/null | sed -E 's/^\[[0-9:]+\] //' \
            | grep -vE '^Playbook finished|^\s*$' | head -20 || true)"
        if [[ -n "${vfails}" ]]; then
            sed 's/^/  /' <<<"${vfails}"
        elif [[ ${VERIFY_RC} -ne 0 ]]; then
            echo "  no FAILED section in the verify log although it exited ${VERIFY_RC}, so the verification died before the recap. Read the log directly."
        else
            echo "  none"
        fi

        echo "verify_recap:"
        grep -oE 'localhost: ok=[0-9]+.*$' "${VERIFY_LOG}" 2>/dev/null | tail -1 | sed 's/^/  /' || echo "  (none)"

        # The second pass, named task by task rather than reduced to a count. A count says a run is
        # not idempotent and a list says which task to go and look at, and the list is the reason
        # this scenario exists: the tasks it names are either doing their work twice or misreporting
        # it, and neither is visible from anywhere else in this harness.
        if [[ "${SCENARIO_RUN_TWICE:-}" == "true" ]]; then
            echo "second_run_rc:  ${SECOND_RC}"
            echo "second_run_recap:"
            grep -oE 'localhost: ok=[0-9]+.*$' "${SECOND_LOG}" 2>/dev/null | tail -1 | sed 's/^/  /' || echo "  (none)"
            echo "second_run_changed_total: ${#SECOND_CHANGED[@]}"
            echo "second_run_changed_not_allowed: ${#SECOND_UNEXPECTED[@]}"
            if [[ ${#SECOND_UNEXPECTED[@]} -gt 0 ]]; then
                printf '  %s\n' "${SECOND_UNEXPECTED[@]}"
            else
                echo "  none"
            fi
            echo "second_run_changed_allowed: ${#SECOND_EXCUSED[@]}"
            if [[ ${#SECOND_EXCUSED[@]} -gt 0 ]]; then
                printf '  %s\n' "${SECOND_EXCUSED[@]}"
            else
                echo "  none"
            fi
        fi
    } > "${RESULT_FILE}"

    cat "${RESULT_FILE}"

    if [[ "${SCENARIO_EXPECT_FAILURE:-}" == "true" ]]; then
        # Every verdict inverts, because this scenario broke the run on purpose. A clean exit here is
        # the defect: it means the machinery that makes a failure visible swallowed one instead. The
        # four checks are the four places a failure has to appear, and they are separate on purpose,
        # because each has failed on its own before: an exit code without a summary, a summary
        # without an error log entry, and a verification that reported a pass over a broken machine.
        if [[ "${PLAYBOOK_RC}" != "0" ]]; then
            pass "${SCENARIO_NAME}: the playbook exited ${PLAYBOOK_RC}, so the failure reached the exit code"
        else
            fail "${SCENARIO_NAME}: the playbook exited 0 although the run was made to fail" \
                 "the failure was swallowed somewhere between the failing task and the exit code, see ${PLAYBOOK_LOG}"
        fi

        # The terminal summary, which is what a person watching the console reads. dual_logger prints
        # one "═══ FAILED (n) ═══" banner with one bullet per failing task.
        local named_task
        named_task="$(sed -n '/═══ FAILED (/,$p' "${PLAYBOOK_LOG}" | sed -E 's/^\[[0-9:]+\] //' \
            | grep -m1 '^  • ' | sed -E 's/^  • //' || true)"
        if [[ -n "${named_task}" ]]; then
            pass "${SCENARIO_NAME}: the terminal summary names a failing task"
            dim "first named: ${named_task}"
        else
            fail "${SCENARIO_NAME}: the terminal summary names no failing task" \
                 "expected a '═══ FAILED (n) ═══' section with one bullet per task in ${PLAYBOOK_LOG}"
        fi

        # And the same task, by name, in the error log. Matching the name is what makes this more
        # than a file-exists check: a log holding something unrelated would pass that and prove
        # nothing about whether this failure was recorded.
        if [[ -n "${named_task}" ]] && grep -qF -- "${named_task}" "${ERRORS_LOG}"; then
            pass "${SCENARIO_NAME}: the error log names the same failing task"
        else
            fail "${SCENARIO_NAME}: the error log does not name the failing task" \
                 "expected '${named_task:-the failing task}' in ${ERRORS_LOG}"
        fi

        # The verification has to refuse, and it has to say what is missing rather than only that
        # something is. This is the assertion that a run which installed nothing cannot pass.
        if [[ ${VERIFY_RC} -ne 0 ]] && grep -q 'FAIL native packages missing:' "${VERIFY_LOG}"; then
            pass "${SCENARIO_NAME}: verification refused and named the missing packages"
        else
            fail "${SCENARIO_NAME}: verification did not refuse over a machine the run failed to build" \
                 "expected a non-zero exit code and a 'FAIL native packages missing:' line, got exit ${VERIFY_RC}, see ${VERIFY_LOG}"
        fi
    else
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
    fi

    if [[ "${SCENARIO_RUN_TWICE:-}" == "true" ]]; then
        if [[ "${SECOND_RC}" != "0" ]]; then
            fail "${SCENARIO_NAME}: the second pass did not finish cleanly, exit ${SECOND_RC}" \
                 "a second pass that never ran or did not exit 0 says nothing about idempotency, so this is a failed run rather than an unproven one, see ${SECOND_LOG}"
        elif [[ ${#SECOND_UNEXPECTED[@]} -eq 0 ]]; then
            pass "${SCENARIO_NAME}: the second pass changed nothing outside the allowlist, ${#SECOND_CHANGED[@]} changed task(s), all ${#SECOND_EXCUSED[@]} accounted for"
        else
            fail "${SCENARIO_NAME}: ${#SECOND_UNEXPECTED[@]} task(s) reported changed on a second pass with nothing left to do" \
                 "$(printf '%s; ' "${SECOND_UNEXPECTED[@]}")"
        fi
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
            # Which pass is running, and therefore which log to read the current task out of. A
            # two-pass scenario writes playbook.rc only after the second pass, so reading the first
            # pass's log throughout would have reported its last task as the current one for the
            # whole of the second pass, which reads as a stalled run.
            CURRENT_LOG=/work/playbook.log
            if docker exec "${CONTAINER}" test -f /work/playbook2.log 2>/dev/null; then
                CURRENT_LOG=/work/playbook2.log
                warn "the second pass is still running. Current task:"
            else
                warn "the playbook is still running. Current task:"
            fi
            docker exec "${CONTAINER}" bash -c "grep -E '^\[[0-9:]+\] TASK' ${CURRENT_LOG} | tail -1" 2>/dev/null || true
            info "Rerun --collect when it has finished, or watch it with:"
            echo "  docker exec ${CONTAINER} tail -f ${CURRENT_LOG}"
            exit 3
        fi
        collect_and_verify
        teardown
        finish "tier 3 / ${SCENARIO_NAME}"
        ;;
esac
