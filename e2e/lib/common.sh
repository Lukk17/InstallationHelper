#!/usr/bin/env bash
#
# Shared helpers for the end-to-end harness. Sourced, never executed directly.

set -euo pipefail

# shellcheck source=host.sh
source "$(dirname "${BASH_SOURCE[0]}")/host.sh"

# Every check sources this file, so this is the one place that stops a check running on the machine
# that started the harness. A check runs only inside the gate container, which e2e/run.sh starts by
# itself. Reading files counts too: a check that only reads is still a test, and tests run in a
# container, never on the owner's computer.
if ! e2e_inside_gate; then
    cat >&2 <<EOF
REFUSED: $(basename "${BASH_SOURCE[1]:-${0}}") is a check, and checks run only inside the gate container.
Nothing was run. Start the harness through e2e/run.sh, which builds e2e/gate/Dockerfile and runs
every tier inside it:

    bash e2e/run.sh
EOF
    exit 2
fi

E2E_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# E2E_REPO_ROOT lets a check run against a copy of the tree, which is how the
# checks themselves are tested: point it at a copy carrying the old bug and the
# check must fail. A check never proven to fail is not a check.
REPO_ROOT="$(cd "${E2E_REPO_ROOT:-${E2E_ROOT}/..}" && pwd)"
# Both are read only by the checks that source this file, never inside it, so shellcheck sees an
# assignment with no reader. Not exported instead, because that would hand both paths to every
# python, docker and ansible child a check starts, which is a behaviour change to silence a linter.
# shellcheck disable=SC2034
ANSIBLE_DIR="${REPO_ROOT}/setup/ansible"
# shellcheck disable=SC2034
RUNS_DIR="${E2E_ROOT}/runs"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_DIM=""; C_OFF=""
fi

CHECKS_RUN=0
CHECKS_FAILED=0
CHECKS_SKIPPED=0
FAILED_NAMES=()
SKIPPED_NAMES=()

log()   { printf '%s\n' "$*"; }
info()  { printf '%s>>%s %s\n' "${C_BLUE}" "${C_OFF}" "$*"; }
dim()   { printf '%s   %s%s\n' "${C_DIM}" "$*" "${C_OFF}"; }
warn()  { printf '%sWARN%s %s\n' "${C_YELLOW}" "${C_OFF}" "$*"; }

# pass <name>            record a passing check
# fail <name> <detail>   record a failing check, never exits on its own so one
#                        failure does not hide the rest of the run
pass() {
    CHECKS_RUN=$((CHECKS_RUN + 1))
    printf '%sPASS%s %s\n' "${C_GREEN}" "${C_OFF}" "$1"
}

