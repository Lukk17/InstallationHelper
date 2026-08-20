# shellcheck shell=bash
# -----------------------------------------------------------------------------
# The shell end of the pinned values port. Source it, do not execute it.
#
#   source setup/pinned_values/pinned_values.sh
#   pinned_value minikube_url
#
# pinned_values_load  loads every pin once into PIN_<NAME> variables.
# pinned_value <name> prints one value, returning 3 when nothing pins that name.
#
# Absence and emptiness stay different answers: a name pinned to an empty string prints nothing and
# returns 0, and only an unpinned name returns 3. Two tier 1 checks depend on that distinction to
# catch a download location that renders to nothing.
#
# Returns 2 when no Python 3.11 or newer can be found, naming what to install rather than behaving
# as though nothing is pinned. Set PINNED_VALUES_PYTHON to choose the interpreter yourself.
# -----------------------------------------------------------------------------

PINNED_VALUES_CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pinned_values.py"
readonly PINNED_VALUES_CORE

pinned_values_python() {
    if [[ -n ${PINNED_VALUES_PYTHON:-} ]]; then
        printf '%s\n' "${PINNED_VALUES_PYTHON}"
        return 0
    fi

    local candidate
    for candidate in python3 python py; do
        command -v "${candidate}" >/dev/null 2>&1 || continue
        # tomllib is what the reader needs, and it entered the standard library in 3.11. This also
        # rejects the Windows App Execution Alias stub, which resolves and then does nothing useful.
        if "${candidate}" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
            PINNED_VALUES_PYTHON="${candidate}"
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    printf 'pinned values: no Python 3.11 or newer on PATH (tried python3, python, py), so %s cannot be read\n' \
        "${PINNED_VALUES_CORE}" >&2
    return 2
}

pinned_values_load() {
    [[ ${PINNED_VALUES_LOADED:-0} == 1 ]] && return 0

    local interpreter
    interpreter="$(pinned_values_python)" || return 2

    local rendered status
    rendered="$("${interpreter}" "${PINNED_VALUES_CORE}" --sh)"
    status=$?
    if [[ ${status} -ne 0 ]]; then
        printf 'pinned values: %s --sh failed with status %d\n' "${PINNED_VALUES_CORE}" "${status}" >&2
        return "${status}"
    fi

    eval "${rendered}"
    PINNED_VALUES_LOADED=1
    return 0
}

pinned_value() {
    local name="${1:?a pin name is required}"
    pinned_values_load || return $?

    local variable="PIN_${name^^}"
    if [[ -z ${!variable+set} ]]; then
        printf 'pinned values: nothing pins %s in %s\n' "${name}" "${PINNED_VALUES_CORE}" >&2
        return 3
    fi
    printf '%s\n' "${!variable}"
}
