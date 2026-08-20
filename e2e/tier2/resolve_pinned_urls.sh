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
# The shell end of the pinned values port, and the only thing here that reads a pin. Sourced rather
# than executed. See setup/pinned_values.
source "${REPO_ROOT}/setup/pinned_values/pinned_values.sh"

require_cmd curl

ALLOWED_FILE="$(dirname "${BASH_SOURCE[0]}")/pinned_urls_allowed.txt"

# --connect-timeout separately from --max-time so a refused or unroutable host is concluded in
# seconds instead of burning the whole budget, while a slow but working vendor still gets time to
# answer. An unresolved location is asked again rather than written off, because the fault this exists
# for came and went between two runs minutes apart. A host that stays silent therefore costs two
# requests times the attempt count, so roughly two minutes each, which is the price of not crying
# wolf and is paid only by a location nothing could reach.
PROBE_CURL_OPTS=(--connect-timeout 10 --max-time 20)
PROBE_ATTEMPTS=3
PROBE_RETRY_PAUSE=3

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

# What one HTTP status says about the object itself, which is a narrower question than whether the
# request went well.
#
#   alive       a 200 or a 206 header arrived, so the object is served. 401 and 403 join them on
#               purpose: they prove the location exists and the download wants a session, which is a
#               different problem from rot.
#   gone        the server was asked about this exact object and said it does not have it.
#   indefinite  the server said something else. 405 is a vendor refusing HEAD, 429 and the 5xx range
#               are the vendor's own trouble, and a 3xx still standing at the end means curl never
#               reached the end of the redirect chain. None of those is evidence either way, and
#               treating one of them as evidence is the bug being fixed here: launchpad.net answers
#               303 towards launchpadlibrarian.net, so when the librarian said nothing at all the
#               last code seen was that 303 and the pin read as dead.
http_verdict() {
    case "$1" in
        200|206|401|403) printf 'alive' ;;
        404|410)         printf 'gone' ;;
        *)               printf 'indefinite' ;;
    esac
}

# Why curl gave up, as a verb phrase that follows the name of the request that failed. Taken from the
# EXIT CODES section of the curl manual, https://curl.se/docs/manpage.html. Only the codes a download
# location can plausibly hit are spelled out and the rest fall through, because this list decides
# nothing: the verdict comes from whether curl exited zero at all, so an unnamed code is still
# classified correctly and merely gets a duller sentence.
curl_fault_reason() {
    case "$1" in
        5)     printf 'could not resolve the proxy host (curl 5)' ;;
        6)     printf 'could not resolve the host through DNS (curl 6)' ;;
        7)     printf 'could not connect to the host (curl 7)' ;;
        16|92) printf 'failed in the HTTP/2 framing layer (curl %s)' "$1" ;;
        18)    printf 'was cut off part way through (curl 18)' ;;
        28)    printf 'timed out with no answer (curl 28)' ;;
        35)    printf 'failed the TLS handshake (curl 35)' ;;
        47)    printf 'never reached the end of the redirect chain (curl 47)' ;;
        52)    printf 'connected and then got nothing back at all (curl 52)' ;;
        55)    printf 'could not send the request (curl 55)' ;;
        56)    printf 'lost the answer on the way back (curl 56)' ;;
        60)    printf 'could not verify the certificate against the local trust store (curl 60)' ;;
        95)    printf 'failed in the HTTP/3 layer (curl 95)' ;;
        *)     printf 'gave up with curl exit %s, see the EXIT CODES section of https://curl.se/docs/manpage.html' "$1" ;;
    esac
}

# The host a location really failed at, which is not always the host written in the pin. Both
# VeraCrypt pins name launchpad.net and both of them fail at launchpadlibrarian.net, so the skip line
# reads %{url_effective} rather than the pinned string and names the host a reader would have to go
# and poke.
url_host() {
    local rest="${1#*://}"
    rest="${rest%%/*}"
    printf '%s' "${rest%%\?*}"
}

# probe_once <url>  ->  "<verdict><tab><detail><tab><url actually reached>"
#
# curl's own exit status decides whether there is an answer to read at all, rather than the answer
# being guessed at from a body or from the last number that went past. Non-zero means the exchange
# never completed, and %{http_code} in that case holds whatever was seen on the way, which for a
# redirect is the redirect. So a non-zero exit contributes no verdict at all and only a clean exit
# gets its status interpreted.
#
# Two requests, HEAD first because it is the cheapest question that gets a real answer, then the
# one-byte ranged GET. The ranged GET runs whenever the HEAD did not prove the object is there, which
# includes the HEAD hanging: a host that will not answer a HEAD is refusing HEAD whether it says so
# with a 405 or by saying nothing, and this repository would rather spend one more request than call
# a live location unproven. It also means a 404 is seen twice before this check fails a build on it.
probe_once() {
    local url="$1" mode out code status effective saw_gone=0
    local notes=()

    effective="${url}"
    for mode in "HEAD" "a ranged GET"; do
        status=0
        if [[ "${mode}" == "HEAD" ]]; then
            out="$(curl -s -o /dev/null -w '%{http_code} %{url_effective}' -I -L "${PROBE_CURL_OPTS[@]}" "${url}")" || status=$?
        else
            out="$(curl -s -o /dev/null -w '%{http_code} %{url_effective}' -r 0-0 -L "${PROBE_CURL_OPTS[@]}" "${url}")" || status=$?
        fi
        code="${out%% *}"
        [[ "${out}" == *" "* ]] && effective="${out#* }"

        if [[ ${status} -ne 0 ]]; then
            notes+=("${mode} $(curl_fault_reason "${status}")")
            continue
        fi

        case "$(http_verdict "${code}")" in
            alive)
                printf 'alive\t%s answered HTTP %s\t%s\n' "${mode}" "${code}" "${effective}"
                return 0
                ;;
            gone)
                saw_gone=1
                notes+=("${mode} answered HTTP ${code}")
                ;;
            *)
                notes+=("${mode} answered HTTP ${code}, which says nothing about the object")
                ;;
        esac
    done

    local detail="${notes[0]}"
    if [[ ${#notes[@]} -gt 1 ]]; then
        detail="${detail} and ${notes[1]}"
    fi

    if [[ ${saw_gone} -eq 1 ]]; then
        printf 'gone\t%s\t%s\n' "${detail}" "${effective}"
    else
        printf 'unresolved\t%s\t%s\n' "${detail}" "${effective}"
    fi
}

# Retries only what is worth retrying. A definite answer is taken the first time it arrives, and an
# unresolved one is asked again, because an intermittent fault is exactly what this is.
url_verdict() {
    local url="$1" attempt result=""
    for (( attempt = 1; attempt <= PROBE_ATTEMPTS; attempt++ )); do
        result="$(probe_once "${url}")"
        if [[ "${result}" != unresolved* ]]; then
            printf '%s\n' "${result}"
            return 0
        fi
        if [[ ${attempt} -lt ${PROBE_ATTEMPTS} ]]; then
            sleep "${PROBE_RETRY_PAUSE}"
        fi
    done
    printf '%s\n' "${result}"
}

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
    printf '%s\n' "${entries[@]}" | grep -qE "^${key} " || stale+=("${key}")
done < <(grep -vE '^\s*(#|$)' "${ALLOWED_FILE}" 2>/dev/null || true)

if [[ ${#stale[@]} -eq 0 ]]; then
    pass "pinned_urls_allowed.txt has no stale entries"
else
    fail "pinned_urls_allowed.txt names pins that no longer exist" "${stale[*]}"
fi

finish "pinned download locations"
