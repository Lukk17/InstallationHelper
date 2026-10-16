#!/usr/bin/env bash
#
# Tier 1: the agent artifacts imported from agent-standards are not stale.
#
# .agents/, .claude/agents, .codex/agents, .github/ and opencode.json are pulled from upstream and
# never hand edited, so nothing in this repository changes them until somebody pulls again, and a
# stale copy works exactly as well as a fresh one until the day it is measured. On 2026-10-13 a
# measurement found three defects that had been shipping for exactly that reason. The plugin
# declared is_subagent as Boolean(sessionID), which is true for every session, so on OpenCode 1.x and
# Kilo Code the main thread was treated as a subagent and every main-thread rule allowed. The
# plugin's default export was a bare function, which OpenCode 2.x does not call, so it loaded
# nothing. And the read-only subagents listed only the tools they use, which OpenCode and Kilo read
# as overrides on top of every tool, so they could still edit and run commands. See
# docs/regression_ledger.md, 10.15 to 10.17.
#
# This cannot ask upstream whether the copy is current, because a hermetic gate has no upstream. It
# asserts the properties whose absence was the staleness instead, and runs the real plugin for the
# one that matters most. Nothing here is a hash of a file: a hash goes red on every legitimate
# upstream change and teaches people to refresh the number, and these properties only go red on the
# three defects above.
#
# The plugin run needs Node and is skipped, by name, without it. Everything else is text.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: the imported agent artifacts are not stale"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "imported agent artifacts"; }

require_python "the imported agent artifacts are not stale" "imported agent artifacts"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import json
import pathlib
import re

AGENTS = pathlib.Path('.agents/agents')
PLUGIN = pathlib.Path('.agents/plugin/hooks.js')
OUT = []


def ok(message):
    OUT.append('OK ' + message)


def bad(name, detail):
    OUT.append('FAIL %s|%s' % (name, detail))


def front_matter(path):
    text = path.read_text(encoding='utf-8')
    parts = text.split('---', 2)
    return parts[1] if len(parts) > 2 and text.startswith('---') else ''


def block_keys(front, key):
    """Child keys of a top-level mapping in a front matter, as {name: value}."""
    found = {}
    inside = False
    for line in front.splitlines():
        if re.match(r'^' + re.escape(key) + r':\s*$', line):
            inside = True
            continue
        if inside:
            child = re.match(r'^\s+([A-Za-z_]+):\s*(\S+)\s*$', line)
            if child:
                found[child.group(1)] = child.group(2).strip('"')
            elif line.strip():
                inside = False
    return found


# opencode.json names the plugin by directory and loads the reply rules.
try:
    config = json.loads(pathlib.Path('opencode.json').read_text(encoding='utf-8'))
except (OSError, ValueError) as exc:
    config = {}
    bad('opencode.json could not be read', str(exc))
plugins = config.get('plugin', [])
if './.agents/plugin' in plugins and pathlib.Path('.agents/plugin/index.js').is_file():
    ok('opencode.json declares the plugin by its directory and .agents/plugin/index.js exists')
else:
    bad('opencode.json does not declare the plugin by its directory',
        'plugin is %r. OpenCode 2.x and Kilo Code resolve a directory to its index.js, so the entry '
        'must be "./.agents/plugin" and that file must exist' % (plugins,))
if '.agents/instructions/reply-rules.md' in config.get('instructions', []) \
        and pathlib.Path('.agents/instructions/reply-rules.md').is_file():
    ok('opencode.json loads .agents/instructions/reply-rules.md and the file exists')
else:
    bad('the reply rules are not loaded by opencode.json',
        'instructions is %r' % (config.get('instructions'),))

# The plugin keeps the three properties that were missing.
try:
    plugin = PLUGIN.read_text(encoding='utf-8')
except OSError as exc:
    plugin = ''
    bad('the plugin could not be read', str(exc))
default_export = re.search(r'export\s+default\s*\{([^}]*)\}', plugin)
if default_export and re.search(r'\bserver\b', default_export.group(1)) \
        and re.search(r'\bsetup\b', default_export.group(1)):
    ok('the plugin default export is an object with server and setup, so OpenCode 1.x, 2.x and Kilo Code each find their entry')
else:
    bad('the plugin default export is not { id, server, setup }',
        'OpenCode 2.x calls setup and never server, and calls nothing at all on a bare function, so '
        'the gate did not load there (10.17)')
if re.search(r'is_subagent\s*:\s*Boolean\(', plugin):
    bad('the plugin decides is_subagent from the mere presence of a session',
        'Boolean(sessionID) is true for the main thread too, so every main-thread rule allowed on '
        'OpenCode 1.x and Kilo Code (10.15)')
else:
    ok('the plugin does not equate having a session with being a subagent')

# Reply style is checked on the main thread only, so nothing reply-style runs when a subagent stops.
try:
    claude = json.loads(pathlib.Path('.claude/settings.json').read_text(encoding='utf-8'))
except (OSError, ValueError) as exc:
    claude = {}
    bad('.claude/settings.json could not be read', str(exc))
reply_style = ('no_ai_markers_check.py', 'status_block_check.py', 'question_numbering_check.py')
subagent_stop = [entry.get('command', '') for group in claude.get('hooks', {}).get('SubagentStop', [])
                 for entry in group.get('hooks', [])]
styled = [c for c in subagent_stop if any(h in c for h in reply_style)]
if styled:
    bad('a reply-style check runs when a subagent stops',
        'nobody reads a subagent reply style, and a block costs the subagent a rewrite of its whole '
        'report (10.19): ' + '; '.join(styled))
else:
    ok('no reply-style check is wired on SubagentStop in .claude/settings.json')

