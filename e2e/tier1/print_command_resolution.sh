#!/usr/bin/env bash
#
# Tier 1: --print-command must resolve a selection into the command the run would really use.
#
# --print-command exists so that a person or a pipeline can read what a set of options resolves to
# before spending an hour on it, and it is the only place where the resolution of every branch can
# be inspected without installing anything. Its value is entirely in the resolution being the real
# one: it shares resolve_overrides and build_playbook_args with the real run and with --verify-only
# precisely so the three cannot drift. Asserting only its exit code would prove none of that, since
# a resolution that silently dropped every toggle would still exit 0 and still print a command that
# looks like a command.
#
# This repository has already paid for that class of defect twice. A toggle the wizard could not see
# was a toggle the user could not control, and a per-OS value the wizard read in the wrong order
# meant the checklist showed one state while the playbook acted on another. Both were invisible from
# the exit code and both were visible in what the run resolved to.
#
# The toggle keys are read out of group_vars rather than written down here, so this check and the
# wizard are compared against the same declared set rather than against a copy of it that ages. A
# key that reaches the resolution and is not in group_vars, or a key in group_vars that the
# resolution never mentions, fails by name.
#
# Nothing here changes the machine. --print-command answers at line 1402 of setup.sh and exits,
# above prepare_become_password, ensure_ansible and system_upgrade.
#
# The six wizard runs are started together and waited for once, rather than one after another. Each
# one is an independent read-only process, and on Git Bash a single run costs nine seconds inside
# preload_toggles and up to twenty-six with a full software baseline, all of it process creation. Run
# in sequence they took nearly two minutes of a gate that is supposed to answer in seconds.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: --print-command resolution"

SETUP_SH="${REPO_ROOT}/setup/setup.sh"
GROUP_VARS_DIR="${ANSIBLE_DIR}/group_vars"
PROFILE_NAME="linux_live"
PROFILE_FILE="${ANSIBLE_DIR}/profiles/${PROFILE_NAME}.yaml"

if [[ ! -f "${SETUP_SH}" ]]; then
    fail "the wizard is missing, so this check proves nothing" "${SETUP_SH}"
    finish "print-command resolution"
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

# --- which group_vars files the wizard would read ----------------------------
# detect_os is taken out of setup.sh and run rather than reimplemented, so this check asks the same
# question the wizard asks and gets the same answer on macOS as on Linux. It reads only LINUX_VARS
# and MACOS_VARS, which are set here from the repository under test.
# Both are read by detect_os, which is eval'd out of setup.sh below and which shellcheck
# cannot see into.
# shellcheck disable=SC2034
LINUX_VARS="${GROUP_VARS_DIR}/linux.yaml"
# shellcheck disable=SC2034
MACOS_VARS="${GROUP_VARS_DIR}/macos.yaml"

detect_os_text="$(sed -n '/^detect_os()/,/^}/p' "${SETUP_SH}")"
excluded_line="$(grep -m1 '^EXCLUDED_VARS=' "${SETUP_SH}" || true)"
de_keys_line="$(grep -m1 '^DE_KEYS=' "${SETUP_SH}" || true)"

if [[ -z "${detect_os_text}" || -z "${excluded_line}" || -z "${de_keys_line}" ]]; then
    fail "setup.sh no longer defines detect_os, EXCLUDED_VARS and DE_KEYS, so the expected key set cannot be built" \
         "one of the three was not found in ${SETUP_SH}"
    finish "print-command resolution"
fi

eval "${excluded_line}"
eval "${de_keys_line}"
eval "${detect_os_text}"
detect_os

# --- the key set the resolution is expected to name --------------------------
# Independent of the wizard's own parse: the YAML is read here through the harness helper, the
# hidden variables are removed, and the four desktop keys are removed because the wizard gives them
# a screen of their own and never puts them on the checklist.
is_de_key_here() {
    local candidate
    for candidate in "${DE_KEYS[@]}"; do
        [[ "${candidate}" == "$1" ]] && return 0
    done
    return 1
}

EXPECTED_KEYS=()
while read -r key _; do
    [[ -z "${key}" ]] && continue
    is_de_key_here "${key}" && continue
    EXPECTED_KEYS+=("${key}")
