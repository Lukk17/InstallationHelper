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
#   setup.sh --passwordless-sudo      # drop Ansible's -K, for a machine with NOPASSWD sudo
#                                     # (a throwaway container or a hosted runner). Without it,
#                                     # every path prompts for the sudo password as it always has.
#
# Choosing without the menus. These reach the same code the interactive screens reach, so a
# scripted run and a hand-driven run produce the same playbook command. Any of them implies
# --non-interactive.
#
#   setup.sh --desktop-environment skip|kde|gnome    # what screen 1 asks
#   setup.sh --desktop-action full|install|configure # what screen 1 asks next, needs kde or gnome
#   setup.sh --software defaults|all|none            # the starting point for screen 2
#   setup.sh --enable <keys>                         # turn these on, comma separated
#   setup.sh --disable <keys>                        # turn these off, comma separated, wins over --enable
#   setup.sh --list-software                         # print every key --enable and --disable accept
#   setup.sh --print-command                         # print the resolved playbook command, run nothing
#
#   defaults means the group_vars values as they are, all means every selectable toggle on, and
#   none means every selectable toggle off so --enable can build a run up from nothing. An unknown
#   key is refused rather than ignored, because a typo that installs nothing while the run reports
#   success is this project's most repeated defect.
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

# Variables hidden from the wizard's checklist. Only two reasons qualify: the value
# is not a boolean the checklist could render, or getting it wrong costs you a working
# machine. Everything else belongs on the checklist, because a setting the user cannot
# reach is a setting they cannot work around when it breaks. setup_zsh used to be
# hidden here, defaults to true, and failed every install that had no font directory,
# with no way to opt out short of editing YAML. See docs/regression_ledger.md.
#
#   not booleans, or derived        non_root_user, non_root_home, default_wallpaper
#   logging switch, not software    allow_callback_failure
#   the bootstrap everything needs  install_system_core
#   needs swap plus a resume param  setup_hibernate
#   rewrites the bootloader         setup_systemd_boot, setup_grub, remove_distro_*
EXCLUDED_VARS="non_root_user|non_root_home|allow_callback_failure|default_wallpaper|install_system_core|setup_hibernate|setup_systemd_boot|setup_grub|remove_distro_grub|remove_distro_systemd_boot"

# System settings share the checklist with software, so their labels have to say what
# they do. "Zsh" next to "Chrome" tells the user nothing about which one reconfigures
# their shell. Keys not listed here fall through to format_label.
declare -A LABEL_OVERRIDES=(
    [setup_zsh]="System: zsh shell, with Powerlevel10k and Nerd Fonts"
    [setup_tmpfs]="System: mount /tmp in RAM as tmpfs"
    [set_custom_wallpaper]="System: set the desktop wallpaper"
    [toggle_wayland_nvidia]="System: force Wayland on NVIDIA, can break the session"
    [setup_karabiner]="System: Karabiner-Elements key remapping (macOS)"
    [setup_finder_defaults]="System: Finder default settings (macOS)"
    [setup_wsl]="System: install WSL and Ubuntu (Windows)"
    [enable_hyperv]="System: enable Hyper-V, WSL, .NET and Sandbox features, needs a reboot (Windows)"
    [import_hibernate_task]="System: scheduled task to hibernate at 2 AM (Windows)"
)
DE_KEYS=("install_kde_plasma" "configure_kde_plasma" "install_gnome" "configure_gnome")

# CLI options
OPT_PROFILE=""
OPT_NON_INTERACTIVE=false
OPT_SKIP_SYSTEM_UPGRADE=false
# Default false, so every existing invocation keeps asking for the sudo password exactly as before.
# Only a caller that passes --passwordless-sudo drops Ansible's -K, and it should only do that on a
# machine whose account genuinely has a NOPASSWD sudo rule, which means a throwaway container or a
# hosted runner. On a normal machine the run fails early with a sudo error rather than doing
# anything surprising, which is the point of making this explicit instead of auto-detected.
OPT_PASSWORDLESS_SUDO=false

# Empty means "not asked for", which is not the same as any of the accepted values. The interactive
# path defaults the desktop environment to skip, and so does a run that passes none of these, but
# only after parse_args has had the chance to tell an empty --desktop-environment apart from an
# absent one.
OPT_DESKTOP_ENVIRONMENT=""
OPT_DESKTOP_ACTION=""
OPT_SOFTWARE=""
OPT_ENABLE=""
OPT_DISABLE=""
OPT_LIST_SOFTWARE=false
OPT_PRINT_COMMAND=false

