#!/usr/bin/env bash
#
# Tier 1: every per-task log file the callback, the setup hub and the container harness name is one a
# real task writes, under a task name that still exists.
#
# The dual_logger callback tails a log file while a long task runs, chosen by a task-name prefix in
# HEARTBEAT_LOG_FILES. When apt and Flatpak stopped batching on 2026-08-25 their tasks were renamed
# and their logs moved from installation-apt-batch.log and installation-flatpak-batch.log to
# installation-apt.log and installation-flatpak.log, and nothing followed: the callback kept both old
# prefixes, so the heartbeat never found a log for the two longest tasks in a Debian run, the setup hub
# told the reader to tail files that are never written, and e2e/tier3/container.sh copied an apt
# transcript out of every container that no longer existed, losing it silently behind `|| true`. When
# Claude Desktop moved to Anthropic's apt repository, a prefix for an install task that had been
# deleted stayed behind as well. Every one of those was a name in one file that had to match a name in
# another, which is a comparison a check can make.
#
# So this asserts:
#   1. every HEARTBEAT_LOG_FILES prefix in setup/ansible/callback_plugins/dual_logger.py is part of at
#      least one task name under setup/ansible, and one of those tasks writes the mapped log with tee;
#   2. every /var/log/installation-*.log that setup/README_SETUP.md names is written with tee by a task;
#   3. every log that e2e/tier3/container.sh copies out of a container is written with tee by a task.
# The callback is read with ast rather than imported, because importing it needs Ansible and pwd.
# The prefix count is reported and must not be zero, so a rewrite that hides the table from the
# parser fails here instead of passing over nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: every per-task log file named anywhere is written by a task that still exists"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "heartbeat log files"; }

require_python "every per-task log file named anywhere is written by a task that still exists" "heartbeat log files"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import ast
import json
import pathlib
import re

import yaml

ANSIBLE = pathlib.Path('setup') / 'ansible'
CALLBACK = ANSIBLE / 'callback_plugins' / 'dual_logger.py'
README = pathlib.Path('setup') / 'README_SETUP.md'
CONTAINER = pathlib.Path('e2e') / 'tier3' / 'container.sh'
COMMAND_MODULES = ('ansible.builtin.command', 'ansible.builtin.shell', 'ansible.builtin.raw',
                   'command', 'shell', 'raw')
LOG_PATH = re.compile(r'/var/log/installation[-_][A-Za-z0-9_.-]*\.log')
COPY_LOOP = re.compile(r'for remote_log in ([^;]+);')

lines = []


def walk(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for item in node:
            yield from walk(item)


def heartbeat_table():
    tree = ast.parse(CALLBACK.read_text(encoding='utf-8'))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
                isinstance(t, ast.Name) and t.id == 'HEARTBEAT_LOG_FILES' for t in node.targets):
            return ast.literal_eval(node.value)
    return None


tasks = []
for path in sorted(ANSIBLE.rglob('*.yaml')):
    try:
        doc = yaml.safe_load(path.read_text(encoding='utf-8'))
    except (yaml.YAMLError, UnicodeDecodeError):
        continue
    for task in walk(doc):
        if not isinstance(task.get('name'), str):
            continue
        command = next((task[k] for k in COMMAND_MODULES if k in task), None)
        command_text = json.dumps(command, default=str) if command is not None else ''
        tasks.append((path.as_posix(), task['name'], command_text))

if not tasks:
    print('FAIL no named task under setup/ansible could be read, so this check proves nothing')
    raise SystemExit(0)


def tee_writers(log):
    return [t for t in tasks if 'tee' in t[2] and log in t[2]]


table = heartbeat_table()
if not table:
    print('FAIL HEARTBEAT_LOG_FILES was not found in %s or is empty, so this check proves nothing'
          % CALLBACK.as_posix())
    raise SystemExit(0)

for prefix, log in sorted(table.items()):
    named = [t for t in tasks if prefix in t[1]]
    if not named:
        lines.append('FAIL %s maps the prefix "%s" to %s, and no task under setup/ansible has a name '
                     'containing it, so the heartbeat never tails that log'
                     % (CALLBACK.as_posix(), prefix, log))
        continue
    if not any('tee' in t[2] and log in t[2] for t in named):
        lines.append('FAIL %s maps "%s" to %s, and no task with that name writes that file with tee, '
                     'so the heartbeat tails a file the task never writes'
                     % (CALLBACK.as_posix(), prefix, log))

readme_logs = sorted(set(LOG_PATH.findall(README.read_text(encoding='utf-8'))))
for log in readme_logs:
    if not tee_writers(log):
        lines.append('FAIL %s tells the reader to look at %s, and no task under setup/ansible writes '
                     'it' % (README.as_posix(), log))

copied = []
for match in COPY_LOOP.finditer(CONTAINER.read_text(encoding='utf-8')):
    copied.extend(word for word in match.group(1).split() if word.endswith('.log'))
for name in copied:
    if not tee_writers('/var/log/' + name):
        lines.append('FAIL %s copies /var/log/%s out of every container, and no task under '
                     'setup/ansible writes it, so the copy finds nothing and says nothing'
                     % (CONTAINER.as_posix(), name))
if not copied:
    lines.append('FAIL no `for remote_log in` loop was found in %s, so its copied logs were not '
                 'checked' % CONTAINER.as_posix())

if not lines:
    lines.append('OK %d heartbeat prefixes, %d log files in the setup hub and %d copied by the '
                 'container harness all match a task that writes them'
                 % (len(table), len(readme_logs), len(copied)))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "heartbeat log files"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a per-task log file is named that no current task writes" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the heartbeat log file check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "heartbeat log files"
