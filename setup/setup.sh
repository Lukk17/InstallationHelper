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
#   setup.sh --verify-only                           # only verify what is installed, install nothing
#
#   defaults means the group_vars values as they are, all means every selectable toggle on, and
#   none means every selectable toggle off so --enable can build a run up from nothing. An unknown
#   key is refused rather than ignored, because a typo that installs nothing while the run reports
#   success is this project's most repeated defect.
#
# Verification. Every run ends by asking the machine what it actually ended up with, per
# application: installed, missing, or not requested. There is no flag to turn it off, because a run
# that reports success without checking is how every regression in docs/regression_ledger.md
# reached a real machine. The full result goes to ~/installation_verify.log, named on screen when
# the wizard finishes, and a missing application makes this script exit non-zero.
#
# --verify-only runs that step alone, against the same selection options, and installs nothing. Use
# it on a virtual machine, or to re-check a machine long after its install. The verification play
# can also be run directly without this wizard; its own header documents that.
#
# Exit codes:
#   0   success
#   1   bootstrap or playbook failure
#   2   bad usage
#   3   the playbook succeeded but the verification found something missing
#   130 cancelled (SIGINT/SIGQUIT)

set -euo pipefail
IFS=$'\n\t'

# --- bash 4, or a bash 4 to re-exec into -----------------------------------------------------------
#
# This script uses an associative array and one ${var^^} expansion, both of which are bash 4 syntax.
# macOS ships bash 3.2, because Apple stopped shipping bash at the last version under the GPL version
# 2 licence, and /bin/bash is still that. On 3.2 the associative array below is not an error the
# reader would recognise: `declare -A` is silently a plain array, the subscript is read as a variable
# name, and under `set -u` the script dies with "setup_zsh: unbound variable" at a line that has
# nothing wrong with it.
#
# That is exactly how it was found: the first time a hosted macOS runner executed this wizard, on
# 2026-08-20, it failed on that line, which means the macOS path had never actually been run rather
# than merely never been tested.
#
# So the version is checked before any of that syntax is reached, and a newer bash is used when one
# is installed. Homebrew's own paths are searched first, since brew is a prerequisite of the macOS
# path anyway, and PATH last. Anything else is a clear refusal naming the fix rather than a crash
# eighty lines later.
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash "$(command -v bash 2>/dev/null || true)"; do
        [ -n "${candidate}" ] || continue
        [ -x "${candidate}" ] || continue
        candidate_major="$("${candidate}" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null || echo 0)"
        if [ "${candidate_major}" -ge 4 ]; then
            exec "${candidate}" "$0" "$@"
        fi
    done
    printf 'ERROR: this wizard needs bash 4 or newer and found %s.\n' "${BASH_VERSION:-unknown}" >&2
    printf '       macOS ships bash 3.2 for licensing reasons. Install a current one:\n' >&2
    printf '           brew install bash\n' >&2
    printf '       then run this script again. Nothing has been changed.\n' >&2
    exit 2
fi

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

# The verification play and where its output is kept. The log sits beside the four the
# dual_logger callback writes (installation_full.log and friends), under the same name pattern, so
# everything one run produced is in one place.
VERIFY_PLAY="${ANSIBLE_DIR}/verify_install.yaml"
VERIFY_LOG="${HOME}/installation_verify.log"

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
OPT_VERIFY_ONLY=false

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
            --verify-only)     OPT_VERIFY_ONLY=true ;;
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

    # Both answer a question and run nothing, so a caller passing both would get whichever this
    # script happens to check first. Refuse instead of picking.
    if [[ "${OPT_VERIFY_ONLY}" == true && "${OPT_PRINT_COMMAND}" == true ]]; then
        echo "ERROR: --verify-only and --print-command each end the run on their own, pass one of them" >&2
        exit 2
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

