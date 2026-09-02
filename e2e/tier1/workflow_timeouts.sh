#!/usr/bin/env bash
#
# Tier 1: the single-platform workflow gives each platform at least as long as the sweep does.
#
# Two workflows run the same wizard against the same platforms. e2e-matrix.yml runs everything, and
# e2e-manual.yaml runs one platform per dispatch, which is what you reach for when only one platform
# changed and a three hour sweep would be waste. Same work, so the same work needs the same time.
#
# It did not have it. The Windows job in the manual workflow carried timeout-minutes: 60 while every
# Windows cell in the matrix carried 150 for the identical run, and that identical run had just taken
# 94 minutes for `Windows all apps` and 100 for `Windows default apps` in sweep 32739529615. So run
# 32763779284 was killed at 60 minutes and 32 seconds while still installing, and the run list called
# it "cancelled", which reads like somebody pressed a button rather than like a ceiling that was
# never large enough.
#
# That is a nasty failure to diagnose from the outside, because a cancelled run carries no error and
# no failing step. The only tell is the duration sitting suspiciously close to a round number.
#
# So: for every platform both workflows cover, the manual ceiling must be greater than or equal to
# the matrix ceiling. Greater is fine, the manual entry point accepts arbitrary key lists the matrix
# never runs. Smaller is a job that cannot finish work the other one finishes.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: the single-platform workflow allows as much time as the sweep"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "workflow timeouts"; }

require_python "the single-platform workflow allows as much time as the sweep" "workflow timeouts"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib

import yaml

MATRIX = pathlib.Path('.github/workflows/e2e-matrix.yml')
MANUAL = pathlib.Path('.github/workflows/e2e-manual.yaml')

for path in (MATRIX, MANUAL):
    if not path.exists():
        print('FAIL %s is missing, so this check proves nothing' % path.as_posix())
        raise SystemExit(0)

matrix = yaml.safe_load(MATRIX.read_text(encoding='utf-8'))
manual = yaml.safe_load(MANUAL.read_text(encoding='utf-8'))


def ceilings(doc, predicate):
    """Every timeout-minutes among the jobs the predicate selects, as ints."""
    found = []
    for name, job in (doc.get('jobs') or {}).items():
        if not isinstance(job, dict):
            continue
        if not predicate(name, job):
            continue
        value = job.get('timeout-minutes')
        if isinstance(value, int):
            found.append((name, value))
    return found


# The jobs that run the real wizard rather than a static check. A wizard job is the one that runs for
# hours, and on both sides it is identified by its runner plus the absence of a plan-only shape, so a
# new job added to either workflow is covered without being named here.
def is_wizard(runner_prefix, minimum):
    def predicate(name, job):
        runs_on = job.get('runs-on')
        if not isinstance(runs_on, str) or not runs_on.startswith(runner_prefix):
            return False
        value = job.get('timeout-minutes')
        # A five minute job is a plan or a probe, not an install. The cut is deliberately low so a
        # real install job can never be excluded by it.
        return isinstance(value, int) and value >= minimum
    return predicate


lines = []
for label, prefix in (('Windows', 'windows-'), ('macOS', 'macos-')):
    matrix_jobs = ceilings(matrix, is_wizard(prefix, 30))
    manual_jobs = ceilings(manual, is_wizard(prefix, 30))

    if not matrix_jobs:
        lines.append('SKIP the sweep has no %s install job with a ceiling, so there is nothing to '
                     'compare against' % label)
        continue
    if not manual_jobs:
        lines.append('SKIP the single-platform workflow has no %s install job with a ceiling' % label)
        continue

    needed = max(v for _, v in matrix_jobs)
    worst_name, worst = min(manual_jobs, key=lambda pair: pair[1])
    if worst < needed:
        lines.append('FAIL %s: the sweep allows %d minutes and %s in the single-platform workflow '
                     'allows %d, so it cannot finish work the sweep finishes and will be killed '
                     'mid-install and reported as cancelled'
                     % (label, needed, worst_name, worst))
    else:
        lines.append('OK %s: the sweep allows %d minutes and the single-platform workflow allows %d'
                     % (label, needed, worst))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "workflow timeouts"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        SKIP*) skip "both workflows allow the same time per platform" "${line#SKIP }" ;;
        FAIL*) fail "the single-platform workflow allows less time than the sweep for the same work" \
                    "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the timeout check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "workflow timeouts"
