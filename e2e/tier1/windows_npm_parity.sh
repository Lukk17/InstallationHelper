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

# OpenCode is the one tool with two packages, version 2 by default and version 1 when opencode_use_v1 is true,
# and each side declares the pair once: ih_opencode_cli in setup/ansible/tasks/opencode_version.yaml, which
# opencode_unix.yaml reads as opencode_cli_package and opencode_other_cli_package, and $script:OpenCodeCliPackages
# in WindowsNpmTools.ps1, which Get-NpmToolPackage reads. Both pairs are read here, as "<version> <package>" lines.
ansible_opencode_pair="$(opencode_cli_pair)"
ps_opencode_pair="$(
    grep -E '^\$script:OpenCodeCliPackages = ' "${PS_FILE}" \
        | grep -oE "v[12] = '[^']+'" | sed -E "s/ = '/ /; s/'$//" | sort
)"
if [[ -n "${ansible_opencode_pair}" && "${ansible_opencode_pair}" == "${ps_opencode_pair}" && "$(grep -c . <<<"${ps_opencode_pair}")" -eq 2 ]]; then
    pass "both sides name the same two OpenCode command line packages: $(tr '\n' ' ' <<<"${ps_opencode_pair}")"
else
    fail "the two sides disagree about OpenCode's command line package per version, or one side declares no pair" \
         "ai_tools [$(tr '\n' ' ' <<<"${ansible_opencode_pair}")] PowerShell [$(tr '\n' ' ' <<<"${ps_opencode_pair}")]"
fi

# The Ansible side: every npm_pkg named by a *_unix.yaml consumer, and both packages of the OpenCode pair for the
# consumer that names the selected one, read by ai_tools_npm_packages in lib/common.sh, which tier 2 reads too.
ansible_pkgs="$(ai_tools_npm_packages)"

# The PowerShell side: every Package value in the table, and the pair Get-NpmToolPackage fills the opencode row
# from. Extracted with a different expression from the one above on purpose, so a shared mistake cannot hide
# the difference.
ps_pkgs="$(
    {
        sed -n '/NpmToolPackages = \[ordered\]@{/,/^}/p' "${PS_FILE}" \
            | grep -oE "Package = '[^']+'" \
            | sed -E "s/Package = '//; s/'$//"
        awk '{print $2}' <<<"${ps_opencode_pair}"
    } | sort -u
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

# The older package a tool replaces has to match as well. Each side removes it before installing,
# because npm refuses a second package claiming the same bin with EEXIST, so a replacement named on
# one platform and not the other leaves that platform failing the install on every machine that
# still carries the old package.
#
# For OpenCode the replaced package is the other one of the pair, both ways round, on each side only while that
# side still wires it so: opencode_unix.yaml passing opencode_other_cli_package, and Get-NpmToolPackage setting
# Replaces from $script:OpenCodeCliPackages[$other].
opencode_pairs_both_ways() {
    local v1 v2
    v1="$(awk '$1 == "v1" {print $2}' <<<"$1")"
    v2="$(awk '$1 == "v2" {print $2}' <<<"$1")"
    [[ -n "${v1}" && -n "${v2}" ]] && printf '%s %s\n%s %s\n' "${v1}" "${v2}" "${v2}" "${v1}"
}
ansible_replaced="$(
    {
        for f in "${AI_TASKS}"/*_unix.yaml; do
            [[ "$(basename "${f}")" == "npm_install_unix.yaml" ]] && continue
            pkg="$(grep -hE '^\s*npm_pkg:' "${f}" 2>/dev/null | sed -E 's/^\s*npm_pkg:\s*//; s/"//g; s/\s+$//')"
            old="$(grep -hE '^\s*npm_replaced_pkg:' "${f}" 2>/dev/null | sed -E 's/^\s*npm_replaced_pkg:\s*//; s/"//g; s/\s+$//')"
            if [[ "${pkg}" == "{{ opencode_cli_package }}" && "${old}" == "{{ opencode_other_cli_package }}" ]]; then
                opencode_pairs_both_ways "${ansible_opencode_pair}"
            elif [[ -n "${old}" ]]; then
                echo "${pkg} ${old}"
            fi
        done
    } | sort -u
)"
ps_replaced="$(
    {
        sed -n '/NpmToolPackages = \[ordered\]@{/,/^}/p' "${PS_FILE}" \
            | { grep -E "Replaces = '" || true; } \
            | sed -E "s/.*Package = '([^']+)'.*Replaces = '([^']+)'.*/\1 \2/"
        if grep -qF "\$table['opencode']['Replaces']       = \$script:OpenCodeCliPackages[\$other]" "${PS_FILE}"; then
            opencode_pairs_both_ways "${ps_opencode_pair}"
        fi
    } | sort -u
)"

