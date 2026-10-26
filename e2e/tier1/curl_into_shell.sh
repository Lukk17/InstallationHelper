#!/usr/bin/env bash
#
# Tier 1: an install script that curl fetches for a shell is fetched with -f and -L, and a failed fetch
# fails the command that runs it.
#
# Until 2026-10-26 the k3d task in setup/ansible/roles/software_installer/tasks/custom_installs.yaml ran
# `bash -c 'curl -s --max-time 120 <install.sh> | bash'`, while uv in the same file and LM Studio in
# roles/ai_tools/tasks/local_llm.yaml used `curl -fsSL`. Without -f, curl writes an error page to the
# pipe and exits 0, so bash runs the page as a script. Without -L, a moved script arrives as an empty
# redirect body, bash runs nothing and exits 0. And the task's own `set -o pipefail` does not reach a
# pipe inside `bash -c '...'`: measured in the gate image, a refused fetch there ended with status 0,
# and with `set -o pipefail;` inside the quotes with curl's 7. docs/regression_ledger.md 10.207.
#
# The Oh My Zsh and Homebrew tasks ran `sh -c "$(curl -fsSL <install.sh>)"`. There -f does not help: a
# failed fetch leaves the substitution empty and `sh -c ""` exits 0. The script goes into a variable
# first, with `|| exit 1`, and the shell runs the variable. docs/regression_ledger.md 10.208.
#
# Read: every file under setup/ and docs/manual/. A YAML file is read one string at a time, so a task's
# body is one script, and a shell script is read whole. Comment lines are left out. In markdown the
# escaped table pipe `\|` counts as a pipe and only the flags are checked, because a reader types the
# vendor's command and sees curl's error on the screen. A curl with no URL and no Jinja expression,
# such as the words "curl | bash" in prose, is not a fetch.
#
# Asserted:
#   1. a curl piped into sh, bash, zsh or dash, with sudo or variable assignments between, carries -f
#      (or --fail, --fail-with-body) and -L (or --location);
#   2. outside markdown, that pipe runs under pipefail: set inside the quotes when the pipe sits in a
#      `bash -c` or `sh -c` string, otherwise set earlier in the same script;
#   3. outside markdown, no sh -c or bash -c is given "$(curl ...)" directly;
#   4. outside markdown, a variable captured from curl that a shell then runs with -c carries -f and -L;
#   5. at least one fetch was read, because a check over nothing proves nothing.
# The reader runs first against a planted tree and must name exactly the nine planted defects.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: install scripts curl fetches for a shell use -f and -L and fail when the fetch fails"

require_python "install scripts curl fetches for a shell use -f and -L and fail when the fetch fails" "curl into shell"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

