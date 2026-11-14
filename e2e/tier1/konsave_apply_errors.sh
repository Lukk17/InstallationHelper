#!/usr/bin/env bash
#
# Tier 1: the task that imports and applies the Konsave profile fails when konsave reports a failure.
#
# konsave wraps every one of its functions in a handler that catches the exception, writes it to
# ~/.cache/konsave_log.txt, prints "Konsave: <error>" and returns, so the command exits 0 after a
# failure halfway through, a permission refused or a parent folder missing, and still prints
# "Profile successfully imported!" or "Profile applied successfully!". Until 2026-11-14 "Import and
# apply Konsave profile" in setup/ansible/roles/kde_plasma_setup/tasks/configure_kde.yaml looked at the
# exit code alone, so such a run passed with a desktop half applied, docs/regression_ledger.md 10.356.
#
# The task is lifted out of the shipped file as it is, with become taken off, and run with
# ansible-playbook against a fixture home whose ~/.local/bin holds a fake konsave, which the task puts
# first on PATH itself. The fake is proven to be the konsave that PATH finds before anything runs,
# defect class 16 in docs/regression_ledger.md, and every run proves which calls it got. It behaves as
# konsave 2.3.0 did in a throwaway container on 2026-11-14 and prints what it printed there, the same
# -i and -a lines the kde-full cell of sweep 39850886667 logged: -i stores the profile under
# ~/.config/konsave/profiles and refuses one stored already with "A profile with this name already
# exists" and exit 0, -r removes the stored copy, and every caught error is followed by a line naming
# ~/.cache/konsave_log.txt. Each case is run on a fresh home:
#   1. the output of a real run: the task succeeds and calls -i then -a.
#   2. two runs in a row: both succeed, the second removes the copy the first stored and imports the
#      profile again, so konsave ends up holding the second import, docs/regression_ledger.md 10.358.
#   3. a "Konsave: " error line among the lines of the import, on stdout, where konsave prints: the
#      task fails.
#   4. the same error line on stderr: the task fails.
#   5. an import that exits 1: the task fails, and the apply is never run.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd ansible-playbook
require_python "the Konsave profile task fails when konsave reports a failure" "konsave apply errors"

info "Tier 1: the Konsave profile task fails when konsave reports a failure"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

report_status=0
report="$("${PYTHON}" - "${ANSIBLE_DIR}" "${work}" <<'PYEOF'
import os
import pathlib
import shutil
import stat
import subprocess
import sys

import yaml

ANSIBLE = pathlib.Path(sys.argv[1])
WORK = pathlib.Path(sys.argv[2])
KDE_TASKS = ANSIBLE / 'roles' / 'kde_plasma_setup' / 'tasks' / 'configure_kde.yaml'
TASK_NAME = 'Import and apply Konsave profile'
REAL_OUTPUT = '''Konsave: Importing profile. It might take a minute or two...
Konsave: Importing "plasma"...
Konsave: Importing "kwin"...
Konsave: Importing "konsole"...
Konsave: Importing "fonts"...
Konsave: Importing "color-schemes"...
Konsave: Importing "aurorae"...
Konsave: Importing "icons"...
Konsave: Importing "wallpapers"...
Konsave: Importing "yakuake"...
Konsave: Importing ".fonts"...
Konsave: Importing ".themes"...
Konsave: Importing ".icons"...
Konsave: Profile successfully imported!
Konsave: copying files...
Konsave: Profile applied successfully! Please log-out and log-in to see the changes completely!
'''
IMPORT_LINES, APPLY_LINES = REAL_OUTPUT.splitlines()[:14], REAL_OUTPUT.splitlines()[14:]
REMOVE_LINES = ['Konsave: removing profile...', 'Konsave: removed profile successfully']
ERROR_LINE = "Konsave: [Errno 13] Permission denied: '/home/fixture/.local/share/icons/Dracula'"
lines = []


def strip_become(node):
    if isinstance(node, dict):
        return {key: strip_become(value) for key, value in node.items() if key not in ('become', 'become_user')}
    if isinstance(node, list):
        return [strip_become(value) for value in node]
    return node


tasks = yaml.safe_load(KDE_TASKS.read_text(encoding='utf-8')) or []
task = next((t for t in tasks if isinstance(t, dict) and t.get('name') == TASK_NAME), None)
if task is None:
    lines.append('FAIL %s holds no task named "%s", so nothing here is proven' % (KDE_TASKS.as_posix(), TASK_NAME))
    print('\n'.join(lines))
    sys.exit(0)
task = strip_become(dict(task))
task.pop('when', None)
(WORK / 'ansible').mkdir()
(WORK / 'ansible' / 'konsave.yaml').write_text(yaml.safe_dump([task], sort_keys=False), encoding='utf-8')
(WORK / 'ansible' / 'play.yaml').write_text(yaml.safe_dump([{
    'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
    'tasks': [{'name': 'The shipped Konsave apply', 'ansible.builtin.include_tasks': 'konsave.yaml'}],
}], sort_keys=False), encoding='utf-8')


def shlex_quote(text):
    return "'" + text.replace("'", "'\\''") + "'"


