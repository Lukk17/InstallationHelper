#!/usr/bin/env bash
#
# Moves a harness entry point into the gate container. Sourced, never executed directly, by
# e2e/run.sh and e2e/tier3/container.sh before anything else they do.
#
# Inside the gate container gate_enter returns at once and the caller carries on. Anywhere else it
# builds e2e/gate/Dockerfile, starts the same script inside that image with the same arguments, and
# exits with that run's status, so nothing after the call ever runs on the machine that started it.
# The repository reaches the container read-only, the container works on its own copy, and the only
# thing it writes back is e2e/runs.

# shellcheck source=host.sh
source "$(dirname "${BASH_SOURCE[0]}")/host.sh"

E2E_GATE_IMAGE="installationhelper-e2e-gate:latest"
E2E_GATE_QUEUE_NAME="e2e-queue"

# gate_refuse_foreign_container  ->  returns on a real machine, exits 2 inside any other container
#
# A host path read from inside another container names nothing the daemon can mount, so starting the
# gate from there would hand it an empty repository.
gate_refuse_foreign_container() {
    [[ -f /.dockerenv || -f /run/.containerenv ]] || return 0
    cat >&2 <<EOF
REFUSED: this is a container, but not the gate container, so the harness cannot start from here.
Nothing was run. Start it from the machine that runs Docker instead:

    bash e2e/run.sh

For a run that has to outlive the terminal, the gate container itself is the queue:

    bash e2e/run.sh --queue --tier 3 --scenario all --jobs 3
EOF
    exit 2
}

# gate_build <repository root>  ->  builds the gate image, quietly when nothing changed
gate_build() {
    local repo_root="$1" log
    log="$(mktemp)"
    info_line "building the gate image ${E2E_GATE_IMAGE} from e2e/gate/Dockerfile (minutes the first time, cached after)"
    if ! docker build -q \
            -f "$(host_path "${repo_root}/e2e/gate/Dockerfile")" \
            --build-arg "GATE_UID=$(id -u)" --build-arg "GATE_GID=$(id -g)" \
            -t "${E2E_GATE_IMAGE}" "$(host_path "${repo_root}")" >"${log}" 2>&1; then
        echo "ERROR: the gate image did not build, so nothing was run. The build said:" >&2
        tail -30 "${log}" >&2
        rm -f "${log}"
        exit 2
    fi
    rm -f "${log}"
}

info_line() { printf '>> %s\n' "$*"; }

# gate_container_path <repository root> <argument>  ->  the argument, with a host path into the
# repository rewritten to the same place inside the container
gate_container_path() {
    local repo_root="$1" arg="$2"
    if [[ "${E2E_HOST_KIND}" == "windows-msys" && "${arg}" =~ ^[A-Za-z]:[\\/] ]]; then
        arg="$(cygpath -u "${arg}")"
    fi
    if [[ "${arg}" == "${repo_root}" ]]; then
        printf '%s\n' "${E2E_GATE_REPO}"
    elif [[ "${arg}" == "${repo_root}/"* ]]; then
        printf '%s\n' "${E2E_GATE_REPO}/${arg#"${repo_root}/"}"
    else
        printf '%s\n' "${arg}"
    fi
}

# gate_lend_github_token  ->  writes this machine's GitHub token to a private file the gate mounts
#
# Tier 2 reads winget manifests through gh when no winget can run, and the gate container has no gh
# login of its own. The token goes into a 0600 file that gate_enter mounts read-only, never into the
# container's environment settings or onto a command line, because `docker inspect` prints both to
# anybody who can reach the daemon. A GH_TOKEN or GITHUB_TOKEN already exported here wins over the gh
# login. Called only for a tier that reads GitHub, so the other tiers never hold it.
gate_lend_github_token() {
    e2e_inside_gate && return 0
    local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    if [[ -z "${token}" ]] && command -v gh &>/dev/null; then
        token="$(gh auth token 2>/dev/null || true)"
    fi
    [[ -n "${token}" ]] || return 0
    E2E_GATE_TOKEN_HOST_FILE="$(umask 077 && mktemp)"
    trap gate_forget_github_token EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    printf '%s' "${token}" >"${E2E_GATE_TOKEN_HOST_FILE}"
}

