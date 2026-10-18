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
#
# Both classes exist twice, because there are two wizards. setup.sh ends its runs in the Ansible
# play, and setup.ps1 ends its runs in setup/windows/WindowsVerify.ps1, which asks winget,
# Chocolatey, npm and the disk the same question the play asks apt, pacman and dpkg. Windows had
# neither half of this for as long as it had a native installer: it printed what its own installer
# believed it had done, which is a claim about a command's exit status rather than about the
# machine, and that gap is where every silent-failure entry in docs/regression_ledger.md lives. So
# the Windows half is checked here alongside the Unix half rather than in a file of its own.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

VERIFY_PLAY="${ANSIBLE_DIR}/verify_install.yaml"
WRAPPER="${E2E_ROOT}/tier3/verify.yaml"
SETUP_SH="${REPO_ROOT}/setup/setup.sh"
SETUP_PS1="${REPO_ROOT}/setup/setup.ps1"
VERIFY_PS1="${REPO_ROOT}/setup/windows/WindowsVerify.ps1"

info "Tier 1: the verification play, and the wizard's use of it"

for f in "${VERIFY_PLAY}" "${WRAPPER}" "${SETUP_SH}" "${SETUP_PS1}" "${VERIFY_PS1}"; do
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

# --- the Windows wizard ends in verification too -----------------------------
# setup.ps1 has one exit path for both of its entrypoints, so unlike setup.sh there is no pair of
# call sites to count. What has to be true instead is an order: the verification runs after the
# phases that install, because a verification that runs first describes the machine the run started
# from and would pass on a run that installed nothing at all.
#
# Every one of these reads ends in `|| true`, and that is not decoration. common.sh sets -e and
# -o pipefail, so a grep that matches nothing takes the whole script down at the assignment, and a
# check script that dies is a check script that reports nothing: the run above it prints its passes,
# stops without a word, and the summary never mentions the thing that broke. Proven by deleting the
# verification call from setup.ps1, which is the exact defect this block exists to catch and which
# ended the script silently after the last Unix check.
ps_dotsources=$(grep -cF 'windows\WindowsVerify.ps1' "${SETUP_PS1}" || true)
run_line=$( { grep -nF '$phases = Invoke-WindowsRun' "${SETUP_PS1}" || true; } | head -1 | cut -d: -f1)
verify_line=$( { grep -n 'Invoke-AndShowVerification -' "${SETUP_PS1}" || true; } | head -1 | cut -d: -f1)

if [[ "${ps_dotsources}" -eq 0 ]]; then
    fail "setup.ps1 does not dot-source setup/windows/WindowsVerify.ps1, so it cannot verify anything" \
         "expected a dot-source beside the other four Windows modules"
elif [[ -z "${run_line}" || -z "${verify_line}" ]]; then
    fail "setup.ps1 no longer has both an install phase call and a verification call on its main path" \
         "found install at line [${run_line:-none}] and verification at line [${verify_line:-none}]"
elif [[ "${verify_line}" -gt "${run_line}" ]]; then
    pass "setup.ps1 runs the Windows verification after the install phases (lines ${run_line} then ${verify_line})"
else
    fail "setup.ps1 verifies at line ${verify_line}, before it installs at line ${run_line}" \
         "a verification that runs first describes the machine the run started from, so it would pass a run that installed nothing"
fi

# The selection must be the one the run was given, not a second resolution of the same options. This
# is the Windows spelling of the VERIFY_ARGS check above, and it exists for the same reason: a
# verification that resolves the toggles again demands every application the user unticked and
# reports it missing, which makes the whole step noise on the first customised install. Compared as
# text so a divergence in either direction fails, and the function definitions are excluded because
# a parameter block naturally names the same things a call site does.
run_args=$( { grep -F 'Invoke-WindowsRun -' "${SETUP_PS1}" || true; } | { grep -v '^function' || true; } | head -1 | sed -E 's/^.*Invoke-WindowsRun //')
verify_args=$( { grep -F 'Invoke-AndShowVerification -' "${SETUP_PS1}" || true; } | { grep -v '^function' || true; } | head -1 | sed -E 's/^.*Invoke-AndShowVerification //')

if [[ -n "${run_args}" && "${run_args}" == "${verify_args}" ]]; then
    pass "the Windows verification is handed the same selection as the run (${run_args})"
