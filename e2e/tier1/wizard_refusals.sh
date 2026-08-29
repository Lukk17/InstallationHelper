#!/usr/bin/env bash
#
# Tier 1: every argument the wizard refuses must actually be refused, and must say why.
#
# setup/setup.sh has ten places that print an error and exit 2, and until this check existed not one
# of them had ever been executed by anything. They are the whole defence against the shape of defect
# this repository keeps producing: a run that installs something other than what it was asked for
# and reports success anyway. A refusal that silently stopped refusing, because a case branch moved
# or a condition inverted, would turn a mistyped --software value into a defaults run that nobody
# ordered and nothing would say so.
#
# So each refusal is driven as a real process rather than by reading the source, and three things
# are asserted about it. It exits 2, which is what the wizard's own header documents for bad usage.
# Its standard error names the option or the value at fault, because a refusal that exits 2 with the
# wrong message is a refusal the user cannot act on. And it never reaches the machine, which is
# checked by looking for the lines the upgrade and the Ansible bootstrap print.
#
# Every case is safe to run on a developer machine. Nine of the ten sites are inside parse_args or
# validate_selection_options, both of which run before prepare_become_password, ensure_ansible and
# system_upgrade. The tenth, the missing profile, lives in build_playbook_args, which a real run
# reaches only after the password prompt, so that one case is driven with --print-command alongside
# it: that branch calls build_playbook_args at line 1404 and exits, while prepare_become_password is
# at line 1416 and everything that touches the machine is below it.
#
# The list of cases below is not the assertion of completeness. The completeness assertion is at the
# bottom and is mechanical: each run is traced, the line number of the exit 2 it reached is recorded,
# and the set of line numbers reached is compared against every exit 2 in the file. A refusal added
# tomorrow and covered by nobody fails this check by name.
#
# The runs are started together and waited for once. Three of them get past parse_args into
# preload_toggles, which costs nine seconds on Git Bash in process creation alone, and in sequence
# that made this check the slowest thing in a gate that answers in seconds.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: the wizard refuses a bad selection"

SETUP_SH="${REPO_ROOT}/setup/setup.sh"
GROUP_VARS_DIR="${ANSIBLE_DIR}/group_vars"

if [[ ! -f "${SETUP_SH}" ]]; then
    fail "the wizard is missing, so this check proves nothing" "${SETUP_SH}"
    finish "wizard refusals"
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

# A key that must not exist, used to drive the two unknown-key refusals. Asserted rather than
# assumed, because the day somebody adds a toggle by this name the two cases below would start
# passing validation and this check would report a refusal that never happened.
UNKNOWN_KEY="install_definitely_not_a_real_toggle"
if grep -rqE "^${UNKNOWN_KEY}:" "${GROUP_VARS_DIR}"; then
    fail "the key this check uses to drive the unknown-key refusals now exists" \
         "${UNKNOWN_KEY} was found in ${GROUP_VARS_DIR}, so pick another one"
fi

CASE_ORDER=()

# start_case <name> <label> <stderr regex> -- <argument>...
#
# Runs the wizard under bash -x, with the trace sent to file descriptor 9 so that standard error
# stays exactly what a user would see. PS4 carries the line number, which is how the site of the
# exit 2 is recorded for the completeness assertion at the bottom. Standard input is closed so that
# a case which one day reaches a prompt fails instead of hanging the gate.
start_case() {
    local name="$1" label="$2" needle="$3"; shift 3
    [[ "${1:-}" == "--" ]] && shift
    CASE_ORDER+=("${name}")
    printf '%s\n' "${label}" >"${WORK_DIR}/${name}.label"
    printf '%s\n' "${needle}" >"${WORK_DIR}/${name}.needle"
    (
        local rc=0
        PS4='+${LINENO}+ ' BASH_XTRACEFD=9 \
            bash -x "${SETUP_SH}" "$@" \
                >"${WORK_DIR}/${name}.out" 2>"${WORK_DIR}/${name}.err" 9>"${WORK_DIR}/${name}.trace" \
                </dev/null || rc=$?
        printf '%s\n' "${rc}" >"${WORK_DIR}/${name}.rc"
    ) &
}

