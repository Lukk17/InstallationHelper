#!/usr/bin/env bash
#
# Tier 1: every workflow job that starts setup.ps1 to install runs the Windows unit tests first.
#
# The Pester suite over the Windows installer runs in this gate on Linux, through windows_pester, and on
# a Windows runner only through the shared action .github/actions/windows-pester. Until 2026-11-13 only
# the sweep's stage 1 job ran the suite on Windows, so a dispatch of the single platform workflow at its
# windows target installed the whole software set without ever running it there. The KiCad 10 test of
# docs/regression_ledger.md 10.270 passed here on Linux and failed only on the Windows runner, and the
# single platform workflow could not have seen it.
#
# So, for every job in every workflow under .github/workflows that starts setup.ps1 for anything but
# -PrintPlan or -ListSoftware, in a step of its own or in a local action it uses:
#
#   - the job runs the shared action before that step, not under continue-on-error, and no wizard step
#     after it carries an `if` with always(), failure() or cancelled(), which would run it after a
#     failed test, or
#   - a job it needs, directly or through other needs, runs the shared action, not under
#     continue-on-error. That route proves order only: whether the install is skipped after a failed
#     test is the decision of the jobs in between, as "Gate: checks passed" decides it in the sweep.
#
# And no workflow step and no other local action runs Invoke-Pester, New-PesterConfiguration or
# e2e/tier1/windows_pester.ps1 itself,
# so the suite has one way of running on Windows rather than a copy per workflow that can drift. The
# shared action and the tier 1 check windows_pester.sh must both start e2e/tier1/windows_pester.ps1 and
# run no Pester of their own, so the runner and the gate judge a run by one rule (docs/regression_ledger.md
# 10.345), and that script must run WindowsSoftware.Tests.ps1 with exactly the Slow and Network tags
# excluded.
#
# The runner and the gate also run one Pester, the one gate_pester_version pins (owner decision 53,
# docs/regression_ledger.md 10.348), from one file, the package gate_pester_url names and
# gate_pester_sha256 checks, the file e2e/gate/provision.sh puts into the gate image (owner decision 54,
# docs/regression_ledger.md 10.359). The shared action and the shared script must both read the version
# pin with Get-PinnedValue and pick Pester by an exact -eq match on it, and neither may accept a newer or
# an older Pester or write a version number of its own. The action may read only those three pins and the
# script only the version pin. The action must download the package once with Invoke-WebRequest from the
# variable that holds gate_pester_url, hash that file with Get-FileHash -Algorithm SHA256, compare the
# hash with the variable that holds gate_pester_sha256 and throw, naming both, on a mismatch, and only
# then unpack it with Expand-Archive into Pester/<version> on the CurrentUser module path. It may not
# install Pester any other way, through Install-Module, Save-Module, Install-PSResource or the like, nor
# write an address or a SHA-256 of its own. The script may not answer a missing Pester with a skip, and no
# other workflow step or local action installs Pester at all. The pin itself must name one exact version.
#
# Before it reads the repository it runs its readers against planted workflows and planted action and
# script bodies, and requires them to name exactly the seven planted workflow defects and none of the
# four sound jobs, and each planted pin defect by the problem written for it and nothing in the sound
# pair, so a reader that went blind fails here instead of passing the real tree.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "${REPO_ROOT}/setup/pinned_values/pinned_values.sh"

info "Tier 1: every job that installs with setup.ps1 runs the Windows unit tests first"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "Windows unit tests before the install"; }

require_python "every job that installs with setup.ps1 runs the Windows unit tests first" "Windows unit tests before the install"

pin_status=0
PINNED_PESTER_VERSION="$(pinned_value gate_pester_version)" || pin_status=$?
if [[ "${pin_status}" -ne 0 ]]; then
    fail "the pinned Pester version cannot be read, so nothing here can compare against it" \
         "pinned_value gate_pester_version exited ${pin_status}"
    finish "Windows unit tests before the install"
fi
export PINNED_PESTER_VERSION

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import os
import pathlib
import re
import sys

import yaml

sys.path.insert(0, 'e2e/lib')
from windows_wizard_jobs import SHARED_USES, code_lines, local_uses, starts_wizard, steps_of

