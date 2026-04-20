#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
ALL_VARS="${ANSIBLE_DIR}/group_vars/all.yaml"
LINUX_VARS="${ANSIBLE_DIR}/group_vars/linux.yaml"
MACOS_VARS="${ANSIBLE_DIR}/group_vars/macos.yaml"

EXCLUDED_VARS="non_root_user|non_root_home|allow_callback_failure|default_wallpaper|set_custom_wallpaper|install_system_core|setup_tmpfs|toggle_wayland_nvidia"
DE_KEYS=("install_kde_plasma" "configure_kde_plasma" "install_gnome" "configure_gnome")

# Matrix green-on-black theme for whiptail dialogs (radiolist + yesno screens).
# actbutton=white,green → white text on green = maximum contrast, clearly selected.
export NEWT_COLORS='
root=green,black
border=green,black
window=green,black
shadow=black,black
title=white,black
button=green,black
actbutton=white,green
checkbox=green,black
actcheckbox=black,green
entry=green,black
label=green,black
listbox=green,black
actlistbox=black,green
sellistbox=white,green
actsellistbox=white,green
textbox=green,black
acttextbox=green,black
helpline=black,green
roottext=green,black
emptyscale=green,black
fullscale=black,green
disabledentry=green,black
compactbutton=green,black
'

# ANSI colour shortcuts used by the custom checklist TUI.
_G='\e[32m'       # green
_DG='\e[2;32m'    # dim green
_BG='\e[1;32m'    # bold bright green
_SEL='\e[42;30m'    # selected row: black text on green bg
_BTN_ON='\e[1;30;42m'  # focused button: BOLD black on green bg — unmistakable
_BTN_OFF='\e[2;32m'    # unfocused button: dim green, no bg — clearly inactive
_RST='\e[0m'

_RESULT=""
_RC=0

# Global cleanup — restores terminal state on Ctrl+C / Ctrl+\ from any screen.
cleanup_exit() {
    tput cvvis 2>/dev/null || true
    clear
    echo "Wizard cancelled."
    exit 130
}
trap cleanup_exit INT QUIT

_tui() {
    set +e
    _RESULT=$("$@" 3>&1 1>&2 2>&3)
    _RC=$?
    set -e
}

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

detect_tui_tool() {
    command -v whiptail &>/dev/null && echo "whiptail" && return
    command -v dialog  &>/dev/null && echo "dialog"  && return
    echo ""
}

detect_os() {
    if [[ "$(uname)" == "Darwin" ]]; then
        OS_FAMILY="Darwin"; DISTRO="macOS"; OS_VARS_FILE="${MACOS_VARS}"
    elif [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        DISTRO="${NAME:-Linux}"
        case "${ID_LIKE:-${ID:-}}" in
            *arch*)                     OS_FAMILY="Archlinux" ;;
            *fedora*|*rhel*|*centos*)   OS_FAMILY="RedHat" ;;
            *debian*|*ubuntu*)          OS_FAMILY="Debian" ;;
            *)
                case "${ID:-}" in
                    arch)                       OS_FAMILY="Archlinux" ;;
                    fedora|rhel|centos)          OS_FAMILY="RedHat" ;;
                    ubuntu|debian|linuxmint|pop) OS_FAMILY="Debian" ;;
                    *)                           OS_FAMILY="Linux" ;;
                esac ;;
        esac
        OS_VARS_FILE="${LINUX_VARS}"
    else
        OS_FAMILY="Linux"; DISTRO="Unknown Linux"; OS_VARS_FILE="${LINUX_VARS}"
    fi
}

ensure_ansible() {
    command -v ansible-playbook &>/dev/null && return 0
    echo "Ansible not found — installing for ${OS_FAMILY}..."
    case "${OS_FAMILY}" in
        Debian)
            sudo apt-get update -q
            # Ubuntu: use PPA for latest Ansible. Debian: ansible is in default repos.
            if command -v add-apt-repository &>/dev/null || apt-cache show software-properties-common &>/dev/null 2>&1; then
                sudo apt-get install -y software-properties-common
                sudo add-apt-repository --yes --update ppa:ansible/ansible 2>/dev/null || true
            fi
            sudo apt-get install -y ansible ;;
        RedHat)    sudo dnf install -y ansible ;;
        Archlinux) sudo pacman -S --noconfirm ansible ;;
        Darwin)    brew install ansible ;;
        *) echo "ERROR: Cannot auto-install Ansible on ${OS_FAMILY}." >&2; exit 1 ;;
    esac
}

ensure_tui_tool() {
    TUI_TOOL=$(detect_tui_tool)
    [[ -n "${TUI_TOOL}" ]] && return 0
    echo "Installing whiptail for ${OS_FAMILY}..."
    case "${OS_FAMILY}" in
        Debian)    sudo apt-get install -y whiptail ;;
        RedHat)    sudo dnf install -y newt ;;
        Archlinux) sudo pacman -S --noconfirm libnewt ;;
        Darwin)    brew install newt ;;
        *) echo "ERROR: Cannot auto-install whiptail on ${OS_FAMILY}." >&2; exit 1 ;;
    esac
    TUI_TOOL=$(detect_tui_tool)
}

