#!/usr/bin/env bash
#
# Tier 1: no tracked text file carries a carriage return.
#
# .gitattributes has said `* text=auto eol=lf` for a while, and explains why: a carriage return has
# no width, so it is invisible in every diff and in every review, Git Bash hides it in some tools
# and not others, and a real Linux shell hides it nowhere. What .gitattributes cannot do is stop a
# file in the working tree from acquiring one after checkout. Nothing checked that until now.
#
# It happened on 2026-08-22, and how it happened is worth writing down. A series of edits were
# applied with a Python script that opened files for writing without specifying a newline, which on
# Windows silently rewrites every line ending as CRLF. Nineteen files were converted whole. git
# showed nothing, because core.autocrlf=input normalises on the way in. The gate went from 142
# passing assertions to three failures whose messages pointed nowhere near the cause: an awk that
# reads `register: <name>` handed grep a name with a trailing carriage return, so eight results that
# are read all over the playbook were reported as read by nothing.
#
# Worse than the false failures is the true one they hide. The container tiers copy the working tree
# into Linux, where a shebang ending in a carriage return means "no such file or directory" and a
# value read out of a file quietly carries an invisible byte.
#
# The detection is Python and not grep, and that is not a preference either. Measured here on
# 2026-08-22: `printf 'a\r\nb\n' > f; grep -c $'\r' f` prints 0 in Git Bash, because its grep strips
# the carriage return before matching. A check written with grep would pass on precisely the machine
# that creates the problem. awk keeps it, grep does not, and that inconsistency is the trap.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: line endings"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "line endings"; }

if ! command -v git >/dev/null 2>&1; then
    skip "no tracked text file carries a carriage return" "no git here, and only git knows what is tracked"
    finish "line endings"
    return 0 2>/dev/null || exit 0
fi

# Python asks git itself rather than reading a pipe, because a heredoc already owns this stdin:
# `git ls-files | python - <<EOF` hands the script to python and throws the file list away, which
# this check did on its first run and reported "git listed no tracked files" against a clean tree.
require_python "no tracked text file carries a carriage return" "line endings"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import subprocess

raw = subprocess.run(['git', 'ls-files', '-z'], capture_output=True).stdout
paths = [p for p in raw.decode('utf-8', 'surrogateescape').split('\0') if p]

offenders, checked = [], 0
for path in paths:
    try:
        with open(path, 'rb') as handle:
            data = handle.read()
    except OSError:
        continue
    if b'\0' in data:          # git's own definition of binary, so no suffix list to maintain
        continue
    checked += 1
    if b'\r' in data:
        offenders.append(path)

if not paths:
    print('FAIL git listed no tracked files, so this check proves nothing')
elif offenders:
    print('FAIL {} of {} tracked text files carry a carriage return: {}'.format(
        len(offenders), checked, ' '.join(offenders[:12]) + (' ...' if len(offenders) > 12 else '')))
else:
    print('OK {}'.format(checked))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "line endings"

case "${report}" in
    OK*) pass "none of the ${report#OK } tracked text files carries a carriage return" ;;
    *)   fail "a tracked text file carries Windows line endings, which .gitattributes forbids and which no diff will show you" \
              "${report#FAIL }" ;;
esac

# The policy itself has to still be there, or the check above guards a rule nobody declared.
if [[ -f .gitattributes ]] && grep -qE '^\*[[:space:]]+text=auto[[:space:]]+eol=lf' .gitattributes; then
    pass ".gitattributes still declares eol=lf for every text file"
else
    fail ".gitattributes no longer declares eol=lf, so a fresh clone decides line endings by local preference" \
         "expected a line reading '* text=auto eol=lf'"
fi

finish "line endings"
