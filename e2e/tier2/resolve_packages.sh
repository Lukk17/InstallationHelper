#!/usr/bin/env bash
#
# Tier 2: every package name the playbook would install must actually exist.
#
# Nothing is installed. Each name is resolved against the real index for its package
# manager, which catches renames, drops and typos in a few minutes. Package names drift
# constantly: hardinfo became hardinfo2 on both Arch and Fedora, arduino left the Arch
# repositories, and Broadcom pulled VMware's installer. See docs/regression_ledger.md.
#
# apt and dnf are the two that cannot be resolved over HTTP, because the answer depends
# on a package index that only exists on a machine of that distribution. They used to be
# left out entirely, on the grounds that most of their names come from repositories the
# playbook adds at run time and checking them would report false failures. That reasoning
# left the 35 apt names and the 35 dnf names covered by nothing at all, on the two
# families most people run. They are now resolved inside the same pinned base images the
# tier 3 scenarios use, and the handful that genuinely need a repository the playbook adds
# are forgiven by name and reason in runtime_repo_packages.txt.
#
# apt_url and dnf_url entries are not package names at all, they are vendor downloads.
# tier1/toggle_coverage.sh and tier2/resolve_pinned_urls.sh cover those.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/package_probe.sh"
source "${REPO_ROOT}/setup/pinned_values/pinned_values.sh"

require_cmd curl

VARS_DIR="${ANSIBLE_DIR}/vars"

