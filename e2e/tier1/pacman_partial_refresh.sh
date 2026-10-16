#!/usr/bin/env bash
#
# Tier 1: no pacman call refreshes the package index and installs a package in the same invocation
# without upgrading the system.
#
# `pacman -Sy <package>` and `pacman -Syy <package>` install against an index newer than the installed
# system, which is the partial upgrade the Arch wiki tells you never to do: the new package can need a
# library version the rest of the machine does not have yet. Two tasks did exactly that on every
# attempt, the first included, until 2026-10-15: "Install Docker (Arch), one package at a time" ran
# `pacman -Syy --noconfirm --needed <package>`, and the CachyOS graphics alignment ran
# `pacman -Syy --needed mesa-git lib32-mesa-git`. arch_core has already refreshed and upgraded the whole
# system by then, so the first attempt has nothing to gain from a refresh. A retry after a failure is
# where a refresh helps, because a mirror that is behind the index answers 404, and there it runs as its
# own invocation before the install: `pacman -Syy && pacman -S <package>`. See docs/regression_ledger.md.
#
# So every command, shell and raw body under setup/ansible, and every shell script under setup/, is
# read invocation by invocation, split on newlines, &&, ||, ; and |, and an invocation whose sync flags
# carry y and no u, or --refresh without --sysupgrade, fails when it also names a package. A refresh on
# its own, and -Syu with packages, are fine. The pacman module is read too: update_cache with a name
# and no upgrade is the same partial upgrade.
#
# The by-hand route is read as well, every shell script under docs/manual and every fenced code block
# of every markdown page there, in the order a reader runs them. Until 2026-10-15 the Arch guide told a
# CachyOS user to run `sudo pacman -Syy --needed mesa-git`, and docs/manual/arch/install.sh ran a bare
# `sudo pacman -Syy` just before installing the two Mesa packages, which is the same partial upgrade
# split over two lines. So there a refresh on its own fails too when a later install follows it with no
# full upgrade in between. The playbook is not held to that second rule, because its one refresh on
# its own is the retry after a failed attempt, `pacman -Syy && pacman -S <package>`, and a guide a
# person reads top to bottom has no failed attempt to answer.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: no pacman call refreshes the index and installs in one invocation"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "pacman partial refresh"; }

require_python "no pacman call refreshes the index and installs in one invocation" "pacman partial refresh"

report_status=0
report="$("${PYTHON}" - setup docs/manual <<'PYEOF'
import json
import pathlib
import re
import sys

import yaml

root = pathlib.Path(sys.argv[1])
SHELLS = ('ansible.builtin.command', 'ansible.builtin.shell', 'ansible.builtin.raw',
          'command', 'shell', 'raw')
MODULES = ('community.general.pacman', 'pacman')
SEGMENT = re.compile(r'\n|&&|\|\||;|\|')
TOKEN = re.compile(r'"?\{\{.*?\}\}"?|\S+')
REDIRECT = re.compile(r'^\d*[<>]')


def walk(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for item in node:
            yield from walk(item)


def pacman_call(segment):
    """The sync flags of one invocation as (sync, refresh, upgrade, targets), or None for no pacman."""
    words = TOKEN.findall(segment)
    if 'pacman' not in words:
        return None
    words = words[words.index('pacman') + 1:]
    sync = refresh = upgrade = False
    targets = []
    skip_next = False
    for word in words:
        if skip_next:
            skip_next = False
            continue
        if REDIRECT.match(word):
            skip_next = word in ('<', '>', '2>', '1>')
            continue
        if word in ('--refresh',):
            refresh = True
        elif word in ('--sysupgrade',):
            upgrade = True
        elif re.fullmatch(r'-[A-Za-z]+', word) and 'S' in word:
            sync = True
            refresh = refresh or 'y' in word
            upgrade = upgrade or 'u' in word
        elif not word.startswith('-'):
            targets.append(word)
    return sync, refresh, upgrade, targets


def partial_refreshes(text):
    found = []
    for segment in SEGMENT.split(text.replace('\\\n', ' ')):
        call = pacman_call(segment)
        if call and call[1] and not call[2] and call[3]:
            found.append(segment.strip())
    return found


lines = []
read = 0
for path in sorted(root.rglob('*.yaml')):
    try:
        doc = yaml.safe_load(path.read_text(encoding='utf-8'))
    except (yaml.YAMLError, UnicodeDecodeError):
        continue
    for task in walk(doc):
        if not isinstance(task.get('name'), str):
            continue
        read += 1
        for key in SHELLS:
            if key not in task:
                continue
            body = task[key]
            if isinstance(body, dict):
                body = body.get('cmd') or body.get('_raw_params') or ''
            for call in partial_refreshes(str(body)):
                lines.append('FAIL %s :: %s refreshes the index and installs in one invocation: %s'
                             % (path.as_posix(), task['name'], call))
        for key in MODULES:
            args = task.get(key)
            if isinstance(args, dict) and args.get('update_cache') in (True, 'yes', 'true') \
                    and args.get('name') and not args.get('upgrade'):
                lines.append('FAIL %s :: %s asks the pacman module for update_cache and a package '
                             'without upgrade' % (path.as_posix(), task['name']))

for path in sorted(root.rglob('*.sh')):
    read += 1
    text = '\n'.join(line for line in path.read_text(encoding='utf-8').splitlines()
                     if not line.lstrip().startswith('#'))
    for call in partial_refreshes(text):
        lines.append('FAIL %s refreshes the index and installs in one invocation: %s'
                     % (path.as_posix(), call))

if not read:
    print('FAIL nothing was read under %s, so this check proves nothing' % root.as_posix())
    raise SystemExit(0)


def manual_lines(path):
    """(line number, text) for every command line a reader runs: a script's code, a page's fences."""
    text = path.read_text(encoding='utf-8').replace('\\\n', ' ')
    fenced = path.suffix != '.md'
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if path.suffix == '.md' and stripped.startswith('```'):
            fenced = not fenced
            continue
        if fenced and stripped and not stripped.startswith('#'):
            yield number, stripped


manual = pathlib.Path(sys.argv[2])
manual_files = sorted(manual.rglob('*.sh')) + sorted(manual.rglob('*.md'))
manual_calls = 0
for path in manual_files:
    pending = None
    for number, line in manual_lines(path):
        for segment in SEGMENT.split(line):
            call = pacman_call(segment)
            if not call or not call[0]:
                continue
            manual_calls += 1
            sync, refresh, upgrade, targets = call
            where = '%s:%d' % (path.as_posix(), number)
            if upgrade:
                pending = None
            elif refresh and targets:
                lines.append('FAIL %s refreshes the index and installs in one invocation: %s'
                             % (where, segment.strip()))
            elif refresh:
                pending = (where, segment.strip())
            elif targets and pending:
                lines.append('FAIL %s refreshes the index without upgrading, and %s then installs against '
                             'it: %s, then %s. Upgrade with -Syu instead, or install against the index '
                             'the last upgrade used.' % (pending[0], where, pending[1], segment.strip()))
                pending = None
if not manual_calls:
    lines.append('FAIL no pacman sync call was found under %s, so the manual route proves nothing'
                 % manual.as_posix())

if not lines:
    lines.append('OK no pacman call refreshes the index and installs in the same invocation without '
                 'upgrading (%d tasks and scripts read), and no manual step installs against a refresh '
                 'it did not upgrade with (%d pacman calls in %d files read)'
                 % (read, manual_calls, len(manual_files)))
print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "pacman partial refresh"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a pacman call installs against a freshly refreshed index without upgrading" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the pacman partial refresh check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "pacman partial refresh"
