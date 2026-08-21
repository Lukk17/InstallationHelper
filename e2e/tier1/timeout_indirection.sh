#!/usr/bin/env bash
#
# Tier 1: no task may call the bare timeout command, because macOS does not have one.
#
# timeout is GNU coreutils and the BSD userland does not ship it, so every task that bounded itself
# with `timeout N ...` failed on macOS with "/bin/bash: line 1: timeout: command not found". The
# macOS defaults scenario died at the first of them, in sdk_manager, which took Node, pyenv, SDKMAN,
# FVM, the Android SDK, the npm tools and JetBrains Toolbox with it. Twenty-seven call sites across
# fourteen files, and none of them was wrong on Linux, which is why it survived until the first stage
# 3 run this repository ever did, on 2026-08-21.
#
# The command is now a fact, ih_timeout, resolved once in tasks/derive_os_facts.yaml, and macos_core
# installs coreutils so gtimeout exists before anything needs it. This check exists because the fix
# is a convention rather than a mechanism: nothing stops the twenty-eighth call site from being
# written the old way, and it would work perfectly on every Linux run and fail on every Mac.
#
# Comments are excluded on purpose. This file's own prose says "timeout" repeatedly and so does the
# reasoning next to several of the tasks, and a check that cannot survive being explained is not
# worth having.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: the timeout command goes through one fact"

ROLES_DIR="${ANSIBLE_DIR}/roles"
TASKS_DIR="${ANSIBLE_DIR}/tasks"

[[ -d "${ROLES_DIR}" ]] || { fail "the roles directory is missing" "${ROLES_DIR}"; finish "timeout indirection"; }

# --- the fact exists at all -----------------------------------------------------------------------
if grep -rqE '^\s*ih_timeout:' "${TASKS_DIR}"/*.yaml 2>/dev/null; then
    pass "ih_timeout is set as a fact before any role runs"
else
    fail "nothing sets ih_timeout, so every task referring to it renders empty" \
         "expected a set_fact in ${TASKS_DIR}, which site.yaml imports in its pre_tasks"
fi

# --- and resolves to something different per platform ---------------------------------------------
if grep -rqE 'gtimeout' "${TASKS_DIR}"/*.yaml 2>/dev/null; then
    pass "the fact names the macOS command, gtimeout, as well as the Linux one"
else
    fail "ih_timeout never mentions gtimeout, so macOS gets a command it does not have" \
         "macOS has no timeout. Homebrew's coreutils installs it as gtimeout."
fi

# --- macOS is given the package that provides it --------------------------------------------------
if grep -rqE '^\s*name:\s*coreutils\s*$' "${ROLES_DIR}/macos_core/tasks/" 2>/dev/null; then
    pass "macos_core installs coreutils, which is where gtimeout comes from"
else
    fail "macos_core does not install coreutils, so gtimeout will not exist when the fact names it" \
         "${ROLES_DIR}/macos_core/tasks/"
fi

# --- nobody calls the bare command ----------------------------------------------------------------
# Only lines that are not comments, and only a call at a command position: the word followed by its
# duration. `timeout: 60` is a module parameter and has nothing to do with this.
offenders="$(
    grep -rnE '(^|[^[:alnum:]_}])timeout [0-9]+' "${ROLES_DIR}"/*/tasks/*.yaml "${TASKS_DIR}"/*.yaml 2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+:\s*#' \
        | grep -vE '\{\{ ih_timeout \}\}' \
        || true
)"

n_offenders="$(grep -c . <<<"${offenders}" || true)"
if [[ "${n_offenders}" -eq 0 ]]; then
    n_indirect="$(grep -rcE '\{\{ ih_timeout \}\} [0-9]+' "${ROLES_DIR}"/*/tasks/*.yaml 2>/dev/null | awk -F: '{ total += $2 } END { print total + 0 }')"
    if [[ "${n_indirect}" -ge 20 ]]; then
        pass "all ${n_indirect} bounded commands go through ih_timeout, and none calls timeout directly"
    else
        fail "only ${n_indirect} call sites go through ih_timeout, which is too few to be the whole set" \
             "there were 27 when this check was written. Either they moved or the indirection was undone."
    fi
else
    fail "${n_offenders} task line(s) call the bare timeout command, which does not exist on macOS" \
         "$(tr '\n' ' ' <<<"${offenders}")"
fi

finish "timeout indirection"
