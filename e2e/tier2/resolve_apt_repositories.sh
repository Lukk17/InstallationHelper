#!/usr/bin/env bash
#
# Tier 2: every apt repository the playbook writes, and every key it fetches for one, answers for
# Debian 13, Ubuntu 26.04, Linux Mint 22 and 22.2 and LMDE 6 and 7.
#
# e2e/tier1/apt_vendor_repositories.sh proves the lines say what this repository believes the vendors
# publish. This asks the vendors. The lines come from e2e/lib/apt_repositories.sh, the same rendering
# tier 1 asserts on, and only the ones that depend on the release or the lineage are asked, because
# those are the ones that differ per machine. A repository line is asked for the file apt fetches
# first, <uri>/dists/<suite>/InRelease, and for Release when InRelease is not there, which is what
# apt itself falls back to. A flat repository, whose suite ends in a slash, is asked under the suite
# itself. A key location is asked as it is.
#
# A 404 or 410 is a repository apt would refuse on that machine, which is the defect this exists for:
# the playbook wrote Linux Mint 22.2's own codename zara and LMDE 7's own gigi into the Docker,
# Tailscale and HashiCorp lines, and all three vendors answer 404 for both. An answer that never came
# is reported apart from that, naming the URL, through http_ask.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/http_ask.sh"
# shellcheck source=../lib/apt_repositories.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/apt_repositories.sh"

require_cmd curl
require_cmd ansible-playbook
require_python "the apt repository lines could not be rendered" "apt repository locations"

info "Tier 2: apt repository locations answer for every Debian-family fixture"

if ! apt_repositories_render; then
    fail "the repository lines could not be rendered, so nothing was asked" "${APT_RENDER_FAULT}"
    finish "apt repository locations"
fi

# index_url_of <deb line>  ->  the InRelease location apt fetches first for it, or nothing
index_url_of() {
    local words=() uri suite i=1
    read -r -a words <<<"$1"
    [[ "${words[0]:-}" == deb ]] || return 0
    if [[ "${words[1]:-}" == \[* ]]; then
        while [[ ${i} -lt ${#words[@]} && "${words[${i}]}" != *"]" ]]; do i=$((i + 1)); done
        i=$((i + 1))
    fi
    uri="${words[${i}]:-}"
    suite="${words[$((i + 1))]:-}"
    [[ -n "${uri}" && -n "${suite}" ]] || return 0
    if [[ "${suite}" == */ ]]; then
        printf '%s/%sInRelease\n' "${uri%/}" "${suite#/}"
    else
        printf '%s/dists/%s/InRelease\n' "${uri%/}" "${suite}"
    fi
}

# Asks one location, and for an InRelease that is definitely not there, the Release beside it.
ask_location() {
    local name="$1" url="$2" status=0
    http_ask "${url}" || status=$?
    if [[ ${status} -eq 1 && "${url}" == */InRelease ]]; then
        url="${url%InRelease}Release"
        status=0
        http_ask "${url}" || status=$?
    fi
    case ${status} in
        1) missing+=("${name}") ;;
        2) unresolved+=("${name}: $(http_unresolved_reason "${url}")") ;;
    esac
}

while IFS= read -r case_json; do
    [[ -z "${case_json}" ]] && continue
    fixture="$(apt_case_field "${case_json}" fixture)"
    missing=()
    unresolved=()
    asked=0
    declare -A seen=()
    while IFS=$'\t' read -r line_fixture kind varies source rendered; do
        [[ "${line_fixture}" == "${fixture}" && "${varies}" == 1 ]] || continue
        if [[ "${kind}" == repo ]]; then
            url="$(index_url_of "${rendered}")"
        else
            url="${rendered}"
        fi
        if [[ -z "${url}" ]]; then
            unresolved+=("${source}: no location could be read out of '${rendered}'")
            continue
        fi
        [[ -v "seen[${url}]" ]] && continue
        seen["${url}"]=1
        asked=$((asked + 1))
        ask_location "${url}" "${url}"
    done <<<"${APT_LINES}"
    unset seen
    if [[ ${asked} -eq 0 ]]; then
        fail "${fixture}: no repository line that depends on the release was rendered, so nothing was asked" "${APT_LINES:0:300}"
        continue
    fi
    report_names "${fixture}" "repository and key locations" "${asked}"
done <<<"${APT_CASES}"

finish "apt repository locations"
