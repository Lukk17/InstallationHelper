#!/usr/bin/env bash
#
# The part of the harness that may run on the machine that starts it. Sourced, never executed
# directly, by lib/gate.sh on that machine and by lib/common.sh inside the gate container.
#
# Nothing here tests anything. It answers how this shell reaches a Docker daemon and how a host
# path has to be spelled for it, and it names the switch that says a process is inside the gate
# container, which is the only place any check is allowed to run.

# The gate container announces itself in two ways, and both have to be present. The variable is set
# by e2e/gate/entrypoint.sh for every process it starts, and the marker file is written into the
# image by e2e/gate/provision.sh while it is built. A shell that only exports the variable has no
# marker, and a machine that only has the file has no variable, so neither alone lets a check run.
# shellcheck disable=SC2034  # read by gate.sh, provision.sh and entrypoint.sh, which source this file
E2E_GATE_SWITCH="E2E_INSIDE_GATE_CONTAINER"
E2E_GATE_MARKER="/etc/installationhelper-e2e-gate"
# shellcheck disable=SC2034  # read by gate.sh and entrypoint.sh
E2E_GATE_REPO="/repo"
# Where gate.sh mounts a lent GitHub token, read-only, and the line the entry point prints once it has
# read it, which is what lets the launcher delete its host copy of a queued run's token.
# shellcheck disable=SC2034  # read by gate.sh and entrypoint.sh
E2E_GATE_TOKEN_FILE="/run/installationhelper-e2e-gate/gh_token"
# shellcheck disable=SC2034  # read by gate.sh and entrypoint.sh
E2E_GATE_TOKEN_READ_LINE=">> the gate read the lent GitHub token from its mounted file"

# e2e_inside_gate  ->  status 0 inside the gate container, 1 anywhere else
e2e_inside_gate() {
    [[ "${!E2E_GATE_SWITCH:-}" == 1 && -f "${E2E_GATE_MARKER}" ]]
}

# Which kind of shell this is, decided once. It is not a stand-in for the operating system: it
# answers the only question the harness cares about, which is how a host path has to be spelled
# before a Docker daemon will accept it. A Linux shell and Git Bash can both drive the daemon on
# this machine, they just spell that path differently.
E2E_HOST_KIND="other"
case "$(uname -s)" in
    Linux*)               E2E_HOST_KIND="linux" ;;
    MINGW*|MSYS*|CYGWIN*) E2E_HOST_KIND="windows-msys" ;;
esac

# Under MSYS every argument that looks like an absolute POSIX path is rewritten before a native
# Windows executable sees it, and for docker that is fatal in both directions. A container path is
# destroyed: `-v /sys/fs/cgroup:/sys/fs/cgroup:rw` becomes `mkdir C:\Program Files\Git\sys: Access
# is denied` and `-w /work/setup/ansible` becomes `Cwd must be an absolute path`. A host path is
# destroyed differently and worse, because `-v /tmp/x:/probe` mounts a directory that is not the one
# meant and reports no error at all.
#
# So the rewriting is turned off for every docker call the harness makes, and the host paths are
# spelled out explicitly through host_path below. One wrapper rather than the same environment
# variable repeated at forty callsites, because the callsite that gets forgotten is the one that
# fails silently, and because it makes the commands in the documentation work unchanged from either
# shell instead of needing a prefix only the reader can add.
#
# Defined only when a real docker executable is on PATH, so require_docker_host still notices its
# absence rather than finding this function and calling it proof.
if [[ "${E2E_HOST_KIND}" == "windows-msys" ]] && E2E_DOCKER_BIN="$(command -v docker 2>/dev/null)"; then
    docker() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "${E2E_DOCKER_BIN}" "$@"; }
fi

# host_path <path>  ->  the same location, spelled the way the Docker daemon accepts it
#
# On Linux the daemon and the shell agree, so this is the identity. Under MSYS the daemon is a
# Windows process that only understands the Windows form: `docker cp /d/repo/setup` answers
# `GetFileAttributesEx D:\d: The system cannot find the file specified`. Every docker argument that
# names a location on this machine goes through here, and every argument that names a location
# inside a container must not.
host_path() {
    if [[ "${E2E_HOST_KIND}" == "windows-msys" ]]; then
        cygpath -w "$1"
    else
        printf '%s\n' "$1"
    fi
}

require_cmd() {
    for c in "$@"; do
        command -v "${c}" &>/dev/null || {
            echo "ERROR: required command not found: ${c}" >&2
            exit 2
        }
    done
}

# The container tiers need two things, and neither of them is an operating system: a Docker daemon
# that answers, and a shell that can spell a host path the way that daemon expects. This asks those
# two questions directly.
#
# It used to ask `uname -s` instead and refuse anything that was not Linux, which meant Git Bash was
# turned away with a message telling the reader to use WSL, whether or not WSL could reach a daemon.
# Git Bash reaches it through docker.exe and drives it fine once the MSYS path rewriting is dealt
# with, which this file now does. Whether WSL can reach one depends on Docker Desktop having
# integration enabled for that distribution: measured on 2026-08-20 the Ubuntu distribution has a
# socket and answers, and it has been off before, in which case there is no socket in there at all.
# Neither of those is a fact about the operating system, which is why the operating system is no
# longer what decides. A guard that refuses a working setup is as much a defect as one that admits a
# broken one, so the refusal that is left names the thing that is actually missing.
require_docker_host() {
    if [[ "${E2E_HOST_KIND}" == "other" ]]; then
        cat >&2 <<EOF
ERROR: the harness needs a shell that can drive a Docker daemon, and this one cannot.
It reports itself as $(uname -s), which is neither a Linux shell nor an MSYS shell such as Git Bash,
so there is no known way to hand the daemon a host path it will accept. Run the harness from a
Linux shell, from WSL, or from Git Bash on Windows.
EOF
        exit 2
    fi

    # cygpath is what host_path translates with, so on MSYS its absence is as disqualifying as
    # docker's own. Named here rather than discovered as a "command not found" inside a docker
    # argument, where it would read as a Docker problem.
    [[ "${E2E_HOST_KIND}" == "windows-msys" ]] && require_cmd cygpath

    # command -v would find the wrapper function this file defines on MSYS whether or not a real
    # docker exists, so the executable is looked for through E2E_DOCKER_BIN instead, which is set
    # only when that lookup already succeeded.
    if [[ "${E2E_HOST_KIND}" == "windows-msys" ]]; then
        [[ -n "${E2E_DOCKER_BIN:-}" ]] || {
            echo "ERROR: required command not found: docker" >&2
            exit 2
        }
    else
        require_cmd docker
    fi

    docker info &>/dev/null || {
        cat >&2 <<'EOF'
ERROR: there is a docker command here but no daemon answering it.
  Linux:    is the docker service running, and is this user in the docker group?
  WSL:      Docker Desktop must have integration enabled for this distribution, under
            Settings, Resources, WSL integration. With it off there is no socket inside
            WSL at all, and Git Bash is the shell to use instead.
  Git Bash: is Docker Desktop running?
EOF
        exit 2
    }
}