# scan <root>  ->  prints "FIND<tab><file>:<line><tab><why><tab><command>" per defect, then "SEEN<tab><fetches>"
scan() {
    "${PYTHON}" -I - "$1" <<'PYEOF'
import pathlib
import re
import sys

import yaml

ROOT = pathlib.Path(sys.argv[1])
SCOPES = ('setup', 'docs/manual')

JINJA = re.compile(r'\{\{.*?\}\}')
SHELL = r'(?:/usr/bin/|/bin/)?(?:ba|z|da)?sh\b'
PIPE = re.compile(r'\bcurl\b(?P<args>[^|\n;&()`]*)\|(?!\|)[ \t]*'
                  r'(?:sudo(?:[ \t]+-\S+)*[ \t]+)?(?:\w+=\S*[ \t]+)*' + SHELL)
SUBST = re.compile(SHELL + r'[ \t]+-c[ \t]+["\']?\$\([ \t]*curl\b(?P<args>[^)\n]*)\)')
CAPTURE = re.compile(r'\b(?P<var>\w+)=["\']?\$\([ \t]*curl\b(?P<args>[^)\n]*)\)')
NESTED = re.compile(SHELL + r'[ \t]+-c[ \t]+(?P<quote>[\'"])')
PIPEFAIL = re.compile(r'\bpipefail\b')
FETCHES = re.compile(r'https?://|\{\{JINJA\}\}')
SHORT_WITH_VALUE = set('AbcCdDEeFHKmoPQrTtuUwxXYyz')


def fail_and_follow(args):
    """Which of -f and -L the curl arguments carry, short clusters such as -fsSLo included."""
    has_fail = has_location = False
    for token in args.split():
        if token.startswith('--'):
            name = token.split('=')[0]
            has_fail |= name in ('--fail', '--fail-with-body')
            has_location |= name in ('--location', '--location-trusted')
        elif token.startswith('-') and len(token) > 1:
            for letter in token[1:]:
                has_fail |= letter == 'f'
                has_location |= letter == 'L'
                if letter in SHORT_WITH_VALUE:
                    break
    return has_fail, has_location


def missing_flags(args):
    has_fail, has_location = fail_and_follow(args)
    return [flag for flag, present in (('-f', has_fail), ('-L', has_location)) if not present]


def runs_under_pipefail(body, start):
    """True when the pipe at `start` runs under pipefail in the shell that runs it."""
    line_start = body.rfind('\n', 0, start) + 1
    before_on_line = body[line_start:start]
    nested = None
    for found in NESTED.finditer(before_on_line):
        if found.group('quote') not in before_on_line[found.end():]:
            nested = found
    if nested is not None:
        return PIPEFAIL.search(before_on_line[nested.end():]) is not None
    return PIPEFAIL.search(body[:start]) is not None


def prepared(text, markdown):
    lines = []
    for line in text.splitlines():
        if not markdown and line.lstrip().startswith('#'):
            lines.append('')
            continue
        if markdown:
            line = line.replace('\\|', '|')
        lines.append(JINJA.sub('{{JINJA}}', line))
    return '\n'.join(lines)


def yaml_strings(node):
    """(first file line, text) of every string scalar in a composed YAML node, at any depth."""
    if isinstance(node, yaml.ScalarNode):
        if isinstance(node.value, str) and node.tag.endswith(':str'):
            first = node.start_mark.line + (2 if node.style in ('|', '>') else 1)
            yield first, node.value
    elif isinstance(node, yaml.SequenceNode):
        for item in node.value:
            yield from yaml_strings(item)
    elif isinstance(node, yaml.MappingNode):
        for key, value in node.value:
            yield from yaml_strings(value)


def units(path, text):
    """(first file line, script) pairs: each YAML string on its own, any other file whole."""
    if path.suffix in ('.yaml', '.yml'):
        try:
            nodes = list(yaml.compose_all(text))
        except yaml.YAMLError:
            return [(1, text)]
        return [pair for node in nodes if node is not None for pair in yaml_strings(node)]
    return [(1, text)]


seen = 0
for scope in SCOPES:
    base = ROOT / scope
    if not base.is_dir():
        continue
    for path in sorted(p for p in base.rglob('*') if p.is_file()):
        try:
            text = path.read_text(encoding='utf-8')
        except (UnicodeDecodeError, OSError):
            continue
        rel = path.relative_to(ROOT).as_posix()
        markdown = path.suffix == '.md'
        for first_line, raw in units(path, text):
            body = prepared(raw, markdown)

            def report(match, reasons):
                line = first_line + body.count('\n', 0, match.start())
                print('FIND\t%s:%d\t%s\t%s' % (rel, line, ', and '.join(reasons), ' '.join(match.group(0).split())))

            for match in PIPE.finditer(body):
                if not FETCHES.search(match.group('args')):
                    continue
                seen += 1
                reasons = []
                lacking = missing_flags(match.group('args'))
                if lacking:
                    reasons.append('pipes curl into a shell without %s' % ' and '.join(lacking))
                if not markdown and not runs_under_pipefail(body, match.start()):
                    reasons.append('runs that pipe without pipefail in its own shell, so a failed fetch ends with status 0')
                if reasons:
                    report(match, reasons)
            if markdown:
                continue
            for match in SUBST.finditer(body):
                if not FETCHES.search(match.group('args')):
                    continue
                seen += 1
                report(match, ['hands a shell "$(curl ...)", which runs an empty script and exits 0 when the fetch fails'])
            for match in CAPTURE.finditer(body):
                if not FETCHES.search(match.group('args')):
                    continue
                if not re.search(SHELL + r'[ \t]+-c[ \t]+["\']?\$\{?' + match.group('var') + r'\b', body):
                    continue
                seen += 1
                lacking = missing_flags(match.group('args'))
                if lacking:
                    report(match, ['captures a script a shell then runs, without %s' % ' and '.join(lacking)])

print('SEEN\t%d' % seen)
PYEOF
}

