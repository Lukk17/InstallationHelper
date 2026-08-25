#!/usr/bin/env bash
#
# Tier 1: the single-platform workflow prepares a runner the same way the sweep does.
#
# Two workflows run the same wizard on the same runner images. e2e-matrix.yml runs everything, and
# e2e-manual.yaml runs one platform per dispatch, which is what you reach for when only one platform
# changed. The wizard is the same, so whatever the runner needs before the wizard is the same too.
#
# Three defects in a row on 2026-08-24 were all this, and all found within two hours of the first
# time anybody dispatched the manual workflow at its Windows target:
#
#   1. it splatted an array, so the wizard died on argument binding in sixteen seconds
#   2. it allowed 60 minutes for work the sweep gives 150, so it was killed mid-install
#   3. it never freed disk space, so the disk filled 65 minutes in
#
# The third is the one this check is about, and it is the worst of the three to read. The runner ships
# roughly 20 GB of toolchains this project never touches, the sweep deletes them before installing,
# and this job did not. So winget started failing every package with
# `0x80073cfc : The application cannot be started` and only the very last line of the job said what
# had actually happened: "There is not enough space on the disk". A reader who stopped at the first
# error would have gone looking for a broken package.
#
# It happened a fourth time on 2026-08-25, and that is why this check now compares three things
# rather than two. The macOS job never ran `brew install bash`, which every macOS cell in the sweep
# has run since the day macOS was added, so the wizard refused on its first line: macOS ships bash
# 3.2 because bash 4 went GPLv3, and setup/setup.sh needs bash 4. Seventeen seconds, and the previous
# version of this check passed the file happily because the missing thing was neither an action nor a
# disk cleanup.
#
# The rule compares capability rather than text, so it survives the two files wording a step
# differently. For each platform both workflows cover:
#
#   - every action the sweep's job uses (actions/upload-artifact and friends) must be used by the
#     single-platform job too
#   - if the sweep's job frees disk space, the single-platform job must free disk space
#   - every setup tool the sweep invokes before the wizard must be invoked by the single-platform job
#
# What it deliberately does not do is compare step lists. The sweep runs four Windows cells with
# different toggles and the manual job runs one parameterised by dispatch input, so their steps
# legitimately differ. Only the preparation the runner needs has to match.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: both workflows prepare a runner the same way"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "workflow parity"; }

report="$("${PYTHON:-python}" - <<'PYEOF'
import pathlib
import re

import yaml

MATRIX = pathlib.Path('.github/workflows/e2e-matrix.yml')
MANUAL = pathlib.Path('.github/workflows/e2e-manual.yaml')

for path in (MATRIX, MANUAL):
    if not path.exists():
        print('FAIL %s is missing, so this check proves nothing' % path.as_posix())
        raise SystemExit(0)

matrix = yaml.safe_load(MATRIX.read_text(encoding='utf-8'))
manual = yaml.safe_load(MANUAL.read_text(encoding='utf-8'))

# The names of the paths the sweep deletes are what "frees disk space" means concretely. Matching on
# any of them rather than on a step name means a step that was renamed still counts, and a step that
# was renamed to look like a cleanup while deleting nothing does not.
FREES_DISK = re.compile(r'hostedtoolcache|/usr/share/dotnet|Miniconda|ghcup', re.IGNORECASE)


def install_jobs(doc, prefix):
    """Jobs on this runner family that run long enough to be real installs rather than probes."""
    found = {}
    for name, job in (doc.get('jobs') or {}).items():
        if not isinstance(job, dict):
            continue
        runs_on = job.get('runs-on')
        ceiling = job.get('timeout-minutes')
        if not isinstance(runs_on, str) or not runs_on.startswith(prefix):
            continue
        if not isinstance(ceiling, int) or ceiling < 30:
            continue
        found[name] = job
    return found


# The tools a preparation step invokes. A whitelist rather than every word, because the interesting
# question is "does this job bootstrap the same things", and a whitelist says what was compared
# instead of drowning in shell builtins. Add to it when a new bootstrap tool appears.
SETUP_TOOLS = ('brew', 'apt-get', 'dnf', 'pacman', 'choco', 'winget', 'npm',
               'Add-AppxPackage', 'wsl', 'docker')


def capabilities(job):
    uses = set()
    frees = False
    tools = set()
    for step in job.get('steps') or []:
        if not isinstance(step, dict):
            continue
        if isinstance(step.get('uses'), str):
            uses.add(step['uses'].split('@')[0])
        body = step.get('run')
        if not isinstance(body, str):
            continue
        if FREES_DISK.search(body):
            frees = True
        # The wizard step itself is excluded: it is the work, not the preparation, and the two
        # workflows legitimately invoke it with different arguments.
        if 'setup.sh' in body or 'setup.ps1' in body:
            continue
        for tool in SETUP_TOOLS:
            if re.search(r'(?<![\w.-])%s(?![\w-])' % re.escape(tool), body):
                tools.add(tool)
    return uses, frees, tools


lines = []
for label, prefix in (('Windows', 'windows-'), ('macOS', 'macos-')):
    sweep = install_jobs(matrix, prefix)
    single = install_jobs(manual, prefix)

    if not sweep or not single:
        lines.append('SKIP %s: one of the two workflows has no install job on this runner family, '
                     'so there is nothing to compare' % label)
        continue

    # The union across the sweep's cells, because a capability any cell needs is one the single
    # platform job needs when it runs that same work.
    sweep_uses = set()
    sweep_frees = False
    sweep_tools = set()
    for job in sweep.values():
        uses, frees, tools = capabilities(job)
        sweep_uses |= uses
        sweep_frees = sweep_frees or frees
        sweep_tools |= tools

    problems = []
    for name, job in single.items():
        uses, frees, tools = capabilities(job)
        missing = sweep_uses - uses
        if missing:
            problems.append('%s does not use %s' % (name, ', '.join(sorted(missing))))
        if sweep_frees and not frees:
            problems.append('%s never frees disk space while every sweep cell does, so the runner '
                            'fills and winget reports every package as broken' % name)
        missing_tools = sweep_tools - tools
        if missing_tools:
            problems.append('%s never invokes %s before the wizard while the sweep does, so whatever '
                            'that step bootstraps is absent' % (name, ', '.join(sorted(missing_tools))))

    if problems:
        lines.append('FAIL %s: %s' % (label, '; '.join(problems)))
    else:
        lines.append('OK %s: %d single-platform job(s) match the sweep on %d action(s), %d setup '
                     'tool(s) and on freeing disk space'
                     % (label, len(single), len(sweep_uses), len(sweep_tools)))

print('\n'.join(lines))
PYEOF
)"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        SKIP*) skip "both workflows prepare a runner the same way" "${line#SKIP }" ;;
        FAIL*) fail "the single-platform workflow prepares its runner differently from the sweep" \
                    "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the parity check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "workflow parity"