install_collections() {
    echo "Installing required Ansible collections..."
    ansible-galaxy collection install -r "${ANSIBLE_DIR}/requirements.yaml" 2>&1 \
        | grep -v '^Starting galaxy' || true
}

check_requirements() {
    if [[ ! -d "${ANSIBLE_DIR}" ]]; then
        echo "ERROR: Ansible directory not found at ${ANSIBLE_DIR}" >&2
        exit 1
    fi
}

read_boolean_toggles() {
    local file="$1"
    grep -E '^[a-z_]+: (true|false)' "${file}" 2>/dev/null \
        | grep -vE "^(${EXCLUDED_VARS}):" \
        | sed 's/: true$/ ON/;s/: false$/ OFF/'
}

# Populated at startup — no I/O between TUI dialogs.
PRELOADED_ITEMS=()   # whiptail triplets: key label ON|OFF
PRELOADED_KEYS=()    # ordered keys (parallel to PRELOADED_ITEMS / 3)

preload_toggles() {
    local all_toggles=()
    while IFS= read -r line; do all_toggles+=("${line}"); done \
        < <(read_boolean_toggles "${ALL_VARS}")

    while IFS= read -r line; do
        local k="${line%% *}"
        local seen=false
        for t in "${all_toggles[@]}"; do [[ "${t%% *}" == "${k}:" ]] && seen=true && break; done
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

# ---------------------------------------------------------------------------
# Profile discovery — scans profiles/*.yaml + synthetic "Default" profile
# ---------------------------------------------------------------------------

PROF_NAMES=()
PROF_DESCS=()
PROF_COUNTS=()
PROF_SW=()        # comma-separated enabled software labels
PROF_STATES=()    # space-separated 0/1 per PRELOADED_KEYS index

load_profiles() {
    # Synthetic "Default" profile — group_vars as-is
    PROF_NAMES+=("Default")
    PROF_DESCS+=("All software from group_vars defaults")
    local cnt=0 sw="" st=""
    for (( i=0; i<${#PRELOADED_KEYS[@]}; i++ )); do
        if [[ "${PRELOADED_ITEMS[$((i*3+2))]}" == "ON" ]]; then
            (( cnt++ )) || true; sw+="${sw:+, }$(format_label "${PRELOADED_KEYS[$i]}")"
            st+="${st:+ }1"
        else
            st+="${st:+ }0"
        fi
    done
    PROF_COUNTS+=("${cnt}"); PROF_SW+=("${sw}"); PROF_STATES+=("${st}")

    # Auto-discover from profiles/*.yaml
    for pfile in "${ANSIBLE_DIR}/profiles/"*.yaml; do
        [[ ! -f "${pfile}" ]] && continue
        local raw_name; raw_name=$(basename "${pfile}" .yaml)
        raw_name="${raw_name//_/ }"
        local name="" word
        for word in ${raw_name}; do name+="${name:+ }${word^}"; done
        PROF_NAMES+=("${name}")

        # Description: first comment line after ---
        local desc=""
        while IFS= read -r line; do
            [[ "${line}" == "---" ]] && continue
            [[ "${line}" == \#* ]] && desc="${line#\# }" && break
            break
        done < "${pfile}"
        PROF_DESCS+=("${desc:-No description}")

        # Merge defaults with profile overrides
        local pcnt=0 psw="" pst=""
        for (( i=0; i<${#PRELOADED_KEYS[@]}; i++ )); do
            local key="${PRELOADED_KEYS[$i]}"
            local val="${PRELOADED_ITEMS[$((i*3+2))]}"
            local ovr
            ovr=$(grep -m1 "^${key}:" "${pfile}" 2>/dev/null || true)
            if [[ -n "${ovr}" ]]; then
                [[ "${ovr}" == *"true"* ]] && val="ON" || val="OFF"
            fi
            if [[ "${val}" == "ON" ]]; then
                (( pcnt++ )) || true; psw+="${psw:+, }$(format_label "${key}")"
                pst+="${pst:+ }1"
            else
                pst+="${pst:+ }0"
            fi
        done
        PROF_COUNTS+=("${pcnt}"); PROF_SW+=("${psw}"); PROF_STATES+=("${pst}")
    done
}

# ---------------------------------------------------------------------------
# Reusable radio-select TUI — consistent arrow/button navigation
#
# Usage: radio_tui "Title" key1 "Label 1" key2 "Label 2" ...
# Sets _RESULT=selected_key, _RC=0 on select, _RC=1 on back/esc.
#
# Navigation:
#   ↑↓           — move cursor between items
#   Space        — mark item (radio dot ●)
#   Enter/Tab    — move focus to buttons
#   ↓ at last    — move focus to buttons
#   ↑ on buttons — return to list
#   Esc          — back
# ---------------------------------------------------------------------------

radio_tui() {
    local title="$1"; shift
    local -a keys=() labels=()
    while [[ $# -ge 2 ]]; do
        keys+=("$1"); labels+=("$2"); shift 2
    done
    local total=${#keys[@]}
    [[ ${total} -eq 0 ]] && _RC=1 && return 0

    local tw; tw=$(tput cols)
    local cur=0 selected=0 mode="list" btn=0
    local HDR=5

    tput civis 2>/dev/null || true
    clear

    # Header
    local sep; sep=$(printf '%*s' "${tw}" '' | tr ' ' '-')
    tput cup 0 0
    printf "${_G}%s${_RST}\n" "${sep}"
    printf "${_BG}  %s — %-*s${_RST}\n" "${title}" $(( tw - ${#title} - 6 )) "${DISTRO}"
    printf "${_G}%s${_RST}\n" "${sep}"
    printf "${_DG}  ↑↓ move  Space mark  Enter/Tab → buttons  Esc back${_RST}\n"
    printf '\n'

    while true; do
        # Items
        for (( i=0; i<total; i++ )); do
            tput cup $(( HDR + i )) 0
            local radio="○"; (( i == selected )) && radio="●"
            local row="  ${radio} ${labels[$i]}"
            local pad=$(( tw - ${#row} ))
            (( pad < 0 )) && pad=0
            if (( i == cur )) && [[ "${mode}" == "list" ]]; then
                printf "${_SEL}%s%*s${_RST}" "${row}" "${pad}" ''
            elif (( i == selected )); then
                printf "${_G}%s%*s${_RST}" "${row}" "${pad}" ''
            else
                printf "${_DG}%s%*s${_RST}" "${row}" "${pad}" ''
            fi
        done

        # Blank + buttons
        tput cup $(( HDR + total )) 0
        printf '%-*s' "${tw}" ''
        tput cup $(( HDR + total + 1 )) 0
        if [[ "${mode}" == "buttons" && ${btn} -eq 0 ]]; then
            printf "  ${_BTN_ON}[ Select ]${_RST}"
        else
            printf "  ${_BTN_OFF}  Select  ${_RST}"
        fi
        printf '   '
        if [[ "${mode}" == "buttons" && ${btn} -eq 1 ]]; then
            printf "${_BTN_ON}[ Back ]${_RST}"
        else
            printf "${_BTN_OFF}  Back  ${_RST}"
        fi
        printf '%-*s' $(( tw - 28 )) ''

        _cl_read_key

        if [[ "${mode}" == "list" ]]; then
            case "${_KEY}" in
                $'\x1b[A')  (( cur > 0 )) && (( cur-- )) || true ;;
                $'\x1b[B')
                    if (( cur < total - 1 )); then
                        (( cur++ )) || true
                    else
                        mode="buttons"; btn=0
                    fi ;;
                ' ')         selected=${cur} ;;                      # Space = mark radio
                $'\t'|ENTER) mode="buttons"; btn=0 ;;               # Tab/Enter = go to buttons
                $'\x11')     cleanup_exit ;;
                $'\x1b')     tput cvvis 2>/dev/null || true; clear; _RC=1; return 0 ;;
            esac
        else
            case "${_KEY}" in
                $'\x1b[D')           btn=0 ;;                        # Left → Select
                $'\x1b[C')           btn=1 ;;                        # Right → Back
                $'\x1b[A')           mode="list" ;;                  # Up → back to list
                $'\x1b[B')           ;;                              # Down — at bottom
                $'\t')               btn=$(( 1 - btn )) ;;
                $'\x11')             cleanup_exit ;;
                $'\x1b')             mode="list" ;;
                ' '|ENTER)                                           # Enter/Space = activate button
                    tput cvvis 2>/dev/null || true; clear
                    if (( btn == 0 )); then
                        _RESULT="${keys[$selected]}"; _RC=0
                    else
                        _RC=1
                    fi
                    return 0 ;;
            esac
        fi
    done
}

# ---------------------------------------------------------------------------
# Screens using radio_tui and whiptail (yesno dialogs stay as whiptail)
# ---------------------------------------------------------------------------

screen_de() {
    radio_tui "Step 1/3: Desktop Environment" \
        "none"  "No desktop environment (server / headless)" \
        "kde"   "KDE Plasma (Wayland)" \
        "gnome" "GNOME"
}

screen_configure_de() {
    local de="${1^^}"
    _tui whiptail \
        --title "  Step 1/3: Configure ${de}  " \
        --yes-button "  Yes  " --no-button "  No  " \
        --yesno $"\nAlso apply ${de} configuration after install?\n(Themes, shortcuts, panel defaults)\n\nEnter = Yes  |  Tab = No  |  Esc = back\n" \
        12 58
}

screen_review() {
    radio_tui "Step 2/3: Software Selection" \
        "defaults"  "Use group_vars settings as-is" \
        "customise" "Open checklist to toggle individual software" \
        "profile"   "Load a preset profile (e.g. Linux Live)"
}

screen_confirm() {
    local cmd="$1"
    local tw; tw=$(tput cols)
    local btn=0
    local HDR=5

    tput civis 2>/dev/null || true
    clear

    # Header
    local sep; sep=$(printf '%*s' "${tw}" '' | tr ' ' '-')
    tput cup 0 0
    printf "${_G}%s${_RST}\n" "${sep}"
    printf "${_BG}  Step 3/3: Confirm & Run — %-*s${_RST}\n" $(( tw - 30 )) "${DISTRO}"
    printf "${_G}%s${_RST}\n" "${sep}"
    printf "${_DG}  ←→/Tab switch buttons  Enter/Space activate  Esc back${_RST}\n"
    printf '\n'

    # Command display
    tput cup ${HDR} 0
    printf "${_G}  Ready to run:${_RST}\n\n"
    # Word-wrap command to fit terminal
    printf "${_BG}  %s${_RST}\n" "${cmd}" | fold -s -w $(( tw - 4 ))
    printf '\n'

    local btn_row=$(( HDR + 5 ))

    while true; do
        tput cup ${btn_row} 0
        if (( btn == 0 )); then
            printf "  ${_BTN_ON}[ Run ]${_RST}"
        else
            printf "  ${_BTN_OFF}  Run  ${_RST}"
        fi
        printf '   '
        if (( btn == 1 )); then
            printf "${_BTN_ON}[ Cancel ]${_RST}"
        else
            printf "${_BTN_OFF}  Cancel  ${_RST}"
        fi
        printf '%-*s' $(( tw - 26 )) ''

        _cl_read_key
        case "${_KEY}" in
            $'\x1b[D'|$'\x1b[A') btn=0 ;;
            $'\x1b[C'|$'\x1b[B') btn=1 ;;
            $'\t')               btn=$(( 1 - btn )) ;;
            $'\x11')             cleanup_exit ;;
            $'\x1b')             tput cvvis 2>/dev/null || true; clear; _RC=1; return 0 ;;
            ' '|ENTER)
                tput cvvis 2>/dev/null || true; clear
                if (( btn == 0 )); then _RC=0; else _RC=1; fi
                return 0 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Profiles TUI — radiolist with multi-line entries showing software per profile
