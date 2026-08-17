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
        | grep -oE '^\s{4}[a-z0-9_]+' | tr -d ' '
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

# A mapping resolving to a package manager is not the end of it for apt_url and dnf_url, which
# install a vendor file instead of a repository package. Both dispatch tasks in dynamic_install.yaml
# are guarded by `when: item_url | length > 0`, so a download location that renders empty skips the
# download and the install and prints nothing at all. Nine mappings sit on that path, and until now
# no tier looked at them: tier 2 resolves names against repository indexes these packages are not
# in, and tier 3 excluded both managers from its expected set.
#
# The package name is checked too, because verification looks the installed package up by it. These
# entries used to hold a filename such as minikube_latest_amd64.deb, which no package database ever
# reports, and which had rotted out of step with the real filename anyway, since the pinned version
# has been 1.38.1-0 for some time. The values now in the files were measured with
# `dpkg-deb -f <file> Package` and `rpm -qp --qf '%{NAME}'` against the real vendor artifacts.
#
# The accepted variable names differ per family on purpose: the apt path reads only <key>_url, so
# accepting <key>_rpm_url for Debian would report a location the playbook never looks at.
#
# Only group_vars/versions.yaml is searched, while the playbook's lookup('vars', ...) sees the whole
# variable space, so a URL defined in all.yaml, linux.yaml or a profile overlay would be invisible
# here and this check would call it absent. Every such variable lives in versions.yaml today, which
# is the convention, and this is the check that will complain first if someone breaks it.
check_url_managers() {
    local family="$1" manager="$2"
    shift 2
    local suffixes=("$@")
    local vars_file="${VARS_DIR}/${family}.yaml"
    local versions="${GV_DIR}/versions.yaml"
    local bad_name=() no_location=() n=0 key pkg line found suffix

    while IFS= read -r line; do
        n=$((n + 1))
        key="$(sed -E 's/^  ([a-z0-9_]+):.*/\1/' <<<"${line}")"

        # The sed leaves the line untouched when there is no package field, and an unchanged mapping
        # line is neither empty nor filename-shaped, so it would have sailed through the name check
        # below. Absence is checked first for that reason.
        if ! grep -q 'package: "' <<<"${line}"; then
            bad_name+=("${key} -> no package field")
            continue
        fi
        pkg="$(sed -E 's/.*package: "([^"]*)".*/\1/' <<<"${line}")"

        if [[ -z "${pkg}" || "${pkg}" =~ \.(deb|rpm)$ || "${pkg}" =~ (http|\{\{) ]]; then
            bad_name+=("${key} -> '${pkg}'")
        fi

        # An inline url: field on the mapping itself outranks the versions file, same as the
        # dispatcher's own resolution order.
        if grep -qE '\burl: ' <<<"${line}"; then
            continue
        fi
        found=false
        for suffix in "${suffixes[@]}"; do
            grep -qE "^${key}${suffix}:[[:space:]]*\"?[^\"[:space:]]" "${versions}" && found=true
        done
        [[ "${found}" == false ]] && no_location+=("${key}")

    # manager is matched anywhere in the mapping rather than as the first field, because field order
    # inside a flow mapping carries no meaning to YAML and all nine entries happening to be written
    # manager-first today is a coincidence this check should not depend on. An entry written the other
    # way round would have been skipped in silence, and the zero-entries guard below only fires when
    # every single one is missed.
    done < <(grep -E "^  [a-z0-9_]+: \{.*manager: \"${manager}\"" "${vars_file}")

    if [[ "${n}" -eq 0 ]]; then
        fail "${family}: no ${manager} mappings found, so this check cannot mean anything" \
             "expected entries in ${vars_file}, the grep pattern or the file layout has changed"
        return 0
    fi

    if [[ ${#no_location[@]} -eq 0 ]]; then
        pass "${family}: all ${n} ${manager} mappings have a download location"
    else
        fail "${family}: ${#no_location[@]} of ${n} ${manager} mappings have no download location, so they install nothing silently" \
             "${no_location[*]}"
    fi

    if [[ ${#bad_name[@]} -eq 0 ]]; then
        pass "${family}: all ${n} ${manager} mappings name the package the way the package database will"
    else
        fail "${family}: ${#bad_name[@]} of ${n} ${manager} mappings hold a filename or URL where the installed package name belongs" \
             "${bad_name[*]}"
    fi
}

check_url_managers Debian apt_url _url
check_url_managers RedHat dnf_url _rpm_url _url

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
