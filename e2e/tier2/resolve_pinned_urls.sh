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
#
# Three outcomes, not two. The version of this check that had only two called an unreachable host a
# rotted pin, and on 2026-08-20 it reported veracrypt_rpm_url as dead when the truth was that
# Launchpad's file host launchpadlibrarian.net was answering nothing at all from this machine: the
# TLS handshake completed, the request went out, and no response ever came back. The run after it
# named veracrypt_url as well, which is the signature of a network fault rather than of a vendor
# removing a file. A check that cries wolf gets ignored, and this one is the only thing standing
# between a pin rotting and a real machine finding out, so the two are kept apart:
#
#   alive       the server answered about this object and it is there.
#   gone        the server answered about this object and it is not there. That is a real failure.
#   unresolved  no answer arrived. Nothing is known, so this is a skip that names the host and the
#               reason, never a pass and never a failure.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/http_ask.sh"
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

# kicad9_icon_urls  ->  "kicad9_icon_<tool> <url>" per line, and 1 when the pin is missing, an entry names no
#                       tool or there is no entry, built as custom_installs.yaml builds it, {{ kicad9_icon_base }}/{{ item.tool }}.svg
kicad9_icon_urls() {
    local base tool count=0
    base="$(pinned_value kicad9_icon_base)" || return 1
    [[ -n "${base}" ]] || return 1
    while IFS= read -r tool; do
        [[ -n "${tool}" ]] || return 1
        printf 'kicad9_icon_%s %s/%s.svg\n' "${tool}" "${base}" "${tool}"
        count=$((count + 1))
    done < <(kicad9_launcher_tools)
    [[ ${count} -gt 0 ]]
}

icon_list=""
if icon_list="$(kicad9_icon_urls)"; then
    mapfile -t icon_entries <<<"${icon_list}"
    entries+=("${icon_entries[@]}")
    info "KiCad 9 icon locations built from kicad9_icon_base and the ${#icon_entries[@]} tools of kicad9_launchers"
else
    fail "no KiCad 9 icon location could be built, so the icons custom_installs.yaml downloads are checked by nothing" \
         "kicad9_icon_base in setup/pinned_values/pinned_values.toml and a tool in every kicad9_launchers entry of setup/ansible/group_vars/all.yaml are both needed"
fi

# Each location is asked through url_verdict in lib/http_ask.sh, which owns the HEAD and ranged GET
# probe, the retry of a location that gave no answer, and which statuses read as alive or gone.
#
# A key naming a base or a repository is not a downloadable object. An apt or yum repository answers
# on the files beneath it, Release and the package pool, and returns 404 on the base itself, and a
# content-delivery base is the same. Probing those reports rot that is not there, which is how a check
# earns the right to be ignored. They are skipped by rule rather than by an allowlist entry each,
# because the rule is a property of what the value is, and the count is reported so the skipping is
# never silent.
gone=()
unresolved_names=()
unresolved_details=()
not_objects=()
alive=0
checked=0
for entry in "${entries[@]}"; do
    key="${entry%% *}"
    url="${entry#* }"
    grep -qE "^${key}([[:space:]]|$)" "${ALLOWED_FILE}" 2>/dev/null && continue
    if [[ "${key}" =~ (_base|_repo)$ ]]; then
        not_objects+=("${key}")
        continue
    fi
    checked=$((checked + 1))
    IFS=$'\t' read -r verdict detail effective < <(url_verdict "${url}")
    case "${verdict}" in
        alive)
            alive=$((alive + 1))
            ;;
        gone)
            gone+=("${key}: ${detail}: ${url}")
            ;;
        *)
            unresolved_names+=("${key} unresolved, $(url_host "${effective}") gave no answer")
            unresolved_details+=("${detail}, after ${PROBE_ATTEMPTS} attempts. Nothing is known about this location, so it is neither proven alive nor proven rotted: ${effective}")
            ;;
    esac
done

if [[ ${#not_objects[@]} -gt 0 ]]; then
    info "not probed, a base or repository path is not an object: ${not_objects[*]}"
fi

# One skip per unresolved location, so finish counts them and the tally cannot read as clean. A
# location nobody could reach is the one most likely to have rotted unnoticed, so it is named here
# and named again in the tally rather than folded into a single line that scrolls past.
for i in "${!unresolved_names[@]}"; do
    skip "${unresolved_names[i]}" "${unresolved_details[i]}"
done

if [[ ${#gone[@]} -eq 0 ]]; then
    if [[ ${#unresolved_names[@]} -eq 0 ]]; then
        pass "all ${checked} pinned download locations answer"
    else
        pass "${alive} of ${checked} pinned download locations answer, ${#unresolved_names[@]} unreachable and therefore unproven"
    fi
else
    fail "${#gone[@]} of ${checked} pinned download locations are gone" "$(printf '%s; ' "${gone[@]}")"
fi

# An allowlist entry that has stopped matching a real pin forgives nothing and hides a rename.
stale=()
while read -r key _; do
    [[ -z "${key}" || "${key}" == \#* ]] && continue
    grep -qE "^${key} " <<<"$(printf '%s\n' "${entries[@]}")" || stale+=("${key}")
done < <(grep -vE '^\s*(#|$)' "${ALLOWED_FILE}" 2>/dev/null || true)

if [[ ${#stale[@]} -eq 0 ]]; then
    pass "pinned_urls_allowed.txt has no stale entries"
else
    fail "pinned_urls_allowed.txt names pins that no longer exist" "${stale[*]}"
fi

finish "pinned download locations"
