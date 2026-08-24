#!/usr/bin/env bash
#
# Tier 1: every Windows phase function returns the summary object its caller reads.
#
# setup.ps1 runs the Windows wizard as a sequence of phases, and every phase function hands back one
# summary object: Results, Installed, Present, Failed, and whatever else that phase has to say. The
# caller reads those properties straight away, and PowerShell runs the whole wizard under
# Set-StrictMode -Version Latest, where reading a property an object does not carry is a terminating
# error rather than an empty value.
#
# So a phase function that returns nothing does not degrade, it kills the run, and it kills it in
# the reporting code rather than in the install, which makes the message point away from the cause.
#
# This is not hypothetical. Commit fef5e56 removed the Razer Cortex block from the end of
# Invoke-WindowsCustomInstall and took the function's own summary return with it, because the two
# were adjacent. Nothing complained: the file still parsed, the Pester suite never calls that
# function, and the tier 1 gate passed 146 assertions. Two Windows cells of sweep 32703419920 then
# died with "The property 'Results' cannot be found on this object", after the software phase and
# before the settings phase, so a wizard that had done its work correctly reported none of it.
#
# Three assertions per phase function:
#
#   1. it returns a [PSCustomObject] somewhere, which is what the deletion removed
#   2. that object declares every property setup.ps1 reads off the variable it is assigned to
#   3. nothing but blanks and comments follow the last summary return, which is what a function that
#      has lost its return to a neighbouring deletion looks like from the outside
#
# The second is what stops this check from rotting: the required list is read out of the caller
# rather than written down here, so adding a `$r.Skipped` to setup.ps1 without adding Skipped to the
# callee fails the gate rather than the next Windows run.
#
# Property names are taken as a union across return paths, because a function may hand back a
# different shape when it gives up early. Invoke-WindowsNpmToolInstall does exactly that: `Wanted`
# exists only on the path where npm is missing, and the caller reads it only inside the
# `if ($r.NpmMissing)` that path exists to trigger.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: Windows phase functions return what their caller reads"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "Windows phase contract"; }

report="$("${PYTHON:-python}" - <<'PYEOF'
import pathlib
import re

SETUP = pathlib.Path('setup/setup.ps1')
SOURCES = [SETUP] + sorted(pathlib.Path('setup/windows').glob('*.ps1'))

lines = []


def function_body(text, name):
    """The lines of `function <name> {` up to the closing brace in column one.

    Every function in these files closes that way, and one that does not is reported rather than
    skipped, because a skipped function is a check that proves nothing.
    """
    all_lines = text.splitlines()
    start = None
    for i, line in enumerate(all_lines):
        if re.match(r'^function\s+%s\s*\{' % re.escape(name), line):
            start = i
            break
    if start is None:
        return None
    body = all_lines[start:]
    for j, line in enumerate(body[1:], start=1):
        if line == '}':
            return body[:j + 1]
    return None


def summary_returns(body):
    """Every `return [PSCustomObject]@{ ... }` in a body, as (first line, last line, property set).

    Braces are counted from the opening one, so a nested hashtable inside the summary does not end
    it early and a one-line return reads the same as a block.
    """
    found = []
    for i, line in enumerate(body):
        if not re.search(r'return\s+\[PSCustomObject\]@\{', line):
            continue
        depth, props, last = 0, set(), i
        for offset, current in enumerate(body[i:]):
            fragment = current[current.index('@{'):] if offset == 0 else current
            for name in re.findall(r'(?:^|\{|;)\s*([A-Za-z_]\w*)\s*=', fragment):
                props.add(name)
            depth += fragment.count('{') - fragment.count('}')
            last = i + offset
            if depth <= 0:
                break
        found.append((i, last, props))
    return found


setup_text = SETUP.read_text(encoding='utf-8')
setup_lines = setup_text.splitlines()

# Where each caller function starts, so a property read is attributed to the call above it rather
# than to a variable of the same name three functions away.
starts = [i for i, line in enumerate(setup_lines) if line.startswith('function ')]

calls = []
for i, line in enumerate(setup_lines):
    m = re.match(r'^\s*\$(\w+)\s*=\s*(Invoke-Windows\w+)\b', line)
    if m:
        calls.append((i, m.group(1), m.group(2)))

if not calls:
    print('FAIL setup.ps1 calls no Invoke-Windows phase function, so this check proves nothing')
    raise SystemExit(0)

texts = {path: path.read_text(encoding='utf-8') for path in SOURCES}

for index, var, callee in calls:
    lower = max([s for s in starts if s <= index], default=0)
    upper = min([s for s in starts if s > index], default=len(setup_lines))
    read = set()
    for line in setup_lines[lower:upper]:
        for name in re.findall(r'\$%s\.(\w+)' % re.escape(var), line):
            if name != 'PSObject':
                read.add(name)

    body, source = None, None
    for path, text in texts.items():
        body = function_body(text, callee)
        if body:
            source = path
            break
    if not body:
        lines.append('FAIL %s is called by setup.ps1 and is either not defined under setup/, or does not close with a brace in column one' % callee)
        continue

    returns = summary_returns(body)

    # The tail rule applies whatever the return hands back, because not every phase returns a
    # [PSCustomObject]: Invoke-WindowsRun collects the other phases into an ordered hashtable. What
    # they all share is ending on an explicit return, which is the statement a neighbouring deletion
    # takes with it.
    last_return = None
    for i, line in enumerate(body):
        if re.match(r'^\s*return\b', line):
            last_return = i
    if last_return is None:
        lines.append('FAIL %s (%s) has no return statement at all, so it hands its caller nothing and every property read off it is a terminating error under strict mode' % (callee, source))
        continue

    end = last_return
    for first, final, _ in returns:
        if first == last_return:
            end = final
    # Closing braces are not statements. A function whose last return sits inside an `if` closes
    # one or more blocks after it, and counting those as code would report a false tail on a shape
    # that is perfectly ordinary. The deletion this check exists for leaves real statements behind,
    # seventeen of them in the case it was written against, so nothing is lost by ignoring closers.
    tail = [line.strip() for line in body[end + 1:-1]]
    trailing = [line for line in tail
                if line and not line.startswith('#') and line.strip('}) 	') != '']
    if trailing:
        lines.append('FAIL %s (%s) does not end on a return, and %d statement(s) run after the last one'
                     % (callee, source, len(trailing)))
        continue

    props = set()
    for _, _, names in returns:
        props |= names

    missing = read - props
    if missing:
        lines.append('FAIL %s (%s) returns no %s on any path, and setup.ps1 reads %s off it'
                     % (callee, source, ', '.join(sorted(missing)), ', '.join(sorted(read))))
        continue

    lines.append('OK %s ends on a return of %s, and setup.ps1 reads %s'
                 % (callee, ', '.join(sorted(props)) or 'a value with no declared properties',
                    ', '.join(sorted(read)) or 'nothing off it directly'))

print('\n'.join(lines))
PYEOF
)"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a Windows phase function does not return the summary its caller reads" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the phase contract check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "Windows phase contract"
