#!/usr/bin/env bash
#
# Tier 1: the pinned values stay behind one reader, and every pin still has a reader.
#
# The versions, download locations and vendor identifiers live in setup/pinned_values, behind one
# reader with one adapter per runtime. Before that they were a YAML file that three separate
# hand-written parsers read: a regular expression and a five-pass resolver in the Windows installer,
# a two-step sed dereference in e2e/tier1/windows_mapping.sh, and a grep for a non-empty value in
# e2e/tier1/toggle_coverage.sh. Three readers of one file drift, and they did: the Windows one left
# an unresolvable reference standing as literal text, and the sed one could follow exactly one hop.
#
# This check is what stops a fourth appearing, and what stops a pin rotting into place unread. The
# sibling check e2e/tier1/pinned_values_reader.sh asks the different question of whether the reader
# itself is correct, driven against fixtures. Nothing here depends on which version is pinned today,
# so bumping a pin cannot make this red.
#
# Six assertions, one per way the design can be bypassed. See docs/pinned_values_adapter_design.md
# section 6.
#
#   1. Nobody parses the pins file but the reader.
#   2. Every pin has at least one reader.
#   3. Every reader names a pin that exists.
#   4. The resolved set is total: every value a string, no braces, nothing empty.
#   5. No pin name is defined as a variable anywhere else, which is what makes the precedence
#      change safe. The pins used to arrive as a play vars_files entry, rank 14 of 22, and now
#      arrive from a vars plugin, ranks 4 to 10, so a same-named variable elsewhere would now win
#      where it previously lost.
#   6. The PowerShell adapter and the reader agree key by key.
#
# Two things about how this is written are deliberate.
#
# This file is inside its own scan. The needles are therefore spelled so that they do not match the
# text that defines them, using the same bracket trick as the familiar grep for a process by name:
# a dot written as a one-character class finds the real filename without being the real filename. A
# guard exempted from itself is a guard nobody checks, and one assertion below proves this file
# really is in the scanned list.
#
# Every needle is proven live against the reader itself, which is the one file the scan excludes and
# which genuinely names the data file, imports a TOML library and carries a reference-capturing
# regular expression. A needle that has rotted into matching nothing would pass the whole scan
# silently, which is the vacuous-pass trap this suite has been caught by twice.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# The set is read through the shell adapter rather than parsed, because parsing it here is the very
# thing assertion 1 forbids everywhere else.
source "${REPO_ROOT}/setup/pinned_values/pinned_values.sh"
# Finding a runnable pwsh and converting a path for it are shared with windows_mapping.sh and
# windows_settings.sh. See pwsh_probe.sh.
source "$(dirname "${BASH_SOURCE[0]}")/pwsh_probe.sh"

CORE="${REPO_ROOT}/setup/pinned_values/pinned_values.py"
PS_MODULE="${REPO_ROOT}/setup/pinned_values/PinnedValues.psm1"
ALLOWED_FILE="$(dirname "${BASH_SOURCE[0]}")/unread_pins_allowed.txt"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

info "Tier 1: pinned values behind one reader"

[[ -f "${CORE}" ]] || { fail "the pinned values reader is missing" "${CORE}"; finish "pinned values"; }

is_pin() { [[ -n "${pin_set["$1"]-}" ]]; }

# pin_value <name>  one resolved value, out of the already-loaded set.
pin_value() {
    local holder="PIN_${1^^}"
    printf '%s' "${!holder-}"
}

# in_list <needle> <item...>  membership in a handful of items.
in_list() {
    local needle="$1"; shift
    local item
    for item in "$@"; do [[ "${item}" == "${needle}" ]] && return 0; done
    return 1
}

# fill_set <associative array name> <item...>  the same question for the word lists, which run to
# thousands of entries and are asked about once per pin. Walking them as flat arrays is the whole
# difference between this check taking half a minute and taking a couple of seconds.
fill_set() {
    local -n target="$1"; shift
    local item
    for item in "$@"; do [[ -n "${item}" ]] && target["${item}"]=1; done
}

declare -A pin_set=() ansible_used_set=() script_word_set=() runtime_set=() defined_set=()

