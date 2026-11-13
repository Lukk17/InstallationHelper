#!/usr/bin/env bash
#
# Tier 1: a message the playbook writes for the owner reaches the terminal.
#
# Since commit 37aeb15 the dual_logger callback shows on the terminal only changed, failed and
# unreachable results, plus a debug message that opens with [WARN], [ERROR] or [FATAL]. The output of
# an ok command and an ok debug message without one of those markers go to ~/installation_full.log
# only. "Show what pacman recorded for every AUR package that is absent" was a shell task with
# changed_when: false, written to print pacman's log on the terminal when an AUR build claimed
# success and installed nothing, and after that commit its output reached the log file alone
# (docs/regression_ledger.md 10.294). Twelve rescue messages in site.yaml lost the terminal the same way.
#
# So this asserts, over every YAML file under setup/ansible apart from verify_install.yaml, which
# setup.sh runs under Ansible's own callback rather than dual_logger:
#   1. no command, shell, raw or script task is named Show, Print or Display, because its output
#      never reaches the terminal. Register it and print it from a debug task with a marker.
#   2. every debug task named Show, Print, Display, Surface or Warn carries a level marker.
#   3. every debug task inside a rescue carries a level marker, because a rescue runs only after
#      something failed and its message says what that cost.
# The counts of named and rescue debug tasks are reported and must not be zero, so a parser that
# stops finding tasks fails here instead of passing over nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: a message written for the owner reaches the terminal"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "owner facing messages"; }

require_python "a message written for the owner reaches the terminal" "owner facing messages"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re

import yaml

ANSIBLE = pathlib.Path('setup') / 'ansible'
NOT_DUAL_LOGGER = {(ANSIBLE / 'verify_install.yaml').as_posix()}

COMMANDS = {'ansible.builtin.command', 'command', 'ansible.builtin.shell', 'shell',
            'ansible.builtin.raw', 'raw', 'ansible.builtin.script', 'script'}
DEBUG = ('ansible.builtin.debug', 'debug')
SHOW_VERBS = re.compile(r'^(Show|Print|Display)\b')
MESSAGE_VERBS = re.compile(r'^(Show|Print|Display|Surface|Warn)\b')
# A marker at the start of a line, or quoted inside a Jinja expression that builds the message.
MARKER = re.compile(r'''(^|\n|['"])\s*\[(WARN|ERROR|FATAL)\]''')

lines = []


# Yields each mapping with whether it sits in a rescue and the name of the nearest named mapping
# around it, so an unnamed rescue task is reported by the block it belongs to.
def walk(node, in_rescue=False, owner=''):
    if isinstance(node, dict):
        yield node, in_rescue, owner
        inner = node['name'] if isinstance(node.get('name'), str) else owner
        for key, value in node.items():
            yield from walk(value, in_rescue or key == 'rescue', inner)
    elif isinstance(node, list):
        for item in node:
            yield from walk(item, in_rescue, owner)


def message_text(debug):
    msg = debug.get('msg', '') if isinstance(debug, dict) else debug
    if isinstance(msg, list):
        return '\n'.join(str(entry) for entry in msg)
    return str(msg).strip()


files_read = 0
named_debugs = 0
rescue_debugs = 0
for path in sorted(ANSIBLE.rglob('*.yaml')):
    where = path.as_posix()
    if where in NOT_DUAL_LOGGER:
        continue
    try:
        doc = yaml.safe_load(path.read_text(encoding='utf-8'))
    except (yaml.YAMLError, UnicodeDecodeError):
        continue
    files_read += 1
    for task, in_rescue, owner in walk(doc):
        name = task.get('name') if isinstance(task.get('name'), str) else ''
        label = '%s :: %s' % (where, name or 'unnamed task in "%s"' % (owner or 'the play'))
        debug = next((task[key] for key in DEBUG if key in task), None)
        if debug is None:
            if SHOW_VERBS.match(name) and any(key in task for key in COMMANDS):
                lines.append('FAIL %s is a command named for showing its output, and the callback writes '
                             'the output of an ok command to installation_full.log only. Register it and '
                             'print it from a debug task whose message opens with [WARN] or [ERROR], or '
                             'rename it to say it only logs' % label)
            continue
        marked = bool(MARKER.search(message_text(debug)))
        if MESSAGE_VERBS.match(name):
            named_debugs += 1
            if not marked:
                lines.append('FAIL %s is named for telling the owner something and its message carries no '
                             '[WARN], [ERROR] or [FATAL], so it reaches installation_full.log only' % label)
        if in_rescue:
            rescue_debugs += 1
            if not marked:
                lines.append('FAIL %s runs in a rescue, after something failed, and its message carries no '
                             '[WARN], [ERROR] or [FATAL], so what the failure cost reaches '
                             'installation_full.log only' % label)

if not files_read:
    print('FAIL no YAML file under setup/ansible could be read, so this check proves nothing')
    raise SystemExit(0)
if not named_debugs:
    lines.append('FAIL no debug task named Show, Print, Display, Surface or Warn was found, so rule 2 '
                 'proved nothing. Either the parser lost them or the names changed')
if not rescue_debugs:
    lines.append('FAIL no debug task inside a rescue was found, so rule 3 proved nothing. Either the '
                 'parser lost them or the rescues changed')
if not lines:
    lines.append('OK %d debug tasks named for the owner and %d debug tasks in a rescue across %d files '
                 'all carry a level marker, and no command is named for showing its output'
                 % (named_debugs, rescue_debugs, files_read))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "owner facing messages"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a message written for the owner does not reach the terminal" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the owner facing message check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "owner facing messages"
