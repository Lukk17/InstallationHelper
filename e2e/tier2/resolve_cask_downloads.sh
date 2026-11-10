#!/usr/bin/env bash
#
# Tier 2: the file every Homebrew cask the macOS mapping installs downloads must still exist.
#
# resolve_packages.sh asks formulae.brew.sh whether each cask name exists. That is not the question that
# failed on 2026-11-10. GitHub-hosted macOS run 42791651164 installed every cask but one, and the one,
# tor-browser 16.0, had a healthy entry in the index whose download was gone:
#
#   https://www.torproject.org/dist/torbrowser/16.0/tor-browser-macos-16.0.dmg   302, then 404
#
# brew tried four times and reported `curl: (22) The requested URL returned error: 404` about twenty
# minutes into the run. The name check passed and was right to, because the cask exists. The file below
# it does not. See docs/regression_ledger.md 10.257.
#
# So this asks the level below. For every cask in vars/Darwin.yaml, and every companion_packages name
# the cask index knows, it reads https://formulae.brew.sh/api/cask/<token>.json, takes "url" and the
# "url" of every macOS entry under "variations", which is where the Apple Silicon and Intel builds and
# the builds for older macOS releases differ, and asks each address with the HEAD and ranged GET probe
# in lib/http_ask.sh. Nothing is downloaded. A variation named *_linux is not asked, because casks are
# installed here only on macOS, and neither is one for an architecture the cask's depends_on arch rules
# out, because brew never downloads it: lm-studio declares arm64 and still lists Intel addresses that
# answer 404. Nor is a variation for a macOS release older than OLDEST_MACOS, macOS 14 Sonoma, the
# oldest release this project supports by the owner's decision of 2026-11-10: slack's big_sur and
# arm64_big_sur variations name Slack 4.45.69, which answers 403 (docs/regression_ledger.md 10.261).
# A variation key that names no release in MACOS_RELEASES fails the check by name, so a new macOS is
# added to the table rather than skipped unseen. The table is Homebrew's own, RELEASES in
# Library/Homebrew/macos_version.rb, without the releases before Big Sur, which no variation can name.
#
# Three outcomes per address, as in resolve_pinned_urls.sh. A 4xx answer to the ranged GET is gone and
# fails the check, naming the cask, the address and the status, because brew downloads a cask with no
# session and gets the same answer. 429 is a rate limit rather than an answer about the file, so it
# stays with the 5xx range and the network faults as unresolved: a SKIP naming the cask and the host,
# never a pass and never a failure. A lookup in the cask index that never gets a definite answer fails
# as `could not be checked`, the way every name check over http_ask does.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/package_probe.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/http_ask.sh"

require_cmd curl

LABEL="Homebrew cask download locations"
DARWIN_VARS="${ANSIBLE_DIR}/vars/Darwin.yaml"
FIELD_SEPARATOR=$'\x1f'

# Read by http_verdict in lib/http_ask.sh, which shellcheck cannot see from here.
# shellcheck disable=SC2034
DOWNLOAD_ALIVE_CODES='200|206'
# shellcheck disable=SC2034
DOWNLOAD_GONE_CODES='4(0[0-9]|1[0-9]|2[0-8]|[3-9][0-9])'

# The user agents brew sends. HOMEBREW_USER_AGENT_CURL is "Homebrew/<version> (<os>) curl/<version>",
# and a cask whose url carries user_agent: :fake gets HOMEBREW_USER_AGENT_FAKE_SAFARI. The version
# numbers here are only the shape of those strings, not a pinned Homebrew release.
BREW_USER_AGENT="Homebrew/4.6.0 (Macintosh; arm64 Mac OS X 15.0) curl/8.7.1"
FAKE_SAFARI_USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

# Homebrew's variation key for each macOS release, without the arm64_ prefix, and its major version.
MACOS_RELEASES="big_sur=11 monterey=12 ventura=13 sonoma=14 sequoia=15 tahoe=26 golden_gate=27"
OLDEST_MACOS="sonoma"

info "Tier 2: ${LABEL}"

require_python "every Homebrew cask download location answers" "${LABEL}"

