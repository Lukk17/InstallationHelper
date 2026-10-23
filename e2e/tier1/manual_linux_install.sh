#!/usr/bin/env bash
#
# Tier 1: the manual Linux install scripts and guides must say what the Linux dictionaries say.
#
# docs/manual/{arch,debian-ubuntu,fedora}/install.sh and their *_manual_install.md guides are the
# by-hand route to the software set the playbook installs, and until 2026-10-15 nothing compared them
# with setup/ansible/vars/*.yaml. By then none of the three scripts installed OpenCode desktop, which
# every guide listed, and the Arch and Fedora scripts and guides lacked PuTTY, which both dictionaries
# map. e2e/tier1/manual_windows_install.sh has guarded the Windows side since 2026-10-11, and this is
# its Linux counterpart.
#
# The dictionary side is the family's software_mapping with every derivative under
# vars/derivatives/ merged over it exactly as setup/ansible/tasks/load_os_dict.yaml does, one entry
# replacing the family's entry of the same key whole. A derivative belongs to the family its
# os-release fixture in e2e/tier1/os_release_fixtures names in ID_LIKE. The manual route serves the
# family and its derivatives with one script, so a name counts when any of them maps it. Only the
# managers the manual route can run count: pacman, aur, apt, apt_url, dnf, dnf_url, flatpak and snap.
# An apt_url or dnf_url mapping is compared by the download location the playbook resolves for it,
# the mapping's url field, else the <key>_rpm_url pin for dnf_url, else the <key>_url pin, rendered by
# the pinned values port, because that location is what the manual route has to fetch. The family's
# companion_packages entries beside a mapping count as well, each package under its toggle, because the
# playbook installs them under that toggle beside the mapping. An entry for a toggle with no mapping,
# install_docker's engine or install_snapper's snapper, is no dictionary name to the manual route, so a
# script that installs one says why in manual_linux_install_allowed.txt like any other name.
#
# Asserted for each family:
#   1. the script installs, or for the AUR lists with its yay command, every mapping whose toggle is
#      on by default, all.yaml overlaid by linux.yaml;
#   2. the script installs nothing else, apart from a documented difference;
#   3. the guide carries an install command for every mapping on by default;
#   4. no install command in the guide names a package the dictionaries do not map, on or off, apart
#      from a documented difference;
#   5. the script and the guide enable and start docker.service, as virtualization_config does;
#   6. every usermod and systemctl line in the script reports a skip rather than ending it.
# A documented difference is a line in manual_linux_install_allowed.txt naming the file of the
# playbook that installs the same package outside the dictionary, and that file must still name it,
# or naming no file, written -, for a prerequisite only the manual route needs, which the reason has
# to explain. A line nothing uses any more fails too, so the list cannot outlive its reasons.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../../setup/pinned_values/pinned_values.sh
source "${REPO_ROOT}/setup/pinned_values/pinned_values.sh"

TIER1_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOWED_FILE="${TIER1_DIR}/manual_linux_install_allowed.txt"
FIXTURE_DIR="${TIER1_DIR}/os_release_fixtures"
VARS_DIR="${ANSIBLE_DIR}/vars"
ALL_VARS="${ANSIBLE_DIR}/group_vars/all.yaml"
LINUX_VARS="${ANSIBLE_DIR}/group_vars/linux.yaml"
MANUAL_DIR="${REPO_ROOT}/docs/manual"
MANUAL_MANAGERS=" pacman aur apt apt_url dnf dnf_url flatpak snap "

declare -A SCRIPT_OF=(
    [Archlinux]="${MANUAL_DIR}/arch/install.sh"
    [Debian]="${MANUAL_DIR}/debian-ubuntu/install.sh"
    [RedHat]="${MANUAL_DIR}/fedora/install.sh"
)
declare -A GUIDE_OF=(
    [Archlinux]="${MANUAL_DIR}/arch/arch_manual_install.md"
    [Debian]="${MANUAL_DIR}/debian-ubuntu/debian_ubuntu_manual_install.md"
    [RedHat]="${MANUAL_DIR}/fedora/fedora_manual_install.md"
)
FAMILIES=(Archlinux Debian RedHat)

info "Tier 1: the manual Linux installs against vars/{Archlinux,Debian,RedHat}.yaml"

