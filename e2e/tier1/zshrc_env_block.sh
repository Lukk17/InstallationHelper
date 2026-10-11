#!/usr/bin/env bash
#
# Tier 1: setup/config/.zshrc carries, byte for byte, the marked block env_variables writes into it.
#
# env_variables writes a blockinfile block into ~/.zshrc, and later in the same first run shell_zsh's
# one-time "Copy ZSH configuration files" replaces ~/.zshrc with setup/config/.zshrc. If that file
# does not already hold the same block between the same markers, the second run finds no markers,
# inserts the block again and reports changed. GitHub sweep run 38107292439 measured exactly that on
# Arch idempotency, pass 2: "env_variables : Source the project's environment file from every rc
# file (Linux/macOS)" changed for /home/lukk/.zshrc and nothing else.
#
# The expected text is rendered from the task in env_unix.yaml, the marker with {mark} replaced by
# blockinfile's own BEGIN and END and the block body between them, so the two files cannot drift
# without this failing. A task that can no longer be found, or a block that holds a template
# expression this check cannot render, fails rather than passing over nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: the checked-in .zshrc already carries the block env_variables writes into it"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "zshrc env block"; }

require_python "the checked-in .zshrc already carries the block env_variables writes into it" "zshrc env block"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib

import yaml

TASKS = pathlib.Path('setup/ansible/roles/env_variables/tasks/env_unix.yaml')
TEMPLATE = pathlib.Path('setup/config/.zshrc')
TASK_NAME = "Source the project's environment file from every rc file (Linux/macOS)"
MODULES = ('ansible.builtin.blockinfile', 'community.general.blockinfile', 'blockinfile')


def emit(line):
    print(line)
    raise SystemExit(0)


try:
    tasks = yaml.safe_load(TASKS.read_text(encoding='utf-8'))
except (OSError, yaml.YAMLError) as exc:
    emit('FAIL %s could not be read as YAML: %s' % (TASKS.as_posix(), exc))

task = next((t for t in tasks or [] if isinstance(t, dict) and t.get('name') == TASK_NAME), None)
if task is None:
    emit('FAIL %s no longer has a task named "%s", so this check cannot know what block to expect'
         % (TASKS.as_posix(), TASK_NAME))
args = next((task[m] for m in MODULES if m in task), None)
if not isinstance(args, dict):
    emit('FAIL "%s" in %s is no longer a blockinfile task' % (TASK_NAME, TASKS.as_posix()))

marker = args.get('marker', '# {mark} ANSIBLE MANAGED BLOCK')
block = args.get('block', '')
if '{mark}' not in marker:
    emit('FAIL the marker "%s" in %s has no {mark}, which this check does not know how to render'
         % (marker, TASKS.as_posix()))
if '{{' in marker or '{{' in block or '{%' in block:
    emit('FAIL the marker or block in %s holds a template expression, so its rendered text cannot be '
         'known here and the copy of %s cannot be compared with it' % (TASKS.as_posix(), TEMPLATE.as_posix()))
if not block.endswith('\n'):
    block += '\n'
begin = marker.replace('{mark}', args.get('marker_begin', 'BEGIN'))
end = marker.replace('{mark}', args.get('marker_end', 'END'))
expected = '%s\n%s%s\n' % (begin, block, end)

try:
    text = TEMPLATE.read_bytes().decode('utf-8')
except OSError as exc:
    emit('FAIL %s could not be read: %s' % (TEMPLATE.as_posix(), exc))

lines = text.splitlines(keepends=True)
begin_count = sum(1 for line in lines if line.rstrip('\n') == begin)
starts = [i for i in range(len(lines)) if ''.join(lines[i:i + expected.count('\n')]) == expected]
if len(starts) != 1 or begin_count != 1:
    emit('FAIL %s carries the block "%s" as whole lines %d time(s) and its BEGIN marker %d time(s), '
         'where exactly once each is required. shell_zsh copies this file over ~/.zshrc after '
         'env_variables has written that block, so without it the next run inserts the block again '
         'and reports changed. Expected, byte for byte:\n%s'
         % (TEMPLATE.as_posix(), begin, len(starts), begin_count, expected))
print('OK %s carries the %d line block env_variables writes, markers included, exactly once at line %d'
      % (TEMPLATE.as_posix(), expected.count('\n'), starts[0] + 1))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "zshrc env block"

failure=""
while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) failure="${line#FAIL }" ;;
        *)     [[ -n "${failure}" ]] && failure+=$'\n'"${line}" ;;
    esac
done <<<"${report}"
[[ -n "${failure}" ]] && fail "the checked-in .zshrc does not carry the block env_variables writes" "${failure}"
[[ -z "${report}" ]] && fail "the zshrc block check printed nothing" "expected an OK or FAIL line"

finish "zshrc env block"
