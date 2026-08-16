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

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

ALLOWLIST="$(dirname "${BASH_SOURCE[0]}")/failed_key_reads_allowed.txt"

info "Tier 1: nothing decides from a result's failed key"

# Where a decision can be made from a result: the playbook, its roles, and the verify play.
SEARCH_PATHS=("${ANSIBLE_DIR}/roles" "${ANSIBLE_DIR}/site.yaml" "${E2E_ROOT}/tier3/verify.yaml")

# Four ways to reach the key: a selectattr or rejectattr on it, a map over it, dotted access, and
# bracket access. Comment lines are stripped first, because this file and the roles both discuss the
# pattern at length and a check that trips over its own documentation is useless.
matches="$(
    for p in "${SEARCH_PATHS[@]}"; do
        [[ -e "${p}" ]] || continue
        grep -rn --include='*.yaml' --include='*.yml' -E \
            "(select|reject)attr\([[:space:]]*['\"]failed['\"]|attribute=['\"]failed['\"]|[a-z_]+\.failed[[:space:]]*[|}]|\[['\"]failed['\"]\]" \
            "${p}" 2>/dev/null
    done | grep -vE ':[0-9]+:[[:space:]]*#' || true
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