# The ansible-core versions this repository is written against, as a half-open range: the minimum is
# accepted and the maximum is not. Checked rather than installed, because not one of the four package
# managers below can be told which version to fetch. Each distribution publishes exactly one, and they
# do not agree. Measured from the e2e images on 2026-08-20: Debian trixie carries 2.19.4, Ubuntu 26.04
# carries 2.20.1, Fedora 44 carries 2.20.7 and the two Arch-family images carry 2.21.2 and 2.21.3. An
# exact pin would therefore be a pin only on paper, so the range is the honest form of it, and this is
# the one place that states it for a real machine.
#
# The floor is 2.19.0 because that is the floor this project has always declared: the collection
# ranges in setup/ansible/requirements.yaml are resolved against it, docs/pinned_values_adapter_design.md
# is written against 2.19 and later, and the oldest supported distribution, Debian trixie, already
# carries 2.19.4, so nothing supported sits below it.
#
# The ceiling is 2.22.0 because 2.21 is the newest branch anything here has actually run. Arch and
# CachyOS ship it today, so refusing it would refuse two of the five supported distributions outright.
# 2.22 does not exist yet, and a branch nobody has run is not a branch this repository can claim.
#
# Note what the range deliberately does NOT promise. Every release inside it carries the ansiballz
# result-deserialization race documented in AGENTS.md, because the upstream fix, pull request 86739
# against ansible/ansible, is still unmerged. There is no version to move to that escapes it, so the
# mitigations in this repository stay whatever version this check accepts.
ANSIBLE_CORE_MIN_VERSION="2.19.0"
ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE="2.22.0"

