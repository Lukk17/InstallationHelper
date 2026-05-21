#!/usr/bin/env bash
#
# Installation Helper bootstrap wizard (Linux / macOS).
#
# Usage:
#   setup.sh                          # interactive wizard (gum-driven)
#   setup.sh --help                   # this message
#   setup.sh --profile <name>         # apply profiles/<name>.yaml, skip selection
#   setup.sh --non-interactive        # use group_vars defaults, no prompts
#   setup.sh --no-color               # disable ANSI colour
#   setup.sh --skip-system-upgrade    # don't run full system upgrade before Ansible
#
# Exit codes:
#   0   success
#   1   bootstrap or playbook failure
#   2   bad usage
#   130 cancelled (SIGINT/SIGQUIT)

set -euo pipefail
IFS=$'\n\t'

# Force a UTF-8 locale so that the few non-ASCII glyphs we render don't
# get mojibake'd into CJK fragments under a POSIX/C locale. Falls back
# silently if the locale is not generated on the host.
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

# Honour NO_COLOR (https://no-color.org/) and non-TTY stdout.
if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
    USE_COLOR=false
else
    USE_COLOR=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
ALL_VARS="${ANSIBLE_DIR}/group_vars/all.yaml"
LINUX_VARS="${ANSIBLE_DIR}/group_vars/linux.yaml"
MACOS_VARS="${ANSIBLE_DIR}/group_vars/macos.yaml"

# Variables hidden from the wizard's per-app checklist. These are baseline
# system settings, not optional software. They live in group_vars (linux.yaml /
# macos.yaml) and stay at whatever they default to there.
EXCLUDED_VARS="non_root_user|non_root_home|allow_callback_failure|default_wallpaper|set_custom_wallpaper|install_system_core|setup_tmpfs|toggle_wayland_nvidia|setup_zsh|setup_karabiner|setup_finder_defaults|setup_hibernate|setup_systemd_boot|setup_grub|remove_distro_grub|remove_distro_systemd_boot"
DE_KEYS=("install_kde_plasma" "configure_kde_plasma" "install_gnome" "configure_gnome")

# CLI options
OPT_PROFILE=""
OPT_NON_INTERACTIVE=false
OPT_SKIP_SYSTEM_UPGRADE=false

usage() { sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)         usage; exit 0 ;;
            --profile)         shift; OPT_PROFILE="${1:-}"; [[ -z "${OPT_PROFILE}" ]] && { echo "ERROR: --profile requires a value" >&2; exit 2; } ;;
            --profile=*)       OPT_PROFILE="${1#--profile=}" ;;
            --non-interactive) OPT_NON_INTERACTIVE=true ;;
            --no-color)        USE_COLOR=false ;;
            --skip-system-upgrade) OPT_SKIP_SYSTEM_UPGRADE=true ;;
            *)                 echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 2 ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------------------
# Signal handling
# ---------------------------------------------------------------------------

on_err() {
    local rc=$?
    echo >&2
    echo "ERROR: setup.sh aborted (exit $rc) at line ${BASH_LINENO[0]} (in function: ${FUNCNAME[1]:-MAIN})" >&2
    echo "Rerun with: bash -x setup/setup.sh   for a full trace." >&2
}
trap on_err ERR

# INT/QUIT/TERM/HUP set a flag rather than exiting directly, so a gum picker
# can finish drawing its exit screen first. check_int_or_die() then triggers
# the goodbye splash and a clean shutdown from a sensible place.
INT_RECEIVED=false
trap 'INT_RECEIVED=true' INT QUIT TERM HUP

# Always print at least one line on startup so the user knows the script started.
say() { printf '  >> %s\n' "$1"; }

goodbye_splash() {
    echo
    if command -v gum &>/dev/null && ${USE_COLOR}; then
        gum style \
            --border double --margin "1 2" --padding "1 4" --align center \
            --border-foreground 11 --foreground 11 \
            "Setup cancelled" \
            "" \
            "No changes were made to your system." \
            "Run ./setup.sh again whenever you're ready."
    else
        cat <<'EOF'

    +------------------------------------------+
    |                                          |
    |             Setup cancelled              |
    |                                          |
    |   No changes were made to your system.   |
    |   Run ./setup.sh again when ready.       |
    |                                          |
    +------------------------------------------+

EOF
    fi
    echo
}

