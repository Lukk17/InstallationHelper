#!/usr/bin/env bash
#
# Tier 1: the generated package manifests still match the toggles and mappings they came from.
#
# setup/manifests/ holds a Brewfile, a Chocolatey packages file and a winget configuration file, so a
# machine can be brought up with the vendor's own tooling instead of the whole playbook. They are
# generated from group_vars and the OS dictionaries, and a generated file that nobody regenerates is
# worse than no file at all: it looks authoritative, it is committed, and it quietly describes the
# software set as it was months ago.
#
# So this check regenerates them into memory and compares. Adding an application to the dictionary,
# or flipping a toggle, without regenerating is a failure here rather than a surprise for whoever
# trusts the manifest later.
#
# It also asserts the generator obeys the rule that the pinned values have exactly one reader: the
# manifests carry no version today, and the day someone adds pinning, it has to come through
# setup/pinned_values rather than through a second parse of the TOML.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

GENERATOR="${REPO_ROOT}/setup/manifests/generate.py"
MANIFEST_DIR="${REPO_ROOT}/setup/manifests"

info "Tier 1: the generated package manifests"

if [[ ! -f "${GENERATOR}" ]]; then
    fail "the manifest generator is missing" "${GENERATOR}"
    finish "generated manifests"
fi

require_python "the generated package manifests are up to date" "generated manifests"

# --- every manifest exists ------------------------------------------------------------------------
missing=()
for name in Brewfile packages.config configuration.winget; do
    [[ -f "${MANIFEST_DIR}/${name}" ]] || missing+=("${name}")
done
if [[ ${#missing[@]} -eq 0 ]]; then
    pass "all three manifests are present"
else
    fail "${#missing[@]} manifest(s) are missing, so nothing can be compared against them" "${missing[*]}"
    finish "generated manifests"
fi

# --- and matches what the generator produces today --------------------------------------------------
check_output=""
check_status=0
check_output="$("${PYTHON}" "${GENERATOR}" --check 2>&1)" || check_status=$?
if [[ ${check_status} -eq 0 ]]; then
    pass "every manifest matches the toggles and mappings it is generated from"
else
    fail "a generated manifest is out of date, so it describes a software set that is no longer true" \
         "${check_output}"
fi

# --- the manifests are not a second reader of the pinned values -------------------------------------
# The generator may ask setup/pinned_values for a value. It may not open the TOML itself, and neither
# may a manifest carry a rendered version that nothing keeps in step. e2e/tier1/pinned_values.sh owns
# the general form of this rule, and this is the manifest-shaped half of it.
if grep -qE 'pinned_values\.toml|import[[:space:]]+toml' "${GENERATOR}"; then
    fail "the generator reads the pinned values file itself instead of asking for a value" \
         "one reader owns that file, see setup/pinned_values"
else
    pass "the generator does not parse the pinned values file itself"
fi

# --- a manifest that lists nothing would pass every check above -------------------------------------
# The comparison is against the generator's own output, so a generator that produced empty files
# would agree with empty manifests and report success. The floor makes that impossible without
# somebody noticing, and it is set well below the real counts rather than at them, so ordinary
# additions and removals do not have to touch this file.
brew_lines="$(grep -cE '^(brew|cask) "' "${MANIFEST_DIR}/Brewfile" || true)"
choco_lines="$(grep -cE '^  <package id=' "${MANIFEST_DIR}/packages.config" || true)"
winget_lines="$(grep -cE '^    - resource: ' "${MANIFEST_DIR}/configuration.winget" || true)"

if [[ "${brew_lines}" -ge 40 && "${choco_lines}" -ge 3 && "${winget_lines}" -ge 50 ]]; then
    pass "the manifests carry ${brew_lines} Homebrew, ${choco_lines} Chocolatey and ${winget_lines} winget entries"
else
    fail "a manifest holds implausibly few entries, so the comparison above proves nothing" \
         "Homebrew ${brew_lines}, Chocolatey ${choco_lines}, winget ${winget_lines}"
fi

finish "generated manifests"
