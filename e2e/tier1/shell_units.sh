#!/usr/bin/env bash
#
# Tier 1: unit tests for the pure functions inside setup/setup.sh.
#
# setup.sh is a wizard, so nothing that runs it in anger runs it in a way anything can assert on.
# The four functions covered here are the ones with no side effects and real consequences, and none
# of them had a single test before this file existed.
#
#   version_lt          the whole ansible-core range enforcement rests on it, and it is hand written
#                       because the sort that ships with macOS has no -V
#   format_label        decides what the user is told a toggle does
#   load_profiles       decides what the profile screen offers and what each profile claims to install
#   assert_known_keys   the refusal that stops a typo installing something other than what was asked
#
# Each function is lifted out of the shipped file rather than copied here, using the same sed
# extraction e2e/tier1/wizard_parse.sh uses, so these tests exercise the code that ships. The whole
# file runs under setup.sh's own IFS of newline and tab, because that file sets it at the top and
# several of its expansions behave differently without it.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

SETUP_SH="${REPO_ROOT}/setup/setup.sh"
GROUP_VARS_DIR="${ANSIBLE_DIR}/group_vars"
PROFILES_DIR="${ANSIBLE_DIR}/profiles"

info "Tier 1: unit tests for the pure functions in setup.sh"

if [[ ! -f "${SETUP_SH}" ]]; then
    fail "setup.sh is missing, so none of these unit tests prove anything" "${SETUP_SH}"
    finish "shell units"
fi

# Every piece of setup.sh these tests drive, as a label and the sed program that finds it.
#
# The loop below evaluates each one in the script's own scope rather than inside a helper function,
# because LABEL_OVERRIDES is an associative array and a declare inside a function is local to it.
# Evaluated in a function, the array simply does not exist afterwards, and under set -u the first
# lookup dies with "install_chrome: unbound variable" at a line that has nothing wrong with it.
#
# A piece that cannot be found is a failure rather than a skip. Every test below is an assertion
# about shipped code, so code that could not be loaded is a test that silently did not run, which is
# the one outcome this directory exists to prevent.
EXTRACTIONS=(
    "EXCLUDED_VARS|/^EXCLUDED_VARS=/{p;q;}"
    "DE_KEYS|/^DE_KEYS=/{p;q;}"
    "LABEL_OVERRIDES|/^declare -A LABEL_OVERRIDES=(/,/^)$/p"
    "version_lt|/^version_lt()/,/^}/p"
    "format_label|/^format_label()/,/^}/p"
    "is_de_key|/^is_de_key()/,/^}/p"
    "read_boolean_toggles|/^read_boolean_toggles()/,/^}/p"
    "preload_toggles|/^preload_toggles()/,/^}/p"
    "load_profiles|/^load_profiles()/,/^}/p"
    "split_key_list|/^split_key_list()/{p;q;}"
    "assert_known_keys|/^assert_known_keys()/,/^}/p"
)

IFS=$'\n\t'

EXTRACTION_FAILED=false
for extraction in "${EXTRACTIONS[@]}"; do
    extract_label="${extraction%%|*}"
    extract_program="${extraction#*|}"
    extract_text="$(sed -n "${extract_program}" "${SETUP_SH}")"
    if [[ -z "${extract_text}" ]]; then
        fail "setup.sh still defines ${extract_label}" \
             "the extraction found nothing, so every test that needs it did not run"
        EXTRACTION_FAILED=true
        continue
    fi
    eval "${extract_text}"
done

if [[ "${EXTRACTION_FAILED}" == true ]]; then
    finish "shell units"
fi

# --- version_lt ---------------------------------------------------------------------------------
#
# The table is the contract. The 2.9 against 2.19 pair is the one the function's own comment warns
# about, because every string comparison and every plain sort answers it backwards: 2.9 sorts after
# 2.19 as text and before it as a version. The pre-release rows exist because each field is cut at
# its first non-digit, and without that cut the arithmetic aborts the whole script under set -e. The
# 08 row exists because a field with a leading zero is an invalid octal number to bash, which is what
# the 10# prefix in the function is there to prevent.
#
# Each row is "left right expected", where expected is older or not-older.
version_lt_cases=(
    "2.19.0 2.20.0 older"
    "2.20.0 2.19.0 not-older"
    "2.19.0 2.19.0 not-older"
    "2.19.4 2.19.5 older"
    "2.19.5 2.19.4 not-older"
    "2.9 2.19 older"
    "2.19 2.9 not-older"
    "2.9.0 2.19.0 older"
    "1.99.99 2.0.0 older"
    "2.19 2.19.0 not-older"
    "2.19.0 2.19 not-older"
    "2.19 2.19.1 older"
    "2.19.1 2.19 not-older"
    "2 2.0.1 older"
    "2.20.0rc1 2.20.0 not-older"
    "2.20.0 2.20.0rc1 not-older"
    "2.19.9 2.20.0rc1 older"
    "2.20.0rc1 2.20.1 older"
    "2.20.1rc1 2.20.0 not-older"
    "2.08.0 2.9.0 older"
    "2.9.0 2.08.0 not-older"
    "2.19.4 2.19.0 not-older"
    "2.21.3 2.22.0 older"
    "2.22.0 2.22.0 not-older"
)