done < <(cat <(yaml_bool_toggles "${GROUP_VARS_DIR}/all.yaml") <(yaml_bool_toggles "${OS_VARS_FILE}") \
         | grep -vE "^(${EXCLUDED_VARS}) " | awk '!seen[$1]++')

if [[ ${#EXPECTED_KEYS[@]} -lt 3 ]]; then
    fail "fewer than three selectable toggles were read out of group_vars, so this check proves nothing" \
         "read ${#EXPECTED_KEYS[@]} from ${GROUP_VARS_DIR}/all.yaml and ${OS_VARS_FILE}"
    finish "print-command resolution"
fi

# Three keys taken from the declared set rather than named here. First, second and last, so the two
# that are turned on are not the same key as the one the enable-and-disable case argues over.
KEY_FIRST="${EXPECTED_KEYS[0]}"
KEY_SECOND="${EXPECTED_KEYS[1]}"
KEY_LAST="${EXPECTED_KEYS[$((${#EXPECTED_KEYS[@]} - 1))]}"

# The four desktop key names come out of DE_KEYS in setup.sh and are checked against group_vars
# below, so a desktop toggle renamed in one place and not the other fails here rather than resolving
# to a variable the playbook has never heard of.
de_key_matching() { printf '%s\n' "${DE_KEYS[@]}" | grep -m1 -E "$1" || true; }

KDE_INSTALL="$(de_key_matching '^install_.*kde')"
KDE_CONFIGURE="$(de_key_matching '^configure_.*kde')"
GNOME_INSTALL="$(de_key_matching '^install_.*gnome')"
GNOME_CONFIGURE="$(de_key_matching '^configure_.*gnome')"

# --- the six runs, started together ------------------------------------------
start_case() {
    local name="$1"; shift
    (
        local rc=0
        bash "${SETUP_SH}" --print-command "$@" \
            >"${WORK_DIR}/${name}.out" 2>"${WORK_DIR}/${name}.err" </dev/null || rc=$?
        printf '%s\n' "${rc}" >"${WORK_DIR}/${name}.rc"
    ) &
}

start_case software_all      --software all
start_case software_none     --software none --enable "${KEY_FIRST},${KEY_SECOND}"
start_case enable_and_disable --software all --enable "${KEY_LAST}" --disable "${KEY_LAST}"
start_case kde_configure     --desktop-environment kde   --desktop-action configure
start_case gnome_install     --desktop-environment gnome --desktop-action install
start_case profile           --profile "${PROFILE_NAME}"
wait || true

# resolved_command <name>  the command line that run printed, or an EXIT line describing the failure.
#
# Everything above it on standard output is the wizard's own progress reporting, so the command is
# the last line.
resolved_command() {
    local name="$1" rc
    rc="$(cat "${WORK_DIR}/${name}.rc" 2>/dev/null || echo missing)"
    if [[ "${rc}" != "0" ]]; then
        printf 'EXIT %s %s\n' "${rc}" "$(tr '\n' ' ' <"${WORK_DIR}/${name}.err" 2>/dev/null | cut -c1-160)"
        return 0
    fi
    tail -1 "${WORK_DIR}/${name}.out"
}

# keys_resolved_to <line> <true|false>  the toggle names the command sets to that value, sorted.
#
# One pass rather than a lookup per key. Asking grep about each of a hundred keys in turn costs a
# hundred processes, and a process here is expensive enough that it doubled the runtime of this
# check on Git Bash before it was written this way.
keys_resolved_to() { grep -oE "[a-z0-9_]+=$2" <<<"$1" | sed "s/=$2\$//" | sort; }

# count_assignments <line> <true|false>
count_assignments() { keys_resolved_to "$1" "$2" | grep -c . || true; }

# assignment_present <line> <key> <true|false>
assignment_present() { grep -qE "(^| |\\\\ )$2=$3( |\\\\ |\$)" <<<"$1"; }

# --- --software all -----------------------------------------------------------
line="$(resolved_command software_all)"
if [[ "${line}" != ansible-playbook* ]]; then
    fail "--software all did not resolve to a command" "${line}"
else
    expected_sorted="$(printf '%s\n' "${EXPECTED_KEYS[@]}" | sort)"
    resolved_true="$(keys_resolved_to "${line}" true)"
    missing="$(comm -23 <(echo "${expected_sorted}") <(echo "${resolved_true}") || true)"
    unexpected="$(comm -13 <(echo "${expected_sorted}") <(echo "${resolved_true}") || true)"
    n_true="$(count_assignments "${line}" true)"
    n_false="$(count_assignments "${line}" false)"

    if [[ -n "${missing}" ]]; then
        fail "--software all leaves declared toggles out of the resolved command" \
             "$(grep -c . <<<"${missing}") missing, first five: $(head -5 <<<"${missing}" | tr '\n' ' ')"
    elif [[ -n "${unexpected}" ]]; then
        fail "--software all resolves toggles group_vars does not declare" \
             "$(grep -c . <<<"${unexpected}") of them, first five: $(head -5 <<<"${unexpected}" | tr '\n' ' ')"
    elif [[ "${n_false}" -ne 0 ]]; then
        fail "--software all resolves some toggle to false" \
             "${n_false} of them, first: $(grep -oE '[a-z0-9_]+=false' <<<"${line}" | head -1)"
    elif [[ "${n_true}" -ne "${#EXPECTED_KEYS[@]}" ]]; then
        fail "--software all resolves a different number of toggles than group_vars declares" \
             "resolved ${n_true}, group_vars declares ${#EXPECTED_KEYS[@]}"
    else
        pass "--software all turns on every one of the ${#EXPECTED_KEYS[@]} toggles group_vars declares"
    fi
fi

# --- --software none with two keys enabled -------------------------------------
line="$(resolved_command software_none)"
if [[ "${line}" != ansible-playbook* ]]; then
    fail "--software none with two enabled keys did not resolve to a command" "${line}"
else
    problems=()
    assignment_present "${line}" "${KEY_FIRST}" true  || problems+=("${KEY_FIRST} is not true")
    assignment_present "${line}" "${KEY_SECOND}" true || problems+=("${KEY_SECOND} is not true")
    n_true="$(count_assignments "${line}" true)"
    n_false="$(count_assignments "${line}" false)"
    [[ "${n_true}" -eq 2 ]] || problems+=("${n_true} toggles are true where only the two named should be")
    [[ "${n_false}" -eq $(( ${#EXPECTED_KEYS[@]} - 2 )) ]] \
        || problems+=("${n_false} toggles are false where $(( ${#EXPECTED_KEYS[@]} - 2 )) should be")

    if [[ ${#problems[@]} -eq 0 ]]; then
        pass "--software none --enable ${KEY_FIRST},${KEY_SECOND} turns on those two and nothing else"
    else
        fail "--software none with two enabled keys resolves to the wrong set" "$(printf '%s | ' "${problems[@]}")"
    fi
fi

# --- the same key enabled and disabled ------------------------------------------
# --disable is applied after --enable on purpose, so the option that removes software wins over the
# option that adds it. Driven from a baseline of all, so the assertion is that --disable beats both
# the baseline and --enable rather than only one of them.
line="$(resolved_command enable_and_disable)"
if [[ "${line}" != ansible-playbook* ]]; then
    fail "a key both enabled and disabled did not resolve to a command" "${line}"
else
    problems=()
    assignment_present "${line}" "${KEY_LAST}" false || problems+=("${KEY_LAST} did not end up false")
    n_false="$(count_assignments "${line}" false)"
    [[ "${n_false}" -eq 1 ]] || problems+=("${n_false} toggles are false where only ${KEY_LAST} should be")

    if [[ ${#problems[@]} -eq 0 ]]; then
        pass "--enable and --disable naming ${KEY_LAST} resolves it to disabled"
    else
        fail "a key named in both --enable and --disable does not end up disabled" "$(printf '%s | ' "${problems[@]}")"
    fi
fi

# --- the desktop environment screen ---------------------------------------------
declared_in_group_vars=()
os_toggles="$(yaml_bool_toggles "${OS_VARS_FILE}")"
for key in "${KDE_INSTALL}" "${KDE_CONFIGURE}" "${GNOME_INSTALL}" "${GNOME_CONFIGURE}"; do
    [[ -z "${key}" ]] && continue
    grep -qE "^${key} " <<<"${os_toggles}" && declared_in_group_vars+=("${key}")
done

if [[ ${#declared_in_group_vars[@]} -ne 4 ]]; then
    fail "the four desktop toggles could not be matched against group_vars, so the desktop cases cannot run" \
         "DE_KEYS gave [${KDE_INSTALL} ${KDE_CONFIGURE} ${GNOME_INSTALL} ${GNOME_CONFIGURE}] and $(basename "${OS_VARS_FILE}") declares ${#declared_in_group_vars[@]} of them"
else
    line="$(resolved_command kde_configure)"
    if [[ "${line}" != ansible-playbook* ]]; then
        fail "--desktop-environment kde --desktop-action configure did not resolve to a command" "${line}"
    else
        problems=()
        assignment_present "${line}" "${KDE_INSTALL}" false  || problems+=("${KDE_INSTALL} is not false")
        assignment_present "${line}" "${KDE_CONFIGURE}" true || problems+=("${KDE_CONFIGURE} is not true")
        grep -q "${GNOME_INSTALL}" <<<"${line}" && problems+=("it also decides ${GNOME_INSTALL}")
        [[ "$(( $(count_assignments "${line}" true) + $(count_assignments "${line}" false) ))" -eq 2 ]] \
            || problems+=("it resolves variables beyond the two the desktop screen owns")

        if [[ ${#problems[@]} -eq 0 ]]; then
            pass "kde with configure installs nothing and applies the configuration"
        else
            fail "kde with configure resolves to the wrong desktop variables" "$(printf '%s | ' "${problems[@]}")"
        fi
    fi

    line="$(resolved_command gnome_install)"
    if [[ "${line}" != ansible-playbook* ]]; then
        fail "--desktop-environment gnome --desktop-action install did not resolve to a command" "${line}"
    else
        problems=()
        assignment_present "${line}" "${GNOME_INSTALL}" true     || problems+=("${GNOME_INSTALL} is not true")
        assignment_present "${line}" "${GNOME_CONFIGURE}" false  || problems+=("${GNOME_CONFIGURE} is not false")
        grep -q "${KDE_INSTALL}" <<<"${line}" && problems+=("it also decides ${KDE_INSTALL}")

        if [[ ${#problems[@]} -eq 0 ]]; then
            pass "gnome with install installs the packages and leaves the configuration alone"
        else
            fail "gnome with install resolves to the wrong desktop variables" "$(printf '%s | ' "${problems[@]}")"
        fi
    fi
fi

# --- a profile ------------------------------------------------------------------
if [[ ! -f "${PROFILE_FILE}" ]]; then
    fail "the profile this check resolves is missing, so the profile case cannot run" "${PROFILE_FILE}"
else
    line="$(resolved_command profile)"
    if [[ "${line}" != ansible-playbook* ]]; then
        fail "--profile ${PROFILE_NAME} did not resolve to a command" "${line}"
    else
        problems=()
        grep -qE -- "-e @[^ ]*profiles/${PROFILE_NAME}\.yaml" <<<"${line}" \
            || problems+=("the resolved command carries no -e @ pointing at profiles/${PROFILE_NAME}.yaml")
        # A profile decides the software set on its own, so nothing else may also decide it. Two
        # answers to one question is exactly what --profile with --software is refused for.
        grep -q -- '--extra-vars' <<<"${line}" \
            && problems+=("it also passes --extra-vars, which would outrank the profile")

        if [[ ${#problems[@]} -eq 0 ]]; then
            pass "--profile ${PROFILE_NAME} resolves to the profile file and nothing that outranks it"
        else
            fail "--profile ${PROFILE_NAME} resolves to the wrong command" "$(printf '%s | ' "${problems[@]}")"
        fi
    fi
fi

# An assertion over an empty set passes and looks exactly like an assertion that found no problem,
# so the number of wizard runs that actually answered is asserted too.
answered="$(grep -lx 0 "${WORK_DIR}"/*.rc 2>/dev/null | grep -c . || true)"
if [[ "${answered}" -eq 6 ]]; then
    pass "all six selections were resolved through the shipped --print-command path"
else
    fail "not every selection reached the resolution, so part of this check proved nothing" \
         "${answered} of six runs exited 0"
fi

finish "print-command resolution"
