#!/usr/bin/env bash
#
# Tier 1: the forced-failure scenario's own assertions say what they mean, and its paru injection
# fails at one known step every time.
#
# GitHub sweep run 38107292439 failed forced-failure on Arch, CachyOS and Fedora on 2026-10-11, and in
# all three the rescue being tested had worked. Two assertions in e2e/tier3/container.sh were wrong:
#
#   Fedora   it matched the literal "could not be added: lens." while the software installer printed
#            "could not be added: lens, tailscale.", because a real repository had failed as well.
#            Lens has to be one entry of that list, which is what log_list_names answers.
#   Arch     it named "Clone paru AUR helper repository", and the injection pointed paru at an empty
#            Arch User Repository name, so which step failed was the server's choice: the clone on
#            2026-10-10, the build on 2026-10-11. The injection is now a host under .invalid, which
#            never resolves, so the clone is the step that fails, every time.
#
# Tier 3 cannot run in this gate, so both are checked here: log_list_names is lifted out of the
# shipped container.sh, the same way shell_units.sh lifts functions out of setup.sh, and driven over
# lines copied from that run's artefacts. The rest is read from the files the scenario depends on.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

CONTAINER_SH="${REPO_ROOT}/e2e/tier3/container.sh"
SCENARIO="${REPO_ROOT}/e2e/tier3/scenarios/07-forced-failure.yaml"
DYNAMIC_INSTALL="${ANSIBLE_DIR}/roles/software_installer/tasks/dynamic_install.yaml"
ARCH_CORE_TASKS="${ANSIBLE_DIR}/roles/arch_core/tasks/main.yaml"
PARU_CLONE_TASK="Clone paru AUR helper repository"

info "Tier 1: the forced-failure assertions match what the playbook prints, and the paru injection is deterministic"

for required in "${CONTAINER_SH}" "${SCENARIO}" "${DYNAMIC_INSTALL}" "${ARCH_CORE_TASKS}"; do
    if [[ ! -f "${required}" ]]; then
        fail "a file this check reads is missing, so none of it proves anything" "${required}"
        finish "forced failure assertions"
    fi
done

# --- the skipped-repository list ----------------------------------------------
prefix_text="$(sed -n '/^REPOSITORY_SKIP_LIST_PREFIX=/{p;q;}' "${CONTAINER_SH}")"
function_text="$(sed -n '/^log_list_names()/,/^}/p' "${CONTAINER_SH}")"
if [[ -z "${prefix_text}" || -z "${function_text}" ]]; then
    fail "container.sh still defines REPOSITORY_SKIP_LIST_PREFIX and log_list_names" \
         "the extraction found nothing, so the Lens assertion of forced-failure cannot be tested here"
    finish "forced failure assertions"
fi
eval "${prefix_text}"
eval "${function_text}"

if [[ -n "${REPOSITORY_SKIP_LIST_PREFIX}" ]] && grep -qF -- "${REPOSITORY_SKIP_LIST_PREFIX}" "${DYNAMIC_INSTALL}"; then
    pass "the list prefix the harness parses is printed word for word by the software installer"
else
    fail "the software installer no longer prints the prefix the harness parses" \
         "expected '${REPOSITORY_SKIP_LIST_PREFIX}' in ${DYNAMIC_INSTALL}, so the Lens assertion would fail on every run"
fi

if grep -qF 'log_list_names "${REPOSITORY_SKIP_LIST_PREFIX}" lens "${PLAYBOOK_LOG}"' "${CONTAINER_SH}" \
    && ! grep -qF 'could not be added: lens.' "${CONTAINER_SH}"; then
    pass "the Lens assertion asks whether lens is one entry of the skipped list, not for one whole sentence"
else
    fail "the Lens assertion in container.sh does not go through log_list_names" \
         "a literal match on the sentence fails as soon as a second repository fails on the same run, as tailscale did on Fedora in run 38107292439"
fi

