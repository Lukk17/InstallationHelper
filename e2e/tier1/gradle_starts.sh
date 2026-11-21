#!/usr/bin/env bash
#
# Tier 1: the verification counts Gradle as installed only when gradle --version starts.
#
# A Gradle with no usable Java is on disk, resolves on PATH and is in the package database, and it
# cannot run, which is the defect docs/regression_ledger.md 10.351 and 10.360 fixed in the installs.
# setup/ansible/verify_install.yaml only asked whether `command -v gradle` resolved and the Windows
# verification only asked Chocolatey, so both would have passed that Gradle, 10.368. Owner decision of
# 2026-11-21: the verification runs gradle --version as the user, from a login shell on Linux and
# macOS, with a timeout, and counts Gradle installed only when it exits 0 and names a Gradle version
# and a JVM, and the row names both. So this asserts:
#
#   1. verify_install.yaml has one task that runs gradle --version, as non_root_user, through
#      `{{ ih_user_shell }} -lic`, bounded by `{{ ih_timeout }}` and ih_gradle_start_timeout_seconds,
#      with its input closed, under install_gradle and changed_when false, one task that reads its
#      register into ih_start_checks, and an assertion "Assert Gradle starts ..." on it. The gradle
#      (via SDKMAN) row carries start_check gradle, and both the per-application table and the
#      outside-package-manager report read ih_start_checks and can say DOES NOT START.
#   2. those tasks, lifted as shipped with become taken off, run with ansible-playbook against a fake
#      gradle that a login bash finds through the ~/.bash_profile of a fixture home and nothing else
#      finds, proven before anything runs. For every case of gradle_version_fixtures/cases.txt the
#      answer must be started exactly when the exit code is 0 and a version and a JVM are named, the
#      note must name that version and JVM, or the exit code and the last two lines printed, or what
#      was not named, the assertion must pass or fail with it, and the shipped
#      outside-package-manager report must give the gradle (via SDKMAN) row installed or DOES NOT
#      START with the note beside it. A gradle that never ends must be stopped at the timeout, and
#      with install_gradle off nothing may run. The Pester tests of ConvertFrom-GradleVersionOutput
#      read the same cases, so the Linux and the Windows reader give the same answers.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd ansible-playbook
require_python "the verification counts Gradle as installed only when gradle --version starts" "Gradle starts"

info "Tier 1: the verification counts Gradle as installed only when gradle --version starts"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

report_status=0
report="$("${PYTHON}" - "${REPO_ROOT}" "${work}" <<'PYEOF'
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time

import yaml

REPO = pathlib.Path(sys.argv[1])
WORK = pathlib.Path(sys.argv[2])
ANSIBLE = REPO / 'setup' / 'ansible'
COPY = WORK / 'setup' / 'ansible'
FIXTURES = REPO / 'e2e' / 'tier1' / 'gradle_version_fixtures'
SDKMAN_ROW = 'gradle (via SDKMAN)'
lines = []


def walk(node):
    if isinstance(node, list):
        for task in node:
            if isinstance(task, dict):
                yield task
                for section in ('block', 'rescue', 'always'):
                    yield from walk(task.get(section))


def facts_of(task):
    values = task.get('ansible.builtin.set_fact') or task.get('set_fact')
    return values if isinstance(values, dict) else {}


verify = (yaml.safe_load((ANSIBLE / 'verify_install.yaml').read_text(encoding='utf-8')) or [{}])[0]
tasks = list(walk(verify.get('tasks')))

# --- 1. the wiring -------------------------------------------------------------------------------
probes = [t for t in tasks if 'gradle --version' in str(t.get('ansible.builtin.shell', ''))]
timeouts = [t for t in tasks if 'ih_gradle_start_timeout_seconds' in facts_of(t)]
readers = [t for t in tasks if 'ih_start_checks' in facts_of(t)]
asserts = [t for t in tasks if str(t.get('name', '')).startswith('Assert Gradle starts')]
rows = [r for t in tasks for r in (facts_of(t).get('ih_outside_pm_tools') or []) if isinstance(r, dict)]
report_task = [t for t in tasks if 'ih_report' in facts_of(t)]
full_rows = [t for t in tasks if 'ih_outside_pm_report_all' in facts_of(t)]
wiring = []
if len(probes) != 1:
    wiring.append('%d tasks run gradle --version where one is expected' % len(probes))
