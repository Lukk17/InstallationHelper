# shellcheck shell=bash
# -----------------------------------------------------------------------------
# The shell end of the pinned values port. Source it, do not execute it.
#
#   source setup/pinned_values/pinned_values.sh
#   pinned_value minikube_url
#
# pinned_values_load   loads every pin once into PIN_<NAME> variables.
# pinned_values_names  prints the names that were loaded, one per line.
# pinned_value <name>  prints one value, returning 3 when nothing pins that name.
#
# Absence and emptiness stay different answers: a name pinned to an empty string prints nothing and
# returns 0, and only an unpinned name returns 3. Two tier 1 checks depend on that distinction to
# catch a download location that renders to nothing.
#
# Return codes, which callers are expected to read. Both functions are meant to be called somewhere
# that looks at their status, because a caller running under `set -e` that ignores it will be killed
# by the failure rather than shown the message.
#
#   0  answered
#   2  no Python 3.11 or newer could be found, or the name asked for is not a pin name
#   3  nothing pins that name
#   *  whatever the reader exited with, when the file itself is unreadable or invalid
#
# Set PINNED_VALUES_PYTHON to choose the interpreter yourself.
#
# Requires bash 4 or newer for the associative-free PIN_<NAME> indirection used below. Uppercasing is
# done with tr rather than ${name^^} on purpose, because stock macOS still ships bash 3.2 and the
# two manual install scripts under docs/manual source this file.
# -----------------------------------------------------------------------------

# Guarded rather than readonly: a script that sources this file twice, directly and through a
# library, would otherwise die on the reassignment under `set -u` with nothing useful said.
if [[ -z ${PINNED_VALUES_CORE:-} ]]; then
    PINNED_VALUES_CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pinned_values.py"
fi

# The reader's exit code for a name nobody pinned. Named here as well as in PinnedValues.psm1 so the
# third runtime cannot drift from the other two.
PINNED_VALUES_ABSENT=3
PINNED_VALUES_UNUSABLE=2

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
    return "${PINNED_VALUES_UNUSABLE}"
}

pinned_values_load() {
    [[ ${PINNED_VALUES_LOADED:-0} == 1 ]] && return 0

    local interpreter
    interpreter="$(pinned_values_python)" || return "${PINNED_VALUES_UNUSABLE}"

    local rendered status
    rendered="$("${interpreter}" "${PINNED_VALUES_CORE}" --sh)"
    status=$?
    if [[ ${status} -ne 0 ]]; then
        printf 'pinned values: %s --sh failed with status %d\n' "${PINNED_VALUES_CORE}" "${status}" >&2
        return "${status}"
    fi

    # The status of the eval is read rather than discarded. The reader refuses a name that is not a
    # shell-safe identifier, so a line that eval cannot treat as an assignment should be impossible,
    # and declaring the set loaded anyway would turn that impossible case into every pin reporting
    # itself absent, which is the false-absence answer this whole design exists to prevent.
    if ! eval "${rendered}"; then
        printf 'pinned values: the assignments rendered by %s did not load\n' "${PINNED_VALUES_CORE}" >&2
        return 1
    fi

    # Recorded from the reader's own output rather than discovered with `compgen -v PIN_`, which
    # would also collect any PIN_-prefixed variable that happened to be in the environment already.
    PINNED_VALUE_NAMES="$(printf '%s\n' "${rendered}" \
        | sed -n 's/^PIN_\([A-Za-z0-9_]*\)=.*/\1/p' \
        | tr '[:upper:]' '[:lower:]')"

    PINNED_VALUES_LOADED=1
    return 0
}

pinned_values_names() {
    pinned_values_load || return $?
    printf '%s\n' "${PINNED_VALUE_NAMES}"
}

pinned_value() {
    local name="${1:?a pin name is required}"

    # Validated before it is spliced into an indirect expansion. Without this, a name carrying a
    # bracket such as `minikube_url[0]` reads element zero of a scalar, which bash answers with the
    # scalar itself, so the call would return a value at status 0 for a name that is not a pin.
    if [[ ! ${name} =~ ^[A-Za-z0-9_]+$ ]]; then
        printf 'pinned values: %s is not a pin name\n' "${name}" >&2
        return "${PINNED_VALUES_UNUSABLE}"
    fi

    pinned_values_load || return $?

    local variable
    variable="PIN_$(printf '%s' "${name}" | tr '[:lower:]' '[:upper:]')"
    if [[ -z ${!variable+set} ]]; then
        printf 'pinned values: nothing pins %s in %s\n' "${name}" "${PINNED_VALUES_CORE}" >&2
        return "${PINNED_VALUES_ABSENT}"
    fi
    printf '%s\n' "${!variable}"
}