# cask_locations  ->  one line per distinct address in the cask JSON on stdin,
#                     "<labels><US><url>[<US><curl argument>...]", labels being "default" for "url" and
#                     the variation names, comma separated, and the curl arguments the user agent,
#                     referer, headers and cookies the url_specs ask brew to send, then one line
#                     "-unknown<US><variation names>" for the keys MACOS_RELEASES does not know,
#                     "-older<US><variation names>" for the releases older than OLDEST_MACOS and
#                     "-arch<US><variation names>" for the architectures the cask's depends_on arch
#                     rules out, each only when it names something. Prints no address line for a cask
#                     with no address.
#
# Only the macOS variations are asked. The ones named <arch>_linux are Homebrew on Linux, which the
# playbook never runs. A variation for the architecture the cask's own depends_on arch refuses is never
# installed by brew either: lm-studio declares arm64, and its Intel variations name an x64 build that
# answered 404 on 2026-11-10, so they are named in a dim line instead of being asked.
cask_locations() {
    BREW_USER_AGENT="${BREW_USER_AGENT}" FAKE_SAFARI_USER_AGENT="${FAKE_SAFARI_USER_AGENT}" \
        MACOS_RELEASES="${MACOS_RELEASES}" OLDEST_MACOS="${OLDEST_MACOS}" "${PYTHON}" -c '
import json, os, sys
cask = json.loads(sys.stdin.read())

def curl_arguments(specs):
    agent = specs.get("user_agent")
    if agent in (None, "", ":default", "default"):
        agent = os.environ["BREW_USER_AGENT"]
    elif agent in (":fake", "fake"):
        agent = os.environ["FAKE_SAFARI_USER_AGENT"]
    arguments = ["-A", str(agent)]
    if specs.get("referer"):
        arguments += ["-e", str(specs["referer"])]
    headers = specs.get("header") or specs.get("headers") or []
    for header in [headers] if isinstance(headers, str) else headers:
        arguments += ["-H", str(header)]
    cookies = specs.get("cookies") or {}
    if cookies:
        arguments += ["-b", "; ".join(f"{name}={value}" for name, value in cookies.items())]
    return arguments

arch_types = [str(entry.get("type") if isinstance(entry, dict) else entry)
              for entry in (cask.get("depends_on") or {}).get("arch") or []]
arm_only = bool(arch_types) and all("arm" in kind for kind in arch_types)
intel_only = bool(arch_types) and all("intel" in kind for kind in arch_types)

releases = {key: int(major) for key, major in
            (pair.split("=") for pair in os.environ["MACOS_RELEASES"].split())}
oldest = releases[os.environ["OLDEST_MACOS"]]

base_specs = cask.get("url_specs") or {}
locations = {}
not_asked = {"unknown": [], "older": [], "arch": []}
def add(label, url, specs):
    if not url:
        return
    if url not in locations:
        locations[url] = ([], curl_arguments(specs))
    locations[url][0].append(label)

add("default", cask.get("url"), base_specs)
for name, variation in sorted((cask.get("variations") or {}).items()):
    if name.endswith("_linux"):
        continue
    release = name.removeprefix("arm64_")
    if release not in releases:
        not_asked["unknown"].append(name)
        continue
    if releases[release] < oldest:
        not_asked["older"].append(name)
        continue
    if (arm_only and not name.startswith("arm64_")) or (intel_only and name.startswith("arm64_")):
        not_asked["arch"].append(name)
        continue
    add(name, variation.get("url"), variation.get("url_specs", base_specs))
for url, (labels, arguments) in locations.items():
    print("\x1f".join([",".join(labels), url] + arguments))
for reason, names in not_asked.items():
    if names:
        print("\x1f".join(["-" + reason, ",".join(names)]))
'
}

mapfile -t mapped < <(package_names_for "${DARWIN_VARS}" brew_cask)
mapfile -t companions < <(companion_packages_of "${DARWIN_VARS}" | awk '{print $2}' | sort -u)

# Fewer than this many would pass every assertion below while checking almost nothing, the vacuous pass
# this repository has been caught by more than once. vars/Darwin.yaml maps dozens of casks.
if [[ ${#mapped[@]} -lt 10 ]]; then
    fail "only ${#mapped[@]} casks were read out of vars/Darwin.yaml, so this check cannot mean anything" \
         "expected dozens of software_mapping entries with manager: \"brew_cask\" in ${DARWIN_VARS}"
    finish "${LABEL}"
fi

# Every cask once, with "companion" beside a companion_packages name, which may be a formula instead.
tokens=()
for token in "${mapped[@]}"; do tokens+=("${token} mapping"); done
for token in "${companions[@]}"; do
    grep -qxF -- "${token}" <<<"$(printf '%s\n' "${mapped[@]}")" || tokens+=("${token} companion")
done

missing=()
unresolved=()
formulae=()
no_address=()
other_arch=()
older_macos=()
unknown_macos=()
special_requests=()
entries=()
casks=0
for item in "${tokens[@]}"; do
    token="${item% *}"
    kind="${item#* }"
    index_url="https://formulae.brew.sh/api/cask/${token}.json"
    status=0
    http_ask "${index_url}" '"token"' || status=$?
    case ${status} in
        1)
            if [[ "${kind}" == companion ]]; then formulae+=("${token}"); else missing+=("${token}"); fi
            continue
            ;;
        2)
            unresolved+=("${token}: $(http_unresolved_reason "${index_url}")")
            continue
            ;;
    esac
    casks=$((casks + 1))

    python_status=0
    locations="$(cask_locations <<<"${HTTP_BODY}")" || python_status=$?
    assert_python_ran "${python_status}" "${LABEL}"
    addresses=0
    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        case "${line}" in
            "-unknown${FIELD_SEPARATOR}"*) unknown_macos+=("${token} (${line#*"${FIELD_SEPARATOR}"})"); continue ;;
            "-older${FIELD_SEPARATOR}"*)   older_macos+=("${token} (${line#*"${FIELD_SEPARATOR}"})"); continue ;;
            "-arch${FIELD_SEPARATOR}"*)    other_arch+=("${token} (${line#*"${FIELD_SEPARATOR}"})"); continue ;;
        esac
        addresses=$((addresses + 1))
        entries+=("${token}${FIELD_SEPARATOR}${line}")
        [[ "${line}" == *"${BREW_USER_AGENT}"* ]] || special_requests+=("${token}")
    done <<<"${locations}"
    [[ ${addresses} -gt 0 ]] || no_address+=("${token}")
