#!/usr/bin/env bash
#
# Tier 1: the native Windows npm tool list must match the Ansible role it replaces.
#
# The ai_tools role has a Windows task file per npm tool and none of them can run, because the
# playbook is invoked from inside WSL and reports os_family Debian. setup/windows/WindowsNpmTools.ps1
# is the native replacement, which means there are now two lists of the same packages.
#
# Two lists of the same thing drift. That is not a hypothetical here: the bash and PowerShell wizards
# drifted on toggle parsing and one of them was broken for months before anyone noticed. This compares
# them directly, extracting each side independently, so adding a tool to one and forgetting the other
# fails immediately instead of silently shipping a tool nobody installs.
#
# The Ansible side is kept as the reference even though it cannot execute, because it is where the
# toggle wiring and the documentation still live, and because deleting it would lose the record of
# what the Windows path is supposed to do.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

AI_TASKS="${ANSIBLE_DIR}/roles/ai_tools/tasks"
PS_FILE="${REPO_ROOT}/setup/windows/WindowsNpmTools.ps1"

info "Tier 1: Windows npm tool parity"

[[ -f "${PS_FILE}" ]] || { fail "WindowsNpmTools.ps1 is missing" "${PS_FILE}"; finish "Windows npm parity"; }
[[ -d "${AI_TASKS}" ]] || { fail "ai_tools task directory is missing" "${AI_TASKS}"; finish "Windows npm parity"; }

# The Ansible side: every npm_pkg named by a *_windows.yaml consumer. The shared helper itself only
# documents the variable, so it is excluded.
ansible_pkgs="$(
    for f in "${AI_TASKS}"/*_windows.yaml; do
        [[ "$(basename "${f}")" == "npm_install_windows.yaml" ]] && continue
        grep -hE '^\s*npm_pkg:' "${f}" 2>/dev/null | sed -E 's/^\s*npm_pkg:\s*//; s/"//g; s/\s+$//'
    done | sort -u
)"

# The PowerShell side: every Package value in the table. Extracted with a different expression from
# the one above on purpose, so a shared mistake cannot hide the difference.
ps_pkgs="$(
    sed -n '/NpmToolPackages = \[ordered\]@{/,/^}/p' "${PS_FILE}" \
        | grep -oE "Package = '[^']+'" \
        | sed -E "s/Package = '//; s/'$//" \
        | sort -u
)"

n_ansible="$(grep -c . <<<"${ansible_pkgs}" || true)"
n_ps="$(grep -c . <<<"${ps_pkgs}" || true)"

assert_eq "both sides list the same number of npm packages" "${n_ansible}" "${n_ps}"

if [[ "${ansible_pkgs}" == "${ps_pkgs}" ]]; then
    pass "the PowerShell installer and the ai_tools role list the same ${n_ansible} npm packages"
else
    fail "the PowerShell installer and the ai_tools role disagree about which npm packages to install" \
         "$(diff <(echo "${ansible_pkgs}") <(echo "${ps_pkgs}") | tr '\n' ' ')"
fi

# Every tool must also have a toggle, or nothing can select it. Same class of dead data as the
# orphaned teams and angry_ip_scanner mappings.
missing_toggles=()
while IFS= read -r key; do
    [[ -z "${key}" ]] && continue
    grep -qE "^install_${key}:" "${ANSIBLE_DIR}/group_vars/all.yaml" "${ANSIBLE_DIR}/group_vars/windows.yaml" \
        || missing_toggles+=("${key}")
done < <(sed -n '/NpmToolPackages = \[ordered\]@{/,/^}/p' "${PS_FILE}" | grep -oE '^\s{4}[a-z_]+' | tr -d ' ')

if [[ ${#missing_toggles[@]} -eq 0 ]]; then
    pass "every npm tool has an install toggle"
else
    fail "npm tools with no install_ toggle, so nothing can select them" "${missing_toggles[*]}"
fi

finish "Windows npm parity"
