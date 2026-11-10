#!/usr/bin/env bash
#
# Asking a package index over HTTP whether something exists, and asking a download location whether
# its file is still there, for tier 2. Sourced after common.sh, never executed directly.
#
# Three answers, not two. A name either exists, or the index said definitely that it does not (404 or
# 410), or no definite answer came back at all. The tier 2 name checks used to have two: one request,
# and anything other than 200, 301 or 302 meant "does not exist". So a timeout or a 503 from
# formulae.brew.sh failed the run as `Homebrew brew: 1 of 19 names do not exist / minikube` while
# https://formulae.brew.sh/api/formula/minikube.json answered 200 moments later. See
# docs/regression_ledger.md. Anything that is not a definite answer is asked again, and if it never
# becomes one the caller reports it as a lookup that could not be made, naming the URL and what came
# back, never as a missing name.
#
# HTTP_ASK_ATTEMPTS and HTTP_ASK_PAUSE are read from the environment so
# e2e/tier1/name_lookup_retries.sh can drive every path in seconds. The pause grows with each attempt,
# so the defaults wait 3, 6 and 9 seconds.

HTTP_ASK_ATTEMPTS="${HTTP_ASK_ATTEMPTS:-4}"
HTTP_ASK_PAUSE="${HTTP_ASK_PAUSE:-3}"

# Filled in by http_ask from its last attempt.
HTTP_CODE=""
HTTP_BODY=""
HTTP_FAULT=""
HTTP_ATTEMPTS_MADE=0

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

# Asks one URL until the answer is definite, and sets HTTP_CODE, HTTP_BODY, HTTP_FAULT and
# HTTP_ATTEMPTS_MADE. A 2xx or 3xx counts only when its body matches the extended regular expression
# in $2, when one is given, because archlinux.org answers a throttled request with 200 and no body.
# Returns 0 when it exists, 1 on 404 or 410, 2 when no attempt gave a definite answer.
http_ask() {
    local url="$1" answer_pattern="${2:-}" raw status attempt
    HTTP_FAULT=""
    for (( attempt = 1; attempt <= HTTP_ASK_ATTEMPTS; attempt++ )); do
        HTTP_ATTEMPTS_MADE=${attempt}
        status=0
        # The null bytes of a binary answer, such as a signing key, are dropped here rather than by
        # bash, which warns on stderr for each one. pipefail keeps curl's own status.
        raw="$(curl -s -w '\n%{http_code}' --connect-timeout 10 --max-time 20 "${url}" 2>/dev/null | tr -d '\000')" || status=$?
        HTTP_CODE="${raw##*$'\n'}"
        HTTP_BODY="${raw%$'\n'*}"
        if [[ ${status} -ne 0 ]]; then
            HTTP_FAULT="$(curl_fault_reason "${status}")"
        else
            case "${HTTP_CODE}" in
                2??|3??)
                    if [[ -z "${answer_pattern}" ]] || grep -qE -- "${answer_pattern}" <<<"${HTTP_BODY}"; then
                        return 0
                    fi
                    HTTP_FAULT="answered HTTP ${HTTP_CODE} with a body that held no answer"
                    ;;
                404|410)
                    return 1
                    ;;
                *)
                    HTTP_FAULT="answered HTTP ${HTTP_CODE}"
                    ;;
            esac
        fi
        if [[ ${attempt} -lt ${HTTP_ASK_ATTEMPTS} ]]; then
            sleep $(( attempt * HTTP_ASK_PAUSE ))
        fi
    done
    return 2
}

# One line naming the URL http_ask could not get a definite answer from, and what the last attempt
# got instead.
http_unresolved_reason() {
    printf '%s %s, on all %s attempts' "$1" "${HTTP_FAULT}" "${HTTP_ATTEMPTS_MADE}"
}

# Asks the URL for one name and files the name under the caller's own missing or unresolved array,
# which bash's dynamic scope makes visible here. A third argument is the answer pattern http_ask takes.
ask_name() {
    local name="$1" url="$2" status=0
    http_ask "${url}" "${3:-}" || status=$?
    case ${status} in
        1) missing+=("${name}") ;;
        2) unresolved+=("${name}: $(http_unresolved_reason "${url}")") ;;
    esac
}