# --- a value no option accepts -----------------------------------------------
# All three go through require_one_of, and all three are driven, because the option name and the
# accepted list it prints are per-callsite and a wrong list is as unactionable as no message.
start_case de_bogus \
    "--desktop-environment refuses a value it does not accept" \
    "--desktop-environment does not accept 'bogus'.*Accepted: skip kde gnome" \
    -- --desktop-environment bogus

start_case action_bogus \
    "--desktop-action refuses a value it does not accept" \
    "--desktop-action does not accept 'bogus'.*Accepted: full install configure" \
    -- --desktop-environment kde --desktop-action bogus

start_case software_bogus \
    "--software refuses a value it does not accept" \
    "--software does not accept 'bogus'.*Accepted: defaults all none" \
    -- --software bogus

# --- an option with nothing after it ------------------------------------------
start_case profile_empty \
    "--profile refuses to be passed with no value" \
    '\-\-profile requires a value' \
    -- --profile

# --- an option that does not exist --------------------------------------------
start_case unknown_option \
    "an unknown option is refused rather than ignored" \
    'Unknown option: --frobnicate' \
    -- --frobnicate

# --- the two halves of the desktop choice must arrive together -----------------
start_case action_without_de \
    "a desktop action with no environment is refused" \
    '\-\-desktop-action needs --desktop-environment kde or gnome' \
    -- --desktop-action full

start_case action_with_skip \
    "a desktop action against the skip environment is refused" \
    '\-\-desktop-action needs --desktop-environment kde or gnome' \
    -- --desktop-environment skip --desktop-action full

start_case de_without_action \
    "a desktop environment with no action is refused" \
    '\-\-desktop-environment kde needs --desktop-action full, install or configure' \
    -- --desktop-environment kde

# --- two answers to one question ----------------------------------------------
start_case profile_and_software \
    "--profile and --software together are refused" \
    '\-\-profile and --software both decide the software set' \
    -- --profile linux_live --software all

start_case verify_and_print \
    "--verify-only and --print-command together are refused" \
    '\-\-verify-only and --print-command each end the run on their own' \
    -- --verify-only --print-command

# --- a key the checklist does not offer ---------------------------------------
start_case enable_unknown_key \
    "--enable refuses a key the wizard does not offer" \
    "--enable names 1 key\\(s\\) the wizard does not offer: ${UNKNOWN_KEY}" \
    -- --enable "${UNKNOWN_KEY}"

start_case disable_unknown_key \
    "--disable refuses a key the wizard does not offer" \
    "--disable names 1 key\\(s\\) the wizard does not offer: ${UNKNOWN_KEY}" \
    -- --disable "${UNKNOWN_KEY}"

# --- a profile file that is not there ------------------------------------------
# --print-command is passed so the refusal is reached from the branch that answers and exits, rather
# than from the branch that runs below the password prompt. The refusal itself is the same one.
start_case profile_missing \
    "a profile naming a file that does not exist is refused" \
    'profile not found: .*no_such_profile\.yaml' \
    -- --print-command --profile no_such_profile

wait || true

