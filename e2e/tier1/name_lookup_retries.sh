#!/usr/bin/env bash
#
# Tier 1: the tier 2 name checks call a name missing only when the index says so, and retry the rest.
#
# check_brew asked formulae.brew.sh once and read anything but 200, 301 or 302 as "does not exist", so
# one slow or failing request failed the gate as `Homebrew brew: 1 of 19 names do not exist / minikube`
# while https://formulae.brew.sh/api/formula/minikube.json answered 200 right after. See
# docs/regression_ledger.md. The same one-shot shape was in the Flathub, Chocolatey, AUR and npm lookups
# and in both Arch lookups, which fell back to "missing" once their retries ran out.
#
# Tier 2 needs the network and this does not. The real check functions are sourced out of
# e2e/tier2/resolve_packages.sh and run against a stand-in curl on PATH that answers from a script,
# per URL, one step per request: an HTTP status, `timeout` for curl's exit 28 with no status, `empty`
# for a 200 with no body, which is how archlinux.org answers a throttled request, and `none` for a 200
# carrying an empty results list, which is its definite "no such package". The last step repeats.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: the tier 2 name checks tell a missing name apart from a lookup that never answered"

RESOLVE_PACKAGES="${E2E_ROOT}/tier2/resolve_packages.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

mkdir -p "${work}/bin" "${work}/vars"
cat > "${work}/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
format="" out="" url=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) format="$2"; shift ;;
        -o) out="$2"; shift ;;
        -m|--max-time|--connect-timeout) shift ;;
        http*) url="$1" ;;
    esac
    shift
done
printf '%s\n' "${url}" >> "${STUB_STATE}/requests.log"
steps=""
while read -r pattern rest; do
    [[ -n "${pattern}" && "${url}" == *"${pattern}"* ]] && { steps="${rest}"; break; }
done < "${STUB_PLAN}"
read -r -a plan <<<"${steps:-404}"
counter="${STUB_STATE}/$(printf '%s' "${url}" | cksum | cut -d' ' -f1)"
n="$(cat "${counter}" 2>/dev/null || echo 0)"
printf '%s' "$((n + 1))" > "${counter}"
step="${plan[$(( n < ${#plan[@]} ? n : ${#plan[@]} - 1 ))]}"
code="${step}" body='{"results": [{"pkgname": "stub"}], "resultcount": 1}'
case "${step}" in
    timeout) printf '%b' "${format//%\{http_code\}/000}"; exit 28 ;;
    empty)   code=200; body="" ;;
    none)    code=200; body='{"results": []}' ;;
esac
if [[ -n "${out}" ]]; then printf '%s' "${body}" > "${out}"; else printf '%s' "${body}"; fi
printf '%b' "${format//%\{http_code\}/${code}}"
STUB
chmod +x "${work}/bin/curl"

# run_case <manager> <package> <plan line...>  ->  the output of the one check that resolves <manager>
run_case() {
    local manager="$1" package="$2"
    shift 2
    rm -rf "${work}/state"
    mkdir -p "${work}/state"
    printf '%s\n' "$@" > "${work}/plan"
    case "${manager}" in
        brew)   printf 'software_mapping:\n  probe: { manager: "brew", package: "%s" }\n' "${package}" > "${work}/vars/Darwin.yaml" ;;
        pacman) printf 'software_mapping:\n  probe: { manager: "pacman", package: "%s" }\n' "${package}" > "${work}/vars/Archlinux.yaml" ;;
    esac
    (
        export PATH="${work}/bin:${PATH}" STUB_PLAN="${work}/plan" STUB_STATE="${work}/state" HTTP_ASK_PAUSE=0
        # shellcheck source=../tier2/resolve_packages.sh
        source "${RESOLVE_PACKAGES}"
        # shellcheck disable=SC2034  # read by check_brew and check_pacman, sourced above
        VARS_DIR="${work}/vars"
        case "${manager}" in
            brew)   check_brew brew formula ;;
            pacman) check_pacman ;;
        esac
    ) 2>&1 || true
}

requests() { wc -l < "${work}/state/requests.log" | tr -d ' '; }

# expect <description> <output> <text that must appear> [text that must not appear]
expect() {
    if [[ "$2" != *"$3"* ]]; then
        fail "$1" "wanted ${3@Q} in: $(tr '\n' ' ' <<<"$2")"
    elif [[ -n "${4:-}" && "$2" == *"$4"* ]]; then
        fail "$1" "did not want ${4@Q} in: $(tr '\n' ' ' <<<"$2")"
    else
        pass "$1"
    fi
}

BREW_URL="https://formulae.brew.sh/api/formula/minikube.json"

out="$(run_case brew minikube "minikube 503 200")"
expect "a Homebrew name whose first lookup answered 503 and whose retry answered 200 resolves" "${out}" \
    "PASS Homebrew brew: all 1 names resolve" "do not exist"

out="$(run_case brew minikube "minikube timeout 200")"
expect "a Homebrew name whose first lookup timed out and whose retry answered 200 resolves" "${out}" \
    "PASS Homebrew brew: all 1 names resolve" "do not exist"

out="$(run_case brew minikube "minikube 404")"
expect "a Homebrew name the index answers 404 for is reported as not existing" "${out}" \
    "FAIL Homebrew brew: 1 of 1 names do not exist" "could not be checked"
if [[ "$(requests)" == "1" ]]; then
    pass "a 404 is a definite answer and is taken the first time, with no retry"
else
    fail "a 404 is a definite answer and is taken the first time, with no retry" "$(requests) requests were made"
fi

out="$(run_case brew minikube "minikube 503")"
expect "a Homebrew lookup that answers 503 every time is reported as not checked, naming the URL, never as a missing name" "${out}" \
    "${BREW_URL} answered HTTP 503, on all 4 attempts" "do not exist"
expect "a lookup that never answered fails the check rather than passing it" "${out}" \
    "FAIL Homebrew brew: 1 of 1 names could not be checked"

out="$(run_case brew hashicorp/tap/terraform "/master/ 404" "/main/ 200")"
expect "a tap-qualified name missing on master and present on main resolves" "${out}" \
    "PASS Homebrew brew: all 1 names resolve"

out="$(run_case brew hashicorp/tap/terraform "/master/ 404" "/main/ 503")"
expect "a tap-qualified name is not called missing while one branch never answered" "${out}" \
    "names could not be checked" "do not exist"

out="$(run_case pacman jq "search/json empty 200")"
expect "an Arch name whose first lookup came back throttled with an empty body resolves on the retry" "${out}" \
    "PASS Arch official repositories: all 1 package names resolve"

out="$(run_case pacman no-such-package "search/json none")"
expect "an Arch name archlinux.org answers with an empty results list is reported as not existing" "${out}" \
    "FAIL Arch official repositories: 1 of 1 package names do not exist" "could not be checked"

finish "tier 2 name lookups"