SHARED_FILE = pathlib.Path('.github/actions/windows-pester/action.yml')
SHARED_SCRIPT = pathlib.Path('e2e/tier1/windows_pester.ps1')
LOCAL_CHECK = pathlib.Path('e2e/tier1/windows_pester.sh')
INVOKES_PESTER = re.compile(r'\b(Invoke-Pester|New-PesterConfiguration)\b', re.IGNORECASE)
RUNS_PESTER = re.compile(r'\b(Invoke-Pester|New-PesterConfiguration)\b|windows_pester\.ps1', re.IGNORECASE)
OVERRIDES_FAILURE = re.compile(r'\b(always|failure|cancelled)\s*\(')
EXCLUDED_TAGS = re.compile(r'^\s*\$excludedTags\s*=\s*@\(([^)]*)\)', re.MULTILINE)
FILTER_READS_TAGS = re.compile(r'\.Filter\.ExcludeTag\s*=\s*\$excludedTags\s*$', re.MULTILINE)
PESTER_PIN = 'gate_pester_version'
PESTER_URL_PIN = 'gate_pester_url'
PESTER_SHA_PIN = 'gate_pester_sha256'
ACTION_PINS = {PESTER_PIN, PESTER_URL_PIN, PESTER_SHA_PIN}
SCRIPT_PINS = {PESTER_PIN}
PINNED_VERSION = os.environ.get('PINNED_PESTER_VERSION', '')
EXACT_VERSION = re.compile(r'^\d+\.\d+\.\d+$')
READS_PIN = re.compile(r'\bGet-PinnedValue\s+-Key\s+' + PESTER_PIN + r'\b')
READS_ANY_PIN = re.compile(r'\bGet-PinnedValue\b(?:\s+-Key\s+(\w+))?')
ASSIGNS_PIN = re.compile(r'^\s*\$(\w+)\s*=\s*(?:\[[Vv]ersion\]\s*)?\(?\s*Get-PinnedValue\s+-Key\s+(\w+)\s*\)?\s*$')
EXACT_SELECTION = re.compile(r'\.Version\s+-eq\s+\[[Vv]ersion\]\s*\$\w+')
LOOSE_SELECTION = re.compile(r'-(Minimum|Maximum)Version\b|\.Major\b|-(ge|gt|le|lt)\s*\[[Vv]ersion\]'
                             r'|Sort-Object\s+Version\s+-Descending', re.IGNORECASE)
VERSION_LITERAL = re.compile(r'(?<![\w.])\d+\.\d+(?:\.\d+)*(?![\w.])')
URL_LITERAL = re.compile(r'\b[a-z][a-z0-9+.-]*://', re.IGNORECASE)
HASH_LITERAL = re.compile(r'(?<![0-9A-Fa-f])[0-9A-Fa-f]{64}(?![0-9A-Fa-f])')
OTHER_INSTALL = re.compile(r'\b(Install|Save|Update|Find)-(Module|PSResource|Package)\b'
                           r'|\bRegister-PS(Resource)?Repository\b|\bnuget(\.exe)?\s+install\b', re.IGNORECASE)
ANY_DOWNLOAD = re.compile(r'\b(Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|iwr|irm|curl|wget|bitsadmin)\b'
                          r'|\b(WebClient|HttpClient)\b', re.IGNORECASE)
DOWNLOAD = re.compile(r'^\s*Invoke-WebRequest\s+-Uri\s+\$(\w+)\s+-OutFile\s+\$(\w+)\b')
HASHES = re.compile(r'^\s*\$(\w+)\s*=\s*\(Get-FileHash\s+-LiteralPath\s+\$(\w+)\s+-Algorithm\s+SHA256\)\.Hash\b')
COMPARES = re.compile(r'^\s*if\s*\(\s*\$(\w+)\s+-[ci]?ne\s+\$(\w+)\s*\)\s*\{\s*$')
THROWS = re.compile(r'^\s*throw\b')
CLOSES = re.compile(r'^\s*\}\s*$')
UNPACKS = re.compile(r'^\s*Expand-Archive\s+-LiteralPath\s+\$(\w+)\s+-DestinationPath\s+\$(\w+)\b')
ANY_UNPACK = re.compile(r'\bExpand-Archive\b|\bZipFile\b|\btar\s+-|\b7z\b', re.IGNORECASE)
REMOVES = re.compile(r'^\s*Remove-Item\s+-LiteralPath\s+\$(\w+)\s+-Force\s*$')
ASSIGNS = re.compile(r'^\s*\$(\w+)\s*=')
USER_MODULES = re.compile(r"^\s*\$(\w+)\s*=\s*Join-Path\s+\(\[Environment\]::GetFolderPath\('MyDocuments'\)\)"
                          r"\s+'PowerShell'\s+'Modules'\s*$")