# version_lt <a> <b>  true when dotted-numeric a is strictly older than b.
#
# Compared field by field as integers rather than handed to `sort -V`, which the sort that ships with
# macOS does not have, and which would in any case sort 2.9.0 above 2.19.0 the moment it fell back to
# a plain sort. Each field is cut at its first non-digit so a pre-release such as 2.20.0rc1 compares
# as 2.20.0 instead of aborting the arithmetic under `set -e`.
version_lt() {
    local i left right
    local -a left_fields right_fields
    IFS=. read -r -a left_fields <<<"$1"
    IFS=. read -r -a right_fields <<<"$2"
    for ((i = 0; i < 3; i++)); do
        left="${left_fields[i]:-0}";  left="${left%%[!0-9]*}"
        right="${right_fields[i]:-0}"; right="${right%%[!0-9]*}"
        (( 10#${left:-0} < 10#${right:-0} )) && return 0
        (( 10#${left:-0} > 10#${right:-0} )) && return 1
    done
    return 1
}

# The core version behind ansible-playbook, as x.y.z, or nothing when it cannot be read.
#
# The first line is `ansible-playbook [core 2.19.9]`, and the number after the word core is the one
# that matters here: the `ansible` community package has a version of its own, 14.3.1 today, which
# says nothing about which core is underneath it.
ansible_core_version() {
    ansible-playbook --version 2>/dev/null | sed -n '1s/.*core \([0-9][0-9.]*\).*/\1/p'
}

# Refuses a control node outside the range above, rather than letting the run discover it somewhere
# in the middle of the playbook. Both paths through ensure_ansible reach this: the one that installed
# Ansible just now and the one that found it already there, which is the path that actually matters,
# because that is where an unrelated system upgrade quietly moves the version under the project.
ensure_ansible_version() {
    local version
    version="$(ansible_core_version)"
    if [[ -z "${version}" ]]; then
        echo "ERROR: cannot read the ansible-core version from 'ansible-playbook --version'." >&2
        echo "       Ansible is on PATH but not answering, so the run stops here rather than guessing." >&2
        exit 1
    fi
    if version_lt "${version}" "${ANSIBLE_CORE_MIN_VERSION}"; then
        echo "ERROR: ansible-core ${version} is older than ${ANSIBLE_CORE_MIN_VERSION}, which this playbook needs." >&2
        echo "       On Debian or Ubuntu add the Ansible PPA (ppa:ansible/ansible) and upgrade, on macOS run" >&2
        echo "       'brew upgrade ansible', or install a supported version with pipx or pip." >&2
        exit 1
    fi
    if ! version_lt "${version}" "${ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE}"; then
        echo "ERROR: ansible-core ${version} is newer than anything this repository has run." >&2
        echo "       The tested range is ${ANSIBLE_CORE_MIN_VERSION} up to but not including ${ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE}." >&2
        echo "       Run the e2e suite against the new branch first, then widen" >&2
        echo "       ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE in setup/setup.sh and the same value in the" >&2
        echo "       e2e/tier3 Dockerfiles. Do not skip the check, it is the only thing that notices." >&2
        exit 1
    fi
    say "Ansible: core ${version}, inside the tested ${ANSIBLE_CORE_MIN_VERSION} to ${ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE} range"
}

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

# The selection a non-interactive run resolves, in one place, into OVERRIDE_VARS. Three callers need
# it: the real run, --print-command and --verify-only. Three hand-copied read loops is how one of
# them ends up resolving something the other two do not, and the whole value of --print-command is
# that it prints what the run would really do.
OVERRIDE_VARS=()
resolve_overrides() {
    OVERRIDE_VARS=()
    local line
    while IFS= read -r line; do
        [[ -n "${line}" ]] && OVERRIDE_VARS+=("${line}")
    done < <(
        desktop_override_vars "${OPT_DESKTOP_ENVIRONMENT}" "${OPT_DESKTOP_ACTION}"
        software_override_vars
    )
}

# Both entrypoints assemble the playbook command here, into PLAYBOOK_ARGS. Two separate
# assemblies is how the non-interactive path came to accept a profile and nothing else, and how a
# second -K could have appeared in one of them without the other noticing.
PLAYBOOK_ARGS=()
VERIFY_ARGS=()
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

    # The verification is handed exactly what the playbook was handed: the same inventory, the same
    # become flags, the same profile and the same --extra-vars, with only the playbook file swapped.
    # It is sliced off the list built above rather than assembled a second time, because the two
    # would drift and the drift has a known shape. The wizard passes every toggle as an extra
    # variable and extra variables outrank group_vars, so a verification resolving toggles from
    # group_vars alone would demand every application the user unticked and report it missing. The
    # container harness learned the same lesson from the other end: without the scenario's profile
    # its verification failed the live-profile run for doing exactly what it was told.
    VERIFY_ARGS=("${VERIFY_PLAY}" "${PLAYBOOK_ARGS[@]:1}")
}

# ---------------------------------------------------------------------------
# Verification — the last step of every run
# ---------------------------------------------------------------------------

# Asks the machine what it actually ended up with and prints one verdict per application. Nothing
# here installs, changes or removes anything: setup/ansible/verify_install.yaml only reads.
#
# There is no option to skip it. A run that says "success" without asking the machine anything is
# the shape of every regression in docs/regression_ledger.md, and the one that hurt most was an
# install that exited zero with a driver that could never work.
run_verification() {
    local rc=0
    echo
    say "Verifying what actually landed (this installs and changes nothing)..."
    # Said out loud because Ansible's own "BECOME password:" prompt goes to the terminal device
    # while everything else goes to the log, so without this line a second prompt looks like a
    # wizard that stopped for no reason. -K is here for two reads that need root: /etc/sudoers.d is
    # mode 0750 on Debian and Arch, and the Flathub remote is a system-wide setting.
    if [[ "${OPT_PASSWORDLESS_SUDO}" != true ]]; then
        say "It asks for your sudo password once more: two of the checks read root-owned settings."
    fi

    # Three environment settings, each for its own reason.
    #
    # ANSIBLE_STDOUT_CALLBACK: ansible.cfg selects dual_logger, which opens installation_full.log,
    # installation_errors.log, installation_warnings.log and installation_skipped.log with mode "w".
    # Running the verification under it would truncate the logs of the run being verified, the
    # moment it started. The stock callback writes nothing but stdout, which is captured below.
    #
    # ANSIBLE_CALLBACK_RESULT_FORMAT: the report is one multi-line message. As JSON it arrives as a
    # single line with literal backslash-n in it, unreadable on screen and in the log alike. As yaml
    # it arrives as a block, one report line per line, which is what the extraction below reads.
    #
    # ANSIBLE_DISPLAY_SKIPPED_HOSTS: one skipped line per unrequested toggle buries the report in
    # the log for no gain, and the verdict already names every application that was not asked for.
    ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg" ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_CALLBACK_RESULT_FORMAT=yaml ANSIBLE_DISPLAY_SKIPPED_HOSTS=false ansible-playbook "${VERIFY_ARGS[@]}" >"${VERIFY_LOG}" 2>&1 || rc=$?

    # The screen gets the report, the log keeps everything. Ansible's own output is a play recap and
    # a task list, which is not a verdict a person can read, so the report lines are lifted out of
    # it by their [verify] marker. awk rather than sed -E with a T command, because BSD sed on macOS
    # has no T and this script runs there too. The trailing-quote strip is there in case a future
    # Ansible renders the message as JSON after all: then the marker still matches and the line is
    # still readable.
    echo
    if grep -q '\[verify\]' "${VERIFY_LOG}"; then
        awk '/\[verify\]/ { sub(/^.*\[verify\] ?/, ""); sub(/",?$/, ""); print "  " $0 }' "${VERIFY_LOG}"
    else
        echo "  The verification printed no report, so it died before it could look at anything." >&2
        echo "  Read the log and start at the first fatal task." >&2
    fi

    echo
    if [[ "${rc}" -eq 0 ]]; then
        say "Verification passed. Full result: ${VERIFY_LOG}"
    else
        say "Verification FAILED, ansible-playbook exited ${rc}. Full result: ${VERIFY_LOG}"
    fi
    return "${rc}"
}

# The single exit for both entrypoints, and the only place the two results are combined.
#
# The playbook's own status always wins when it is non-zero, and a happy verification never erases
# it. That case is real rather than theoretical: a task the playbook tolerates can mark the run
# failed while every application the user asked for is present, and exiting zero there would hide a
# failure the playbook itself reported. It is called out on screen, because "the playbook failed but
# everything you asked for is installed" is a genuinely different situation from either half alone.
#
# A verification failure on a playbook that succeeded exits 3, which is its own code so that a
# caller can tell "the install broke" from "the install claimed success and the machine disagrees".
finish_run() {
    local playbook_rc="$1" verify_rc=0
    run_verification || verify_rc=$?

    echo
    if [[ "${playbook_rc}" -ne 0 ]]; then
        if [[ "${verify_rc}" -eq 0 ]]; then
            echo "The playbook exited ${playbook_rc}, but the verification found everything that was requested." >&2
            echo "Something failed that the verification does not cover. Start with ${HOME}/installation_errors.log." >&2
        else
            echo "The playbook exited ${playbook_rc} and the verification found problems too." >&2
            echo "Start with ${HOME}/installation_errors.log, then ${VERIFY_LOG}." >&2
        fi
        exit "${playbook_rc}"
    fi

    if [[ "${verify_rc}" -ne 0 ]]; then
        echo "The playbook succeeded and the verification did not: something it asked for is not on this machine." >&2
        echo "Read ${VERIFY_LOG}." >&2
        exit 3
    fi

    say "Done. The playbook succeeded and every requested application is present."
    exit 0
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
                local playbook_rc=0
                ansible-playbook "${ansible_args[@]}" || playbook_rc=$?
                finish_run "${playbook_rc}"
                ;;
        esac
    done
}

# Non-interactive entrypoint, used by --profile, --non-interactive and every selection option.
run_non_interactive() {
    resolve_overrides
    build_playbook_args "${OVERRIDE_VARS[@]+"${OVERRIDE_VARS[@]}"}"
    export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"
    echo "Running: ansible-playbook $(printf '%q ' "${PLAYBOOK_ARGS[@]}")"
    # `|| playbook_rc=$?` rather than a bare call, so a failed playbook reaches the verification
    # instead of ending the script through set -e. A failed run still put software on the machine,
    # and which parts survived is exactly what a person triaging it needs to know.
    local playbook_rc=0
    ansible-playbook "${PLAYBOOK_ARGS[@]}" || playbook_rc=$?
    finish_run "${playbook_rc}"
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
    resolve_overrides
    build_playbook_args "${OVERRIDE_VARS[@]+"${OVERRIDE_VARS[@]}"}"
    printf 'ansible-playbook'
    printf ' %q' "${PLAYBOOK_ARGS[@]}"
    printf '\n'
    exit 0
fi

# Pre-create Ansible tmp + fact-cache dirs (ansible.cfg uses ~/.ansible/...).
# jsonfile fact cache fails on first run if its dir doesn't exist.
mkdir -p "${HOME}/.ansible/tmp" "${HOME}/.ansible/facts-cache"
ensure_ansible
ensure_ansible_version

# Verification on its own, for a virtual machine or for a machine whose install finished long ago.
# It sits above system_upgrade deliberately: this path is not allowed to change the machine, and an
# upgrade is a change. It needs no collections either, because the play uses builtin modules only.
#
# The selection resolves exactly as a real run's would, through the same two functions and the same
# assembly, so `--verify-only --disable chrome` asks about the same set that `--disable chrome`
# would have installed.
if [[ "${OPT_VERIFY_ONLY}" == true ]]; then
    resolve_overrides
    build_playbook_args "${OVERRIDE_VARS[@]+"${OVERRIDE_VARS[@]}"}"
    run_verification || exit 3
    exit 0
fi

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
