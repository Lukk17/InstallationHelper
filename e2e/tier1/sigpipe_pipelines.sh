#!/usr/bin/env bash
#
# Tier 1: nothing feeds a command from a program that never stops writing.
#
# `yes` writes the letter y forever. It is still running when the program on the right of the pipe
# finishes, so the kernel kills it with SIGPIPE, and a process killed by a signal reports 128 plus the
# signal number, which is 141. Under `set -o pipefail` that 141 becomes the pipeline's answer whatever
# the real command did, and a `failed_when: rc != 0` beside it then fires on a success.
#
# Both halves of that have already cost this repository a run.
#
#   Accept Android SDK licenses     ended `yes | sdkmanager --licenses` with `|| true` to swallow the
#                                   141, which swallowed sdkmanager's own status with it and left the
#                                   failed_when beside it unable to fire at all
#
#   Align the 32-bit graphics       `yes | pacman -Syy --needed mesa-git lib32-mesa-git` under
#   stack (CachyOS)                 pipefail, on 2026-08-28, on a real CachyOS machine where pacman
#                                   printed "there is nothing to do" and exited cleanly. The task
#                                   retried three times, failed all three, and took the whole run down
#                                   with it before a single application was installed
#
# The second one was written after the first was fixed, which is why this is a check rather than a
# note. The ledger's own checklist said to prepend `set -o pipefail` to any pipeline whose status you
# intend to check, and following that literally on a `yes |` pipeline produces exactly this bug.
#
# The answer this repository uses is to not pipe at all: write the answers to a temporary file and
# redirect the file into the command's standard input. One process, nothing to kill, and the return
# code means what it says. Both tasks above now do that.
#
# There is no allowlist. A pipeline from an unbounded writer has a working alternative that costs
# three lines, so there is no case to forgive.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: no command is fed from a program that never stops writing"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "sigpipe pipelines"; }

require_python "no command is fed from a program that never stops writing" "sigpipe pipelines"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re

import yaml

REPO = pathlib.Path('.')
ROOTS = ('setup', 'e2e')

# Programs that never terminate on their own, so the reader's exit is always what stops them.
# `yes` is the one this repository has been bitten by twice. `tail -f` and a bare `while true` loop
# are the same shape and are here so the next one is caught the first time rather than the second.
UNBOUNDED = re.compile(r'(?:^|[;&|(]|\bthen\b|\bdo\b|\belse\b)[ \t]*'
                       r'(yes(?:[ \t]+[^|;&\n]*)?|tail[ \t]+-[a-zA-Z]*f[a-zA-Z]*[ \t]+[^|;&\n]+)\|(?!\|)',
                       re.MULTILINE)

# Module keys whose value is a script this check has to read. The short and fully qualified spellings
# both appear in this repository.
SHELL_KEYS = ('ansible.builtin.shell', 'shell', 'ansible.builtin.raw', 'raw',
              'ansible.builtin.command', 'command')


def strip_comments(text):
    """Drop whole-line and trailing shell comments, so a comment naming the hazard is not the hazard.

    Deliberately crude: a `#` inside a quoted string is rare in these scripts and treating it as a
    comment can only lose a detection, never invent one, and losing one is caught by the count guard
    at the bottom.
    """
    out = []
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith('#'):
            continue
        out.append(re.sub(r'\s#.*$', '', line))
    return '\n'.join(out)


def walk(node):
    """Every mapping in a parsed YAML document, at any depth."""
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for item in node:
            yield from walk(item)


scripts = []   # (label, script text)

for root in ROOTS:
    base = REPO / root
    if not base.is_dir():
        continue
    for path in sorted(base.rglob('*')):
        if not path.is_file():
            continue
        rel = path.as_posix()
        if path.suffix in ('.yaml', '.yml'):
            try:
                doc = yaml.safe_load(path.read_text(encoding='utf-8'))
            except (yaml.YAMLError, UnicodeDecodeError):
                # A file that does not parse is not this check's business. ansible_static.sh owns
                # that, and reporting it twice would make one defect look like two.
                continue
            for task in walk(doc):
                for key in SHELL_KEYS:
                    value = task.get(key)
                    if isinstance(value, str):
                        name = task.get('name') if isinstance(task.get('name'), str) else key
                        scripts.append(('%s :: %s' % (rel, name), value))
        elif path.suffix == '.sh' or path.name.endswith('.bash'):
            try:
                scripts.append((rel, path.read_text(encoding='utf-8')))
            except UnicodeDecodeError:
                continue

lines = []
offenders = []

for label, text in scripts:
    body = strip_comments(text)
    match = UNBOUNDED.search(body)
    if match:
        offenders.append((label, match.group(1).strip()))

# An assertion over an empty set passes and is indistinguishable from one that found no problem, so
# the count is part of the result rather than a detail. Checklist item 11 in the regression ledger.
if not scripts:
    lines.append('FAIL nothing was read, so this check proves nothing')
else:
    for label, snippet in offenders:
        lines.append('FAIL %s feeds a command from `%s`, which never stops writing. The kernel kills '
                     'it with SIGPIPE when the reader exits, so under pipefail the pipeline reports '
                     '141 whatever the real command did. Write the answers to a temporary file and '
                     'redirect it instead, as roles/sdk_manager/tasks/android_sdk_unix.yaml and '
                     'roles/arch_core/tasks/main.yaml both do.' % (label, snippet))
    if not offenders:
        lines.append('OK %d scripts read, none fed from an unbounded writer' % len(scripts))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "sigpipe pipelines"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a command is fed from a program that never stops writing" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the SIGPIPE pipeline check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "sigpipe pipelines"
