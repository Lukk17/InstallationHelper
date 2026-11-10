#!/usr/bin/env bash
#
# Tier 1: setup/setup.sh is the only place the accepted ansible-core range is written, and every tier 3
# image is held to it.
#
# Each tier 3 image fails its own build when its ansible-core is outside ANSIBLE_CORE_MIN_VERSION up to
# but not including ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE. Until 2026-11-10 each of the five Dockerfiles
# carried its own copy of both bounds as ARG defaults, and the prose beside them stated the numbers
# again, while nothing compared the copies with setup.sh, so they were kept in step by hand
# (docs/regression_ledger.md 10.263). Now e2e/tier3/container.sh reads both out of setup.sh with
# setup_sh_ansible_core_range in lib/common.sh and passes them to every build as build arguments.
#
# Three things are asserted.
#
#   Every e2e/tier3/*.Dockerfile gives neither ARG a default and sets neither with ENV, and states
#   neither bound setup.sh declares today, comments included. One that builds on a distribution image
#   rather than on another image of this directory declares both ARGs bare and has exactly one RUN that
#   names both.
#   That RUN, run with sh in this container, refuses with a message naming e2e/run.sh --tier 3 when
#   either argument is missing, passes with the range read out of setup.sh, because the gate's own
#   ansible-core sits inside it (e2e/gate/provision.sh refuses to build the gate otherwise), and refuses
#   with "outside the range" for a range the gate's version is below, which proves the guard hands
#   over to the version check rather than ending the command.
#   Every docker build under e2e/, apart from tier1/ and the gate image's own build in lib/gate.sh,
#   and every docker build in a workflow or action under .github/, passes both as --build-arg with a
#   variable as the value, never a number, from a file that calls setup_sh_ansible_core_range. A
#   workflow step using docker/build-push-action fails, because this check cannot read its arguments.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

LABEL="tier 3 ansible-core range"
TIER3_DIR="${REPO_ROOT}/e2e/tier3"
RANGE_NAMES="ANSIBLE_CORE_MIN_VERSION|ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE"

info "Tier 1: the tier 3 images take the ansible-core range from setup/setup.sh and from nowhere else"

if ! setup_sh_ansible_core_range; then
    fail "setup/setup.sh declares ANSIBLE_CORE_MIN_VERSION and ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE" \
         "setup_sh_ansible_core_range in e2e/lib/common.sh read nothing, so there is no range to hold the images to"
    finish "${LABEL}"
fi
floor="${ANSIBLE_CORE_MIN_VERSION}"
ceiling="${ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE}"
pass "setup/setup.sh declares the range ${floor} <= version < ${ceiling}"

# --- the Dockerfiles ------------------------------------------------------------------------------

# "<line number> <text>" for every ARG or ENV line that gives one of the two names a value, and
# "declared <name>" for every bare ARG of one of them.
range_arg_lines() {
    awk -v names="^(${RANGE_NAMES})$" '
        { sub(/\r$/, "") }
        toupper($1) == "ENV" {
            for (i = 2; i <= NF; i++) {
                field = $i; sub(/=.*/, "", field)
                if (field ~ names) { print FNR " " $0; next }
            }
        }
        toupper($1) == "ARG" {
            for (i = 2; i <= NF; i++) {
                field = $i; name = field; sub(/=.*/, "", name)
                if (name !~ names) continue
                if (field ~ /=/) print FNR " " $0
                else print "declared " name
            }
        }' "$1"
}

# Every RUN instruction of a Dockerfile as one line, continuation lines joined, without the RUN word.
run_instructions() {
    awk '
        { sub(/\r$/, "") }
        collecting {
            line = $0
            more = sub(/\\$/, "", line)
            command = command " " line
            if (!more) { print command; collecting = 0 }
            next
        }
        toupper($1) == "RUN" {
            line = $0
            sub(/^[[:space:]]*[Rr][Uu][Nn][[:space:]]+/, "", line)
            more = sub(/\\$/, "", line)
            command = line
            if (more) collecting = 1
            else print command
        }' "$1"
}

floor_pattern="(^|[^0-9.])${floor//./\\.}([^0-9]|$)"
ceiling_pattern="(^|[^0-9.])${ceiling//./\\.}([^0-9]|$)"

# One answer per distinct RUN text and case, because the five images carry the same command and each
# case that reaches the version check starts ansible-playbook once.
declare -A guard_results=()

