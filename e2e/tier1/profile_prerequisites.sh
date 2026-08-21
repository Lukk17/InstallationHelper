#!/usr/bin/env bash
#
# Tier 1: a profile may not enable a tool while disabling the only thing that can install it.
#
# profiles/linux_live.yaml turns install_nodejs off, which is right for a live USB session, and it
# turns off five of the six tools whose only Linux install path is npm through NVM. It missed
# install_bruno_cli, which group_vars/all.yaml has on. Every single live-profile run therefore
# failed, on all six distributions, with the npm helper reporting that NVM was absent and Bruno CLI
# was not installed. Found by the first GitHub sweep, where live-profile was the only scenario that
# failed everywhere including the two images that pass everything else, which is the signature of a
# fault in the scenario rather than in any image.
#
# The tool list is derived rather than written down, because the interesting failure is the seventh
# npm tool somebody adds next year. The chain is followed the way Ansible follows it: find whatever
# includes npm_install_unix.yaml, and if the including task carries no install_ toggle of its own,
# go up one level to the file that includes it and take the toggle from there.
#
# The check is not npm-specific in shape, only in what it currently finds. install_nodejs is the
# prerequisite because it is the toggle that decides whether sdk_manager installs NVM at all.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "${REPO_ROOT}/setup/pinned_values/pinned_values.sh"

AI_TASKS="${ANSIBLE_DIR}/roles/ai_tools/tasks"
PROFILES_DIR="${ANSIBLE_DIR}/profiles"

info "Tier 1: profile prerequisites"

[[ -d "${AI_TASKS}" ]]    || { fail "the ai_tools task directory is missing" "${AI_TASKS}"; finish "profile prerequisites"; }
[[ -d "${PROFILES_DIR}" ]] || { fail "the profiles directory is missing" "${PROFILES_DIR}"; finish "profile prerequisites"; }

# The same interpreter search the pinned values adapter uses, for the same reason manifests.sh gives:
# Git Bash has no python3 and the Windows App Execution Alias resolves without running.
if ! PYTHON="$(pinned_values_python)"; then
    skip "profiles do not enable a tool whose prerequisite they disable"          "no Python 3.11 or newer on PATH, so the task graph cannot be walked"
    finish "profile prerequisites"
fi

# The toggles whose only install path on Linux runs through npm, derived from the task graph.
#
npm_toggles="$(
"${PYTHON}" - "${AI_TASKS}" <<'PY'
import pathlib
import re
import sys

# Written with an explicit newline, because this interpreter may be a Windows Python, where
# print() turns every newline into a carriage return plus a newline. The shell reading this
# output then builds a grep pattern with a carriage return inside it, that pattern matches
# nothing, and the whole check reports a clean tree with the defect in front of it. That is
# not hypothetical: the first version of this file did exactly that and passed against the
# known-bad tree it was written to catch.
sys.stdout.reconfigure(newline=chr(10))

tasks = pathlib.Path(sys.argv[1])
HELPER = "npm_install_unix.yaml"

# One task block is everything from a "- name:" line up to the next one. That is enough structure
# for this: the include and the when that guards it always live in the same block.
def blocks(path):
    current = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if re.match(r"^\s*-\s+name:", line) and current:
            yield "\n".join(current)
            current = [line]
        else:
            current.append(line)
    if current:
        yield "\n".join(current)


def includers(target):
    """Files with a block that includes or imports `target`, paired with that block."""
    found = []
    for path in sorted(tasks.glob("*.yaml")):
        for block in blocks(path):
            if re.search(r"(include|import)_tasks:\s*" + re.escape(target) + r"\s*$", block, re.M):
                found.append((path.name, block))
    return found


def toggles_in(block):
    return set(re.findall(r"\b(install_[a-z0-9_]+)\b", block))


result = set()
for name, block in includers(HELPER):
    direct = toggles_in(block)
    if direct:
        result |= direct
        continue
    # The leaf carries no toggle of its own, so whoever includes the leaf decides.
    for _, parent_block in includers(name):
        result |= toggles_in(parent_block)

print("\n".join(sorted(result)))
PY
)"

n_toggles="$(grep -c . <<<"${npm_toggles}" || true)"
if [[ "${n_toggles}" -ge 5 ]]; then
    pass "derived ${n_toggles} toggles whose only Linux install path is npm: $(tr '\n' ' ' <<<"${npm_toggles}")"
else
    fail "the npm toggle derivation found ${n_toggles} toggles, which is too few to be a real answer" \
         "expected at least five, walk of ${AI_TASKS} produced: $(tr '\n' ' ' <<<"${npm_toggles}")"
fi

# The value a toggle really has for a given profile: the profile wins, then linux.yaml, then
# all.yaml. Read with grep rather than a YAML parser on purpose, so this check needs nothing
# installed, the same reasoning the rest of tier 1 follows.
toggle_value() {
    local toggle="$1" profile="$2" value=""
    local file
    for file in "${profile}" "${ANSIBLE_DIR}/group_vars/linux.yaml" "${ANSIBLE_DIR}/group_vars/all.yaml"; do
        [[ -f "${file}" ]] || continue
        value="$(grep -E "^${toggle}:[[:space:]]*(true|false)[[:space:]]*(#.*)?$" "${file}" 2>/dev/null \
            | tail -1 | sed -E 's/^[^:]+:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//')"
        [[ -n "${value}" ]] && { echo "${value}"; return 0; }
    done
    echo "unset"
}

shopt -s nullglob
profiles=("${PROFILES_DIR}"/*.yaml)
shopt -u nullglob

if [[ ${#profiles[@]} -eq 0 ]]; then
    fail "no profile files found, so this check proves nothing" "${PROFILES_DIR}"
    finish "profile prerequisites"
fi

for profile in "${profiles[@]}"; do
    profile_name="$(basename "${profile}")"
    nodejs="$(toggle_value install_nodejs "${profile}")"

    if [[ "${nodejs}" != false ]]; then
        pass "${profile_name} leaves install_nodejs at ${nodejs}, so the npm tools have their prerequisite"
        continue
    fi

    orphans=()
    while IFS= read -r toggle; do
        [[ -z "${toggle}" ]] && continue
        [[ "${toggle}" == install_nodejs ]] && continue
        [[ "$(toggle_value "${toggle}" "${profile}")" == true ]] && orphans+=("${toggle}")
    done <<<"${npm_toggles}"

    if [[ ${#orphans[@]} -eq 0 ]]; then
        pass "${profile_name} turns install_nodejs off and every npm-only tool with it"
    else
        fail "${profile_name} turns install_nodejs off while leaving npm-only tools on, so every run of it fails" \
             "${orphans[*]} would reach the npm helper with no NVM to use. Set them false in ${profile_name}."
    fi
done

finish "profile prerequisites"