# Every definition that lists no write, edit or bash tool is denied edit and bash by name.
names = {}
for tree, pattern in (('.agents/agents', '*.md'), ('.claude/agents', '*.md'),
                      ('.codex/agents', '*.toml'), ('.github/agents', '*.agent.md')):
    stems = set()
    for path in sorted(pathlib.Path(tree).glob(pattern)):
        stems.add(path.name.split('.')[0])
    names[tree] = stems
reference = names['.agents/agents']
for tree, stems in names.items():
    if stems != reference:
        bad('%s does not hold the same subagents as .agents/agents' % tree,
            'missing %s, extra %s' % (sorted(reference - stems), sorted(stems - reference)))
        break
else:
    ok('the four generated subagent trees hold the same %d subagents' % len(reference))

read_only = []
broken = []
for path in sorted(AGENTS.glob('*.md')):
    front = front_matter(path)
    tools = {k for k, v in block_keys(front, 'tools').items() if v == 'true'}
    permission = block_keys(front, 'permission')
    wants = []
    if not tools & {'write', 'edit'}:
        wants.append('edit')
    if 'bash' not in tools:
        wants.append('bash')
    if wants:
        read_only.append(path.stem)
    missing = [w for w in wants if permission.get(w) != 'deny']
    if missing:
        broken.append('%s lacks %s: deny' % (path.name, ', '.join(missing)))
if broken:
    bad('a subagent that lists no write or bash tool is not denied them',
        'OpenCode and Kilo Code read the tools map as overrides on top of every tool, so these can '
        'edit and run commands (10.16): ' + '; '.join(broken))
else:
    ok('%d subagent(s) without a write or bash tool carry permission deny for edit and bash' % len(read_only))

plan_missing = []
for stem in read_only:
    front = front_matter(pathlib.Path('.claude/agents') / (stem + '.md'))
    listed = re.search(r'^tools:\s*(.*)$', front, re.M)
    names_here = {t.strip() for t in listed.group(1).split(',')} if listed else set()
    if not names_here & {'Write', 'Edit', 'Bash'} and 'permissionMode: plan' not in front:
        plan_missing.append(stem)
if plan_missing:
    bad('a read-only Claude Code subagent is not in plan mode', ', '.join(plan_missing))
else:
    ok('every read-only Claude Code subagent runs in plan mode')

print('\n'.join(OUT))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "imported agent artifacts"

# Each report line is OK <name> or FAIL <name>|<detail>, so a failure keeps its explanation.
relay_failures() {
    local line body
    while IFS= read -r line; do
        case "${line}" in
            OK*)   pass "${line#OK }" ;;
            FAIL*) body="${line#FAIL }"; fail "${body%%|*}" "${body#*|}" ;;
        esac
    done <<<"$1"
}

relay_failures "${report}"
[[ -z "${report}" ]] && fail "the imported agent artifacts check printed nothing" "expected OK or FAIL lines"

# The plugin itself, through the entry point OpenCode 1.x and Kilo Code call. A session the plugin
# reads as a root session is the main thread, and the main thread writing a file inside the repository
# must be refused. This is the property that was lost, and the static half above cannot see it.
if command -v node >/dev/null 2>&1; then
    probe_status=0
    probe="$(node --input-type=module - "${REPO_ROOT}" <<'JSEOF' 2>&1
import { pathToFileURL } from "node:url"
import { join } from "node:path"

const root = process.argv[2]
const mod = await import(pathToFileURL(join(root, ".agents", "plugin", "hooks.js")).href)
const entry = mod.default
const server = typeof entry === "function" ? entry : entry?.server
if (typeof server !== "function") {
  console.log("FAIL the plugin has no server entry|default export is " + typeof entry)
  process.exit(0)
}
const client = {
  session: {
    get: async ({ path }) => ({ data: { id: path.id } }),
    messages: async () => ({ data: [] }),
  },
}
const hooks = await server({ worktree: root, directory: root, client })
try {
  await hooks["tool.execute.before"](
    { tool: "write", sessionID: "ses_probe_main" },
    { args: { filePath: join(root, ".agents", "never-written-by-the-probe.txt"), content: "x" } },
  )
  console.log("FAIL a main-thread write inside the repository was allowed through the plugin|" +
    "the gate did not refuse a root session, which is what an is_subagent of Boolean(sessionID) does (10.15)")
} catch (error) {
  console.log("OK a main-thread write inside the repository is refused through the plugin: " +
    String(error.message).split("\n")[0].slice(0, 80))
}

// OpenCode 2.x: the reply rules reach the main thread and never a subagent's session.
const registered = {}
const sessions = { ses_main: { id: "ses_main" }, ses_child: { id: "ses_child", parentID: "ses_main" } }
await entry.setup?.({
  location: { project: { directory: root }, directory: root },
  session: {
    get: async ({ sessionID }) => sessions[sessionID],
    context: async () => [],
    hook: async (name, callback) => { registered[name] = callback },
  },
  tool: { hook: async () => {} },
})
const rulesFor = async (sessionID) => {
  const event = { sessionID, system: [] }
  await registered.context?.(event)
  return event.system.length
}
const [main, child] = [await rulesFor("ses_main"), await rulesFor("ses_child")]
if (main > 0 && child === 0) {
  console.log("OK OpenCode 2.x adds the reply rules to the main thread only")
} else {
  console.log("FAIL OpenCode 2.x reply rules are not main-thread only|" +
    "system parts added: main " + main + ", subagent " + child + ", expected at least 1 and 0 (10.19)")
}
JSEOF
)" || probe_status=$?
    if [[ ${probe_status} -ne 0 ]]; then
        fail "the plugin probe did not run to completion" "${probe}"
    else
        relay_failures "${probe}"
    fi
else
    skip "a main-thread write is refused through the plugin" "no node on PATH, so the plugin could not be run"
fi

finish "imported agent artifacts"
