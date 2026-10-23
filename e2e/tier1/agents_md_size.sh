#!/usr/bin/env bash
#
# Tier 1: the agent instruction files stay small enough to be read whole.
#
# The root AGENTS.md had grown to twice what Codex reads before it stops adding files, and every
# agent loaded all of it at the start of every session. It is now split into nested AGENTS.md files
# that load only for work in their folder, recorded with the measured sizes in
# docs/decisions/0001_split_agents_md.md. This holds the split: no CLAUDE.md or CLAUDE.local.md
# anywhere, the root AGENTS.md under 200 lines and under 32 KiB, and every nested AGENTS.md under 60
# lines. The rules live in e2e/lib/check_agents_md.py.
#
# The scanner is first run against planted trees and must name exactly what was planted, so a
# scanner that finds nothing cannot pass for a repository that holds nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

SCANNER="${E2E_ROOT}/lib/check_agents_md.py"

info "Tier 1: the agent instruction files stay small enough to be read whole"

require_python "the agent instruction files stay within their size limits" "agents md size"

if ! command -v git >/dev/null 2>&1; then
    fail "git answers" "no git here, and only git knows which files the repository would commit"
    finish "agents md size"
fi

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

# write_lines <file> <count> <width>  ->  <count> lines of <width> characters each
write_lines() {
    mkdir -p "$(dirname "$1")"
    "${PYTHON}" -I -c 'import sys; open(sys.argv[1], "w", encoding="utf-8").write(("x" * int(sys.argv[3]) + "\n") * int(sys.argv[2]))' "$1" "$2" "$3"
}

# scan <root>  ->  sets scan_output and scan_status
scan() {
    scan_status=0
    scan_output="$("${PYTHON}" -I "${SCANNER}" "$1" 2>&1)" || scan_status=$?
}

# A tree where every rule is broken once, and one near miss beside each that must not be named.
broken="${work}/broken"
mkdir -p "${broken}"
git -C "${broken}" init -q
write_lines "${broken}/AGENTS.md" 199 200
write_lines "${broken}/module/AGENTS.md" 60 10
write_lines "${broken}/other/AGENTS.md" 59 10
write_lines "${broken}/.claude/CLAUDE.md" 1 10
write_lines "${broken}/CLAUDE.local.md" 1 10
write_lines "${broken}/scratch/CLAUDE.md" 1 10
printf 'scratch/\n' >"${broken}/.gitignore"

scan "${broken}"
expected=(
    ".claude/CLAUDE.md exists."
    "CLAUDE.local.md exists."
    "AGENTS.md is 39999 bytes, the limit is under 32768 bytes"
    "module/AGENTS.md has 60 lines, the limit is fewer than 60."
)
missing=()
for want in "${expected[@]}"; do
    grep -qF -- "${want}" <<<"${scan_output}" || missing+=("${want}")
done
named="$(grep -cE 'exists\.|limit is' <<<"${scan_output}" || true)"
if [[ ${scan_status} -eq 1 && ${#missing[@]} -eq 0 && "${named}" -eq ${#expected[@]} ]]; then
    pass "the scanner names exactly the ${#expected[@]} planted breaches and none of the near misses"
else
    fail "the scanner names exactly the ${#expected[@]} planted breaches and none of the near misses" \
         "exit ${scan_status}, ${named} named, missing: ${missing[*]:-none}. Output: ${scan_output}"
fi

# The line limit on the root, which the tree above stays one line under.
long="${work}/long"
mkdir -p "${long}"
git -C "${long}" init -q
write_lines "${long}/AGENTS.md" 200 10
scan "${long}"
if [[ ${scan_status} -eq 1 ]] && grep -qF "AGENTS.md has 200 lines, the limit is fewer than 200." <<<"${scan_output}"; then
    pass "the scanner names a root AGENTS.md of 200 lines"
else
    fail "the scanner names a root AGENTS.md of 200 lines" "exit ${scan_status}. Output: ${scan_output}"
fi

# A tree inside every limit passes.
clean="${work}/clean"
mkdir -p "${clean}"
git -C "${clean}" init -q
write_lines "${clean}/AGENTS.md" 199 100
write_lines "${clean}/module/AGENTS.md" 59 10
scan "${clean}"
if [[ ${scan_status} -eq 0 ]]; then
    pass "the scanner passes a tree inside every limit"
else
    fail "the scanner passes a tree inside every limit" "exit ${scan_status}. Output: ${scan_output}"
fi

scan "${REPO_ROOT}"
case "${scan_status}" in
    0) pass "${scan_output}" ;;
    1) while IFS= read -r finding; do
           [[ -n "${finding}" ]] && fail "an agent instruction file breaks a size rule" "${finding}"
       done <<<"${scan_output}" ;;
    *) fail "the scanner could read the repository" "exit ${scan_status}: ${scan_output}" ;;
esac

finish "agents md size"
