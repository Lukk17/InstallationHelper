#!/usr/bin/env bash
#
# Shared helpers for the end-to-end harness. Sourced, never executed directly.

set -euo pipefail

E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# E2E_REPO_ROOT lets a check run against a copy of the tree, which is how the
# checks themselves are tested: point it at a copy carrying the old bug and the
# check must fail. A check never proven to fail is not a check.
REPO_ROOT="$(cd "${E2E_REPO_ROOT:-${E2E_ROOT}/..}" && pwd)"
ANSIBLE_DIR="${REPO_ROOT}/setup/ansible"
RUNS_DIR="${E2E_ROOT}/runs"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_DIM=""; C_OFF=""
fi

CHECKS_RUN=0
CHECKS_FAILED=0
FAILED_NAMES=()

log()   { printf '%s\n' "$*"; }
info()  { printf '%s>>%s %s\n' "${C_BLUE}" "${C_OFF}" "$*"; }
dim()   { printf '%s   %s%s\n' "${C_DIM}" "$*" "${C_OFF}"; }
warn()  { printf '%sWARN%s %s\n' "${C_YELLOW}" "${C_OFF}" "$*"; }

# pass <name>            record a passing check
# fail <name> <detail>   record a failing check, never exits on its own so one
#                        failure does not hide the rest of the run
pass() {
    CHECKS_RUN=$((CHECKS_RUN + 1))
    printf '%sPASS%s %s\n' "${C_GREEN}" "${C_OFF}" "$1"
}

fail() {
    CHECKS_RUN=$((CHECKS_RUN + 1))
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    FAILED_NAMES+=("$1")
    printf '%sFAIL%s %s\n' "${C_RED}" "${C_OFF}" "$1"
    [[ $# -gt 1 ]] && printf '     %s\n' "$2"
    return 0
}

# assert_eq <name> <expected> <actual>
assert_eq() {
    if [[ "$2" == "$3" ]]; then
        pass "$1"
    else
        fail "$1" "expected [$2], got [$3]"
    fi
}

# finish <label>  print the tally and exit, non-zero if anything failed.
#
# Exits explicitly rather than letting the last command's status propagate. A
# harness that reports failures and still exits zero is worse than no harness,
# because every caller reads it as a pass, which is the same shape of defect this
# suite exists to catch. Every check script must end with this.
finish() {
    echo
    if [[ "${CHECKS_FAILED:-0}" -eq 0 ]]; then
        printf '%s%s: %d checks, all passed%s\n' "${C_GREEN}" "$1" "${CHECKS_RUN:-0}" "${C_OFF}"
        exit 0
    fi
    printf '%s%s: %d checks, %d FAILED%s\n' "${C_RED}" "$1" "${CHECKS_RUN:-0}" "${CHECKS_FAILED}" "${C_OFF}"
    for n in "${FAILED_NAMES[@]}"; do printf '  - %s\n' "${n}"; done
    exit 1
}

require_cmd() {
    for c in "$@"; do
        command -v "${c}" &>/dev/null || {
            echo "ERROR: required command not found: ${c}" >&2
            exit 2
        }
    done
}

# The harness drives Linux containers, so it needs a Linux shell with Docker. On
# Windows that means running it from inside WSL, which is also the only place the
# playbook itself runs. Fail with that instruction rather than a confusing
# docker error twenty lines later.
require_linux_docker() {
    if [[ "$(uname -s)" != Linux* ]]; then
        cat >&2 <<'EOF'
ERROR: this harness must run from a Linux shell with a Docker socket.
On Windows, run it from inside WSL:
  wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && ./e2e/run.sh --tier 1"
EOF
        exit 2
    fi
    require_cmd docker
    docker info &>/dev/null || {
        echo "ERROR: cannot talk to the Docker daemon. Is Docker Desktop running with WSL integration enabled?" >&2
        exit 2
    }
}

# Extract "<key> true|false" for every boolean toggle in a group_vars file,
# independently of setup.sh, so tier 1 can compare the two and catch drift.
yaml_bool_toggles() {
    sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//' "$1" \
        | grep -E '^[a-z_]+: (true|false)$' \
        | tr -d ':'
}

timestamp() { date -u +%Y-%m-%dT%H-%M-%SZ; }
