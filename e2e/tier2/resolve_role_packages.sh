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
# the scenarios can never drift apart. Nothing is installed anywhere. That container probe lives in
# lib/package_probe.sh, because resolve_packages.sh resolves the dictionary names exactly the same
# way and two copies of it would be two checks that quietly stop agreeing about what they test.
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
source "$(dirname "${BASH_SOURCE[0]}")/../lib/package_probe.sh"

require_cmd curl awk
TIER2_DIR="$(dirname "${BASH_SOURCE[0]}")"
ROLES_DIR="${ANSIBLE_DIR}/roles"
VARS_DIR="${ANSIBLE_DIR}/vars"
EXTRACTOR="${TIER2_DIR}/extract_role_packages.awk"
ALLOWLIST="${PROBE_ALLOWLIST}"

info "Tier 2: package names embedded in role tasks"

# extract <module> -> lines of "<applies>\t<file>\t<package>"
extract() {
    local module="$1" files
    files=$(grep -rl "${module}" "${ROLES_DIR}" 2>/dev/null) || return 0
    [[ -z "${files}" ]] && return 0
    # shellcheck disable=SC2086
    awk -v mod="${module}" -f "${EXTRACTOR}" ${files} 2>/dev/null | sort -u
}

# Names for one distro, excluding templated entries. Forgiveness is applied by the probe rather than
# here, because the probe asks about the forgiven names too. That is the only way to notice a
# forgiveness that has stopped being needed, and the forgiven names are never counted.
names_for() {
    local distro="$1"; shift
    local line applies pkg
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        applies="${line%%$'\t'*}"
        pkg="${line##*$'\t'}"
        [[ ",${applies}," == *",${distro},"* ]] || continue
        [[ "${pkg}" == *'{{'* ]] && continue
        # A bare asterisk is dnf's every-installed-package wildcard in the full upgrade task, not a
        # package name, so there is nothing to resolve.
        [[ "${pkg}" == '*' ]] && continue
        printf '%s\n' "${pkg}"
    done <<<"$1" | sort -u
}

report_templated() {
    local label="$1" body="$2" n
    n="$(grep -c '{{' <<<"${body}" || true)"
    [[ "${n}" -gt 0 ]] && warn "${label}: ${n} templated name(s) not checked, they cannot be resolved without rendering"
    return 0
}

where_is() {
    local pkg="$1" body="$2"
    grep -F -- "	${pkg}" <<<"${body}" | head -1 | awk -F'\t' '{n=split($2,p,"/"); print p[n]}'
}

# Called back by the probe for every missing name, so a failure says which task file to open.
ROLE_BODY=""
role_annotate() { printf '(in %s)' "$(where_is "$1" "${ROLE_BODY}")"; }

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
    local distro="$1" image="$2" kind="$3"
    ROLE_BODY="$4"
    probe_names "${distro}" "${image}" "${distro} role package names" \
        "literal ${kind} names in role tasks" "$(names_for "${distro}" "${ROLE_BODY}")" role_annotate
}

# --- an exemption nobody needs any more is its own hazard --------------------
# A line in runtime_repo_packages.txt naming a package that nothing installs is a leftover, and it
# will happily forgive that name again the day someone reintroduces it with a typo. Only two things
# can ask for a package name, a role task and a vars dictionary, so both are consulted here. The
# other half of the staleness question, whether the name resolves without its repository after all,
# is answered by probe_report_forgiveness once the container has spoken.
check_allowlist_orphans() {
    local apt_body="$1" dnf_body="$2" requested stale=() distro pkg rest
    requested="$(
        {
            names_for debian "${apt_body}" | sed 's/^/debian /'
            names_for ubuntu "${apt_body}" | sed 's/^/ubuntu /'
            names_for fedora "${dnf_body}" | sed 's/^/fedora /'
            package_names_for "${VARS_DIR}/Debian.yaml" apt | sed 's/^/debian /'
            package_names_for "${VARS_DIR}/Debian.yaml" apt | sed 's/^/ubuntu /'
            package_names_for "${VARS_DIR}/RedHat.yaml" dnf | sed 's/^/fedora /'
        } | sort -u
    )"

    while read -r distro pkg rest; do
        [[ -z "${distro}" || "${distro}" == \#* ]] && continue
        grep -qxF "${distro} ${pkg}" <<<"${requested}" || stale+=("${distro} ${pkg}")
    done < "${ALLOWLIST}"

    if [[ ${#stale[@]} -eq 0 ]]; then
        pass "every entry in runtime_repo_packages.txt is still asked for by a role task or a dictionary"
    else
        fail "${#stale[@]} entry(ies) in runtime_repo_packages.txt forgive a name nothing installs any more" "${stale[*]}"
    fi
}

check_arch

apt_body="$(extract 'ansible.builtin.apt:')"
dnf_body="$(extract 'ansible.builtin.dnf:')"

check_allowlist_orphans "${apt_body}" "${dnf_body}"

if docker info &>/dev/null; then
    report_templated "Debian family" "${apt_body}"
    check_in_container debian "$(probe_image_for debian)" apt "${apt_body}"
    check_in_container ubuntu "$(probe_image_for ubuntu)" apt "${apt_body}"

    report_templated "Fedora" "${dnf_body}"
    check_in_container fedora "$(probe_image_for fedora)" dnf "${dnf_body}"
else
    skip "apt and dnf role package names" "no reachable Docker daemon, so the package indexes cannot be queried"
fi

probe_report_forgiveness "no role-task forgiveness in runtime_repo_packages.txt has become unnecessary"

finish "role package names"
