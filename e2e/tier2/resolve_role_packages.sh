#!/usr/bin/env bash
#
# Tier 2: package names hardcoded inside role task files must exist too.
#
# resolve_packages.sh checks the vars/<OS>.yaml dictionaries, which is where most package names
# live. It does not see names written directly into a task, and those are just as capable of going
# stale. plasma-framework5 is the proof: it was the Plasma 5 name, it sat in a pacman list inside
# kde_plasma_setup, it stopped existing, and nothing caught it until a container run had spent
# fifty minutes getting to that task and died on it. This check would have found it in about a
# minute. See docs/regression_ledger.md.
#
# Arch only for now, matching the distribution the harness actually exercises. The extraction is
# per package manager, so adding apt and dnf is a matter of pointing the same parser at
# ansible.builtin.apt and ansible.builtin.dnf blocks once those containers are in use. Stated
# rather than left implicit, because a check that silently covers one third of the input is the
# kind of half-measure this suite exists to remove.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd curl

ROLES_DIR="${ANSIBLE_DIR}/roles"

info "Tier 2: package names embedded in role tasks (Arch)"
warn "apt and dnf embedded lists are not checked yet, only pacman. Tier 3 covers them by installing."

# Extracts the literal package names from every community.general.pacman block. Walks from the
# module line to the first key that ends the name list, so a following `state:` or `when:` stops
# it. Templated entries are skipped rather than guessed at, and reported, because a name built
# from a variable cannot be resolved without rendering it.
mapfile -t found < <(
    awk '
        # Reset at every task boundary and at every other module key. Without this the parser
        # leaked out of a pacman task that has no name list at all, such as a full system
        # upgrade, and kept collecting until it hit the name of an unrelated task in a different
        # module. That is how it reported "*" as a missing Arch package, having wandered into a
        # dnf full upgrade three tasks later.
        /^-[[:space:]]/ { inmod = 0; inname = 0 }
        /^[[:space:]]*(ansible\.builtin\.|ansible\.windows\.|community\.(docker|windows)\.|chocolatey\.|kewlfft\.)/ { inmod = 0; inname = 0 }

        /community\.general\.pacman:/ { inmod = 1; inname = 0; next }

        # A one-line name, as in `name: flatpak`.
        inmod && /^[[:space:]]*name:[[:space:]]*[^[:space:]]/ {
            line = $0
            sub(/^[[:space:]]*name:[[:space:]]*/, "", line)
            gsub(/"|'"'"'/, "", line)
            print FILENAME "\t" line
            inmod = 0; next
        }
        # A list, as in `name:` followed by indented dashes.
        inmod && /^[[:space:]]*name:[[:space:]]*$/ { inname = 1; next }
        # A comment or a blank line inside a name list is not the end of the list. Treating it as
        # the end silently dropped every entry after the first comment, which meant this check
        # walked straight past plasma-framework5 and reported a clean pass over an incomplete set.
        # The same silent-skip shape it exists to catch, in itself.
        inname && /^[[:space:]]*(#|$)/ { next }

        inname && /^[[:space:]]*-[[:space:]]/ {
            line = $0
            sub(/^[[:space:]]*-[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            gsub(/"|'"'"'/, "", line)
            print FILENAME "\t" line
            next
        }
        inname && !/^[[:space:]]*-/ { inmod = 0; inname = 0 }
    ' $(grep -rl "community.general.pacman" "${ROLES_DIR}") 2>/dev/null | sort -u
)

templated=()
literal=()
for entry in "${found[@]}"; do
    pkg="${entry#*$'\t'}"
    [[ -z "${pkg}" ]] && continue
    if [[ "${pkg}" == *'{{'* ]]; then
        templated+=("${entry}")
    else
        literal+=("${entry}")
    fi
done

info "found ${#literal[@]} literal pacman package names across the roles, ${#templated[@]} templated"

if [[ ${#templated[@]} -gt 0 ]]; then
    warn "templated names cannot be resolved without rendering, so they are NOT checked:"
    for t in "${templated[@]}"; do printf '       %s -> %s\n' "$(basename "${t%%$'\t'*}")" "${t#*$'\t'}"; done
fi

# Same retry shape as the mapping check. archlinux.org answers a burst of sequential requests with
# an empty body rather than a 404, and without the retry that reads identically to "no such
# package", which once reported eleven real packages as missing.
# pacman accepts a package group where it accepts a package name, and a group is not in the
# packages index, so `gnome` looked missing when it is a perfectly valid group the GNOME role
# installs. Groups live behind their own page, which answers 200 whether or not the group exists,
# so the title is the discriminator rather than the status code. Both architectures are tried
# because an `any` group such as base-devel is absent from the x86_64 listing.
group_exists() {
    local g="$1" arch
    for arch in x86_64 any; do
        if curl -s --max-time 20 "https://archlinux.org/groups/${arch}/${g}/" | grep -q 'Group Details'; then
            return 0
        fi
    done
    return 1
}

missing=()
groups=()
checked=0
for entry in "${literal[@]}"; do
    file="${entry%%$'\t'*}"
    pkg="${entry#*$'\t'}"
    checked=$((checked + 1))
    ok=false
    for attempt in 1 2 3; do
        if curl -s --max-time 20 "https://archlinux.org/packages/search/json/?name=${pkg}" | grep -q '"pkgname"'; then
            ok=true; break
        fi
        sleep $((attempt * 2))
    done
    if [[ "${ok}" == false ]]; then
        if group_exists "${pkg}"; then
            groups+=("${pkg}")
        else
            missing+=("${pkg} (in $(basename "${file}"))")
        fi
    fi
done

[[ ${#groups[@]} -gt 0 ]] && dim "resolved as package groups rather than packages: ${groups[*]}"

if [[ ${#missing[@]} -eq 0 ]]; then
    pass "all ${checked} literal pacman names in role tasks resolve as a package or a group"
else
    fail "${#missing[@]} of ${checked} literal pacman names in role tasks do not exist" "${missing[*]}"
fi

# A name that resolves only in the AUR is not installable by the pacman module, which talks to the
# configured repositories. That would fail at run time with "could not find package", so it is
# worth separating from a name that does not exist anywhere.
finish "role package names"