for family in "${FAMILIES[@]}"; do
    for f in "${VARS_DIR}/${family}.yaml" "${SCRIPT_OF[${family}]}" "${GUIDE_OF[${family}]}"; do
        [[ -f "${f}" ]] || { fail "a file this check compares is missing" "${f}"; finish "manual Linux install"; }
    done
done
for f in "${ALL_VARS}" "${LINUX_VARS}" "${ALLOWED_FILE}"; do
    [[ -f "${f}" ]] || { fail "a file this check compares is missing" "${f}"; finish "manual Linux install"; }
done

require_python "the manual Linux install could not be compared" "manual Linux install"
if ! pinned_values_load; then
    fail "the pinned values could not be read, so no apt_url or dnf_url location can be compared" \
         "e2e/tier1/pinned_values.sh names what is wrong with the pins"
    finish "manual Linux install"
fi

# pin_location <name>  ->  the rendered pin, or nothing when nothing pins that name
pin_location() { pinned_value "$1" 2>/dev/null || true; }

# --- the dictionary side ---------------------------------------------------------------------------
yaml_field() { sed -nE "s/.*[{,][[:space:]]*$1:[[:space:]]*\"?([^\", }]*)\"?[[:space:]]*[,}].*/\1/p" <<<"$2"; }

declare -A default_on=()
while read -r key value; do
    default_on["${key#install_}"]="${value}"
done < <({ yaml_bool_toggles "${ALL_VARS}"; yaml_bool_toggles "${LINUX_VARS}"; } | grep '^install_')

family_mapping_lines() {
    tr -d '\r' <"$1" | awk '/^software_mapping:/ { inside = 1; next } /^[^[:space:]#]/ { inside = 0 } inside && /^  [a-z0-9_]+: \{/'
}