VERSION_FOLDER = re.compile(r"^\s*\$(\w+)\s*=\s*Join-Path\s+\$(\w+)\s+'Pester'\s+\"\$(\w+)\"\s*$")
INSTALLS_PESTER = re.compile(r'\b(Install|Save|Update)-(Module|PSResource)\b.*\bPester\b', re.IGNORECASE)


def is_true(value):
    return value is True or (isinstance(value, str) and value.strip().lower() == 'true')


def runs_pester_inline(step):
    body = step.get('run')
    return isinstance(body, str) and any(RUNS_PESTER.search(line) for line in code_lines(body))


def installs_pester_inline(step):
    body = step.get('run')
    return isinstance(body, str) and any(INSTALLS_PESTER.search(line) for line in code_lines(body))


def powershell_code(text):
    """A PowerShell file's lines with its block comments and full-line comments left out."""
    return '\n'.join(code_lines(re.sub(r'<#.*?#>', '', text, flags=re.DOTALL)))


def mentions(name, line):
    return re.search(r'\$' + re.escape(name) + r'\b', line) is not None


def first_match(pattern, lines, start=0):
    """The index and match of the first line from start on that the pattern matches, or (None, None)."""
    for index in range(start, len(lines)):
        match = pattern.search(lines[index])
        if match:
            return index, match
    return None, None


def hash_check_problems(lines, pins):
    """What is wrong with the download, the SHA-256 check and the unpack, in that order, and the unpack match."""
    url_name, expected = pins[PESTER_URL_PIN], pins[PESTER_SHA_PIN]
    downloads = [index for index, line in enumerate(lines) if ANY_DOWNLOAD.search(line)]
    at_download, download = first_match(DOWNLOAD, lines)
    if download is None or downloads != [at_download] or download.group(1) != url_name:
        return ['the shared action does not download the package exactly once, on one line '
                'Invoke-WebRequest -Uri $%s -OutFile $<package>, $%s being %s, and with nothing else'
                % (url_name, url_name, PESTER_URL_PIN)], None
    package = download.group(2)
    at_hash, hashed = first_match(HASHES, lines, at_download + 1)
    if hashed is None or hashed.group(2) != package:
        return ['the shared action does not hash the downloaded file with $<actual> = (Get-FileHash '
                '-LiteralPath $%s -Algorithm SHA256).Hash after the download, so nothing checks it against %s'
                % (package, PESTER_SHA_PIN)], None
    actual = hashed.group(1)
    at_compare = next((index for index in range(at_hash + 1, len(lines))
                       if COMPARES.match(lines[index])
                       and set(COMPARES.match(lines[index]).groups()) == {actual, expected}), None)
    if at_compare is None:
        return ['the shared action does not compare $%s with $%s, the value of %s, in a block that opens with '
                'if ($%s -ne $%s) { after it hashes the file'
                % (actual, expected, PESTER_SHA_PIN, actual, expected)], None
    at_throw, _ = first_match(THROWS, lines, at_compare + 1)
    between = lines[at_compare + 1:at_throw] if at_throw is not None else []
    if (at_throw is None or any(not REMOVES.match(line) for line in between)
            or not (mentions(expected, lines[at_throw]) and mentions(actual, lines[at_throw]))
            or at_throw + 1 >= len(lines) or not CLOSES.match(lines[at_throw + 1])):
        return ['the shared action does not stop on a SHA-256 mismatch: the block that compares $%s with $%s must '
                'hold only Remove-Item -LiteralPath $<file> -Force lines and then one throw that names both $%s and '
                '$%s, closing right after it' % (actual, expected, expected, actual)], None
    problems = []
    unpacks = [index for index, line in enumerate(lines) if ANY_UNPACK.search(line)]
    at_unpack, unpack = first_match(UNPACKS, lines)
    if unpack is None or unpacks != [at_unpack] or unpack.group(1) != package:
        problems.append('the shared action does not unpack the package exactly once, with Expand-Archive -LiteralPath '
                        '$%s -DestinationPath $<the version folder>, and with nothing else' % package)
    elif at_unpack < at_throw:
        problems.append('the shared action unpacks $%s at code line %d, before the SHA-256 check that stops a '
                        'mismatch at code line %d' % (package, at_unpack + 1, at_throw + 1))
    allowed = {at_download, at_hash, at_unpack}
    for index, line in enumerate(lines):
        assignment = ASSIGNS.match(line)
        if (mentions(package, line) and index not in allowed and not REMOVES.match(line)
                and not (assignment and assignment.group(1) == package)):
            problems.append('the shared action hands the package $%s to something other than the download, the '
                            'SHA-256, the unpack or Remove-Item, at code line %d: %s'
                            % (package, index + 1, line.strip()))
    return problems, unpack


