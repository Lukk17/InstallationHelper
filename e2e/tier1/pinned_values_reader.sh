#!/usr/bin/env bash
#
# Tier 1: the pinned values reader keeps its contract, driven through the interface its callers use.
#
# e2e/tier1/pinned_values.sh asks whether the repository still routes every pin through this reader.
# This check asks the different question of whether the reader itself is still correct, because every
# adapter is a shim over it and a wrong answer here is a wrong answer everywhere at once. It is what
# the two hand-written parsers this reader replaced never had: the Windows one silently left an
# unresolvable reference as literal text, and the sed chain in windows_mapping.sh could only
# dereference one hop.
#
# Every case runs against a fixture in pins_fixtures/ through INSTALLATION_HELPER_PINS_FILE, so
# nothing here depends on the values actually pinned today and a bump cannot make this check red.
#
# The distinction the whole suite leans on is absence against emptiness. An unpinned name is an
# error, exit 3, because a caller asking for something nobody pinned has a typo or a stale rename. A
# name pinned to an empty string is answered with the empty string, exit 0, because that is a value
# somebody wrote, and it is e2e/tier1/pinned_values.sh that refuses it in the real file. Collapse the
# two and an empty download location becomes indistinguishable from a missing one, which is how the
# dispatcher used to skip an install without a word.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "${REPO_ROOT}/setup/pinned_values/pinned_values.sh"

FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pins_fixtures"
CORE="${REPO_ROOT}/setup/pinned_values/pinned_values.py"

info "Tier 1: the pinned values reader's contract"

if [[ ! -f "${CORE}" ]]; then
    fail "the pinned values reader is missing" "${CORE}"
    finish "pinned values reader"
fi

if ! PYTHON="$(pinned_values_python)"; then
    skip "the pinned values reader's contract" \
         "no Python 3.11 or newer on PATH, so the reader cannot be driven at all"
    finish "pinned values reader"
fi
dim "interpreter: ${PYTHON}"

# read_fixture <fixture> <mode...>  runs the reader against one fixture, capturing both streams and
# the status, so a case can assert on the message as well as on the outcome.
read_fixture() {
    local fixture="$1"; shift
    OUT=""; ERR=""; STATUS=0
    local err_file
    err_file="$(mktemp)"
    OUT="$(INSTALLATION_HELPER_PINS_FILE="${FIXTURE_DIR}/${fixture}.toml" "${PYTHON}" "${CORE}" "$@" 2>"${err_file}")" || STATUS=$?
    ERR="$(cat "${err_file}")"
    rm -f "${err_file}"
}

# assert_refused <name> <fixture> <expected substring...>  a load that must fail, with a message
# that names what is wrong. A refusal with an unhelpful message is half a defect: the whole reason
# these errors are raised at load is that the reader knows the key and the caller does not.
assert_refused() {
    local name="$1" fixture="$2"; shift 2
    read_fixture "${fixture}" --json
    if [[ ${STATUS} -eq 0 ]]; then
        fail "${name}" "the reader accepted ${fixture} and printed ${#OUT} bytes"
        return 0
    fi
    local wanted missing=()
    for wanted in "$@"; do
        [[ "${ERR}" == *"${wanted}"* ]] || missing+=("${wanted}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        fail "${name}" "refused, but the message names none of: ${missing[*]}. It said: ${ERR}"
    else
        pass "${name}"
    fi
}

# --- resolution ----------------------------------------------------------------------------------
read_fixture chained --get alias
assert_eq "a three-hop reference chain resolves" \
    "https://example.invalid/v2.2.0/app_2.2.0_amd64.deb" "${OUT}"

read_fixture chained --get file
assert_eq "a reference inside a longer string resolves" "app_2.2.0_amd64.deb" "${OUT}"

read_fixture chained --json
if [[ "${OUT}" == *"{{"* ]]; then
    fail "no resolved value carries a template" "the JSON output still contains {{"
else
    pass "no resolved value carries a template"
fi

# --- absence is not emptiness --------------------------------------------------------------------
read_fixture chained --get blank
if [[ ${STATUS} -eq 0 && -z "${OUT}" ]]; then
    pass "a pin held empty answers empty, exit 0"
else
    fail "a pin held empty answers empty, exit 0" "status ${STATUS}, output [${OUT}], stderr ${ERR}"
fi

read_fixture chained --get nothing_pins_this
if [[ ${STATUS} -eq 3 && "${ERR}" == *"nothing_pins_this"* ]]; then
    pass "an unpinned name exits 3 and is named"
else
    fail "an unpinned name exits 3 and is named" "status ${STATUS}, stderr ${ERR}"
fi

# --- the checksum table ---------------------------------------------------------------------------
read_fixture chained --json
if [[ ${STATUS} -eq 0 && "${OUT}" != *"app_deb"* ]]; then
    pass "the checksum table is not mixed into the pins"
else
    fail "the checksum table is not mixed into the pins" "status ${STATUS}, output ${OUT}"
fi

read_fixture no_checksums --json
if [[ ${STATUS} -eq 0 ]]; then
    pass "a file with no checksum table still loads"
else
    fail "a file with no checksum table still loads" "status ${STATUS}, stderr ${ERR}"
fi

# --- everything the reader must refuse, at load, by name ------------------------------------------
assert_refused "a non-string value is refused by key and type" non_string "android_api_level" "not a string"
assert_refused "a reference naming nothing is refused by both names" unknown_reference "url" "nowhere"
assert_refused "a reference cycle is refused by the keys in it" cycle "cycle" "first" "second" "third"
assert_refused "a missing pins table is refused" no_pins_table "[pins]"
assert_refused "a file that is not TOML is refused by path" broken_syntax "broken_syntax.toml"
assert_refused "two names differing only in case are refused, naming both" case_collision "java21_id" "Java21_id" "case"
assert_refused "a name no adapter could carry is refused, naming it" hyphen_name "appimage-launcher-version"
assert_refused "an empty pins table is refused" empty_pins "empty"
assert_refused "a value containing a line break is refused" newline_value "multiline" "line break"

# --- a broken file must not answer with the absence code -----------------------------------------
# Exit 3 has exactly one meaning, that this name is not pinned, and a caller is entitled to branch on
# it. Before this was fixed, --get reported a missing file, invalid TOML, a cycle and a bad value all
# as 3, so a corrupt file read as "nobody pinned that" and a caller carried on with a default.
read_fixture broken_syntax --get anything
if [[ ${STATUS} -eq 1 ]]; then
    pass "a broken file read through --get exits 1, not the absence code"
else
    fail "a broken file read through --get exits 1, not the absence code" \
         "status ${STATUS}, stderr ${ERR}"
fi

read_fixture cycle --get first
if [[ ${STATUS} -eq 1 ]]; then
    pass "a cycle read through --get exits 1, not the absence code"
else
    fail "a cycle read through --get exits 1, not the absence code" "status ${STATUS}, stderr ${ERR}"
fi

# --- the port's single-value operation, which the command line no longer goes through --------------
# --get reads the whole set now, so pin() would otherwise be code with no test behind it.
pin_out="$(INSTALLATION_HELPER_PINS_FILE="${FIXTURE_DIR}/chained.toml" "${PYTHON}" -c '
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]).parent))
import pinned_values as reader
print(reader.pin("alias"))
try:
    reader.pin("nothing_pins_this")
    print("ABSENCE DID NOT RAISE")
