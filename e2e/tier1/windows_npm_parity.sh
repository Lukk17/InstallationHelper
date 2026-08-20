#!/usr/bin/env bash
#
# Tier 1: the native Windows npm tool list must match the one the ai_tools role installs everywhere
# else.
#
# The role used to carry a Windows task file per npm tool and none of them could run, because the
# playbook is invoked from inside WSL and reports os_family Debian. Those files have been deleted and
# setup/windows/WindowsNpmTools.ps1 is the whole Windows path now. See docs/regression_ledger.md.
#
# That still leaves two lists of the same packages, one per platform, and two lists of the same thing
# drift. That is not a hypothetical here: the bash and PowerShell wizards drifted on toggle parsing
# and one of them was broken for months before anyone noticed. The Unix task files are the other
# list, and they are a better reference than the deleted Windows ones ever were, because they
# execute: a tool whose Windows package has drifted from the package Linux and macOS install is a
# real difference in what the user gets, not a difference between a live file and a dead one.
#
# Each side is extracted with a different expression on purpose, so a shared mistake cannot hide the
# difference.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

AI_TASKS="${ANSIBLE_DIR}/roles/ai_tools/tasks"
PS_FILE="${REPO_ROOT}/setup/windows/WindowsNpmTools.ps1"

info "Tier 1: Windows npm tool parity"

[[ -f "${PS_FILE}" ]] || { fail "WindowsNpmTools.ps1 is missing" "${PS_FILE}"; finish "Windows npm parity"; }
[[ -d "${AI_TASKS}" ]] || { fail "ai_tools task directory is missing" "${AI_TASKS}"; finish "Windows npm parity"; }

# The Ansible side: every npm_pkg named by a *_unix.yaml consumer. The shared helper itself only
# documents the variable, so it is excluded.
ansible_pkgs="$(
    for f in "${AI_TASKS}"/*_unix.yaml; do
        [[ "$(basename "${f}")" == "npm_install_unix.yaml" ]] && continue
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
done < <(sed -n '/NpmToolPackages = \[ordered\]@{/,/^}/p' "${PS_FILE}" | grep -oE '^\s{4}[a-z0-9_]+' | tr -d ' ')

if [[ ${#missing_toggles[@]} -eq 0 ]]; then
    pass "every npm tool has an install toggle"
else
    fail "npm tools with no install_ toggle, so nothing can select them" "${missing_toggles[*]}"
fi

finish "Windows npm parity"
