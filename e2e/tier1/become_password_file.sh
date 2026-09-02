#!/usr/bin/env bash
#
# Tier 1: the sudo password setup.sh asks for is held safely, handed over once, and always removed.
#
# setup.sh runs two ansible-playbook processes, the install play and then the verification. Ansible's
# -K flag asks once per process, so the same person was asked the same question twice, roughly a
# quarter of an hour apart, and the second prompt arrived on an otherwise silent screen because the
# verification's output goes to a log file while Ansible's prompt goes to the terminal device. On
# 2026-08-28 that second prompt went unanswered and cost a whole run, with a zero byte verification
# log to show for it.
#
# The first attempt at fixing it warmed a sudo credential with `sudo -v` and a background keepalive
# and dropped -K from both playbooks. It was reverted the same day, because sudo keys its credential
# timestamp to the controlling terminal, timestamp_type=tty in sudo 1.9, and Ansible's -c local
# connection runs sudo in a child process with no controlling terminal. Every become failed with
# `sudo: a password is required` about twenty seconds into the run.
#
# What replaced it hands the password to both processes through a file. That is safe only while a
# short list of properties all hold at once, and each of them is silent when it breaks: a file left
# world readable is still a file Ansible can read, a fixed path is still a path Ansible can read, and
# a cleanup that never fires leaves the password on disk with nothing on screen to say so. So each
# one is asserted here by reading setup.sh as text.
#
# It is text analysis and nothing else. It cannot prove that ansible-playbook authenticates from the
# file, because that needs a machine whose sudo demands a password and a terminal to type one into,
# which is the same coverage hole docs/regression_ledger.md records against the reverted attempt.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: the sudo password file setup.sh hands to both playbooks"

SETUP_SH="${REPO_ROOT}/setup/setup.sh"

if [[ ! -f "${SETUP_SH}" ]]; then
    fail "setup.sh is missing, so this check proves nothing" "${SETUP_SH}"
    finish "become password file"
fi

require_python "the sudo password file setup.sh hands to both playbooks" "become password file"

report_status=0
report="$("${PYTHON}" - "${SETUP_SH}" <<'PYEOF'
import pathlib
import re
import sys

setup = pathlib.Path(sys.argv[1])
text = setup.read_text(encoding='utf-8')

# An assertion over an empty string is indistinguishable from one that found no problem, so an
# unreadable or empty file is a failure rather than a silent pass.
if not text.strip():
    print('FAIL setup.sh read as empty, so this check proves nothing')
    raise SystemExit(0)

# Comments explain the arrangement and are not the arrangement, so every assertion below reads the
# code with the comments stripped. A comment naming umask 077 must never count as setting it.
code = '\n'.join(re.sub(r'(^|\s)#.*$', '', line) for line in text.splitlines())

lines = []


def assert_that(condition, ok_message, fail_message):
    lines.append(('OK ' + ok_message) if condition else ('FAIL ' + fail_message))


assert_that(
    re.search(r'umask\s+077', code) or re.search(r'chmod\s+0?600\b', code),
    'the password file is written with the permissions narrowed first',
    'nothing narrows the permissions of the password file. Write it under umask 077, or chmod it '
    '600, or every account on the machine can read the sudo password while the run lasts')

assert_that(
    re.search(r'mktemp\s+-d', code),
    'the password file lives inside a directory mktemp -d created',
    'the password file is not created inside a mktemp -d directory. A fixed path is predictable, '
    'so another process can sit on it, and mktemp -d is what gives a private 0700 directory')

# The directory the password lives in, named by reading the file rather than by writing the name
# here: whatever `mktemp -d` fills, plus whatever that value is then copied into, so a rename does
# not quietly disable the assertion below.
temp_dir_vars = set(re.findall(r'(\w+)="?\$\(\s*mktemp\s+-d', code))
for _ in range(3):
    for assignment in re.finditer(r'(\w+)="\$\{(\w+)\}"', code):
        if assignment.group(2) in temp_dir_vars:
            temp_dir_vars.add(assignment.group(1))

# Every trap handler, resolved to the text that actually runs. An identifier is looked up as a
# function and replaced by its body, an inline handler is taken as written. Asserting only that some
# trap exists would pass on any copy of this file, because setup.sh already traps ERR and the four
# interrupt signals for reasons that have nothing to do with a password.
functions = dict(re.findall(r'^(\w+)\(\)\s*\{\n(.*?)\n\}$', code, re.S | re.M))
handler_bodies = []
for handler, _signals in re.findall(r'^\s*trap\s+(\'[^\']*\'|"[^"]*"|\S+)\s+([A-Z][A-Z ]*)$', code, re.M):
    handler = handler.strip('\'"')
    handler_bodies.append(functions.get(handler, handler))

removes_temp_dir = any(
    re.search(r'\brm\s+-rf\b', body) and any(var in body for var in temp_dir_vars)
    for body in handler_bodies)

assert_that(
    temp_dir_vars and removes_temp_dir,
    'a trap removes the temporary directory',
    'no trap removes the temporary directory holding the password. Without one an interrupted run '
    'leaves the sudo password on disk and says nothing about it. Directory variable(s) found: %s'
    % (', '.join(sorted(temp_dir_vars)) or 'none'))

flag_uses = text.count('--become-password-file')
assert_that(
    flag_uses == 1,
    'the become password file flag is written in exactly one place',
    'the become password file flag appears %d times rather than once. BECOME_ARGS is baked into '
    'PLAYBOOK_ARGS and VERIFY_ARGS is sliced off that, so one assignment already reaches both '
    'playbooks and a second one is how the two come to disagree' % flag_uses)

# The variable is whatever the silent read was told to fill, so the name is read out of the file
# rather than written here, and then that same name has to be emptied or unset somewhere later. Only
# a silent read counts, since -s is what a password prompt uses and a read without it is reading
# something that is not a secret.
read_names = []
for line in code.splitlines():
    match = re.search(r'\bread\b((?:\s+-\w+|\s+-p\s+"[^"]*")*)\s+(\w+)\s*(?:;|$)', line)
    if match and re.search(r'-\w*s', match.group(1)):
        read_names.append(match.group(2))

cleared = [name for name in read_names
           if re.search(r'^\s*%s=(""|\'\')?\s*$' % re.escape(name), code, re.MULTILINE)
           or re.search(r'\bunset\s+%s\b' % re.escape(name), code)]

assert_that(
    read_names and len(cleared) == len(read_names),
    'the shell variable holding the password is cleared after it is written to the file',
    'nothing clears the shell variable holding the password, so it stays readable for the rest of '
    'the run. Variable(s) read silently: %s' % (', '.join(read_names) or 'none found'))

assert_that(
    re.search(r'\bsudo\b(\s+-\w+)*\s+-S\b', code),
    'the password is proved against sudo before the playbook is started',
    'nothing feeds the password to sudo -S to check it. A wrong password then surfaces about twenty '
    'seconds into the run as a become failure on some unrelated task, which reads as a broken '
    'playbook rather than as a typo')

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "become password file"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "the sudo password file is not handled safely" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the become password file check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "become password file"
