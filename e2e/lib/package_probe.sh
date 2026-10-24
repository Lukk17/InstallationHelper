#!/usr/bin/env bash
#
# Shared package-name probing for tier 2. Sourced after common.sh, never executed directly.
#
# Two tier 2 checks need the same thing: ask a real package index whether a name exists, without
# installing anything. Arch, the AUR, Flathub, Homebrew, Chocolatey and winget all answer over HTTP.
# apt and dnf do not, because the answer depends on a package index that only exists on a machine of
# that distribution, so those names are resolved inside the same pinned base images the tier 3
# scenarios use.
#
# The image is read out of e2e/tier3/<distro>.Dockerfile rather than written here, so the check and
# the scenarios can never drift apart. Nothing is installed, and the container is thrown away.
#
# This started as one implementation inside resolve_role_packages.sh, covering only the names written
# directly into role tasks. The names in the vars/<OS>.yaml dictionaries needed exactly the same
# probe, and a second copy of it would have been the usual way two checks quietly stop agreeing about
# what they test, so it lives here and both call it.
#
# Names that legitimately do not resolve until the playbook adds a repository are forgiven by
# runtime_repo_packages.txt. Both callers read that one file through probe_is_forgiven, and a
# forgiveness that has become unnecessary is reported, because a stale exemption silently covers for
# a real defect later.

PROBE_TIER3_DIR="${E2E_ROOT}/tier3"
PROBE_ALLOWLIST="${E2E_ROOT}/tier2/runtime_repo_packages.txt"

# Filled in by probe_names, read by probe_report_forgiveness.
PROBE_CONTAINER_RUNS=0
PROBE_FORGIVEN_UNNEEDED=()

# package_names_for <vars-file> <manager>  ->  one package name per line
#
# Reads the software_mapping dictionary entries of one package manager out of a vars file.
package_names_for() {
    grep -E "^  [a-z0-9_]+: \{ *manager: \"$2\"" "$1" \
        | sed -E 's/.*package: "([^"]+)".*/\1/' | sort -u || true
}

# derivative_package_names_for <family-file> <derivative-file> <manager>  ->  one package name per line
#
# The names one manager installs on a derivative such as CachyOS, whose dictionary is its family's
# with the derivative's entries merged over it by setup/ansible/tasks/load_os_dict.yaml. That task
# replaces a family entry whole when the derivative maps the same key, so a family entry counts here
# only when the derivative does not name its key at all, whatever manager the derivative gives it.
derivative_package_names_for() {
    local overridden
    overridden="$(derivative_mapping_keys "$2" | tr '\n' ' ')"
    {
        grep -E "^  [a-z0-9_]+: \{ *manager: \"$3\"" "$1" \
            | awk -v skip="${overridden}" 'BEGIN { n = split(skip, k, " "); for (i = 1; i <= n; i++) s[k[i]] = 1 }
                                          { key = $1; sub(/:$/, "", key); if (!(key in s)) print }'
        derivative_mapping_lines "$2" | grep -E "\{ *manager: \"$3\""
    } | sed -E 's/.*package: "([^"]+)".*/\1/' | sort -u || true
}

# arch_group_exists <name>  ->  for a name archlinux.org knows as a package group rather than a package.
# Needs http_ask.sh, which both callers source. Read by resolve_role_packages.sh for the role tasks and
# by resolve_packages.sh for companion_packages, where Arch's gnome is a group.
#
# Returns 0 when the group exists, 1 when archlinux.org says it does not for both architectures, 2
# when either never gave a definite answer, with what came back in ARCH_GROUP_FAULT.
ARCH_GROUP_FAULT=""
# shellcheck disable=SC2034  # ARCH_GROUP_FAULT is read by both callers after a status of 2
arch_group_exists() {
    local arch url status verdict=1
    ARCH_GROUP_FAULT=""
    for arch in x86_64 any; do
        url="https://archlinux.org/groups/${arch}/$1/"
        status=0
        http_ask "${url}" 'Group Details' || status=$?
        if [[ ${status} -eq 0 ]]; then
            return 0
        fi
        if [[ ${status} -eq 2 ]]; then
            verdict=2
            ARCH_GROUP_FAULT="$(http_unresolved_reason "${url}")"
        fi
    done
    return ${verdict}
}

# probe_image_for <distro>  ->  the pinned image, or nothing when there is no Dockerfile
probe_image_for() {
    local f="${PROBE_TIER3_DIR}/$1.Dockerfile"
    [[ -f "${f}" ]] && grep -m1 '^FROM ' "${f}" | awk '{print $2}' || echo ""
}

# probe_is_forgiven <distro> <package>  ->  true when runtime_repo_packages.txt covers it
#
# Compared field by field rather than with a regular expression, because a package name is not a
# pattern. The regular expression this replaced read the name as one, so the dnf wildcard "*" turned
# into a quantifier and matched every fedora line in the file, which forgave a name nobody had
# listed. Same reasoning as the index() note in extract_role_packages.awk.
probe_is_forgiven() {
    awk -v d="$1" -v p="$2" '$1 == d && $2 == p { found = 1 } END { exit !found }' "${PROBE_ALLOWLIST}"
}

