#!/usr/bin/env bash
#
# Tier 1: every winget package whose manifest leaves the installer to a scope pins one.
#
# A winget manifest can carry the same package as several installers that differ by scope, and
# when the mapping in setup/ansible/vars/Windows.yaml names no scope, winget chooses. The wizard
# runs elevated, and three packages have now failed there while winget chose for them: Bruno.Bruno
# on 2026-08-22 with exit 3221225477, an access violation, Overwolf.CurseForge on 2026-08-25 with
# 0x8A150006, and Mirantis.Lens in GitHub sweep run 38107292439 on 2026-10-11 with both. The first
# two were fixed one at a time after they had failed, and nothing stopped the third from shipping
# the same way. For Lens the scope is the likely cause rather than a proven one, which the ledger
# entry spells out.
#
# The manifests live upstream and this tier is offline, so the facts come from
# winget_scoped_packages.txt beside this file, which tier2/resolve_packages.sh reads afresh from
# winget-pkgs and fails on when it has drifted. This check asserts, against that list:
#   1. every listed package is a winget mapping, so a stale entry cannot sit there forgiving nothing;
#   2. every listed package pins a scope;
#   3. the scope it pins is one its manifest can serve, because winget answers a scope the manifest
#      lacks with "No applicable installer found" rather than falling back. A user pin needs a user
#      installer. A machine pin needs a machine type in the third column, which an unscoped msix,
#      msstore, portable or font installer also gives, because winget ignores the manifest's scope
#      for those (winget-cli v1.29.380, DoesInstallerTypeIgnoreScopeFromManifest);
#   4. every winget mapping that pins a scope is listed, so a pin always has its evidence;
#   5. every machine pin carries installer_type, equal to the machine type listed, and no other
#      mapping carries one. setup/windows/WindowsSoftware.ps1 decides from it whether winget has to
#      run elevated, so a missing or stale type is a machine install that dies on
#      APPINSTALLER_CLI_ERROR_COMMAND_REQUIRES_ADMIN on a real machine, or a consent prompt nobody
#      needed.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

MAPPING_YAML="${ANSIBLE_DIR}/vars/Windows.yaml"
SCOPED_LIST="${REPO_ROOT}/e2e/tier1/winget_scoped_packages.txt"

info "Tier 1: winget packages that offer a choice of scope pin one"

[[ -f "${MAPPING_YAML}" ]] || { fail "vars/Windows.yaml is missing" "${MAPPING_YAML}"; finish "winget scope pins"; }
[[ -f "${SCOPED_LIST}" ]] || { fail "the list of winget packages that need a scope is missing" "${SCOPED_LIST}"; finish "winget scope pins"; }

# <package id> <pinned scope or nothing> <installer_type or nothing>, one per winget mapping. The
# same field order the PowerShell reader in setup/windows/WindowsSoftware.ps1 accepts, where scope
# follows source and installer_type follows scope.
declare -A pinned=() typed=()
while IFS=$'\t' read -r package scope kind; do
    [[ -z "${package}" ]] && continue
    pinned["${package}"]="${scope}"
    typed["${package}"]="${kind}"
done < <(
    sed -nE 's/^  [a-z0-9_]+: \{[[:space:]]*manager:[[:space:]]*"winget"[[:space:]]*,[[:space:]]*package:[[:space:]]*"([^"]+)"[[:space:]]*(,[[:space:]]*source:[[:space:]]*"[a-z]+"[[:space:]]*)?(,[[:space:]]*scope:[[:space:]]*"([a-z]+)"[[:space:]]*)?(,[[:space:]]*installer_type:[[:space:]]*"([a-z]+)")?.*/\1\t\4\t\6/p' "${MAPPING_YAML}" | tr -d '\r'
)

