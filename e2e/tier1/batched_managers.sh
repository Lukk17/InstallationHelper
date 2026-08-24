#!/usr/bin/env bash
#
# Tier 1: only a manager whose solver works on the whole set may install in one batched call.
#
# A batch is a single call, so one failure anywhere in it loses every package in it. That is worth
# paying only when the manager genuinely resolves the set together, which apt, dnf and pacman do and
# which flatpak, snap, the AUR helper, winget, Chocolatey and Homebrew casks do not.
#
# The bill for getting this wrong, three times in four days, all in the ledger. A flatpak batch of
# twenty-two applications lost all twenty-two to one fetch timing out, on twenty of the forty-eight
# container cells of sweep 32723213808, and abandoned every task after it in the software installer.
# A Homebrew cask batch lost roughly thirty casks to one deleted Tor Browser build, then lost them
# again the next day to rawtherapee refusing an older macOS. A Chocolatey batch stamped one package's
# failure onto every package in it.
#
# The flatpak case is the reason this check exists rather than a comment. The argument against
# batching independent downloads was already written in this repository, for casks, two days before
# flatpak lost twenty cells to exactly it. A reason living only in a comment beside one manager does
# not travel to the manager three hundred lines below it. A check does.
#
# How it decides. [batched_managers_allowed.txt](batched_managers_allowed.txt) lists the managers
# allowed to batch, with the reason. For every other manager, the task that installs it must loop:
# either `loop:` over the batch list, or a loop over the package list the dispatcher builds. Passing
# `software_installer_batches.<manager>` straight into a module's `name:`, or joining it into a
# command line, is what this fails on.
#
# Deliberately narrow. It reads the one file that dispatches installs and asks one question about
# each manager. It does not try to judge whether a loop is correct, only that the set is not handed
# over in one call.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: only managers that resolve the whole set may batch"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "batched managers"; }

DISPATCH="setup/ansible/roles/software_installer/tasks/dynamic_install.yaml"
ALLOWED="e2e/tier1/batched_managers_allowed.txt"

if [[ ! -f "${DISPATCH}" ]]; then
    fail "the software installer dispatcher is missing, so this check proves nothing" "${DISPATCH}"
    finish "batched managers"
    return 0 2>/dev/null || exit 0
fi

report="$("${PYTHON:-python}" - "${DISPATCH}" "${ALLOWED}" <<'PYEOF'
import json
import pathlib
import re
import sys

import yaml

dispatch = pathlib.Path(sys.argv[1])
allowed_path = pathlib.Path(sys.argv[2])

allowed = {}
if allowed_path.exists():
    for line in allowed_path.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split(None, 1)
        allowed[parts[0]] = parts[1] if len(parts) > 1 else ''

text = dispatch.read_text(encoding='utf-8')

# Managers are read out of the file rather than listed here, so one added tomorrow is covered without
# anybody remembering to add it. Two shapes exist today: a prebuilt batch list, and a list filtered
# inline out of the package set. Homebrew formulae use the second, which is why the first version of
# this check could not see them.
managers = set(re.findall(r'software_installer_batches\.([a-z_]+)', text))
managers |= set(re.findall(r"selectattr\(\s*'value\.manager'\s*,\s*'equalto'\s*,\s*'([a-z_]+)'", text))
managers = sorted(managers)

if not managers:
    print('FAIL the dispatcher names no package managers, so this check proves nothing')
    raise SystemExit(0)


def leaf_tasks(node):
    """Every task mapping that is not a block, at any depth.

    A block mapping contains every task inside it, so counting one would match every manager in the
    file and name the block instead of the install. Blocks are walked into, never reported.
    """
    if isinstance(node, dict):
        if any(k in node for k in ('block', 'rescue', 'always')):
            for value in node.values():
                yield from leaf_tasks(value)
            return
        yield node
        for value in node.values():
            yield from leaf_tasks(value)
    elif isinstance(node, list):
        for item in node:
            yield from leaf_tasks(item)


try:
    tasks = list(leaf_tasks(yaml.safe_load(text)))
except yaml.YAMLError as exc:
    print('FAIL the dispatcher does not parse as YAML, so this check proves nothing: %s' % exc)
    raise SystemExit(0)

lines = []
for manager in managers:
    needles = ['software_installer_batches.%s' % manager,
               "'equalto', '%s'" % manager,
               "'equalto',\n%s'" % manager]

    installers = []
    for task in tasks:
        if not isinstance(task.get('name'), str):
            continue
        # A set_fact derives one list from another and installs nothing.
        if any(k == 'set_fact' or k.endswith('.set_fact') for k in task):
            continue
        # changed_when: false is this repository declaring a task read-only. Asking pacman what is
        # installed, or tailing a log, is not an install and must not be judged as one.
        if task.get('changed_when') is False:
            continue
        # json rather than yaml.safe_dump, measured: safe_dump doubles every single quote, so
        # "'equalto', 'aur'" could never match the dumped form ''equalto'', ''aur''. Four managers
        # reported SKIP for exactly that, which read as "nothing installs this" when the loop was
        # right there.
        body = json.dumps({k: v for k, v in task.items()
                           if k not in ('when', 'name', 'tags', 'loop_control')}, default=str)
        body = re.sub(r'\s+', ' ', body)
        # A third shape: the task loops over a list some earlier set_fact derived, named after the
        # manager. apt_url and dnf_url install that way, over apt_url_items and dnf_url_items, so
        # neither the batch-list needle nor the selectattr needle can see them and both reported
        # SKIP, which reads as "nothing installs this" beside a loop that plainly does.
        loop_text = json.dumps(task.get('loop', ''), default=str)
        if any(re.sub(r'\s+', ' ', n) in body for n in needles) or manager in loop_text:
            installers.append(task)

    if not installers:
        lines.append('SKIP %s is named in the dispatcher and no task installs from it' % manager)
        continue

    looped = [t for t in installers if 'loop' in t or 'with_items' in t]
    handed_over = [t for t in installers if t not in looped]

    if manager in allowed:
        if handed_over:
            lines.append('OK %s batches %d task(s), allowed: %s'
                         % (manager, len(handed_over), allowed[manager]))
        else:
            lines.append('OK %s is allowed to batch and loops anyway, which is stricter than required'
                         % manager)
        continue

    if handed_over:
        names = ', '.join(t['name'] for t in handed_over)
        lines.append('FAIL %s hands its whole set to one call and is not in %s. One failure there '
                     'loses every package in the set. Loop it, or add it to that file with the '
                     'reason its solver needs the whole set. Task(s): %s'
                     % (manager, allowed_path.as_posix(), names))
    else:
        lines.append('OK %s installs one package at a time' % manager)

print('\n'.join(lines))
PYEOF
)"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        SKIP*) skip "every manager that cannot resolve a set together installs one at a time" "${line#SKIP }" ;;
        FAIL*) fail "a manager that cannot resolve a set together is installing it in one call" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the batched manager check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "batched managers"