# family_of_derivative <id>  ->  Archlinux, Debian or RedHat from the fixture's ID_LIKE, or nothing
family_of_derivative() {
    local fixture like
    fixture="$(grep -lE "^ID=\"?$1\"?$" "${FIXTURE_DIR}"/* 2>/dev/null | sed -n 1p || true)"
    [[ -n "${fixture}" ]] || return 0
    like=" $(sed -nE 's/^ID_LIKE="?([^"]*)"?$/\1/p' "${fixture}") "
    case "${like}" in
        *" arch "*) echo Archlinux ;;
        *" debian "* | *" ubuntu "*) echo Debian ;;
        *" fedora "* | *" rhel "*) echo RedHat ;;
    esac
}

# mapping_token <key> <line>  ->  the name or location the manual route has to install, or nothing
mapping_token() {
    local key="$1" line="$2" manager package url
    manager="$(yaml_field manager "${line}")"
    [[ "${MANUAL_MANAGERS}" == *" ${manager} "* ]] || return 0
    package="$(yaml_field package "${line}")"
    url="$(yaml_field url "${line}")"
    case "${manager}" in
        apt_url) [[ -n "${url}" ]] || url="$(pin_location "${key}_url")" ;;
        dnf_url) [[ -n "${url}" ]] || url="$(pin_location "${key}_rpm_url")"
                 [[ -n "${url}" ]] || url="$(pin_location "${key}_url")" ;;
        *) echo "${package}"; return 0 ;;
    esac
    if [[ -z "${url}" ]]; then
        echo "unresolved:${manager}:${key}"
    else
        echo "url:${url}"
    fi
}

declare -A derivatives_of=()
for f in "${VARS_DIR}"/derivatives/*.yaml; do
    [[ -f "${f}" ]] || continue
    id="$(basename "${f}" .yaml)"
    family="$(family_of_derivative "${id}")"
    if [[ -z "${family}" ]]; then
        fail "${id}: no os-release fixture in e2e/tier1/os_release_fixtures names a family this check knows for it, so its mappings were not compared" "${f}"
        continue
    fi
    derivatives_of["${family}"]+=" ${id}"
done

# --- the manual side -------------------------------------------------------------------------------
# script_tokens <script>  ->  one installed name, or pin:<name> for a pinned location, per line
#
# Read from the shapes these scripts install through: an array or a scalar named *_PACKAGES, *_APPS or
# *_SUITE, the literal list of a for loop, the first argument of install_one, and a sudo pacman -S,
# apt-get install, dnf install or snap install with literal arguments. A variable assigned from
# pinned_value stands for its pin wherever a for loop or install_one names it.
script_tokens() {
    local pins
    pins="$(tr -d '\r' <"$1" | sed -nE 's/^[[:space:]]*([A-Z_]+)="\$\(pinned_value ([a-z0-9_]+)\)"$/\1=\2/p' | tr '\n' ' ')"
    tr -d '\r' <"$1" | awk -v pins="${pins}" '
        function emit_words(text,    n, w, i) {
            n = split(text, w, /[[:space:]]+/)
            for (i = 1; i <= n; i++) if (w[i] != "") print w[i]
        }
        function pin_refs(text,    rest, name, found) {
            found = 0
            rest = text
            while (match(rest, /\$\{?[A-Z_]+\}?/)) {
                name = substr(rest, RSTART, RLENGTH)
                gsub(/[${}]/, "", name)
                if (name in pin) { print "pin:" pin[name]; found = 1 }
                rest = substr(rest, RSTART + RLENGTH)
            }
            return found
        }
        BEGIN {
            n = split(pins, p, " ")
            for (i = 1; i <= n; i++) { split(p[i], kv, "="); pin[kv[1]] = kv[2] }
        }
        /^[[:space:]]*#/ { next }
        in_array {
            line = $0
            if (index(line, ")")) { sub(/\).*/, "", line); in_array = 0 }
            emit_words(line)
            next
        }
        /^[[:space:]]*[A-Z_]+(_PACKAGES|_APPS|_SUITE)=\(/ {
            line = $0
            sub(/^[^(]*\(/, "", line)
            if (index(line, ")")) sub(/\).*/, "", line); else in_array = 1
            emit_words(line)
            next
        }
        /^[[:space:]]*[A-Z_]+(_PACKAGES|_APPS|_SUITE)="[^"$]*"$/ {
            line = $0
            sub(/^[^"]*"/, "", line); sub(/"$/, "", line)
            emit_words(line)
            next
        }
        /^[[:space:]]*for [a-z_]+ in .*; do/ {
            line = $0
            sub(/^[[:space:]]*for [a-z_]+ in /, "", line); sub(/; do.*/, "", line)
            if (index(line, "$(")) next
            n = split(line, w, /[[:space:]]+/)
            for (i = 1; i <= n; i++) {
                if (w[i] == "" || index(w[i], "[@]") || w[i] ~ /^\//) continue
                if (w[i] ~ /^"?\$/) pin_refs(w[i]); else print w[i]
            }
            next
        }
        /^[[:space:]]*install_one / {
            if (pin_refs($0)) next
            split($0, w, /[[:space:]]+/)
            first = (w[1] == "") ? w[3] : w[2]
            if (first !~ /^["$]/) print first
            next
        }
        /^[[:space:]]*sudo (pacman -S[a-z]*|apt-get install|dnf install|snap install) / {
            line = $0
            sub(/[<|;&].*/, "", line)
            sub(/^[[:space:]]*sudo (pacman -S[a-z]*|apt-get install|dnf install|snap install) /, "", line)
            n = split(line, w, /[[:space:]]+/)
            for (i = 1; i <= n; i++) if (w[i] != "" && w[i] !~ /^[-"$\/]/) print w[i]
        }
    ' | sort -u
}

# guide_tokens <guide>  ->  one name, or url:<location> for a downloaded .deb or .rpm, per line
#
# Read from every install command on the page, in a table cell or a code block alike: pacman -S,
# yay -S, paru -S, apt-get install, dnf install, snap install, flatpak install -y flathub, a one-line
# for loop over any of those, a .deb or .rpm downloaded to /tmp with curl, and dnf install of a URL.
guide_tokens() {
    tr -d '\r' <"$1" | awk '
        function words_after(text,    seg, n, w, i) {
            seg = text
            if (match(seg, /[`|;&)\\*<>"]/)) seg = substr(seg, 1, RSTART - 1)
            n = split(seg, w, /[[:space:]]+/)
            for (i = 1; i <= n; i++) {
                if (w[i] == "" || w[i] ~ /^[-$\/]/) continue
                if (w[i] ~ /^https?:\/\//) print "url:" w[i]; else print w[i]
            }
        }
        function scan(text, pattern,    rest) {
            rest = text
            while (match(rest, pattern)) {
                rest = substr(rest, RSTART + RLENGTH)
                words_after(rest)
            }
        }
        {
            line = $0
            rest = line
            while (match(rest, /for [a-z_]+ in [^;`]+; do (sudo )?(pacman|yay|paru|apt-get|dnf|snap|flatpak) /)) {
                loop = substr(rest, RSTART, RLENGTH)
                rest = substr(rest, RSTART + RLENGTH)
                sub(/^for [a-z_]+ in /, "", loop); sub(/;.*/, "", loop)
                n = split(loop, w, /[[:space:]]+/)
                for (i = 1; i <= n; i++) if (w[i] != "" && w[i] !~ /^["$\/]/) print w[i]
            }
            scan(line, "pacman -S[a-z]* ")
            scan(line, "(yay|paru) -S ")
            scan(line, "apt-get install ")
            scan(line, "dnf install ")
            scan(line, "snap install ")
            scan(line, "flatpak install -y flathub ")
            rest = line
            while (match(rest, /curl -fsSLo \/tmp\/[^ ]+\.(deb|rpm) https?:\/\/[^ `]+/)) {
                download = substr(rest, RSTART, RLENGTH)
                rest = substr(rest, RSTART + RLENGTH)
                sub(/^curl -fsSLo [^ ]+ /, "", download)
                print "url:" download
            }
        }
    ' | sort -u
}

# --- the documented differences --------------------------------------------------------------------
declare -A allowed=() allowance_used=()
while read -r a_family a_name a_source a_reason; do
    [[ -z "${a_family}" || "${a_family}" == \#* ]] && continue
    if [[ -z "${a_reason}" ]]; then
        fail "a line in manual_linux_install_allowed.txt gives no reason" "${a_family} ${a_name} ${a_source}"
        continue
    fi
    needle="${a_name#pin:}"
    if [[ "${a_source}" != "-" && ! -f "${ANSIBLE_DIR}/${a_source}" ]]; then
        fail "${a_family} ${a_name}: the allowance names ${a_source}, which does not exist under setup/ansible" "${ALLOWED_FILE}"
        continue
    fi
    if [[ "${a_source}" != "-" ]] && ! grep -qwF -- "${needle}" "${ANSIBLE_DIR}/${a_source}"; then
        fail "${a_family} ${a_name}: the allowance says setup/ansible/${a_source} installs it, and that file no longer names it" "${ALLOWED_FILE}"
        continue
    fi
    if [[ "${a_name}" == pin:* ]]; then
        location="$(pin_location "${needle}")"
        if [[ -z "${location}" ]]; then
            fail "${a_family} ${a_name}: the allowance names a pin nothing defines" "${ALLOWED_FILE}"
            continue
        fi
        a_name="url:${location}"
    fi
    allowed["${a_family}|${a_name}"]=1
done < <(tr -d '\r' <"${ALLOWED_FILE}")

# --- the comparison --------------------------------------------------------------------------------
for family in "${FAMILIES[@]}"; do
    script="${SCRIPT_OF[${family}]}"
    guide="${GUIDE_OF[${family}]}"
    script_rel="${script#"${REPO_ROOT}"/}"
    guide_rel="${guide#"${REPO_ROOT}"/}"

    declare -A family_line=() expected=() mapped=()
    while IFS= read -r line; do
        family_line["$(sed -nE 's/^  ([a-z0-9_]+):.*/\1/p' <<<"${line}")"]="${line}"
    done < <(family_mapping_lines "${VARS_DIR}/${family}.yaml")
    if [[ ${#family_line[@]} -eq 0 ]]; then
        fail "${family}: no mapping could be read out of vars/${family}.yaml, so nothing here means anything" "${VARS_DIR}/${family}.yaml"
        unset family_line expected mapped
        continue
    fi

    variants=("") unresolved=()
    for id in ${derivatives_of[${family}]:-}; do variants+=("${id}"); done
    for variant in "${variants[@]}"; do
        declare -A merged=()
        for key in "${!family_line[@]}"; do merged["${key}"]="${family_line[${key}]}"; done
        if [[ -n "${variant}" ]]; then
            while IFS= read -r line; do
                merged["$(sed -nE 's/^  ([a-z0-9_]+):.*/\1/p' <<<"${line}")"]="${line}"
            done < <(derivative_mapping_lines "${VARS_DIR}/derivatives/${variant}.yaml" | tr -d '\r')
        fi
        for key in "${!merged[@]}"; do
            token="$(mapping_token "${key}" "${merged[${key}]}")"
            [[ -z "${token}" ]] && continue
            if [[ "${token}" == unresolved:* ]]; then
                unresolved+=("${token#unresolved:}")
                continue
            fi
            mapped["${token}"]=1
            [[ "${default_on[${key}]:-false}" == "true" ]] && expected["${token}"]=1
        done
        unset merged
    done
    while read -r c_key c_name; do
        [[ -n "${c_name}" ]] || continue
        [[ -v "family_line[${c_key}]" ]] || continue
        mapped["${c_name}"]=1
        if [[ "${default_on[${c_key}]:-false}" == "true" ]]; then expected["${c_name}"]=1; fi
    done < <(companion_packages_of "${VARS_DIR}/${family}.yaml")
    if [[ ${#unresolved[@]} -gt 0 ]]; then
        fail "${family}: mappings whose download location resolves to nothing, so the manual route cannot fetch them" \
             "$(printf '%s\n' "${unresolved[@]}" | sort -u | tr '\n' ' ')"
    fi
    label="vars/${family}.yaml${derivatives_of[${family}]:+ with${derivatives_of[${family}]} merged over it}"

    declare -A script_has=() guide_has=()
    while IFS= read -r token; do
        [[ -z "${token}" ]] && continue
        if [[ "${token}" == pin:* ]]; then
            location="$(pin_location "${token#pin:}")"
            [[ -n "${location}" ]] && token="url:${location}" || token="unresolved-pin:${token#pin:}"
        fi
        script_has["${token}"]=1
    done < <(script_tokens "${script}")
    while IFS= read -r token; do
        [[ -n "${token}" ]] && guide_has["${token}"]=1
    done < <(guide_tokens "${guide}")

    if [[ ${#script_has[@]} -eq 0 ]]; then
        fail "${family}: no installed package could be read out of ${script_rel}, so this check proves nothing" "${script}"
    else
        missing=()
        for token in "${!expected[@]}"; do [[ -v "script_has[${token}]" ]] || missing+=("${token}"); done
        if [[ ${#missing[@]} -eq 0 ]]; then
            pass "${family}: ${script_rel} installs every one of the ${#expected[@]} mappings on by default in ${label}"
        else
            fail "${family}: ${script_rel} does not install mappings that are on by default in ${label}" \
                 "$(printf '%s\n' "${missing[@]}" | sort | tr '\n' ' ')"
        fi

        stray=()
        for token in "${!script_has[@]}"; do
            if [[ -v "expected[${token}]" ]]; then continue; fi
            if [[ -v "allowed[${family}|${token}]" ]]; then allowance_used["${family}|${token}"]=1; continue; fi
            stray+=("${token}")
        done
        if [[ ${#stray[@]} -eq 0 ]]; then
            pass "${family}: ${script_rel} installs nothing beyond those mappings except the documented differences"
        else
            fail "${family}: ${script_rel} installs names no mapping on by default has, and manual_linux_install_allowed.txt does not explain" \
                 "$(printf '%s\n' "${stray[@]}" | sort | tr '\n' ' ')"
        fi
    fi

    if [[ ${#guide_has[@]} -eq 0 ]]; then
        fail "${family}: no install command could be read out of ${guide_rel}, so this check proves nothing" "${guide}"
    else
        missing=()
        for token in "${!expected[@]}"; do [[ -v "guide_has[${token}]" ]] || missing+=("${token}"); done
        if [[ ${#missing[@]} -eq 0 ]]; then
            pass "${family}: ${guide_rel} carries an install command for every one of the ${#expected[@]} mappings on by default"
        else
            fail "${family}: ${guide_rel} has no install command for mappings that are on by default in ${label}" \
                 "$(printf '%s\n' "${missing[@]}" | sort | tr '\n' ' ')"
        fi

        stray=()
        for token in "${!guide_has[@]}"; do
            if [[ -v "mapped[${token}]" ]]; then continue; fi
            if [[ -v "allowed[${family}|${token}]" ]]; then allowance_used["${family}|${token}"]=1; continue; fi
            stray+=("${token}")
        done
        if [[ ${#stray[@]} -eq 0 ]]; then
            pass "${family}: every install command in ${guide_rel} names a mapping in ${label} or a documented difference"
        else
            fail "${family}: ${guide_rel} installs names ${label} does not map, and manual_linux_install_allowed.txt does not explain" \
                 "$(printf '%s\n' "${stray[@]}" | sort | tr '\n' ' ')"
        fi
    fi

    unset family_line expected mapped script_has guide_has
done

# --- the services and groups the playbook sets up after installing ----------------------------------
# virtualization_config enables and starts docker.service after installing Docker, and every script
# and guide installed Docker without ever starting it, so `docker run` failed with "Cannot connect
# to the Docker daemon" on Fedora and Arch, whose packages do not start it themselves.
#
# The scripts run under set -e, so a usermod or systemctl that fails because its package did not
# install ends the script there, before the list of packages that did not install, which is the one
# thing the script promises to print. debian-ubuntu/install.sh had `sudo usermod -aG plugdev` with no
# guard while fedora/install.sh had one. Every such line carries the `|| printf '   Skipped: ...'`
# the docker group line already had.
for family in "${FAMILIES[@]}"; do
    script="${SCRIPT_OF[${family}]}"
    guide="${GUIDE_OF[${family}]}"
    script_rel="${script#"${REPO_ROOT}"/}"
    guide_rel="${guide#"${REPO_ROOT}"/}"

    if grep -qE "^[[:space:]]*sudo systemctl enable --now docker(\.service)?[[:space:]]+\|\|[[:space:]]+printf '   Skipped: " <<<"$(tr -d '\r' <"${script}")"; then
        pass "${family}: ${script_rel} enables and starts docker.service, and says so when Docker did not install"
    else
        fail "${family}: ${script_rel} installs Docker and never enables and starts docker.service, guarded like the docker group line" \
             "expected a line: sudo systemctl enable --now docker || printf '   Skipped: ...'"
    fi
    if grep -qE '^[[:space:]]*sudo systemctl enable --now docker(\.service)?[[:space:]]*$' <<<"$(tr -d '\r' <"${guide}")"; then
        pass "${family}: ${guide_rel} tells the reader to enable and start docker.service"
    else
        fail "${family}: ${guide_rel} installs Docker and never tells the reader to enable and start docker.service" \
             "expected a code block holding: sudo systemctl enable --now docker"
    fi

    unguarded="$(tr -d '\r' <"${script}" | grep -nE '^[[:space:]]*(sudo[[:space:]]+)?(usermod|systemctl)[[:space:]]' \
        | grep -vE "\|\|[[:space:]]+printf '   Skipped: " || true)"
    service_lines="$(tr -d '\r' <"${script}" | grep -cE '^[[:space:]]*(sudo[[:space:]]+)?(usermod|systemctl)[[:space:]]' || true)"
    if [[ "${service_lines}" -eq 0 ]]; then
        fail "${family}: no usermod or systemctl line could be read out of ${script_rel}, so this proves nothing" "${script}"
    elif [[ -z "${unguarded}" ]]; then
        pass "${family}: all ${service_lines} usermod and systemctl lines in ${script_rel} report a skip instead of ending the script under set -e"
    else
        fail "${family}: ${script_rel} has usermod or systemctl lines that end the script under set -e when their package did not install" \
             "$(tr '\n' ' ' <<<"${unguarded}")"
    fi
done

unused=()
for entry in "${!allowed[@]}"; do
    [[ -v "allowance_used[${entry}]" ]] || unused+=("${entry}")
done
if [[ ${#allowed[@]} -eq 0 ]]; then
    fail "manual_linux_install_allowed.txt allows nothing, which cannot be true while the scripts install their own prerequisites" "${ALLOWED_FILE}"
elif [[ ${#unused[@]} -eq 0 ]]; then
    pass "every one of the ${#allowed[@]} documented differences in manual_linux_install_allowed.txt is still used"
else
    fail "documented differences that neither a script nor a guide uses any more, so delete them" \
         "$(printf '%s\n' "${unused[@]}" | sort | tr '\n' ' ')"
fi

finish "manual Linux install"