done

report_names "Homebrew cask index" "cask tokens" "$(( ${#tokens[@]} - ${#formulae[@]} ))"
[[ ${#formulae[@]} -gt 0 ]] && dim "companion_packages names the cask index does not have, so formulae with no cask download: ${formulae[*]}"
[[ ${#other_arch[@]} -gt 0 ]] && dim "variations not asked, because the cask's depends_on arch rules their architecture out: ${other_arch[*]}"
[[ ${#older_macos[@]} -gt 0 ]] && dim "variations not asked, because their macOS is older than ${OLDEST_MACOS}, the oldest this project supports: ${older_macos[*]}"
[[ ${#special_requests[@]} -gt 0 ]] && dim "casks whose url_specs set their own user agent: $(printf '%s\n' "${special_requests[@]}" | sort -u | tr '\n' ' ')"

if [[ ${#unknown_macos[@]} -gt 0 ]]; then
    fail "${#unknown_macos[@]} casks have variation keys that name no macOS release this check knows, so nothing here can say whether they are older than ${OLDEST_MACOS}" \
         "${unknown_macos[*]}. Add the release to MACOS_RELEASES in e2e/tier2/resolve_cask_downloads.sh from RELEASES in Homebrew's Library/Homebrew/macos_version.rb"
fi

if [[ ${#no_address[@]} -gt 0 ]]; then
    fail "${#no_address[@]} casks have no download address in their formulae.brew.sh entry, so nothing here can say whether brew can download them" \
         "${no_address[*]}"
fi

gone=()
unresolved_names=()
unresolved_details=()
alive=0
checked=0
for entry in "${entries[@]}"; do
    IFS="${FIELD_SEPARATOR}" read -r -a parts <<<"${entry}"
    token="${parts[0]}"
    labels="${parts[1]}"
    url="${parts[2]}"
    curl_arguments=("${parts[@]:3}")
    checked=$((checked + 1))
    IFS=$'\t' read -r verdict detail effective < <(url_verdict "${url}" "${curl_arguments[@]}")
    reached=""
    [[ "${effective}" != "${url}" ]] && reached=", reached ${effective}"
    case "${verdict}" in
        alive)
            alive=$((alive + 1))
            ;;
        gone)
            gone+=("${token} (${labels}): ${detail}: ${url}${reached}")
            ;;
        *)
            unresolved_names+=("${token} (${labels}) unresolved, $(url_host "${effective}") gave no answer")
            unresolved_details+=("${detail}, after ${PROBE_ATTEMPTS} attempts. Nothing is known about this location, so it is neither proven alive nor proven gone: ${url}${reached}")
            ;;
    esac
done

for i in "${!unresolved_names[@]}"; do
    skip "${unresolved_names[i]}" "${unresolved_details[i]}"
done

if [[ ${checked} -eq 0 ]]; then
    fail "no cask download address was asked, so this check proves nothing" \
         "the ${#tokens[@]} cask tokens read out of ${DARWIN_VARS} produced no address from formulae.brew.sh"
elif [[ ${#gone[@]} -eq 0 ]]; then
    if [[ ${#unresolved_names[@]} -eq 0 ]]; then
        pass "all ${checked} download locations of ${casks} casks answer"
    else
        pass "${alive} of ${checked} download locations of ${casks} casks answer, ${#unresolved_names[@]} unreachable and therefore unproven"
    fi
else
    fail "${#gone[@]} of ${checked} download locations of ${casks} casks are gone, so brew install --cask fails for each" \
         "$(printf '%s | ' "${gone[@]}")"
fi

finish "${LABEL}"
