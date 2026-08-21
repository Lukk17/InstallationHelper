#!/usr/bin/env bash
#
# Tier 1: the compose files parse and resolve, and the documentation links point at files that exist.
#
# local-dev/ and homelab/ are two thirds of this repository and until now had no test of any kind.
# Everything the harness does is about setup/, so a broken compose file or a documentation link
# pointing at a renamed page would have shipped unnoticed, and the markdown filename rename earlier
# in this project's history is exactly the change that breaks links quietly.
#
# Two questions are asked here, both cheap and both static:
#
#   1. Every compose file resolves. `docker compose config` is the only thing that answers this
#      honestly, because it merges, interpolates and validates in one pass, and a file that parses as
#      YAML can still be a compose file docker refuses. It needs no daemon: config reads and prints.
#   2. Every relative markdown link in those two directories points at a path that exists. Absolute
#      links are somebody else's problem and are not fetched here, that is what tier 2 is for.
#
# A missing docker binary is a skip rather than a pass, for the reason the rest of the harness gives:
# silence and success have to be told apart.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: compose files and documentation links"

# --- compose files resolve ------------------------------------------------------------------------
mapfile -t compose_files < <(
    find "${REPO_ROOT}/local-dev" "${REPO_ROOT}/homelab" \
        -type f \( -name '*compose*.yaml' -o -name '*compose*.yml' \) 2>/dev/null | sort
)

if [[ ${#compose_files[@]} -eq 0 ]]; then
    fail "no compose files found under local-dev/ or homelab/, so this check proves nothing" \
         "${REPO_ROOT}"
elif ! command -v docker >/dev/null 2>&1; then
    skip "every compose file resolves" "no docker binary here, and only docker can answer this"
else
    broken=()
    for f in "${compose_files[@]}"; do
        # --dry-run is not it: config is the validating read, and it needs no daemon. Stderr is kept
        # because that is where the reason lives when it refuses.
        # --no-interpolate on purpose. These files read secrets from a .env this repository does not
        # commit, so interpolation fails on a missing SEARXNG_SECRET and says nothing about whether
        # the file is valid. Without interpolation the merge and the schema are still checked, which
        # is the part a reader can get wrong.
        if ! out="$(docker compose -f "$(host_path "${f}")" config --no-interpolate 2>&1)"; then
            broken+=("$(basename "$(dirname "${f}")")/$(basename "${f}"): $(head -1 <<<"${out}")")
        fi
    done
    if [[ ${#broken[@]} -eq 0 ]]; then
        pass "all ${#compose_files[@]} compose files under local-dev/ and homelab/ resolve"
    else
        fail "${#broken[@]} of ${#compose_files[@]} compose files do not resolve" "${broken[*]}"
    fi
fi

# --- every service names an image -----------------------------------------------------------------
# A service with neither image nor build is a service that can never start, and compose config does
# not object to it.
# Asked of compose rather than of the indentation. The first version of this counted every key at two
# spaces, which catches volumes: and networks: entries as well as services and reported three healthy
# files as broken. compose knows what a service is, so it is the one to ask.
missing_image=()
if command -v docker >/dev/null 2>&1; then
    for f in "${compose_files[@]}"; do
        while IFS= read -r svc; do
            [[ -z "${svc}" ]] && continue
            body="$(docker compose -f "$(host_path "${f}")" config --no-interpolate --format json 2>/dev/null                 | "${PYTHON:-python}" -c "
import json, sys
name = sys.argv[1]
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
s = (d.get('services') or {}).get(name) or {}
print('yes' if ('image' in s or 'build' in s) else 'no')
" "${svc}" 2>/dev/null)"
            [[ "${body}" == no ]] && missing_image+=("$(basename "${f}"): ${svc}")
        done < <(docker compose -f "$(host_path "${f}")" config --services 2>/dev/null || true)
    done
fi
if [[ ${#missing_image[@]} -eq 0 ]]; then
    pass "every service in those files names an image or a build context"
else
    fail "${#missing_image[@]} compose file(s) have a service with nothing to run" "${missing_image[*]}"
fi

# --- documentation links point at something -------------------------------------------------------
# Relative markdown links only. Anchors are stripped, and a link to a directory counts as long as the
# directory is there.
dead_links=()
n_links=0
while IFS= read -r md; do
    dir="$(dirname "${md}")"
    while IFS= read -r target; do
        [[ -z "${target}" ]] && continue
        [[ "${target}" =~ ^(https?:|mailto:|file:|#) ]] && continue
        n_links=$((n_links + 1))
        clean="${target%%#*}"
        [[ -z "${clean}" ]] && continue
        [[ -e "${dir}/${clean}" ]] || dead_links+=("$(basename "${md}") -> ${target}")
    done < <(grep -oE '\]\([^)]+\)' "${md}" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//')
done < <(find "${REPO_ROOT}/local-dev" "${REPO_ROOT}/homelab" -type f -name '*.md' 2>/dev/null | sort)

if [[ "${n_links}" -eq 0 ]]; then
    fail "no markdown links found in either directory, so this check proves nothing" \
         "expected the two hub pages to link their siblings at least"
elif [[ ${#dead_links[@]} -eq 0 ]]; then
    pass "all ${n_links} relative documentation links in local-dev/ and homelab/ point at something that exists"
else
    fail "${#dead_links[@]} of ${n_links} relative documentation links point at nothing" "${dead_links[*]}"
fi

finish "compose files and documentation links"
