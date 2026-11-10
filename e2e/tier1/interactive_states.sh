#!/usr/bin/env bash
#
# Tier 1: the interactive state machine in setup/setup.sh goes where it says it goes.
#
# main_interactive has six states and seven back edges, and until this file existed nothing had ever
# executed any of them. The wizard is the path a person actually takes, so every one of those edges
# is code that reaches a real machine and that no gate had an opinion about.
#
# Driving the gum widgets is out of scope and is not worth the machinery. What is driven instead is
# the machine itself: main_interactive is lifted out of the shipped file, the six pick functions and
# confirm_run are replaced by stubs that hand back a scripted SCREEN_RESULT, and a sequence of
# answers is pushed through. Everything the states reach at their edges is stubbed too, so nothing
# installs and no playbook runs.
#
# The stubs are deliberately thin, because a permissive stub turns this into a test of the stubs.
# Two things keep that honest. Every assertion is made on the sequence of states the run visited
# rather than only on where it ended, so a machine that reached the right place by the wrong route
# fails. And the two states that produce something, the desktop screen and the checklist, are
# additionally judged on the variables they hand to the playbook, using the shipped
# desktop_override_vars rather than a restatement of it.
#
# The toggle and profile fixtures are synthetic on purpose. The state machine treats PRELOADED_KEYS
# and PROF_FILES as opaque lists, so a small known set makes the expected output exact, and the real
# group_vars files are covered by e2e/tier1/wizard_parse.sh and e2e/tier1/selection_parity.sh.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

SETUP_SH="${REPO_ROOT}/setup/setup.sh"

info "Tier 1: the interactive state machine in setup.sh"

if [[ ! -f "${SETUP_SH}" ]]; then
    fail "setup.sh is missing, so none of these transitions were driven" "${SETUP_SH}"
    finish "interactive states"
fi

main_text="$(sed -n '/^main_interactive()/,/^}/p' "${SETUP_SH}")"
desktop_text="$(sed -n '/^desktop_override_vars()/,/^}/p' "${SETUP_SH}")"
if [[ -z "${main_text}" || -z "${desktop_text}" ]]; then
    fail "setup.sh still defines main_interactive and desktop_override_vars" \
         "one of them was not found, so not a single transition was driven"
    finish "interactive states"
fi

# The states are read out of the shipped case statement rather than listed here. A state added
# tomorrow that no sequence below reaches will therefore be reported as never visited, instead of
# quietly sitting outside a hand-maintained list.
DECLARED_STATES="$(grep -oE '^[[:space:]]+[a-z_]+\)$' <<<"${main_text}" | tr -d ' )' | sort -u)"
if [[ -z "${DECLARED_STATES}" ]]; then
    fail "no states could be read out of main_interactive, so reachability proves nothing" \
         "looked for case labels inside the extracted function body"
    finish "interactive states"
fi

# setup.sh sets IFS to newline and tab at the top of the file, and the checklist path depends on it,
# so the same value is set here before anything from that file is evaluated.
IFS=$'\n\t'

eval "${desktop_text}"
eval "${main_text}"

TRACE_FILE="$(mktemp)"
EXTRAS_FILE="$(mktemp)"
cleanup() { rm -f "${TRACE_FILE}" "${EXTRAS_FILE}"; }
trap cleanup EXIT

# --- fixtures ------------------------------------------------------------------------------------
# Every one of these is read by the wizard functions eval'd out of setup.sh above, and by
# nothing in this file, so shellcheck sees an assignment with no reader.
# shellcheck disable=SC2034
PRELOADED_KEYS=("install_alpha" "install_beta" "install_gamma" "install_delta")
# shellcheck disable=SC2034
PROF_NAMES=("Default" "Demo Profile")
# shellcheck disable=SC2034
PROF_FILES=("" "demo_profile")
ANSIBLE_DIR="${ANSIBLE_DIR}"
PLAYBOOK_ARGS=()
SCREEN_RESULT=""
OPT_PROFILE=""

# --- stubs ---------------------------------------------------------------------------------------
#
# Two exit codes stand for the two ways the machine can end, and two more for the ways a test can be
# wrong. A run that falls off the end of its answers, or that goes round more times than any correct
# path could, ends loudly rather than hanging or passing.
readonly EXIT_PLAYBOOK_RAN=70
readonly EXIT_ANSWERS_EXHAUSTED=90
readonly EXIT_TOO_MANY_SCREENS=91
readonly MAX_SCREENS=24

ANSWERS=()
ANSWER_INDEX=0
ANSWER_VALUE=""
SCREEN_COUNT=0