def module_folder_problems(lines, pins, unpack):
    """What is wrong with where the package is unpacked: Pester/<version> under the CurrentUser module path."""
    modules = next((match.group(1) for match in map(USER_MODULES.match, lines) if match), None)
    folders = [match for match in map(VERSION_FOLDER.match, lines) if match]
    folder = next((match.group(1) for match in folders
                   if match.group(2) == modules and match.group(3) == pins[PESTER_PIN]), None)
    if modules is None or folder is None:
        return ["the shared action does not lay Pester out in a folder named for the pinned version on the "
                "CurrentUser module path, $<modules> = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "
                "'PowerShell' 'Modules' and then $<folder> = Join-Path $<modules> 'Pester' \"$%s\""
                % pins[PESTER_PIN]]
    if unpack is not None and unpack.group(2) != folder:
        return ['the shared action unpacks into $%s, not into $%s, the folder named for the pinned version'
                % (unpack.group(2), folder)]
    return []


def action_install_problems(code):
    """Every way the shared action stops installing exactly the package gate_pester_url and gate_pester_sha256 pin."""
    lines = code.splitlines()
    problems = []
    other = next((match.group(0) for match in map(OTHER_INSTALL.search, lines) if match), None)
    if other:
        problems.append('the shared action installs Pester another way, through %s, which checks no SHA-256 of the '
                        'file the gate image gets' % other)
    url = URL_LITERAL.search(code)
    if url:
        problems.append('the shared action writes an address of its own, starting %s, where only %s may name the '
                        'package' % (url.group(0), PESTER_URL_PIN))
    digest = HASH_LITERAL.search(code)
    if digest:
        problems.append('the shared action writes the SHA-256 %s itself, where only %s may name it'
                        % (digest.group(0), PESTER_SHA_PIN))
    pins = {}
    for match in map(ASSIGNS_PIN.match, lines):
        if match:
            pins.setdefault(match.group(2), match.group(1))
    missing = sorted(ACTION_PINS - set(pins))
    if missing:
        problems.append('the shared action does not read %s into a variable of its own, on a line '
                        '$<name> = Get-PinnedValue -Key <pin>' % ', '.join(missing))
        return problems
    checked, unpack = hash_check_problems(lines, pins)
    return problems + checked + module_folder_problems(lines, pins, unpack)


def pester_pin_problems(action_code, script_code):
    """Every way the shared action and the shared script stop running exactly the pinned Pester."""
    problems = []
    for label, code, allowed in (('the shared action', action_code, ACTION_PINS),
                                 ('the shared script', script_code, SCRIPT_PINS)):
        if not READS_PIN.search(code):
            problems.append('%s does not read the Pester version with Get-PinnedValue -Key %s' % (label, PESTER_PIN))
        read = {match.group(1) or 'a pin it does not name with -Key' for match in READS_ANY_PIN.finditer(code)}
        if read - allowed:
            problems.append('%s reads the pins %s, where it may read only %s'
                            % (label, ', '.join(sorted(read)), ', '.join(sorted(allowed))))
        if not EXACT_SELECTION.search(code):
            problems.append('%s does not pick Pester by an exact .Version -eq [Version]$<pin> match' % label)
        loose = LOOSE_SELECTION.search(code)
        if loose:
            problems.append('%s accepts a Pester other than the pinned one through %s' % (label, loose.group(0)))
        literal = VERSION_LITERAL.search(code)
        if literal:
            problems.append('%s writes the version %s itself, a second literal beside the pin'
                            % (label, literal.group(0)))
    problems.extend(action_install_problems(action_code))
    if 'PESTER_ABSENT' in script_code:
        problems.append('the shared script answers a missing Pester with PESTER_ABSENT, which the gate reads as a '
                        'skip, where a missing pinned Pester must be a PROBLEM line and a failed verdict')
    return problems


