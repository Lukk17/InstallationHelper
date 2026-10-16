#!/usr/bin/env bash
#
# Entry point of the gate container. e2e/lib/gate.sh starts the container with the repository-relative
# path of a harness script and its arguments, and this runs that script against a private copy of the
# repository, as the unprivileged gate user, with the gate switch set.
#
# Mounts it expects, all made by e2e/lib/gate.sh:
#   /source                 the repository, read-only
#   /repo/e2e/runs          the host's e2e/runs, the only place a run writes back to
#   /var/run/docker.sock    the daemon, for tier 1's compose checks and tiers 2 and 3
#
# Environment it reads:
#   E2E_GATE_CWD   the caller's directory relative to the repository root, empty for the root
#   E2E_GATE_LOG   when set, the whole run goes to this file, followed by a QUEUE_EXIT=<status> line
#
# Exit codes: the script's own status, or 2 when the container was started without a script.

set -euo pipefail

# shellcheck source=../lib/host.sh
source "$(dirname "${BASH_SOURCE[0]}")/host.sh"

GATE_USER="gate"
GATE_SOURCE="/source"

# As root: give the gate user the socket's group, then drop to it for everything else.
if [[ "${EUID}" -eq 0 ]]; then
    if [[ -S /var/run/docker.sock ]]; then
        socket_gid="$(stat -c '%g' /var/run/docker.sock)"
        socket_group="$(getent group "${socket_gid}" | cut -d: -f1 || true)"
        if [[ -z "${socket_group}" ]]; then
            socket_group="docker-host"
            groupadd --gid "${socket_gid}" "${socket_group}"
        fi
        usermod --append --groups "${socket_group}" "${GATE_USER}"
    fi
    gate_home="$(getent passwd "${GATE_USER}" | cut -d: -f6)"
    exec setpriv --reuid="${GATE_USER}" --regid="$(id -g "${GATE_USER}")" --init-groups \
        env HOME="${gate_home}" USER="${GATE_USER}" LOGNAME="${GATE_USER}" bash "${BASH_SOURCE[0]}" "$@"
fi

if [[ $# -eq 0 ]]; then
    echo "ERROR: the gate container needs the repository-relative path of a harness script to run" >&2
    exit 2
fi
script="$1"
shift

# A queued run has nobody watching its terminal, so everything from here on goes to the log, and the
# log always ends with the status, whichever step it was that stopped.
if [[ -n "${E2E_GATE_LOG:-}" ]]; then
    exec >"${E2E_GATE_LOG}" 2>&1
    trap 'echo "QUEUE_EXIT=$?"' EXIT
fi

# A private, writable copy, so nothing a check writes can reach the repository on the host. The run
# directory is excluded because it is the bind mount that does reach the host, and the download
# cache because the image already carries every pinned tool it would hold.
tar -C "${GATE_SOURCE}" --exclude=./e2e/runs --exclude=./e2e/.cache -cf - . | tar -C "${E2E_GATE_REPO}" -xf -

cd "${E2E_GATE_REPO}/${E2E_GATE_CWD:-}"
export "${E2E_GATE_SWITCH}=1"

if [[ -z "${E2E_GATE_LOG:-}" ]]; then
    exec bash "${E2E_GATE_REPO}/${script}" "$@"
fi
bash "${E2E_GATE_REPO}/${script}" "$@"
