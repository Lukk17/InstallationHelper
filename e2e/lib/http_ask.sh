#!/usr/bin/env bash
#
# Asking a package index over HTTP whether something exists, for tier 2. Sourced after common.sh,
# never executed directly.
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
        raw="$(curl -s -w '\n%{http_code}' --connect-timeout 10 --max-time 20 "${url}" 2>/dev/null)" || status=$?
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
# which bash's dynamic scope makes visible here.
ask_name() {
    local name="$1" url="$2" status=0
    http_ask "${url}" || status=$?
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