def fake_konsave(home, case):
    """A konsave that keeps its stored profile as konsave 2.3.0 does and records each call in calls.log."""
    import_out, import_err, import_rc = IMPORT_LINES, [], 0
    if case == 'error on stdout':
        import_out = IMPORT_LINES[:8] + [ERROR_LINE] + IMPORT_LINES[8:]
    elif case == 'error on stderr':
        import_err = [ERROR_LINE]
    elif case == 'import exits 1':
        import_rc = 1
    log_line = 'Please check the log at %s/.cache/konsave_log.txt for more details.' % home
    quoted = lambda texts: ' '.join(shlex_quote(text) for text in texts) or "''"
    script = home / '.local' / 'bin' / 'konsave'
    script.parent.mkdir(parents=True)
    script.write_text(
        '#!/bin/bash\n'
        'printf "%%s\\n" "$*" >> %(calls)s\n'
        'store=%(store)s\n'
        'case "$1" in\n'
        '  -r) if [[ -d "${store}" ]]; then rm -r -- "${store}"; printf "%%s\\n" %(removed)s\n'
        '      else printf "%%s\\n" %(not_saved)s; fi; exit 0 ;;\n'
        '  -i) if [[ -d "${store}" ]]; then printf "%%s\\n" %(exists)s; exit 0; fi\n'
        '      count=$(( $(cat %(imports)s 2>/dev/null || echo 0) + 1 )); printf "%%s\\n" "${count}" > %(imports)s\n'
        '      mkdir -p "${store}"; printf "import %%s\\n" "${count}" > "${store}/imported"\n'
        '      printf "%%s\\n" %(import_out)s; %(import_err)s exit %(import_rc)d ;;\n'
        '  -a) printf "%%s\\n" %(apply_out)s; exit 0 ;;\n'
        'esac\n'
        'exit 2\n' % {
            'calls': shlex_quote(str(home / 'calls.log')), 'imports': shlex_quote(str(home / 'imports.count')),
            'store': shlex_quote(str(home / '.config' / 'konsave' / 'profiles' / 'lukk_desktop_profile')),
            'removed': quoted(REMOVE_LINES), 'not_saved': quoted(['Konsave: No profile saved yet.', log_line]),
            'exists': quoted(['Konsave: A profile with this name already exists', log_line]),
            'import_out': quoted(import_out), 'import_rc': import_rc, 'apply_out': quoted(APPLY_LINES),
            'import_err': ('printf "%%s\\n" %s >&2;' % quoted(import_err)) if import_err else ''},
        encoding='utf-8')
    script.chmod(script.stat().st_mode | stat.S_IXUSR)
    return script


# Each case is one or more runs of the task on the same home, each with whether it must pass and the
# konsave calls it must make.
CASES = {
    'the output of a real run': [(True, ['-i', '-a'])],
    'two runs in a row': [(True, ['-i', '-a']), (True, ['-r', '-i', '-a'])],
    'error on stdout': [(False, ['-i', '-a'])],
    'error on stderr': [(False, ['-i', '-a'])],
    'import exits 1': [(False, ['-i'])],
}
for case, runs in CASES.items():
    home = WORK / ('home-%d' % len(list(WORK.glob('home-*'))))
    home.mkdir()
    (home / '.cache').mkdir()
    fake = fake_konsave(home, case)
    path = '%s:%s' % (home / '.local' / 'bin', os.environ.get('PATH', ''))
    found = shutil.which('konsave', path=path)
    if found != str(fake):
        lines.append('FAIL in the case "%s" PATH finds konsave at %s, not the fake at %s, so the case was not run'
                     % (case, found, fake))
        continue
    env = dict(os.environ, HOME=str(home), ANSIBLE_STDOUT_CALLBACK='default', ANSIBLE_FORCE_COLOR='0',
               ANSIBLE_NOCOLOR='1', ANSIBLE_LOCALHOST_WARNING='false', ANSIBLE_RETRY_FILES_ENABLED='false',
               ANSIBLE_LOCAL_TEMP=str(WORK / 'ansible-tmp'), ANSIBLE_REMOTE_TEMP=str(WORK / 'ansible-tmp'))
    problems = []
    for number, (should_pass, calls) in enumerate(runs, start=1):
        (home / 'calls.log').write_text('', encoding='utf-8')
        done = subprocess.run(['ansible-playbook', '-i', 'localhost,', str(WORK / 'ansible' / 'play.yaml')],
                              cwd=WORK, env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                              check=False)
        made = [line.split()[0] for line in (home / 'calls.log').read_text(encoding='utf-8').splitlines()]
        if made != calls:
            problems.append('run %d called konsave with %s and %s, exit %d, where it should call %s'
                            % (number, made or 'nothing', 'passed' if done.returncode == 0 else 'failed',
                               done.returncode, calls))
        elif (done.returncode == 0) != should_pass:
            problems.append('run %d %s, exit %d, where it should %s'
                            % (number, 'passed' if done.returncode == 0 else 'failed', done.returncode,
                               'pass' if should_pass else 'fail, because konsave reported a failure and exited 0'))
    imported = home / '.config' / 'konsave' / 'profiles' / 'lukk_desktop_profile' / 'imported'
    if not problems and len(runs) > 1 and (not imported.is_file()
                                           or imported.read_text(encoding='utf-8').strip() != 'import %d' % len(runs)):
        problems.append('the profile konsave holds after %d runs is not the one imported by the last of them' % len(runs))
    if problems:
        lines.append('FAIL in the case "%s" %s' % (case, '. '.join(problems)))
    else:
        lines.append('OK in the case "%s" %s' % (case, ', and '.join(
            'run %d %s calling konsave %s' % (number, 'passed' if ok else 'failed', ' then '.join(calls))
            for number, (ok, calls) in enumerate(runs, start=1))))
print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "konsave apply errors"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a failure konsave reports does not fail the run" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the konsave apply errors check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "konsave apply errors"