else
    fail "setup.ps1 hands the verification a different selection from the one it installed" \
         "run got [${run_args:-nothing}], verification got [${verify_args:-nothing}]"
fi

# --- the Windows verification may only read ----------------------------------
# The same rule the play is held to, in the vocabulary Windows uses. Named commands rather than a
# pattern over anything not on an allowlist, for the reason the module list above gives.
#
# Set-Content is absent from this list and its single permitted use is asserted separately below,
# because the report has to reach the log the wizard names on screen and there is no way to write a
# file without a cmdlet that writes files. Set-Location is absent too: it moves this process, not the
# machine, and the npm read needs it to anchor the .npmrc lookup the way WindowsNpmTools.ps1 does.
#
# The whole file is scanned, comments included. A check that skipped comments could be satisfied by
# commenting out the install, which is not a state that ever needs to pass.
CHANGING_COMMANDS=('Install-Module' 'Install-Package' 'Install-WindowsFeature'
                   'Set-ItemProperty' 'New-ItemProperty' 'Remove-ItemProperty' 'Set-Item'
                   'New-Item' 'Remove-Item' 'Copy-Item' 'Move-Item' 'Rename-Item'
                   'Add-Content' 'Clear-Content' 'Out-File'
                   'SetEnvironmentVariable' 'Set-ExecutionPolicy' 'Register-ScheduledTask'
                   'Enable-WindowsOptionalFeature' 'Disable-WindowsOptionalFeature'
                   'Start-Process' 'Invoke-Expression' 'Invoke-WebRequest' 'Invoke-RestMethod'
                   'winget install' 'winget upgrade' 'winget uninstall'
                   'choco install' 'choco upgrade' 'choco uninstall'
                   'npm install' 'npm uninstall')

found_changing_ps=()
for c in "${CHANGING_COMMANDS[@]}"; do
    if grep -qF "${c}" "${VERIFY_PS1}"; then found_changing_ps+=("${c}"); fi
done

n_writes=$(grep -cF 'Set-Content' "${VERIFY_PS1}" || true)
n_log_writes=$(grep -cF 'Set-Content -LiteralPath $LogPath' "${VERIFY_PS1}" || true)

