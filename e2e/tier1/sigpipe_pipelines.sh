#!/usr/bin/env bash
#
# Tier 1: nothing feeds a command from a program that never stops writing, and no script under e2e/ or
# setup/ pipes into a reader that stops reading early.
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
#
# The same 141 comes from the other end of a pipe. `grep -q` and `grep -m` exit at the first match and
# `head` after its last line, so a writer that still has output to send is killed by SIGPIPE, and
# under pipefail the pipeline fails although the reader found what it looked for. Every script under
# e2e/ runs under pipefail through e2e/lib/common.sh. On 2026-10-23 manual_linux_install.sh read the
# Fedora guide through `tr -d '\r' <guide | grep -qE ...` and reported that the guide never tells the
# reader to enable docker.service, in 56 of 2000 runs in the gate image on one CPU, while tr's exit
# status was 141 and grep's was 0 (docs/regression_ledger.md 10.190). The answer is the same: no pipe. A
# grep reads a here-string, `grep -q pattern <<<"$(producer)"`, and a pipe that wants the first lines
# ends in `sed -n 1,Np`, which reads to the end. An awk program that wants the first match keeps a flag
# instead of calling exit. This half covers the shell scripts under e2e/, and since 2026-10-23 every
# string in the YAML under setup/ and every shell script there too, where verify_install.yaml ran
# `find ... | grep -q .` and `npm list -g ... | grep -q -F` under pipefail (docs/regression_ledger.md
# 10.196).

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
    """Blank whole-line and drop trailing shell comments, so a comment naming the hazard is not the hazard.

    Deliberately crude: a `#` inside a quoted string is rare in these scripts and treating it as a
    comment can only lose a detection, never invent one, and losing one is caught by the count guard
    at the bottom.
    """
    out = []
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith('#'):
            out.append('')
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

# A pipe into a reader that can exit before its input ends: `head`, `read`, an awk program that calls
# exit outside its END block, or a grep whose options before the pattern hold -q, -m, -l, -L, --quiet,
# --silent, --max-count, --files-with-matches or --files-without-match. A single bar only, so `||` is
# not a pipe, and a pipe may continue on the next line.
EARLY_READER = re.compile(r'(?<!\|)\|(?!\|)&?[ \t]*(?:\\?\n[ \t]*)?'
                          r'(head(?=[ \t\n;)]|$)|grep((?:[ \t]+-[^ \t\n]*)*)|awk(?=[ \t])|'
                          r'\{?[ \t]*(?:IFS=[^ \t\n]*[ \t]+)?read(?=[ \t\n;]|$))')


def early_exit_options(options):
    """True when grep's leading options make it stop at the first match."""
    for option in options.split():
        if option == '--':
            return False
        if option.startswith('--'):
            if option.split('=')[0] in ('--quiet', '--silent', '--max-count',
                                        '--files-with-matches', '--files-without-match'):
                return True
        elif any(letter in option[1:] for letter in 'qmlL'):
            return True
    return False


def awk_command(body, start):
    """The awk command from `start` to the first newline, pipe, semicolon or `)` outside single quotes."""
    quoted = False
    for index in range(start, len(body)):
        character = body[index]
        if character == "'":
            quoted = not quoted
        elif not quoted and character in '\n|;)':
            return body[start:index]
    return body[start:]


def awk_exits_early(command):
    """True when an awk program calls exit anywhere but in its END block, which runs after the last line."""
    return re.search(r'\bexit\b', re.sub(r'\bEND[ \t]*\{[^}]*\}', '', command)) is not None


def early_readers(body):
    """Every (line number, snippet) in `body` where a pipe feeds a reader that can exit before its input ends."""
    found_readers = []
    for found in EARLY_READER.finditer(body):
        reader = found.group(1)
        if reader == 'awk':
            command = awk_command(body, found.start(1))
            if not awk_exits_early(command):
                continue
            snippet = '| ' + command
        elif reader.startswith('grep'):
            if not early_exit_options(found.group(2) or ''):
                continue
            snippet = found.group(0)
        else:
            snippet = found.group(0)
        line_number = body.count('\n', 0, found.start()) + 1
        found_readers.append((line_number, ' '.join(snippet.split())))
    return found_readers


def strings_in(node, path=''):
    """Every string scalar in a parsed YAML document, with the dotted path of keys that leads to it."""
    if isinstance(node, str):
        yield path, node
    elif isinstance(node, dict):
        for key, value in node.items():
            yield from strings_in(value, '%s.%s' % (path, key) if path else str(key))
    elif isinstance(node, list):
        for index, item in enumerate(node):
            yield from strings_in(item, '%s[%d]' % (path, index))


# The setup/ half reads every string in every YAML file under setup/, not only the shell and command
# modules, because a script also arrives through a variable: the probes in tasks/opencode_version.yaml
# and the disk_cmd lines in verify_install.yaml are set_fact values a shell task runs later. A Jinja
# filter is written `| name` too, and none of them is called head, grep, awk or read, so a filter is
# never taken for a reader. Shell scripts under setup/ are read whole.
setup_texts = []   # (label, text)
for path in sorted((REPO / 'setup').rglob('*')):
    if not path.is_file():
        continue
    rel = path.as_posix()
    if path.suffix in ('.yaml', '.yml'):
        try:
            doc = yaml.safe_load(path.read_text(encoding='utf-8'))
        except (yaml.YAMLError, UnicodeDecodeError):
            continue
        for key_path, value in strings_in(doc):
            setup_texts.append(('%s :: %s' % (rel, key_path or 'document'), value))
    elif path.suffix in ('.sh', '.bash', '.zsh') or path.name.endswith('zshrc'):
        try:
            setup_texts.append((rel, path.read_text(encoding='utf-8')))
        except UnicodeDecodeError:
            continue


lines = []
offenders = []
readers = []

for label, text in scripts:
    body = strip_comments(text)
    match = UNBOUNDED.search(body)
    if match:
        offenders.append((label, match.group(1).strip()))
    if label.startswith('e2e/') and ' :: ' not in label:
        for line_number, snippet in early_readers(body):
            readers.append((label, line_number, snippet))

for label, text in setup_texts:
    for line_number, snippet in early_readers(strip_comments(text)):
        readers.append((label, line_number, snippet))

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
    for label, line_number, snippet in readers:
        lines.append('READER %s, line %d, pipes into `%s`, which can exit before its '
                     'input ends. The writer is then killed by SIGPIPE and pipefail fails the pipeline '
                     'whatever the reader found. Give a grep a here-string, grep -q pattern <<<"$(producer)", '
                     'end a pipe that wants the first lines in sed -n 1,Np, and let an awk program keep a '
                     'flag rather than call exit.' % (label, line_number, snippet))
    e2e_scripts = sum(1 for label, _ in scripts if label.startswith('e2e/') and ' :: ' not in label)
    if not readers and e2e_scripts and setup_texts:
        lines.append('OK %d e2e scripts and %d strings and scripts under setup/ read, none pipes into a '
                     'reader that stops early' % (e2e_scripts, len(setup_texts)))
    if not e2e_scripts:
        lines.append('FAIL no e2e script was read, so the early reader half proves nothing for e2e/')
    if not setup_texts:
        lines.append('FAIL nothing under setup/ was read, so the early reader half proves nothing for setup/')

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "sigpipe pipelines"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a command is fed from a program that never stops writing" "${line#FAIL }" ;;
        READER*) fail "a script pipes into a reader that stops early" "${line#READER }" ;;
        *)     [[ -n "${line}" ]] && fail "the SIGPIPE pipeline check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "sigpipe pipelines"
