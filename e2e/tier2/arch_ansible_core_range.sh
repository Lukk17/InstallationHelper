#!/usr/bin/env bash
#
# Tier 2: the ansible-core Arch Linux ships today sits inside the range setup/setup.sh accepts.
#
# setup.sh refuses a control node whose ansible-core is outside ANSIBLE_CORE_MIN_VERSION up to but not
# including ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE, and every e2e/tier3/*.Dockerfile asserts the same two
# bounds at build time. Arch is rolling and CachyOS takes ansible-core from Arch's extra repository, so
# the day extra moves to a branch at or above the ceiling, setup.sh refuses every Arch and CachyOS
# machine and the tier 3 arch and cachyos images stop building. That happened when extra moved to
# ansible-core 2.22.0-1 on 2026-11-03 under a ceiling of 2.22.0. Nothing said so until the tier 3 Arch
# image failed its base check on GitHub run 42791629177 (docs/regression_ledger.md 10.263).
#
# So this asks https://archlinux.org/packages/search/json/?name=ansible-core for the pkgver extra carries
# now, through http_ask in lib/http_ask.sh, the way check_pacman in resolve_packages.sh asks for a name,
# and compares it with both bounds read out of setup/setup.sh, using the version_lt that setup.sh itself
# enforces them with. A version at or above the ceiling, or below the floor, fails and names the version
# and the range. Only the extra repository counts, because a release still in extra-testing has not
# reached a machine. A lookup that never gets a definite answer fails as `could not be checked`, the way
# every name check over http_ask does, never as a version outside the range.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/http_ask.sh"

require_cmd curl

LABEL="Arch ansible-core range"
CLAIM="the ansible-core in Arch extra sits inside the range setup/setup.sh accepts"
SETUP_SH="${REPO_ROOT}/setup/setup.sh"
ARCH_URL="https://archlinux.org/packages/search/json/?name=ansible-core"

info "Tier 2: ${CLAIM}"

require_python "${CLAIM}" "${LABEL}"

floor="$(sed -n 's/^ANSIBLE_CORE_MIN_VERSION="\(.*\)"$/\1/p' "${SETUP_SH}")"
ceiling="$(sed -n 's/^ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE="\(.*\)"$/\1/p' "${SETUP_SH}")"
version_lt_source="$(sed -n '/^version_lt()/,/^}/p' "${SETUP_SH}")"
if [[ -z "${floor}" || -z "${ceiling}" || -z "${version_lt_source}" ]]; then
    fail "setup/setup.sh no longer declares ANSIBLE_CORE_MIN_VERSION, ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE and version_lt, so there is no range to compare with" \
         "${SETUP_SH}"
    finish "${LABEL}"
fi
eval "${version_lt_source}"

status=0
http_ask "${ARCH_URL}" '"results"' || status=$?
case ${status} in
    1)
        fail "Arch ansible-core: ${ARCH_URL} answered HTTP ${HTTP_CODE}, so there is no version to compare with the range" \
             "the package search answers an empty results list for an unknown name, never a 404"
        finish "${LABEL}"
        ;;
    2)
        fail "Arch ansible-core: the version could not be checked, because the index never gave a definite answer" \
             "$(http_unresolved_reason "${ARCH_URL}")"
        finish "${LABEL}"
        ;;
esac

parse_status=0
versions="$("${PYTHON}" -I -c '
import json, sys
for entry in json.load(sys.stdin).get("results", []):
    if entry.get("pkgname") == "ansible-core" and entry.get("repo") == "extra":
        print(entry.get("pkgver", ""))
' <<<"${HTTP_BODY}")" || parse_status=$?
assert_python_ran "${parse_status}" "${LABEL}"

if [[ -z "${versions}" ]]; then
    fail "Arch ansible-core: the package search lists no ansible-core in extra, so there is no version to compare with the range" \
         "${ARCH_URL}"
    finish "${LABEL}"
fi

range="${floor} <= version < ${ceiling}"
while IFS= read -r version; do
    if [[ -z "${version}" ]]; then
        fail "Arch ansible-core: extra lists ansible-core with no pkgver" "${ARCH_URL}"
    elif version_lt "${version}" "${floor}"; then
        fail "Arch extra carries ansible-core ${version}, below the range ${range} that setup/setup.sh accepts, so setup.sh refuses every Arch and CachyOS machine" \
             "${ARCH_URL}"
    elif ! version_lt "${version}" "${ceiling}"; then
        fail "Arch extra carries ansible-core ${version}, at or above the ceiling of the range ${range} that setup/setup.sh accepts, so setup.sh refuses every Arch and CachyOS machine and the tier 3 arch and cachyos images fail their base check" \
             "read the ${version%.*} changelog and porting guide against this repository, then raise ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE in setup/setup.sh and in every e2e/tier3/*.Dockerfile together. ${ARCH_URL}"
    else
        pass "Arch extra carries ansible-core ${version}, inside the range ${range} that setup/setup.sh accepts"
    fi
done <<<"${versions}"

finish "${LABEL}"