#
# Layout per profile entry (5 lines each):
#   line 0   ► Name                                    XX packages
#   line 1     Description text
#   line 2     Software1, Software2, Software3, ...
#   line 3     Software4, Software5, ...
#   line 4     (blank separator)
#
# Navigation:
#   ↑↓           — move between profiles
#   Enter/Space  — select highlighted profile
#   ↓ at last    — move focus to buttons
#   Tab          — move to buttons
#   Esc          — cancel / back
# ---------------------------------------------------------------------------

_pr_draw_header() {
    local tw="$1"
    local sep; sep=$(printf '%*s' "${tw}" '' | tr ' ' '-')
    tput cup 0 0
    printf "${_G}%s${_RST}\n"              "${sep}"
    printf "${_BG}  Profiles — %-*s${_RST}\n" $(( tw - 14 )) "${DISTRO}"
    printf "${_G}%s${_RST}\n"              "${sep}"
    printf "${_DG}  ↑↓ select  Enter apply  Esc back${_RST}\n"
    printf '\n'
}

_pr_draw_frame() {
    local tw="$1" ppage="$2" cur="$3" scroll="$4" mode="$5" btn="$6"
    local total="${#PROF_NAMES[@]}"
    local HDR=5 EH=5
    local wrap_w=$(( tw - 6 ))

    # Scroll-up indicator
    tput cup ${HDR} 0
    if (( scroll > 0 )); then
        printf "${_DG}  ↑ %d more above%-*s${_RST}\n" "${scroll}" $(( tw - 18 )) ''
    else
        printf '%-*s\n' "${tw}" ''
    fi

    # Profile entries
    local end=$(( scroll + ppage ))
    (( end > total )) && end=${total}

    for (( p=scroll; p<end; p++ )); do
        local base=$(( HDR + 1 + (p - scroll) * EH ))

        # Line 1: indicator + name + package count
        tput cup ${base} 0
        local ind="○"; (( p == cur )) && [[ "${mode}" == "list" ]] && ind="►"
        local name_str="  ${ind} ${PROF_NAMES[$p]}"
        local cnt_str="${PROF_COUNTS[$p]} packages"
        local gap=$(( tw - ${#name_str} - ${#cnt_str} - 2 ))
        (( gap < 1 )) && gap=1
        if (( p == cur )) && [[ "${mode}" == "list" ]]; then
            printf "${_SEL}%s%*s%s  ${_RST}" "${name_str}" "${gap}" '' "${cnt_str}"
        else
            printf "${_G}%s${_RST}%*s${_DG}%s  ${_RST}" "${name_str}" "${gap}" '' "${cnt_str}"
        fi

        # Line 2: description
        tput cup $(( base + 1 )) 0
        local desc="${PROF_DESCS[$p]:0:${wrap_w}}"
        local dpad=$(( tw - ${#desc} - 4 ))
        (( dpad < 0 )) && dpad=0
        printf "${_DG}    %s%*s${_RST}" "${desc}" "${dpad}" ''

        # Lines 3-4: software list (max 2 lines, word-wrapped)
        local sw_text="${PROF_SW[$p]}"
        local sw1="" sw2=""
        if [[ -n "${sw_text}" ]]; then
            sw1=$(printf '%s' "${sw_text}" | fold -s -w "${wrap_w}" | head -1)
            sw2=$(printf '%s' "${sw_text}" | fold -s -w "${wrap_w}" | sed -n '2p')
            local sw_lines
            sw_lines=$(printf '%s' "${sw_text}" | fold -s -w "${wrap_w}" | wc -l)
            if (( sw_lines > 2 )) && [[ -n "${sw2}" ]]; then
                sw2="${sw2:0:$((wrap_w-3))}..."
            fi
        fi
        tput cup $(( base + 2 )) 0
        printf "${_DG}    %-*s${_RST}" $(( tw - 4 )) "${sw1}"
        tput cup $(( base + 3 )) 0
        printf "${_DG}    %-*s${_RST}" $(( tw - 4 )) "${sw2}"

        # Line 5: blank separator
        tput cup $(( base + 4 )) 0
        printf '%-*s' "${tw}" ''
    done

    # Clear remaining viewport
    local used=$(( (end - scroll) * EH ))
    local viewport=$(( ppage * EH ))
    for (( l=used; l<viewport; l++ )); do
        tput cup $(( HDR + 1 + l )) 0
        printf '%-*s' "${tw}" ''
    done

    # Scroll-down indicator
    local bot=$(( HDR + 1 + viewport ))
    tput cup ${bot} 0
    local rem=$(( total - scroll - ppage ))
    if (( rem > 0 )); then
        printf "${_DG}  ↓ %d more below%-*s${_RST}\n" "${rem}" $(( tw - 19 )) ''
    else
        printf '%-*s\n' "${tw}" ''
    fi

    # Blank + buttons
    tput cup $(( bot + 1 )) 0
    printf '%-*s\n' "${tw}" ''
    tput cup $(( bot + 2 )) 0
    if [[ "${mode}" == "buttons" && ${btn} -eq 0 ]]; then
        printf "  ${_BTN_ON}[ Apply ]${_RST}"
    else
        printf "  ${_BTN_OFF}  Apply  ${_RST}"
    fi
    printf '   '
    if [[ "${mode}" == "buttons" && ${btn} -eq 1 ]]; then
        printf "${_BTN_ON}[ Back ]${_RST}"
    else
        printf "${_BTN_OFF}  Back  ${_RST}"
    fi
    printf '%-*s' $(( tw - 26 )) ''
}

profiles_tui() {
    local total="${#PROF_NAMES[@]}"
    [[ ${total} -eq 0 ]] && _RC=1 && return 0

    local tw; tw=$(tput cols)
    local th; th=$(tput lines)
    local EH=5
    local ppage=$(( (th - 9) / EH ))
    (( ppage < 1 )) && ppage=1

    local cur=0 scroll=0 mode="list" btn=0

    tput civis 2>/dev/null || true
    clear
    _pr_draw_header "${tw}"

    while true; do
        _pr_draw_frame "${tw}" "${ppage}" "${cur}" "${scroll}" "${mode}" "${btn}"

        _cl_read_key

        if [[ "${mode}" == "list" ]]; then
            case "${_KEY}" in
                $'\x1b[A')   # Up
                    if (( cur > 0 )); then
                        (( cur-- )) || true
                        (( cur < scroll )) && (( scroll-- )) || true
                    fi ;;
                $'\x1b[B')   # Down
                    if (( cur < total - 1 )); then
                        (( cur++ )) || true
                        (( cur >= scroll + ppage )) && (( scroll++ )) || true
                    else
                        mode="buttons"; btn=0
                    fi ;;
                $'\x1b[5~')  # PgUp
                    cur=$(( cur > ppage ? cur - ppage : 0 ))
                    (( cur < scroll )) && scroll=${cur} || true ;;
                $'\x1b[6~')  # PgDn
                    cur=$(( cur + ppage < total - 1 ? cur + ppage : total - 1 ))
                    (( cur >= scroll + ppage )) && (( scroll = cur - ppage + 1 )) || true ;;
                $'\x1b[H'|$'\x1b[1~') cur=0; scroll=0 ;;     # Home
                $'\x1b[F'|$'\x1b[4~')                          # End
                    cur=$(( total - 1 ))
                    (( cur >= scroll + ppage )) && (( scroll = cur - ppage + 1 )) || true ;;
                ' '|ENTER)                                     # Enter/Space → select profile
                    tput cvvis 2>/dev/null || true; clear
                    _RESULT="${cur}"; _RC=0; return 0 ;;
                $'\t')       mode="buttons"; btn=0 ;;          # Tab → buttons
                $'\x11')     cleanup_exit ;;                    # Ctrl+Q
                $'\x1b')     tput cvvis 2>/dev/null || true; clear; _RC=1; return 0 ;;
            esac
        else  # buttons mode
            case "${_KEY}" in
                $'\x1b[D')           (( btn > 0 )) && (( btn-- )) || true ;;  # Left
                $'\x1b[C')           (( btn < 1 )) && (( btn++ )) || true ;;  # Right
                $'\x1b[A')           mode="list" ;;                            # Up → back to list
                $'\x1b[B')           ;;                                        # Down — at bottom
                $'\t')               btn=$(( 1 - btn )) ;;                     # Tab toggle
                $'\x11')             cleanup_exit ;;                            # Ctrl+Q
                $'\x1b')             mode="list" ;;                             # Esc → list
                ' '|ENTER)                                                      # Activate
                    tput cvvis 2>/dev/null || true; clear
                    if (( btn == 0 )); then
                        _RESULT="${cur}"; _RC=0
                    else
                        _RC=1
                    fi
                    return 0 ;;
            esac
        fi
    done
}