version_lt_failures=()
for case_line in "${version_lt_cases[@]}"; do
    read -r vl_left vl_right vl_expected <<<"$(tr ' ' '\t' <<<"${case_line}")"
    if version_lt "${vl_left}" "${vl_right}"; then vl_actual="older"; else vl_actual="not-older"; fi
    [[ "${vl_actual}" == "${vl_expected}" ]] \
        || version_lt_failures+=("${vl_left} vs ${vl_right}: expected ${vl_expected}, got ${vl_actual}")
done

# The row count is asserted as well as the rows, because a table that emptied itself would leave the
# loop above passing over nothing at all.
assert_eq "version_lt is driven over its whole table" "24" "${#version_lt_cases[@]}"
if [[ ${#version_lt_failures[@]} -eq 0 ]]; then
    pass "version_lt answers all ${#version_lt_cases[@]} ordering cases correctly"
else
    fail "version_lt gets an ordering wrong" "$(printf '%s | ' "${version_lt_failures[@]}")"
fi

# The two bounds the wizard actually enforces, read out of the file, so a widened range is exercised
# rather than merely declared. This is the assertion that connects the function to its one caller.
min_version="$(sed -n 's/^ANSIBLE_CORE_MIN_VERSION="\(.*\)"$/\1/p' "${SETUP_SH}")"
max_version="$(sed -n 's/^ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE="\(.*\)"$/\1/p' "${SETUP_SH}")"
if [[ -z "${min_version}" || -z "${max_version}" ]]; then
    fail "setup.sh still declares both ends of the accepted ansible-core range" \
         "ANSIBLE_CORE_MIN_VERSION or ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE was not found"
else
    if version_lt "${min_version}" "${max_version}"; then
        pass "the accepted ansible-core range ${min_version} to ${max_version} is the right way round"
    else
        fail "the accepted ansible-core range is inverted, so every version is refused" \
             "minimum ${min_version} is not older than the exclusive maximum ${max_version}"
    fi
    if version_lt "${min_version}" "${min_version}"; then
        fail "the minimum accepted ansible-core version is refused by its own bound" "${min_version}"
    else
        pass "the minimum accepted ansible-core version ${min_version} passes its own bound"
    fi
fi

# --- format_label -------------------------------------------------------------------------------
#
# Every override the file declares is driven, so an override that stops being reachable is caught
# rather than assumed. The derived cases below cover the fall-through, where the prefix is stripped
# and the underscores become spaces.
override_failures=()
override_count=0
for label_key in "${!LABEL_OVERRIDES[@]}"; do
    override_count=$((override_count + 1))
    actual_label="$(format_label "${label_key}")"
    [[ "${actual_label}" == "${LABEL_OVERRIDES[${label_key}]}" ]] \
        || override_failures+=("${label_key}: expected [${LABEL_OVERRIDES[${label_key}]}], got [${actual_label}]")
done

if [[ "${override_count}" -eq 0 ]]; then
    fail "setup.sh declares no label overrides, so the override half of format_label was not tested" \
         "LABEL_OVERRIDES came out empty"
elif [[ ${#override_failures[@]} -eq 0 ]]; then
    pass "format_label returns the declared override for all ${override_count} keys that have one"
else
    fail "format_label ignores a declared override" "$(printf '%s | ' "${override_failures[@]}")"
fi

assert_eq "format_label strips the install_ prefix"        "Chrome"        "$(format_label install_chrome)"
assert_eq "format_label turns underscores into spaces"     "Android sdk"   "$(format_label install_android_sdk)"
assert_eq "format_label strips the configure_ prefix"      "Kde plasma"    "$(format_label configure_kde_plasma)"
assert_eq "format_label strips only the leading setup_"    "Hibernate"     "$(format_label setup_hibernate)"
assert_eq "format_label leaves an unprefixed key alone"    "Wayland only"  "$(format_label wayland_only)"
assert_eq "format_label capitalises only the first letter" "Gnome shell extensions" \
          "$(format_label install_gnome_shell_extensions)"

# --- load_profiles ------------------------------------------------------------------------------
#
# Driven against the real profiles directory, because the thing worth asserting is what the wizard
# offers on this tree rather than what it would offer over a fixture. The expected values are worked
# out here from the files themselves, with a different mechanism to the one load_profiles uses, so a
# profile added tomorrow is covered with no edit to this file.
ALL_VARS="${GROUP_VARS_DIR}/all.yaml"
OS_VARS_FILE="${GROUP_VARS_DIR}/linux.yaml"
PRELOADED_ITEMS=(); PRELOADED_KEYS=()
preload_toggles

profile_files=()
while IFS= read -r profile_path; do
    [[ -n "${profile_path}" ]] && profile_files+=("${profile_path}")
done < <(find "${PROFILES_DIR}" -maxdepth 1 -name '*.yaml' -type f 2>/dev/null | sort)

if [[ ${#PRELOADED_KEYS[@]} -eq 0 ]]; then
    fail "preload_toggles produced no toggles, so nothing about load_profiles was proven" \
         "checked ${ALL_VARS} and ${OS_VARS_FILE}"
elif [[ ${#profile_files[@]} -eq 0 ]]; then
    fail "there are no profile files, so load_profiles was driven over an empty directory" "${PROFILES_DIR}"
else
    PROF_NAMES=(); PROF_FILES=(); PROF_DESCS=(); PROF_COUNTS=()
    load_profiles

    assert_eq "load_profiles offers Default plus every profile file" \
              "$(( ${#profile_files[@]} + 1 ))" "${#PROF_NAMES[@]}"
    assert_eq "the four profile arrays stay parallel" \
              "${#PROF_NAMES[@]}:${#PROF_NAMES[@]}:${#PROF_NAMES[@]}" \
              "${#PROF_FILES[@]}:${#PROF_DESCS[@]}:${#PROF_COUNTS[@]}"

    assert_eq "the first entry is the Default pseudo-profile"   "Default" "${PROF_NAMES[0]}"
    assert_eq "the Default entry names no file to load"         ""        "${PROF_FILES[0]}"
    assert_eq "the Default entry describes itself" \
              "All software from group_vars defaults" "${PROF_DESCS[0]}"

    # The Default count is every preloaded toggle that is already on. Counted here straight off the
    # state array rather than through the same loop load_profiles uses.
    expected_default_count="$(
        for (( i = 0; i < ${#PRELOADED_KEYS[@]}; i++ )); do
            printf '%s\n' "${PRELOADED_ITEMS[$(( i * 3 + 2 ))]}"
        done | grep -c '^ON$' || true
    )"
    assert_eq "the Default entry counts the toggles that are already on" \
              "${expected_default_count}" "${PROF_COUNTS[0]}"

    for (( p = 0; p < ${#profile_files[@]}; p++ )); do
        profile_path="${profile_files[$p]}"
        profile_base="$(basename "${profile_path}" .yaml)"
        entry=$(( p + 1 ))

        # The display name is the basename with underscores turned into spaces and every word
        # capitalised, which is what the loop inside load_profiles is written to do. Built here with
        # sed rather than with the shell expansion that function uses, so the two cannot share a
        # mistake.
        expected_name="$(tr '_' ' ' <<<"${profile_base}" | sed -E 's/(^| )([a-z])/\1\u\2/g')"

        # The description is the first comment line, and only while the lines above it are the YAML
        # document marker. Anything else, including a blank line, ends the search.
        expected_desc="$(awk '
            $0 == "---" { next }
            substr($0, 1, 1) == "#" { sub(/^# ?/, "", $0); print; exit }
            { exit }
        ' "${profile_path}")"
        [[ -z "${expected_desc}" ]] && expected_desc="No description"

        # The count is the Default count adjusted by what this profile actually changes, which is a
        # different sum to the recount load_profiles performs.
        turned_off=0; turned_on=0
        for (( i = 0; i < ${#PRELOADED_KEYS[@]}; i++ )); do
            override_line="$(grep -m1 "^${PRELOADED_KEYS[$i]}:" "${profile_path}" || true)"
            [[ -z "${override_line}" ]] && continue
            if [[ "${override_line}" == *"true"* ]]; then
                [[ "${PRELOADED_ITEMS[$(( i * 3 + 2 ))]}" == "OFF" ]] && turned_on=$(( turned_on + 1 ))
            else
                [[ "${PRELOADED_ITEMS[$(( i * 3 + 2 ))]}" == "ON" ]] && turned_off=$(( turned_off + 1 ))
            fi
        done
        expected_count=$(( expected_default_count + turned_on - turned_off ))

        actual_name="${PROF_NAMES[${entry}]:-<missing>}"
        if [[ "${actual_name}" == "${expected_name}" ]]; then
            pass "${profile_base}: the profile is offered under its title-cased name"
        else
            fail "${profile_base}: the profile name is not title-cased" \
                 "expected [${expected_name}], got [${actual_name}]. load_profiles capitalises the name with an unquoted expansion, and setup.sh sets IFS to newline and tab at the top of the file, so a multi-word name is never split on its space and only its first letter is capitalised"
        fi
        assert_eq "${profile_base}: the profile records the file the wizard would load" \
                  "${profile_base}" "${PROF_FILES[${entry}]:-<missing>}"
        assert_eq "${profile_base}: the description is the first comment line of the file" \
                  "${expected_desc}" "${PROF_DESCS[${entry}]:-<missing>}"
        assert_eq "${profile_base}: the package count is the default count adjusted by the overrides" \
                  "${expected_count}" "${PROF_COUNTS[${entry}]:-<missing>}"

        # A profile that changes nothing would make the count assertion above pass for the wrong
        # reason, so the profile is required to be doing something.
        if [[ $(( turned_on + turned_off )) -gt 0 ]]; then
            pass "${profile_base}: the profile changes ${turned_off} toggle(s) off and ${turned_on} on, so its count is a real result"
        else
            fail "${profile_base}: the profile overrides nothing the wizard offers" \
                 "its count therefore cannot distinguish a working recount from a broken one"
        fi
    done
fi

# --- assert_known_keys --------------------------------------------------------------------------
#
# The refusal path calls exit 2, so it has to be driven in a subshell and judged on the status and
# the standard error rather than on a return value. That is exactly why the shipped code calls this
# from the entrypoint instead of from inside software_override_vars, where the exit would have ended
# a process substitution and let the run carry on with an empty override list.
if [[ ${#PRELOADED_KEYS[@]} -eq 0 ]]; then
    fail "there are no known keys, so nothing about assert_known_keys was proven" "PRELOADED_KEYS is empty"
else
    known_one="${PRELOADED_KEYS[0]}"
    known_two="${PRELOADED_KEYS[$(( ${#PRELOADED_KEYS[@]} - 1 ))]}"

    accept_status=0
    accept_output="$( assert_known_keys --enable "${known_one},${known_two}" 2>&1 )" || accept_status=$?
    assert_eq "assert_known_keys accepts two keys the wizard offers" "0" "${accept_status}"
    assert_eq "accepting keys says nothing at all" "" "${accept_output}"

    accept_status=0
    assert_known_keys --enable "" >/dev/null 2>&1 || accept_status=$?
    assert_eq "assert_known_keys accepts an empty list, which is what an unused option looks like" \
              "0" "${accept_status}"

    accept_status=0
    assert_known_keys --disable "${known_one} ${known_two}" >/dev/null 2>&1 || accept_status=$?
    assert_eq "assert_known_keys accepts a space separated list as well as a comma separated one" \
              "0" "${accept_status}"

    refuse_status=0
    refuse_output="$( assert_known_keys --enable "install_not_a_real_package" 2>&1 )" || refuse_status=$?
    assert_eq "an unknown key exits 2, the usage code" "2" "${refuse_status}"
    if grep -q 'install_not_a_real_package' <<<"${refuse_output}"; then
        pass "the refusal names the key it refused"
    else
        fail "the refusal does not name the key it refused" "stderr was [${refuse_output}]"
    fi
    if grep -q -- '--list-software' <<<"${refuse_output}"; then
        pass "the refusal points at --list-software, which is where the accepted keys are"
    else
        fail "the refusal does not say where the accepted keys are" "stderr was [${refuse_output}]"
    fi
    if grep -q -- '--enable' <<<"${refuse_output}"; then
        pass "the refusal names the option that carried the bad key"
    else
        fail "the refusal does not name the option that carried the bad key" "stderr was [${refuse_output}]"
    fi

    # One good key beside one bad one. A refusal that counted both, or that gave up before reaching
    # the bad one, would be just as wrong as one that let it through.
    refuse_status=0
    refuse_output="$( assert_known_keys --enable "${known_one},install_not_a_real_package" 2>&1 )" || refuse_status=$?
    assert_eq "a list mixing a good key with a bad one is still refused" "2" "${refuse_status}"
    if grep -q '1 key(s)' <<<"${refuse_output}"; then
        pass "the refusal counts only the key that was actually unknown"
    else
        fail "the refusal miscounts the unknown keys" "stderr was [${refuse_output}]"
    fi
    if grep -q "${known_one}" <<<"${refuse_output}"; then
        fail "the refusal names a key the wizard does offer" "stderr was [${refuse_output}]"
    else
        pass "the refusal does not name the key the wizard does offer"
    fi
fi

finish "shell units"
