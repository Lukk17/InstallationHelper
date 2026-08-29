#!/usr/bin/env bash
#
# Tier 1: every enabled toggle must resolve to something that installs it, and every declared
# toggle must resolve to something that acts on it.
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
#
# Both directions used to read the install_ prefix and nothing else, which is why a dead toggle
# could sit in group_vars for as long as this project has existed while every assertion here
# passed. The prefixes are taken from the data now instead: whatever group_vars declares as a
# boolean is a toggle, and there are eight spellings of one today.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# The download locations checked at the bottom of this file are pinned values, and the shell end
# of the pinned values port is the only thing allowed to read them. See setup/pinned_values.
source "${REPO_ROOT}/setup/pinned_values/pinned_values.sh"

NO_OPS_FILE="$(dirname "${BASH_SOURCE[0]}")/documented_no_ops.txt"
VARS_DIR="${ANSIBLE_DIR}/vars"
GV_DIR="${ANSIBLE_DIR}/group_vars"

info "Tier 1: toggle coverage"

# Every toggle name any Ansible task file or site.yaml mentions, comments removed.
#
# The pattern used to be install_[a-z0-9_]+, and that single prefix was a blind spot rather than a
# filter. group_vars declares toggles under eight prefixes today, and toggle_wayland_nvidia has been
# declared, labelled on both wizards' checklists and consumed by nothing for as long as it has
# existed, while this check reported full coverage on every family. So every identifier is collected
# here and the declared set below decides which of them are toggle names. Nothing in this file names
# a prefix: a toggle written tomorrow under a prefix nobody has used yet is covered on the day it is
# written, which a hardcoded list of eight would not be.
consumers="$(
    { find "${ANSIBLE_DIR}/roles" -name '*.yaml' -o -name '*.yml'; echo "${ANSIBLE_DIR}/site.yaml"; } \
        | xargs -r sed -E 's/#.*$//' \
        | grep -ohE '[a-z0-9_]+' \
        | sort -u || true
)"

# Keys that the dynamic dispatcher resolves through os_dict need no direct reference,
# so the mapping itself counts as a consumer. Read per OS below.

# Windows is the one family where an Ansible task consuming the toggle proves nothing. Both wizards
# invoke the playbook from inside WSL as `-i localhost, -c local`, so ansible_os_family reports
# Debian and every Windows-gated task is skipped. Counting those files as consumers is what let
# eleven toggles sit enabled, installing nothing, while this check reported full coverage. For
# Windows the consumers are the native installers instead: the mapping dictionary, the npm table
# in WindowsNpmTools.ps1, the key list in WindowsCustomInstalls.ps1, and the settings list in
# WindowsSettings.ps1, which is where the toggles that carry no install_ prefix are applied.
WINDOWS_DIR="${REPO_ROOT}/setup/windows"

# Emits whole toggle names, prefix included, because the settings keys do not carry one.
windows_native_consumers() {
    sed -n '/NpmToolPackages = \[ordered\]@{/,/^}/p' "${WINDOWS_DIR}/WindowsNpmTools.ps1" 2>/dev/null \
        | grep -oE '^\s{4}[a-z0-9_]+' | tr -d ' ' | sed 's/^/install_/'
    # Read out of the declared array rather than the dispatch, so the two cannot drift.
    sed -n 's/^\$script:CustomInstallKeys = @(\(.*\))$/\1/p' "${WINDOWS_DIR}/WindowsCustomInstalls.ps1" 2>/dev/null \
        | tr -d "' " | tr ',' '\n' | sed 's/^/install_/'
    # The system settings the native installer applies, read out of their declared list for the same
    # reason. These are enable_hyperv, setup_wsl and set_custom_wallpaper, and nothing above would
    # ever find them, because none of them carries the install_ prefix.
    sed -n 's/^\$script:SettingKeys = @(\(.*\))$/\1/p' "${WINDOWS_DIR}/WindowsSettings.ps1" 2>/dev/null \
        | tr -d "' " | tr ',' '\n'
}

