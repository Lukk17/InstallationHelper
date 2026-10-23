#!/usr/bin/env bash
#
# The apt repository lines the playbook would write, per os-release fixture, for tier 1 and tier 2.
# Sourced after common.sh, never executed directly.
#
# The facts come from the shipped setup/ansible/tasks/derive_os_facts.yaml, driven by
# e2e/tier1/apt_vendor_repositories.yaml, and the lines from the shipped task files, rendered by
# e2e/lib/render_apt_repositories.py. e2e/tier1/apt_vendor_repositories.sh asserts what the lines
# say and e2e/tier2/resolve_apt_repositories.sh asks the vendors whether they answer, and both read
# them from here so the two cannot render differently.

APT_REPOSITORIES_PLAY="${E2E_ROOT}/tier1/apt_vendor_repositories.yaml"

# Filled in by apt_repositories_render.
APT_CASES=""
APT_LINES=""
# shellcheck disable=SC2034  # read by the checks that source this file
APT_RENDER_FAULT=""

# apt_repositories_render  ->  returns 0 and sets APT_CASES and APT_LINES, or returns 1 and sets
# APT_RENDER_FAULT
#
# APT_CASES holds one JSON object per case, the case from the play with ih_family, ih_base and
# ih_apt_codename added. APT_LINES holds the tab-separated lines render_apt_repositories.py prints.
# shellcheck disable=SC2034  # APT_RENDER_FAULT is read by the checks that source this file
apt_repositories_render() {
    local play_out expected work status=0
    APT_CASES=""
    APT_LINES=""
    APT_RENDER_FAULT=""

    PYTHON="${PYTHON:-}"
    if [[ -z "${PYTHON}" ]]; then
        PYTHON="$(find_runnable_python)" || { APT_RENDER_FAULT="no Python 3.11 or newer on PATH to render the lines with"; return 1; }
    fi

    # dual_logger is this repository's stdout callback and writes ~/installation_*.log on every play,
    # so the default callback is used, as in os_family_derivation.sh.
    play_out="$(
        ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_FORCE_COLOR=0 \
            ansible-playbook -i localhost, "${APT_REPOSITORIES_PLAY}" \
            -e "{\"ih_derivation\": \"${ANSIBLE_DIR}/tasks/derive_os_facts.yaml\", \"ih_fixtures\": \"${E2E_ROOT}/tier1/os_release_fixtures\"}" 2>&1 || true
    )"
    expected="$(grep -cE '^[[:space:]]*- \{ fixture:' "${APT_REPOSITORIES_PLAY}" || true)"
    if ! grep -q "IH_APT_DONE cases=${expected}\b" <<<"${play_out}"; then
        APT_RENDER_FAULT="the derivation play did not finish: $(grep -E 'fatal:|FAILED!|failed=[1-9]|ERROR' <<<"${play_out}" | sed -n 1,4p | tr '\n' ' ')"
        return 1
    fi
    APT_CASES="$(grep -oE 'IH_APT_FACTS \{.*\}' <<<"${play_out}" | sed -E 's/^IH_APT_FACTS //; s/\\"/"/g' || true)"
    if [[ "$(grep -c . <<<"${APT_CASES}")" -ne "${expected}" ]]; then
        APT_RENDER_FAULT="the play asserted ${expected} cases and reported facts for $(grep -c . <<<"${APT_CASES}")"
        return 1
    fi

    work="$(mktemp)"
    printf '%s\n' "${APT_CASES}" >"${work}"
    APT_LINES="$("${PYTHON}" -I "${E2E_ROOT}/lib/render_apt_repositories.py" "${REPO_ROOT}" "${work}")" || status=$?
    rm -f "${work}"
    if [[ ${status} -ne 0 || -z "${APT_LINES}" ]]; then
        APT_RENDER_FAULT="render_apt_repositories.py exited ${status} and rendered $(grep -c . <<<"${APT_LINES}" || true) lines, its own error is above"
        return 1
    fi
}

# apt_case_field <json> <field>  ->  the field's string value
apt_case_field() {
    sed -nE "s/.*\"$2\": *\"([^\"]*)\".*/\1/p" <<<"$1"
}
