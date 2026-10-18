#!/usr/bin/env bash
#
# Tier 1: the bash wizard refuses to run as root, says what to do instead, and does nothing else.
#
# setup/setup.sh stops with exit 1 when EUID is 0, because a run as root or through sudo installs
# per-user software for the wrong account and leaves root-owned files in a normal user's home. Until
# this check existed nothing had ever executed that refusal, so it could have moved below a step that
# changes the machine, or stopped refusing, and the gate would have stayed green.
#
# So the wizard is started as uid 0 without any password, and three things are asserted for each
# command line: the exit status, the exact message on standard error, and that nothing past the
# refusal ran. The last one is checked two ways. A sudo stub first on PATH records every call and
# fails it, so a run that reached prepare_become_password leaves a line in its log, and standard
# output must carry neither the wizard banner nor the lines detect_os, the toggle preload and
# --print-command print. --help is the one command line that answers as root, because parse_args
# prints the header before the refusal and that changes nothing.
#
# Both refused command lines stay harmless even against a copy of the wizard without the refusal,
# which is how this check was proven: the bare run stops in prepare_become_password when the sudo
# stub fails and standard input is closed, and --print-command exits before that function.
#
# Getting uid 0 honestly, in this order:
#   1. `unshare -r`, which maps the current user to root inside a user namespace. EUID reads 0 there
#      and nothing outside the namespace gains anything, so this is safe on a developer machine.
#   2. A Linux shell that is already root, which is what a container gives.
#   3. Passwordless sudo on Linux, which is what a hosted runner gives when its kernel refuses an
#      unprivileged user namespace. The sudo stub is still first on PATH inside that run.
# If none of the three is available the check reports SKIP and names why, rather than a pass.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

SETUP_SH="${REPO_ROOT}/setup/setup.sh"
EXPECTED_MESSAGE="ERROR: Do not run this script as root or with sudo. Run it as your normal user: ./setup.sh. It asks for your sudo password itself when a step needs it."

if [[ ! -f "${SETUP_SH}" ]]; then
    fail "the wizard is missing, so this check proves nothing" "${SETUP_SH}"
    finish "wizard root refusal"
fi

ROOT_RUNNER=()
ROOT_HOW=""
if command -v unshare &>/dev/null \
        && [[ "$(unshare -r bash -c 'printf %s "${EUID}"' 2>/dev/null || true)" == "0" ]]; then
    ROOT_RUNNER=(unshare -r)
    ROOT_HOW="a user namespace from unshare -r"
elif [[ "${E2E_HOST_KIND}" == "linux" && "${EUID}" == "0" ]]; then
    ROOT_HOW="this shell, which is already root"
elif [[ "${E2E_HOST_KIND}" == "linux" ]] && sudo -n true &>/dev/null; then
    ROOT_RUNNER=(sudo -n)
    ROOT_HOW="passwordless sudo"
else
    skip "the wizard refuses to run as root" \
         "no unshare -r, no root shell, and no passwordless sudo, so nothing here can start the wizard as uid 0"
    finish "wizard root refusal"
fi

info "Tier 1: the wizard refuses to run as root"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

STUB_DIR="${WORK_DIR}/bin"
SUDO_LOG="${WORK_DIR}/sudo.log"
mkdir -p "${STUB_DIR}"
: >"${SUDO_LOG}"
cat >"${STUB_DIR}/sudo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "sudo \$*" >>"${SUDO_LOG}"
exit 1
EOF
chmod +x "${STUB_DIR}/sudo"

# as_root <command>...  runs the command as uid 0 with the sudo stub first on PATH
as_root() {
    ${ROOT_RUNNER[@]+"${ROOT_RUNNER[@]}"} env "PATH=${STUB_DIR}:${PATH}" "$@"
}

# --- the premise ------------------------------------------------------------------
# Measured rather than assumed, because a runner that silently stayed the normal user would make
# every case below pass for the wrong reason: the wizard would never reach its refusal at all.
seen_euid="$(as_root bash -c 'printf %s "${EUID}"' 2>&1 || true)"
assert_eq "the wizard is started as uid 0 through ${ROOT_HOW}" "0" "${seen_euid}"

seen_sudo="$(as_root bash -c 'command -v sudo' 2>&1 || true)"
assert_eq "the sudo stub is the sudo that run would call" "${STUB_DIR}/sudo" "${seen_sudo}"

# --- the cases ---------------------------------------------------------------------
# run_case <name> <argument>...  records rc, stdout and stderr of one wizard run as root
run_case() {
    local name="$1"; shift
    local rc=0
    as_root bash "${SETUP_SH}" "$@" \
        >"${WORK_DIR}/${name}.out" 2>"${WORK_DIR}/${name}.err" </dev/null || rc=$?
    printf '%s\n' "${rc}" >"${WORK_DIR}/${name}.rc"
}

# assert_refused <name> <label>
assert_refused() {
    local name="$1" label="$2" problems=() rc
    rc="$(cat "${WORK_DIR}/${name}.rc")"

    [[ "${rc}" == "1" ]] || problems+=("exited ${rc} where the refusal exits 1")

    if ! grep -qxF -- "${EXPECTED_MESSAGE}" "${WORK_DIR}/${name}.err"; then
        problems+=("standard error does not carry the refusal, got [$(tr '\n' ' ' <"${WORK_DIR}/${name}.err" | cut -c1-200)]")
    fi

    if grep -qE 'bootstrap wizard|Detected OS|Loading toggles|ansible-playbook' "${WORK_DIR}/${name}.out"; then
        problems+=("the run got past the refusal, standard output was [$(tr '\n' ' ' <"${WORK_DIR}/${name}.out" | cut -c1-200)]")
    fi

    if [[ -s "${SUDO_LOG}" ]]; then
        problems+=("sudo was called: $(tr '\n' ' ' <"${SUDO_LOG}")")
    fi

    if [[ ${#problems[@]} -eq 0 ]]; then
        pass "${label}"
    else
        fail "${label}" "$(printf '%s | ' "${problems[@]}")"
    fi
}

run_case bare
assert_refused bare "./setup.sh as root is refused with the message and nothing else runs"

: >"${SUDO_LOG}"
run_case print_command --print-command --software defaults
assert_refused print_command "--print-command as root is refused as well, before it resolves anything"

: >"${SUDO_LOG}"
run_case help --help
help_rc="$(cat "${WORK_DIR}/help.rc")"
if [[ "${help_rc}" == "0" ]] \
        && grep -qF 'Installation Helper bootstrap wizard' "${WORK_DIR}/help.out" \
        && [[ ! -s "${SUDO_LOG}" ]]; then
    pass "--help still answers as root, because it only prints the header"
else
    fail "--help still answers as root, because it only prints the header" \
         "exited ${help_rc}, standard output [$(head -3 "${WORK_DIR}/help.out" | tr '\n' ' ')], sudo log [$(tr '\n' ' ' <"${SUDO_LOG}")]"
fi

finish "wizard root refusal"