def planted_pin_bodies():
    """Planted action and script bodies, each with a fragment the problems for it must hold, None for sound."""
    hash_line = '$actual = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()'
    unpack_line = 'Expand-Archive -LiteralPath $package -DestinationPath $target -Force'
    sound_action = '\n'.join((
        "Import-Module (Join-Path $env:GITHUB_WORKSPACE 'setup' 'pinned_values' 'PinnedValues.psm1')",
        '$version = [Version](Get-PinnedValue -Key gate_pester_version)',
        '$url = Get-PinnedValue -Key gate_pester_url',
        '$expected = Get-PinnedValue -Key gate_pester_sha256',
        "$modules = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell' 'Modules'",
        '$target = Join-Path $modules \'Pester\' "$version"',
        "if (-not (Test-Path -LiteralPath (Join-Path $target 'Pester.psd1'))) {",
        '  $package = Join-Path $env:RUNNER_TEMP "Pester.$version.zip"',
        '  Invoke-WebRequest -Uri $url -OutFile $package',
        '  ' + hash_line,
        '  if ($actual -ne $expected) {',
        '    Remove-Item -LiteralPath $package -Force',
        '    throw "expected $expected, actual $actual"',
        '  }',
        '  ' + unpack_line,
        '  Remove-Item -LiteralPath $package -Force',
        '}',
        '$first = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -eq [Version]$version }',
    ))
    sound_script = '\n'.join((
        '$wanted = Get-PinnedValue -Key gate_pester_version',
        '$pester = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -eq [Version]$wanted }',
        'Write-Output "PESTER version=$($pester.Version)"',
    ))
    gallery_action = '\n'.join((
        '$version = [Version](Get-PinnedValue -Key gate_pester_version)',
        '$present = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -eq [Version]$version }',
        'if (-not $present) { Install-Module -Name Pester -RequiredVersion $version -Scope CurrentUser -Force }',
    ))
    no_hash = '\n'.join(line for line in sound_action.splitlines()
                        if line.strip() not in (hash_line, 'if ($actual -ne $expected) {',
                                                'Remove-Item -LiteralPath $package -Force',
                                                'throw "expected $expected, actual $actual"', '}')) + '\n}'
    unpack_first = sound_action.replace('  ' + unpack_line + '\n', '').replace(
        '  ' + hash_line, '  ' + unpack_line + '\n  ' + hash_line)
    return {
        'sound': (sound_action, sound_script, None),
        'action-gallery': (gallery_action, sound_script, 'installs Pester another way, through Install-Module'),
        'action-minimum': ('\n'.join((
            "$mod = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [Version]'5.0.0' }",
            'if (-not $mod) { Install-Module -Name Pester -MinimumVersion 5.5.0 -Force -Scope CurrentUser }',
        )), sound_script, 'accepts a Pester other than the pinned one'),
        'action-literal': (sound_action.replace('[Version](Get-PinnedValue -Key gate_pester_version)', "'5.9.1'"),
                           sound_script, 'writes the version 5.9.1 itself'),
        'action-save-module': (sound_action + '\nSave-Module -Name Pester -RequiredVersion $version -Path $modules',
                               sound_script, 'installs Pester another way, through Save-Module'),
        'action-url-literal': (sound_action.replace(
            'Get-PinnedValue -Key gate_pester_url',
            "'https://www.powershellgallery.com/api/v2/package/Pester/' + $version"),
            sound_script, 'writes an address of its own'),
        'action-hash-literal': (sound_action.replace(
            'Get-PinnedValue -Key gate_pester_sha256',
            "'8dd4060fc3bc895f05bd655e4ab82abe346de54a4e6415dfb727cc8378672b69'"),
            sound_script, 'writes the SHA-256 8dd4060fc3bc895f05bd655e4ab82abe346de54a4e6415dfb727cc8378672b69'),
        'action-no-hash': (no_hash, sound_script, 'does not hash the downloaded file'),
        'action-unpack-first': (unpack_first, sound_script, 'before the SHA-256 check'),
        'action-warns': (sound_action.replace('throw "expected', 'Write-Warning "expected'),
                         sound_script, 'does not stop on a SHA-256 mismatch'),
        'action-other-url-pin': (sound_action.replace('-Key gate_pester_url', '-Key gate_pwsh_linux_x86_64_url'),
                                 sound_script, 'reads the pins'),
        'action-other-sha-pin': (sound_action.replace('-Key gate_pester_sha256', '-Key gate_pwsh_linux_x86_64_sha256'),
                                 sound_script, 'reads the pins'),
        'action-flat-folder': (sound_action.replace('\'Pester\' "$version"', "'Pester'"),
                               sound_script, 'a folder named for the pinned version'),
        'script-newest': (sound_action, '\n'.join((
            '$pester = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -ge 5 } |',
            '    Sort-Object Version -Descending | Select-Object -First 1',
            "if (-not $pester) { Write-Output 'PESTER_ABSENT none'; exit 1 }",
        )), 'the shared script accepts a Pester other than the pinned one'),
        'script-literal': (sound_action, sound_script.replace('Get-PinnedValue -Key gate_pester_version', "'5.9.1'"),
                           'the shared script writes the version 5.9.1 itself'),
        'script-other-pin': (sound_action, sound_script + '\n$url = Get-PinnedValue -Key gate_pester_url',
                             'the shared script reads the pins'),
    }