# Reports the caller's own missing and unresolved arrays for one index: one pass, or a failure for each
# kind of problem, so a name that does not exist is never confused with a lookup that never answered.
report_names() {
    local label="$1" noun="$2" total="$3"
    if [[ ${#missing[@]} -eq 0 && ${#unresolved[@]} -eq 0 ]]; then
        pass "${label}: all ${total} ${noun} resolve"
        return
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        fail "${label}: ${#missing[@]} of ${total} ${noun} do not exist" "${missing[*]}"
    fi
    if [[ ${#unresolved[@]} -gt 0 ]]; then
        fail "${label}: ${#unresolved[@]} of ${total} ${noun} could not be checked, because the index never gave a definite answer" \
            "$(printf '%s | ' "${unresolved[@]}")"
    fi
}

# --- download locations ---------------------------------------------------------
# Nothing is downloaded. Each location gets a HEAD request, and the ones that refuse HEAD get a ranged
# GET of the first byte, which is what a redirecting content host tends to answer. Read by
# tier2/resolve_pinned_urls.sh for the pinned locations and by tier2/resolve_cask_downloads.sh for the
# files the Homebrew casks download.
#
# --connect-timeout separately from --max-time so a refused or unroutable host is concluded in
# seconds instead of burning the whole budget, while a slow but working vendor still gets time to
# answer. An unresolved location is asked again rather than written off, because the fault this exists
# for came and went between two runs minutes apart. A host that stays silent therefore costs two
# requests times the attempt count, so roughly two minutes each, which is the price of not crying
# wolf and is paid only by a location nothing could reach.
PROBE_CURL_OPTS=(--connect-timeout 10 --max-time 20)
PROBE_ATTEMPTS=3
PROBE_RETRY_PAUSE=3

# The statuses http_verdict reads as alive and as gone, as extended regular expressions. A caller
# sets both after sourcing this file when its downloads need no session, the way
# tier2/resolve_cask_downloads.sh does, because Homebrew downloads a cask without one and a 401 or a
# 403 is then the answer brew itself gets.
DOWNLOAD_ALIVE_CODES='200|206|401|403'
DOWNLOAD_GONE_CODES='404|410'

# What one HTTP status says about the object itself, which is a narrower question than whether the
# request went well.
#
#   alive       a 200 or a 206 header arrived, so the object is served. 401 and 403 join them by
#               default: they prove the location exists and the download wants a session, which is a
#               different problem from rot.
#   gone        the server was asked about this exact object and said it does not have it.
#   indefinite  the server said something else. 405 is a vendor refusing HEAD, 429 and the 5xx range
#               are the vendor's own trouble, and a 3xx still standing at the end means curl never
#               reached the end of the redirect chain. None of those is evidence either way, and
#               treating one of them as evidence is the bug being fixed here: launchpad.net answers
#               303 towards launchpadlibrarian.net, so when the librarian said nothing at all the
#               last code seen was that 303 and the pin read as dead.
http_verdict() {
    if [[ "$1" =~ ^(${DOWNLOAD_ALIVE_CODES})$ ]]; then
        printf 'alive'
    elif [[ "$1" =~ ^(${DOWNLOAD_GONE_CODES})$ ]]; then
        printf 'gone'
    else
        printf 'indefinite'
    fi
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

# probe_once <url> [curl argument...]  ->  "<verdict><tab><detail><tab><url actually reached>"
#
# The curl arguments after the URL are added to both requests, for a download that wants its own
# user agent, referer, header or cookie.
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
# a live location unproven. Only the ranged GET's gone answer counts as gone: the PowerShell Gallery
# answers HEAD with 404 for a package it serves, and its ranged GET then took 13 to 29 seconds on
# 2026-10-22, so a HEAD 404 beside a GET that timed out read as a dead pin when it was a slow one.
probe_once() {
    local url="$1" mode out code status effective saw_gone=0
    shift
    local notes=()

    effective="${url}"
    for mode in "HEAD" "a ranged GET"; do
        status=0
        if [[ "${mode}" == "HEAD" ]]; then
            out="$(curl -s -o /dev/null -w '%{http_code} %{url_effective}' -I -L "${PROBE_CURL_OPTS[@]}" "$@" "${url}")" || status=$?
        else
            out="$(curl -s -o /dev/null -w '%{http_code} %{url_effective}' -r 0-0 -L "${PROBE_CURL_OPTS[@]}" "$@" "${url}")" || status=$?
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
                if [[ "${mode}" == "HEAD" ]]; then
                    notes+=("${mode} answered HTTP ${code}, which some vendors answer for an object they serve")
                else
                    saw_gone=1
                    notes+=("${mode} answered HTTP ${code}")
                fi
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

# url_verdict <url> [curl argument...]  ->  the line probe_once prints, from the last attempt made
#
# Retries only what is worth retrying. A definite answer is taken the first time it arrives, and an
# unresolved one is asked again, because an intermittent fault is exactly what this is.
url_verdict() {
    local attempt result=""
    for (( attempt = 1; attempt <= PROBE_ATTEMPTS; attempt++ )); do
        result="$(probe_once "$@")"
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