# --- what each run did ----------------------------------------------------------
COVERED_SITES=()
for name in "${CASE_ORDER[@]}"; do
    label="$(cat "${WORK_DIR}/${name}.label")"
    needle="$(cat "${WORK_DIR}/${name}.needle")"
    rc="$(cat "${WORK_DIR}/${name}.rc" 2>/dev/null || echo missing)"
    problems=()

    # The line number only. Trimming everything that is not a digit looks like it would do, and it
    # is wrong: the traced line is +191+ exit 2, so that would hand back 1912 and every recorded
    # site would be a number the file does not have.
    site="$(grep -oE '^\+[0-9]+\+ exit 2$' "${WORK_DIR}/${name}.trace" 2>/dev/null \
            | head -1 | grep -oE '[0-9]+' | head -1 || true)"
    [[ -n "${site}" ]] && COVERED_SITES+=("${site}")

    if [[ "${rc}" != "2" ]]; then
        problems+=("exited ${rc} where 2 is what the wizard documents for bad usage")
    fi

    if ! grep -qE -- "${needle}" "${WORK_DIR}/${name}.err"; then
        problems+=("standard error does not name what is wrong, wanted /${needle}/ and got [$(tr '\n' ' ' <"${WORK_DIR}/${name}.err" | cut -c1-160)]")
    fi

    if grep -qE 'Running full system upgrade|Ansible not found|Ansible: already installed' \
              "${WORK_DIR}/${name}.out" "${WORK_DIR}/${name}.err"; then
        problems+=("the run reached the machine before it refused")
    fi

    if [[ -z "${site}" ]]; then
        problems+=("no exit 2 was traced, so it is unknown which refusal answered")
    fi

    if [[ ${#problems[@]} -eq 0 ]]; then
        pass "${label} (refused at line ${site})"
    else
        fail "${label}" "$(printf '%s | ' "${problems[@]}")"
    fi
done

# --- completeness --------------------------------------------------------------
# Every exit 2 in the wizard, minus the ones inside the bash version guard at the top of the file.
# Those refuse a bash older than 4, which cannot be driven here: the only interpreter that reaches
# them is one that this repository's supported machines no longer ship, and the guard re-execs into
# a newer bash whenever one is installed. The range is located by its condition rather than by a
# line number, so removing or moving that block makes those sites required again instead of quietly
# staying excluded.
bash4_start="$(grep -n 'BASH_VERSINFO\[0\]:-0}" -lt 4' "${SETUP_SH}" | head -1 | cut -d: -f1)"
bash4_end=""
if [[ -n "${bash4_start}" ]]; then
    bash4_end="$(awk -v start="${bash4_start}" 'NR > start && /^fi$/ { print NR; exit }' "${SETUP_SH}")"
fi

if [[ -z "${bash4_start}" || -z "${bash4_end}" ]]; then
    fail "the bash version guard could not be located in the wizard, so the completeness assertion cannot run" \
         "looked for the BASH_VERSINFO condition and the fi that closes it in ${SETUP_SH}"
else
    expected_sites="$(awk -v start="${bash4_start}" -v end="${bash4_end}" '
        {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (line ~ /^#/) next
            if ($0 ~ /exit 2/ && (NR < start || NR > end)) print NR
        }' "${SETUP_SH}" | sort -n)"

    covered_sites=""
    if [[ ${#COVERED_SITES[@]} -gt 0 ]]; then
        covered_sites="$(printf '%s\n' "${COVERED_SITES[@]}" | sort -nu)"
    fi

    if [[ -z "${expected_sites}" ]]; then
        fail "no refusal was found in the wizard at all, so this check proves nothing" \
             "no uncommented exit 2 outside the bash version guard in ${SETUP_SH}"
    elif [[ "${expected_sites}" == "${covered_sites}" ]]; then
        pass "every refusal in the wizard was driven ($(grep -c . <<<"${expected_sites}") sites, ${#CASE_ORDER[@]} cases)"
    else
        # Compared with grep rather than comm, because comm wants both sides sorted the same way and
        # these are numbers: a lexicographic sort would put 1000 before 184 and the difference would
        # be wrong rather than merely oddly ordered.
        missed="$(grep -vxF -f <(echo "${covered_sites}") <<<"${expected_sites}" || true)"
        detail=""
        while IFS= read -r line_number; do
            [[ -z "${line_number}" ]] && continue
            detail+="line ${line_number}: $(sed -n "${line_number}p" "${SETUP_SH}" | sed -E 's/^[[:space:]]+//' | cut -c1-90) | "
        done <<<"${missed}"
        fail "a refusal in the wizard is driven by nothing here" \
             "${detail:-covered sites [${covered_sites//$'\n'/ }] do not match expected [${expected_sites//$'\n'/ }]}"
    fi
fi

if [[ ${#CASE_ORDER[@]} -eq 0 ]]; then
    fail "no refusal case was driven at all, so this check proves nothing" "start_case was never called"
fi

finish "wizard refusals"