# gate_forget_github_token  ->  deletes the host copy of the lent token, when there is one
gate_forget_github_token() {
    [[ -n "${E2E_GATE_TOKEN_HOST_FILE:-}" ]] || return 0
    rm -f "${E2E_GATE_TOKEN_HOST_FILE}"
    E2E_GATE_TOKEN_HOST_FILE=""
}

# gate_await_token_read <seconds> <queue log>  ->  returns once the queued container has read the lent
# token, has stopped, or the time is up, whichever comes first. The entry point writes
# E2E_GATE_TOKEN_READ_LINE to the queue log right after it reads the file.
gate_await_token_read() {
    local deadline=$((SECONDS + $1)) log="$2"
    while ((SECONDS < deadline)); do
        grep -qxF "${E2E_GATE_TOKEN_READ_LINE}" "${log}" 2>/dev/null && return 0
        [[ "$(docker inspect -f '{{.State.Running}}' "${E2E_GATE_QUEUE_NAME}" 2>/dev/null)" == true ]] || return 0
        sleep 1
    done
    echo "WARNING: the queued container did not report reading the GitHub token within $1 seconds, so the host copy is deleted now and tier 2 may report the winget assertions as SKIP" >&2
}

# gate_enter <queue|wait> <repository-relative script> <argument>...
#
# queue starts the run detached in a container named e2e-queue, writing everything to
# e2e/runs/queue.log and ending that file with QUEUE_EXIT=<status>. wait runs it in the foreground.
gate_enter() {
    e2e_inside_gate && return 0

    local mode="$1" script="$2"
    shift 2

    gate_refuse_foreign_container
    require_docker_host

    local repo_root
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    gate_build "${repo_root}"
    mkdir -p "${repo_root}/e2e/runs"

    local cwd_rel=""
    if [[ "${PWD}" == "${repo_root}/"* ]]; then
        cwd_rel="${PWD#"${repo_root}/"}"
    fi

    local args=() arg
    for arg in "$@"; do
        args+=("$(gate_container_path "${repo_root}" "${arg}")")
    done

    local run_opts=(
        --init
        -v "$(host_path "${repo_root}"):/source:ro"
        -v "$(host_path "${repo_root}/e2e/runs"):${E2E_GATE_REPO}/e2e/runs"
        -e "E2E_GATE_CWD=${cwd_rel}"
        -e NO_COLOR
    )
    if [[ -n "${E2E_GATE_TOKEN_HOST_FILE:-}" ]]; then
        run_opts+=(-v "$(host_path "${E2E_GATE_TOKEN_HOST_FILE}"):${E2E_GATE_TOKEN_FILE}:ro")
    fi
    if [[ "${E2E_HOST_KIND}" == "windows-msys" || -S /var/run/docker.sock ]]; then
        run_opts+=(-v /var/run/docker.sock:/var/run/docker.sock)
    fi

    if [[ "${mode}" == queue ]]; then
        if [[ -n "$(docker ps -aq --filter "name=^/${E2E_GATE_QUEUE_NAME}$")" ]]; then
            echo "ERROR: a container named ${E2E_GATE_QUEUE_NAME} already exists. Read e2e/runs/queue.log, then remove it with: docker rm ${E2E_GATE_QUEUE_NAME}" >&2
            exit 2
        fi
        # Emptied here rather than by the container, because the container takes a moment to start
        # and a watcher reading the log in that moment would find the last run's QUEUE_EXIT line.
        : > "${repo_root}/e2e/runs/queue.log"
        if ! docker run -d --name "${E2E_GATE_QUEUE_NAME}" "${run_opts[@]}" \
                -e "E2E_GATE_LOG=${E2E_GATE_REPO}/e2e/runs/queue.log" \
                "${E2E_GATE_IMAGE}" "${script}" ${args[@]+"${args[@]}"} >/dev/null; then
            echo "ERROR: the queue container did not start, so nothing was queued" >&2
            exit 2
        fi
        if [[ -n "${E2E_GATE_TOKEN_HOST_FILE:-}" ]]; then
            gate_await_token_read 120 "${repo_root}/e2e/runs/queue.log"
            gate_forget_github_token
        fi
        info_line "queued in the detached container ${E2E_GATE_QUEUE_NAME}, writing e2e/runs/queue.log, which ends with QUEUE_EXIT=<status>"
        exit 0
    fi

    local rc=0
    docker run --rm "${run_opts[@]}" "${E2E_GATE_IMAGE}" "${script}" ${args[@]+"${args[@]}"} || rc=$?
    exit "${rc}"
}