# ---------------------------------------------------------------------------
# Custom bash TUI checklist — full navigation control, no whiptail limitations
#
# Layout (line numbers, 0-indexed):
#   0        separator
#   1        title
#   2        separator
#   3        hint
#   4        blank
#   5        scroll-up indicator     ← HDR = 5 (lines 0-4 are static header)
#   6..6+P-1 items (P = page size)
#   6+P      scroll-down indicator
#   6+P+1    status bar (Selected N/T)
#   6+P+2    blank
#   6+P+3    buttons
#
# Navigation:
#   ↑↓ / PgUp/PgDn / Home/End  — move through items
#   Space                       — toggle item
#   ↓ at last item / Tab / Enter — move focus to button row
#   ← → / Tab (in button row)   — switch between Apply / Back
#   ↑ / Esc (in button row)     — return focus to list
#   Enter / Space (on button)   — activate button
#   Esc (in list)               — same as Back (exit)
# ---------------------------------------------------------------------------

_KEY=""
_cl_read_key() {
    local rest
    IFS= read -rsn1 _KEY
    # Enter key produces empty string — normalize
    if [[ -z "${_KEY}" ]]; then
        _KEY="ENTER"
        return
    fi
    if [[ "${_KEY}" == $'\x1b' ]]; then
        IFS= read -rsn2 -t 0.1 rest || rest=''
        # Handle 3-char sequences (PgUp/PgDn/Home/End)
        if [[ "${rest}" == $'[5' || "${rest}" == $'[6' \
           || "${rest}" == $'[1' || "${rest}" == $'[4' ]]; then
            local extra
            IFS= read -rsn1 -t 0.1 extra || extra=''
            rest="${rest}${extra}"
        fi
        _KEY="${_KEY}${rest}"
        # Drain any leftover bytes from fast key repeat
        while IFS= read -rsn1 -t 0.01 _ 2>/dev/null; do :; done
    fi
}