def needs_of(job):
    needs = job.get('needs')
    if isinstance(needs, str):
        return [needs]
    if isinstance(needs, list):
        return [name for name in needs if isinstance(name, str)]
    return []


def shared_step(job):
    for index, step in enumerate(steps_of(job)):
        if local_uses(step) == SHARED_USES:
            return index, step
    return None, None


def upstream_runs_tests(name, jobs):
    queue, seen = needs_of(jobs[name]), set()
    while queue:
        other = queue.pop()
        if other in seen or not isinstance(jobs.get(other), dict):
            continue
        seen.add(other)
        _, step = shared_step(jobs[other])
        if step is not None and not is_true(step.get('continue-on-error')):
            return True
        queue.extend(needs_of(jobs[other]))
    return False


def job_problems(label, name, jobs, actions):
    """None for a job that never installs with setup.ps1, otherwise the list of what is wrong."""
    steps = steps_of(jobs[name])
    wizard_at = next((i for i, step in enumerate(steps) if starts_wizard(step, actions)), None)
    if wizard_at is None:
        return None
    where = '%s job %s' % (label, name)
    tests_at, tests = shared_step(jobs[name])
    if tests_at is None:
        if upstream_runs_tests(name, jobs):
            return []
        return ['%s starts setup.ps1 to install at step %d and runs %s neither before it nor in a '
                'job it needs' % (where, wizard_at + 1, SHARED_USES)]
    problems = []
    if tests_at > wizard_at:
        problems.append('%s runs %s at step %d, after it starts setup.ps1 to install at step %d'
                        % (where, SHARED_USES, tests_at + 1, wizard_at + 1))
    if is_true(tests.get('continue-on-error')):
        problems.append('%s runs %s under continue-on-error, so a failed test does not stop the install'
                        % (where, SHARED_USES))
    for index in range(tests_at + 1, len(steps)):
        condition = steps[index].get('if')
        if (starts_wizard(steps[index], actions) and isinstance(condition, str)
                and OVERRIDES_FAILURE.search(condition)):
            problems.append('%s starts setup.ps1 at step %d under if: %s, which runs it after a failed test'
                            % (where, index + 1, condition))
    return problems


def analyse(workflows, actions):
    """Returns the install jobs found and every (label, problem) pair."""
    install_jobs, problems = [], []
    for label, doc in sorted(workflows.items()):
        jobs = {name: job for name, job in ((doc or {}).get('jobs') or {}).items() if isinstance(job, dict)}
        for name in jobs:
            found = job_problems(label, name, jobs, actions)
            if found is not None:
                install_jobs.append('%s:%s' % (label, name))
                problems.extend((label, text) for text in found)
            for index, step in enumerate(steps_of(jobs[name])):
                if runs_pester_inline(step):
                    problems.append((label, '%s job %s runs Pester itself at step %d instead of calling %s'
                                     % (label, name, index + 1, SHARED_USES)))
                if installs_pester_inline(step):
                    problems.append((label, '%s job %s installs Pester itself at step %d, beside the pinned one '
                                     '%s installs' % (label, name, index + 1, SHARED_USES)))
    for uses, doc in sorted(actions.items()):
        if uses == SHARED_USES:
            continue
        for index, step in enumerate(steps_of((doc or {}).get('runs'))):
            if runs_pester_inline(step):
                problems.append((uses, 'the action %s runs Pester itself at step %d instead of calling %s'
                                 % (uses, index + 1, SHARED_USES)))
            if installs_pester_inline(step):
                problems.append((uses, 'the action %s installs Pester itself at step %d, beside the pinned one '
                                 '%s installs' % (uses, index + 1, SHARED_USES)))
    return install_jobs, problems


