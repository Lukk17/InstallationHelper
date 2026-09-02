#!/usr/bin/env bash
#
# Tier 1: the Windows run still reclaims the package caches, in the right place, without being able
# to fail the run.
#
# In the all-apps Windows cell of run 32864564543 the pre-run cleanup freed 17 GB, taking the runner
# from 29.2 to 46.1 GB free, and the software set exhausted the disk anyway:
#
#   setup_wsl (Ubuntu): wsl --install exited -1. There is not enough space on the disk.
#                       Error code: Wsl/InstallDistro/0x80070070
#
# The two failures either side of it were the same cause in different clothes, an access violation
# out of the Arduino installer and the Android SDK dying at 85 per cent while unzipping, and neither
# message mentions disk. Chocolatey is what leaves the payload behind: it downloads to
# <temp>\chocolatey\<package>\<version>, installs from there, and does not clean up, which a real
# run's log confirms for a 170 MB VirtualBox installer.
#
# So the wizard now empties both package caches between the packages and the phases that need room.
# Four things about that arrangement are worth more than a comment, because each of them is silent
# when it breaks:
#
#   1. the step is still called, at all. Delete the call and the wizard loses the headroom without
#      one line of output changing.
#   2. it is called after the packages and before the SDK installers. Moved above the packages it
#      empties an empty cache, moved below `wsl --install` it frees the disk after the phase that
#      needed it.
#   3. its result is discarded into $null. An unassigned call would add its return object to
#      Invoke-WindowsRun's output stream, and the caller would get an array of two things where it
#      reads an ordered hashtable, which under Set-StrictMode -Version Latest is a terminating error
#      in the reporting rather than at the call.
#   4. the remover cannot throw. A cache that will not empty leaves the disk exactly as it was, so
#      it is a line in the summary, never the end of the run.
#
# Points 1 and 2 are the ones that cost a sweep before, in another shape: the manual workflow was
# missing the disk cleanup and the AppArmor step the sweep's Linux cell has, and nothing said so.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: the Windows run reclaims the package caches between the packages and the SDKs"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "Windows cache cleanup"; }

require_python "the Windows run reclaims the package caches between the packages and the SDKs" "Windows cache cleanup"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re

SETUP = pathlib.Path('setup/setup.ps1')
MODULE = pathlib.Path('setup/windows/WindowsSoftware.ps1')

lines = []

for path in (SETUP, MODULE):
    if not path.exists():
        print('FAIL %s is missing, so this check proves nothing' % path.as_posix())
        raise SystemExit(0)

setup_text = SETUP.read_text(encoding='utf-8')
setup_lines = setup_text.splitlines()
module_text = MODULE.read_text(encoding='utf-8')


def function_body(text, name):
    """The lines of `function <name> {` up to the closing brace in column one."""
    all_lines = text.splitlines()
    start = None
    for i, line in enumerate(all_lines):
        if re.match(r'^function\s+%s\s*\{' % re.escape(name), line):
            start = i
            break
    if start is None:
        return None
    body = all_lines[start:]
    for j, line in enumerate(body[1:], start=1):
        if line == '}':
            return body[:j + 1]
    return None


# --- 1 and 3: called once, from the run function, with its result discarded --------------------
run_body = function_body(setup_text, 'Invoke-WindowsRun')
if run_body is None:
    lines.append('FAIL setup.ps1 has no Invoke-WindowsRun that closes with a brace in column one')
else:
    calls = [i for i, line in enumerate(run_body) if re.search(r'\bClear-WindowsCacheAndShow\b', line)]
    if not calls:
        lines.append('FAIL Invoke-WindowsRun never calls Clear-WindowsCacheAndShow, so the Windows run '
                     'keeps every installer it downloaded and the phases after the packages get whatever '
                     'disk is left')
    elif len(calls) > 1:
        lines.append('FAIL Invoke-WindowsRun calls Clear-WindowsCacheAndShow %d times, and each one '
                     'prints a phase header' % len(calls))
    else:
        call_line = run_body[calls[0]]
        if not re.match(r'^\s*\$null\s*=\s*Clear-WindowsCacheAndShow\b', call_line):
            lines.append('FAIL Invoke-WindowsRun calls Clear-WindowsCacheAndShow as `%s`, which is not '
                         'discarded into $null, so its return joins the function output and the caller '
                         'reads an array where it expects the phase hashtable' % call_line.strip())
        else:
            lines.append('OK Invoke-WindowsRun calls Clear-WindowsCacheAndShow once and discards its result')

        # --- 2: after the packages, before the SDK installers ---------------------------------
        def index_of(pattern):
            for i, line in enumerate(run_body):
                if re.search(pattern, line):
                    return i
            return None

        software = index_of(r'\$windowsResult\s*=\s*Invoke-WindowsSoftwareInstall')
        custom = index_of(r'\$customResult\s*=\s*Invoke-AndShowCustomInstalls')
        where = calls[0]
        if software is None or custom is None:
            lines.append('FAIL Invoke-WindowsRun no longer assigns $windowsResult from '
                         'Invoke-WindowsSoftwareInstall and $customResult from Invoke-AndShowCustomInstalls, '
                         'so the ordering of the cache cleanup cannot be checked')
        elif not (software < where < custom):
            lines.append('FAIL the cache cleanup sits at line %d of Invoke-WindowsRun, outside the window '
                         'between the package install at %d and the SDK installers at %d, where it either '
                         'empties a cache nothing has filled yet or frees the disk after the phase that '
                         'needed it' % (where + 1, software + 1, custom + 1))
        else:
            lines.append('OK the cache cleanup runs after the packages and before the SDK installers')

# --- 3 and 4: what the remover does, and what it cannot do ------------------------------------
remover = function_body(module_text, 'Clear-WindowsPackageCache')
if remover is None:
    lines.append('FAIL setup/windows/WindowsSoftware.ps1 has no Clear-WindowsPackageCache that closes '
                 'with a brace in column one')
else:
    body = '\n'.join(remover)

    # The winget source index is the manifests and version data winget resolves ids against, and the
    # verification phase queries winget after this runs. Deleting it only buys another download.
    if re.search(r"KeepInWingetCache\s*=\s*@\(\s*'cache'\s*\)", body):
        lines.append("OK Clear-WindowsPackageCache keeps winget's source index by default")
    else:
        lines.append("FAIL Clear-WindowsPackageCache no longer keeps winget's source index by default, so "
                     "the verification phase that runs after it has to fetch another one")

    throws = [line.strip() for line in remover if re.search(r'(^|\s)throw(\s|$)', line)]
    if throws:
        lines.append('FAIL Clear-WindowsPackageCache can throw (%s), and a cache it cannot empty leaves '
                     'the disk exactly as it was, so it must never be the end of the run'
                     % '; '.join(throws))
    else:
        lines.append('OK Clear-WindowsPackageCache carries no throw, so a cache it cannot empty cannot '
                     'end the run')

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "Windows cache cleanup"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "the Windows cache cleanup is not wired the way the disk failure needs" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the cache cleanup check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "Windows cache cleanup"
