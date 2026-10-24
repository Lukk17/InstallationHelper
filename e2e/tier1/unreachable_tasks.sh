#!/usr/bin/env bash
#
# Tier 1: no task is gated on a toggle the container tier switches off everywhere it could run.
#
# The harness applies container_limits.yaml to every scenario and container_limits.<os>.yaml on top of
# it for one image. A toggle switched off there is a toggle no scenario can ever set, so every task
# gated on it is skipped in every run of the whole suite. Tier 1 does not execute anything and tier 2
# only resolves names, so such a task has no automated coverage at all, anywhere.
#
# That is not a theory. Until 2026-08-28 the CachyOS 32-bit graphics alignment task was gated on
# ih_os_release_id == 'cachyos' and install_steam, and container_limits.cachyos.yaml set install_steam
# to false. The only image that could run the task was the only image where the toggle was off, so
# that shell was never executed by the suite, not once. It shipped with `yes |` under `set -o pipefail`
# and reported failure on a pacman that had succeeded, and the first thing to find out was a person
# installing a real machine, fourteen minutes into a run that then installed nothing.
#
# The suppression itself was also wrong on the facts, which is the second half of the lesson: it was
# justified by a content delivery network answering 404 for two packages, and re-measured, those exact
# builds answer 200 on mirror.cachyos.org. A suppression nobody rechecks becomes permanent.
#
# So each entry in uncovered_toggles_allowed.txt is a written admission that a feature is tested by
# hand or not at all, and anything not listed fails this check. The list is meant to be short and to
# get shorter.
#
# A task may also be gated on a fact derived from toggles rather than on a toggle. That same CachyOS task
# is gated on ih_steam_requested now, which tasks/steam_graphics_alignment.yaml sets true when
# install_steam asks for Steam or when a mapping marked brings_steam: true is toggled on, which on
# CachyOS is install_gaming_suite, and for a while this check read no toggle in its `when` at all and so
# could not see it. DERIVED_FACTS_DECLARED below names each such fact with the toggles it names
# literally and the mapping attribute it reads, the toggles behind that attribute are read from the
# vars files, and the check fails when the file that sets the fact stops reading exactly those, so the
# table cannot drift from the fact. A task gated on a derived fact is dead only when every toggle behind
# it is switched off on every image that can run the task.
#
# What this check does not do is solve conditions. It reads the toggles a task's `when` names, the
# derived facts listed below, and the image a task's `when` pins itself to, and nothing more. A task
# made unreachable by some subtler combination of facts will not be caught here, and that is a known
# limit rather than an oversight.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: no task is gated on a toggle the container tier switches off everywhere it could run"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "unreachable tasks"; }

require_python "no task is gated on a toggle the container tier switches off everywhere it could run" "unreachable tasks"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re

import yaml

REPO = pathlib.Path('.')
TIER3 = REPO / 'e2e' / 'tier3'
ALLOWED = REPO / 'e2e' / 'tier1' / 'uncovered_toggles_allowed.txt'
ANSIBLE = REPO / 'setup' / 'ansible'

TOGGLE = re.compile(r'\b((?:install|configure|setup|remove)_[a-z0-9_]+)\b')
PINNED_ID = re.compile(r"ih_os_release_id\s*==\s*'([a-z0-9_]+)'")

# fact -> (the task file that sets it, the toggles it names literally, the mapping attribute it reads
# or None). A mapping attribute stands for install_<key> of every software_mapping entry in
# setup/ansible/vars/*.yaml and vars/derivatives/*.yaml that sets it true, read from those files here
# rather than written down, so a new mapping that brings Steam is covered on the day it is added.
DERIVED_FACTS_DECLARED = {
    'ih_steam_requested': (ANSIBLE / 'tasks' / 'steam_graphics_alignment.yaml',
                           frozenset({'install_steam'}), 'brings_steam'),
}

lines = []


def uncommented(path):
    return '\n'.join(text_line for text_line in path.read_text(encoding='utf-8').splitlines()
                     if not text_line.lstrip().startswith('#'))


def toggles_of_mappings_with(attribute):
    found = set()
    for vars_file in sorted((ANSIBLE / 'vars').glob('*.yaml')) + sorted((ANSIBLE / 'vars' / 'derivatives').glob('*.yaml')):
        data = yaml.safe_load(vars_file.read_text(encoding='utf-8')) or {}
        for key, entry in ((data.get('software_mapping') or {}).items()):
            if isinstance(entry, dict) and entry.get(attribute) is True:
                found.add('install_%s' % key)
    return found


drifted = False
DERIVED_FACTS = {}
for fact, (source, literal, attribute) in DERIVED_FACTS_DECLARED.items():
    if not source.is_file():
        lines.append('DRIFT %s is said to be set by %s, which does not exist' % (fact, source.as_posix()))
        drifted = True
        continue
    text = uncommented(source)
    read = set(TOGGLE.findall(text))
    if fact not in text or read != literal or (attribute and attribute not in text):
        lines.append('DRIFT %s, which sets %s, reads the toggles %s%s, and DERIVED_FACTS_DECLARED in '
                     'e2e/tier1/unreachable_tasks.sh says %s%s. Make the table match the file.'
                     % (source.as_posix(), fact, ', '.join(sorted(read)) or 'none',
                        ' and the mapping attribute %s' % attribute if attribute and attribute in text else
                        ' and no mapping attribute' if attribute else '',
                        ', '.join(sorted(literal)),
                        ' plus every mapping with %s: true' % attribute if attribute else ''))
        drifted = True
        continue
    DERIVED_FACTS[fact] = (source, frozenset(literal | (toggles_of_mappings_with(attribute) if attribute else set())))