# Call after every interactive screen. If a SIGINT was delivered while a gum
# picker was up, abort with the goodbye splash. Esc inside a picker does NOT
# raise SIGINT — it just produces an empty SCREEN_RESULT, so the state machine
# can use that for back-navigation without triggering this.
check_int_or_die() {
    if ${INT_RECEIVED}; then
        INT_RECEIVED=false
        goodbye_splash
        exit 130
    fi
}

# ---------------------------------------------------------------------------
# OS detection (handles WSL)
# ---------------------------------------------------------------------------

detect_os() {
    IS_WSL=false
    if grep -qi microsoft /proc/version 2>/dev/null; then
        IS_WSL=true
    fi
    if [[ "$(uname)" == "Darwin" ]]; then
        OS_FAMILY="Darwin"; DISTRO="macOS"; OS_VARS_FILE="${MACOS_VARS}"
        return 0
    fi
    if [[ ! -f /etc/os-release ]]; then
        OS_FAMILY="Linux"; DISTRO="Unknown Linux"; OS_VARS_FILE="${LINUX_VARS}"
        return 0
    fi
    # Source /etc/os-release in a subshell so we read NAME/ID/ID_LIKE without
    # polluting the parent scope. Using a subshell + echo avoids the
    # grep|head|cut|tr pipe that trips `pipefail` when a field is missing.
    local _name _id _id_like
    _name=$(. /etc/os-release 2>/dev/null; printf '%s\n' "${NAME:-Linux}")
    _id=$(. /etc/os-release 2>/dev/null; printf '%s\n' "${ID:-}")
    _id_like=$(. /etc/os-release 2>/dev/null; printf '%s\n' "${ID_LIKE:-}")
    DISTRO="${_name:-Linux}"
    ${IS_WSL} && DISTRO="${DISTRO} (WSL)"
    case "${_id_like:-${_id:-}}" in
        *arch*)                     OS_FAMILY="Archlinux" ;;
        *fedora*|*rhel*|*centos*)   OS_FAMILY="RedHat" ;;
        *debian*|*ubuntu*)          OS_FAMILY="Debian" ;;
        *)
            case "${_id:-}" in
                arch)                        OS_FAMILY="Archlinux" ;;
                fedora|rhel|centos)          OS_FAMILY="RedHat" ;;
                ubuntu|debian|linuxmint|pop) OS_FAMILY="Debian" ;;
                *)                           OS_FAMILY="Linux" ;;
            esac ;;
    esac
    OS_VARS_FILE="${LINUX_VARS}"
}

# ---------------------------------------------------------------------------
# Dependency bootstrap — Ansible, collections, gum
# ---------------------------------------------------------------------------

ensure_ansible() {
    if command -v ansible-playbook &>/dev/null; then
        say "Ansible: already installed ($(ansible-playbook --version 2>/dev/null | head -1))"
        return 0
    fi
    say "Ansible not found - installing for ${OS_FAMILY}..."
    case "${OS_FAMILY}" in
        Debian)
            sudo apt-get update -q
            if command -v add-apt-repository &>/dev/null || apt-cache show software-properties-common &>/dev/null 2>&1; then
                sudo apt-get install -y software-properties-common
                sudo add-apt-repository --yes --update ppa:ansible/ansible 2>/dev/null || true
            fi
            sudo apt-get install -y ansible ;;
        RedHat)    sudo dnf install -y ansible ;;
        Archlinux)
            # Arch is rolling-release and does not support partial upgrades.
            # `pacman -S ansible` against a stale local db produces 404s from
            # every mirror because the recorded package versions have already
            # been cycled out. Use -Syu to refresh the db AND upgrade
            # everything in one transaction before installing the new package.
            say "Arch: syncing package database and applying pending upgrades (pacman -Syu)..."
            sudo pacman -Syu --noconfirm --needed ansible ;;
        Darwin)    brew install ansible ;;
        *) echo "ERROR: Cannot auto-install Ansible on ${OS_FAMILY}. Install manually and re-run." >&2; exit 1 ;;
    esac
}

