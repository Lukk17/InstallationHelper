#!/usr/bin/env bash
#
# Tier 1: no tracked text file carries a control character.
#
# The characters meant here are the code points below 32 other than the tab and the newline. None of
# them has a shape. A file carrying one looks correct in the editor, in `git diff`, in a pull request
# and on the rendered markdown page, and the only thing that finds one is a scan of the raw bytes.
#
# This class has shipped here twice, both times the same way. Text was written into a tracked file
# through a layer that interpreted a backslash escape, and the single byte that escape stands for
# landed in the file instead of the two literal characters:
#
#   docs/regression_ledger.md line 1124     a quoted Windows path where 0x07, 0x02 and 0x08 had
#                                           replaced a backslash a, a backslash two and a backslash
#                                           b, so the line read `C:` followed straight by
#                                           `ctions-runner`. Repaired in 822887a.
#   local-dev/auth/Keycloak/README.md       a PowerShell example written through a Python heredoc,
#                                           where `.\\local-dev\\auth\\...` arrived as a single
#                                           backslash, `\a` became 0x07, and the line rendered as
#                                           `.\local-devuth\certificates\...` with the directory
#                                           name swallowed.
#
# The second one was caught only because the interpreter happened to warn on the way past. Nothing
# would have caught the first, and it sat in the tree through every read of that page until a byte
# scan was pointed at it. That is the whole argument for a mechanical check: a reviewer cannot see
# this, and neither can any tool that renders the file rather than reading it.
#
# The carriage return is deliberately not in the set. .gitattributes forces Unix line endings and
# line_endings.sh enforces them in the working tree, with the whole story in its own header. One rule
# in one place.
#
# Text and binary are decided by asking git rather than by listing extensions, through
# `git ls-files --eol`, which prints git's own verdict for every tracked blob: `i/-text` for one it
# treats as binary and `i/lf` for one it treats as text. That verdict already combines both of git's
# rules, the `binary` attribute this repository sets in .gitattributes for images and the `.knsv`
# archive, and git's own content sniff for anything not named there. An extension list would have to
# be extended by hand for the next binary file somebody adds, and the one that gets forgotten is the
# one that turns this check into noise until somebody deletes it. Nine tracked files are binary
# today, eight images and a Zip archive, and every one of them is full of bytes this check refuses.
# The count is reported rather than hardcoded, and a run where git calls nothing binary reports the
# exclusion as unproven instead of quietly passing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "${REPO_ROOT}/setup/pinned_values/pinned_values.sh"

info "Tier 1: control characters"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "control characters"; }

if ! command -v git >/dev/null 2>&1; then
    skip "no tracked text file carries a control character" "no git here, and only git knows what is tracked and which of it is binary"
    finish "control characters"
    return 0 2>/dev/null || exit 0
fi

# The interpreter is resolved through the search the pinned values adapter already owns, the way
# manifests.sh does, rather than through `${PYTHON:-python}`. Git Bash here has no python3 and its
# App Execution Alias resolves without running, while WSL has python3 and no python at all, so a
# check that names one of the two reports a failure on the other shell that is about the shell rather
# than about the tree.
if ! CONTROL_CHARACTERS_PYTHON="$(pinned_values_python)"; then
    skip "no tracked text file carries a control character" \
         "no Python 3.11 or newer on PATH, so the byte scan could not run"
    finish "control characters"
    return 0 2>/dev/null || exit 0
fi

# git is asked from inside Python rather than through a pipe, because this heredoc already owns the
# script's stdin. line_endings.sh reported "git listed no tracked files" against a clean tree on its
# first run for exactly that reason.
scan_status=0
report="$("${CONTROL_CHARACTERS_PYTHON}" - <<'PYEOF'
import subprocess
import sys

FORBIDDEN = frozenset(set(range(32)) - {9, 10, 13})
KEEP_ONLY_FORBIDDEN = bytes(b for b in range(256) if b not in FORBIDDEN)
NAMES = {
    0: 'NUL', 1: 'SOH', 2: 'STX', 3: 'ETX', 4: 'EOT', 5: 'ENQ', 6: 'ACK', 7: 'BEL',
    8: 'BS', 11: 'VT', 12: 'FF', 14: 'SO', 15: 'SI', 16: 'DLE', 17: 'DC1', 18: 'DC2',
    19: 'DC3', 20: 'DC4', 21: 'NAK', 22: 'SYN', 23: 'ETB', 24: 'CAN', 25: 'EM',
    26: 'SUB', 27: 'ESC', 28: 'FS', 29: 'GS', 30: 'RS', 31: 'US',
}


