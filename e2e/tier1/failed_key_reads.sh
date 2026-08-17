#!/usr/bin/env bash
#
# Tier 1: nothing in the playbook may decide anything from a result's `failed` key.
#
# This check exists for one defect that cost a day and would have been caught in a second.
#
#   aur_reported_failures: >-
#     {{ (aur_results.results | default([]))
#        | selectattr('failed', 'defined')
#        | selectattr('failed', 'equalto', true)
#
# The task that produced `aur_results` carried `failed_when: false`, so one bad AUR build could not
# abandon a forty minute play. Ansible applies `failed_when` by rewriting the result's own `failed`
# key, so every item reached that expression with `failed: false` whatever the build did. The task
# whose entire job was reporting failed AUR builds had never reported one, and three builds that
# exited rc 1 with `"failed": true` in their own result files on disk were counted as successes.
#
# The same trap has a second form, which was also live here:
#
#   register: pacman_full_upgrade
#   failed_when: pacman_full_upgrade.failed | default(false)
#
# That restates the default when the key is present and turns anything into a pass when it is not,
# which an async result can be. Its only possible effect is to convert a failure into a success.
#
# So the rule is blunt on purpose: read `rc`, read `finished`, read the module's own fields, never
# read `failed`. `rc` and `finished` survive `failed_when` untouched, which is exactly why the
# timed-out AUR collector always worked while the failure collector never did.
#
# Genuine exceptions go in failed_key_reads_allowed.txt with a reason, one path per line, so an
# exception is a decision somebody wrote down rather than a grep that quietly matches less.
#
# One thing this deliberately does not forbid is `until: <result> is succeeded`, which forty tasks in
# this repository use as their retry condition. That test reads the same key through its negation, so
# a `failed_when: false` on a retried task would make it always true and the retries would never
# happen. Forbidding it would mean forty allowlist entries, and an allowlist with forty lines in it
# forgives by default rather than by decision. The failure-side tests are the ones matched, because
# those are the ones a collector or a gate reads to conclude something failed.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

ALLOWLIST="$(dirname "${BASH_SOURCE[0]}")/failed_key_reads_allowed.txt"

info "Tier 1: nothing decides from a result's failed key"

# Where a decision can be made from a result: the playbook, the task files it imports, the profile
# overlays, its roles, and the verify play. tasks/ and profiles/ were both missing until an audit
# noticed, and tasks/ now holds derive_os_facts.yaml, which decides the operating system family every
# later task branches on, so a result read in there steers the whole run.
SEARCH_PATHS=(
    "${ANSIBLE_DIR}/roles"
    "${ANSIBLE_DIR}/tasks"
    "${ANSIBLE_DIR}/profiles"
    "${ANSIBLE_DIR}/site.yaml"
    "${E2E_ROOT}/tier3/verify.yaml"
)

# Five ways to reach the key: a selectattr or rejectattr on it, a map over it, dotted access, bracket
# access, and the Jinja tests that read it by name.
#
# Dotted access is matched on a word boundary rather than on a following pipe or closing brace. The
# narrower version passed `when: r.failed` and `failed_when: r.failed == true`, which are the two
# shortest ways to write the exact thing this check forbids, and it was the second of those that
# shipped here as `failed_when: pacman_full_upgrade.failed | default(false)`. The boundary also keeps
# `failed_when` itself from matching, because an underscore is a word character.
#
# The variable half of dotted access accepts digits. Without them `k3d.failed` reads the key and no
# alternative sees it, because the run of letters the pattern needs ends at the digit.
#
# `is failed` and `is not failed` reach the same key without naming it, and `failure` is Ansible's
# alias for that test, so all four spellings are matched.
#
# Two kinds of line are dropped afterwards. Comment lines, because this file and the roles both
# discuss the pattern at length and a check that trips over its own documentation is useless. And task
# name declarations, because a name is a label rather than a decision, and `- name: Assert the
# download is not failed` is ordinary English that would otherwise force an allowlist entry. Entries
# there forgive a whole file, so a false positive does real damage: it buys silence for every real
# read in the same file.
matches="$(
    for p in "${SEARCH_PATHS[@]}"; do
        [[ -e "${p}" ]] || continue
        grep -rn --include='*.yaml' --include='*.yml' -E \
            "(select|reject)attr\([[:space:]]*['\"]failed['\"]|attribute=['\"]failed['\"]|[a-z0-9_]+\.failed\b|\[['\"]failed['\"]\]|\bis[[:space:]]+(not[[:space:]]+)?(failed|failure)\b" \
            "${p}" 2>/dev/null
    done | grep -vE ':[0-9]+:[[:space:]]*#' \
         | grep -vE ':[0-9]+:[[:space:]]*-?[[:space:]]*name:' || true
)"

if [[ -z "${matches}" ]]; then
    pass "no task reads a result's failed key"
    finish "failed key reads"
fi

unexpected=()
allowed=0
while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    file="${line%%:*}"
    rel="${file#"${REPO_ROOT}/"}"
    if [[ -f "${ALLOWLIST}" ]] && grep -qxF "${rel}" "${ALLOWLIST}"; then
        allowed=$((allowed + 1))
        continue
    fi
    unexpected+=("${rel}:${line#*:}")
done <<<"${matches}"

[[ ${allowed} -gt 0 ]] && dim "${allowed} read(s) forgiven by failed_key_reads_allowed.txt"

if [[ ${#unexpected[@]} -eq 0 ]]; then
    pass "every read of a failed key is on the allowlist"
else
    fail "${#unexpected[@]} task(s) decide from a result's failed key, which failed_when rewrites" \
         "$(printf '%s | ' "${unexpected[@]}")"
fi

finish "failed key reads"
