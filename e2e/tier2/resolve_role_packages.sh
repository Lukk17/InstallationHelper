#!/usr/bin/env bash
#
# Tier 2: package names hardcoded inside role task files must exist, on every distribution that
# actually runs them.
#
# resolve_packages.sh checks the vars/<OS>.yaml dictionaries, which is where most package names
# live. It does not see names written directly into a task, and those go stale just as readily. Five
# real defects came from exactly there:
#
#   plasma-framework5      Plasma 5 name in kde_plasma_setup, gone from Arch. Nothing caught it
#                          until a container run had spent fifty minutes reaching that task.
#   iptables-nft           Gone from Arch after it consolidated iptables to the nftables build. It
#                          was itself an earlier Arch fix, so the fix had rotted.
#   libkdecorations2-dev   Plasma 5 name, absent from Debian and Ubuntu alike.
#   libncursesw5-dev       Gone from both, replaced by libncurses-dev.
#   zlib-devel             Fedora moved to zlib-ng, so 44 has no zlib-devel.
#
# Arch resolves over HTTP with no container. apt and dnf need a package index, so those run inside
# the same pinned base images the tier 3 scenarios use, read out of the Dockerfiles so the check and
# the scenarios can never drift apart. Nothing is installed anywhere.
#
# Two things this has to get right or it becomes noise, and both were learned by getting them wrong:
#
#   when gating   A task restricted to Ubuntu must not be checked against Debian. The first version
#                 ignored when clauses and reported Ubuntu-only language packs as missing on Debian,
#                 which is a false alarm, and a check that cries wolf gets ignored.
#   added repos   Some names legitimately do not exist until the playbook adds a repository. Those
#                 are listed with the reason in runtime_repo_packages.txt, and anything not listed
#                 is treated as a defect.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd curl awk
TIER2_DIR="$(dirname "${BASH_SOURCE[0]}")"
ROLES_DIR="${ANSIBLE_DIR}/roles"
TIER3_DIR="${E2E_ROOT}/tier3"
EXTRACTOR="${TIER2_DIR}/extract_role_packages.awk"
ALLOWLIST="${TIER2_DIR}/runtime_repo_packages.txt"

info "Tier 2: package names embedded in role tasks"

# extract <module> -> lines of "<applies>\t<file>\t<package>"
extract() {
    local module="$1" files
    files=$(grep -rl "${module}" "${ROLES_DIR}" 2>/dev/null) || return 0
    [[ -z "${files}" ]] && return 0
    # shellcheck disable=SC2086
    awk -v mod="${module}" -f "${EXTRACTOR}" ${files} 2>/dev/null | sort -u
}

# Names for one distro, excluding templated entries and anything the allow-list forgives.
names_for() {
    local distro="$1"; shift
    local line applies pkg
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        applies="${line%%$'\t'*}"
        pkg="${line##*$'\t'}"
        [[ ",${applies}," == *",${distro},"* ]] || continue
        [[ "${pkg}" == *'{{'* ]] && continue
        grep -qE "^${distro}[[:space:]]+${pkg}([[:space:]]|$)" "${ALLOWLIST}" 2>/dev/null && continue
        printf '%s\n' "${pkg}"
    done <<<"$1" | sort -u
}

report_templated() {
    local label="$1" body="$2" n
    n="$(grep -c '{{' <<<"${body}" || true)"
    [[ "${n}" -gt 0 ]] && warn "${label}: ${n} templated name(s) not checked, they cannot be resolved without rendering"
    return 0
}

image_for() {
    local f="${TIER3_DIR}/$1.Dockerfile"
    [[ -f "${f}" ]] && grep -m1 '^FROM ' "${f}" | awk '{print $2}' || echo ""
}

where_is() {
    local pkg="$1" body="$2"
    grep -F -- "	${pkg}" <<<"${body}" | head -1 | awk -F'\t' '{n=split($2,p,"/"); print p[n]}'
}

# --- Arch, over HTTP ---------------------------------------------------------
arch_group_exists() {
    local arch
    for arch in x86_64 any; do
        curl -s --max-time 20 "https://archlinux.org/groups/${arch}/$1/" | grep -q 'Group Details' && return 0
    done
    return 1
}