# The whole leading comment block, however long it grows. This was a fixed line range and it had
# already truncated the exit codes once, because adding usage text and remembering to widen a
# hardcoded range are two separate acts and the second one gets forgotten.
usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; }

# One place that refuses a value, so every option reports the same way and lists what it would
# have accepted. A silent fallback to a default is how a pipeline ends up testing something other
# than what its own configuration says it is testing.
require_one_of() {
    local option="$1" value="$2"; shift 2
    local allowed=("$@") candidate
    for candidate in "${allowed[@]}"; do
        [[ "${value}" == "${candidate}" ]] && return 0
    done
    # printf rather than "${allowed[*]}", because this script sets IFS to newline and tab, so the
    # star expansion would put each accepted value on a line of its own and the reader of a log sees
    # only the first one.
    printf "ERROR: %s does not accept '%s'. Accepted: %s\n" \
           "${option}" "${value}" "$(printf '%s ' "${allowed[@]}")" >&2
    exit 2
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)         usage; exit 0 ;;
            --profile)         shift; OPT_PROFILE="${1:-}"; [[ -z "${OPT_PROFILE}" ]] && { echo "ERROR: --profile requires a value" >&2; exit 2; } ;;
            --profile=*)       OPT_PROFILE="${1#--profile=}" ;;
            --non-interactive) OPT_NON_INTERACTIVE=true ;;
            --no-color)        USE_COLOR=false ;;
            --skip-system-upgrade) OPT_SKIP_SYSTEM_UPGRADE=true ;;
            --passwordless-sudo)   OPT_PASSWORDLESS_SUDO=true ;;
            --desktop-environment) shift; OPT_DESKTOP_ENVIRONMENT="${1:-}" ;;
            --desktop-environment=*) OPT_DESKTOP_ENVIRONMENT="${1#--desktop-environment=}" ;;
            --desktop-action)  shift; OPT_DESKTOP_ACTION="${1:-}" ;;
            --desktop-action=*) OPT_DESKTOP_ACTION="${1#--desktop-action=}" ;;
            --software)        shift; OPT_SOFTWARE="${1:-}" ;;
            --software=*)      OPT_SOFTWARE="${1#--software=}" ;;
            --enable)          shift; OPT_ENABLE="${1:-}" ;;
            --enable=*)        OPT_ENABLE="${1#--enable=}" ;;
            --disable)         shift; OPT_DISABLE="${1:-}" ;;
            --disable=*)       OPT_DISABLE="${1#--disable=}" ;;
            --list-software)   OPT_LIST_SOFTWARE=true ;;
            --print-command)   OPT_PRINT_COMMAND=true ;;
            *)                 echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 2 ;;
        esac
        shift
    done

    [[ -n "${OPT_DESKTOP_ENVIRONMENT}" ]] \
        && require_one_of --desktop-environment "${OPT_DESKTOP_ENVIRONMENT}" skip kde gnome
    [[ -n "${OPT_DESKTOP_ACTION}" ]] \
        && require_one_of --desktop-action "${OPT_DESKTOP_ACTION}" full install configure
    [[ -n "${OPT_SOFTWARE}" ]] \
        && require_one_of --software "${OPT_SOFTWARE}" defaults all none

    # An action without an environment is a run that silently does nothing about the desktop, and
    # an environment of skip with an action is a contradiction. Both are refused rather than
    # resolved, because either resolution would be a guess at what the caller meant.
    if [[ -n "${OPT_DESKTOP_ACTION}" && ( -z "${OPT_DESKTOP_ENVIRONMENT}" || "${OPT_DESKTOP_ENVIRONMENT}" == skip ) ]]; then
        echo "ERROR: --desktop-action needs --desktop-environment kde or gnome" >&2
        exit 2
    fi
    if [[ -n "${OPT_DESKTOP_ENVIRONMENT}" && "${OPT_DESKTOP_ENVIRONMENT}" != skip && -z "${OPT_DESKTOP_ACTION}" ]]; then
        echo "ERROR: --desktop-environment ${OPT_DESKTOP_ENVIRONMENT} needs --desktop-action full, install or configure" >&2
        exit 2
    fi

    # A profile and an explicit software baseline are two answers to the same question, and the
    # playbook would take whichever the extra-vars precedence happened to favour rather than
    # whichever the caller meant.
    if [[ -n "${OPT_PROFILE}" && -n "${OPT_SOFTWARE}" ]]; then
        echo "ERROR: --profile and --software both decide the software set, pass one of them" >&2
        exit 2
    fi

    if [[ -n "${OPT_DESKTOP_ENVIRONMENT}${OPT_SOFTWARE}${OPT_ENABLE}${OPT_DISABLE}" ]]; then
        OPT_NON_INTERACTIVE=true
    fi
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
    if [[ -n "${LABEL_OVERRIDES[$1]:-}" ]]; then
        echo "${LABEL_OVERRIDES[$1]}"
        return
    fi
    local key="${1#install_}"; key="${key#setup_}"; key="${key#configure_}"
    key="${key//_/ }"
    echo "${key^}"
}