else:
    probe = probes[0]
    command = str(probe.get('ansible.builtin.shell'))
    for needed in ('{{ ih_timeout }}', '{{ ih_gradle_start_timeout_seconds }}', '{{ ih_user_shell }} -lic',
                   'gradle --version', '</dev/null'):
        if needed not in command:
            wiring.append('the gradle --version task does not hold %s' % needed)
    if probe.get('become_user') != '{{ non_root_user }}' or not probe.get('become'):
        wiring.append('the gradle --version task does not run as non_root_user')
    if probe.get('changed_when') is not False or 'install_gradle' not in str(probe.get('when')):
        wiring.append('the gradle --version task is not changed_when false under install_gradle')
    register = str(probe.get('register', ''))
    if not register or len(readers) != 1 or register not in yaml.safe_dump(readers[0]):
        wiring.append('no single task reads the register %s into ih_start_checks' % (register or 'of the gradle --version task'))
if len(timeouts) != 1:
    wiring.append('%d tasks set ih_gradle_start_timeout_seconds where one is expected' % len(timeouts))
if len(asserts) != 1 or 'ih_start_checks.gradle.ok' not in str(asserts[0].get('ansible.builtin.assert')) \
        or 'install_gradle' not in str(asserts[0].get('when')):
    wiring.append('no single assertion "Assert Gradle starts ..." reads ih_start_checks.gradle.ok under install_gradle')
if [r.get('start_check') for r in rows if r.get('key') == SDKMAN_ROW] != ['gradle']:
    wiring.append('the %s row of ih_outside_pm_tools does not carry start_check gradle' % SDKMAN_ROW)
report_text = yaml.safe_dump(report_task[0]) if len(report_task) == 1 else ''
if '(ih_start_checks | default({}))[key]' not in report_text or 'DOES NOT START' not in report_text:
    wiring.append('the per-application table of ih_report does not read ih_start_checks by key and say DOES NOT START')
full_text = yaml.safe_dump(full_rows[0]) if len(full_rows) == 1 else ''
if 'item.start_check' not in full_text or 'DOES NOT START' not in full_text:
    wiring.append('the outside-package-manager report does not read start_check and say DOES NOT START')
if wiring:
    lines.append('FAIL verify_install.yaml does not ask Gradle to start: %s' % '; '.join(wiring))
    print('\n'.join(lines))
    sys.exit(0)
lines.append('OK verify_install.yaml runs gradle --version as the user from a login shell under a timeout, reads it '
             'into ih_start_checks, asserts on it, and both report rows read it')

# --- 2. the shipped tasks ------------------------------------------------------------------------
cases = []
for raw in (FIXTURES / 'cases.txt').read_text(encoding='utf-8').splitlines():
    text = raw.strip()
    if not text or text.startswith('#'):
        continue
    parts = [p.strip() for p in text.split('|')]
    if len(parts) != 4 or not (FIXTURES / parts[0]).is_file() or not parts[1].lstrip('-').isdigit():
        lines.append('FAIL a line of gradle_version_fixtures/cases.txt is not <output file> | <exit> | <version> | <jvm>: %s' % text)
        continue
    cases.append(parts)
if len(cases) < 4:
    lines.append('FAIL gradle_version_fixtures/cases.txt holds %d cases, fewer than the four it was written with, so '
                 'the reader was not held to them' % len(cases))

for part in ('ansible', 'pinned_values'):
    shutil.copytree(REPO / 'setup' / part, WORK / 'setup' / part, ignore=shutil.ignore_patterns('__pycache__'))