info "Tier 2: package name resolution"

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
    done < <(package_names_for "${VARS_DIR}/Archlinux.yaml" pacman)
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
    mapfile -t pkgs < <(package_names_for "${VARS_DIR}/Archlinux.yaml" aur)
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
        { package_names_for "${VARS_DIR}/Archlinux.yaml" flatpak
          package_names_for "${VARS_DIR}/Debian.yaml" flatpak
          package_names_for "${VARS_DIR}/RedHat.yaml" flatpak; } | sort -u
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
    mapfile -t pkgs < <(package_names_for "${VARS_DIR}/Darwin.yaml" "${kind}")
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
    mapfile -t pkgs < <(package_names_for "${VARS_DIR}/Windows.yaml" choco)
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
# resolves for the user. Reachable from Git Bash, and measured on 2026-08-20, from WSL too, because
# the Store winget.exe runs through interop. This is why the probe below runs a candidate instead of
# trusting the shell it is in. It once ran unproven for a long time for exactly the opposite reason:
# from WSL it skipped, WSL was the documented way to run the gate, and 82 mapped ids had never been
# resolved by anything.
#
# Fallback: look for the manifest directory in microsoft/winget-pkgs, whose path is
# manifests/<first letter lowercased>/<id split on dots>. Needs an authenticated gh, because
# unauthenticated GitHub allows 60 requests an hour and there are more ids than that. This
# proves the manifest exists upstream, which is close to the same thing but not identical: a
# manifest can exist while the id fails to resolve on a machine whose sources are stale.
check_winget() {
    local pkgs=() missing=() skipped=0
    mapfile -t pkgs < <(package_names_for "${VARS_DIR}/Windows.yaml" winget)
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

# --- the file a winget manifest points at ------------------------------------
# check_winget above asks whether the identifier resolves. That is not the question that failed twice
# on 2026-08-25. Both hwinfo and openssl had current, healthy manifests whose download was gone:
#
#   REALiX.HWiNFO              https://www.sac.sk/download/utildiag/hwi_850x.exe            404
#   ShiningLight.OpenSSL.Light https://slproweb.com/download/Win64OpenSSL_Light-4_0_1.msi   404
#
# Each surfaced as `exit -2145844844 ... 0x80190194 : Not found (404)` about an hour into a Windows
# run, and each cost roughly two hours of runner time to find. The identifier check passed both times
# and was right to: the manifest exists. The file below it does not.
#
# So this asks the level below, taking the URL from `winget show` and sending it a request.
#
# winget rather than the manifest tree on GitHub, and that is measured rather than a preference.
# Reading manifests from microsoft/winget-pkgs needs two authenticated API calls per package and
# eighty packages did not finish inside a ten minute window. `winget show --id <id> --exact` prints
# the same InstallerUrl from one local process in 0.8 seconds. GitHub is kept as the fallback for a
# machine with no winget, and on that route this check reports what it could not prove rather than
# pretending to a result.
#
# What counts as a failure is deliberately narrow. 404 and 410 mean the vendor removed the file, which
# is the defect. A timeout, a refused connection, or a 403 is reported as unproven, because those are
# properties of the request rather than of the file: several vendors refuse a bare request from a data
# centre while serving a browser perfectly well, and calling that a dead download would make this
# check cry wolf until somebody stopped reading it.
check_winget_downloads() {
    local pkgs=() dead=() unproven=() checked=0 skipped=0
    mapfile -t pkgs < <(package_names_for "${VARS_DIR}/Windows.yaml" winget)
    [[ ${#pkgs[@]} -eq 0 ]] && { pass "winget downloads: nothing mapped"; return; }

    if ! command -v curl &>/dev/null; then
        skip "the file every winget manifest points at still exists" "no curl here to ask with"
        return
    fi

    local winget_cmd=""
    for candidate in winget winget.exe; do
        command -v "${candidate}" &>/dev/null || continue
        if "${candidate}" --version &>/dev/null; then winget_cmd="${candidate}"; break; fi
    done

    if [[ -z "${winget_cmd}" ]]; then
        skip "the file every winget manifest points at still exists" \
             "no runnable winget here, and reading ${#pkgs[@]} manifests from GitHub instead does not finish in a sensible time"
        return
    fi

    dim "asking winget for ${#pkgs[@]} installer URLs and then asking each one whether it still exists"

    local id url code
    for id in "${pkgs[@]}"; do
        # Store product ids carry no manifest, so there is no URL to ask about.
        if [[ "${id}" != *.* ]]; then skipped=$((skipped + 1)); continue; fi

        # The first URL only. A manifest can carry six architectures and the question here is whether
        # the vendor still publishes the release at all, so asking once keeps this near one request
        # per package instead of six.
        url="$("${winget_cmd}" show --id "${id}" --exact --disable-interactivity --accept-source-agreements 2>/dev/null \
               | grep -iE '^[[:space:]]*Installer Url:' | head -1 | sed -E 's/.*Installer Url:[[:space:]]*//' | tr -d '\r')"
        if [[ -z "${url}" ]]; then
            unproven+=("${id} (winget printed no installer URL)")
            continue
        fi

        checked=$((checked + 1))
        code="$(curl -s -o /dev/null -m 25 -w '%{http_code}' -L "${url}" 2>/dev/null || echo 000)"
        case "${code}" in
            404|410) dead+=("${id} -> ${url} answered ${code}") ;;
            2*|3*)   : ;;
            *)       unproven+=("${id} -> ${url} answered ${code}") ;;
        esac
    done

    [[ ${skipped} -gt 0 ]] && dim "${skipped} entries skipped, they are Microsoft Store product ids"
    [[ ${#unproven[@]} -gt 0 ]] && dim "${#unproven[@]} not proven either way: ${unproven[*]}"

    if [[ ${#dead[@]} -eq 0 ]]; then
        pass "winget downloads: all ${checked} packages point at a file that still exists"
    else
        fail "winget downloads: ${#dead[@]} package(s) point at a file the vendor has removed, so the install fails with 0x80190194 about an hour into a Windows run" "${dead[*]}"
    fi
}

# --- apt and dnf, inside the pinned base image -------------------------------
# The image comes out of e2e/tier3/<distro>.Dockerfile, so this check and the scenarios
# always talk about the same distribution release. Nothing is installed: apt-cache policy
# and dnf info both answer from the index alone.
#
# Debian and Ubuntu are both asked about the apt half of vars/Debian.yaml, because both
# families read that one dictionary and their package sets are not the same. Ubuntu 26.04
# has no kubectl of its own while Debian trixie does, and only asking one of them would
# have missed that.
check_dictionary() {
    local distro="$1" manager="$2" file="$3"
    probe_names "${distro}" "$(probe_image_for "${distro}")" \
        "${distro} dictionary package names" \
        "${manager} names in vars/${file}" \
        "$(package_names_for "${VARS_DIR}/${file}" "${manager}")"
}

check_apt_and_dnf() {
    if ! docker info &>/dev/null; then
        skip "apt and dnf dictionary package names" "no reachable Docker daemon, so the package indexes cannot be queried"
        return
    fi
    check_dictionary debian apt Debian.yaml
    check_dictionary ubuntu apt Debian.yaml
    check_dictionary fedora dnf RedHat.yaml
}

# --- npm ---------------------------------------------------------------------
# The other checks in this file ask "does this name exist". That is not the question that failed.
# The OpenSpec mapping named the npm package `openspec`, which exists: it is a stub published once in
# 2019 at version 0.0.0, with no executable in it and no relation to the project. Every other check
# in this repository was happy, the install exited zero, and the tool was absent. What provides the
# openspec command is @fission-ai/openspec.
#
# So this asks three things the registry can answer, and each one would have caught it on its own:
# the package is not deprecated, it declares at least one executable, and its newest version is not
# 0.0.0. The third is a blunt instrument on purpose, because a name squatted years ago and never
# touched again is exactly the shape of the thing that got through.
#
# Read from the Ansible task files rather than from the PowerShell table, because tier 1 already
# proves the two agree, so one side is enough and the other cannot drift unnoticed.
check_npm() {
    if ! PYTHON="$(pinned_values_python)"; then
        skip "npm packages are live, undeprecated and each installs an executable"              "no Python 3.11 or newer on PATH, so the registry answers cannot be read"
        return
    fi
    local pkgs=() bad=() n=0
    mapfile -t pkgs < <(
        for f in "${ANSIBLE_DIR}"/roles/ai_tools/tasks/*_unix.yaml; do
            [[ "$(basename "${f}")" == "npm_install_unix.yaml" ]] && continue
            grep -hE '^\s*npm_pkg:' "${f}" 2>/dev/null | sed -E 's/^\s*npm_pkg:\s*//; s/"//g; s/\s+$//'
        done | sort -u
    )
    [[ ${#pkgs[@]} -eq 0 ]] && { fail "npm: no packages found in the ai_tools task files, so this check proves nothing" "${ANSIBLE_DIR}/roles/ai_tools/tasks"; return; }

    for pkg in "${pkgs[@]}"; do
        n=$((n + 1))
        # The scope separator has to be encoded or the registry reads it as a path segment.
        local encoded="${pkg//\//%2f}"
        local body
        body="$(curl -s --max-time 25 "https://registry.npmjs.org/${encoded}" || true)"
        if [[ -z "${body}" ]]; then
            bad+=("${pkg}: the registry did not answer")
            continue
        fi
        local verdict
        verdict="$(
            PKG="${pkg}" "${PYTHON}" -c '
import json, os, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except ValueError:
    print("the registry answer was not JSON"); raise SystemExit
if "error" in d:
    print("the registry says: " + str(d["error"])); raise SystemExit
latest = d.get("dist-tags", {}).get("latest")
if not latest:
    print("no latest version"); raise SystemExit
v = d.get("versions", {}).get(latest, {})
problems = []
if v.get("deprecated"):
    problems.append("deprecated: " + str(v["deprecated"])[:60])
if not (v.get("bin") or {}):
    problems.append("declares no executable, so installing it globally leaves no command behind")
if latest == "0.0.0":
    problems.append("newest version is 0.0.0, which is what an abandoned name looks like")
print("; ".join(problems))
' <<<"${body}"
        )"
        [[ -n "${verdict}" ]] && bad+=("${pkg}: ${verdict}")
    done

    if [[ ${#bad[@]} -eq 0 ]]; then
        pass "npm: all ${n} packages are live, undeprecated and each installs an executable"
    else
        fail "npm: ${#bad[@]} of ${n} packages are not what they claim" "$(printf '%s | ' "${bad[@]}")"
    fi
}

check_pacman
check_aur
check_flatpak
check_brew brew formula
check_brew brew_cask cask
check_choco
check_winget
check_winget_downloads
check_npm
check_apt_and_dnf
probe_report_forgiveness "no dictionary forgiveness in runtime_repo_packages.txt has become unnecessary"

finish "package name resolution"
