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
source "$(dirname "${BASH_SOURCE[0]}")/../lib/http_ask.sh"
source "${REPO_ROOT}/setup/pinned_values/pinned_values.sh"

require_cmd curl

VARS_DIR="${ANSIBLE_DIR}/vars"
DERIVATIVES_DIR="${VARS_DIR}/derivatives"

# --- Arch official repositories ---------------------------------------------
# One request per name, because the search endpoint honours only the last `name`
# parameter and silently ignores earlier ones, so batching would report everything
# except the final package as missing.
#
# archlinux.org throttles a burst of sequential requests and answers with an empty
# body rather than a 404, which is indistinguishable from "no such package" unless you
# retry. Without the retry this check reported eleven perfectly real packages as
# missing, all of them at the alphabetical tail where the throttle kicked in. A check
# that cries wolf gets ignored, which is worse than not having it. So only a body that
# carries a results list is an answer, and an empty list is the definite "no such package".
check_pacman() {
    local missing=() unresolved=() n=0 pkg url status
    while IFS= read -r pkg; do
        [[ -z "${pkg}" ]] && continue
        n=$((n + 1))
        url="https://archlinux.org/packages/search/json/?name=${pkg}"
        status=0
        http_ask "${url}" '"results"' || status=$?
        case ${status} in
            0) grep -q '"pkgname"' <<<"${HTTP_BODY}" || missing+=("${pkg}") ;;
            1) missing+=("${pkg}") ;;
            *) unresolved+=("${pkg}: $(http_unresolved_reason "${url}")") ;;
        esac
    done < <({ package_names_for "${VARS_DIR}/Archlinux.yaml" pacman
               companion_packages_of "${VARS_DIR}/Archlinux.yaml" | awk '{print $2}'; } | sort -u)
    report_names "Arch official repositories" "package names" "${n}"
}

# --- Arch User Repository ----------------------------------------------------
# One batched request. The RPC endpoint takes repeated arg[] parameters and returns
# only the names it found, so the difference is the missing set.
check_aur() {
    local pkgs=() query="" f
    mapfile -t pkgs < <(
        { package_names_for "${VARS_DIR}/Archlinux.yaml" aur
          for f in "${DERIVATIVES_DIR}"/*.yaml; do [[ -f "${f}" ]] && package_names_for "${f}" aur; done; } | sort -u
    )
    [[ ${#pkgs[@]} -eq 0 ]] && { pass "AUR: nothing mapped"; return; }
    for p in "${pkgs[@]}"; do query+="&arg[]=${p}"; done
    local found url="https://aur.archlinux.org/rpc/v5/info?${query#&}"
    if ! http_ask "${url}" '"resultcount"'; then
        fail "AUR: the ${#pkgs[@]} package names could not be checked, because the index never gave a definite answer" \
            "$(http_unresolved_reason "${url}")"
        return
    fi
    found="$(tr '{' '\n' <<<"${HTTP_BODY}" | grep -oE '"Name":"[^"]+"' | sed -E 's/.*:"([^"]+)"/\1/' | sort -u || true)"
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
    local ids=() missing=() unresolved=() f
    mapfile -t ids < <(
        { package_names_for "${VARS_DIR}/Archlinux.yaml" flatpak
          package_names_for "${VARS_DIR}/Debian.yaml" flatpak
          package_names_for "${VARS_DIR}/RedHat.yaml" flatpak
          for f in "${DERIVATIVES_DIR}"/*.yaml; do [[ -f "${f}" ]] && package_names_for "${f}" flatpak; done; } | sort -u
    )
    for id in "${ids[@]}"; do
        [[ -z "${id}" ]] && continue
        ask_name "${id}" "https://flathub.org/api/v2/appstream/${id}"
    done
    report_names "Flathub" "application ids" "${#ids[@]}"
}

# --- Homebrew ----------------------------------------------------------------
check_brew() {
    local kind="$1" api="$2" pkgs=() missing=() unresolved=()
    mapfile -t pkgs < <(package_names_for "${VARS_DIR}/Darwin.yaml" "${kind}")
    [[ ${#pkgs[@]} -eq 0 ]] && { pass "Homebrew ${kind}: nothing mapped"; return; }
    for p in "${pkgs[@]}"; do
        # A tap-qualified name (owner/tap/formula) is not in the core index, so
        # formulae.brew.sh answers 404 for a name that is perfectly correct. Terraform
        # is the live example: HashiCorp's licence change pushed it out of homebrew-core
        # and the only working name is hashicorp/tap/terraform. Resolve those against
        # the tap repository instead.
        # The name is missing only when both branches say so definitely.
        if [[ "${p}" == */*/* ]]; then
            local owner tap formula branch url status verdict=missing reasons=()
            owner="${p%%/*}"; tap="${p#*/}"; tap="${tap%%/*}"; formula="${p##*/}"
            for branch in master main; do
                url="https://raw.githubusercontent.com/${owner}/homebrew-${tap}/${branch}/Formula/${formula}.rb"
                status=0
                http_ask "${url}" || status=$?
                if [[ ${status} -eq 0 ]]; then
                    verdict=found
                    break
                fi
                if [[ ${status} -eq 2 ]]; then
                    verdict=unresolved
                    reasons+=("$(http_unresolved_reason "${url}")")
                fi
            done
            case "${verdict}" in
                missing)    missing+=("${p}") ;;
                unresolved) unresolved+=("${p}: ${reasons[*]}") ;;
            esac
            continue
        fi
        ask_name "${p}" "https://formulae.brew.sh/api/${api}/${p}.json"
    done
    report_names "Homebrew ${kind}" "names" "${#pkgs[@]}"
}