# run_guard <command> <case>  ->  prints nothing, sets GUARD_STATUS to the command's exit status and
#                                 GUARD_OUTPUT to its output on one line
#
# case is none, floor-only, setup or above: no argument, only the floor, the range setup.sh declares,
# or a range starting at setup.sh's ceiling, which the gate's ansible-core is below.
run_guard() {
    local command="$1" which="$2" key rc=0 output
    key="${which}|${command}"
    if [[ -z "${guard_results[${key}]+set}" ]]; then
        local -a values=()
        case "${which}" in
            none)       values=() ;;
            floor-only) values=("ANSIBLE_CORE_MIN_VERSION=${floor}") ;;
            setup)      values=("ANSIBLE_CORE_MIN_VERSION=${floor}" "ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE=${ceiling}") ;;
            above)      values=("ANSIBLE_CORE_MIN_VERSION=${ceiling}" "ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE=9999.0.0") ;;
        esac
        output="$(env -u ANSIBLE_CORE_MIN_VERSION -u ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE \
            ${values[@]+"${values[@]}"} sh -c "${command}" 2>&1)" || rc=$?
        guard_results["${key}"]="${rc} ${output//$'\n'/ }"
    fi
    GUARD_STATUS="${guard_results[${key}]%% *}"
    GUARD_OUTPUT="${guard_results[${key}]#* }"
}