take_answer() {
    printf '%s\n' "$1" >> "${TRACE_FILE}"
    SCREEN_COUNT=$(( SCREEN_COUNT + 1 ))
    if (( SCREEN_COUNT > MAX_SCREENS )); then
        printf 'LOOP\n' >> "${TRACE_FILE}"
        exit "${EXIT_TOO_MANY_SCREENS}"
    fi
    if (( ANSWER_INDEX >= ${#ANSWERS[@]} )); then
        printf 'ANSWERS-EXHAUSTED\n' >> "${TRACE_FILE}"
        exit "${EXIT_ANSWERS_EXHAUSTED}"
    fi
    ANSWER_VALUE="${ANSWERS[${ANSWER_INDEX}]}"
    ANSWER_INDEX=$(( ANSWER_INDEX + 1 ))
}

pick_de()          { take_answer de;        SCREEN_RESULT="${ANSWER_VALUE}"; }
pick_de_action()   { take_answer de_action; SCREEN_RESULT="${ANSWER_VALUE}"; }
pick_review_mode() { take_answer review;    SCREEN_RESULT="${ANSWER_VALUE}"; }
pick_profile()     { take_answer profile;   SCREEN_RESULT="${ANSWER_VALUE}"; }
confirm_run()      { take_answer confirm;   SCREEN_RESULT="${ANSWER_VALUE}"; }

# The answer is written as a comma separated list for readability, and handed back joined exactly
# the way the shipped pick_software joins it, with "${array[*]}". That expansion uses the first
# character of IFS, so reproducing the join rather than inventing one is the difference between
# testing what the checklist really hands over and testing a convenient fiction.
pick_software() {
    take_answer checklist
    if [[ -z "${ANSWER_VALUE}" ]]; then
        SCREEN_RESULT=""
        return
    fi
    local picked=() item
    while IFS= read -r item; do
        [[ -n "${item}" ]] && picked+=("${item}")
    done < <(tr ',' '\n' <<<"${ANSWER_VALUE}")
    # Read by the eval'd state machine, which is the caller of every stub in this block.
    # shellcheck disable=SC2034
    SCREEN_RESULT="${picked[*]}"
}

goodbye_splash() { printf 'goodbye\n' >> "${TRACE_FILE}"; }

build_playbook_args() {
    local arg
    for arg in "$@"; do printf 'extra %s\n' "${arg}" >> "${EXTRAS_FILE}"; done
    printf 'profile %s\n' "${OPT_PROFILE}" >> "${EXTRAS_FILE}"
    # Read by the eval'd main flow, not here.
    # shellcheck disable=SC2034
    PLAYBOOK_ARGS=("site.yaml")
}

# Named with a hyphen so the state machine's own call reaches it instead of a real Ansible.
ansible-playbook() { printf 'playbook\n' >> "${TRACE_FILE}"; }

finish_run() { printf 'finish\n' >> "${TRACE_FILE}"; exit "${EXIT_PLAYBOOK_RAN}"; }

# --- driver ---------------------------------------------------------------------------------------
DRIVE_TRACE=""
DRIVE_STATUS=0
DRIVE_EXTRAS=""
VISITED_STATES=""

drive() {
    ANSWERS=("$@")
    : > "${TRACE_FILE}"
    : > "${EXTRAS_FILE}"
    DRIVE_STATUS=0
    ( ANSWER_INDEX=0; SCREEN_COUNT=0; OPT_PROFILE=""; main_interactive ) >/dev/null 2>&1 \
        || DRIVE_STATUS=$?
    DRIVE_TRACE="$(tr '\n' ' ' < "${TRACE_FILE}" | sed -E 's/ +$//')"
    DRIVE_EXTRAS="$(cat "${EXTRAS_FILE}")"
    VISITED_STATES="${VISITED_STATES}${DRIVE_TRACE} "
}

# expect_run <name> <expected trace> <answer>...   the machine reaches the playbook by that route
expect_run() {
    local name="$1" expected="$2"; shift 2
    drive "$@"
    if [[ "${DRIVE_TRACE}" == "${expected}" && "${DRIVE_STATUS}" -eq "${EXIT_PLAYBOOK_RAN}" ]]; then
        pass "${name}"
    else
        fail "${name}" "expected route [${expected}] ending in the playbook, got [${DRIVE_TRACE}] with status ${DRIVE_STATUS}"
    fi
}

# --- cancelling at each of the six states ---------------------------------------------------------
#
# The desktop screen is the root, so cancelling there is the only cancel that ends the run. The file
# says so in as many words, and it exits 0 after the goodbye splash rather than treating a deliberate
# cancellation as a failure.
drive ""
if [[ "${DRIVE_TRACE}" == "de goodbye" && "${DRIVE_STATUS}" -eq 0 ]]; then
    pass "cancelling at the desktop screen shows the goodbye splash and exits 0"
else
    fail "cancelling at the desktop screen does not end the run cleanly" \
         "expected route [de goodbye] and status 0, got [${DRIVE_TRACE}] with status ${DRIVE_STATUS}"
fi

expect_run "cancelling at the desktop action screen goes back to the desktop screen" \
           "de de_action de review confirm playbook finish" \
           "kde" "" "skip" "defaults" "run"

expect_run "cancelling at the review screen goes back to the action screen when a desktop was chosen" \
           "de de_action review de_action review confirm playbook finish" \
           "kde" "full" "" "full" "defaults" "run"

expect_run "cancelling at the review screen goes back to the desktop screen when the desktop was skipped" \
           "de review de review confirm playbook finish" \
           "skip" "" "skip" "defaults" "run"

expect_run "cancelling at the checklist goes back to the review screen" \
           "de review checklist review confirm playbook finish" \
           "skip" "customise" "" "defaults" "run"

expect_run "cancelling at the profile screen goes back to the review screen" \
           "de review profile review confirm playbook finish" \
           "skip" "profile" "" "defaults" "run"

expect_run "cancelling at the confirmation goes back to the checklist when the checklist made the selection" \
           "de review checklist confirm checklist confirm playbook finish" \
           "skip" "customise" "install_alpha" "" "install_alpha" "run"

expect_run "cancelling at the confirmation goes back to the review screen when the selection came from group_vars" \
           "de review confirm review confirm playbook finish" \
           "skip" "defaults" "" "defaults" "run"

# A profile leaves have_pkg_vars false, so cancelling the confirmation lands on the review screen
# rather than on a checklist the user never opened.
expect_run "cancelling at the confirmation after a profile goes back to the review screen" \
           "de review profile confirm review confirm playbook finish" \
           "skip" "profile" "1" "" "defaults" "run"

# --- forward passes --------------------------------------------------------------------------------
expect_run "a full forward pass through the checklist reaches the playbook" \
           "de de_action review checklist confirm playbook finish" \
           "kde" "full" "customise" "install_alpha,install_gamma" "run"
checklist_extras="${DRIVE_EXTRAS}"

expect_run "a forward pass that skips the desktop and keeps the group_vars defaults reaches the playbook" \
           "de review confirm playbook finish" \
           "skip" "defaults" "run"
defaults_extras="${DRIVE_EXTRAS}"

expect_run "a forward pass through a profile reaches the playbook" \
           "de review profile confirm playbook finish" \
           "skip" "profile" "1" "run"
profile_extras="${DRIVE_EXTRAS}"

expect_run "gnome reaches the same action screen as kde" \
           "de de_action review confirm playbook finish" \
           "gnome" "configure" "defaults" "run"
gnome_extras="${DRIVE_EXTRAS}"

# --- every state was reached -----------------------------------------------------------------------
unreached=""
while IFS= read -r declared_state; do
    [[ -z "${declared_state}" ]] && continue
    grep -q " ${declared_state} \| ${declared_state}$\|^${declared_state} " <<<" ${VISITED_STATES}" \
        || unreached="${unreached}${declared_state} "
done <<<"${DECLARED_STATES}"

declared_count="$(grep -c . <<<"${DECLARED_STATES}")"
if [[ -z "${unreached}" ]]; then
    pass "all ${declared_count} states declared in main_interactive were reached by these sequences"
else
    fail "a state declared in main_interactive was never reached" \
         "never visited: ${unreached}"
fi

# --- what each state actually handed the playbook ----------------------------------------------------
#
# The route being right is not the same as the run being right. These assert on the variables the
# machine built, which is the part a stub cannot fake, because desktop_override_vars is the shipped
# function and the checklist conversion is the shipped code inside main_interactive.
assert_eq "choosing kde and full turns both kde variables on" \
          "extra install_kde_plasma=true
extra configure_kde_plasma=true" \
          "$(grep -E '^extra (install|configure)_kde_plasma=' <<<"${checklist_extras}")"

assert_eq "choosing gnome and configure installs nothing and configures the existing desktop" \
          "extra install_gnome=false
extra configure_gnome=true" \
          "$(grep -E '^extra (install|configure)_gnome=' <<<"${gnome_extras}")"

assert_eq "skipping the desktop and keeping the defaults passes no extra variable at all" \
          "profile " "${defaults_extras}"

assert_eq "picking a profile hands its file to the playbook builder" \
          "profile demo_profile" "$(grep '^profile ' <<<"${profile_extras}")"

# The checklist has to carry every key the user marked, and mark every other key false. This is the
# one assertion here that judges data rather than control flow, and it is the reason pick_software
# above reproduces the shipped join instead of inventing a friendlier one.
expected_checklist="extra install_alpha=true
extra install_beta=false
extra install_gamma=true
extra install_delta=false"
actual_checklist="$(grep -E '^extra install_(alpha|beta|gamma|delta)=' <<<"${checklist_extras}")"
if [[ "${actual_checklist}" == "${expected_checklist}" ]]; then
    pass "the checklist turns exactly the marked toggles on and every other one off"
else
    fail "the checklist does not carry every toggle the user marked" \
         "expected [${expected_checklist}], got [${actual_checklist}]. pick_software joins the marked keys with \"\${_results[*]}\", which uses the first character of IFS, and setup.sh sets IFS to newline and tab, so the checklist state receives them one per line. The 'read -ra selected_keys' that consumes them has no -d, so it reads the first line and stops, and every key after the first is written out as false"
fi

finish "interactive states"
