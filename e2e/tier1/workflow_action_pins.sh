#!/usr/bin/env bash
#
# Tier 1: every action a workflow or a local action pulls from another repository is pinned to a commit.
#
# Until 2026-11-21 every workflow under .github/workflows and the local action load-gate-image named
# actions/checkout, actions/upload-artifact and actions/download-artifact by the moving tag v4. A tag can
# be moved to other code, and those three v4 releases run on Node.js 20, so every job of run 44334176847
# ended with `Node.js 20 is deprecated. The following actions target Node.js 20 but are being forced to
# run on Node.js 24: actions/checkout@v4, actions/upload-artifact@v4`, docs/regression_ledger.md 10.376.
#
# So every `uses:` under .github/workflows and .github/actions that does not start with ./ must name
# owner/repo, or owner/repo/path, at a 40 character lowercase commit SHA, on a line of its own, and that
# line must end in a comment naming the release the SHA is, `# vX.Y.Z`. The SHAs are taken from the
# YAML, so a `uses:` written in flow style or quoted is still read, and the comments from the lines
# that carry each one, because YAML drops comments. A `uses:` the YAML holds on no line of its own
# fails, because its comment cannot be read. Whether the comment names the release the SHA really is
# needs the network, which tier 1 does not reach, so that stays a review question.
#
# It fails when it finds no external `uses:` at all. Before it reads the repository it runs its reader
# against planted files and requires it to name exactly the eight planted defects and nothing in the
# sound file, so a reader that went blind fails here instead of passing the real tree.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: every external action is pinned to a commit SHA with its version beside it"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "action pins"; }

require_python "every external action is pinned to a commit SHA with its version beside it" "action pins"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re

import yaml

PINNED = re.compile(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[^@\s]+)?@[0-9a-f]{40}$')
USES_LINE = re.compile(r'''^\s*(?:-\s+)?uses:\s*(['"]?)([^'"\s#]+)\1\s*(#.*)?$''')
VERSION_COMMENT = re.compile(r'^#\s*v\d+\.\d+\.\d+\s*$')
SHA = '3d3c42e5aac5ba805825da76410c181273ba90b1'


def yaml_uses(doc):
    """Every uses value of a workflow's jobs and steps or of an action's steps, as YAML reads them."""
    found = []

    def from_steps(steps):
        for step in steps or []:
            if isinstance(step, dict) and isinstance(step.get('uses'), str):
                found.append(step['uses'].strip())

    if isinstance(doc, dict):
        for job in (doc.get('jobs') or {}).values():
            if isinstance(job, dict):
                if isinstance(job.get('uses'), str):
                    found.append(job['uses'].strip())
                from_steps(job.get('steps'))
        runs = doc.get('runs')
        if isinstance(runs, dict):
            from_steps(runs.get('steps'))
    return found


def file_problems(label, text):
    """Returns the number of external uses in one file and what is wrong with them."""
    comments = {}
    for line in text.splitlines():
        match = USES_LINE.match(line)
        if match:
            comments.setdefault(match.group(2), []).append((match.group(3) or '').strip())
    external = [value for value in yaml_uses(yaml.safe_load(text)) if not value.startswith('./')]
    problems = []
    for value in sorted(set(external)):
        if not PINNED.match(value):
            problems.append('%s uses %s, which is not pinned to a 40 character commit SHA' % (label, value))
            continue
        seen = comments.get(value, [])
        if len(seen) != external.count(value):
            problems.append('%s uses %s %d time(s) and only %d line(s) carry it on their own, so its version '
                            'comment cannot be read' % (label, value, external.count(value), len(seen)))
            continue
        loose = [comment or 'no comment' for comment in seen if not VERSION_COMMENT.match(comment)]
        if loose:
            problems.append('%s uses %s with %s where the line must end in # vX.Y.Z'
                            % (label, value, ', '.join(sorted(set(loose)))))
    return len(external), problems


def planted():
    def step_file(*lines):
        return 'jobs:\n  one:\n    runs-on: ubuntu-latest\n    steps:\n' + ''.join('      %s\n' % line for line in lines)

    return {
        'tag.yml': step_file('- uses: actions/checkout@v4'),
        'branch.yml': step_file('- uses: actions/checkout@main'),
        'short.yml': step_file('- uses: actions/checkout@%s # v7.0.1' % SHA[:7]),
        'no-comment.yml': step_file('- uses: actions/checkout@%s' % SHA),
        'loose-comment.yml': step_file('- uses: actions/checkout@%s # v7' % SHA),
        'reusable.yml': 'jobs:\n  call:\n    uses: octo/repo/.github/workflows/x.yml@v1\n',
        'flow.yml': step_file("- {uses: 'actions/checkout@%s'} # v7.0.1" % SHA),
        'action.yml': 'runs:\n  using: composite\n  steps:\n    - uses: actions/download-artifact@v4\n',
        'sound.yml': step_file('- uses: actions/checkout@%s # v7.0.1' % SHA,
                               '- uses: "actions/checkout@%s"  # v7.0.1' % SHA,
                               '- uses: ./.github/actions/windows-pester',
                               '- name: Upload',
                               '  uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2')
               + '  call:\n    uses: ./.github/workflows/e2e-linux-cell.yml\n',
    }


lines = []

expected = {'tag.yml', 'branch.yml', 'short.yml', 'no-comment.yml', 'loose-comment.yml', 'reusable.yml', 'flow.yml',
            'action.yml'}
planted_problems = []
planted_external = {}
for label, text in sorted(planted().items()):
    count, found = file_problems(label, text)
    planted_external[label] = count
    planted_problems.extend((label, problem) for problem in found)
named = [label for label, _ in planted_problems]
if set(named) == expected and len(named) == len(expected) and planted_external.get('sound.yml') == 3:
    lines.append('OK the reader names exactly the eight planted defects and nothing in the sound file, '
                 'whose three external uses it reads')
else:
    lines.append('FAIL the reader misreads planted files, so nothing it says about the real ones can be trusted '
                 ':: expected one problem each in %s and three external uses in sound.yml, got %s, and %s external '
                 'uses in sound.yml' % (', '.join(sorted(expected)),
                                        ' | '.join(problem for _, problem in planted_problems) or 'none',
                                        planted_external.get('sound.yml')))

paths = sorted(pathlib.Path('.github/workflows').glob('*.y*ml')) + sorted(pathlib.Path('.github/actions').glob('*/action.y*ml'))
total, problems = 0, []
for path in paths:
    count, found = file_problems(path.as_posix(), path.read_text(encoding='utf-8'))
    total += count
    problems.extend(found)

if total == 0:
    lines.append('FAIL no workflow or local action uses an external action, so this check proves nothing :: read '
                 '%d file(s)' % len(paths))
elif problems:
    lines.append('FAIL an external action is not pinned to a commit SHA with its version beside it :: %s'
                 % ' | '.join(problems))
else:
    lines.append('OK all %d external uses in %d workflow and action file(s) name a commit SHA and end in # vX.Y.Z'
                 % (total, len(paths)))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "action pins"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) claim="${line#FAIL }"
               fail "${claim%% :: *}" "${claim#* :: }" ;;
        *)     [[ -n "${line}" ]] && fail "the action pins check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "action pins"
