#!/usr/bin/env bash
#
# Tier 1: the desktop session check names exactly what the session would miss, quoted PATH included.
#
# setup/ansible/verify_install.yaml asks the systemd user environment generator what a desktop
# session started now would carry, and "Name what the desktop session environment would be missing"
# compares that with the variables and PATH entries the run owes it. The generator quotes a value
# that holds a space, so the task takes the quotes off PATH before it splits it, and it did that with
# regex_replace('^"(.*)"$', '\\1') inside a folded scalar. In every ansible-core setup/setup.sh
# accepts a Jinja string literal keeps both backslashes, so a quoted PATH became the two characters
# \1 and every PATH entry was reported missing, docs/regression_ledger.md 10.373. So this asserts:
#
#   1. the task, lifted as shipped, run with ansible-playbook on what the Debian trixie generator,
#      systemd 257.13-1~deb13u1, printed in a throwaway container on 2026-11-21 for an environment.d
#      file whose PATH holds a folder with a space, `PATH="/usr/local/bin:/usr/bin:/bin:/opt/my
#      tools/bin:/home/u/.local/bin"`, names nothing missing.
#   2. on the unquoted line the same generator printed for a PATH with no space it names nothing
#      missing, and where a variable and a PATH entry are absent, from a quoted or an unquoted PATH,
#      or where no PATH line is printed, it names exactly those.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd ansible-playbook
require_python "the desktop session check names exactly what the session would miss" "session environment PATH"

info "Tier 1: the desktop session check names exactly what the session would miss, quoted PATH included"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

report_status=0
report="$("${PYTHON}" - "${REPO_ROOT}" "${work}" <<'PYEOF'
import json
import os
import pathlib
import subprocess
import sys

import yaml

REPO = pathlib.Path(sys.argv[1])
WORK = pathlib.Path(sys.argv[2])
VERIFY = REPO / 'setup' / 'ansible' / 'verify_install.yaml'
NAME = 'Name what the desktop session environment would be missing'
QUOTED = 'PATH="/usr/local/bin:/usr/bin:/bin:/opt/my tools/bin:/home/u/.local/bin"'
UNQUOTED = 'PATH=/usr/local/bin:/usr/bin:/bin:/home/u/.local/bin'
JAVA = 'JAVA_HOME=/home/u/.sdkman/candidates/java/current'
SDKMAN_BIN = '/home/u/.sdkman/candidates/java/current/bin'
CASES = [
    ('a quoted PATH that holds everything', [QUOTED, JAVA], ['JAVA_HOME'],
     ['/opt/my tools/bin', '/home/u/.local/bin'], []),
    ('an unquoted PATH that holds everything', [UNQUOTED, JAVA], ['JAVA_HOME'], ['/home/u/.local/bin'], []),
    ('a quoted PATH without one entry and no SDKMAN_DIR', [QUOTED, JAVA], ['JAVA_HOME', 'SDKMAN_DIR'],
     [SDKMAN_BIN, '/opt/my tools/bin'], ['SDKMAN_DIR', 'PATH entry ' + SDKMAN_BIN]),
    ('an unquoted PATH without one entry', [UNQUOTED, JAVA], ['JAVA_HOME'],
     [SDKMAN_BIN, '/home/u/.local/bin'], ['PATH entry ' + SDKMAN_BIN]),
    ('no PATH line at all', [JAVA], ['JAVA_HOME'], ['/home/u/.local/bin'], ['PATH entry /home/u/.local/bin']),
]


def walk(node):
    if isinstance(node, list):
        for task in node:
            if isinstance(task, dict):
                yield task
                for section in ('block', 'rescue', 'always'):
                    yield from walk(task.get(section))


verify = (yaml.safe_load(VERIFY.read_text(encoding='utf-8')) or [{}])[0]
found = [t for t in walk(verify.get('tasks')) if t.get('name') == NAME]
if len(found) != 1:
    print('FAIL %s holds %d tasks named "%s" where one is expected, so nothing could be lifted'
          % (VERIFY.relative_to(REPO).as_posix(), len(found), NAME))
    sys.exit(0)

plays = []
for number, (label, generated, variables, entries, _) in enumerate(CASES):
    plays.append({
        'name': label, 'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
        'vars': {'ansible_facts': {'system': 'Linux'}, 'ih_session_env': {'rc': 0, 'stdout_lines': generated},
                 'ih_session_env_vars': variables, 'ih_session_path_entries': entries},
        'tasks': [found[0], {'name': 'Record the answer', 'ansible.builtin.copy': {
            'dest': str(WORK / ('answer-%d.json' % number)), 'content': '{{ ih_session_env_missing | to_json }}'}}],
    })
(WORK / 'play.yaml').write_text(yaml.safe_dump(plays, sort_keys=False), encoding='utf-8')
(WORK / 'empty.cfg').write_text('[defaults]\n', encoding='utf-8')
env = dict(os.environ, ANSIBLE_CONFIG=str(WORK / 'empty.cfg'), ANSIBLE_STDOUT_CALLBACK='default', ANSIBLE_NOCOLOR='1',
           ANSIBLE_LOCALHOST_WARNING='false', ANSIBLE_RETRY_FILES_ENABLED='false')
done = subprocess.run(['ansible-playbook', '-i', 'localhost,', str(WORK / 'play.yaml')], cwd=WORK, env=env,
                      stdin=subprocess.DEVNULL, capture_output=True, text=True)
if done.returncode != 0:
    output = done.stdout + done.stderr
    fatal = [l.strip() for l in output.splitlines() if l.startswith(('fatal:', 'ERROR!', '[ERROR]'))]
    print('FAIL the lifted task "%s" stopped with exit %d: %s'
          % (NAME, done.returncode, (fatal or [' '.join(output.split()[-40:])])[0]))
    sys.exit(0)

lines = []
for number, (label, _, _, _, expected) in enumerate(CASES):
    missing = json.loads((WORK / ('answer-%d.json' % number)).read_text(encoding='utf-8'))
    if missing != expected:
        lines.append('FAIL %s: the task names %s as missing where %s was expected' % (label, missing, expected))
    else:
        lines.append('OK %s: the task names %s' % (label, ', '.join(missing) if missing else 'nothing missing'))
print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "session environment PATH"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "the desktop session check names exactly what the session would miss" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the session environment PATH check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "session environment PATH"