_cl_draw_header() {
    local tw="$1"
    local sep; sep=$(printf '%*s' "${tw}" '' | tr ' ' '-')
    tput cup 0 0
    printf "${_G}%s${_RST}\n"              "${sep}"
    printf "${_BG}  Software — %-*s${_RST}\n" $(( tw - 14 )) "${DISTRO}"
    printf "${_G}%s${_RST}\n"              "${sep}"
    printf "${_DG}  ↑↓ scroll  Space toggle  ↓(end)/Tab → buttons  Esc back${_RST}\n"
    printf '\n'
}

_cl_draw_frame() {
    local tw="$1" page="$2" cur="$3" scroll="$4" mode="$5" btn="$6"
    local -n _states="$7"
    local total="${#PRELOADED_KEYS[@]}"
    local HDR=5

    # Scroll-up indicator
    tput cup ${HDR} 0
    if (( scroll > 0 )); then
        printf "${_DG}  ↑ %d more above%-*s${_RST}\n" "${scroll}" $(( tw - 18 )) ''
    else
        printf '%-*s\n' "${tw}" ''
    fi

    # Items
    local end=$(( scroll + page ))
    (( end > total )) && end=${total}
    local row_idx
    for (( i=scroll; i<end; i++ )); do
        row_idx=$(( HDR + 1 + i - scroll ))
        tput cup "${row_idx}" 0
        local ck; (( _states[i] )) && ck='X' || ck=' '
        local lbl="${PRELOADED_KEYS[$i]}  $(format_label "${PRELOADED_KEYS[$i]}")"
        # Truncate label to fit terminal width
        local maxlbl=$(( tw - 10 ))
        lbl="${PRELOADED_ITEMS[$((i*3+1))]}"
        local row="  [${ck}]  ${lbl}"
        local pad=$(( tw - ${#row} ))
        (( pad < 0 )) && pad=0

        if (( i == cur )) && [[ "${mode}" == "list" ]]; then
            printf "${_SEL}%s%*s${_RST}" "${row}" "${pad}" ''
        elif (( _states[i] )); then
            printf "${_G}%s%*s${_RST}"  "${row}" "${pad}" ''
        else
            printf "${_DG}%s%*s${_RST}" "${row}" "${pad}" ''
        fi
    done

    # Blank padding below items
    for (( i=end; i<scroll+page; i++ )); do
        tput cup $(( HDR + 1 + i - scroll )) 0
        printf '%*s' "${tw}" ''
    done

    # Scroll-down indicator
    tput cup $(( HDR + 1 + page )) 0
    local rem=$(( total - scroll - page ))
    if (( rem > 0 )); then
        printf "${_DG}  ↓ %d more below%-*s${_RST}\n" "${rem}" $(( tw - 19 )) ''
    else
        printf '%-*s\n' "${tw}" ''
    fi

    # Status bar
    tput cup $(( HDR + 1 + page + 1 )) 0
    local cnt=0
    for s in "${_states[@]}"; do (( s )) && (( cnt++ )) || true; done
    printf "${_BG}  Selected: %d / %d%-*s${_RST}\n" "${cnt}" "${total}" $(( tw - 16 )) ''

    # Blank line
    tput cup $(( HDR + 1 + page + 2 )) 0
    printf '%-*s\n' "${tw}" ''

    # Buttons — Apply + Back (uniform focus style)
    tput cup $(( HDR + 1 + page + 3 )) 0
    if [[ "${mode}" == "buttons" && ${btn} -eq 0 ]]; then
        printf "  ${_BTN_ON}[ Apply ]${_RST}"
    else
        printf "  ${_BTN_OFF}  Apply  ${_RST}"
    fi
    printf '   '
    if [[ "${mode}" == "buttons" && ${btn} -eq 1 ]]; then
        printf "${_BTN_ON}[ Back ]${_RST}"
    else
        printf "${_BTN_OFF}  Back  ${_RST}"
    fi
    printf '%-*s' $(( tw - 26 )) ''
}

checklist_tui() {
    local total="${#PRELOADED_KEYS[@]}"
    [[ ${total} -eq 0 ]] && _RC=0 && _RESULT="" && return 0

    local tw; tw=$(tput cols)
    local th; th=$(tput lines)
    # HDR=5 lines + scroll-up + items + scroll-down + status + blank + buttons = page + 10
    local page=$(( th - 10 ))
    (( page < 3 )) && page=3

    local -a states=()
    for (( i=0; i<total; i++ )); do
        [[ "${PRELOADED_ITEMS[$((i*3+2))]}" == "ON" ]] && states+=(1) || states+=(0)
    done

    local cur=0 scroll=0 mode="list" btn=0

    tput civis 2>/dev/null || true
    clear
    _cl_draw_header "${tw}"

    while true; do
        _cl_draw_frame "${tw}" "${page}" "${cur}" "${scroll}" "${mode}" "${btn}" states

        _cl_read_key

        if [[ "${mode}" == "list" ]]; then
            case "${_KEY}" in
                $'\x1b[A')   # Up
                    if (( cur > 0 )); then
                        (( cur-- )) || true
                        (( cur < scroll )) && (( scroll-- )) || true
                    fi ;;
                $'\x1b[B')   # Down
                    if (( cur < total - 1 )); then
                        (( cur++ )) || true
                        (( cur >= scroll + page )) && (( scroll++ )) || true
                    else
                        mode="buttons"; btn=0   # ← Down at last item → buttons
                    fi ;;
                $'\x1b[5~')  # PgUp
                    cur=$(( cur > page ? cur - page : 0 ))
                    (( cur < scroll )) && scroll=${cur} || true ;;
                $'\x1b[6~')  # PgDn
                    cur=$(( cur + page < total - 1 ? cur + page : total - 1 ))
                    (( cur >= scroll + page )) && (( scroll = cur - page + 1 )) || true ;;
                $'\x1b[H'|$'\x1b[1~') cur=0; scroll=0 ;;     # Home
                $'\x1b[F'|$'\x1b[4~')                          # End
                    cur=$(( total - 1 ))
                    (( cur >= scroll + page )) && (( scroll = cur - page + 1 )) || true ;;
                ' ')         states[$cur]=$(( 1 - states[$cur] )) ;;  # Space toggle
                $'\t'|ENTER) mode="buttons"; btn=0 ;;                # Tab/Enter → buttons
                $'\x11')     cleanup_exit ;;   # Ctrl+Q
                $'\x1b')     tput cvvis 2>/dev/null || true; clear; _RC=1; return 0 ;;
            esac
        else  # buttons mode (0=Apply, 1=Back)
            case "${_KEY}" in
                $'\x1b[D'|$'\x1b[A') btn=0 ;;                               # Left/Up → Apply
                $'\x1b[C'|$'\x1b[B') btn=1 ;;                               # Right/Down → Back
                $'\t')               btn=$(( 1 - btn )) ;;                   # Tab toggle
                $'\x11')             cleanup_exit ;;                          # Ctrl+Q
                $'\x1b')             mode="list" ;;                           # Esc → back to list
                ' '|ENTER)                                                    # Enter/Space → activate
                    tput cvvis 2>/dev/null || true; clear
                    if (( btn == 0 )); then  # Apply
                        local -a out=()
                        for (( i=0; i<total; i++ )); do
                            (( states[i] )) && out+=("${PRELOADED_KEYS[$i]}") || true
                        done
                        _RESULT="${out[*]:-}"
                        _RC=0
                    else  # Back
                        _RC=1
                    fi
                    return 0 ;;
            esac
        fi
    done
}