def planted():
    wizard = {'shell': 'pwsh', 'run': '& ./setup/setup.ps1 -NonInteractive -Software all'}
    tests = {'uses': SHARED_USES}
    checkout = {'uses': 'actions/checkout@v4'}

    def one_job(*steps, **extra):
        return {'jobs': {'install': dict({'runs-on': 'windows-latest', 'steps': list(steps)}, **extra)}}

    workflows = {
        'no-tests.yml': one_job(checkout, wizard),
        'late.yml': one_job(checkout, wizard, tests),
        'soft.yml': one_job(checkout, dict(tests, **{'continue-on-error': True}), wizard),
        'always.yml': one_job(checkout, tests, dict(wizard, **{'if': 'always()'})),
        'inline.yml': one_job(checkout, {'shell': 'pwsh', 'run': '$r = Invoke-Pester -Path x'}),
        'hidden.yml': one_job(checkout, {'uses': './.github/actions/wrapper'}),
        'installs.yml': one_job(checkout, {'shell': 'pwsh',
                                           'run': 'Install-Module -Name Pester -RequiredVersion 5.9.1 -Force'}),
        'sound-steps.yml': one_job(checkout, tests, wizard),
        'sound-needs.yml': {'jobs': {
            'unit': {'runs-on': 'windows-latest', 'steps': [checkout, tests]},
            'gate': {'runs-on': 'ubuntu-latest', 'needs': 'unit', 'if': 'always()', 'steps': []},
            'install': {'runs-on': 'windows-latest', 'needs': ['gate'],
                        'if': "!cancelled() && needs.gate.outputs.ok == 'true'", 'steps': [checkout, wizard]},
        }},
        'sound-plan.yml': one_job(checkout, {'shell': 'pwsh',
                                             'run': '& ./setup/setup.ps1 -NonInteractive -PrintPlan\n'
                                                    'if ($LASTEXITCODE -ne 0) { throw "setup.ps1 exited" }'}),
        'sound-comment.yml': one_job(checkout, {'shell': 'pwsh',
                                                'run': '# setup/setup.ps1 runs in another job\nWrite-Host ok'}),
    }
    actions = {'./.github/actions/wrapper': {'runs': {'using': 'composite', 'steps': [wizard]}}}
    return workflows, actions


lines = []

expected = {'no-tests.yml', 'late.yml', 'soft.yml', 'always.yml', 'inline.yml', 'hidden.yml', 'installs.yml'}
_, planted_problems = analyse(*planted())
named = {label for label, _ in planted_problems}
if named == expected and len(planted_problems) == len(expected):
    lines.append('OK the reader names exactly the seven planted defects and none of the four sound jobs')
else:
    lines.append('FAIL the reader misreads planted workflows, so nothing it says about the real ones '
                 'can be trusted :: expected one problem each in %s, got %s'
                 % (', '.join(sorted(expected)), ' | '.join(text for _, text in planted_problems) or 'none'))

shared = None
if SHARED_FILE.exists():
    shared = yaml.safe_load(SHARED_FILE.read_text(encoding='utf-8'))
runs = (shared or {}).get('runs') if isinstance(shared, dict) else None
bodies = '\n'.join('\n'.join(code_lines(step['run'])) for step in steps_of(runs)
                   if isinstance(step.get('run'), str))
if not isinstance(runs, dict) or runs.get('using') != 'composite':
    lines.append('FAIL the shared action is not a composite action :: %s is missing or does not say '
                 'using: composite' % SHARED_FILE.as_posix())
elif INVOKES_PESTER.search(bodies) or SHARED_SCRIPT.as_posix() not in bodies:
    lines.append('FAIL the shared action does not hand the Windows unit tests to the one script the gate '
                 'runs too :: %s must start %s and run no Invoke-Pester or New-PesterConfiguration of its '
                 'own, so the runner and the gate cannot judge a run differently'
                 % (SHARED_FILE.as_posix(), SHARED_SCRIPT.as_posix()))
else:
    lines.append('OK %s hands the Windows unit tests to %s' % (SHARED_FILE.as_posix(), SHARED_SCRIPT.as_posix()))

local_check = '\n'.join(code_lines(LOCAL_CHECK.read_text(encoding='utf-8'))) if LOCAL_CHECK.exists() else ''
if INVOKES_PESTER.search(local_check) or SHARED_SCRIPT.name not in local_check:
    lines.append('FAIL the gate does not run the Windows unit tests through the script the shared action '
                 'runs :: %s must start %s and run no Invoke-Pester or New-PesterConfiguration of its own'
                 % (LOCAL_CHECK.as_posix(), SHARED_SCRIPT.name))
else:
    lines.append('OK %s runs the Windows unit tests through %s' % (LOCAL_CHECK.as_posix(), SHARED_SCRIPT.name))

script = '\n'.join(code_lines(SHARED_SCRIPT.read_text(encoding='utf-8'))) if SHARED_SCRIPT.exists() else ''
excluded = EXCLUDED_TAGS.search(script)
excluded_names = sorted(re.findall(r"'([^']*)'", excluded.group(1))) if excluded else []
if not INVOKES_PESTER.search(script) or "'WindowsSoftware.Tests.ps1'" not in script:
    lines.append('FAIL the shared script does not run the Windows unit tests :: %s runs no Invoke-Pester '
                 'over e2e/tier1/windows/WindowsSoftware.Tests.ps1' % SHARED_SCRIPT.as_posix())
