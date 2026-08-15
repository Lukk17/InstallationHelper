#!/usr/bin/env bash
#
# Tier 1: every enabled toggle must resolve to something that installs it.
#
# A toggle set to true with no mapping in vars/<OS>.yaml and no task consuming it is
# the worst kind of bug this project produces: the user asks for software, the run
# reports success, and the software is not there. It has shipped twice, with putty
# missing on Arch and Fedora, and with gradle on Debian and Fedora where a comment
# claimed SDKMAN handled it and nothing did. See docs/regression_ledger.md.
#
# Comments are stripped before searching for consumers, precisely because the gradle
# case was a comment promising an implementation that did not exist.
#
# Intended no-ops live in documented_no_ops.txt with a reason. Anything not listed
# there is treated as a defect.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

NO_OPS_FILE="$(dirname "${BASH_SOURCE[0]}")/documented_no_ops.txt"
VARS_DIR="${ANSIBLE_DIR}/vars"
GV_DIR="${ANSIBLE_DIR}/group_vars"

info "Tier 1: toggle coverage"

# Every install_ toggle referenced by any task file or by site.yaml, comments removed.
consumers="$(
    { find "${ANSIBLE_DIR}/roles" -name '*.yaml' -o -name '*.yml'; echo "${ANSIBLE_DIR}/site.yaml"; } \
        | xargs -r sed -E 's/#.*$//' \
        | grep -ohE 'install_[a-z0-9_]+' \
        | sort -u || true
)"

# Keys that the dynamic dispatcher resolves through os_dict need no direct reference,
# so the mapping itself counts as a consumer. Read per OS below.

# Windows is the one family where an Ansible task consuming the toggle proves nothing. Both wizards
# invoke the playbook from inside WSL as `-i localhost, -c local`, so ansible_os_family reports
# Debian and every Windows-gated task is skipped. Counting those files as consumers is what let
# eleven toggles sit enabled, installing nothing, while this check reported full coverage. For
# Windows the consumers are the three native installers instead: the mapping dictionary, the npm
# table in WindowsNpmTools.ps1, and the key list in WindowsCustomInstalls.ps1.
WINDOWS_DIR="${REPO_ROOT}/setup/windows"

windows_native_consumers() {
    sed -n '/NpmToolPackages = \[ordered\]@{/,/^}/p' "${WINDOWS_DIR}/WindowsNpmTools.ps1" 2>/dev/null \
        | grep -oE '^\s{4}[a-z_]+' | tr -d ' '
    # Read out of the declared array rather than the dispatch, so the two cannot drift.
    sed -n "s/^\\\$script:CustomInstallKeys = @(\(.*\))$/\1/p" "${WINDOWS_DIR}/WindowsCustomInstalls.ps1" 2>/dev/null \
        | tr -d "' " | tr ',' '\n'
}

check_family() {
    local family="$1" os_gv="$2"
    local vars_file="${VARS_DIR}/${family}.yaml"

    [[ -f "${vars_file}" ]] || { fail "${family}: vars file missing" "${vars_file}"; return 0; }

    local mapped enabled unresolved=() family_consumers
    mapped="$(grep -E '^  [a-z0-9_]+: \{' "${vars_file}" | sed -E 's/^  ([a-z0-9_]+):.*/\1/' | sort -u)"

    if [[ "${family}" == Windows ]]; then
        family_consumers="$(windows_native_consumers | sed 's/^/install_/' | sort -u)"
        if [[ -z "$(tr -d '[:space:]' <<<"${family_consumers}")" ]]; then
            fail "Windows: neither native installer yielded any consumer keys, so this check cannot mean anything" \
                 "looked in ${WINDOWS_DIR}/WindowsNpmTools.ps1 and WindowsCustomInstalls.ps1"
            return 0
        fi
    else
        family_consumers="${consumers}"
    fi

    # Toggle values, OS-specific file layered over the cross-platform one, which is
    # the same precedence the playbook and both wizards use.
    enabled="$(
        {
            sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//' "${GV_DIR}/${os_gv}"
            sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//' "${GV_DIR}/all.yaml"
        } | grep -E '^install_[a-z0-9_]+: (true|false)$' \
          | awk -F': ' '!seen[$1]++ { if ($2 == "true") print substr($1, 9) }' \
          | sort -u
    )"

    local n_enabled=0
    while IFS= read -r key; do
        [[ -z "${key}" ]] && continue
        n_enabled=$((n_enabled + 1))
        grep -qx "${key}" <<<"${mapped}" && continue
        grep -qx "install_${key}" <<<"${family_consumers}" && continue
        grep -qE "^${family}[[:space:]]+${key}([[:space:]]|$)" "${NO_OPS_FILE}" && continue
        unresolved+=("${key}")
    done <<<"${enabled}"

    if [[ ${#unresolved[@]} -eq 0 ]]; then
        if [[ "${family}" == Windows ]]; then
            pass "${family}: all ${n_enabled} enabled toggles resolve to a mapping or a native installer"
        else
            pass "${family}: all ${n_enabled} enabled toggles resolve to a mapping or a task"
        fi
    else
        fail "${family}: ${#unresolved[@]} enabled toggles install nothing and are not documented as no-ops" \
             "${unresolved[*]}"
    fi
}

check_family Debian    linux.yaml
check_family RedHat    linux.yaml
check_family Archlinux linux.yaml
check_family Darwin    macos.yaml
check_family Windows   windows.yaml

# A stale entry in the no-op file is its own hazard: it silently forgives a toggle
# that has since gained a real mapping, so a later break in that mapping looks
# intentional. Flag them so the list stays honest.
stale=()
while read -r family key _; do
    [[ -z "${family}" || "${family}" == \#* ]] && continue
    vf="${VARS_DIR}/${family}.yaml"
    [[ -f "${vf}" ]] || continue
    if grep -qE "^  ${key}: \{" "${vf}"; then
        stale+=("${family}/${key}")
    fi
done < <(grep -vE '^\s*(#|$)' "${NO_OPS_FILE}")

if [[ ${#stale[@]} -eq 0 ]]; then
    pass "documented_no_ops.txt has no stale entries"
else
    fail "documented_no_ops.txt forgives toggles that now have a real mapping" "${stale[*]}"
fi

finish "toggle coverage"