is_de_key() {
    local k="$1"
    for dk in "${DE_KEYS[@]}"; do [[ "${dk}" == "${k}" ]] && return 0; done
    return 1
}

# Emits one "<key> ON|OFF" line per boolean toggle. Inline comments and trailing
# blanks are stripped up front, and the value grep is anchored, so a commented
# toggle can never reach the caller with its state unconverted. See
# docs/regression_ledger.md, entry "wizard toggle parse desync".
read_boolean_toggles() {
    local file="$1"
    sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//' "${file}" 2>/dev/null \
        | grep -E '^[a-z0-9_]+: (true|false)$' \
        | grep -vE "^(${EXCLUDED_VARS}):" \
        | sed 's/: true$/ ON/;s/: false$/ OFF/'
}

# Populated at startup — no I/O between dialogs.
PRELOADED_ITEMS=()   # parallel arrays: key label state ; flattened triplets
PRELOADED_KEYS=()    # ordered keys (parallel to PRELOADED_ITEMS / 3)

# The order below is the playbook's precedence, and it used to be the opposite of it. site.yaml loads
# group_vars/all.yaml as a vars_files entry and the per-OS file through include_vars in its pre-tasks,
# and include_vars outranks play vars, so the per-OS value wins there. This function read all.yaml first
# and kept the first spelling of each key, so the per-OS value lost.
#
# One toggle differs today and it is enough to show the cost: install_claude_desktop is true in all.yaml
# and false in linux.yaml. The checklist showed it ON while a defaults run installed nothing, and the two
# paths disagreed with each other, because opening the checklist and confirming passes every state as an
# extra variable, which outranks everything, so the same toggle installed on one path and not the other.
# The Windows wizard had the same shape for two packages and was corrected the same way.
#
# Keys are still ordered all.yaml first, because that is the reading order of the checklist and the
# grouping the user recognises. Only the state comes from the per-OS file.
preload_toggles() {
    local all_toggles=() os_states=""
    os_states="$(read_boolean_toggles "${OS_VARS_FILE}")"

    while IFS= read -r line; do
        local k="${line%% *}" os_line=""
        os_line="$(grep -m1 -E "^${k} " <<<"${os_states}" || true)"
        all_toggles+=("${os_line:-${line}}")
    done < <(read_boolean_toggles "${ALL_VARS}")

    while IFS= read -r line; do
        local k="${line%% *}"
        local seen=false
        for t in "${all_toggles[@]}"; do [[ "${t%% *}" == "${k}" ]] && seen=true && break; done
        [[ "${seen}" == false ]] && all_toggles+=("${line}")
    done <<<"${os_states}"

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

load_profiles() {
    PROF_NAMES+=("Default")
    PROF_FILES+=("")
    PROF_DESCS+=("All software from group_vars defaults")
    local cnt=0
    for (( i=0; i<${#PRELOADED_KEYS[@]}; i++ )); do
        if [[ "${PRELOADED_ITEMS[$((i*3+2))]}" == "ON" ]]; then
            cnt=$((cnt+1))
        fi
    done
    PROF_COUNTS+=("${cnt}")

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

        local pcnt=0
        for (( i=0; i<${#PRELOADED_KEYS[@]}; i++ )); do
            local key="${PRELOADED_KEYS[$i]}"
            local val="${PRELOADED_ITEMS[$((i*3+2))]}"
            local ovr
            ovr=$(grep -m1 "^${key}:" "${pfile}" 2>/dev/null || true)
            if [[ -n "${ovr}" ]]; then
                [[ "${ovr}" == *"true"* ]] && val="ON" || val="OFF"
            fi
            if [[ "${val}" == "ON" ]]; then
                pcnt=$((pcnt+1))
            fi
        done
        PROF_COUNTS+=("${pcnt}")
    done
}

# ---------------------------------------------------------------------------
# What a choice means to the playbook
#
# The interactive screens and the command line options both come through here, so there is one
# description of each choice rather than one per entrypoint. Screen 3 used to hold the only copy of
# the desktop mapping and the non-interactive entrypoint had no equivalent at all, which is why a
# scripted run could reach the profile and nothing else the wizard offers.
# ---------------------------------------------------------------------------

#   skip       no overrides at all, whatever group_vars says stands
#   full       install the packages and apply the configuration
#   install    install the packages, leave the configuration alone
#   configure  install nothing, apply the configuration to an existing desktop
desktop_override_vars() {
    local environment="$1" action="$2" keys=""
    case "${environment}" in
        kde)   keys="kde_plasma" ;;
        gnome) keys="gnome" ;;
        *)     return 0 ;;
    esac
    case "${action}" in
        full)      printf '%s\n' "install_${keys}=true"  "configure_${keys}=true" ;;
        install)   printf '%s\n' "install_${keys}=true"  "configure_${keys}=false" ;;
        configure) printf '%s\n' "install_${keys}=false" "configure_${keys}=true" ;;
    esac
}

# Comma or space separated, because a pipeline writes these as a list and a person types them with
# commas.
split_key_list() { tr ',' '\n' <<<"$1" | tr -s '[:space:]' '\n' | grep -v '^$' || true; }

# Every key has to be one the checklist itself offers. Refused, never ignored: the point of these
# options is to exercise what the wizard can do, so a key the wizard cannot reach is either a typo
# or a setting deliberately kept off the checklist, and both deserve an error rather than a run that
# quietly installs something else.
assert_known_keys() {
    local option="$1" list="$2"
    local unknown=() key candidate found
    while IFS= read -r key; do
        [[ -z "${key}" ]] && continue
        found=false
        for candidate in "${PRELOADED_KEYS[@]+"${PRELOADED_KEYS[@]}"}"; do
            [[ "${candidate}" == "${key}" ]] && { found=true; break; }
        done
        [[ "${found}" == false ]] && unknown+=("${key}")
    done < <(split_key_list "${list}")

    if [[ ${#unknown[@]} -gt 0 ]]; then
        printf 'ERROR: %s names %d key(s) the wizard does not offer: %s\n' \
               "${option}" "${#unknown[@]}" "$(printf '%s ' "${unknown[@]}")" >&2
        printf '       Run setup.sh --list-software for the keys it does offer.\n' >&2
        exit 2
    fi
}

# One key=value line per selectable toggle, or nothing at all when none of the three options was
# passed, which leaves group_vars untouched exactly as --non-interactive always did.
#
# --disable is applied after --enable so a key named in both ends up off. That order is the safe
# one: the option that removes software wins over the option that adds it.
software_override_vars() {
    [[ -z "${OPT_SOFTWARE}${OPT_ENABLE}${OPT_DISABLE}" ]] && return 0

    local baseline="${OPT_SOFTWARE:-defaults}"
    local enabled disabled
    enabled="$(split_key_list "${OPT_ENABLE}")"
    disabled="$(split_key_list "${OPT_DISABLE}")"

    local i key value
    for (( i=0; i<${#PRELOADED_KEYS[@]}; i++ )); do
        key="${PRELOADED_KEYS[$i]}"
        case "${baseline}" in
            all)  value=true ;;
            none) value=false ;;
            *)    if [[ "${PRELOADED_ITEMS[$((i*3+2))]}" == "ON" ]]; then value=true; else value=false; fi ;;
        esac
        grep -qx -- "${key}" <<<"${enabled}"  && value=true
        grep -qx -- "${key}" <<<"${disabled}" && value=false
        printf '%s=%s\n' "${key}" "${value}"
    done
}

# Called from the entrypoint rather than from software_override_vars, and that placement is the
# whole point. software_override_vars runs inside a process substitution, where `exit 2` ends the
# subshell and nothing else: the error would print, the script would carry on with an empty
# override list, and the run would install the group_vars defaults while claiming to honour the
# options it had just rejected.
validate_selection_options() {
    assert_known_keys --enable "${OPT_ENABLE}"
    assert_known_keys --disable "${OPT_DISABLE}"
}

list_software() {
    local i key
    for (( i=0; i<${#PRELOADED_KEYS[@]}; i++ )); do
        key="${PRELOADED_KEYS[$i]}"
        printf '%-32s %-4s %s\n' "${key}" "${PRELOADED_ITEMS[$((i*3+2))]}" "${PRELOADED_ITEMS[$((i*3+1))]}"
    done
}

# Both entrypoints assemble the playbook command here, into PLAYBOOK_ARGS. Two separate
# assemblies is how the non-interactive path came to accept a profile and nothing else, and how a
# second -K could have appeared in one of them without the other noticing.
PLAYBOOK_ARGS=()
build_playbook_args() {
    local overrides=("$@")

    PLAYBOOK_ARGS=(
        "${ANSIBLE_DIR}/site.yaml"
        -i "localhost,"
        -c local
        "${BECOME_ARGS[@]+"${BECOME_ARGS[@]}"}"
    )

    if [[ -n "${OPT_PROFILE}" ]]; then
        local pfile="${ANSIBLE_DIR}/profiles/${OPT_PROFILE}.yaml"
        if [[ ! -f "${pfile}" ]]; then
            echo "ERROR: profile not found: ${pfile}" >&2
            exit 2
        fi
        PLAYBOOK_ARGS+=(-e "@${pfile}")
    fi

    if [[ ${#overrides[@]} -gt 0 ]]; then
        local extra_str
        extra_str="$(printf ' %s' "${overrides[@]}")"
        PLAYBOOK_ARGS+=(--extra-vars "${extra_str:1}")
    fi
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
                local de_vars=()
                while IFS= read -r line; do
                    [[ -n "${line}" ]] && de_vars+=("${line}")
                done < <(desktop_override_vars "${de_choice}" "${de_action}")

                local all_extra=("${de_vars[@]+"${de_vars[@]}"}")
                [[ "${have_pkg_vars}" == true ]] && all_extra+=("${pkg_vars[@]}")

                export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"
                build_playbook_args "${all_extra[@]+"${all_extra[@]}"}"
                local -a ansible_args=("${PLAYBOOK_ARGS[@]}")

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

# Non-interactive entrypoint, used by --profile, --non-interactive and every selection option.
run_non_interactive() {
    local overrides=() line
    while IFS= read -r line; do
        [[ -n "${line}" ]] && overrides+=("${line}")
    done < <(
        desktop_override_vars "${OPT_DESKTOP_ENVIRONMENT}" "${OPT_DESKTOP_ACTION}"
        software_override_vars
    )

    build_playbook_args "${overrides[@]+"${overrides[@]}"}"
    export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"
    echo "Running: ansible-playbook $(printf '%q ' "${PLAYBOOK_ARGS[@]}")"
    ansible-playbook "${PLAYBOOK_ARGS[@]}"
}

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

parse_args "$@"

# Built once, here, so the interactive path and the non-interactive path cannot disagree about
# whether Ansible asks for a sudo password. Two literal -K flags in two places is how they would
# drift, and the whole point of the flag is that the answer is the same wherever the run starts.
#
# Empty by default, which means -K is present and the prompt appears exactly as it always has.
BECOME_ARGS=(-K)
if [[ "${OPT_PASSWORDLESS_SUDO}" == true ]]; then
    BECOME_ARGS=()
fi

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

# Read before either entrypoint, because both need the toggle list now: the checklist renders it and
# --enable, --disable and --list-software are all validated against it. It is file parsing only, so
# the interactive path pays nothing for having it a few lines earlier, and --list-software answers
# without installing Ansible or upgrading the system first.
say "Loading toggles..."
preload_toggles

if [[ "${OPT_LIST_SOFTWARE}" == true ]]; then
    list_software
    exit 0
fi

validate_selection_options

# Answers what a set of options resolves to and changes nothing, so a pipeline author can read the
# command before spending an hour on it, and so the gate can check the resolution of every branch
# without installing anything. It sits before ensure_ansible on purpose: the question is what this
# script would run, and answering it does not need Ansible to be present.
if [[ "${OPT_PRINT_COMMAND}" == true ]]; then
    overrides=() line=""
    while IFS= read -r line; do
        [[ -n "${line}" ]] && overrides+=("${line}")
    done < <(
        desktop_override_vars "${OPT_DESKTOP_ENVIRONMENT}" "${OPT_DESKTOP_ACTION}"
        software_override_vars
    )
    build_playbook_args "${overrides[@]+"${overrides[@]}"}"
    printf 'ansible-playbook'
    printf ' %q' "${PLAYBOOK_ARGS[@]}"
    printf '\n'
    exit 0
fi

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

say "Loading profiles..."
load_profiles
echo

main_interactive