if [[ ${#found_changing_ps[@]} -gt 0 ]]; then
    fail "WindowsVerify.ps1 uses ${#found_changing_ps[@]} command(s) that can change the machine it is meant to only inspect" \
         "${found_changing_ps[*]}"
elif [[ "${n_writes}" -ne "${n_log_writes}" ]]; then
    fail "WindowsVerify.ps1 writes ${n_writes} file(s) and only ${n_log_writes} of those is its own log" \
         "the report may be written to \$LogPath and nothing else may be written at all"
else
    pass "WindowsVerify.ps1 changes nothing but its own log"
fi

# A file that asks nothing passes the check above perfectly, and reads exactly like a file that
# asked and found everything. So the four questions are asserted by name: winget through the shared
# read in WindowsSoftware.ps1, Chocolatey through the shared local-package reader, npm through its
# own global list, and the disk through the proof paths the custom installs have to leave behind.
missing_reads=()
for probe in 'Test-WingetPackageInstalled' 'Get-ChocolateyInstalledPackage' 'npm ls -g' 'Test-Path'; do
    grep -qF "${probe}" "${VERIFY_PS1}" || missing_reads+=("${probe}")
done

if [[ ${#missing_reads[@]} -eq 0 ]]; then
    pass "WindowsVerify.ps1 asks winget, Chocolatey, npm and the disk itself"
else
    fail "WindowsVerify.ps1 no longer asks ${#missing_reads[@]} of the four things a Windows run installs through" \
         "missing: ${missing_reads[*]}"
fi

# --- and the answer has to reach the exit code -------------------------------
# A verification that cannot fail is decoration. setup.sh gives a failed verification its own exit
# code 3 so a caller can tell "the install broke" from "the install claimed success and the machine
# disagrees", and setup.ps1 has to do the same or the whole step is a screenful of text nobody has
# to act on.
if grep -qF '$verifyFailed = $verification.Failed.Count' "${SETUP_PS1}" \
   && grep -qE '^\s*if \(\$verifyFailed -gt 0\) \{' "${SETUP_PS1}" \
   && grep -qE '^\s*exit 3$' "${SETUP_PS1}"; then
    pass "a failed Windows verification reaches setup.ps1's exit code as 3"
else
    fail "setup.ps1 runs the verification and does not act on its result" \
         "expected the Failed count to be read into \$verifyFailed and to exit 3 when it is not zero"
fi

# --- every package a toggle installs is verified, not only its mapped one ----------------------------
# The play expects the package a toggle's software_mapping entry names. Where a role installs more
# under the same toggle, through setup/ansible/tasks/install_role_packages.yaml, the rest used to be a
# literal list in the role that the play never read: install_qastools on Debian and Ubuntu installed
# qashctl and qasconfig beside the qasmixer mapping, install_virt_manager installed the KVM stack beside
# virt-manager, and install_openrazer installed kernel headers beside openrazer-meta and
# openrazer-daemon, and a run that lost any of them was verified as a success. Owner decision 70.
#
# So the role reads such a list from the toggle's companion_packages entry in vars/<OS>.yaml, or from a
# fact a shared task file derives, and the play reads the same thing into its expected set. Asserted:
#   1. every role include of install_role_packages.yaml under install_<key>, on a family whose
#      software_mapping has <key>, takes its list from companion_packages.<key>, or from one fact the
#      play also reads into its companion set, never from a literal list;
#   2. every companion_packages entry belongs to a mapping of its family, is a list of literal names
#      without the mapped package, and is read by some role include, so it is installed by something;
#   3. the play reads os_dict.companion_packages into a fact that reaches expected_native, the set the
#      native-package assertion compares with the machine.
# The number of role installs beside a mapping is reported and must not be zero, so a rewrite that hides
# them from this parser fails here rather than passing over nothing.
require_python "every package a toggle installs is verified" "verification wiring"

companion_status=0
companion_report="$("${PYTHON}" - "${ANSIBLE_DIR}" <<'PYEOF'
import pathlib
import re
import sys

import yaml

ANSIBLE = pathlib.Path(sys.argv[1])
FAMILIES = ['Debian', 'RedHat', 'Archlinux', 'Darwin']
INCLUDE_KEYS = ('ansible.builtin.include_tasks', 'include_tasks', 'ansible.builtin.import_tasks', 'import_tasks')
SHARED = 'install_role_packages.yaml'
WORD = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
lines = []


def single_variable(listed):
    text = listed.strip() if isinstance(listed, str) else ''
    if not (text.startswith('{' * 2) and text.endswith('}' * 2)):
        return None
    name = text[2:-2].strip()
    return name if name.isidentifier() else None


def load(path):
    return yaml.safe_load(path.read_text(encoding='utf-8')) or {}


def when_text(task):
    cond = task.get('when')
    if isinstance(cond, list):
        return ' and '.join(str(c) for c in cond)
    return '' if cond is None else str(cond)


def tasks_of(node, inherited=''):
    if not isinstance(node, list):
        return
    for task in node:
        if not isinstance(task, dict):
            continue
        text = (inherited + ' ' + when_text(task)).strip()
        yield task, text
        for section in ('block', 'rescue', 'always'):
            yield from tasks_of(task.get(section), text)


def included_file(task):
    for key in INCLUDE_KEYS:
        if key in task:
            value = task[key]
            return str(value.get('file', '')) if isinstance(value, dict) else str(value)
    return ''


dictionaries = {family: load(ANSIBLE / 'vars' / (family + '.yaml')) for family in FAMILIES}
mappings = {family: d.get('software_mapping') or {} for family, d in dictionaries.items()}
companions = {family: d.get('companion_packages') or {} for family, d in dictionaries.items()}

# The play: the fact that reads companion_packages, and whether it reaches expected_native.
verify_doc = yaml.safe_load((ANSIBLE / 'verify_install.yaml').read_text(encoding='utf-8'))
facts = {}
for play in verify_doc or []:
    for section in ('pre_tasks', 'tasks', 'post_tasks'):
        for task, _ in tasks_of(play.get(section)):
            values = task.get('ansible.builtin.set_fact') or task.get('set_fact')
            if isinstance(values, dict):
                for name, value in values.items():
                    facts.setdefault(name, []).append(str(value))

companion_facts = [name for name, values in facts.items() if any('os_dict.companion_packages' in v for v in values)]


def reaches(start, goal):
    seen, todo = set(), [start]
    while todo:
        name = todo.pop()
        if name == goal:
            return True
        if name in seen:
            continue
        seen.add(name)
        for value in facts.get(name, []):
            todo.extend(w for w in WORD.findall(value) if w in facts and w not in seen)
    return False


verified_fact = next((name for name in companion_facts if reaches('expected_native', name)), None)
if not companion_facts:
    lines.append('FAIL setup/ansible/verify_install.yaml reads no os_dict.companion_packages, so every '
                 'package a role installs beside a mapping is installed by the run and checked by nothing')
elif verified_fact is None:
    lines.append('FAIL setup/ansible/verify_install.yaml reads os_dict.companion_packages into %s, and '
                 'expected_native never takes it in, so the native-package assertion still ignores them'
                 % ', '.join(sorted(companion_facts)))
verified_text = ' '.join(facts.get(verified_fact, [])) if verified_fact else ''

# The roles: every install beside a mapping, and where its list comes from.
beside = 0
read_keys = set()
for path in sorted((ANSIBLE / 'roles').glob('*/tasks/*.yaml')):
    rel = path.relative_to(ANSIBLE).as_posix()
    for task, text in tasks_of(yaml.safe_load(path.read_text(encoding='utf-8'))):
        if SHARED not in included_file(task):
            continue
        listed = (task.get('vars') or {}).get('role_packages')
        named = [family for family in FAMILIES if "'%s'" % family in text]
        for key in sorted(set(re.findall(r'\binstall_([a-z0-9_]+)\b', text))):
            for family in (named or [f for f in FAMILIES if key in mappings[f]]):
                if key not in mappings[family]:
                    continue
                beside += 1
                where = '%s, "%s", on %s beside the %s mapping' % (rel, task.get('name', '?'), family, key)
                if isinstance(listed, str) and ('companion_packages.' + key) in listed:
                    read_keys.add((family, key))
                    continue
                single = single_variable(listed)
                if single and single in WORD.findall(verified_text):
                    continue
                if single:
                    lines.append('FAIL %s installs the fact %s, which setup/ansible/verify_install.yaml '
                                 'never reads into the set it expects, so those packages are installed and '
                                 'not verified' % (where, single))
                else:
                    lines.append('FAIL %s installs %s from a list of its own, which '
                                 'setup/ansible/verify_install.yaml cannot see. Move the names into '
                                 'companion_packages.%s in vars/%s.yaml and read them from there'
                                 % (where, listed, key, family))

for family in FAMILIES:
    for key, names in sorted(companions[family].items()):
        entry = 'companion_packages.%s in vars/%s.yaml' % (key, family)
        if key not in mappings[family]:
            lines.append('FAIL %s has no software_mapping entry of that key on %s, so no toggle '
                         'enables it in the verification' % (entry, family))
            continue
        if not isinstance(names, list) or not names \
                or not all(isinstance(n, str) and n and '{{' not in n for n in names):
            lines.append('FAIL %s is not a list of literal package names: %r' % (entry, names))
            continue
        if mappings[family][key].get('package') in names:
            lines.append('FAIL %s repeats the mapped package %s, which the verification already expects'
                         % (entry, mappings[family][key].get('package')))
        if (family, key) not in read_keys:
            lines.append('FAIL %s is read by no role include of install_role_packages.yaml under '
                         'install_%s, so the verification expects packages nothing installs' % (entry, key))

if beside == 0:
    lines.append('FAIL no role include of install_role_packages.yaml under a mapped toggle was found, '
                 'so either the parser broke or the includes moved, and nothing here was checked')

if not lines:
    lines.append('OK all %d role installs beside a mapping read companion_packages or a fact the '
                 'verification reads, and setup/ansible/verify_install.yaml expects them through %s'
                 % (beside, verified_fact))

print('\n'.join(lines))
PYEOF
)" || companion_status=$?
assert_python_ran "${companion_status}" "verification wiring"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a package a toggle installs is not verified" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the companion package check printed something unexpected" "${line}" ;;
    esac
done <<<"${companion_report}"

finish "verification wiring"