# ---------------------------------------------------------------------------
# Main — state machine with back navigation (Esc = 255 in whiptail; _RC=1 in custom TUI)
# ---------------------------------------------------------------------------

main() {
    if [[ "${EUID}" == "0" ]]; then
        echo "ERROR: Do not run as root — the script will prompt for sudo when needed." >&2
        exit 1
    fi

    echo "Checking requirements..."
    check_requirements
    echo "Detecting OS..."
    detect_os
    echo "Ensuring Ansible is installed..."
    ensure_ansible
    echo "Ensuring TUI tool is available..."
    ensure_tui_tool

    echo "Loading software list..."
    preload_toggles

    echo "Loading profiles..."
    load_profiles

    echo "Installing Ansible collections..."
    install_collections

    clear

    local de_choice="none" configure_de="false"
    local pkg_vars=() have_pkg_vars=false
    local state="de"

    while true; do
        case "${state}" in

            de)
                screen_de
                [[ ${_RC} -ne 0 ]] && clear && echo "Cancelled." && exit 0
                de_choice="${_RESULT}"
                state="configure_de" ;;

            configure_de)
                if [[ "${de_choice}" != "none" ]]; then
                    screen_configure_de "${de_choice}"
                    [[ ${_RC} -eq 255 ]] && state="de" && continue
                    configure_de=$([[ ${_RC} -eq 0 ]] && echo "true" || echo "false")
                fi
                state="review" ;;

            review)
                screen_review
                if [[ ${_RC} -ne 0 ]]; then
                    # Esc or Cancel → back
                    state=$([[ "${de_choice}" != "none" ]] && echo "configure_de" || echo "de")
                    continue
                fi
                case "${_RESULT}" in
                    defaults)
                        pkg_vars=(); have_pkg_vars=false; state="confirm" ;;
                    customise)
                        state="checklist" ;;
                    profile)
                        profiles_tui
                        if [[ ${_RC} -eq 0 ]]; then
                            local prof_idx="${_RESULT}"
                            local -a pst
                            read -ra pst <<< "${PROF_STATES[$prof_idx]}"
                            pkg_vars=()
                            for (( i=0; i<${#PRELOADED_KEYS[@]}; i++ )); do
                                if (( pst[i] )); then
                                    pkg_vars+=("${PRELOADED_KEYS[$i]}=true")
                                else
                                    pkg_vars+=("${PRELOADED_KEYS[$i]}=false")
                                fi
                            done
                            have_pkg_vars=true
                            state="confirm"
                        fi
                        # If profiles_tui was cancelled, stay in review
                        ;;
                esac ;;

            checklist)
                checklist_tui
                if [[ ${_RC} -ne 0 ]]; then state="review"; continue; fi

                local selected_keys=()
                read -ra selected_keys <<< "${_RESULT}" 2>/dev/null || true

                pkg_vars=()
                for key in "${PRELOADED_KEYS[@]}"; do
                    local found=false
                    for sel in "${selected_keys[@]+"${selected_keys[@]}"}"; do
                        [[ "${sel}" == "${key}" ]] && found=true && break
                    done
                    pkg_vars+=("${key}=$([[ "${found}" == true ]] && echo true || echo false)")
                done
                have_pkg_vars=true
                state="confirm" ;;

            confirm)
                local de_vars=()
                case "${de_choice}" in
                    kde)
                        de_vars=("install_kde_plasma=true" "configure_kde_plasma=${configure_de}"
                                 "install_gnome=false"     "configure_gnome=false") ;;
                    gnome)
                        de_vars=("install_gnome=true"      "configure_gnome=${configure_de}"
                                 "install_kde_plasma=false" "configure_kde_plasma=false") ;;
                    none)
                        de_vars=("install_kde_plasma=false" "configure_kde_plasma=false"
                                 "install_gnome=false"      "configure_gnome=false") ;;
                esac

                local all_extra=("${de_vars[@]}")
                [[ "${have_pkg_vars}" == true ]] && all_extra+=("${pkg_vars[@]}")

                local extra_str=""
                [[ ${#all_extra[@]} -gt 0 ]] \
                    && extra_str=$(printf ' %s' "${all_extra[@]}") && extra_str="${extra_str:1}"

                export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"
                local ansible_cmd="ansible-playbook ${ANSIBLE_DIR}/site.yaml -i localhost, -c local -K"
                [[ -n "${extra_str}" ]] && ansible_cmd+=" --extra-vars \"${extra_str}\""

                screen_confirm "${ansible_cmd}"
                if [[ ${_RC} -ne 0 ]]; then
                    state=$([[ "${have_pkg_vars}" == true ]] && echo "checklist" || echo "review")
                    continue
                fi

                clear
                echo "Running: ${ansible_cmd}"
                echo ""
                eval "${ansible_cmd}"
                exit 0 ;;
        esac
    done
}

main "$@"