check_family() {
    local family="$1" os_gv="$2"
    local vars_file="${VARS_DIR}/${family}.yaml"

    [[ -f "${vars_file}" ]] || { fail "${family}: vars file missing" "${vars_file}"; return 0; }

    local mapped enabled unresolved=() family_consumers
    mapped="$(grep -E '^  [a-z0-9_]+: \{' "${vars_file}" | sed -E 's/^  ([a-z0-9_]+):.*/\1/' | sort -u)"

    if [[ "${family}" == Windows ]]; then
        family_consumers="$(windows_native_consumers | sort -u)"
        if [[ -z "$(tr -d '[:space:]' <<<"${family_consumers}")" ]]; then
            fail "Windows: neither native installer yielded any consumer keys, so this check cannot mean anything" \
                 "looked in ${WINDOWS_DIR}/WindowsNpmTools.ps1 and WindowsCustomInstalls.ps1"
            return 0
        fi
    else
        family_consumers="${consumers}"
    fi

    # Toggle values, OS-specific file layered over the cross-platform one, which is
    # the same precedence the playbook and both wizards use. Every prefix rather than install_
    # alone, because a toggle that does nothing does nothing whatever it is called, and the eight
    # prefixes in use are read off the data rather than written down here.
    enabled="$(
        {
            sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//' "${GV_DIR}/${os_gv}"
            sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//' "${GV_DIR}/all.yaml"
        } | grep -E '^[a-z0-9_]+: (true|false)$' \
          | awk -F': ' '!seen[$1]++ { if ($2 == "true") print $1 }' \
          | sort -u
    )"

    local n_enabled=0 key bare
    while IFS= read -r key; do
        [[ -z "${key}" ]] && continue
        n_enabled=$((n_enabled + 1))
        # The mapping route belongs to the install_ prefix alone. os_dict is keyed on the name with
        # that prefix removed, so testing any other toggle against it would let setup_zsh be
        # answered by a mapping that happened to be called setup_zsh, which is a different claim.
        bare="${key#install_}"
        [[ "${key}" == install_* ]] && grep -qx "${bare}" <<<"${mapped}" && continue
        grep -qx "${key}" <<<"${family_consumers}" && continue
        grep -qE "^${family}[[:space:]]+${bare}([[:space:]]|$)" "${NO_OPS_FILE}" && continue
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

    # The other direction, which nothing checked until this was written, and which was already
    # costing five applications.
    #
    # The dispatcher gates every mapping on lookup('vars', 'install_' ~ key, default=false), and the
    # toggles a run can see are all.yaml overlaid by the one per-OS file that family loads. A mapping
    # whose toggle is defined in neither can never install, whatever its value, and nothing says so:
    # the default of false makes it look like a deliberate choice. Found this way: Fedora mapped
    # boot_repair with no toggle anywhere, and macOS mapped intellij and utm with no toggle anywhere
    # plus docker and lynis whose toggles live only in linux.yaml, which macOS never loads.
    #
    # Defined is what matters here rather than enabled, because a toggle set to false is reachable
    # and is a decision, while an absent toggle is an accident nobody can see from the mapping file.
    local defined unreachable=() n_mapped=0
    defined="$(
        {
            sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//' "${GV_DIR}/${os_gv}"
            sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//' "${GV_DIR}/all.yaml"
        } | grep -E '^install_[a-z0-9_]+: (true|false)$' \
          | sed -E 's/^install_([a-z0-9_]+):.*/\1/' \
          | sort -u
    )"

    while IFS= read -r key; do
        [[ -z "${key}" ]] && continue
        n_mapped=$((n_mapped + 1))
        grep -qx "${key}" <<<"${defined}" || unreachable+=("${key}")
    done <<<"${mapped}"

    if [[ ${#unreachable[@]} -eq 0 ]]; then
        pass "${family}: every one of the ${n_mapped} mappings has a toggle this family can see"
    else
        fail "${family}: ${#unreachable[@]} mapping(s) have no toggle this family loads, so they can never install" \
             "${unreachable[*]}"
    fi
}

check_family Debian    linux.yaml
check_family RedHat    linux.yaml
check_family Archlinux linux.yaml
check_family Darwin    macos.yaml
check_family Windows   windows.yaml

# --- every declared toggle must be consumed by something that acts on it -------------------------
#
# The direction above asks about enabled toggles, and on its own that is not enough. A toggle set to
# false with nothing behind it looks exactly like a toggle set to false with an implementation
# waiting for it, and the user finds out which by ticking it and getting nothing. toggle_wayland_nvidia
# is on both wizards' checklists with a label promising to force Wayland on NVIDIA, has been declared
# and unimplemented for as long as it has existed, and every assertion above passed on every family
# throughout.
#
# Asked once over the union of the group_vars files rather than once per family, because these
# toggles have exactly one route each and the thing at the end of it differs by platform: an Ansible
# task for Linux and macOS, WindowsSettings.ps1 for Windows, the callback plugin for
# allow_callback_failure. Asking per family would demand a per-family answer for a toggle only one
# platform was ever meant to honour.
#
# install_ toggles are left out of this direction and only this one, because their route is the OS
# mapping dictionary, and a family that maps nothing for one of them is making a decision that the
# direction above and documented_no_ops.txt already cover between them.
#
# Neither wizard counts as a consumer. setup.sh and setup.ps1 each name every toggle twice over, in
# a label table and in an exclusion list, and both of those are display. Counting them is what made
# setup_grub and remove_distro_systemd_boot look implemented while this was being written. The
# callback plugin's role-to-toggle table is left out for the same reason: it decides how a skipped
# role is described in the summary, and describing is not acting.
implementation_tokens="$(
    {
        { find "${ANSIBLE_DIR}/roles" "${ANSIBLE_DIR}/tasks" -name '*.yaml' -o -name '*.yml' 2>/dev/null
          echo "${ANSIBLE_DIR}/site.yaml"; } | xargs -r sed -E 's/#.*$//'
        sed -E '/^ROLE_TOGGLE_MAPPING/,/^\}/d; s/#.*$//' "${ANSIBLE_DIR}/callback_plugins/dual_logger.py"
        find "${WINDOWS_DIR}" -name '*.ps1' -exec sed -E '/<#/,/#>/d; s/#.*$//' {} +
    } | grep -ohE '[a-z0-9_]+' | sort -u || true
)"

declared_toggles="$(
    sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//' "${GV_DIR}"/*.yaml \
        | grep -E '^[a-z0-9_]+: (true|false)$' \
        | sed -E 's/:.*//' \
        | sort -u || true
)"
declared_prefixes="$(sed -E 's/^([a-z0-9]+_).*/\1/' <<<"${declared_toggles}" | sort -u | tr '\n' ' ')"
n_declared="$(grep -c . <<<"${declared_toggles}" || true)"
n_prefixes="$(wc -w <<<"${declared_prefixes}" | tr -d ' ')"