def strip(task):
    return {k: v for k, v in task.items() if k not in ('become', 'become_user')}


gradle_row = [r for r in rows if r.get('key') == SDKMAN_ROW][0]
lifted_assert = dict(asserts[0], ignore_errors=True, register='ih_lifted_assert')
record = ('{{ {"start": ih_start_checks.gradle | default(none), "assert_failed": ih_lifted_assert is failed,'
          ' "assert_skipped": ih_lifted_assert is skipped, "ran": ih_gradle_start_run is not skipped,'
          ' "row": ih_outside_pm_report_all | default([]) | selectattr("key", "equalto", "%s") | first | default(none)}'
          ' | to_json }}' % SDKMAN_ROW)
play = [{
    'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
    'vars': {
        'ih_outside_pm_tools': [gradle_row],
        'ih_sdk_toggles': ['install_java'],
        'ih_outside_pm_report': [{'key': SDKMAN_ROW, 'how': 'fixture', 'on_disk': True, 'in_shell': True,
                                  'in_shell_login_only': False}],
    },
    'tasks': [strip(t) for t in (timeouts[0], probes[0], readers[0])] + [lifted_assert, full_rows[0], {
        'name': 'Record the answers', 'ansible.builtin.copy': {'dest': '{{ ih_case_dir }}/answer.json', 'content': record}}],
}]
(COPY / 'gradle_starts_play.yaml').write_text(yaml.safe_dump(play, sort_keys=False), encoding='utf-8')
(WORK / 'empty.cfg').write_text('[defaults]\n', encoding='utf-8')

base_path = os.environ.get('PATH', '')
HANG_SECONDS = 3
runs = [(name, int(code), version, jvm, True) for name, code, version, jvm in cases] \
    + [('hang', 0, '-', '-', True), ('gradle off', 0, '-', '-', False)]
procs = {}
for index, (name, code, version, jvm, gradle_on) in enumerate(runs):
    case = WORK / ('case-%d' % index)
    home = case / 'home'
    fake_bin = case / 'fake-bin'
    fake_bin.mkdir(parents=True)
    home.mkdir()
    fake = fake_bin / 'gradle'
    if name == 'hang':
        fake.write_text('#!/bin/sh\nexec sleep 60\n', encoding='utf-8')
    else:
        fake.write_text("#!/bin/sh\ncat '%s'\nexit %d\n" % (FIXTURES / name, code), encoding='utf-8')
    fake.chmod(0o755)
    (home / '.bash_profile').write_text('export PATH="%s:$PATH"\n' % fake_bin, encoding='utf-8')
    env = dict(os.environ, HOME=str(home), PATH=base_path, ANSIBLE_CONFIG=str(WORK / 'empty.cfg'),
               ANSIBLE_STDOUT_CALLBACK='default', ANSIBLE_NOCOLOR='1', ANSIBLE_LOCALHOST_WARNING='false',
               ANSIBLE_RETRY_FILES_ENABLED='false')
    # Defect class 16: the login shell the task opens must find the fake, and a plain shell must not.
    login = (subprocess.run(['/bin/bash', '-lic', 'command -v gradle'], env=env, stdin=subprocess.DEVNULL,
                            capture_output=True, text=True).stdout.strip().splitlines() or [''])[-1]
    plain = subprocess.run(['/bin/bash', '-c', 'command -v gradle'], env=env, stdin=subprocess.DEVNULL,
                           capture_output=True, text=True).stdout.strip()
    if login != str(fake) or plain:
        lines.append('FAIL %s: a login bash finds gradle at %s and a plain one at %s, where only the login shell may '
                     'find the fake %s, so no run was started' % (name, login or 'nothing', plain or 'nothing', fake))
        continue
    extra = dict(ih_timeout='timeout', ih_user_shell='/bin/bash', non_root_user=os.environ.get('USER', 'root'),
                 non_root_home=str(home), install_gradle=gradle_on, ih_gradle_sdkman_applies=gradle_on,
                 ih_case_dir=str(case))
    if name == 'hang':
        extra['ih_gradle_start_timeout_seconds'] = HANG_SECONDS
    (case / 'extra.json').write_text(json.dumps(extra), encoding='utf-8')
    procs[index] = (case, time.monotonic(), subprocess.Popen(
        ['ansible-playbook', '-i', 'localhost,', str(COPY / 'gradle_starts_play.yaml'), '-e', '@' + str(case / 'extra.json')],
        cwd=WORK, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True))