# Full system upgrade BEFORE Ansible takes over. Running natively here gives
# the user live per-package output in their terminal, instead of the Ansible
# raw task's heartbeat. The corresponding playbook task stays in place as a
# safety net; on a freshly-upgraded host it becomes a no-op (0 packages).
system_upgrade() {
    if [[ "${OPT_SKIP_SYSTEM_UPGRADE}" == true ]]; then
        say "Skipping system upgrade (--skip-system-upgrade)."
        return 0
    fi
    say "Running full system upgrade before Ansible (skip with --skip-system-upgrade)..."
    case "${OS_FAMILY}" in
        Debian)
            sudo DEBIAN_FRONTEND=noninteractive \
                 APT_LISTCHANGES_FRONTEND=none \
                 NEEDRESTART_MODE=a \
                 NEEDRESTART_SUSPEND=1 \
                 apt-get update
            sudo DEBIAN_FRONTEND=noninteractive \
                 APT_LISTCHANGES_FRONTEND=none \
                 NEEDRESTART_MODE=a \
                 NEEDRESTART_SUSPEND=1 \
                 apt-get -y \
                   -o DPkg::Lock::Timeout=300 \
                   -o Dpkg::Options::=--force-confdef \
                   -o Dpkg::Options::=--force-confold \
                   full-upgrade
            sudo apt-get -y autoremove ;;
        RedHat)
            sudo dnf -y upgrade --refresh ;;
        Archlinux)
            sudo pacman -Syu --noconfirm ;;
        Darwin)
            brew update
            brew upgrade ;;
        *)
            say "No system upgrade path defined for ${OS_FAMILY}; skipping." ;;
    esac
}

ensure_prereqs() {
    # curl + gpg + ca-certificates are needed to fetch the gum repo key.
    # Minimal WSL Debian images do not ship them by default.
    local missing=()
    command -v curl &>/dev/null || missing+=(curl)
    command -v gpg  &>/dev/null || missing+=(gnupg)
    if [[ ${#missing[@]} -eq 0 ]]; then return 0; fi
    say "Installing prerequisites: ${missing[*]} (this needs sudo)..."
    case "${OS_FAMILY}" in
        Debian)
            sudo apt-get update -q
            sudo apt-get install -y ca-certificates "${missing[@]}"
            ;;
        RedHat)    sudo dnf install -y ca-certificates "${missing[@]}" ;;
        Archlinux) sudo pacman -Syu --noconfirm --needed ca-certificates "${missing[@]}" ;;
        Darwin)    : ;;  # curl/gpg ship with macOS
        *) echo "ERROR: Install curl + gnupg manually on ${OS_FAMILY} and re-run." >&2; exit 1 ;;
    esac
}

ensure_gum() {
    if command -v gum &>/dev/null; then
        say "gum: already installed ($(gum --version 2>/dev/null))"
        return 0
    fi
    ensure_prereqs
    say "gum (charm.sh) not found - installing for ${OS_FAMILY} (this needs sudo)..."
    case "${OS_FAMILY}" in
        Debian)
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/charm.gpg
            echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
                | sudo tee /etc/apt/sources.list.d/charm.list >/dev/null
            sudo apt-get update -q
            sudo apt-get install -y gum
            ;;
        RedHat)
            printf '%s\n' \
                '[charm]' \
                'name=Charm' \
                'baseurl=https://repo.charm.sh/yum/' \
                'enabled=1' \
                'gpgcheck=1' \
                'gpgkey=https://repo.charm.sh/yum/gpg.key' \
                | sudo tee /etc/yum.repos.d/charm.repo >/dev/null
            sudo dnf install -y gum
            ;;
        Archlinux) sudo pacman -Syu --noconfirm --needed gum ;;
        Darwin)    brew install gum ;;
        *) echo "ERROR: Cannot auto-install gum on ${OS_FAMILY}. See https://github.com/charmbracelet/gum#installation" >&2; exit 1 ;;
    esac
    command -v gum &>/dev/null || { echo "ERROR: gum install completed but binary not in PATH." >&2; exit 1; }
    say "gum: installed ($(gum --version 2>/dev/null))"
}