plant() {
    local root="$1"
    mkdir -p "${root}/setup/ansible/roles/demo/tasks" "${root}/docs/manual/demo"
    cat >"${root}/setup/ansible/roles/demo/tasks/main.yaml" <<'EOF'
- name: a, the k3d line before 2026-10-26
  ansible.builtin.shell: |
    set -o pipefail
    timeout 300 bash -c 'curl -s --max-time 120 https://example.invalid/a.sh | bash'
- name: b, no -L
  ansible.builtin.shell: |
    set -o pipefail
    curl -fsS https://example.invalid/b.sh | sudo bash
- name: c, no -f, through sudo and a variable
  ansible.builtin.shell: |
    set -o pipefail
    curl -sL https://example.invalid/c.sh | sudo UV_DIR=/usr/local/bin sh
- name: g, a Jinja URL without -f or -L
  ansible.builtin.shell: |
    set -o pipefail
    curl -s {{ demo_installer_url | quote }} | bash
- name: r, pipefail only outside the quotes
  ansible.builtin.shell: |
    set -o pipefail
    timeout 300 bash -c 'curl -fsSL --max-time 120 https://example.invalid/r.sh | bash'
- name: s, no pipefail at all, the pipefail of the task above does not count
  ansible.builtin.shell: curl -fsSL https://example.invalid/s.sh | bash
- name: h, as it should be
  ansible.builtin.shell: |
    set -o pipefail
    curl -fsSL --max-time 120 https://example.invalid/h.sh | bash
- name: i, long options
  ansible.builtin.shell: |
    set -euo pipefail
    curl --fail --location https://example.invalid/i.sh | sh
- name: p, -o- and a variable before bash
  ansible.builtin.shell: |
    set -o pipefail
    curl -fsSL --max-time 120 -o- https://example.invalid/p.sh | PROFILE=/dev/null bash || exit 1
- name: t, pipefail inside the quotes
  ansible.builtin.shell: |
    timeout 300 bash -c 'set -o pipefail; curl -fsSL --max-time 120 https://example.invalid/t.sh | bash'
- name: q, a key into gpg is not a shell
  ansible.builtin.shell: curl -fsSL https://example.invalid/q.key | sudo gpg --dearmor -o /tmp/q.gpg
EOF
    cat >"${root}/setup/demo.sh" <<'EOF'
#!/usr/bin/env bash
# curl -s https://example.invalid/m.sh | bash is only a comment
sh -c "$(curl -fsSL https://example.invalid/d.sh)" "" --unattended
script="$(curl -sL https://example.invalid/f.sh)"
bash -c "$script"
installer="$(curl -fsSL https://example.invalid/o.sh)" || exit 1
sh -c "$installer"
curl -fsSLo /tmp/k https://example.invalid/k.bin
EOF
    cat >"${root}/docs/manual/demo/guide.md" <<'EOF'
| k3d | `curl -s https://example.invalid/e.sh \| bash` |
| uv | `curl -LsSf https://example.invalid/j.sh \| sh` |

These install via `curl | bash` into your shell rc.

```bash
sh -c "$(curl -fsSL https://example.invalid/n.sh)"
```
EOF
}

plant "${work}/planted"
planted_status=0
planted="$(scan "${work}/planted")" || planted_status=$?
assert_python_ran "${planted_status}" "curl into shell"
named="$(sed -n 's#^FIND\t.*example\.invalid/\([a-z]\)\.sh.*#\1#p; s#^FIND\t.*{{JINJA}}.*#g#p' <<<"${planted}" | sort | tr -d '\n')"
planted_seen="$(sed -n 's#^SEEN\t##p' <<<"${planted}")"
if [[ "${named}" == "abcdefgrs" && "${planted_seen}" == 15 ]]; then
    pass "the reader names exactly the nine planted defects, a to g, r and s, among the fifteen planted fetches"
else
    fail "the reader does not name exactly the nine planted defects among fifteen fetches" "expected abcdefgrs and 15, got [${named}] and [${planted_seen}]: ${planted}"
fi

report_status=0
report="$(scan "${REPO_ROOT}")" || report_status=$?
assert_python_ran "${report_status}" "curl into shell"

found=0
while IFS=$'\t' read -r kind where why command; do
    case "${kind}" in
        FIND)
            found=$((found + 1))
            fail "${where} ${why}" "${command}. Fetch with curl -fsSL --max-time 120 under pipefail, set inside the quotes of a bash -c, and for sh -c put the script into a variable with || exit 1 first"
            ;;
        SEEN)
            if [[ "${where}" -gt 0 ]]; then
                [[ ${found} -eq 0 ]] && pass "${where} install scripts fetched for a shell under setup/ and docs/manual/, every one with -f and -L, and every one in code failing when its fetch fails"
            else
                fail "no install script fetched for a shell was found under setup/ or docs/manual/" "a check over nothing proves nothing, so either the reader broke or the fetches are gone and this check should go too"
            fi
            ;;
        *) [[ -n "${kind}" ]] && fail "the curl into shell reader printed something unexpected" "${kind} ${where} ${why} ${command}" ;;
    esac
done <<<"${report}"

finish "curl into shell"
