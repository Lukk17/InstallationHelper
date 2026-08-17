#!/usr/bin/env bash
#
# Sourceable helper, not a check of its own. Sourced by every tier 1 check that needs a working
# ansible-playbook, currently ansible_static.sh and os_family_derivation.sh.
#
# Ansible does not run on Windows, so from Git Bash there is no ansible-playbook to call and a check
# that needs one used to abort the whole gate with exit 2. That matters because on this machine
# neither shell can run the gate alone: WSL has Ansible but its only reachable pwsh is a Store alias
# stub it cannot execute, and Git Bash has a working pwsh but no Ansible. Re-executing the affected
# check inside WSL closes that split, so `./e2e/run.sh` is fully green from either shell instead of
# being unsatisfiable from both. The default distribution is used rather than a hardcoded name.
#
# This lives in one file rather than inline in each check because it is exactly the shape of thing
# that drifts: two copies of one piece of shell, one of them fixed and the other not, is the wizard
# toggle parse desync in docs/regression_ledger.md.
#
# The drive mount path is derived here rather than asked of wslpath. wslpath answers with whichever
# mount it finds first, and with Docker Desktop running that is a
# /mnt/wsl/docker-desktop-bind-mounts/... path whose existence comes and goes with the daemon's
# mounts, so the same command worked once and then exited 127. /mnt/<drive>/ is the stable answer,
# it is the path every command in AGENTS.md already uses, and it is checked for before use rather
# than assumed.

# delegate_to_wsl_when_no_ansible <repository-relative path of the calling check>
#
# Returns without doing anything when ansible-playbook is already on PATH. Otherwise it replaces the
# current process with the same check running inside WSL, and if WSL cannot see the repository it
# falls through to require_cmd, which exits 2 with the missing command named.
delegate_to_wsl_when_no_ansible() {
    local check_path="${1:?delegate_to_wsl_when_no_ansible needs the repository-relative path of the calling check}"

    command -v ansible-playbook &>/dev/null && return 0

    if command -v wsl &>/dev/null && command -v cygpath &>/dev/null; then
        local win_repo drive wsl_repo wsl_visible=""
        win_repo="$(cygpath -w "${REPO_ROOT}")"
        drive="$(tr '[:upper:]' '[:lower:]' <<<"${win_repo:0:1}")"
        wsl_repo="/mnt/${drive}${win_repo:2}"
        wsl_repo="${wsl_repo//\\//}"

        # Through `bash -c`, never as a bare `wsl test`. wsl.exe resolves a bare command against the
        # distribution's default path handling and returned 1 for a directory that exists, which made
        # this refuse to delegate while the same test through bash said yes.
        #
        # Retried because interop is not reliable while the machine is busy. With three tier 3
        # scenario containers running, wsl.exe intermittently answers Wsl/Service/0x80072744c, a
        # socket timeout, and one in three invocations failed the gate for a reason that had nothing
        # to do with the playbook.
        for _ in 1 2 3; do
            if wsl bash -c "test -d '${wsl_repo}/e2e/tier1'" 2>/dev/null; then
                wsl_visible="yes"
                break
            fi
            sleep 5
        done

        if [[ -n "${wsl_visible}" ]]; then
            info "no ansible-playbook here, re-running this check inside WSL at ${wsl_repo}"
            exec wsl bash -c "cd '${wsl_repo}' && bash ${check_path}"
        fi
        warn "no ansible-playbook here and ${wsl_repo} is not visible from WSL, so the playbook cannot be parsed from this shell"
    fi

    require_cmd ansible-playbook
}