if drifted:
    print('\n'.join(lines))
    raise SystemExit(0)

# The image list comes from the Dockerfiles rather than a list written here, so an image added
# tomorrow is covered without anybody remembering this file.
images = sorted(p.name[:-len('.Dockerfile')] for p in TIER3.glob('*.Dockerfile'))

shared = TIER3 / 'container_limits.yaml'
if not images or not shared.is_file():
    print('FAIL the tier 3 images or the shared limits file could not be read, so this check proves '
          'nothing')
    raise SystemExit(0)


def limits_of(path):
    data = yaml.safe_load(path.read_text(encoding='utf-8')) or {}
    return {k for k, v in data.items() if v is False}


# suppressed[image] is every toggle forced false for that image, shared plus its own file.
base = limits_of(shared)
suppressed = {}
for image in images:
    per_os = TIER3 / ('container_limits.%s.yaml' % image)
    suppressed[image] = set(base)
    if per_os.is_file():
        suppressed[image] |= limits_of(per_os)

allowed = {}
if ALLOWED.is_file():
    for raw in ALLOWED.read_text(encoding='utf-8').splitlines():
        raw = raw.strip()
        if not raw or raw.startswith('#'):
            continue
        toggle, _, reason = raw.partition(' ')
        allowed[toggle] = reason.strip()


def walk(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for item in node:
            yield from walk(item)


def when_text(task):
    cond = task.get('when')
    if isinstance(cond, str):
        return cond
    if isinstance(cond, list):
        return ' and '.join(str(c) for c in cond)
    return ''


# toggle -> set of task labels that no image can ever run.
dead = {}
tasks_read = 0

for path in sorted(ANSIBLE.rglob('*.yaml')):
    try:
        doc = yaml.safe_load(path.read_text(encoding='utf-8'))
    except (yaml.YAMLError, UnicodeDecodeError):
        continue
    for task in walk(doc):
        if not isinstance(task.get('name'), str) or 'when' not in task:
            continue
        tasks_read += 1
        text = when_text(task)
        # gates[name] is the set of toggles of which at least one must be on for the task to run. A
        # toggle stands alone, a derived fact stands for every toggle behind it.
        gates = {t: {t} for t in TOGGLE.findall(text)}
        gates.update({f: set(t) for f, (_, t) in DERIVED_FACTS.items()
                      if re.search(r'\b%s\b' % re.escape(f), text)})
        gates = {g: t for g, t in gates.items() if any(t <= s for s in suppressed.values())}
        if not gates:
            continue
        pinned = set(PINNED_ID.findall(text))
        reachable = sorted(pinned & set(images)) if pinned else images
        if not reachable:
            continue
        for gate, behind in gates.items():
            if all(behind <= suppressed[image] for image in reachable):
                label = '%s :: %s' % (path.as_posix(), task['name'])
                dead.setdefault(gate, []).append((label, reachable))

if not tasks_read:
    print('FAIL no conditional task was read, so this check proves nothing')
    raise SystemExit(0)

unlisted = sorted(t for t in dead if t not in allowed)
for toggle in unlisted:
    victims = dead[toggle]
    where = ', '.join(sorted({i for _, r in victims for i in r}))
    example = victims[0][0]
    named = toggle
    if toggle in DERIVED_FACTS:
        named = '%s, through every toggle behind it (%s),' % (
            toggle, ', '.join(sorted(DERIVED_FACTS[toggle][1])))
    lines.append('FAIL %s is switched off by the container limits on every image that could run the '
                 '%d task(s) gated on it (%s), so nothing in the whole suite ever executes them. '
                 'First one: %s. Either stop suppressing the toggle, or add a line to '
                 'e2e/tier1/uncovered_toggles_allowed.txt saying what that costs and how it is '
                 'tested instead.' % (named, len(victims), where, example))

stale = sorted(t for t in allowed if t not in dead)
for toggle in stale:
    lines.append('FAIL %s is listed in e2e/tier1/uncovered_toggles_allowed.txt and is not actually '
                 'suppressed any more. Delete the line, or the file stops meaning anything.' % toggle)

if not unlisted and not stale:
    lines.append('OK %d conditional tasks read across %d images, every uncovered toggle is listed '
                 'with a reason' % (tasks_read, len(images)))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "unreachable tasks"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a task is gated on a toggle nothing in the suite can switch on" "${line#FAIL }" ;;
        DRIFT*) fail "a derived fact no longer stands for the toggles this check maps it to" "${line#DRIFT }" ;;
        *)     [[ -n "${line}" ]] && fail "the unreachable task check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "unreachable tasks"