# --- the set, read through the adapter ---------------------------------------------------------
# Loading at all is the first half of assertion 4: the reader refuses a value that is not a string,
# a reference naming nothing and a reference cycle, all at load, so a set that arrives here has
# already passed those three rules and the failure below names which one it was.
#
# Loaded in this shell rather than in a command substitution, because the adapter answers by setting
# PIN_<NAME> variables and a subshell would take every one of them with it when it exited. Its
# complaint goes to a file for the same reason.
load_log="$(mktemp)"
if ! pinned_values_load 2>"${load_log}"; then
    fail "the pinned value set does not load through the adapter, so nothing else here can mean anything" \
         "$(tr '\n' ' ' <"${load_log}")"
    rm -f "${load_log}"
    finish "pinned values"
fi
rm -f "${load_log}"

# Names come back from the adapter as PIN_<NAME>, so they are read out of the environment rather
# than out of the file. The pins table is lowercase throughout, which assertion 3's family rule and
# assertion 5's definition scan both rely on, and which assertion 4 asserts rather than assumes.
mapfile -t pin_names < <(compgen -v 'PIN_' | sed 's/^PIN_//' | tr '[:upper:]' '[:lower:]' | LC_ALL=C sort)
fill_set pin_set "${pin_names[@]-}"

# A scan that finds almost nothing passes every assertion below it, so the floor is checked first.
# There are 67 pins today, so a count in single figures means the adapter or this enumeration broke.
if [[ ${#pin_names[@]} -lt 40 ]]; then
    fail "only ${#pin_names[@]} pinned values came back through the adapter, so this check cannot mean anything" \
         "expected dozens from ${CORE}"
    finish "pinned values"
fi
pass "the adapter resolved ${#pin_names[@]} pinned values, which is where a non-string value, a dangling reference and a cycle are refused"

# --- 1. nobody parses the pins file but the reader ---------------------------------------------
# Three needles, each aimed at one shape of second parser.
#
#   The data file, named in a position that could read it: quoted, or on a line that also carries a
#   read verb. Prose saying where the pins live matches neither, and the dispatcher's failure
#   message, the verify play's failure message and the vars plugin's documentation block all say
#   exactly that on purpose. Prose cannot read a file.
#
#   A TOML library, anywhere at all, because outside the reader there is no second legitimate
#   reason to have one.
#
#   A reference-capturing regular expression, which is a second resolver even when it never opens
#   the file: the Windows parser resolved references in values it already held. A pattern that only
#   tests whether braces are present is a guard rather than a resolver, and is not flagged, which
#   is why the needle requires a capture between the braces.
NEEDLE_DATA_FILE='pinned_values[.]toml'
NEEDLE_READ_VERB='grep|sed|awk|cut|cat|head|tail|jq|Get-Content|Select-String|ConvertFrom|Import-|open\(|read_text|readlines|load\(|loads\(|slurp|lookup\(|include_vars|Join-Path'
NEEDLE_TOML_LIB='\btoml(lib|i)\b|import[[:space:]]+toml|from[[:space:]]+toml|ConvertFrom-T[o]ml|T[o]mlyn'
NEEDLE_REF_REGEX='\\\{[[:space:]]*\\\{.*\(.*[A-Za-z].*\\\}'

# The quoted half of the data-file needle allows no whitespace between the quote and the name,
# because a quote anywhere earlier on the line would otherwise reach it: the dispatcher's failure
# message quotes a separator for a join filter and then says in prose where the URLs come from,
# which matched until the space was forbidden.
NEEDLE_DATA_FILE_READ="('[^'[:space:]]*|\"[^\"[:space:]]*)${NEEDLE_DATA_FILE}"
NEEDLE_DATA_FILE_READ+="|${NEEDLE_DATA_FILE}.*(${NEEDLE_READ_VERB})"
NEEDLE_DATA_FILE_READ+="|(${NEEDLE_READ_VERB}).*${NEEDLE_DATA_FILE}"

# Comments go the same way common.sh strips them for the toggle scan: a full-line comment, and a
# trailing one that follows whitespace. A bare hash inside a URL is not preceded by whitespace, and
# the only cost of getting that wrong here would be a missed line, never a false failure.
strip_comments() {
    sed -E 's/^[[:space:]]*#.*$//; s/[[:space:]]#.*$//' "$1"
}

# The text is captured before it is searched rather than piped straight into grep. Under pipefail,
# grep -q closes the pipe on its first match, sed dies of SIGPIPE, and the pipeline reports 141 for
# what was a hit. Git Bash got away with it because the file fits in one pipe buffer and sed had
# already exited; WSL did not, and reported all three needles below as dead against a reader that
# carries all three.
matches_in() {
    local file="$1" needle="$2" text
    text="$(strip_comments "${file}")"
    grep -qE "${needle}" <<<"${text}"
}

names_data_file()   { matches_in "$1" "${NEEDLE_DATA_FILE_READ}"; }
imports_toml()      { matches_in "$1" "${NEEDLE_TOML_LIB}"; }
carries_ref_regex() { matches_in "$1" "${NEEDLE_REF_REGEX}"; }

# Every needle against the reader, which is the one file the scan excludes and the one file that
# legitimately does all three. A needle that stops matching here has rotted.
needles_live=()
names_data_file "${CORE}"   || needles_live+=("the data-file needle no longer matches the reader's own path")
imports_toml "${CORE}"      || needles_live+=("the TOML-library needle no longer matches the reader's own import")
carries_ref_regex "${CORE}" || needles_live+=("the reference-regex needle no longer matches the reader's own resolver")

if [[ ${#needles_live[@]} -eq 0 ]]; then
    pass "all three second-parser needles still match the reader, so the scan below can mean something"
else
    fail "${#needles_live[@]} of the second-parser needles match nothing any more, so the scan below proves nothing" \
         "$(printf '%s; ' "${needles_live[@]}")"
fi

mapfile -t scanned < <(find "${REPO_ROOT}/setup" "${REPO_ROOT}/e2e" "${REPO_ROOT}/docs/manual" -type f \
    \( -name '*.sh' -o -name '*.bash' -o -name '*.ps1' -o -name '*.psm1' -o -name '*.psd1' \
       -o -name '*.py' -o -name '*.yaml' -o -name '*.yml' -o -name '*.j2' -o -name '*.cfg' \) \
    ! -path '*/e2e/runs/*' ! -path '*/__pycache__/*' 2>/dev/null | LC_ALL=C sort)

if [[ ${#scanned[@]} -lt 50 ]]; then
    fail "the second-parser scan found only ${#scanned[@]} files, so it cannot mean anything" \
         "expected well over a hundred under setup/, e2e/ and docs/manual/"
elif ! in_list "${SELF}" "${scanned[@]}"; then
    fail "this check is not inside its own scan, so nothing would notice a parser written here" \
         "expected ${SELF} among the ${#scanned[@]} scanned files"
else
    pass "${#scanned[@]} files scanned for a second parser, this one among them"
fi

# Every scanned file, comment-stripped once, as <path> TAB <line>. One pass rather than a grep per
# file per needle: this shell spawns a process slowly enough that the per-file version took a minute
# and a half, which is not a pre-commit gate.
STRIPPED="$(mktemp)"
trap 'rm -f "${STRIPPED}"' EXIT
printf '%s\0' "${scanned[@]}" | xargs -0 awk '
    { line = $0
      sub(/^[[:space:]]*#.*$/, "", line)
      sub(/[[:space:]]#.*$/, "", line)
      print FILENAME "\t" line }' > "${STRIPPED}"

# hits <needle> <what it means>  every scanned file, bar the reader, whose stripped text matches.
#
# The needle is required to match after the tab, so a path that happens to contain one of the read
# verbs cannot turn a file's prose mention into a hit. There is exactly one tab per line and the
# path holds none, so a tab followed by the needle can only be a match in the text.
TAB="$(printf '\t')"
hits() {
    grep -E "${TAB}.*(${1})" "${STRIPPED}" 2>/dev/null \
        | cut -f1 | LC_ALL=C sort -u | grep -vxF "${CORE}" \
        | sed "s|^${REPO_ROOT}/||; s|\$| ${2}|" || true
}

mapfile -t second_parsers < <(
    hits "${NEEDLE_DATA_FILE_READ}" "names the data file where it could read it"
    hits "${NEEDLE_TOML_LIB}" "imports a TOML library"
    hits "${NEEDLE_REF_REGEX}" "carries a reference-capturing regular expression"
)

if [[ ${#second_parsers[@]} -eq 0 ]]; then
    pass "nothing but the reader reads the pins file or resolves a reference"
else
    fail "${#second_parsers[@]} second parser(s) of the pinned values, which is how the three the reader replaced started" \
         "$(printf '%s; ' "${second_parsers[@]}")"
fi

# --- the reader set, built once and used by assertions 2 and 3 ---------------------------------
# A file that points the reader at a fixture is talking to made-up pins, so the names in it are
# neither readers nor callsites. Deriving that from the environment variable rather than naming the
# file keeps it true when the next fixture-driven check appears.
FIXTURE_DRIVERS="$(mktemp)"
trap 'rm -f "${STRIPPED}" "${FIXTURE_DRIVERS}"' EXIT
grep -rlF 'INSTALLATION_HELPER_PINS_FILE' \
    "${REPO_ROOT}/setup" "${REPO_ROOT}/e2e" "${REPO_ROOT}/docs/manual" 2>/dev/null \
    | LC_ALL=C sort > "${FIXTURE_DRIVERS}" || true

# text_of <extension pattern> [path fragment to leave out]  the stripped text of the scanned files
# with one of these extensions, fixture drivers always left out.
text_of() {
    local pattern="$1" excluded="${2:-}"
    # The driver list is recognised by its own filename rather than by being the first input, because
    # the NR == FNR idiom silently inverts when the first file turns out to be empty.
    awk -F'\t' -v drivers="${FIXTURE_DRIVERS}" -v pattern="${pattern}" -v excluded="${excluded}" '
        FILENAME == drivers { driver[$0] = 1; next }
        $1 in driver { next }
        excluded != "" && index($1, excluded) { next }
        $1 ~ pattern { print $2 }' "${FIXTURE_DRIVERS}" "${STRIPPED}"
}

# Reader source one: a name used, rather than defined, anywhere under setup/ansible/. Comments are
# stripped because a comment reads nothing, and the key of a definition line is dropped because
# defining a name is not reading it. Everything after the colon is kept, so a line of the shape
# alias: "{{ other }}" still counts as a read of other.
mapfile -t ansible_used < <(find "${ANSIBLE_DIR}" -type f \
        \( -name '*.yaml' -o -name '*.yml' -o -name '*.j2' -o -name '*.cfg' \) -print0 2>/dev/null \
    | xargs -0 awk '
        { line = $0
          sub(/^[[:space:]]*#.*$/, "", line)
          sub(/[[:space:]]#.*$/, "", line)
          sub(/^[[:space:]]*-?[[:space:]]*[a-z][a-z0-9_]*[[:space:]]*:/, "", line)
          print line }' \
    | grep -oE '\b[a-z][a-z0-9_]+\b' | LC_ALL=C sort -u)
fill_set ansible_used_set "${ansible_used[@]-}"

# Reader source two: the names the dispatcher builds at run time. An apt_url mapping resolves
# <key>_url, and a dnf_url mapping tries <key>_rpm_url and then falls back to <key>_url. The keys
# come from the OS dictionaries, so a plain grep of the roles reports these nine as unread when they
# are the whole reason two dispatch tasks work.
#
# One mapping per line, as <key> <manager> <inline|derived>, because the same key can be an apt_url
# mapping in one dictionary and a dnf_url mapping in another and the two want different names. An
# earlier version collapsed them into two key lists and asked one question of the union, which let
# the surviving rpm pin excuse a missing Debian one: renaming teamviewer_url went unreported.
mapfile -t url_mappings < <(grep -hoE '^  [a-z0-9_]+: \{[[:space:]]*manager:[[:space:]]*"(apt_url|dnf_url)"[^}]*' \
    "${ANSIBLE_DIR}"/vars/*.yaml 2>/dev/null \
    | sed -E 's/^  ([a-z0-9_]+): \{[[:space:]]*manager:[[:space:]]*"([a-z_]+)"(.*)$/\1 \2 \3/' \
    | awk '{ inline = ($0 ~ /[[:space:],]url:/) ? "inline" : "derived"; print $1, $2, inline }' \
    | LC_ALL=C sort -u)

url_keys_apt=()
url_keys_dnf=()
runtime_built=()
for mapping in "${url_mappings[@]-}"; do
    read -r key manager _ <<<"${mapping}"
    [[ -z "${key}" ]] && continue
    if [[ "${manager}" == apt_url ]]; then
        url_keys_apt+=("${key}")
        runtime_built+=("${key}_url")
    else
        url_keys_dnf+=("${key}")
        runtime_built+=("${key}_rpm_url" "${key}_url")
    fi
done
fill_set runtime_set "${runtime_built[@]-}"

if [[ ${#runtime_built[@]} -lt 4 ]]; then
    fail "found only ${#runtime_built[@]} runtime-built download names in the OS dictionaries, so the reader set is incomplete" \
         "expected apt_url and dnf_url mapping shapes in ${ANSIBLE_DIR}/vars/*.yaml"
else
    pass "${#url_keys_apt[@]} apt_url and ${#url_keys_dnf[@]} dnf_url mapping keys contribute ${#runtime_built[@]} runtime-built names"
fi

# Reader source three: a name a PowerShell or shell script asks for. Whole words, comments stripped.
SCRIPT_EXTENSIONS='[.](sh|bash|ps1|psm1|psd1)$'
mapfile -t script_words < <(text_of "${SCRIPT_EXTENSIONS}" \
    | grep -oE '\b[a-z][a-z0-9_]+\b' | LC_ALL=C sort -u)
fill_set script_word_set "${script_words[@]-}"

# Reader source four: one pin feeding another. Those references are spelled inside the file, and
# this check is not allowed to read the file, so the edge is established from the resolved set
# instead: a pin whose value appears inside another pin's value was substituted into it. Containment
# is a weaker test than the reference itself, so it is floored at four characters, below which a
# value is too short for containment to prove anything and the pin needs a real reader or an
# allowlist entry. Sixteen pins are feeders only, and every one clears the floor by a wide margin.
CONTAINMENT_FLOOR=4
feeds_another_pin() {
    local name="$1" value other holder
    holder="PIN_${name^^}"
    value="${!holder-}"
    [[ ${#value} -ge ${CONTAINMENT_FLOOR} ]] || return 1
    # Indirect expansion rather than a call to pin_value, because this is the one loop that runs
    # sixty-seven squared times and a command substitution each way costs a subshell.
    for other in "${pin_names[@]}"; do
        [[ "${other}" == "${name}" ]] && continue
        holder="PIN_${other^^}"
        [[ "${!holder-}" == *"${value}"* ]] && return 0
    done
    return 1
}

has_reader() {
    local name="$1"
    [[ -n "${ansible_used_set["${name}"]-}" ]] && return 0
    [[ -n "${runtime_set["${name}"]-}" ]] && return 0
    [[ -n "${script_word_set["${name}"]-}" ]] && return 0
    feeds_another_pin "${name}" && return 0
    return 1
}

# --- 2. every pin has at least one reader -------------------------------------------------------
allowed_names=()
while read -r name _; do
    [[ -z "${name}" || "${name}" == \#* ]] && continue
    allowed_names+=("${name}")
done < <(grep -vE '^\s*(#|$)' "${ALLOWED_FILE}" 2>/dev/null || true)

unread=()
for name in "${pin_names[@]}"; do
    has_reader "${name}" && continue
    in_list "${name}" "${allowed_names[@]-}" && continue
    unread+=("${name}")
done

if [[ ${#unread[@]} -eq 0 ]]; then
    pass "every one of the ${#pin_names[@]} pins has a reader, or an allowlist entry with a reason"
else
    fail "${#unread[@]} pin(s) nobody reads, which still look authoritative and still get bumped by hand" \
         "${unread[*]}"
fi

# An exemption that is no longer needed forgives a future break, so it goes when it stops being
# true. Same rule and the same two failure shapes as documented_no_ops.txt has.
stale=()
for name in "${allowed_names[@]-}"; do
    [[ -z "${name}" ]] && continue
    if ! is_pin "${name}"; then
        stale+=("${name} (nothing pins it any more)")
    elif has_reader "${name}"; then
        stale+=("${name} (now has a reader)")
    fi
done

if [[ ${#stale[@]} -eq 0 ]]; then
    pass "unread_pins_allowed.txt has no stale entries"
else
    fail "unread_pins_allowed.txt forgives pins that now have a reader, or that no longer exist" "${stale[*]}"
fi

# --- 3. every reader names a pin that exists -----------------------------------------------------
# Bounded deliberately. Not every Ansible variable reference is a pin reference, and treating them
# all as one would drown this in role variables, registered results and facts. Three sets, each
# built by the rules assertion 2 uses, and nothing else considered:
#
#   a. The runtime-built download names. Fully mechanical, so these are checked exactly: an apt_url
#      mapping needs <key>_url, a dnf_url mapping needs one of <key>_rpm_url or <key>_url, and
#      either is excused by an inline url: field in the mapping, which is what the dispatcher
#      prefers when it is there.
#
#   b. The names asked of an adapter by name, meaning pinned_value <name> and PIN_<NAME> in shell.
#      The adapter makes the callsite unambiguous, so these are checked exactly too. A lookup built
#      out of a variable cannot be resolved from the text and is skipped, which is why
#      toggle_coverage.sh's lookup of a key and a suffix contributes nothing here.
#
#   c. Bare references, in Ansible expressions and in PowerShell string literals, narrowed to a pin
#      family. A family is a pin name with its last underscore-separated token removed, so
#      minikube_url, minikube_file and minikube_version all put minikube in the family set. A
#      reference is a candidate when it starts with a family prefix, is not itself a pin, and is not
#      defined anywhere in the repository as a variable. That is what a typo in a suffix and a pin
#      renamed within its family both look like, and it was measured to produce no noise, where the
#      unbounded version reported ten harmless names. A whole family renamed at once is not caught
#      here and does not need to be: the new pin then has no reader and assertion 2 fails.
#
# The fourth possible direction, a reference from one pin to another naming nothing, is refused by
# the reader at load and proven by pinned_values_reader.sh, so it is not duplicated here.
missing_pins=()

for mapping in "${url_mappings[@]-}"; do
    read -r key manager inline <<<"${mapping}"
    [[ -z "${key}" ]] && continue
    # A mapping carrying its own url: field needs no pin at all, and that is what the dispatcher
    # prefers when it is there.
    [[ "${inline}" == inline ]] && continue
    if [[ "${manager}" == dnf_url ]]; then
        is_pin "${key}_rpm_url" && continue
        is_pin "${key}_url" && continue
        missing_pins+=("the ${manager} dispatch will look up ${key}_rpm_url and then ${key}_url for the ${key} mapping, and nothing pins either")
    else
        is_pin "${key}_url" && continue
        missing_pins+=("the ${manager} dispatch will look up ${key}_url for the ${key} mapping and nothing pins it")
    fi
done

# The port's own directory is left out here. It declares these two functions rather than calling
# them, and its usage message for a missing argument reads exactly like a callsite.
mapfile -t adapter_calls < <(text_of '[.](sh|bash)$' 'setup/pinned_values/' \
    | grep -oE 'pinned_value[[:space:]]+[a-z][a-z0-9_]+|PIN_[A-Z][A-Z0-9_]+' \
    | sed -E 's/^pinned_value[[:space:]]+//; s/^PIN_//' \
    | tr '[:upper:]' '[:lower:]' | LC_ALL=C sort -u)

for name in "${adapter_calls[@]-}"; do
    [[ -z "${name}" ]] && continue
    is_pin "${name}" && continue
    missing_pins+=("something asks the adapter for ${name} and nothing pins it")
done

# Every name the repository defines as a variable: a YAML mapping key at any indent, which is also
# the shape of a set_fact key and of an inline vars dict, plus registered results. Used here to keep
# a role's own variable out of the candidate set, and again by assertion 5.
mapfile -t YAML_FILES < <(find "${REPO_ROOT}" -type f \( -name '*.yaml' -o -name '*.yml' \) \
    ! -path '*/.git/*' ! -path '*/e2e/runs/*' ! -path '*/setup/pinned_values/*' 2>/dev/null | LC_ALL=C sort)

# Two passes rather than one alternation. Sharing one made every registered name vanish: the
# mapping-key branch matched `register:` itself first, grep resumed after it, and the name that
# followed was never offered to the other branch. Six registered results were reported as pins that
# do not exist before that was noticed.
mapfile -t defined_names < <( {
    printf '%s\0' "${YAML_FILES[@]}" \
        | { xargs -0 grep -hoE '(^|[[:space:],{])[a-z][a-z0-9_]+[[:space:]]*:' 2>/dev/null || true; } \
        | sed -E 's/^[[:space:],{]+//; s/[[:space:]]*:$//'
    printf '%s\0' "${YAML_FILES[@]}" \
        | { xargs -0 grep -hoE '(register|loop_var|index_var):[[:space:]]*[a-z][a-z0-9_]+' 2>/dev/null || true; } \
        | sed -E 's/^[a-z_]+:[[:space:]]*//'
    } | LC_ALL=C sort -u)
fill_set defined_set "${defined_names[@]-}"

families=()
for name in "${pin_names[@]}"; do
    [[ "${name}" == *_* ]] && families+=("${name%_*}")
done
mapfile -t families < <(printf '%s\n' "${families[@]}" | LC_ALL=C sort -u)

# Ansible expression bodies, with quoted literals and attribute accesses removed. A quoted string is
# data, which is how a checksum table key and a manager name reach an expression, and a name after a
# dot is an attribute of something else rather than a variable of its own.
mapfile -t bare_refs < <(find "${ANSIBLE_DIR}" -type f \
        \( -name '*.yaml' -o -name '*.yml' -o -name '*.j2' \) -print0 2>/dev/null \
    | { xargs -0 grep -hoE '\{\{[^}]*\}\}' 2>/dev/null || true; } \
    | sed -E "s/'[^']*'/ /g" \
    | sed -E 's/"[^"]*"/ /g' \
    | sed -E 's/\.[a-z_][a-z0-9_]*//g' \
    | grep -oE '\b[a-z][a-z0-9_]+\b' | LC_ALL=C sort -u)

# PowerShell reaches a pin by quoted name, which is the shape the pass above deliberately discards
# as data, so those literals are collected separately and only the underscore-bearing ones, because
# a pin name always has one.
mapfile -t ps_literals < <(text_of '[.](ps1|psm1|psd1)$' \
    | { grep -oE "'[a-z][a-z0-9]*(_[a-z0-9]+)+'" || true; } \
    | tr -d "'" | LC_ALL=C sort -u)

for name in "${bare_refs[@]-}" "${ps_literals[@]-}"; do
    [[ -z "${name}" ]] && continue
    [[ "${name}" == ansible* ]] && continue
    is_pin "${name}" && continue
    [[ -n "${defined_set["${name}"]-}" ]] && continue
    for family in "${families[@]}"; do
        if [[ "${name}" == "${family}_"* ]]; then
            missing_pins+=("${name} reads like a pin in the ${family} family and nothing pins it")
            break
        fi
    done
done

if [[ ${#missing_pins[@]} -eq 0 ]]; then
    pass "every reader in the three bounded sets names a pin that exists"
else
    mapfile -t missing_pins < <(printf '%s\n' "${missing_pins[@]}" | LC_ALL=C sort -u)
    fail "${#missing_pins[@]} reader(s) name a pin that does not exist, which is a typo or a rename that missed a callsite" \
         "$(printf '%s; ' "${missing_pins[@]}")"
fi

# --- 4. the resolved set is total ----------------------------------------------------------------
# The type rule was proven by the load above. What is left is what the reader deliberately does not
# refuse: an empty value, because absence and emptiness are different answers and the reader hands
# back an empty string as faithfully as any other, and a stray single brace, because only a full
# pair is a reference the reader would have resolved or rejected. An empty download location makes
# both dispatch tasks skip without a word, which is the whole reason this assertion exists.
empty_values=()
braced_values=()
unreachable_names=()
for name in "${pin_names[@]}"; do
    value="$(pin_value "${name}")"
    [[ -z "${value}" ]] && empty_values+=("${name}")
    [[ "${value}" == *'{'* || "${value}" == *'}'* ]] && braced_values+=("${name} = ${value}")
    [[ "$(pinned_value "${name}" 2>/dev/null)" == "${value}" ]] || unreachable_names+=("${name}")
done

if [[ ${#empty_values[@]} -eq 0 ]]; then
    pass "no pinned value is empty"
else
    fail "${#empty_values[@]} pinned value(s) resolve to nothing, and a dispatch task skips an empty location silently" \
         "${empty_values[*]}"
fi

if [[ ${#braced_values[@]} -eq 0 ]]; then
    pass "no pinned value contains a brace after resolution"
else
    fail "${#braced_values[@]} pinned value(s) still contain a brace, so something did not resolve" \
         "${braced_values[*]}"
fi

if [[ ${#unreachable_names[@]} -eq 0 ]]; then
    pass "every pin answers to the lowercase name the scans above reason about"
else
    fail "${#unreachable_names[@]} pin(s) do not answer to their lowercase name, so the scans above looked for the wrong word" \
         "${unreachable_names[*]}"
fi

# --- 5. no pin name is defined as a variable anywhere else ---------------------------------------
collisions=()
for name in "${pin_names[@]}"; do
    [[ -n "${defined_set["${name}"]-}" ]] && collisions+=("${name}")
done

if [[ ${#collisions[@]} -eq 0 ]]; then
    pass "no pin name is also defined as a variable in the ${#YAML_FILES[@]} YAML files of this repository"
else
    where=()
    for name in "${collisions[@]}"; do
        hits="$(printf '%s\0' "${YAML_FILES[@]}" \
            | { xargs -0 grep -lE "(^|[[:space:],{])${name}[[:space:]]*:" 2>/dev/null || true; } \
            | sed "s|${REPO_ROOT}/||" | tr '\n' ' ')"
        where+=("${name} in ${hits}")
    done
    fail "${#collisions[@]} pin name(s) are also defined as a variable elsewhere, and a vars plugin loses to almost everything" \
         "$(printf '%s; ' "${where[@]}")"
fi

# --- 6. the PowerShell adapter and the reader agree ----------------------------------------------
if [[ ! -f "${PS_MODULE}" ]]; then
    fail "the PowerShell adapter is missing, so the Windows installer has no way to reach a pinned value" \
         "${PS_MODULE}"
    finish "pinned values"
fi

PWSH="$(find_runnable_pwsh || true)"

if [[ -z "${PWSH}" ]]; then
    skip "the PowerShell adapter agrees with the reader key by key" "${PWSH_ABSENT_REASON}"
    finish "pinned values"
fi

ps_script="\$ErrorActionPreference = 'Stop'
if (\$PSStyle) { \$PSStyle.OutputRendering = 'PlainText' }
Import-Module '$(to_windows_path "${PS_MODULE}")' -Force
\$map = Get-PinnedValueMap
foreach (\$name in \$map.Keys) { '{0}={1}' -f \$name, \$map[\$name] }"

# Both sides are sorted here rather than in PowerShell, so one collation order applies to both and a
# culture-sensitive sort cannot produce a diff that means nothing.
ps_raw="$("${PWSH}" -NoProfile -NonInteractive -Command "${ps_script}" 2>&1 | tr -d '\r' || true)"
ps_pairs="$(grep -E '^[a-z][a-z0-9_]*=' <<<"${ps_raw}" | LC_ALL=C sort || true)"

if [[ -z "${ps_pairs}" ]]; then
    fail "the PowerShell adapter returned nothing, so the Windows installs would have no pinned values at all" \
         "$(head -5 <<<"${ps_raw}" | tr '\n' ' ')"
    finish "pinned values"
fi

core_pairs="$(for name in "${pin_names[@]}"; do printf '%s=%s\n' "${name}" "$(pin_value "${name}")"; done | LC_ALL=C sort)"
n_ps="$(grep -c . <<<"${ps_pairs}")"
assert_eq "the PowerShell adapter hands back as many pins as the reader" "${#pin_names[@]}" "${n_ps}"

if [[ "${core_pairs}" == "${ps_pairs}" ]]; then
    pass "the PowerShell adapter and the reader agree on all ${#pin_names[@]} pins, name and value"
else
    fail "the PowerShell adapter and the reader disagree, so Windows would install from different pins than Ansible" \
         "$(diff <(printf '%s\n' "${core_pairs}") <(printf '%s\n' "${ps_pairs}") | head -12 | tr '\n' ' ')"
fi

finish "pinned values"