if [[ "${ansible_replaced}" == "${ps_replaced}" ]]; then
    pass "the PowerShell installer and the ai_tools role remove the same replaced npm packages ($(grep -c . <<<"${ansible_replaced}" || true))"
else
    fail "the PowerShell installer and the ai_tools role disagree about which older npm package a tool replaces" \
         "$(diff <(echo "${ansible_replaced}") <(echo "${ps_replaced}") | tr '\n' ' ')"
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

# Both sides remove the replaced package before the new one is proven to install, so both must put it
# back when the new one fails. Until 2026-10-10 neither did, and a failed @opencode/cli install left no
# OpenCode CLI at all on a machine that had a working opencode-ai. The Windows behaviour is driven by
# the Pester tests in e2e/tier1/windows/WindowsSoftware.Tests.ps1, and this asserts the shape on both.
ps_install_body="$(sed -n '/^function Install-NpmToolPackage/,/^}/p' "${PS_FILE}")"
if grep -qF '& npm install -g $ReplacesPackage' <<<"${ps_install_body}"; then
    pass "the PowerShell installer installs the replaced npm package again when the new one fails"
else
    fail "the PowerShell installer removes the replaced npm package and never puts it back" \
         "Install-NpmToolPackage in ${PS_FILE} has no npm install -g \$ReplacesPackage"
fi

require_python "the Unix npm helper restores the package it replaced" "Windows npm parity"
restore_status=0
restore_report="$("${PYTHON}" - "${AI_TASKS}/npm_install_unix.yaml" <<'PYEOF'
import sys

import yaml

tasks = yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or []


def shell_of(task):
    return str(task.get('ansible.builtin.shell', task.get('shell', '')) or '')


holders = [t for t in tasks if isinstance(t, dict) and 'block' in t
           and any('npm install -g' in shell_of(c) and 'npm_pkg' in shell_of(c) for c in t['block'])]
if len(holders) != 1:
    print('FAIL the npm install of npm_pkg is not inside exactly one block, so nothing rescues it')
    raise SystemExit(0)
rescue = holders[0].get('rescue') or []
restores = [t for t in rescue if 'npm_replaced_pkg' in shell_of(t) and 'npm install -g' in shell_of(t)
            and 'npm_replaced_removal is changed' in str(t.get('when', ''))]
fails = [t for t in rescue if 'ansible.builtin.fail' in t or 'fail' in t]
if not restores:
    print('FAIL the rescue around the npm install does not install npm_replaced_pkg again after it was removed')
elif not fails or rescue.index(fails[-1]) < rescue.index(restores[0]):
    print('FAIL the rescue around the npm install does not raise the failure again after the restore, so '
          'the caller never records the tool as NOT installed')
else:
    print('OK')
PYEOF
)" || restore_status=$?
assert_python_ran "${restore_status}" "Windows npm parity"
case "${restore_report}" in
    OK) pass "the Unix npm helper installs the replaced package again when the new one fails, then fails the step" ;;
    *)  fail "the Unix npm helper can leave neither the old nor the new package installed" "${restore_report#FAIL }" ;;
esac

finish "Windows npm parity"