# --- Chocolatey --------------------------------------------------------------
check_choco() {
    local pkgs=() missing=() unresolved=()
    mapfile -t pkgs < <(package_names_for "${VARS_DIR}/Windows.yaml" choco)
    [[ ${#pkgs[@]} -eq 0 ]] && { pass "Chocolatey: nothing mapped"; return; }
    for p in "${pkgs[@]}"; do
        ask_name "${p}" "https://community.chocolatey.org/packages/${p}"
    done
    report_names "Chocolatey" "package ids" "${#pkgs[@]}"
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

# --- which winget manifests leave the installer to a scope ------------------
# tier1/winget_scope_pins.sh requires every package in tier1/winget_scoped_packages.txt to pin a
# scope in vars/Windows.yaml, offline. This is what keeps that list true. It reads the newest
# installer manifest of every mapped winget id from microsoft/winget-pkgs and recomputes the list:
# a package belongs on it when one of its installers declares Scope: user, or when its installers
# declare more than one distinct scope, counting an installer that declares none as "none", or when
# its mapping pins a scope. The first two are the shape Bruno.Bruno, Overwolf.CurseForge and
# Mirantis.Lens failed with in the elevated wizard. Each line also carries the installer type winget
# selects for --scope machine, which is what decides whether the wizard has to run winget elevated.
#
# Read through gh rather than winget, because `winget show` prints no scope at all, measured with
# winget v1.29.380 on 2026-10-11: Mirantis.Lens shows the same nullsoft URL with no scope, with
# --scope machine and with --scope user. Two API calls per package, the version folder listing and
# the installer manifest, measured at about two minutes for the whole dictionary on 2026-10-11.
#
# The parser is deliberately the standard library over the manifest's text rather than PyYAML,
# because PyYAML is not on every machine this tier runs on and the manifest format puts every
# installer key at one indent below its list item.
check_winget_scopes() {
    local list="${REPO_ROOT}/e2e/tier1/winget_scoped_packages.txt"
    local claim="winget packages that leave the installer to a scope match tier1/winget_scoped_packages.txt"

    if ! command -v gh &>/dev/null || ! gh auth status &>/dev/null; then
        skip "${claim}" "gh is not authenticated, and winget itself prints no scope, so the manifests cannot be read"
        return
    fi
    local python
    if ! python="$(find_runnable_python)"; then
        skip "${claim}" "no Python 3.11 or newer on PATH (tried python3, python and py)"
        return
    fi

    local pkgs=() live=() unread=() id first base version manifest scopes
    mapfile -t pkgs < <(package_names_for "${VARS_DIR}/Windows.yaml" winget)
    # The winget ids whose mapping pins a scope, read the way tier1/winget_scope_pins.sh reads them.
    # A pinned package is listed even when its manifest offers no choice, Syncthing.Syncthing's one
    # unscoped zip for instance, because the list is also the evidence for the installer type a
    # machine pin declares.
    local -A pinned=()
    while read -r id; do
        [[ -n "${id}" ]] && pinned["${id}"]=1
    done < <(sed -nE 's/^  [a-z0-9_]+: \{[[:space:]]*manager:[[:space:]]*"winget"[[:space:]]*,[[:space:]]*package:[[:space:]]*"([^"]+)"[[:space:]]*(,[[:space:]]*source:[[:space:]]*"[a-z]+"[[:space:]]*)?,[[:space:]]*scope:[[:space:]]*"[a-z]+".*/\1/p' \
                 "${VARS_DIR}/Windows.yaml" | tr -d '\r')
    dim "reading the newest installer manifest of every winget id from microsoft/winget-pkgs"

    for id in "${pkgs[@]}"; do
        [[ "${id}" != *.* ]] && continue
        first="$(printf '%s' "${id:0:1}" | tr '[:upper:]' '[:lower:]')"
        base="manifests/${first}/${id//./\/}"
        manifest=""
        # A package folder holds its version folders and sometimes the folders of longer ids that
        # share its prefix, so only names starting with a digit are versions. Newest first, and a
        # version folder without the installer manifest is passed over for the one before it.
        while read -r version; do
            manifest="$(gh api -H 'Accept: application/vnd.github.raw' \
                "repos/microsoft/winget-pkgs/contents/${base}/${version}/${id}.installer.yaml" 2>/dev/null)" && break
            manifest=""
        done < <(gh api "repos/microsoft/winget-pkgs/contents/${base}" --jq '.[] | select(.type == "dir") | .name' 2>/dev/null \
                    | tr -d '\r' | grep -E '^[0-9]' | sort -V -r | head -3)
        if [[ -z "${manifest}" ]]; then
            unread+=("${id}")
            continue
        fi

        # Prints the scopes the manifest declares and the installer type winget selects for
        # --scope machine, "-" when none applies. The selection follows winget-cli v1.29.380,
        # src/AppInstallerCommonCore/Manifest/ManifestComparator.cpp: an installer applies to a
        # required scope when it declares that scope or its effective type ignores the manifest's
        # scope (msix, msstore, portable, font, DoesInstallerTypeIgnoreScopeFromManifest), then the
        # architecture, then the default type precedence. The effective type of a zip is its nested
        # type, and appx is msix, both as winget reads them. Checked against `winget show --scope
        # machine` with winget v1.29.380 for all 21 machine pins on 2026-10-11, which agreed on
        # every one.
        scopes="$("${python}" -c '
import re, sys
root = {}
installers = []
inside = False
item_indent = None
key_line = re.compile(r"(Scope|InstallerType|NestedInstallerType|Architecture):\s*[\x22\x27]?([\w-]+)")
names = {"Scope": "scope", "InstallerType": "type", "NestedInstallerType": "nested", "Architecture": "arch"}
for raw in sys.stdin.read().splitlines():
    line = "" if raw.lstrip().startswith("#") else raw.split(" #")[0].rstrip()
    if not line.strip():
        continue
    indent = len(line) - len(line.lstrip())
    text = line.strip()
    if indent == 0 and not text.startswith("- "):
        inside = text.startswith("Installers:")
        found = key_line.match(text)
        if found:
            root[names[found.group(1)]] = found.group(2).lower()
        continue
    if not inside:
        continue
    if text.startswith("- ") and (item_indent is None or indent == item_indent):
        item_indent = indent
        installers.append({})
        text = text[2:].strip()
    elif item_indent is None or indent != item_indent + 2:
        continue
    found = key_line.match(text)
    if found:
        installers[-1][names[found.group(1)]] = found.group(2).lower()
if not installers:
    print("UNPARSED")
    sys.exit(0)
def get(i, key):
    return i.get(key) or root.get(key) or ""
def effective(i):
    kind = get(i, "nested") if get(i, "type") == "zip" else get(i, "type")
    return "msix" if kind == "appx" else kind
scope_agnostic = {"msix", "msstore", "portable", "font"}
arch_rank = {"x64": 0, "neutral": 1, "x86": 2}
type_rank = ["msstore", "msix", "msi", "wix", "burn", "nullsoft", "inno", "exe", "portable"]
declared = sorted({get(i, "scope") or "none" for i in installers})
machine = [i for i in installers
           if (get(i, "scope") == "machine" or effective(i) in scope_agnostic) and get(i, "arch") in arch_rank]
machine.sort(key=lambda i: (arch_rank[get(i, "arch")],
                            type_rank.index(effective(i)) if effective(i) in type_rank else len(type_rank)))
print(",".join(declared), effective(machine[0]) if machine else "-")
' <<<"${manifest}" | tr -d '\r')" || scopes="UNPARSED"

        if [[ "${scopes}" == "UNPARSED" || -z "${scopes}" ]]; then
            unread+=("${id}")
        elif [[ "${scopes%% *}" == *user* || "${scopes%% *}" == *,* || -v "pinned[${id}]" ]]; then
            live+=("${id} ${scopes}")
        fi
    done

    if [[ ${#unread[@]} -gt 0 ]]; then
        fail "winget scopes: ${#unread[@]} installer manifest(s) could not be read, so whether they need a scope is unproven" "${unread[*]}"
    fi

    local expected actual
    expected="$(grep -vE '^[[:space:]]*(#|$)' "${list}" | tr -d '\r' | LC_ALL=C sort)"
    actual="$(printf '%s\n' "${live[@]}" | grep -v '^$' | LC_ALL=C sort)"
    if [[ "${expected}" == "${actual}" ]]; then
        pass "winget scopes: the ${#live[@]} packages whose manifest leaves the installer to a scope or whose mapping pins one are exactly the ones tier1/winget_scoped_packages.txt lists, with the same machine installer types"
    else
        fail "winget scopes: tier1/winget_scoped_packages.txt no longer matches winget-pkgs. Replace its data lines with the live list below, then pin a scope for every new one in vars/Windows.yaml and give every machine pin the installer_type its line names" \
             "$(diff <(echo "${expected}") <(echo "${actual}") | grep -E '^[<>]' | tr '\n' ' ')"
        dim "live list:"
        printf '%s\n' "${actual}" | while read -r line; do dim "${line}"; done
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
#
# The family's companion_packages are asked about with its own manager's names, because a role installs
# them with that manager under the toggle beside the mapping, apt on Debian and Ubuntu and dnf on Fedora.
check_dictionary() {
    local distro="$1" manager="$2" file="$3"
    probe_names "${distro}" "$(probe_image_for "${distro}")" \
        "${distro} dictionary package names" \
        "${manager} names in vars/${file}, companion_packages included" \
        "$({ package_names_for "${VARS_DIR}/${file}" "${manager}"
             companion_packages_of "${VARS_DIR}/${file}" | awk '{print $2}'; } | sort -u)"
}

# --- a derivative's own dictionary, inside its own image ---------------------
# vars/derivatives/<id>.yaml holds the entries a distribution maps differently from its family, and
# setup/ansible/tasks/load_os_dict.yaml merges them over the family's dictionary. CachyOS is the one
# today, and its gaming suite is cachyos-gaming-applications from the cachyos repository, which
# archlinux.org has never heard of. So the merged pacman set is resolved inside the image
# e2e/tier3/<id>.Dockerfile names, which is the distribution the scenarios run.
#
# pacman is the only manager resolved here, because every derivative so far is an Arch one. Flathub and
# AUR names in a derivative file are already asked about by check_flatpak and check_aur above. A
# derivative entry for any other manager fails here by name rather than passing unresolved, and so
# does a derivative whose e2e/tier3/<id>.Dockerfile is missing or never runs pacman, because merging
# it over vars/Archlinux.yaml would check it against the wrong family.
derivative_dockerfile_runs_pacman() {
    local dockerfile="${PROBE_TIER3_DIR}/$1.Dockerfile"
    [[ -f "${dockerfile}" ]] && grep -vE '^\s*#' "${dockerfile}" | grep -qE '(^|[^[:alnum:]_-])pacman -S'
}

check_derivatives() {
    local f id others
    for f in "${DERIVATIVES_DIR}"/*.yaml; do
        [[ -f "${f}" ]] || continue
        id="$(basename "${f}" .yaml)"
        if ! derivative_dockerfile_runs_pacman "${id}"; then
            fail "${id}: vars/derivatives/${id}.yaml is merged over vars/Archlinux.yaml, but e2e/tier3/${id}.Dockerfile is missing or never runs pacman, so it is not an Arch image and its names would be checked against the wrong family" \
                "${PROBE_TIER3_DIR}/${id}.Dockerfile"
            continue
        fi
        others="$(derivative_mapping_lines "${f}" | grep -vE 'manager: "(pacman|aur|flatpak)"' || true)"
        if [[ -n "${others}" ]]; then
            fail "${id}: vars/derivatives/${id}.yaml maps a manager this check cannot resolve" "${others}"
        fi
        if ! derivative_mapping_lines "${f}" | grep -E '\{ *manager: "pacman"' >/dev/null; then
            continue
        fi
        if ! docker info &>/dev/null; then
            skip "${id} dictionary package names" "no reachable Docker daemon, so the ${id} package index cannot be queried"
            continue
        fi
        probe_names "${id}" "$(probe_image_for "${id}")" \
            "${id} dictionary package names" \
            "pacman names in vars/Archlinux.yaml merged with vars/derivatives/${id}.yaml, companion_packages included" \
            "$({ derivative_package_names_for "${VARS_DIR}/Archlinux.yaml" "${f}" pacman
                 companion_packages_of "${VARS_DIR}/Archlinux.yaml" | awk '{print $2}'; } | sort -u)"
    done
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
    mapfile -t pkgs < <(ai_tools_npm_packages)
    [[ ${#pkgs[@]} -eq 0 ]] && { fail "npm: no packages found in the ai_tools task files, so this check proves nothing" "${ANSIBLE_DIR}/roles/ai_tools/tasks"; return; }

    for pkg in "${pkgs[@]}"; do
        n=$((n + 1))
        # The scope separator has to be encoded or the registry reads it as a path segment.
        local encoded="${pkg//\//%2f}"
        local body url="https://registry.npmjs.org/${encoded}" status=0
        http_ask "${url}" '^[[:space:]]*[{]' || status=$?
        case ${status} in
            1) bad+=("${pkg}: the registry says it does not exist, ${url} answered HTTP ${HTTP_CODE}"); continue ;;
            2) bad+=("${pkg}: $(http_unresolved_reason "${url}")"); continue ;;
        esac
        body="${HTTP_BODY}"
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

# e2e/tier1/name_lookup_retries.sh sources this file to drive the checks against a stand-in curl, so
# they run only when the file is executed.
main() {
    info "Tier 2: package name resolution"
    check_pacman
    check_aur
    check_flatpak
    check_brew brew formula
    check_brew brew_cask cask
    check_choco
    check_winget
    check_winget_downloads
    check_winget_scopes
    check_npm
    check_apt_and_dnf
    check_derivatives
    probe_report_forgiveness "no dictionary forgiveness in runtime_repo_packages.txt has become unnecessary"

    finish "package name resolution"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