# Written as bytes rather than printed. A text-mode print on Windows turns every newline into a
# carriage return and a newline, and the caller then reads the count out of `BINARY 9` as a 9 with an
# invisible byte stuck to it, which fails as an arithmetic operand. It did, on this script's first
# run, which is the same trap shell_syntax.sh already carries a note about.
def report(*lines):
    sys.stdout.buffer.write(('\n'.join(lines) + '\n').encode('utf-8'))


listing = subprocess.run(['git', 'ls-files', '--eol', '-z'], capture_output=True)
if listing.returncode != 0:
    report('FAIL git ls-files --eol failed, so this check proves nothing: %s'
           % listing.stderr.decode('utf-8', 'replace').strip().replace('\n', ' '))
    raise SystemExit(0)

records = [r for r in listing.stdout.decode('utf-8', 'surrogateescape').split('\0') if r]

text_paths, binary_paths = [], []
for record in records:
    # "i/lf   w/lf   attr/text=auto eol=lf\t<path>". The attribute field carries spaces, so the tab
    # is the only safe separator, and the path is whatever follows the first one.
    info, _, path = record.partition('\t')
    if not path:
        continue
    fields = info.split()
    if 'i/-text' in fields or 'w/-text' in fields or 'attr/-text' in fields or 'attr/binary' in fields:
        binary_paths.append(path)
    else:
        text_paths.append(path)

offenders, unreadable, scanned = [], [], 0
for path in text_paths:
    try:
        with open(path, 'rb') as handle:
            data = handle.read()
    except OSError:
        # A tracked entry that is not a readable regular file, which here is the three directory
        # symlinks into .agents/. Named rather than dropped, because a scan that silently skips is
        # indistinguishable from a scan that found nothing.
        unreadable.append(path)
        continue
    scanned += 1
    if not data.translate(None, KEEP_ONLY_FORBIDDEN):
        continue
    for number, line in enumerate(data.split(b'\n'), 1):
        for column, byte in enumerate(line, 1):
            if byte in FORBIDDEN:
                offenders.append('%s line %d column %d carries 0x%02x %s'
                                 % (path, number, column, byte, NAMES.get(byte, '?')))

if not records:
    verdict = 'FAIL git listed no tracked files, so this check proves nothing'
elif offenders:
    shown = '; '.join(offenders[:12]) + (' ...' if len(offenders) > 12 else '')
    verdict = ('FAIL %d control character(s) in %d of %d tracked text files: %s'
               % (len(offenders), len({o.split(' line ')[0] for o in offenders}), scanned, shown))
else:
    verdict = 'OK %d' % scanned

report('BINARY %d' % len(binary_paths),
       'UNREADABLE %d %s' % (len(unreadable), ' '.join(unreadable[:6])),
       verdict)
PYEOF
)" || scan_status=$?

# An interpreter that died mid-scan must say so. Without this the assignment above ends the script
# under `set -e`, and a check that exits with no PASS, no FAIL and no tally is the shape of silence
# this harness exists to prevent.
if [[ "${scan_status}" -ne 0 ]]; then
    fail "the byte scan did not run to completion, so nothing here is proven" \
         "${CONTROL_CHARACTERS_PYTHON} exited ${scan_status}, and its own error is above"
    finish "control characters"
fi

binary=""
unreadable=""
verdict=""
while IFS= read -r line; do
    case "${line}" in
        BINARY\ *)     binary="${line#BINARY }" ;;
        UNREADABLE\ *) unreadable="${line#UNREADABLE }" ;;
        "")            ;;
        *)             verdict="${line}" ;;
    esac
done <<<"${report}"

case "${verdict}" in
    OK*)   pass "none of the ${verdict#OK } tracked text files carries a control character" ;;
    FAIL*) fail "a tracked text file carries a control character, which no diff and no rendered page will show you" \
                "${verdict#FAIL }" ;;
    *)     fail "the control character scan printed nothing this check understands" "${verdict:-<no verdict line>}" ;;
esac

# Proving the exclusion rather than assuming it. Every binary file in this repository is full of the
# bytes above, so if the classification were wrong this check would fail on nine files at once and be
# deleted within the day.
if [[ -z "${binary}" ]]; then
    fail "the scan did not report how many tracked files git treats as binary" \
         "expected a line reading 'BINARY <count>'"
elif [[ "${binary}" -gt 0 ]]; then
    pass "${binary} tracked file(s) that git treats as binary were excluded without being read"
else
    skip "files git treats as binary are excluded from the scan" \
         "git treats no tracked file as binary today, so the exclusion never ran and is unproven by this run"
fi

# Named, never silent. The count is the three directory symlinks unless something else has appeared.
if [[ -n "${unreadable}" && "${unreadable}" != "0 " && "${unreadable}" != "0" ]]; then
    dim "not read, because they are not readable regular files: ${unreadable}"
fi

finish "control characters"