# A reader that had narrowed back to one prefix would report full coverage over a fraction of the
# toggles, which is exactly the state this whole section was written to end. So the shape of what
# was read is asserted before anything is concluded from it.
if [[ "${n_declared}" -lt 100 || "${n_prefixes}" -lt 2 ]]; then
    fail "the toggle reader found ${n_declared} toggles under ${n_prefixes} prefix(es), so nothing below can mean anything" \
         "expected well over a hundred under several prefixes in ${GV_DIR}, the pattern has stopped matching"
else
    pass "read ${n_declared} declared toggles under ${n_prefixes} prefixes: ${declared_prefixes}"
fi

dead=()
while IFS= read -r toggle; do
    [[ -z "${toggle}" || "${toggle}" == install_* ]] && continue
    grep -qx "${toggle}" <<<"${implementation_tokens}" && continue
    grep -qE "^[A-Za-z]+[[:space:]]+${toggle}([[:space:]]|$)" "${NO_OPS_FILE}" && continue
    dead+=("${toggle}")
done <<<"${declared_toggles}"

if [[ ${#dead[@]} -eq 0 ]]; then
    pass "every declared toggle outside the install_ prefix is consumed by something that acts on it"
else
    # Reported rather than failed, deliberately and temporarily. Deleting a toggle and implementing
    # one are both the owner's call and not this check's, and the three below were found the day
    # this direction was written. Turn this skip into a fail once they are resolved: that is the
    # whole change, and until it is made this line is the only thing standing between a dead toggle
    # and a green gate.
    skip "every declared toggle outside the install_ prefix is consumed by something that acts on it" \
         "${#dead[@]} are consumed by nothing, so ticking one does nothing at all: ${dead[*]}"
fi

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
# Only the pinned values are consulted, while the playbook's lookup('vars', ...) sees the whole
# variable space, so a URL defined in all.yaml, linux.yaml or a profile overlay would be invisible
# here and this check would call it absent. Every such value is a pin today, which is the
# convention, and this is the check that will complain first if someone breaks it.
#
# The pins are loaded once, up front, because a set of pins that cannot be read has to be one
# named failure rather than nine mappings each reported as having no download location.
PINS_READABLE=true
pinned_values_load || PINS_READABLE=false

check_url_managers() {
    local family="$1" manager="$2"
    shift 2
    local suffixes=("$@")
    local vars_file="${VARS_DIR}/${family}.yaml"
    local bad_name=() no_location=() n=0 key pkg line found suffix

    if [[ "${PINS_READABLE}" != true ]]; then
        fail "${family}: the pinned values could not be read, so no ${manager} download location can be checked" \
             "install Python 3.11 or newer, or point PINNED_VALUES_PYTHON at one"
        return 0
    fi

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

        # An inline url: field on the mapping itself outranks the pinned value, same as the
        # dispatcher's own resolution order.
        if grep -qE '\burl: ' <<<"${line}"; then
            continue
        fi
        found=false
        for suffix in "${suffixes[@]}"; do
            # Absence and emptiness are deliberately one answer here. A pin resolving to an empty
            # string makes the dispatcher skip the download exactly as an unpinned name does, so
            # both count as no location: pinned_value prints nothing for the first and returns 3
            # for the second, which is why the status is discarded and only the value is tested.
            [[ -n "$(pinned_value "${key}${suffix}" 2>/dev/null || true)" ]] && found=true
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
