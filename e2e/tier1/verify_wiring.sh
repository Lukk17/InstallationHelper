#!/usr/bin/env bash
#
# Tier 1: the verification must be read-only, and the wizard must actually run it.
#
# Two separate defect classes, both of them ones this repository has already paid for.
#
# The first is a check that changes the machine it is checking. verify_install.yaml is handed to
# people to run on a working laptop and on a virtual machine, and its whole claim is that it only
# looks. One state-changing module in it turns a diagnostic into an installer, and nothing else in
# the gate would notice, because the play would still parse and still pass.
#
# The second is a step nobody runs. install_gradle sat behind a comment saying another role handled
# it, and it installed nothing for as long as nobody checked. A verification wired into one of the
# wizard's two entrypoints, or wired in and then quietly dropped in a later edit, is the same defect
# with a worse consequence: the run reports success and nobody ever asks the machine.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

VERIFY_PLAY="${ANSIBLE_DIR}/verify_install.yaml"
WRAPPER="${E2E_ROOT}/tier3/verify.yaml"
SETUP_SH="${REPO_ROOT}/setup/setup.sh"

info "Tier 1: the verification play, and the wizard's use of it"

for f in "${VERIFY_PLAY}" "${WRAPPER}" "${SETUP_SH}"; do
    [[ -f "${f}" ]] || { fail "missing file, nothing below can mean anything" "${f}"; finish "verification wiring"; }
done

# --- the play may only read --------------------------------------------------
# Named modules rather than a pattern, because the interesting ones are all boringly recognisable
# and a pattern over "anything not on an allowlist" would fail on every future read module. `command`
# and `shell` are absent from this list on purpose: they are how the package databases are asked what
# they hold, and the next check is what keeps them honest.
CHANGING_MODULES=(apt apt_repository apt_key dnf yum package pacman homebrew homebrew_cask snap
                  flatpak flatpak_remote copy template file lineinfile blockinfile replace ini_file
                  user group systemd systemd_service service get_url unarchive pip npm git cron
                  mount reboot make)

# Two spellings per module, and the split matters. A collection-qualified name is a module wherever
# it appears, so it is matched in any form. A bare name is matched only when it is the whole of the
# line, because several module names are also parameter names: include_vars takes `file:` with a
# value, and matching that would report this play as writing files when all it does is read four
# variable files.
found_changing=()
for m in "${CHANGING_MODULES[@]}"; do
    if grep -qE "^[[:space:]]*(ansible\.builtin\.|community\.general\.|ansible\.posix\.)${m}:" "${VERIFY_PLAY}" \
       || grep -qE "^[[:space:]]*${m}:[[:space:]]*$" "${VERIFY_PLAY}"; then
        found_changing+=("${m}")
    fi
done

if [[ ${#found_changing[@]} -eq 0 ]]; then
    pass "verify_install.yaml uses no state-changing module"
else
    fail "verify_install.yaml uses ${#found_changing[@]} module(s) that can change the machine it is meant to only inspect" \
         "${found_changing[*]}"
fi

# Every command and shell task must declare itself unchanging. Without changed_when: false a read
# reports "changed" on every run, which is not only noise: it is the report telling the reader that
# the verification modified something, which is the one thing it promises never to do.
n_exec="$(grep -cE '^[[:space:]]*ansible\.builtin\.(command|shell):' "${VERIFY_PLAY}" || true)"
n_unchanged="$(grep -cE '^[[:space:]]*changed_when: false$' "${VERIFY_PLAY}" || true)"

if [[ "${n_exec}" -eq 0 ]]; then
    fail "verify_install.yaml runs no command or shell task at all, so it cannot be asking any package database what it holds" \
         "expected at least the per-family installed-package query"
elif [[ "${n_unchanged}" -ge "${n_exec}" ]]; then
    pass "all ${n_exec} command/shell reads in verify_install.yaml are marked changed_when: false"
else
    fail "verify_install.yaml has ${n_exec} command/shell tasks but only ${n_unchanged} changed_when: false" \
         "a read that reports itself as a change contradicts the only promise this play makes"
fi

# --- one implementation, two callers ----------------------------------------
if grep -qE '^[[:space:]]*-[[:space:]]*name:[[:space:]]*Assert ' "${WRAPPER}"; then
    fail "e2e/tier3/verify.yaml carries assertions of its own, so the container and a real machine can now drift" \
         "it must import setup/ansible/verify_install.yaml instead of restating it"
elif grep -q 'verify_install.yaml' "${WRAPPER}"; then
    pass "e2e/tier3/verify.yaml is a wrapper around verify_install.yaml, not a second copy of it"
else
    fail "e2e/tier3/verify.yaml neither asserts nor imports anything recognisable" \
         "expected an import of setup/ansible/verify_install.yaml"
fi

# --- the wizard runs it, on both of its entrypoints -------------------------
# finish_run is the only place setup.sh exits after a playbook run, and it is what calls the
# verification. Both the interactive confirm screen and run_non_interactive must reach it, because a
# scripted install is exactly the kind that nobody watches.
n_finish="$(grep -cE '^[[:space:]]*finish_run "\$\{playbook_rc\}"$' "${SETUP_SH}" || true)"
if [[ "${n_finish}" -ge 2 ]]; then
    pass "setup.sh ends both of its run paths in finish_run (${n_finish} call sites)"
else
    fail "setup.sh reaches finish_run from ${n_finish} place(s), so at least one entrypoint installs without verifying" \
         "expected the interactive confirm screen and run_non_interactive to both call it"
fi

if grep -q 'run_verification' "${SETUP_SH}" && grep -q "${VERIFY_PLAY##*/}" "${SETUP_SH}"; then
    pass "setup.sh names verify_install.yaml and has a verification step to run it"
else
    fail "setup.sh does not run the verification play" \
         "expected VERIFY_PLAY to point at verify_install.yaml and run_verification to exist"
fi

# The selection must be sliced off the playbook command rather than resolved a second time. A
# verification that reads group_vars while the run read extra-vars demands every application the user
# unticked and reports it missing, which makes the whole step noise on the first customised install.
if grep -qF 'VERIFY_ARGS=("${VERIFY_PLAY}" "${PLAYBOOK_ARGS[@]:1}")' "${SETUP_SH}"; then
    pass "the verification is handed the same selection as the playbook, from one assembly"
else
    fail "setup.sh no longer derives the verification arguments from PLAYBOOK_ARGS" \
         "two assemblies of the same selection will drift, and the drift reports deselected applications as missing"
fi

# dual_logger opens the four installation_*.log files in the home directory with mode "w". Running
# the verification under it truncates the logs of the run being verified, the instant it starts.
if grep -q 'ANSIBLE_STDOUT_CALLBACK=default' "${SETUP_SH}"; then
    pass "the verification runs under the stock callback, so it cannot truncate installation_full.log"
else
    fail "the verification does not override the dual_logger stdout callback" \
         "dual_logger opens installation_full.log with mode w, so verifying a run would erase its log"
fi

finish "verification wiring"