for index, (name, code, version, jvm, gradle_on) in enumerate(runs):
    if index not in procs:
        continue
    case, started_at, proc = procs[index]
    output = proc.communicate()[0]
    seconds = time.monotonic() - started_at
    label = '%s, exit %d' % (name, code) if name not in ('hang', 'gradle off') else name
    if proc.returncode != 0 or not (case / 'answer.json').is_file():
        lines.append('FAIL %s: ansible-playbook exited %d before it recorded its answers: %s'
                     % (label, proc.returncode, ' '.join(output.split()[-60:])))
        continue
    answer = json.loads((case / 'answer.json').read_text(encoding='utf-8'))
    start = answer['start'] or {}
    problems = []
    if not gradle_on:
        if answer['ran'] or answer['start'] is not None or not answer['assert_skipped']:
            problems.append('with install_gradle off gradle --version ran %s, the answer is %s and the assertion skipped %s'
                            % (answer['ran'], answer['start'], answer['assert_skipped']))
    else:
        expected_ok = name != 'hang' and code == 0 and version != '-' and jvm != '-'
        ok = str(start.get('ok')).lower() == 'true'
        note = str(start.get('note', ''))
        if ok != expected_ok:
            problems.append('started is %s where %s was expected, note "%s"' % (ok, expected_ok, note))
        if expected_ok and note != 'gradle --version: Gradle %s, JVM %s' % (version, jvm):
            problems.append('the note is "%s", which does not name Gradle %s and JVM %s' % (note, version, jvm))
        if name == 'hang' and (not note.startswith('gradle --version did not finish within %d seconds' % HANG_SECONDS)
                               or seconds > 45):
            problems.append('the gradle that never ends gave "%s" after %.0f seconds' % (note, seconds))
        if not expected_ok and name != 'hang' and code != 0:
            printed = [line for line in (FIXTURES / name).read_text(encoding='utf-8').split('\n') if line.strip()]
            wanted = 'gradle --version exited %d: %s' % (code, ' '.join(printed[-2:]) or 'and printed nothing')
            if note != wanted:
                problems.append('the note is "%s" where "%s", the exit code and the last two lines, was expected'
                                % (note, wanted))
        if not expected_ok and name != 'hang' and code == 0:
            wanted = 'gradle --version exited 0 and named no %s' % ('Gradle version' if version == '-' else 'JVM')
            if note != wanted:
                problems.append('the note is "%s" where "%s" was expected' % (note, wanted))
        if answer['assert_failed'] == expected_ok or answer['assert_skipped']:
            problems.append('the assertion failed %s and skipped %s' % (answer['assert_failed'], answer['assert_skipped']))
        row = answer['row'] or {}
        verdict = 'installed' if expected_ok else 'DOES NOT START'
        if row.get('verdict', '').strip() != verdict or not str(row.get('how', '')).endswith('(%s)' % note):
            problems.append('the %s row reads %s, "%s", where %s with the note was expected'
                            % (SDKMAN_ROW, row.get('verdict'), row.get('how'), verdict))
    if problems:
        lines.append('FAIL %s: %s' % (label, '; '.join(problems)))
    else:
        lines.append('OK %s: %s' % (label, 'nothing ran and the assertion was skipped' if not gradle_on
                                    else '%s, "%s"' % ('started' if str(start.get('ok')).lower() == 'true'
                                                       else 'DOES NOT START', start.get('note'))))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "Gradle starts"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "the verification counts Gradle as installed only when gradle --version starts" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the Gradle start check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "Gradle starts"