elif excluded_names != ['Network', 'Slow'] or not FILTER_READS_TAGS.search(script):
    found = ('Filter.ExcludeTag is not set to $excludedTags alone' if excluded_names == ['Network', 'Slow']
             else '$excludedTags holds %s' % (', '.join(excluded_names) or 'nothing it can read'))
    lines.append("FAIL the shared script does not leave out exactly the Slow and Network tagged tests :: %s "
                 "must set $excludedTags = @('Slow', 'Network') and hand Filter.ExcludeTag that variable, "
                 'because the Chocolatey bootstrap would otherwise run before the install it is meant to '
                 'stop, and any other tag would drop tests the verdict counts as left out by design, but %s'
                 % (SHARED_SCRIPT.as_posix(), found))
else:
    lines.append('OK %s runs WindowsSoftware.Tests.ps1 without the Slow and Network tagged tests'
                 % SHARED_SCRIPT.as_posix())

pin_misread = []
pin_planted = planted_pin_bodies()
for label, (planted_action, planted_script, fragment) in sorted(pin_planted.items()):
    found = pester_pin_problems(planted_action, planted_script)
    if fragment is None and found:
        pin_misread.append('%s got %s' % (label, ' | '.join(found)))
    elif fragment is not None and not any(fragment in problem for problem in found):
        pin_misread.append("%s got no problem holding '%s', only %s" % (label, fragment, ' | '.join(found) or 'none'))
if not pin_misread:
    lines.append('OK the pin reader names each of the %d planted pin defects by its own problem and nothing in '
                 'the sound pair' % (len(pin_planted) - 1))
else:
    lines.append('FAIL the pin reader misreads planted bodies, so nothing it says about the real ones can be '
                 'trusted :: %s' % ' || '.join(pin_misread))

if not EXACT_VERSION.match(PINNED_VERSION):
    lines.append('FAIL %s does not name one exact Pester version, so the runner and the gate cannot be held to '
                 "it :: it reads '%s'" % (PESTER_PIN, PINNED_VERSION))
else:
    script_text = SHARED_SCRIPT.read_text(encoding='utf-8') if SHARED_SCRIPT.exists() else ''
    pin_problems = pester_pin_problems(bodies, powershell_code(script_text))
    if pin_problems:
        lines.append('FAIL the Windows runner or the gate can run a Pester other than the pinned %s, or one whose '
                     'file was not checked by %s :: %s' % (PINNED_VERSION, PESTER_SHA_PIN, ' | '.join(pin_problems)))
    else:
        lines.append('OK %s installs Pester %s only from the package %s names, after checking it against %s, and '
                     '%s imports exactly that version, with no version, address or hash of their own'
                     % (SHARED_FILE.as_posix(), PINNED_VERSION, PESTER_URL_PIN, PESTER_SHA_PIN,
                        SHARED_SCRIPT.as_posix()))

workflows = {}
for path in sorted(pathlib.Path('.github/workflows').glob('*.y*ml')):
    workflows[path.as_posix()] = yaml.safe_load(path.read_text(encoding='utf-8'))
actions = {}
for path in sorted(pathlib.Path('.github/actions').glob('*/action.y*ml')):
    actions['./' + path.parent.as_posix()] = yaml.safe_load(path.read_text(encoding='utf-8'))

install_jobs, problems = analyse(workflows, actions)
if not workflows:
    lines.append('FAIL no workflow was read, so this check proves nothing :: .github/workflows holds no '
                 '.yml or .yaml file')
elif not install_jobs:
    lines.append('FAIL no workflow job starts setup.ps1 to install, so this check proves nothing :: read '
                 '%d workflow(s)' % len(workflows))
elif problems:
    lines.append('FAIL a job starts setup.ps1 to install without the Windows unit tests stopping it first, '
                 'or a workflow runs Pester outside the shared action :: %s'
                 % ' | '.join(text for _, text in problems))
else:
    lines.append('OK all %d job(s) that start setup.ps1 to install run %s first, and no workflow runs '
                 'Pester outside it: %s' % (len(install_jobs), SHARED_USES, ', '.join(install_jobs)))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "Windows unit tests before the install"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) claim="${line#FAIL }"
               fail "${claim%% :: *}" "${claim#* :: }" ;;
        *)     [[ -n "${line}" ]] && fail "the Windows unit tests check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "Windows unit tests before the install"
