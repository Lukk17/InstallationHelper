#!/usr/bin/env bash
#
# Tier 2: every package name the playbook would install must actually exist.
#
# Nothing is installed and no container is started. Each name is resolved against the
# real index for its package manager, which catches renames, drops and typos in about
# a minute. Package names drift constantly: hardinfo became hardinfo2 on both Arch and
# Fedora, arduino left the Arch repositories, and Broadcom pulled VMware's installer.
# See docs/regression_ledger.md.
#
# apt and dnf are deliberately NOT resolved here. Most of their names come from
# repositories the playbook itself adds at run time, so resolving them without those
# repositories would report false failures for packages that are perfectly fine. They
# are covered by the real tier 3 runs instead. That is a stated gap, not an oversight.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd curl

VARS_DIR="${ANSIBLE_DIR}/vars"

info "Tier 2: package name resolution"
warn "apt and dnf names are not checked here, their repositories are added at run time. Tier 3 covers them."

# packages_for <vars-file> <manager>  ->  one package name per line
packages_for() {
    grep -E "^  [a-z0-9_]+: \{ *manager: \"$2\"" "$1" \
        | sed -E 's/.*package: "([^"]+)".*/\1/' | sort -u || true
}

http_ok() { [[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$1")" =~ ^(200|301|302)$ ]]; }