check_arch() {
    local body; body="$(extract 'community.general.pacman:')"
    report_templated "Arch" "${body}"
    local list; list="$(names_for arch "${body}")"
    # The extractor labels pacman tasks debian,ubuntu by default since it keys off the module family,
    # so accept every non-templated pacman name here regardless of that label.
    list="$(grep -v '{{' <<<"${body}" | awk -F'\t' '{print $3}' | sort -u)"
    [[ -z "${list}" ]] && { skip "Arch role package names" "none found"; return; }

    local missing=() groups=() pkg ok attempt n=0
    while IFS= read -r pkg; do
        [[ -z "${pkg}" ]] && continue
        n=$((n + 1)); ok=false
        for attempt in 1 2 3; do
            curl -s --max-time 20 "https://archlinux.org/packages/search/json/?name=${pkg}" | grep -q '"pkgname"' && { ok=true; break; }
            sleep $((attempt * 2))
        done
        if [[ "${ok}" == false ]]; then
            if arch_group_exists "${pkg}"; then groups+=("${pkg}"); else missing+=("${pkg} (in $(where_is "${pkg}" "${body}"))"); fi
        fi
    done <<<"${list}"

    [[ ${#groups[@]} -gt 0 ]] && dim "Arch: resolved as package groups: ${groups[*]}"
    if [[ ${#missing[@]} -eq 0 ]]; then
        pass "Arch: all ${n} literal pacman names in role tasks resolve"
    else
        fail "Arch: ${#missing[@]} of ${n} literal pacman names do not exist" "${missing[*]}"
    fi
}

# --- apt and dnf, inside the pinned base image ------------------------------
check_in_container() {
    local distro="$1" image="$2" kind="$3" body="$4"
    if [[ -z "${image}" ]]; then
        skip "${distro} role package names" "no Dockerfile to read a pinned image from"
        return
    fi
    local list; list="$(names_for "${distro}" "${body}")"
    [[ -z "${list}" ]] && { skip "${distro} role package names" "none apply to this distribution"; return; }

    local work; work="$(mktemp -d)"
    printf '%s\n' "${list}" > "${work}/names.txt"
    cat > "${work}/probe.sh" <<'PROBE'
#!/bin/sh
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq >/dev/null 2>&1
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        c=$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}')
        { [ -z "$c" ] || [ "$c" = "(none)" ]; } && echo "MISSING $p"
    done < /probe/names.txt
else
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        case "$p" in
            @*) dnf -q group info "${p#@}" >/dev/null 2>&1 || echo "MISSING $p" ;;
            *)  dnf -q info "$p" >/dev/null 2>&1 || echo "MISSING $p" ;;
        esac
    done < /probe/names.txt
fi
PROBE

    local out
    out="$(docker run --rm -v "${work}:/probe" "${image}" sh /probe/probe.sh 2>/dev/null | tr -d '\r' | sed -n 's/^MISSING //p' || true)"
    rm -rf "${work}"

    local n_total n_missing detail="" pkg
    n_total="$(grep -c . <<<"${list}" || true)"
    n_missing="$(grep -c . <<<"${out}" || true)"

    if [[ "${n_missing}" -eq 0 ]]; then
        pass "${distro} (${image}): all ${n_total} literal ${kind} names in role tasks resolve"
    else
        while IFS= read -r pkg; do
            [[ -z "${pkg}" ]] && continue
            detail+="${pkg} (in $(where_is "${pkg}" "${body}")) "
        done <<<"${out}"
        fail "${distro} (${image}): ${n_missing} of ${n_total} literal ${kind} names do not exist" "${detail}"
    fi
}

check_arch

if docker info &>/dev/null; then
    apt_body="$(extract 'ansible.builtin.apt:')"
    report_templated "Debian family" "${apt_body}"
    check_in_container debian "$(image_for debian)" apt "${apt_body}"
    check_in_container ubuntu "$(image_for ubuntu)" apt "${apt_body}"

    dnf_body="$(extract 'ansible.builtin.dnf:')"
    report_templated "Fedora" "${dnf_body}"
    check_in_container fedora "$(image_for fedora)" dnf "${dnf_body}"
else
    skip "apt and dnf role package names" "no reachable Docker daemon, so the package indexes cannot be queried"
fi

finish "role package names"