# Lines from run 38107292439's artefacts, verbatim, and the cases a substring match would get wrong.
FEDORA_TWO='  [ERROR] 2 package(s) were NOT installed because the repository they come from could not be added: lens, tailscale. The repository step that failed is named above. Every other package still installs.'
DEBIAN_ONE='  [ERROR] 1 package(s) were NOT installed because the repository they come from could not be added: lens. The repository step that failed is named above. Every other package still installs.'
FEDORA_NO_LENS='  [ERROR] 1 package(s) were NOT installed because the repository they come from could not be added: tailscale. The repository step that failed is named above. Every other package still installs.'
LENS_LAST='  [ERROR] 2 package(s) were NOT installed because the repository they come from could not be added: tailscale, lens.'
LENS_PREFIXED='  [ERROR] 2 package(s) were NOT installed because the repository they come from could not be added: lenses, tailscale. The repository step that failed is named above.'
LENS_AFTER_LIST='  [ERROR] 1 package(s) were NOT installed because the repository they come from could not be added: tailscale. The lens step is named above.'
DOTTED_NAME='  [ERROR] 2 package(s) were NOT installed because the repository they come from could not be added: dotnet-sdk-8.0, lens. The repository step that failed is named above.'

list_case() {
    local label="$1" expected="$2" text="$3"
    local got=no
    if log_list_names "${REPOSITORY_SKIP_LIST_PREFIX}" lens <(printf '%s\n' "${text}"); then
        got=yes
    fi
    if [[ "${got}" == "${expected}" ]]; then
        pass "log_list_names: ${label}"
    else
        fail "log_list_names: ${label}" "expected '${expected}' for lens, got '${got}' from: ${text}"
    fi
}

list_case "lens is found in the Fedora list 'lens, tailscale' from run 38107292439" yes "${FEDORA_TWO}"
list_case "lens is found in the Debian list 'lens' from run 38107292439" yes "${DEBIAN_ONE}"
list_case "lens is not found in the Fedora list 'tailscale' from run 38107292439" no "${FEDORA_NO_LENS}"
list_case "lens is found as the last entry, where the line ends at its full stop" yes "${LENS_LAST}"
list_case "lens is found after an entry whose name holds a dot" yes "${DOTTED_NAME}"
list_case "lenses does not count as lens" no "${LENS_PREFIXED}"
list_case "lens in the sentence after the list does not count" no "${LENS_AFTER_LIST}"
list_case "a log with no skipped list does not name lens" no ""

# --- the paru injection --------------------------------------------------------
paru_repository="$(sed -nE 's/^arch_core_paru_repository:[[:space:]]*"?([^"[:space:]]+)"?[[:space:]]*$/\1/p' "${SCENARIO}")"
paru_host="${paru_repository#*://}"
paru_host="${paru_host%%/*}"
paru_host="${paru_host##*@}"
paru_host="${paru_host%%:*}"
if [[ -n "${paru_repository}" && "${paru_host}" == *.invalid ]]; then
    pass "forced-failure points paru at ${paru_repository}, a host under .invalid, which never resolves"
else
    fail "forced-failure does not point paru at a host under .invalid" \
         "got '${paru_repository:-nothing}' from ${SCENARIO}. Any host that can answer lets the server decide which paru step fails, which is what failed Arch and CachyOS in run 38107292439"
fi

if grep -qF -- "- name: ${PARU_CLONE_TASK}" "${ARCH_CORE_TASKS}" \
    && grep -qF 'repo: "{{ arch_core_paru_repository }}"' <<<"$(sed -n "/- name: ${PARU_CLONE_TASK}\$/,/^ *- name: /p" "${ARCH_CORE_TASKS}")"; then
    pass "arch_core still has a task named '${PARU_CLONE_TASK}' and it clones arch_core_paru_repository"
else
    fail "arch_core has no task named '${PARU_CLONE_TASK}' that clones arch_core_paru_repository" \
         "the injection only fails that step if that task reads the variable, see ${ARCH_CORE_TASKS}"
fi

if grep -qF "grep -qF \"${PARU_CLONE_TASK}\" \"\${ERRORS_LOG}\"" "${CONTAINER_SH}"; then
    pass "the paru assertion in container.sh names the clone step, the one the injection makes fail"
else
    fail "the paru assertion in container.sh does not name '${PARU_CLONE_TASK}'" \
         "the injection is deterministic so that the assertion can name the exact step, see ${CONTAINER_SH}"
fi

finish "forced failure assertions"
