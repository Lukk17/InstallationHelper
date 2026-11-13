#!/usr/bin/env bash
#
# Tier 1: no comment block in a script, workflow or Dockerfile repeats the block right before it.
#
# The linux-e2e job of .github/workflows/e2e-manual.yaml carried its 22-line comment about the
# unix_chkpwd AppArmor profile twice in a row, docs/regression_ledger.md 10.284 and 10.299. A pasted
# copy reads as two notes, and the next edit changes one of them and leaves the other stale.
#
# A comment block is a run of lines whose first character after indentation is #, apart from a
# shebang. It fails when a block is followed, after nothing but blank lines, by a block with the same
# lines, and when one block is the same lines twice over. A block with fewer than two lines of text
# after the # is not read, because a lone rule or label line repeats on purpose.
#
# Every file git would ship under .github/, e2e/ and setup/, tracked or new, is read when it ends in
# .yml, .yaml, .sh, .ps1, .psm1 or .py or is a Dockerfile, apart from a file holding a null byte. This
# script is left out by name, because its planted blocks repeat on purpose.
#
# The reader is first run against a planted tree and must name exactly the planted repeats, so a
# reader that finds nothing cannot pass for a tree that holds nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: no comment block repeats the block right before it"

LEFT_OUT=(e2e/tier1/repeated_comment_blocks.sh)

if ! command -v git >/dev/null 2>&1; then
    skip "no comment block repeats the block right before it" \
         "no git here, and only git knows which files the repository ships"
    finish "repeated comment blocks"
fi

require_python "no comment block repeats the block right before it" "repeated comment blocks"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

# repeats <file>...  ->  prints "<file>:<line>: ..." for each repeated block, then
#                        "READ <files read> <blocks read>"
repeats() {
    "${PYTHON}" -I - "$@" <<'PYEOF'
import sys

MIN_TEXT_LINES = 2


def is_comment(stripped):
    return stripped.startswith('#') and not stripped.startswith('#!')


def text_lines(block):
    return sum(1 for line in block if line.lstrip('#').strip())


def blocks_of(lines):
    """Each comment block as (first line number, stripped lines, blank lines after the previous block only)."""
    found = []
    current = []
    start = 0
    gap_only_blank = False
    seen_code = True
    for number, raw in enumerate(lines, 1):
        stripped = raw.strip()
        if stripped and is_comment(stripped):
            if not current:
                start = number
                gap_only_blank = bool(found) and not seen_code
            current.append(stripped)
            continue
        if current:
            found.append((start, current, gap_only_blank))
            current = []
            seen_code = False
        if stripped:
            seen_code = True
    if current:
        found.append((start, current, gap_only_blank))
    return found


read = 0
blocks_read = 0
for path in sys.argv[1:]:
    try:
        with open(path, 'rb') as handle:
            data = handle.read()
    except OSError:
        continue
    if b'\0' in data:
        continue
    read += 1
    blocks = blocks_of(data.decode('utf-8', 'replace').split('\n'))
    previous = None
    for start, block, after_blank_only in blocks:
        if text_lines(block) >= MIN_TEXT_LINES:
            blocks_read += 1
            half = len(block) // 2
            if len(block) % 2 == 0 and block[:half] == block[half:] and text_lines(block[:half]) >= MIN_TEXT_LINES:
                print('%s:%d: the comment block of %d lines is the same %d lines twice over'
                      % (path, start, len(block), half))
            if previous is not None and after_blank_only and previous[1] == block:
                print('%s:%d: the comment block of %d lines repeats the one at line %d'
                      % (path, start, len(block), previous[0]))
        previous = (start, block)
print('READ %d %d' % (read, blocks_read))
PYEOF
}

planted="${work}/planted"
mkdir -p "${planted}"
cat >"${planted}/pasted.yaml" <<'EOF'
steps:
  # The profile withholds a capability PAM needs.
  #
  # Only Fedora is hit.

  # The profile withholds a capability PAM needs.
  #
  # Only Fedora is hit.
  - name: Relax the profile
    run: |
      # Load the image first.
      # Then start the harness.
      # Load the image first.
      # Then start the harness.
      true
EOF
cat >"${planted}/clean.sh" <<'EOF'
#!/usr/bin/env bash
# ------------------------------------------------------------

# ------------------------------------------------------------

# Stage 1 runs first.
# It installs nothing.
echo one
# Stage 1 runs first.
# It installs nothing.
echo two
# Stage 2 waits for stage 1.
# It installs everything.

# Stage 3 waits for stage 2.
# It installs everything.
EOF
printf '# a\n# b\n\n# a\n# b\n\0' >"${planted}/binary.bin"

expected_planted="pasted.yaml:6: the comment block of 3 lines repeats the one at line 2
pasted.yaml:11: the comment block of 4 lines is the same 2 lines twice over
READ 2 7"

status=0
planted_output="$(cd "${planted}" && repeats pasted.yaml clean.sh binary.bin 2>&1)" || status=$?
if [[ ${status} -eq 0 && "${planted_output}" == "${expected_planted}" ]]; then
    pass "the reader names exactly the two planted repeats and none of the rule lines, the repeats with code between them, the different blocks or the binary file"
else
    fail "the reader names exactly the two planted repeats and none of the rule lines, the repeats with code between them, the different blocks or the binary file" \
         "exit ${status}. Output: ${planted_output//$'\n'/ | }"
fi

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "repeated comment blocks"; }

status=0
listing="$(git -c core.quotePath=false ls-files --cached --others --exclude-standard -- .github e2e setup 2>&1)" || status=$?
if [[ ${status} -ne 0 ]]; then
    fail "git lists the files under .github/, e2e/ and setup/" "git ls-files exited ${status}: ${listing}"
    finish "repeated comment blocks"
fi

files=()
while IFS= read -r path; do
    [[ -z "${path}" ]] && continue
    [[ " ${LEFT_OUT[*]} " == *" ${path} "* ]] && continue
    case "${path##*/}" in
        *.yml|*.yaml|*.sh|*.ps1|*.psm1|*.py|Dockerfile|*.Dockerfile) files+=("${path}") ;;
    esac
done <<<"${listing}"

if [[ ${#files[@]} -eq 0 ]]; then
    fail "no comment block repeats the block right before it" \
         "git listed no script, workflow or Dockerfile under .github/, e2e/ and setup/, so this proves nothing"
    finish "repeated comment blocks"
fi

status=0
repo_output="$(repeats "${files[@]}" 2>&1)" || status=$?
read_count=""
blocks_count=""
findings=()
while IFS= read -r line; do
    case "${line}" in
        READ\ *) read -r _ read_count blocks_count <<<"${line}" ;;
        "")      ;;
        *)       findings+=("${line}") ;;
    esac
done <<<"${repo_output}"

if [[ ${status} -ne 0 || -z "${read_count}" ]]; then
    fail "the reader could read the files under .github/, e2e/ and setup/" "exit ${status}: ${repo_output}"
elif [[ "${read_count}" -eq 0 || "${blocks_count}" -eq 0 ]]; then
    fail "no comment block repeats the block right before it" \
         "the reader read ${read_count} of the ${#files[@]} listed files and ${blocks_count} comment blocks, so this proves nothing"
elif [[ ${#findings[@]} -eq 0 ]]; then
    pass "none of the ${blocks_count} comment blocks in ${read_count} scripts, workflows and Dockerfiles under .github/, e2e/ and setup/ repeats the block right before it"
else
    for finding in "${findings[@]}"; do
        fail "a comment block repeats the block right before it, so one copy goes stale at the next edit" \
             "${finding}"
    done
fi

finish "repeated comment blocks"
