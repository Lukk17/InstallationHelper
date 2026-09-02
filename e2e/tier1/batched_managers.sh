#!/usr/bin/env bash
#
# Tier 1: no package manager installs its whole set in one call.
#
# A batch is a single call with a single exit code. So when one package in it is unavailable, the call
# fails, and everything upstream hears that the install failed with no way to know which package
# broke, how many installed before it, or how many were never attempted.
#
# That cost this repository the entire set three times in four days:
#
#   a flatpak fetch timing out          twenty-two applications lost, on twenty of forty-eight cells
#   a deleted Tor Browser build         roughly thirty Homebrew casks lost, twice in two days
#   one Chocolatey package failing      every package in the batch reported failed
#
# For a while apt, dnf and pacman were allowed to batch, on the argument that their solvers work on
# the whole set. Both halves of that argument were tested and neither survived.
#
# The speed half was measured on 2026-08-25 in debian:trixie, twenty-two packages taken from the real
# Debian mapping, two samples each way, with apt-get update run in both and not timed:
#
#   no recommends       batched 250s and 199s        looped 278s and 244s
#   with recommends     batched 274s                 looped 264s
#
# Both shapes ended with identical package counts. Looping cost eleven and twenty-three per cent on
# the first set and saved four per cent on the second, while two identical batched runs of the first
# set differed from each other by twenty per cent. The noise is the same size as the effect, and the
# absolute figure is tens of seconds inside a scenario that runs thirty to a hundred minutes.
#
# The correctness half was real: a single solve cannot pick a library version or a virtual-package
# provider that a later package rejects, and a loop can. That is now answered where it belongs, by a
# guard. Each family asks its own package manager after the installs whether the set it produced is
# consistent, `apt-get check`, `dnf check --dependencies` and `pacman -Dk`, and names what is broken.
# A batch hid that question. A guard answers it.
#
# So there is no allowlist any more. There used to be a file of exceptions with reasons, and a file of
# exceptions is an invitation to add the next one.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: no manager installs its whole set in one call"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "batched managers"; }

DISPATCH="setup/ansible/roles/software_installer/tasks/dynamic_install.yaml"

if [[ ! -f "${DISPATCH}" ]]; then
    fail "the software installer dispatcher is missing, so this check proves nothing" "${DISPATCH}"
    finish "batched managers"
    return 0 2>/dev/null || exit 0
fi

require_python "no manager installs its whole set in one call" "batched managers"

report_status=0
report="$("${PYTHON}" - "${DISPATCH}" <<'PYEOF'
import json
import pathlib
import re
import sys

import yaml

dispatch = pathlib.Path(sys.argv[1])
text = dispatch.read_text(encoding='utf-8')

# Managers are read out of the file rather than listed here, so one added tomorrow is covered without
# anybody remembering to add it. Three shapes exist: a prebuilt list, a list filtered inline out of
# the package set, and a list an earlier set_fact derived and named after the manager.
managers = set(re.findall(r'software_installer_batches\.([a-z_]+)', text))
managers |= set(re.findall(r"selectattr\(\s*'value\.manager'\s*,\s*'equalto'\s*,\s*'([a-z_]+)'", text))
managers = sorted(managers)

if not managers:
    print('FAIL the dispatcher names no package managers, so this check proves nothing')
    raise SystemExit(0)


def leaf_tasks(node):
    """Every task mapping that is not a block. A block contains every task inside it."""
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
               "'equalto', '%s'" % manager]

    installers = []
    for task in tasks:
        if not isinstance(task.get('name'), str):
            continue
        if any(k == 'set_fact' or k.endswith('.set_fact') for k in task):
            continue
        # changed_when: false is this repository declaring a task read-only. A query is not an
        # install and must not be judged as one, which is what keeps the new consistency guards out
        # of this comparison.
        if task.get('changed_when') is False:
            continue
        body = json.dumps({k: v for k, v in task.items()
                           if k not in ('when', 'name', 'tags', 'loop_control')}, default=str)
        body = re.sub(r'\s+', ' ', body)
        loop_text = json.dumps(task.get('loop', ''), default=str)
        if any(re.sub(r'\s+', ' ', n) in body for n in needles) or manager in loop_text:
            installers.append(task)

    if not installers:
        lines.append('SKIP %s is named in the dispatcher and no task installs from it' % manager)
        continue

    handed_over = [t for t in installers if 'loop' not in t and 'with_items' not in t]
    if handed_over:
        names = ', '.join(t['name'] for t in handed_over)
        lines.append('FAIL %s hands its whole set to one call. One failure there loses every package '
                     'in the set and nothing can say which one broke. Loop it. Task(s): %s'
                     % (manager, names))
    else:
        lines.append('OK %s installs one package at a time' % manager)

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "batched managers"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        SKIP*) skip "every manager installs one package at a time" "${line#SKIP }" ;;
        FAIL*) fail "a manager installs its whole set in one call" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the batched manager check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "batched managers"