install_collections() {
    local req_file="${ANSIBLE_DIR}/requirements.yaml"
    local required installed missing=0
    required=$(grep -E '^\s*-\s*name:\s*' "${req_file}" | awk '{print $NF}')
    if command -v ansible-galaxy &>/dev/null; then
        installed=$(ansible-galaxy collection list 2>/dev/null | awk '/^[a-z]/{print $1}' || true)
        for coll in ${required}; do
            grep -qx "${coll}" <<<"${installed}" || missing=1
        done
        if [[ ${missing} -eq 0 ]]; then
            say "Ansible collections: already installed"
            return 0
        fi
    fi
    # Run ansible-galaxy directly without `gum spin` so download progress and
    # any "could not resolve version" errors are visible. A spinner here hid
    # a real Galaxy resolution failure for ~hours of user time.
    say "Installing Ansible collections..."
    if ! ansible-galaxy collection install -r "${req_file}"; then
        echo "ERROR: ansible-galaxy collection install failed. See output above." >&2
        return 1
    fi
    say "Ansible collections: installed"
}

check_requirements() {
    if [[ ! -d "${ANSIBLE_DIR}" ]]; then
        echo "ERROR: Ansible directory not found at ${ANSIBLE_DIR}" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Toggle and profile loading
# ---------------------------------------------------------------------------

format_label() {
    local key="${1#install_}"; key="${key#setup_}"; key="${key#configure_}"
    key="${key//_/ }"
    echo "${key^}"
}

is_de_key() {
    local k="$1"
    for dk in "${DE_KEYS[@]}"; do [[ "${dk}" == "${k}" ]] && return 0; done
    return 1
}

read_boolean_toggles() {
    local file="$1"
    grep -E '^[a-z_]+: (true|false)' "${file}" 2>/dev/null \
        | grep -vE "^(${EXCLUDED_VARS}):" \
        | sed 's/: true$/ ON/;s/: false$/ OFF/'
}

# Populated at startup — no I/O between dialogs.
PRELOADED_ITEMS=()   # parallel arrays: key label state ; flattened triplets
PRELOADED_KEYS=()    # ordered keys (parallel to PRELOADED_ITEMS / 3)

preload_toggles() {
    local all_toggles=()
    while IFS= read -r line; do all_toggles+=("${line}"); done \
        < <(read_boolean_toggles "${ALL_VARS}")
    while IFS= read -r line; do
        local k="${line%% *}"
        local seen=false
        for t in "${all_toggles[@]}"; do [[ "${t%% *}" == "${k}" ]] && seen=true && break; done
        [[ "${seen}" == false ]] && all_toggles+=("${line}")
    done < <(read_boolean_toggles "${OS_VARS_FILE}")

    PRELOADED_ITEMS=(); PRELOADED_KEYS=()
    for entry in "${all_toggles[@]}"; do
        local key="${entry%% *}" val="${entry##* }"
        is_de_key "${key}" && continue
        local label; label=$(format_label "${key}")
        PRELOADED_ITEMS+=("${key}" "${label}" "${val}")
        PRELOADED_KEYS+=("${key}")
    done
}

# Profile metadata, parallel arrays
PROF_NAMES=()        # display name (Title Case)
PROF_FILES=()        # basename without .yaml (or "" for Default)
PROF_DESCS=()        # one-line description
PROF_COUNTS=()       # enabled-package count
PROF_STATES=()       # space-separated 0/1 per PRELOADED_KEYS index

load_profiles() {
    PROF_NAMES+=("Default")
    PROF_FILES+=("")
    PROF_DESCS+=("All software from group_vars defaults")
    local cnt=0 st=""
    for (( i=0; i<${#PRELOADED_KEYS[@]}; i++ )); do
        if [[ "${PRELOADED_ITEMS[$((i*3+2))]}" == "ON" ]]; then
            cnt=$((cnt+1)); st+="${st:+ }1"
        else
            st+="${st:+ }0"
        fi
    done
    PROF_COUNTS+=("${cnt}"); PROF_STATES+=("${st}")

    for pfile in "${ANSIBLE_DIR}/profiles/"*.yaml; do
        [[ ! -f "${pfile}" ]] && continue
        local base; base=$(basename "${pfile}" .yaml)
        local raw_name="${base//_/ }"
        local name="" word
        for word in ${raw_name}; do name+="${name:+ }${word^}"; done
        PROF_NAMES+=("${name}")
        PROF_FILES+=("${base}")

        local desc=""
        while IFS= read -r line; do
            [[ "${line}" == "---" ]] && continue
            [[ "${line}" == \#* ]] && desc="${line#\# }" && break
            break
        done < "${pfile}"
        PROF_DESCS+=("${desc:-No description}")

        local pcnt=0 pst=""
        for (( i=0; i<${#PRELOADED_KEYS[@]}; i++ )); do
            local key="${PRELOADED_KEYS[$i]}"
            local val="${PRELOADED_ITEMS[$((i*3+2))]}"
            local ovr
            ovr=$(grep -m1 "^${key}:" "${pfile}" 2>/dev/null || true)
            if [[ -n "${ovr}" ]]; then
                [[ "${ovr}" == *"true"* ]] && val="ON" || val="OFF"
            fi
            if [[ "${val}" == "ON" ]]; then
                pcnt=$((pcnt+1)); pst+="${pst:+ }1"
            else
                pst+="${pst:+ }0"
            fi
        done
        PROF_COUNTS+=("${pcnt}"); PROF_STATES+=("${pst}")
    done
}

# ---------------------------------------------------------------------------
# gum-driven screens
#
# Every screen sets a SCREEN_RESULT variable (or empty on cancel).
# Cancel = empty SCREEN_RESULT = caller decides whether to back up or exit.
# ---------------------------------------------------------------------------

SCREEN_RESULT=""

# Pretty header. Uses `gum style` if available; falls back to plain text.
banner() {
    local title="$1"
    if command -v gum &>/dev/null && ${USE_COLOR}; then
        gum style \
            --border normal --margin "1 0" --padding "0 1" \
            --border-foreground 10 --foreground 10 \
            "${title}" "${DISTRO}"
    else
        printf '\n--- %s - %s ---\n\n' "${title}" "${DISTRO}"
    fi
}

pick_de() {
    banner "Step 1/3 - Desktop Environment"
    SCREEN_RESULT=$(gum choose \
        --header "What should the playbook do about your desktop environment?" \
        "skip  - leave my desktop environment alone" \
        "kde   - work with KDE Plasma (Wayland)" \
        "gnome - work with GNOME" \
        || true)
    check_int_or_die
    [[ -z "${SCREEN_RESULT}" ]] && return
    SCREEN_RESULT="${SCREEN_RESULT%% *}"
}

pick_de_action() {
    local de="$1" de_upper="${1^^}"
    banner "Step 1/3 - ${de_upper}: action"
    SCREEN_RESULT=$(gum choose \
        --header "What should the playbook do with ${de_upper}?" \
        "full       - install ${de_upper} packages AND apply theme/config" \
        "install    - install ${de_upper} packages only, skip theming" \
        "configure  - skip install, only apply theme to an existing ${de_upper}" \
        || true)
    check_int_or_die
    [[ -z "${SCREEN_RESULT}" ]] && return
    SCREEN_RESULT="${SCREEN_RESULT%% *}"
}

pick_review_mode() {
    banner "Step 2/3 - Software Selection"
    SCREEN_RESULT=$(gum choose \
        --header "How would you like to choose software?" \
        "defaults  - use group_vars settings as-is" \
        "customise - open checklist to toggle individual apps" \
        "profile   - load a preset profile" \
        || true)
    check_int_or_die
    [[ -z "${SCREEN_RESULT}" ]] && return
    SCREEN_RESULT="${SCREEN_RESULT%% *}"
}

# Multi-select software picker. `gum choose --no-limit` supports `--selected` for
# pre-selection (`gum filter` does not). Items already enabled in group_vars show
# up as pre-selected so the user only changes what they actually want to change.
pick_software() {
    banner "Customise software - arrows to move, Space to mark, Enter to confirm"

    local options=() preselect_csv="" i key label state
    for (( i=0; i<${#PRELOADED_KEYS[@]}; i++ )); do
        key="${PRELOADED_KEYS[$i]}"
        label="${PRELOADED_ITEMS[$((i*3+1))]}"
        state="${PRELOADED_ITEMS[$((i*3+2))]}"
        local line="${key} | ${label}"
        options+=("${line}")
        if [[ "${state}" == "ON" ]]; then
            preselect_csv+="${preselect_csv:+,}${line}"
        fi
    done

    local picked
    picked=$(gum choose \
        --no-limit \
        --header "arrows move | Space toggle | a select-all | A deselect-all | Enter confirm | Esc cancel" \
        --selected="${preselect_csv}" \
        --cursor.foreground=10 --selected.foreground=10 \
        "${options[@]}" \
        || true)
    check_int_or_die

    if [[ -z "${picked}" ]]; then
        SCREEN_RESULT=""; return
    fi
    # Strip the " | label" suffix from each picked line to recover the bare key.
    local _results=() _line
    while IFS= read -r _line; do
        [[ -n "${_line}" ]] && _results+=("${_line%% | *}")
    done <<<"${picked}"
    SCREEN_RESULT="${_results[*]}"
}

pick_profile() {
    banner "Step 2/3 - Load a profile"

    local lines=() i name desc cnt
    for (( i=0; i<${#PROF_NAMES[@]}; i++ )); do
        name="${PROF_NAMES[$i]}"
        desc="${PROF_DESCS[$i]}"
        cnt="${PROF_COUNTS[$i]}"
        lines+=("${name}  |  ${cnt} packages  |  ${desc}")
    done

    local picked
    picked=$(printf '%s\n' "${lines[@]}" \
        | gum choose --header "Pick a profile (Enter to apply, Esc to back out)" \
        || true)
    check_int_or_die
    [[ -z "${picked}" ]] && { SCREEN_RESULT=""; return; }

    # Map back to PROF_* index.
    local i
    for (( i=0; i<${#PROF_NAMES[@]}; i++ )); do
        if [[ "${picked}" == "${PROF_NAMES[$i]}  |"* ]]; then
            SCREEN_RESULT="${i}"
            return
        fi
    done
    SCREEN_RESULT=""
}

confirm_run() {
    local display_cmd="$1"
    banner "Step 3/3 - Ready to run"
    gum style --foreground 7 "${display_cmd}"
    echo
    if gum confirm "Run the playbook now?"; then
        SCREEN_RESULT="run"
    else
        SCREEN_RESULT=""
    fi
    check_int_or_die
}

# ---------------------------------------------------------------------------
# Main — interactive state machine
# ---------------------------------------------------------------------------

main_interactive() {
    local de_choice="skip" de_action="skip"
    local pkg_vars=() have_pkg_vars=false
    local state="de"

    while true; do
        case "${state}" in

            de)
                pick_de
                # Esc at the root screen = graceful goodbye (no previous step).
                if [[ -z "${SCREEN_RESULT}" ]]; then
                    goodbye_splash
                    exit 0
                fi
                de_choice="${SCREEN_RESULT}"
                if [[ "${de_choice}" == "skip" ]]; then
                    de_action="skip"
                    state="review"
                else
                    state="de_action"
                fi
                ;;

            de_action)
                pick_de_action "${de_choice}"
                # Esc here = back to DE picker.
                if [[ -z "${SCREEN_RESULT}" ]]; then state="de"; continue; fi
                de_action="${SCREEN_RESULT}"
                state="review"
                ;;

            review)
                pick_review_mode
                if [[ -z "${SCREEN_RESULT}" ]]; then
                    state=$([[ "${de_choice}" != "skip" ]] && echo "de_action" || echo "de")
                    continue
                fi
                case "${SCREEN_RESULT}" in
                    defaults)  pkg_vars=(); have_pkg_vars=false; state="confirm" ;;
                    customise) state="checklist" ;;
                    profile)   state="profile" ;;
                esac
                ;;

            checklist)
                pick_software
                if [[ -z "${SCREEN_RESULT}" ]]; then state="review"; continue; fi
                local -a selected_keys=()
                read -ra selected_keys <<<"${SCREEN_RESULT}"
                pkg_vars=()
                local key found sel
                for key in "${PRELOADED_KEYS[@]}"; do
                    found=false
                    for sel in "${selected_keys[@]+"${selected_keys[@]}"}"; do
                        [[ "${sel}" == "${key}" ]] && found=true && break
                    done
                    pkg_vars+=("${key}=$([[ "${found}" == true ]] && echo true || echo false)")
                done
                have_pkg_vars=true
                state="confirm"
                ;;

            profile)
                pick_profile
                if [[ -z "${SCREEN_RESULT}" ]]; then state="review"; continue; fi
                local idx="${SCREEN_RESULT}"
                local pfile="${PROF_FILES[${idx}]}"
                pkg_vars=()
                have_pkg_vars=false
                # "Default" profile has an empty file slot — no override needed.
                [[ -n "${pfile}" ]] && OPT_PROFILE="${pfile}"
                state="confirm"
                ;;

            confirm)
                # Build DE override vars from de_choice + de_action.
                #   skip       => no overrides (use group_vars defaults)
                #   full       => install_X=true, configure_X=true
                #   install    => install_X=true, configure_X=false
                #   configure  => install_X=false, configure_X=true
                local de_vars=()
                case "${de_choice}" in
                    kde)
                        case "${de_action}" in
                            full)      de_vars+=("install_kde_plasma=true"  "configure_kde_plasma=true")  ;;
                            install)   de_vars+=("install_kde_plasma=true"  "configure_kde_plasma=false") ;;
                            configure) de_vars+=("install_kde_plasma=false" "configure_kde_plasma=true")  ;;
                        esac ;;
                    gnome)
                        case "${de_action}" in
                            full)      de_vars+=("install_gnome=true"  "configure_gnome=true")  ;;
                            install)   de_vars+=("install_gnome=true"  "configure_gnome=false") ;;
                            configure) de_vars+=("install_gnome=false" "configure_gnome=true")  ;;
                        esac ;;
                    skip)
                        # Leave whatever's in group_vars/linux.yaml. No overrides.
                        ;;
                esac

                local all_extra=("${de_vars[@]+"${de_vars[@]}"}")
                [[ "${have_pkg_vars}" == true ]] && all_extra+=("${pkg_vars[@]}")

                local extra_str=""
                [[ ${#all_extra[@]} -gt 0 ]] \
                    && extra_str=$(printf ' %s' "${all_extra[@]}") && extra_str="${extra_str:1}"

                export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"
                local -a ansible_args=(
                    "${ANSIBLE_DIR}/site.yaml"
                    -i "localhost,"
                    -c local
                    -K
                )
                [[ -n "${OPT_PROFILE}" ]] && ansible_args+=(-e "@${ANSIBLE_DIR}/profiles/${OPT_PROFILE}.yaml")
                [[ -n "${extra_str}" ]] && ansible_args+=(--extra-vars "${extra_str}")

                local display_cmd
                display_cmd=$(printf 'ansible-playbook'; printf ' %q' "${ansible_args[@]}")

                confirm_run "${display_cmd}"
                if [[ -z "${SCREEN_RESULT}" ]]; then
                    state=$([[ "${have_pkg_vars}" == true ]] && echo "checklist" || echo "review")
                    continue
                fi

                echo
                echo "Running: ${display_cmd}"
                echo
                ansible-playbook "${ansible_args[@]}"
                exit $?
                ;;
        esac
    done
}

# Non-interactive entrypoint — used by --profile / --non-interactive.
run_non_interactive() {
    local -a ansible_args=("${ANSIBLE_DIR}/site.yaml" -i "localhost," -c local -K)
    if [[ -n "${OPT_PROFILE}" ]]; then
        local pfile="${ANSIBLE_DIR}/profiles/${OPT_PROFILE}.yaml"
        if [[ ! -f "${pfile}" ]]; then
            echo "ERROR: profile not found: ${pfile}" >&2
            exit 2
        fi
        ansible_args+=(-e "@${pfile}")
    fi
    export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"
    echo "Running: ansible-playbook $(printf '%q ' "${ansible_args[@]}")"
    ansible-playbook "${ansible_args[@]}"
}

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

parse_args "$@"

echo
echo "Installation Helper - bootstrap wizard"
echo "======================================"

if [[ "${EUID}" == "0" ]]; then
    echo "ERROR: Do not run as root - the script will prompt for sudo when needed." >&2
    exit 1
fi

check_requirements
detect_os
say "Detected OS: ${DISTRO} (family: ${OS_FAMILY})"
# Pre-create Ansible tmp + fact-cache dirs (ansible.cfg uses ~/.ansible/...).
# jsonfile fact cache fails on first run if its dir doesn't exist.
mkdir -p "${HOME}/.ansible/tmp" "${HOME}/.ansible/facts-cache"
ensure_ansible
system_upgrade

if [[ "${OPT_NON_INTERACTIVE}" == true || -n "${OPT_PROFILE}" ]]; then
    install_collections
    run_non_interactive
    exit $?
fi

ensure_gum
install_collections

say "Loading toggles..."
preload_toggles
say "Loading profiles..."
load_profiles
echo

main_interactive