fail() {
    CHECKS_RUN=$((CHECKS_RUN + 1))
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    FAILED_NAMES+=("$1")
    printf '%sFAIL%s %s\n' "${C_RED}" "${C_OFF}" "$1"
    [[ $# -gt 1 ]] && printf '     %s\n' "$2"
    return 0
}

# skip <name> <why>  record a check that could not run.
#
# Separate from pass on purpose. A check that did not run is not a check that passed, and a
# summary reading "all passed" when half of it was skipped is exactly the misleading output this
# suite exists to eliminate. Skipping does not fail the run, because a missing optional tool is
# not a defect in the code under test, but it is always named.
skip() {
    CHECKS_SKIPPED=$((CHECKS_SKIPPED + 1))
    SKIPPED_NAMES+=("$1")
    printf '%sSKIP%s %s\n' "${C_YELLOW}" "${C_OFF}" "$1"
    [[ $# -gt 1 ]] && printf '     %s\n' "$2"
    return 0
}

# assert_eq <name> <expected> <actual>
assert_eq() {
    if [[ "$2" == "$3" ]]; then
        pass "$1"
    else
        fail "$1" "expected [$2], got [$3]"
    fi
}

# finish <label>  print the tally and exit, non-zero if anything failed.
#
# Exits explicitly rather than letting the last command's status propagate. A
# harness that reports failures and still exits zero is worse than no harness,
# because every caller reads it as a pass, which is the same shape of defect this
# suite exists to catch. Every check script must end with this.
finish() {
    echo
    local skipnote=""
    if [[ "${CHECKS_SKIPPED:-0}" -gt 0 ]]; then
        skipnote=", ${CHECKS_SKIPPED} SKIPPED and therefore unproven"
    fi

    if [[ "${CHECKS_FAILED:-0}" -eq 0 ]]; then
        if [[ "${CHECKS_SKIPPED:-0}" -gt 0 ]]; then
            printf '%s%s: %d passed%s%s\n' "${C_YELLOW}" "$1" "${CHECKS_RUN:-0}" "${skipnote}" "${C_OFF}"
            for n in "${SKIPPED_NAMES[@]}"; do printf '  ? %s\n' "${n}"; done
        else
            printf '%s%s: %d checks, all passed%s\n' "${C_GREEN}" "$1" "${CHECKS_RUN:-0}" "${C_OFF}"
        fi
        exit 0
    fi

    printf '%s%s: %d checks, %d FAILED%s%s\n' "${C_RED}" "$1" "${CHECKS_RUN:-0}" "${CHECKS_FAILED}" "${skipnote}" "${C_OFF}"
    for n in "${FAILED_NAMES[@]}"; do printf '  - %s\n' "${n}"; done
    [[ "${CHECKS_SKIPPED:-0}" -gt 0 ]] && for n in "${SKIPPED_NAMES[@]}"; do printf '  ? %s\n' "${n}"; done
    exit 1
}

# find_runnable_python  ->  prints the interpreter a check must use, or nothing with status 2
#
# The search itself belongs to setup/pinned_values/pinned_values.sh, which tries python3, python and
# py in turn and asks each candidate its version rather than trusting that it resolved, which is how
# it refuses the Windows app-execution-alias stub. That file is sourced here rather than by every
# check, so the harness has one answer to this question instead of one per check.
#
# Every check that ran Python named the interpreter itself as `${PYTHON:-python}` until 2026-09-02.
# Git Bash on this machine has python and no python3, WSL Ubuntu has python3 and no python, so under
# WSL that expansion resolved to nothing, `set -e` ended the script on the assignment, and fourteen
# checks exited with no PASS, no FAIL and no tally at all. That is the shape this whole harness
# exists to refuse, so the status here is one a caller has to read.
find_runnable_python() {
    if [[ -z "${E2E_PINNED_VALUES_SOURCED:-}" ]]; then
        local adapter="${REPO_ROOT}/setup/pinned_values/pinned_values.sh"
        if [[ ! -f "${adapter}" ]]; then
            printf 'e2e: %s is missing, and it owns the interpreter search\n' "${adapter}" >&2
            return 2
        fi
        # shellcheck source=../../setup/pinned_values/pinned_values.sh
        source "${adapter}"
        E2E_PINNED_VALUES_SOURCED=1
    fi

    pinned_values_python
}

# require_python <claim> <label>  ->  leaves the interpreter in PYTHON, or reports <claim> as SKIP
#                                     and ends the check through finish
#
# For a check that cannot assert anything at all without Python. One that needs it for only part of
# what it asserts calls find_runnable_python itself and skips that part, the way compose_and_docs.sh
# does, because ending the whole check there would throw away assertions that do not need it.
require_python() {
    # shellcheck disable=SC2034  # read by the caller, which shellcheck cannot see from in here
    PYTHON="$(find_runnable_python)" && return 0

    skip "$1" "no Python 3.11 or newer on PATH (tried python3, python and py), so this check could not run"
    finish "$2"
}

# assert_python_ran <status> <label>  ->  returns, or fails the check and ends it
#
# The other half of the same rule. Finding an interpreter is not the same as it finishing: a report
# assignment whose Python raised takes the script down under `set -e` just as silently as one that
# never started. Called with the status of the command substitution, which the callsite has to keep
# with `|| status=$?` because the assignment itself would otherwise be the thing that dies.
assert_python_ran() {
    [[ "$1" -eq 0 ]] && return 0

    fail "the Python half of this check did not run to completion, so nothing here is proven" \
         "${PYTHON:-python} exited $1, and its own error is above"
    finish "$2"
}

# sha256_of <file>  ->  the file's SHA-256 in lowercase hex. sha256sum on Linux and Git Bash,
#                       shasum on stock macOS, which ships no sha256sum.
sha256_of() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        printf 'e2e: neither sha256sum nor shasum is on PATH, so %s cannot be verified\n' "$1" >&2
        return 2
    fi
}

# fetch_url <label> <url> <destination>  ->  downloads to the destination, retrying every error
#
# Returns 1 when curl gives up, with the partial destination removed and
# "<label>: downloading <url> failed, curl exited <status>" on stderr.
fetch_url() {
    local label="$1" url="$2" destination="$3" curl_status=0
    curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors --connect-timeout 15 --max-time 600 \
        -o "${destination}" "${url}" || curl_status=$?
    if [[ ${curl_status} -ne 0 ]]; then
        rm -f "${destination}"
        printf '%s: downloading %s failed, curl exited %d\n' "${label}" "${url}" "${curl_status}" >&2
        return 1
    fi
}

# The version a shellcheck binary reports, or nothing. Not written in the `name <args>  ->` form the
# other helpers use, because ShellCheck reads a comment that opens with its own name as a directive
# and stops analysing the file. The Windows build ends its lines with a carriage return.
shellcheck_version_of() {
    "$1" --version 2>/dev/null | tr -d '\r' | sed -n 's/^version: //p'
}

# pinned_shellcheck  ->  prints the path of a shellcheck at the version setup/pinned_values pins
#
# A shellcheck on PATH is used only when it reports that exact version, because a different release
# warns about different things and the same tree would pass on one machine and fail on another. That
# happened: shellcheck was installed on the GitHub runner and nowhere on the owner's machine, so four
# warnings passed every local run and failed the sweep. Otherwise the release asset for this shell's
# platform is downloaded once into e2e/.cache/shellcheck/<version>/<platform>/ and kept there. Git
# Bash takes the Windows build, WSL and Linux the Linux one, macOS its own.
#
# The archive is checked against its pinned SHA-256 on every call, not only after the download, and
# the binary is extracted from it afresh each time, so nothing runs that did not come out of an
# archive that matched. A cached archive that stops matching is reported and left in place rather
# than replaced, because a file that changed after it was verified is something to look at.
# Returns 2, with the reason on stderr and nothing on stdout, when no such binary can be had.
pinned_shellcheck() {
    find_runnable_python >/dev/null || return 2

    local version
    version="$(pinned_value shellcheck_version)" || return 2

    local on_path
    if on_path="$(command -v shellcheck 2>/dev/null)" \
        && [[ "$(shellcheck_version_of "${on_path}")" == "${version}" ]]; then
        printf '%s\n' "${on_path}"
        return 0
    fi

    local url_pin sha_pin binary_name=shellcheck
    case "$(uname -s)-$(uname -m)" in
        Linux-x86_64)
            url_pin=shellcheck_linux_x86_64_url;    sha_pin=shellcheck_linux_x86_64_sha256 ;;
        Linux-aarch64|Linux-arm64)
            url_pin=shellcheck_linux_aarch64_url;   sha_pin=shellcheck_linux_aarch64_sha256 ;;
        Darwin-x86_64)
            url_pin=shellcheck_macos_x86_64_url;    sha_pin=shellcheck_macos_x86_64_sha256 ;;
        Darwin-arm64)
            url_pin=shellcheck_macos_aarch64_url;   sha_pin=shellcheck_macos_aarch64_sha256 ;;
        MINGW*-x86_64|MSYS*-x86_64|CYGWIN*-x86_64)
            url_pin=shellcheck_windows_x86_64_url;  sha_pin=shellcheck_windows_x86_64_sha256
            binary_name=shellcheck.exe ;;
        *)
            printf 'e2e: no ShellCheck release is pinned for %s %s\n' "$(uname -s)" "$(uname -m)" >&2
            return 2 ;;
    esac

    local url expected
    url="$(pinned_value "${url_pin}")" || return 2
    expected="$(pinned_value "${sha_pin}")" || return 2

    local platform="${url_pin#shellcheck_}"
    platform="${platform%_url}"
    local cache_dir="${REPO_ROOT}/e2e/.cache/shellcheck/${version}/${platform}"
    local archive="${cache_dir}/${url##*/}"
    local fetched=false

    if [[ ! -f "${archive}" ]]; then
        if ! command -v curl &>/dev/null; then
            printf 'e2e: ShellCheck %s is not cached at %s and curl is not on PATH to fetch it\n' \
                "${version}" "${cache_dir}" >&2
            return 2
        fi
        mkdir -p "${cache_dir}" || return 2
        printf 'e2e: fetching ShellCheck %s for %s from %s\n' "${version}" "${platform}" "${url}" >&2
        if ! fetch_url e2e "${url}" "${archive}.part"; then
            printf 'e2e: ShellCheck %s is needed once, after which it is kept in %s\n' "${version}" "${cache_dir}" >&2
            return 2
        fi
        mv -f "${archive}.part" "${archive}" || return 2
        fetched=true
    fi

    local actual
    actual="$(sha256_of "${archive}")" || return 2
    if [[ "${actual}" != "${expected}" ]]; then
        if [[ "${fetched}" == true ]]; then
            rm -f "${archive}"
            printf 'e2e: the download of %s does not match its pinned SHA-256, so it was deleted unused.\n' \
                "${url}" >&2
        else
            printf 'e2e: the cached %s does not match its pinned SHA-256 and was not used. Delete it to fetch it again.\n' \
                "${archive}" >&2
        fi
        printf '     expected %s (%s in setup/pinned_values/pinned_values.toml)\n     actual   %s\n' \
            "${expected}" "${sha_pin}" "${actual}" >&2
        return 2
    fi

    local binary="${cache_dir}/${binary_name}"
    rm -f "${binary}"
    case "${archive}" in
        *.zip)    unzip -o -q "${archive}" "${binary_name}" -d "${cache_dir}" || return 2 ;;
        *.tar.gz) tar -xzf "${archive}" -C "${cache_dir}" --strip-components=1 \
                      "shellcheck-v${version}/${binary_name}" || return 2 ;;
        *)
            printf 'e2e: %s is neither a zip nor a tar.gz, so it cannot be unpacked\n' "${archive}" >&2
            return 2 ;;
    esac
    chmod +x "${binary}" || return 2

    local reported
    reported="$(shellcheck_version_of "${binary}")"
    if [[ "${reported}" != "${version}" ]]; then
        printf 'e2e: %s reports version [%s] where %s is pinned\n' "${binary}" "${reported}" "${version}" >&2
        return 2
    fi

    printf '%s\n' "${binary}"
}