mapfile -t dockerfiles < <(find "${TIER3_DIR}" -maxdepth 1 -type f -name '*.Dockerfile' | sort)
if [[ ${#dockerfiles[@]} -eq 0 ]]; then
    fail "e2e/tier3 holds Dockerfiles to read" "no *.Dockerfile under ${TIER3_DIR}, so nothing below means anything"
    finish "${LABEL}"
fi

base_images=0
for dockerfile in "${dockerfiles[@]}"; do
    rel="${dockerfile#"${REPO_ROOT}/"}"
    arg_lines="$(range_arg_lines "${dockerfile}")"

    defaults="$(grep -vE '^declared ' <<<"${arg_lines}" || true)"
    if [[ -n "${defaults}" ]]; then
        while IFS= read -r entry; do
            fail "${rel} gives the ansible-core range no value of its own" \
                 "line ${entry%% *}: ${entry#* }, while setup/setup.sh is the only place the range is written and container.sh passes it as build arguments"
        done <<<"${defaults}"
    else
        pass "${rel} gives the ansible-core range no value of its own"
    fi

    stated="$(grep -nE -e "${floor_pattern}" -e "${ceiling_pattern}" "${dockerfile}" || true)"
    if [[ -n "${stated}" ]]; then
        while IFS= read -r entry; do
            fail "${rel} does not state the bounds setup/setup.sh declares" \
                 "line ${entry%%:*} states ${floor} or ${ceiling}: ${entry#*:}"
        done <<<"${stated}"
    else
        pass "${rel} does not state ${floor} or ${ceiling}"
    fi

    base="$(awk 'toupper($1) == "FROM" { print $2; exit }' "${dockerfile}")"
    if [[ "${base}" == installationhelper-e2e-* ]]; then
        dim "${rel} builds on ${base}, which checks the range when it is built"
        continue
    fi
    base_images=$((base_images + 1))

    for name in ANSIBLE_CORE_MIN_VERSION ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE; do
        if grep -qxF "declared ${name}" <<<"${arg_lines}"; then
            pass "${rel} declares ARG ${name} with no default"
        else
            fail "${rel} declares ARG ${name} with no default" \
                 "no bare ARG ${name} in a Dockerfile that installs its own ansible-core, so its build cannot check the version against the range"
        fi
    done

    mapfile -t range_runs < <(run_instructions "${dockerfile}" | grep -F 'ANSIBLE_CORE_MIN_VERSION' | grep -F 'ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE' || true)
    if [[ ${#range_runs[@]} -ne 1 ]]; then
        fail "${rel} has one RUN that checks ansible-core against the range" \
             "found ${#range_runs[@]} RUN instructions naming both build arguments"
        continue
    fi
    pass "${rel} has one RUN that checks ansible-core against the range"

    for guard_case in none floor-only; do
        given="no build argument"
        [[ "${guard_case}" == floor-only ]] && given="only ANSIBLE_CORE_MIN_VERSION"
        run_guard "${range_runs[0]}" "${guard_case}"
        if [[ "${GUARD_STATUS}" != 0 && "${GUARD_OUTPUT}" == *"e2e/run.sh --tier 3"* ]]; then
            pass "${rel} refuses a build given ${given} and names e2e/run.sh --tier 3"
        else
            fail "${rel} refuses a build given ${given} and names e2e/run.sh --tier 3" \
                 "the RUN exited ${GUARD_STATUS} with: ${GUARD_OUTPUT}"
        fi
    done

    run_guard "${range_runs[0]}" setup
    if [[ "${GUARD_STATUS}" == 0 ]]; then
        pass "${rel} accepts the gate's ansible-core with the range setup/setup.sh declares"
    else
        fail "${rel} accepts the gate's ansible-core with the range setup/setup.sh declares" \
             "the RUN exited ${GUARD_STATUS} with: ${GUARD_OUTPUT}"
    fi

    run_guard "${range_runs[0]}" above
    if [[ "${GUARD_STATUS}" != 0 && "${GUARD_OUTPUT}" == *"outside the range ${ceiling} <= version < 9999.0.0"* ]]; then
        pass "${rel} still checks the version once both build arguments are given"
    else
        fail "${rel} still checks the version once both build arguments are given" \
             "with the range ${ceiling} <= version < 9999.0.0 the RUN exited ${GUARD_STATUS} with: ${GUARD_OUTPUT}"
    fi
done

if [[ ${base_images} -eq 0 ]]; then
    fail "e2e/tier3 holds a Dockerfile that installs its own ansible-core" "every Dockerfile builds on another one, so no build was checked"
fi

# --- the build sites --------------------------------------------------------------------------------

# "<file>:<line>: <command>" for every logical line, continuation lines joined, that is not a comment.
logical_lines() {
    awk '
        FNR == 1 { pending = "" }
        { sub(/\r$/, "") }
        pending != "" {
            line = $0
            more = sub(/\\$/, "", line)
            pending = pending " " line
            if (!more) { print start ": " pending; pending = "" }
            next
        }
        /^[[:space:]]*#/ { next }
        {
            line = $0
            more = sub(/\\$/, "", line)
            if (more) { pending = line; start = FILENAME ":" FNR; next }
            print FILENAME ":" FNR ": " line
        }' "$@"
}

mapfile -t scanned < <(
    {
        find "${REPO_ROOT}/e2e" -type f -name '*.sh' -not -path "${REPO_ROOT}/e2e/tier1/*" \
            -not -path "${REPO_ROOT}/e2e/runs/*" -not -path "${REPO_ROOT}/e2e/.cache/*"
        if [[ -d "${REPO_ROOT}/.github" ]]; then
            find "${REPO_ROOT}/.github" -type f \( -name '*.yml' -o -name '*.yaml' \)
        fi
    } | sort
)
if [[ ${#scanned[@]} -eq 0 ]]; then
    fail "there are scripts and workflows to read for image builds" "nothing found under e2e/ or .github/"
    finish "${LABEL}"
fi

build_lines="$(logical_lines "${scanned[@]}" | grep -E '(^|[^[:alnum:]_-])docker[[:space:]]+(buildx[[:space:]]+)?build([[:space:]]|$)' || true)"
action_lines="$(logical_lines "${scanned[@]}" | grep -E 'uses:[[:space:]]*docker/build-push-action' || true)"

if [[ -n "${action_lines}" ]]; then
    while IFS= read -r entry; do
        fail "no image is built through docker/build-push-action" \
             "${entry#"${REPO_ROOT}/"}: this check reads only docker build command lines, so teach it this action before a tier 3 image is built with it"
    done <<<"${action_lines}"
fi

sites=0
while IFS= read -r entry; do
    [[ -z "${entry}" ]] && continue
    [[ "${entry}" == *"e2e/gate/Dockerfile"* ]] && continue
    sites=$((sites + 1))
    file="${entry%%:*}"
    where="${entry#"${REPO_ROOT}/"}"
    where="${where%%: *}"
    missing=()
    for name in ANSIBLE_CORE_MIN_VERSION ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE; do
        if ! grep -qE -- "--build-arg[[:space:]=]+\"?${name}=\\$\\{?[A-Za-z_]" <<<"${entry}"; then
            missing+=("${name}")
        fi
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        pass "${where} passes both ansible-core build arguments"
    else
        fail "${where} passes both ansible-core build arguments" \
             "no --build-arg giving ${missing[*]} a variable, so the image it builds refuses to build or carries a number of its own"
    fi
    if grep -qE '(^|[^[:alnum:]_])setup_sh_ansible_core_range([^[:alnum:]_]|$)' "${file}"; then
        pass "${where} builds in a file that reads the range out of setup/setup.sh"
    else
        fail "${where} builds in a file that reads the range out of setup/setup.sh" \
             "${file#"${REPO_ROOT}/"} never calls setup_sh_ansible_core_range, so the build arguments come from somewhere else"
    fi
done <<<"${build_lines}"

if [[ ${sites} -eq 0 ]]; then
    fail "a tier 3 image build was found to read" "no docker build under e2e/ or .github/ other than the gate image's, so nothing above means anything"
fi

finish "${LABEL}"