# --- Arch official repositories ---------------------------------------------
# One request per name, because the search endpoint honours only the last `name`
# parameter and silently ignores earlier ones, so batching would report everything
# except the final package as missing.
#
# archlinux.org throttles a burst of sequential requests and answers with an empty
# body rather than a 404, which is indistinguishable from "no such package" unless you
# retry. Without the retry this check reported eleven perfectly real packages as
# missing, all of them at the alphabetical tail where the throttle kicked in. A check
# that cries wolf gets ignored, which is worse than not having it.
check_pacman() {
    local missing=() n=0
    while IFS= read -r pkg; do
        [[ -z "${pkg}" ]] && continue
        n=$((n + 1))
        local found=false
        for attempt in 1 2 3; do
            if curl -s --max-time 20 "https://archlinux.org/packages/search/json/?name=${pkg}" | grep -q '"pkgname"'; then
                found=true; break
            fi
            sleep $((attempt * 2))
        done
        [[ "${found}" == false ]] && missing+=("${pkg}")
    done < <(packages_for "${VARS_DIR}/Archlinux.yaml" pacman)
    if [[ ${#missing[@]} -eq 0 ]]; then
        pass "Arch official repositories: all ${n} package names resolve"
    else
        fail "Arch official repositories: ${#missing[@]} of ${n} names do not exist" "${missing[*]}"
    fi
}

# --- Arch User Repository ----------------------------------------------------
# One batched request. The RPC endpoint takes repeated arg[] parameters and returns
# only the names it found, so the difference is the missing set.
check_aur() {
    local pkgs=() query=""
    mapfile -t pkgs < <(packages_for "${VARS_DIR}/Archlinux.yaml" aur)
    [[ ${#pkgs[@]} -eq 0 ]] && { pass "AUR: nothing mapped"; return; }
    for p in "${pkgs[@]}"; do query+="&arg[]=${p}"; done
    local found
    found="$(curl -s --max-time 30 "https://aur.archlinux.org/rpc/v5/info?${query#&}" \
        | tr '{' '\n' | grep -oE '"Name":"[^"]+"' | sed -E 's/.*:"([^"]+)"/\1/' | sort -u)"
    local missing=()
    for p in "${pkgs[@]}"; do grep -qx "${p}" <<<"${found}" || missing+=("${p}"); done
    if [[ ${#missing[@]} -eq 0 ]]; then
        pass "AUR: all ${#pkgs[@]} package names resolve"
    else
        fail "AUR: ${#missing[@]} of ${#pkgs[@]} names do not exist" "${missing[*]}"
    fi
}

# --- Flathub -----------------------------------------------------------------
# Checked once across all Linux families, because the application id is the same
# everywhere and re-checking it three times only wastes time.
check_flatpak() {
    local ids=() missing=()
    mapfile -t ids < <(
        { packages_for "${VARS_DIR}/Archlinux.yaml" flatpak
          packages_for "${VARS_DIR}/Debian.yaml" flatpak
          packages_for "${VARS_DIR}/RedHat.yaml" flatpak; } | sort -u
    )
    for id in "${ids[@]}"; do
        [[ -z "${id}" ]] && continue
        http_ok "https://flathub.org/api/v2/appstream/${id}" || missing+=("${id}")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        pass "Flathub: all ${#ids[@]} application ids resolve"
    else
        fail "Flathub: ${#missing[@]} of ${#ids[@]} ids do not exist" "${missing[*]}"
    fi
}

# --- Homebrew ----------------------------------------------------------------
check_brew() {
    local kind="$1" api="$2" pkgs=() missing=()
    mapfile -t pkgs < <(packages_for "${VARS_DIR}/Darwin.yaml" "${kind}")
    [[ ${#pkgs[@]} -eq 0 ]] && { pass "Homebrew ${kind}: nothing mapped"; return; }
    for p in "${pkgs[@]}"; do
        # A tap-qualified name (owner/tap/formula) is not in the core index, so
        # formulae.brew.sh answers 404 for a name that is perfectly correct. Terraform
        # is the live example: HashiCorp's licence change pushed it out of homebrew-core
        # and the only working name is hashicorp/tap/terraform. Resolve those against
        # the tap repository instead.
        if [[ "${p}" == */*/* ]]; then
            local owner tap formula
            owner="${p%%/*}"; tap="${p#*/}"; tap="${tap%%/*}"; formula="${p##*/}"
            if http_ok "https://raw.githubusercontent.com/${owner}/homebrew-${tap}/master/Formula/${formula}.rb" \
               || http_ok "https://raw.githubusercontent.com/${owner}/homebrew-${tap}/main/Formula/${formula}.rb"; then
                continue
            fi
            missing+=("${p}")
            continue
        fi
        http_ok "https://formulae.brew.sh/api/${api}/${p}.json" || missing+=("${p}")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        pass "Homebrew ${kind}: all ${#pkgs[@]} names resolve"
    else
        fail "Homebrew ${kind}: ${#missing[@]} of ${#pkgs[@]} names do not exist" "${missing[*]}"
    fi
}

# --- Chocolatey --------------------------------------------------------------
check_choco() {
    local pkgs=() missing=()
    mapfile -t pkgs < <(packages_for "${VARS_DIR}/Windows.yaml" choco)
    [[ ${#pkgs[@]} -eq 0 ]] && { pass "Chocolatey: nothing mapped"; return; }
    for p in "${pkgs[@]}"; do
        http_ok "https://community.chocolatey.org/packages/${p}" || missing+=("${p}")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        pass "Chocolatey: all ${#pkgs[@]} package ids resolve"
    else
        fail "Chocolatey: ${#missing[@]} of ${#pkgs[@]} ids do not exist" "${missing[*]}"
    fi
}

# --- winget ------------------------------------------------------------------
# Two ways to resolve these, and the better one only exists on Windows.
#
# Preferred: ask winget. `winget show --id <id> --exact` queries the real source the installer
# will use, has no request budget, and answers the actual question, which is whether the id
# resolves for the user. It is only reachable when the check runs from a Windows shell such as
# Git Bash, because WSL cannot execute the Store build of winget. That is where this check ran
# unproven for a long time: from WSL it skipped, and WSL was the documented way to run the gate,
# so 82 mapped ids had never been resolved by anything.
#
# Fallback: look for the manifest directory in microsoft/winget-pkgs, whose path is
# manifests/<first letter lowercased>/<id split on dots>. Needs an authenticated gh, because
# unauthenticated GitHub allows 60 requests an hour and there are more ids than that. This
# proves the manifest exists upstream, which is close to the same thing but not identical: a
# manifest can exist while the id fails to resolve on a machine whose sources are stale.
check_winget() {
    local pkgs=() missing=() skipped=0
    mapfile -t pkgs < <(packages_for "${VARS_DIR}/Windows.yaml" winget)
    [[ ${#pkgs[@]} -eq 0 ]] && { pass "winget: nothing mapped"; return; }

    # Probed by running it, not by existing on PATH. On Windows the first hit is often the Store
    # app-execution-alias stub, which WSL cannot execute at all.
    local winget_cmd=""
    for candidate in winget winget.exe; do
        command -v "${candidate}" &>/dev/null || continue
        if "${candidate}" --version &>/dev/null; then winget_cmd="${candidate}"; break; fi
    done

    local use_gh=false
    command -v gh &>/dev/null && gh auth status &>/dev/null && use_gh=true

    if [[ -z "${winget_cmd}" && "${use_gh}" == false ]]; then
        warn "no runnable winget here and gh is not authenticated, so ${#pkgs[@]} winget ids are unresolved. Run this check from a Windows shell where winget works, or 'gh auth login'."
        skip "winget manifest ids resolve"
        return
    fi

    local method
    if [[ -n "${winget_cmd}" ]]; then method="the winget CLI"; else method="the winget-pkgs manifest tree via gh"; fi
    dim "resolving ${#pkgs[@]} winget ids against ${method}"

    for id in "${pkgs[@]}"; do
        # Store-sourced entries are bare product ids, not publisher.package manifests.
        if [[ "${id}" != *.* ]]; then skipped=$((skipped + 1)); continue; fi
        if [[ -n "${winget_cmd}" ]]; then
            "${winget_cmd}" show --id "${id}" --exact --disable-interactivity --accept-source-agreements &>/dev/null \
                || missing+=("${id}")
        else
            local first path
            first="$(printf '%s' "${id:0:1}" | tr '[:upper:]' '[:lower:]')"
            path="manifests/${first}/${id//./\/}"
            gh api "repos/microsoft/winget-pkgs/contents/${path}" &>/dev/null || missing+=("${id}")
        fi
    done
    [[ ${skipped} -gt 0 ]] && dim "${skipped} entries skipped, they are Microsoft Store product ids rather than winget manifests"
    if [[ ${#missing[@]} -eq 0 ]]; then
        pass "winget: all $(( ${#pkgs[@]} - skipped )) manifest ids resolve against ${method}"
    else
        fail "winget: ${#missing[@]} manifest ids do not exist" "${missing[*]}"
    fi
}

check_pacman
check_aur
check_flatpak
check_brew brew formula
check_brew brew_cask cask
check_choco
check_winget

finish "package name resolution"