# Extract "<key> true|false" for every boolean toggle in a group_vars file,
# independently of setup.sh, so tier 1 can compare the two and catch drift.
yaml_bool_toggles() {
    sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//' "$1" \
        | grep -E '^[a-z0-9_]+: (true|false)$' \
        | tr -d ':'
}

# derivative_mapping_lines <derivative-file>  ->  every software_mapping entry line, as written
#
# The one definition of a derivative entry for the shell side of the harness, a two-space indented key
# followed by a flow mapping, read by tier 1 and tier 2 alike. toggle_coverage.sh counts the same file's
# entries with a YAML loader as well and fails when the two disagree, so an entry written in block style
# cannot slip past this rule unseen.
derivative_mapping_lines() {
    grep -E '^  [a-z0-9_]+: \{' "$1" || true
}

# derivative_mapping_keys <derivative-file>  ->  the key of every software_mapping entry, one per line
derivative_mapping_keys() {
    derivative_mapping_lines "$1" | sed -E 's/^  ([a-z0-9_]+):.*/\1/'
}

# companion_packages_of <family-file>  ->  "<key> <package>" per line, one for every package of every
#                                          companion_packages entry
#
# companion_packages in vars/<OS>.yaml names the packages a role installs under a software toggle beside
# that toggle's mapping, one flow sequence per line, key: ["a", "b"]. The manual install check counts
# them as dictionary names and tier 2 resolves them, so a name listed there is checked like a mapping.
companion_packages_of() {
    tr -d '\r' <"$1" | awk '
        /^companion_packages:/ { inside = 1; next }
        /^[^[:space:]#]/ { inside = 0 }
        inside && /^  [a-z0-9_]+: \[/ {
            key = $1; sub(/:$/, "", key)
            line = $0; sub(/^[^[]*\[/, "", line); sub(/\].*$/, "", line)
            n = split(line, names, /,/)
            for (i = 1; i <= n; i++) {
                gsub(/["\047[:space:]]/, "", names[i])
                if (names[i] != "") print key " " names[i]
            }
        }'
}

# lineage_companion_packages_of <family-file> <lineage>  ->  "<key> <package>" per line, for every
#                                                         package lineage_companion_packages puts in
#                                                         front of a companion_packages entry on that
#                                                         lineage, ubuntu or debian in vars/Debian.yaml
lineage_companion_packages_of() {
    tr -d '\r' <"$1" | awk -v lineage="$2" '
        /^lineage_companion_packages:/ { inside = 1; next }
        /^[^[:space:]#]/ { inside = 0 }
        inside && /^  [a-z0-9_]+:[[:space:]]*$/ { current = $1; sub(/:$/, "", current); next }
        inside && current == lineage && /^    [a-z0-9_]+: \[/ {
            key = $1; sub(/:$/, "", key)
            line = $0; sub(/^[^[]*\[/, "", line); sub(/\].*$/, "", line)
            n = split(line, names, /,/)
            for (i = 1; i <= n; i++) {
                gsub(/["\047[:space:]]/, "", names[i])
                if (names[i] != "") print key " " names[i]
            }
        }'
}

# prepare_detect_os <linux_vars_file> <macos_vars_file>  -> 0 and the real detect_os and
#                                                            debian_lineage defined, or 1 and
#                                                            neither defined
#
# Defines the wizard's own detect_os out of setup.sh rather than reimplementing its logic, the
# same way wizard_toggle_keys above resolves the wizard's own toggles. The caller still has to
# call detect_os itself, rather than this function calling it, and that is deliberate rather than
# an oversight: a failure inside an eval'd function is only guaranteed to abort the script under
# set -e, which is what run.sh's own tally-line check needs to catch a future version of this
# exact regression, when that function is called from the top level of the script that sourced
# common.sh. Calling it from inside a second function, as an earlier version of this helper did,
# lets bash 5.2 (WSL, and the GitHub runner) quietly continue past the exact failure this helper
# exists to surface, proven by running both shapes against the regression.
#
# detect_os calls a second helper, debian_lineage, on every Debian-family host, so both are
# extracted and eval'd together. Defining only detect_os, which is what list_software.sh and
# print_command_resolution.sh both did until 2026-10-11, calls an undefined function the moment
# debian_lineage exists and dies with "command not found" on every Debian-family host, Ubuntu
# included, and nowhere else, which is why it reached the GitHub runner before it reached either
# check's own author: neither Git Bash nor macOS has an /etc/os-release, so OS_FAMILY never
# resolves to Debian there and the call this check depends on never happens.
prepare_detect_os() {
    local linux_vars="$1" macos_vars="$2"
    local setup_sh="${REPO_ROOT}/setup/setup.sh"
    local detect_os_text debian_lineage_text
    detect_os_text="$(sed -n '/^detect_os()/,/^}/p' "${setup_sh}")"
    debian_lineage_text="$(sed -n '/^debian_lineage()/,/^}/p' "${setup_sh}")"
    [[ -n "${detect_os_text}" && -n "${debian_lineage_text}" ]] || return 1

    # Read only by detect_os and debian_lineage, which are eval'd below and which shellcheck
    # cannot see into.
    # shellcheck disable=SC2034
    LINUX_VARS="${linux_vars}"
    # shellcheck disable=SC2034
    MACOS_VARS="${macos_vars}"
    eval "${debian_lineage_text}"
    eval "${detect_os_text}"
}

# The keys the wizard's checklist offers, one per line, in the wizard's own order.
#
# This is the harness's only route to that answer, and it evaluates the functions setup.sh ships
# rather than restating the rule they encode. The rule used to live twice, once in the wizard and
# once as a `^install_` sweep inside container.sh, and the two disagreed in both directions for as
# long as they both existed: the sweep could not see the four system settings whose names do not
# begin with install_, and it swept up the two desktop keys the wizard deliberately keeps off the
# checklist because the desktop has a screen of its own. That is defect class 2 in docs/regression_ledger.md, the
# same rule implemented twice and then disagreeing, sitting inside the harness meant to catch it.
#
# Run under setup.sh's own IFS, because that file sets IFS to newline and tab at the top and its
# expansions are written against it. Everything the extracted functions reach for is extracted too,
# so nothing below is a paraphrase.
#
# $1 is group_vars/all.yaml and $2 the per-OS file, whose value wins, which is the precedence
# site.yaml gives them.
# Returns 3, and writes nothing to stdout, when setup.sh no longer ships a piece this needs or the
# rule resolves no toggle at all. An empty list would read to a caller as "no software", which is a
# generated scenario that installs nothing while reporting a pass over everything.
wizard_toggle_keys() {
    local all_vars="$1" os_vars="$2"
    local setup_sh="${REPO_ROOT}/setup/setup.sh"
    local keys=""

    if [[ -f "${setup_sh}" ]]; then
        keys="$(
            IFS=$'\n\t'
            for piece in "$(grep -m1 '^EXCLUDED_VARS=' "${setup_sh}")" \
                         "$(grep -m1 '^DE_KEYS=' "${setup_sh}")" \
                         "$(sed -n '/^declare -A LABEL_OVERRIDES=(/,/^)$/p' "${setup_sh}")" \
                         "$(sed -n '/^format_label()/,/^}/p' "${setup_sh}")" \
                         "$(sed -n '/^is_de_key()/,/^}/p' "${setup_sh}")" \
                         "$(sed -n '/^read_boolean_toggles()/,/^}/p' "${setup_sh}")" \
                         "$(sed -n '/^preload_toggles()/,/^}/p' "${setup_sh}")"; do
                [[ -z "${piece}" ]] && exit 3
                eval "${piece}"
            done

            # Read only by the functions eval'd above, which shellcheck cannot see, so it
            # reports all four as unused. PRELOADED_KEYS escapes that because it is printed.
            # shellcheck disable=SC2034
            ALL_VARS="${all_vars}"
            # shellcheck disable=SC2034
            OS_VARS_FILE="${os_vars}"
            # shellcheck disable=SC2034
            PRELOADED_ITEMS=(); PRELOADED_KEYS=()
            preload_toggles
            [[ ${#PRELOADED_KEYS[@]} -eq 0 ]] && exit 3
            printf '%s\n' "${PRELOADED_KEYS[@]}"
        )" || keys=""
    fi

    if [[ -z "${keys}" ]]; then
        {
            printf 'ERROR: the wizard checklist could not be resolved out of %s\n' "${setup_sh}"
            printf '       It must still ship EXCLUDED_VARS, DE_KEYS, LABEL_OVERRIDES, format_label,\n'
            printf '       is_de_key, read_boolean_toggles and preload_toggles, and those must resolve\n'
            printf '       at least one toggle out of %s and %s.\n' "${all_vars}" "${os_vars}"
        } >&2
        return 3
    fi

    printf '%s\n' "${keys}"
}

# wizard_all_software_keeps_off  ->  the checklist keys --software all leaves off, one per line
#
# Read out of setup.sh's ALL_SOFTWARE_KEEPS_OFF rather than restated, for the reason wizard_toggle_keys gives,
# so an all_software scenario leaves off what the wizard's --software all leaves off. Returns 3 when setup.sh
# no longer defines it, because an empty answer here would turn on what the wizard keeps off.
wizard_all_software_keeps_off() {
    local setup_sh="${REPO_ROOT}/setup/setup.sh" line
    line="$(grep -m1 '^ALL_SOFTWARE_KEEPS_OFF=' "${setup_sh}" 2>/dev/null || true)"
    if [[ -z "${line}" ]]; then
        printf 'ERROR: %s no longer defines ALL_SOFTWARE_KEEPS_OFF\n' "${setup_sh}" >&2
        return 3
    fi
    (
        eval "${line}"
        tr '|' '\n' <<<"${ALL_SOFTWARE_KEEPS_OFF}" | grep . || true
    )
}

# opencode_cli_pair  ->  "v1 <package>" and "v2 <package>", one per line
#
# OpenCode's two npm packages as setup/ansible/tasks/opencode_version.yaml declares them in ih_opencode_cli, which
# opencode_unix.yaml installs as {{ opencode_cli_package }} rather than by name.
opencode_cli_pair() {
    sed -n '/^    ih_opencode_cli:$/,/^    [a-z_]*:$/p' "${ANSIBLE_DIR}/tasks/opencode_version.yaml" 2>/dev/null \
        | grep -E '^      v[12]: ' | sed -E 's/^ +(v[12]): "?([^"]+)"?$/\1 \2/' | sort
}

# ai_tools_npm_packages  ->  every npm package an ai_tools *_unix.yaml installs, one per line
#
# The literal npm_pkg values, and both OpenCode packages for the consumer that names the selected one.
ai_tools_npm_packages() {
    local f named
    for f in "${ANSIBLE_DIR}"/roles/ai_tools/tasks/*_unix.yaml; do
        [[ "$(basename "${f}")" == "npm_install_unix.yaml" ]] && continue
        grep -hE '^\s*npm_pkg:' "${f}" 2>/dev/null | sed -E 's/^\s*npm_pkg:\s*//; s/"//g; s/\s+$//'
    done | while IFS= read -r named; do
        if [[ "${named}" == "{{ opencode_cli_package }}" ]]; then
            opencode_cli_pair | awk '{print $2}'
        else
            printf '%s\n' "${named}"
        fi
    done | sort -u
}

timestamp() { date -u +%Y-%m-%dT%H-%M-%SZ; }