except reader.PinnedValuesError as exc:
    print("raised:", exc)
' "${CORE}" 2>&1)"
if [[ "${pin_out}" == *"https://example.invalid/v2.2.0/app_2.2.0_amd64.deb"* && "${pin_out}" == *"raised: nothing pinned"* ]]; then
    pass "pin() answers a resolved value and raises by name for an unpinned one"
else
    fail "pin() answers a resolved value and raises by name for an unpinned one" "${pin_out}"
fi

# --- the shell adapter, which is what the other checks call ---------------------------------------
# Its own subshell, because the adapter caches into PIN_* variables on first use and the fixture is
# not the real file. Without the subshell this check would poison every later caller in this process.
#
# The status is collected with || rather than by reading $? on the next line, because common.sh runs
# under set -e and a bare subshell that returns non-zero ends this script before the case below can
# report anything. That was not hypothetical: the first run of the proof for the quoting case killed
# the check silently instead of failing it, which is the exact class of defect this suite exists for.
adapter_status=0
(
    export INSTALLATION_HELPER_PINS_FILE="${FIXTURE_DIR}/chained.toml"
    unset PINNED_VALUES_LOADED
    adapter_out="$(pinned_value alias)"
    [[ "${adapter_out}" == "https://example.invalid/v2.2.0/app_2.2.0_amd64.deb" ]] || exit 1

    # A single quote inside a value is the one character that can break the eval the adapter uses to
    # load the whole set in one call.
    [[ "$(pinned_value quoted)" == "it's quoted" ]] || exit 2

    set +e
    pinned_value nothing_pins_this >/dev/null 2>&1
    absent_status=$?
    # A name that is not a pin name at all, which without validation would be spliced into an
    # indirect expansion: PIN_MINIKUBE_URL[0] reads element zero of a scalar, which bash answers with
    # the scalar, so the call would return a value at status 0 for something that is not a pin.
    pinned_value 'alias[0]' >/dev/null 2>&1
    subscript_status=$?
    set -e
    [[ ${absent_status} -eq 0 ]] && exit 3
    [[ ${absent_status} -eq 3 ]] || exit 4
    [[ ${subscript_status} -eq 0 ]] && exit 5
    exit 0
) || adapter_status=$?
case ${adapter_status} in
    0) pass "the shell adapter resolves, survives a quote, and returns 3 for an unpinned name" ;;
    1) fail "the shell adapter resolves, survives a quote, and returns 3 for an unpinned name" \
            "a chained value came back wrong" ;;
    2) fail "the shell adapter resolves, survives a quote, and returns 3 for an unpinned name" \
            "a value containing a single quote did not survive the eval in pinned_values_load" ;;
    3) fail "the shell adapter resolves, survives a quote, and returns 3 for an unpinned name" \
            "pinned_value answered an unpinned name instead of failing" ;;
    5) fail "the shell adapter resolves, survives a quote, and returns 3 for an unpinned name" \
            "pinned_value answered a subscripted name as though it were a pin" ;;
    *) fail "the shell adapter resolves, survives a quote, and returns 3 for an unpinned name" \
            "pinned_value returned ${adapter_status} for an unpinned name, expected 3" ;;
esac

finish "pinned values reader"
