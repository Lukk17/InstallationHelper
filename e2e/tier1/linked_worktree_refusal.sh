#!/usr/bin/env bash
#
# Tier 1: every entry point into the gate refuses to start from a linked git worktree.
#
# A worktree made with `git worktree add` has a .git that is a file. gate_refuse_linked_worktree in
# e2e/lib/gate.sh refuses such a tree, and gate_lend_github_token and gate_enter ask it first.
#
# The entry scripts are copied into a scratch tree whose .git is a file and started for real, every
# route through e2e/run.sh and e2e/tier3/container.sh, with the gate switch removed so they act as they
# do on the machine that starts them, and with a fake docker and a fake gh that record every call. Each
# route must exit 2 with the refusal and call neither. The same tree with .git as a folder must pass the
# refusal and stop at the next guard, the refusal of a foreign container. `run.sh --help` from the
# worktree must still print the usage and exit 0.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

CHECK_NAME="linked worktree refusal"
REFUSAL_LINE="REFUSED: the gate cannot run from a git worktree"
NEXT_GUARD_LINE="REFUSED: this is a container, but not the gate container"
ROUTE_SECONDS=30

info "Tier 1: every entry point into the gate refuses a linked git worktree"

ENTRY_FILES=(e2e/run.sh e2e/tier3/container.sh e2e/lib/gate.sh e2e/lib/host.sh e2e/lib/throwaway_machine.sh e2e/lib/common.sh)
for relative in "${ENTRY_FILES[@]}"; do
    if [[ ! -f "${REPO_ROOT}/${relative}" ]]; then
        fail "a file of the gate's entry points is missing, so nothing below can start" "${REPO_ROOT}/${relative}"
        finish "${CHECK_NAME}"
    fi
done

work_dir="$(mktemp -d)"
trap 'rm -rf -- "${work_dir}"' EXIT
fake_bin="${work_dir}/bin"
calls_file="${work_dir}/calls"
mkdir -p "${fake_bin}"
for fake in docker gh; do
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >>"%s"\nexit 1\n' "${fake}" "${calls_file}" >"${fake_bin}/${fake}"
    chmod +x "${fake_bin}/${fake}"
done

# build_tree <name> <file|folder>  ->  prints the root of a scratch tree holding the entry scripts
build_tree() {
    local root="${work_dir}/$1" relative
    for relative in "${ENTRY_FILES[@]}"; do
        mkdir -p "$(dirname "${root}/${relative}")"
        cp "${REPO_ROOT}/${relative}" "${root}/${relative}"
    done
    if [[ "$2" == file ]]; then
        printf 'gitdir: %s/.git/worktrees/scratch\n' "${work_dir}" >"${root}/.git"
    else
        mkdir -p "${root}/.git"
    fi
    printf '%s\n' "${root}"
}

# as_host <command>...  ->  runs the command the way the machine that starts the gate would, with the
# gate switch, any GitHub token and any preloaded gate image removed, and the fakes first on PATH
as_host() {
    env -u E2E_INSIDE_GATE_CONTAINER -u GH_TOKEN -u GITHUB_TOKEN -u E2E_GATE_IMAGE_PRELOADED \
        -u GATE_REQUIRES_THROWAWAY PATH="${fake_bin}:${PATH}" NO_COLOR=1 "$@"
}

worktree_root="$(build_tree worktree file)"
clone_root="$(build_tree clone folder)"

for fake in docker gh; do
    resolved="$(as_host bash -c "command -v ${fake}")"
    if [[ "${resolved}" != "${fake_bin}/${fake}" ]]; then
        fail "the fake ${fake} resolves first, so no route below can reach the real one" \
             "${fake} resolved to [${resolved}], so nothing was run"
        finish "${CHECK_NAME}"
    fi
done
: >"${calls_file}"
as_host docker version >/dev/null 2>&1 || true
as_host gh auth token >/dev/null 2>&1 || true
if [[ "$(cat "${calls_file}")" != $'docker version\ngh auth token' ]]; then
    fail "the fake docker and the fake gh record their calls" "they recorded [$(tr '\n' ' ' <"${calls_file}")]"
    finish "${CHECK_NAME}"
fi
pass "the fake docker and the fake gh are the ones that resolve, and they record every call"

