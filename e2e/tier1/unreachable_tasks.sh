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
# What this check does not do is solve conditions. It reads the toggles a task's `when` names and the
# image a task's `when` pins itself to, and nothing more. A task made unreachable by some subtler
# combination of facts will not be caught here, and that is a known limit rather than an oversight.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: no task is gated on a toggle the container tier switches off everywhere it could run"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "unreachable tasks"; }

report="$("${PYTHON:-python}" - <<'PYEOF'
import pathlib
import re

import yaml

REPO = pathlib.Path('.')
TIER3 = REPO / 'e2e' / 'tier3'
ALLOWED = REPO / 'e2e' / 'tier1' / 'uncovered_toggles_allowed.txt'
ANSIBLE = REPO / 'setup' / 'ansible'

TOGGLE = re.compile(r'\b((?:install|configure|setup|remove)_[a-z0-9_]+)\b')
PINNED_ID = re.compile(r"ih_os_release_id\s*==\s*'([a-z0-9_]+)'")

lines = []

# The image list comes from the Dockerfiles rather than a list written here, so an image added
# tomorrow is covered without anybody remembering this file. queue is the driver container and runs no
# scenario.
images = sorted(p.name[:-len('.Dockerfile')] for p in TIER3.glob('*.Dockerfile')
                if p.name != 'queue.Dockerfile')

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
        toggles = {t for t in TOGGLE.findall(text) if any(t in s for s in suppressed.values())}
        if not toggles:
            continue
        pinned = set(PINNED_ID.findall(text))
        reachable = sorted(pinned & set(images)) if pinned else images
        if not reachable:
            continue
        for toggle in toggles:
            if all(toggle in suppressed[image] for image in reachable):
                label = '%s :: %s' % (path.as_posix(), task['name'])
                dead.setdefault(toggle, []).append((label, reachable))

if not tasks_read:
    print('FAIL no conditional task was read, so this check proves nothing')
    raise SystemExit(0)

unlisted = sorted(t for t in dead if t not in allowed)
for toggle in unlisted:
    victims = dead[toggle]
    where = ', '.join(sorted({i for _, r in victims for i in r}))
    example = victims[0][0]
    lines.append('FAIL %s is switched off by the container limits on every image that could run the '
                 '%d task(s) gated on it (%s), so nothing in the whole suite ever executes them. '
                 'First one: %s. Either stop suppressing the toggle, or add a line to '
                 'e2e/tier1/uncovered_toggles_allowed.txt saying what that costs and how it is '
                 'tested instead.' % (toggle, len(victims), where, example))

stale = sorted(t for t in allowed if t not in dead)
for toggle in stale:
    lines.append('FAIL %s is listed in e2e/tier1/uncovered_toggles_allowed.txt and is not actually '
                 'suppressed any more. Delete the line, or the file stops meaning anything.' % toggle)

if not unlisted and not stale:
    lines.append('OK %d conditional tasks read across %d images, every uncovered toggle is listed '
                 'with a reason' % (tasks_read, len(images)))

print('\n'.join(lines))
PYEOF
)"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a task is gated on a toggle nothing in the suite can switch on" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the unreachable task check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "unreachable tasks"
