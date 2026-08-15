#!/usr/bin/env bash
#
# Tier 1: the playbook must parse, and it must parse quietly.
#
# The warning budget is the point. ansible.cfg once set `inventory = localhost,`, and
# because that setting is a comma-separated path list, the empty entry after the comma
# resolved to the config directory. Ansible then walked all of setup/ansible/ as an
# inventory source, tried to run callback_plugins/dual_logger.py as an inventory
# script, and printed 212 warnings on every invocation without an explicit -i. A real
# warning cannot be seen in that. See docs/regression_ledger.md.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

# Ansible does not run on Windows, so from Git Bash there is no ansible-playbook to call and this
# check used to abort the whole gate with exit 2. That matters because on this machine neither shell
# can run the gate alone: WSL has Ansible but its only reachable pwsh is a Store alias stub it cannot
# execute, and Git Bash has a working pwsh but no Ansible. Re-executing this one check inside WSL
# closes that split, so `./e2e/run.sh` is fully green from either shell instead of being
# unsatisfiable from both. The default distribution is used rather than a hardcoded name.
#
# The drive mount path is derived here rather than asked of wslpath. wslpath answers with whichever
# mount it finds first, and with Docker Desktop running that is a
# /mnt/wsl/docker-desktop-bind-mounts/... path whose existence comes and goes with the daemon's
# mounts, so the same command worked once and then exited 127. /mnt/<drive>/ is the stable answer,
# it is the path every command in AGENTS.md already uses, and it is checked for before use rather
# than assumed.
if ! command -v ansible-playbook &>/dev/null; then
    if command -v wsl &>/dev/null && command -v cygpath &>/dev/null; then
        win_repo="$(cygpath -w "${REPO_ROOT}")"
        drive="$(tr '[:upper:]' '[:lower:]' <<<"${win_repo:0:1}")"
        wsl_repo="/mnt/${drive}${win_repo:2}"
        wsl_repo="${wsl_repo//\\//}"
        # Through `bash -c`, never as a bare `wsl test`. wsl.exe resolves a bare command against
        # the distribution's default path handling and returned 1 for a directory that exists,
        # which made this refuse to delegate while the same test through bash said yes.
        #
        # Retried because interop is not reliable while the machine is busy. With three tier 3
        # scenario containers running, wsl.exe intermittently answers
        # Wsl/Service/0x80072744c, a socket timeout, and one in three invocations of this check
        # failed the gate for a reason that had nothing to do with the playbook.
        wsl_visible=""
        for _ in 1 2 3; do
            if wsl bash -c "test -d '${wsl_repo}/e2e/tier1'" 2>/dev/null; then
                wsl_visible="yes"
                break
            fi
            sleep 5
        done
        if [[ -n "${wsl_visible}" ]]; then
            info "no ansible-playbook here, re-running this check inside WSL at ${wsl_repo}"
            exec wsl bash -c "cd '${wsl_repo}' && bash e2e/tier1/ansible_static.sh"
        fi
        warn "no ansible-playbook here and ${wsl_repo} is not visible from WSL, so the playbook cannot be parsed from this shell"
    fi
    require_cmd ansible-playbook
fi

info "Tier 1: Ansible static checks"

cd "${ANSIBLE_DIR}"

# --- syntax ------------------------------------------------------------------
syntax_out="$(ansible-playbook --syntax-check site.yaml 2>&1 || true)"
if grep -qE '^playbook: site\.yaml' <<<"${syntax_out}"; then
    pass "site.yaml parses"
else
    fail "site.yaml does not parse" "$(tail -5 <<<"${syntax_out}" | tr '\n' ' ')"
fi

# --- warning budget ----------------------------------------------------------
# Two warnings are correct and expected here: no inventory was passed, so only the
# implicit localhost exists and it does not match `all`. Anything beyond that is noise
# that will hide a real problem.
EXPECTED_WARNINGS=2
actual_warnings="$(grep -cE '\[WARNING\]|as an inventory source' <<<"${syntax_out}" || true)"
if [[ "${actual_warnings}" -le "${EXPECTED_WARNINGS}" ]]; then
    pass "syntax check emits at most ${EXPECTED_WARNINGS} warnings (got ${actual_warnings})"
else
    fail "syntax check emits ${actual_warnings} warnings, budget is ${EXPECTED_WARNINGS}" \
         "$(grep -E '\[WARNING\]|as an inventory source' <<<"${syntax_out}" | sort -u | head -5 | tr '\n' ' ')"
fi

# --- nothing may be parsed as inventory -------------------------------------
# Guards the specific failure above rather than only its symptom count.
if grep -qE 'as an inventory source|not a valid group definition' <<<"${syntax_out}"; then
    fail "files under setup/ansible are being parsed as inventory" \
         "$(grep -oE '[^ ]+ as an inventory source' <<<"${syntax_out}" | head -3 | tr '\n' ' ')"
else
    pass "no repository file is mistaken for an inventory source"
fi

# --- every verify and scenario file must parse too ---------------------------
for f in "${E2E_ROOT}"/tier3/verify.yaml; do
    if ansible-playbook --syntax-check "${f}" &>/dev/null; then
        pass "$(basename "${f}") parses"
    else
        fail "$(basename "${f}") does not parse" "$(ansible-playbook --syntax-check "${f}" 2>&1 | tail -3 | tr '\n' ' ')"
    fi
done

# --- optional linters --------------------------------------------------------
# Reported, never required. Making the gate depend on a tool that may not be installed
# would mean the gate silently stops running, which is its own failure mode.
if command -v yamllint &>/dev/null; then
    if yamllint -d "{extends: relaxed, rules: {line-length: disable}}" "${ANSIBLE_DIR}" &>/dev/null; then
        pass "yamllint clean"
    else
        fail "yamllint reports problems" "$(yamllint -d '{extends: relaxed, rules: {line-length: disable}}' "${ANSIBLE_DIR}" 2>&1 | head -5 | tr '\n' ' ')"
    fi
else
    warn "yamllint not installed, skipping. Install with: pip install --user yamllint"
fi

if command -v ansible-lint &>/dev/null; then
    if ansible-lint --nocolor -q site.yaml &>/dev/null; then
        pass "ansible-lint clean"
    else
        warn "ansible-lint reports findings, not treated as a failure yet:"
        ansible-lint --nocolor -q site.yaml 2>&1 | head -15 | sed 's/^/       /'
    fi
else
    warn "ansible-lint not installed, skipping. Install with: pip install --user ansible-lint"
fi

finish "Ansible static checks"