# probe_missing_in_image <image> <names>  ->  the names the image cannot resolve, one per line
#
# One container, one pass over the whole list. apt-cache policy, dnf info and pacman -Si all answer
# from the index alone, so nothing is downloaded and nothing is installed. A dnf name starting with @
# is a group rather than a package and is asked about as one. pacman is here for CachyOS, whose own
# repositories archlinux.org knows nothing about.
#
# Returns non-zero when the container did not run to the end. Without that, an image that failed to
# pull produced no output, no output read as no missing names, and the caller announced that all of
# them resolved. Silence and success have to be told apart or the check is decoration.
probe_missing_in_image() {
    local image="$1" names="$2" script out
    # The names travel inside the script and the script travels as the container's command argument,
    # so nothing is bind-mounted. A bind mount names a directory on the daemon's machine, and this
    # runs inside the gate container, where a temporary directory exists for this process alone: the
    # daemon would mount an empty directory of its own and every name would read as missing.
    script="$(
        printf 'cat > /tmp/probe-names.txt <<'"'"'PROBE_NAMES'"'"'\n%s\nPROBE_NAMES\n' "${names}"
        cat <<'PROBE'
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq >/dev/null 2>&1
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        c=$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}')
        { [ -z "$c" ] || [ "$c" = "(none)" ]; } && echo "MISSING $p"
    done < /tmp/probe-names.txt
elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy >/dev/null 2>&1
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        pacman -Si "$p" >/dev/null 2>&1 || pacman -Sg "$p" >/dev/null 2>&1 || echo "MISSING $p"
    done < /tmp/probe-names.txt
else
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        case "$p" in
            @*) dnf -q group info "${p#@}" >/dev/null 2>&1 || echo "MISSING $p" ;;
            *)  dnf -q info "$p" >/dev/null 2>&1 || echo "MISSING $p" ;;
        esac
    done < /tmp/probe-names.txt
fi
echo PROBE_COMPLETE
PROBE
    )"

    out="$(docker run --rm "${image}" sh -c "${script}" 2>/dev/null | tr -d '\r' || true)"

    grep -qx 'PROBE_COMPLETE' <<<"${out}" || return 1
    sed -n 's/^MISSING //p' <<<"${out}"
}

# probe_names <distro> <image> <label> <subject> <names> [annotate-fn]
#
# One assertion: every name that is not forgiven resolves in the pinned image.
#
#   label       what to call the check when it cannot run at all
#   subject     the phrase the pass and fail lines are built around
#   annotate-fn optional, given a missing name it prints a parenthesised note about where it came
#               from, which is what makes a role task failure actionable
#
# Forgiven names are probed too, and never counted. That is how a forgiveness is caught after it
# stops being needed, and it costs nothing because it is the same container.
probe_names() {
    local distro="$1" image="$2" label="$3" subject="$4" names="$5" annotate="${6:-}"

    if [[ -z "${image}" ]]; then
        skip "${label}" "no Dockerfile to read a pinned image from"
        return
    fi

    local checked=() forgiven=() pkg
    while IFS= read -r pkg; do
        [[ -z "${pkg}" ]] && continue
        if probe_is_forgiven "${distro}" "${pkg}"; then forgiven+=("${pkg}"); else checked+=("${pkg}"); fi
    done <<<"${names}"

    [[ ${#checked[@]} -eq 0 ]] && { skip "${label}" "none apply to this distribution"; return; }

    local missing
    if ! missing="$(probe_missing_in_image "${image}" \
        "$(printf '%s\n' "${checked[@]}" ${forgiven[@]+"${forgiven[@]}"})")"; then
        skip "${label}" "the ${image} probe container did not run to the end, so nothing was resolved"
        return
    fi
    PROBE_CONTAINER_RUNS=$((PROBE_CONTAINER_RUNS + 1))

    for pkg in ${forgiven[@]+"${forgiven[@]}"}; do
        grep -qxF -- "${pkg}" <<<"${missing}" || PROBE_FORGIVEN_UNNEEDED+=("${distro} ${pkg}")
    done

    local gone=() detail=""
    for pkg in "${checked[@]}"; do
        if grep -qxF -- "${pkg}" <<<"${missing}"; then gone+=("${pkg}"); fi
    done

    if [[ ${#gone[@]} -eq 0 ]]; then
        pass "${distro} (${image}): all ${#checked[@]} ${subject} resolve"
        return
    fi

    if [[ -n "${annotate}" ]]; then
        for pkg in "${gone[@]}"; do detail+="${pkg} $("${annotate}" "${pkg}") "; done
    else
        detail="${gone[*]}"
    fi
    fail "${distro} (${image}): ${#gone[@]} of ${#checked[@]} ${subject} do not exist" "${detail}"
}

# probe_report_forgiveness <label>
#
# One assertion: no forgiveness that applied to this run has become unnecessary. A name that now
# resolves in the base image no longer needs a line in runtime_repo_packages.txt, and leaving one
# there means the day that name is renamed nothing says so. Same reasoning as the stale entry checks
# on documented_no_ops.txt and unread_pins_allowed.txt.
probe_report_forgiveness() {
    if [[ "${PROBE_CONTAINER_RUNS}" -eq 0 ]]; then
        skip "$1" "no container probe ran, so no forgiveness was tested"
    elif [[ ${#PROBE_FORGIVEN_UNNEEDED[@]} -eq 0 ]]; then
        pass "$1"
    else
        fail "$1" "${PROBE_FORGIVEN_UNNEEDED[*]}"
    fi
}
