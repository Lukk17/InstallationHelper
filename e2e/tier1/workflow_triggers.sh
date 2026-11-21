#!/usr/bin/env bash
#
# Tier 1: no workflow, and no workflow a document shows, starts on anything but a dispatch or a call.
#
# AGENTS.md and e2e/AGENTS.md say no workflow may start on push or on any other automatic event, and
# every file under .github/workflows/ stays dispatch-only or call-only. Until 2026-11-21 the CI sketch
# of openspec/schemas/e2e-runbooks/INTEGRATION.md, which a project copies, started its sweep on
# `schedule: - cron: "0 6 * * *"` beside workflow_dispatch, docs/regression_ledger.md 10.382.
#
# It reads the `on:` of every workflow under .github/workflows/ and of every fenced YAML block in a
# markdown file git would ship that holds both `on:` and `jobs:`, the way YAML reads it, a bare
# string, a list or a mapping, and fails every trigger but workflow_dispatch and workflow_call, and a
# workflow with no `on:` at all. YAML 1.1 reads the key `on` as true, which is why both are read.
# docs/regression_ledger.md is left out by name, because its entries quote the tree of their day, and
# so are the agent tooling folders, .agents/, .claude/, .codex/, .opencode/, .kilo/ and .github/agents/,
# because their files are generated from agent-standards and describe other projects' pipelines. It
# fails when it reads no workflow. Before it reads the repository it runs its reader against planted
# files and requires it to name exactly the planted triggers.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

LABEL="workflow triggers"

info "Tier 1: every workflow, and every workflow a document shows, starts only on a dispatch or a call"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "${LABEL}"; }

require_python "every workflow starts only on a dispatch or a call" "${LABEL}"

mapfile -t markdown < <(git ls-files -co --exclude-standard -- '*.md' 2>/dev/null | sort)

report_status=0
report="$("${PYTHON}" - "${markdown[@]}" <<'PYEOF'
import pathlib
import re
import sys

import yaml

ALLOWED = {'workflow_dispatch', 'workflow_call'}
FENCE = re.compile(r'^```[ \t]*(ya?ml)[^\n]*\n(.*?)^```', re.S | re.M | re.I)
LEFT_OUT = {'docs/regression_ledger.md'}
IMPORTED = ('.agents/', '.claude/', '.codex/', '.opencode/', '.kilo/', '.github/agents/')


def triggers(document):
    """The trigger names of one workflow mapping, or None when it has no on key."""
    if True in document:
        on = document[True]
    elif 'on' in document:
        on = document['on']
    else:
        return None
    if isinstance(on, str):
        return [on]
    if isinstance(on, list):
        return [str(item) for item in on]
    if isinstance(on, dict):
        return [str(key) for key in on]
    return [repr(on)]


def read_workflow(name, text, sketch):
    problems = []
    try:
        documents = [d for d in yaml.safe_load_all(text) if d is not None]
    except yaml.YAMLError as error:
        if sketch:
            return problems, 0
        return ['%s does not parse as YAML: %s' % (name, error)], 0
    read = 0
    for document in documents:
        if not isinstance(document, dict):
            continue
        if sketch and not ('jobs' in document and (True in document or 'on' in document)):
            continue
        read += 1
        names = triggers(document)
        if names is None:
            problems.append('%s has no on: key, so nothing says what starts it' % name)
            continue
        for trigger in names:
            if trigger not in ALLOWED:
                problems.append('%s starts on %s, an event nobody asked for in the moment' % (name, trigger))
    return problems, read


def read_markdown(name, text):
    problems, read = [], 0
    for match in FENCE.finditer(text):
        line = text.count('\n', 0, match.start()) + 1
        found, count = read_workflow('%s:%d' % (name, line), match.group(2), True)
        problems += found
        read += count
    return problems, read


PLANTED = {
    'push.yml': 'on:\n  push:\n    branches: [master]\n  workflow_dispatch:\njobs: {}\n',
    'listed.yml': 'on: [pull_request, workflow_dispatch]\njobs: {}\n',
    'bare.yml': 'on: schedule\njobs: {}\n',
    'none.yml': 'name: x\njobs: {}\n',
    'sound.yml': 'on:\n  workflow_dispatch:\n    inputs: {}\njobs: {}\n',
    'called.yml': '"on":\n  workflow_call:\njobs: {}\n',
}
PLANTED_MD = ('Text.\n\n```yaml\non:\n  workflow_dispatch:\n  schedule:\n    - cron: "0 6 * * *"\njobs:\n  a: {}\n```\n\n'
              '```yaml\non:\n  workflow_dispatch:\njobs:\n  a: {}\n```\n\n```yaml\nschedule: not a workflow\n```\n\n'
              '```bash\non: push\n```\n')
planted = []
for planted_name, planted_text in sorted(PLANTED.items()):
    planted += read_workflow(planted_name, planted_text, False)[0]
planted += read_markdown('planted.md', PLANTED_MD)[0]
wanted = ['push.yml starts on push', 'listed.yml starts on pull_request', 'bare.yml starts on schedule',
          'none.yml has no on:', 'planted.md:3 starts on schedule']
named = [next((p for p in planted if w in p), None) for w in wanted]
if len(planted) != len(wanted) or None in named:
    print('FAIL the reader, run against planted files, named %d triggers where it must name exactly the %d planted '
          'ones: %s' % (len(planted), len(wanted), ' | '.join(planted) or 'none'))
    sys.exit(0)

problems, workflows, sketches = [], 0, 0
for path in sorted(pathlib.Path('.github/workflows').glob('*.y*ml')):
    found, count = read_workflow(path.as_posix(), path.read_text(encoding='utf-8'), False)
    problems += found
    workflows += count
for name in sys.argv[1:]:
    path = pathlib.Path(name)
    if name in LEFT_OUT or name.startswith(IMPORTED) or not path.is_file():
        continue
    found, count = read_markdown(name, path.read_text(encoding='utf-8'))
    problems += found
    sketches += count
if workflows == 0:
    print('FAIL the reader read no workflow under .github/workflows, so nothing is proven')
    sys.exit(0)
for problem in problems:
    print('FAIL %s' % problem)
if not problems:
    print('OK every workflow starts only on workflow_dispatch or workflow_call, %d under .github/workflows and %d '
          'shown in markdown files, and the reader named the %d planted triggers' % (workflows, sketches, len(wanted)))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "${LABEL}"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "every workflow starts only on a dispatch or a call" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the workflow trigger reader printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "${LABEL}"