if [[ ! -f "${worktree_root}/.git" || ! -d "${clone_root}/.git" ]]; then
    fail "the scratch trees have a .git file and a .git folder" "${worktree_root}/.git, ${clone_root}/.git"
    finish "${CHECK_NAME}"
fi

# route label | arguments, read relative to the scratch tree's root
ROUTES=(
    "run.sh, tier 1|e2e/run.sh"
    "run.sh --tier 2, which lends a GitHub token first|e2e/run.sh --tier 2"
    "run.sh --queue --tier 2|e2e/run.sh --queue --tier 2"
    "run.sh --tier 3|e2e/run.sh --tier 3 --scenario defaults"
    "container.sh <scenario>|e2e/tier3/container.sh e2e/tier3/scenarios/01-defaults.yaml --os debian"
    "container.sh <scenario> --detach|e2e/tier3/container.sh e2e/tier3/scenarios/01-defaults.yaml --detach"
    "container.sh --collect|e2e/tier3/container.sh --collect e2e/runs/no-such-run"
)

# start_route <tree root> <arguments>  ->  sets route_rc and route_out, and empties the call record first
start_route() {
    local root="$1" route_args
    read -r -a route_args <<<"$2"
    : >"${calls_file}"
    route_rc=0
    route_out="$(cd "${root}" && as_host timeout --kill-after=5 "${ROUTE_SECONDS}" bash "${route_args[@]}" 2>&1)" || route_rc=$?
}

for route in "${ROUTES[@]}"; do
    route_name="${route%%|*}"
    start_route "${worktree_root}" "${route#*|}"
    problems=()
    [[ ${route_rc} -eq 2 ]] || problems+=("exit ${route_rc}, not 2")
    grep -qF "${REFUSAL_LINE}, and ${worktree_root} is one: its .git is a file, not a folder." <<<"${route_out}" \
        || problems+=("no refusal naming ${worktree_root}")
    grep -qxF "Nothing was run. Run it from the main checkout, or from a full clone made with git clone, instead:" <<<"${route_out}" \
        || problems+=("the refusal does not say nothing was run and where to run it instead")
    [[ -s "${calls_file}" ]] && problems+=("called: $(tr '\n' ' ' <"${calls_file}")")
    if [[ ${#problems[@]} -eq 0 ]]; then
        pass "${route_name}, from a worktree, exits 2 with the refusal and calls neither docker nor gh"
    else
        fail "${route_name}, from a worktree, is not refused before anything runs" \
             "$(printf '%s; ' "${problems[@]}") output: $(sed -n 1,3p <<<"${route_out}" | tr '\n' ' ')"
    fi

    start_route "${clone_root}" "${route#*|}"
    problems=()
    grep -qF "${REFUSAL_LINE}" <<<"${route_out}" && problems+=("refused as a worktree")
    [[ ${route_rc} -eq 2 ]] || problems+=("exit ${route_rc}, not 2")
    grep -qF "${NEXT_GUARD_LINE}" <<<"${route_out}" || problems+=("never reached the foreign container refusal")
    if [[ ${#problems[@]} -eq 0 ]]; then
        pass "${route_name}, from a tree whose .git is a folder, passes the refusal and stops at the next guard"
    else
        fail "${route_name}, from a tree whose .git is a folder, does not pass the worktree refusal" \
             "$(printf '%s; ' "${problems[@]}") output: $(sed -n 1,3p <<<"${route_out}" | tr '\n' ' ')"
    fi
done

start_route "${worktree_root}" "e2e/run.sh --help"
if [[ ${route_rc} -eq 0 ]] && grep -qF "run.sh --tier 2 --only <check>" <<<"${route_out}" \
        && ! grep -qF "REFUSED" <<<"${route_out}" && [[ ! -s "${calls_file}" ]]; then
    pass "run.sh --help, from a worktree, prints the usage and exits 0"
else
    fail "run.sh --help, from a worktree, prints the usage and exits 0" \
         "exit ${route_rc}, calls [$(tr '\n' ' ' <"${calls_file}")], output: $(sed -n 1,3p <<<"${route_out}" | tr '\n' ' ')"
fi

finish "${CHECK_NAME}"
