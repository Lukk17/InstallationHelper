#!/usr/bin/env bash
#
# Tier 2: every pinned download location must still exist.
#
# This is the gap that let Antigravity sit pinned at 1.13.3 while the package had moved to 2.8.1, with
# no tier noticing. Names are resolved against package indexes by the check beside this one, and the
# vendor URLs were resolved by nothing at all: a pinned version can rot quietly, and the first sign
# is an install failing on a real machine months later. Three of those are already in
# docs/regression_ledger.md, including a 404 that read as a network problem.
#
# Nothing is downloaded. Each location gets a HEAD request, and the ones that refuse HEAD get a ranged
# GET of the first byte, which is what a redirecting content host tends to answer. So this costs a few
# seconds and a few kilobytes for the whole set, rather than the several gigabytes the artifacts weigh.
#
# The locations come from the pinned values port rather than from a regular expression pasted here,
# because a third of them are built out of other pins and only the port resolves those references.
# Reimplementing that resolution in bash is exactly the second-parser mistake this repository keeps
# paying for.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# The shell end of the pinned values port, and the only thing here that reads a pin. Sourced rather
# than executed. See setup/pinned_values.
source "${REPO_ROOT}/setup/pinned_values/pinned_values.sh"

require_cmd curl

ALLOWED_FILE="$(dirname "${BASH_SOURCE[0]}")/pinned_urls_allowed.txt"

info "Tier 2: pinned download locations"

# Every pinned value that looks like a location, one per line as <key> <url>. The port hands back
# finished strings with every reference already resolved, so nothing here renders anything and no
# Ansible is needed to read a pin: pinned_values_load puts each pin in PIN_<NAME> and compgen lists
# what arrived. Pin names are lowercase by rule, so lowercasing the variable name recovers the name
# to report.
collect_urls() {
    pinned_values_load || return 1

    local variable name
    for variable in $(compgen -v PIN_ | sort); do
        [[ "${!variable}" == *://* ]] || continue
        name="$(tr '[:upper:]' '[:lower:]' <<<"${variable#PIN_}")"
        printf '%s %s\n' "${name}" "${!variable}"
    done
}

mapfile -t entries < <(collect_urls)

# A collector that returns nothing would pass every assertion below without checking a single URL,
# which is the vacuous pass this repository has been caught by twice. There are dozens of these pins.
if [[ ${#entries[@]} -lt 10 ]]; then
    fail "only ${#entries[@]} pinned locations were collected, so this check cannot mean anything" \
         "expected dozens through setup/pinned_values, so either the pins cannot be read here or they have moved"
    finish "pinned download locations"
fi

# HEAD first. A vendor that refuses HEAD gets a one-byte ranged GET, which is enough to prove the
# object is served without pulling a 230 MB artifact. 401 and 403 count as reachable on purpose: they
# prove the location exists and the download needs a session, which is a different problem from rot.
url_alive() {
    local url="$1" code
    code="$(curl -s -o /dev/null -w '%{http_code}' -I -L --max-time 25 "$url" || true)"
    case "${code}" in
        200|401|403) return 0 ;;
    esac
    code="$(curl -s -o /dev/null -w '%{http_code}' -r 0-0 -L --max-time 25 "$url" || true)"
    case "${code}" in
        200|206|401|403) return 0 ;;
    esac
    printf '%s' "${code}"
    return 1
}

# A key naming a base or a repository is not a downloadable object. An apt or yum repository answers
# on the files beneath it, Release and the package pool, and returns 404 on the base itself, and a
# content-delivery base is the same. Probing those reports rot that is not there, which is how a check
# earns the right to be ignored. They are skipped by rule rather than by an allowlist entry each,
# because the rule is a property of what the value is, and the count is reported so the skipping is
# never silent.
dead=()
skipped=()
checked=0
for entry in "${entries[@]}"; do
    key="${entry%% *}"
    url="${entry#* }"
    grep -qE "^${key}([[:space:]]|$)" "${ALLOWED_FILE}" 2>/dev/null && continue
    if [[ "${key}" =~ (_base|_repo)$ ]]; then
        skipped+=("${key}")
        continue
    fi
    checked=$((checked + 1))
    if ! code="$(url_alive "${url}")"; then
        dead+=("${key} -> HTTP ${code:-no answer} ${url}")
    fi
done

if [[ ${#skipped[@]} -gt 0 ]]; then
    info "not probed, a base or repository path is not an object: ${skipped[*]}"
fi

if [[ ${#dead[@]} -eq 0 ]]; then
    pass "all ${checked} pinned download locations answer"
else
    fail "${#dead[@]} of ${checked} pinned download locations do not answer" "$(printf '%s; ' "${dead[@]}")"
fi

# An allowlist entry that has stopped matching a real pin forgives nothing and hides a rename.
stale=()
while read -r key _; do
    [[ -z "${key}" || "${key}" == \#* ]] && continue
    printf '%s\n' "${entries[@]}" | grep -qE "^${key} " || stale+=("${key}")
done < <(grep -vE '^\s*(#|$)' "${ALLOWED_FILE}" 2>/dev/null || true)

if [[ ${#stale[@]} -eq 0 ]]; then
    pass "pinned_urls_allowed.txt has no stale entries"
else
    fail "pinned_urls_allowed.txt names pins that no longer exist" "${stale[*]}"
fi

finish "pinned download locations"
