#!/usr/bin/env bash
#
# Tier 1: a failure the playbook tolerates must not become a failure nobody can see.
#
# Two defects of this exact shape shipped, both found by a log contradicting itself rather than by a
# run failing, which is the worst way to find anything.
#
# The first was a collector that selected on a result's `failed` key. The task that registered the
# result carried `failed_when: false`, and Ansible applies that by rewriting the very key the
# collector read, so three AUR builds that exited non-zero were counted as successes and the collector
# was dead code from the day it was written. e2e/tier1/failed_key_reads.sh guards that half.
#
# The second is what this script guards. A task tolerates failure, registers its result, and nothing
# downstream ever reads it. Nothing warns, because a registered variable that goes unused is
# perfectly legal, so the tolerance is real and the reporting is imaginary. Every such task is a
# silent failure waiting for a bad day.
#
# The rule: if a task tolerates failure and registers a result, something else must read that result.
# A tolerated task that registers nothing is fine and is counted separately, because the callback now
# renders those under a TOLERATED heading with their return code, so they are visible even unread.
#
# Deliberate exceptions go in tolerated_failures_allowed.txt as `<register-name> <reason>`, and a
# stale entry there fails too, because an exemption that has quietly become unnecessary is how a
# later break looks intentional.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

ALLOWED_FILE="$(dirname "${BASH_SOURCE[0]}")/tolerated_failures_allowed.txt"
SCAN_ROOT="${ANSIBLE_DIR}"

info "Tier 1: tolerated failures must be read"

# Split each task file into task blocks and print the ones that tolerate failure, as
# <file>:<line> TAB <register-or-NONE> TAB <task name>. A block starts at a list item at any indent,
# which is how a task begins in every file here, and ends at the next one.
scan_tolerated() {
    find "${SCAN_ROOT}" -name '*.yaml' -o -name '*.yml' | sort | xargs awk '
        function flush() {
            if (start && tolerated) {
                printf "%s:%d\t%s\t%s\n", FILENAME, start, (reg == "" ? "NONE" : reg), name
            }
            start = 0; tolerated = 0; reg = ""; name = ""
        }
        /^[[:space:]]*-[[:space:]]/ {
            flush()
            start = FNR
            name = $0
            sub(/^[[:space:]]*-[[:space:]]*(name:[[:space:]]*)?/, "", name)
        }
        /^[[:space:]]*failed_when:[[:space:]]*(false|no)[[:space:]]*$/ { tolerated = 1 }
        /^[[:space:]]*ignore_errors:[[:space:]]*(true|yes)[[:space:]]*$/ { tolerated = 1 }
        /^[[:space:]]*register:[[:space:]]*/ { reg = $2 }
        END { flush() }
    '
}

tolerated="$(scan_tolerated)"
n_total="$(grep -c . <<<"${tolerated}" || true)"
n_registered="$(awk -F'\t' '$2 != "NONE"' <<<"${tolerated}" | grep -c . || true)"

# A scanner that matches nothing would pass every assertion below, which is the vacuous-pass trap this
# repository has been caught by twice. Fifty-odd tolerated tasks exist today, so a count in single
# figures means the scan broke rather than that the playbook got tidy.
if [[ "${n_total}" -lt 10 ]]; then
    fail "the tolerated-task scan found only ${n_total} tasks, so it cannot mean anything" \
         "expected dozens under ${SCAN_ROOT}, the block-splitting pattern has probably stopped matching"
    finish "tolerated failures"
fi
pass "found ${n_total} tasks that tolerate failure, ${n_registered} of which register a result"

# The assertion. A registered result must appear somewhere other than its own register line.
unread=()
while IFS=$'\t' read -r loc reg _; do
    [[ -z "${reg}" || "${reg}" == "NONE" ]] && continue
    grep -qE "^${reg}([[:space:]]|$)" "${ALLOWED_FILE}" 2>/dev/null && continue
    uses="$(grep -rho "\b${reg}\b" --include='*.yaml' --include='*.yml' "${SCAN_ROOT}" | grep -c . || true)"
    [[ "${uses}" -le 1 ]] && unread+=("${reg} at ${loc}")
done <<<"${tolerated}"

if [[ ${#unread[@]} -eq 0 ]]; then
    pass "every tolerated task's registered result is read somewhere"
else
    fail "${#unread[@]} tolerated task(s) register a result nothing reads, so their failure is invisible" \
         "${unread[*]}"
fi

# An exemption that is no longer needed forgives a future break, so it has to go when it stops being true.
stale=()
while read -r reg _; do
    [[ -z "${reg}" || "${reg}" == \#* ]] && continue
    uses="$(grep -rho "\b${reg}\b" --include='*.yaml' --include='*.yml' "${SCAN_ROOT}" | grep -c . || true)"
    if [[ "${uses}" -gt 1 ]]; then
        stale+=("${reg}")
    elif [[ "${uses}" -eq 0 ]]; then
        stale+=("${reg} (no longer exists)")
    fi
done < <(grep -vE '^\s*(#|$)' "${ALLOWED_FILE}" 2>/dev/null || true)

if [[ ${#stale[@]} -eq 0 ]]; then
    pass "tolerated_failures_allowed.txt has no stale entries"
else
    fail "tolerated_failures_allowed.txt forgives results that are now read, or no longer exist" "${stale[*]}"
fi

finish "tolerated failures"