if [[ ${#pinned[@]} -eq 0 ]]; then
    fail "no winget mapping could be read out of vars/Windows.yaml, so nothing here means anything" "${MAPPING_YAML}"
    finish "winget scope pins"
fi

declare -A listed=() machine_type=()
stale=() unpinned=() wrong=() malformed=()
while read -r package scopes kind extra; do
    [[ -z "${package}" || "${package}" == \#* ]] && continue
    if [[ -z "${scopes}" || -z "${kind}" || -n "${extra}" \
          || ! "${scopes}" =~ ^(machine|none|user)(,(machine|none|user))*$ || ! "${kind}" =~ ^(-|[a-z]+)$ ]]; then
        malformed+=("${package} ${scopes} ${kind} ${extra}")
        continue
    fi
    listed["${package}"]="${scopes}"
    machine_type["${package}"]="${kind}"
    if [[ ! -v "pinned[${package}]" ]]; then
        stale+=("${package}")
    elif [[ -z "${pinned[${package}]}" ]]; then
        unpinned+=("${package} (manifest declares ${scopes})")
    elif [[ "${pinned[${package}]}" == "user" && ",${scopes}," != *",user,"* ]]; then
        wrong+=("${package} pins user but its manifest declares ${scopes}")
    elif [[ "${pinned[${package}]}" == "machine" && "${kind}" == "-" ]]; then
        wrong+=("${package} pins machine but no installer in its manifest serves a machine install")
    elif [[ ! "${pinned[${package}]}" =~ ^(machine|user)$ ]]; then
        wrong+=("${package} pins ${pinned[${package}]}, which is neither machine nor user")
    fi
done < <(tr -d '\r' <"${SCOPED_LIST}")

if [[ ${#listed[@]} -eq 0 ]]; then
    fail "winget_scoped_packages.txt lists nothing, so this check would pass over nothing" "${SCOPED_LIST}"
    finish "winget scope pins"
fi

if [[ ${#malformed[@]} -eq 0 ]]; then
    pass "every line of winget_scoped_packages.txt is a package id, a list of machine, none and user, and a machine installer type or -"
else
    fail "winget_scoped_packages.txt has lines this check cannot read" "$(printf '%s | ' "${malformed[@]}")"
fi

if [[ ${#stale[@]} -eq 0 ]]; then
    pass "every one of the ${#listed[@]} listed packages is a winget mapping in vars/Windows.yaml"
else
    fail "winget_scoped_packages.txt lists packages that no winget mapping names" "${stale[*]}"
fi

if [[ ${#unpinned[@]} -eq 0 ]]; then
    pass "every listed package pins a scope, so winget never chooses one for the elevated wizard"
else
    fail "winget packages whose manifest offers a choice of scope pin none, so winget chooses, which is how Lens, CurseForge and Bruno failed" \
         "$(printf '%s | ' "${unpinned[@]}")"
fi

if [[ ${#wrong[@]} -eq 0 ]]; then
    pass "every pinned scope is one its manifest can serve"
else
    fail "pinned scopes that the manifest does not offer, which winget answers with No applicable installer found" \
         "$(printf '%s | ' "${wrong[@]}")"
fi

undocumented=()
for package in "${!pinned[@]}"; do
    [[ -n "${pinned[${package}]}" && ! -v "listed[${package}]" ]] && undocumented+=("${package}")
done
if [[ ${#undocumented[@]} -eq 0 ]]; then
    pass "every winget mapping that pins a scope is listed in winget_scoped_packages.txt"
else
    fail "winget mappings pin a scope with no manifest evidence in winget_scoped_packages.txt" "${undocumented[*]}"
fi

untyped=() mistyped=() stray=()
for package in "${!pinned[@]}"; do
    if [[ "${pinned[${package}]}" == "machine" ]]; then
        if [[ -z "${typed[${package}]}" ]]; then
            untyped+=("${package}")
        elif [[ -v "machine_type[${package}]" && "${typed[${package}]}" != "${machine_type[${package}]}" ]]; then
            mistyped+=("${package} declares ${typed[${package}]} but winget selects ${machine_type[${package}]} for --scope machine")
        fi
    elif [[ -n "${typed[${package}]}" ]]; then
        stray+=("${package} (scope ${pinned[${package}]:-none})")
    fi
done
if [[ ${#untyped[@]} -eq 0 && ${#mistyped[@]} -eq 0 && ${#stray[@]} -eq 0 ]]; then
    pass "every machine pin declares the installer_type winget selects for it, and nothing else declares one"
else
    [[ ${#untyped[@]} -gt 0 ]] && fail "machine pins with no installer_type, so the wizard cannot tell whether winget must run elevated" "${untyped[*]}"
    [[ ${#mistyped[@]} -gt 0 ]] && fail "machine pins whose installer_type is not the one winget selects" "$(printf '%s | ' "${mistyped[@]}")"
    [[ ${#stray[@]} -gt 0 ]] && fail "installer_type on a mapping that is not pinned to machine, where nothing reads it" "${stray[*]}"
fi

finish "winget scope pins"
