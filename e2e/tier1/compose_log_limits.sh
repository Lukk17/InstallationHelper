#!/usr/bin/env bash
#
# Tier 1: every service in the homelab compose files caps its container log.
#
# Docker's json-file driver keeps a container's whole log unless the service sets max-size. On
# 2026-10-23 the uptime-kuma container's log on the homelab Docker VM held 24.7 GB of its root disk
# and grew about 2.3 GB a day, because homelab/compose.yaml set no logging block and the VM has no
# daemon.json default, docs/regression_ledger.md 10.177. This reads every compose file under homelab/
# and fails on any service whose logging options carry no max-size.
#
# The reader is first run against a planted file and must name exactly the one service without a
# cap, so a reader that finds nothing cannot pass for files that hold nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: every homelab container caps its log"

require_python "every homelab container caps its log" "compose log limits"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

# uncapped <compose file>...  ->  prints "<file>: <service>" for each service without a max-size
uncapped() {
    "${PYTHON}" -I - "$@" <<'PYEOF'
import sys

import yaml

for path in sys.argv[1:]:
    with open(path, encoding='utf-8') as handle:
        document = yaml.safe_load(handle) or {}
    for name, service in sorted((document.get('services') or {}).items()):
        options = ((service or {}).get('logging') or {}).get('options') or {}
        if not str(options.get('max-size', '')).strip():
            print('%s: %s' % (path, name))
PYEOF
}

planted="${work}/compose.yaml"
cat >"${planted}" <<'EOF'
x-logging: &default-logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

services:
  capped:
    image: example/capped:1
    logging: *default-logging
  capped-inline:
    image: example/inline:1
    logging:
      options:
        max-size: "5m"
  only-max-file:
    image: example/only-max-file:1
    logging:
      driver: json-file
      options:
        max-file: "3"
EOF

status=0
planted_output="$(uncapped "${planted}" 2>&1)" || status=$?
if [[ ${status} -eq 0 && "${planted_output}" == "${planted}: only-max-file" ]]; then
    pass "the reader names exactly the one planted service without a max-size"
else
    fail "the reader names exactly the one planted service without a max-size" \
         "exit ${status}. Output: ${planted_output}"
fi

mapfile -t compose_files < <(
    find "${REPO_ROOT}/homelab" -type f \( -name '*compose*.yaml' -o -name '*compose*.yml' \) | sort
)

if [[ ${#compose_files[@]} -eq 0 ]]; then
    fail "every homelab container caps its log" "no compose file found under homelab/, so this proves nothing"
else
    status=0
    repo_output="$(uncapped "${compose_files[@]}" 2>&1)" || status=$?
    if [[ ${status} -ne 0 ]]; then
        fail "the reader could read the homelab compose files" "exit ${status}: ${repo_output}"
    elif [[ -z "${repo_output}" ]]; then
        pass "every service in the ${#compose_files[@]} homelab compose files caps its log with max-size"
    else
        while IFS= read -r finding; do
            [[ -n "${finding}" ]] && fail "a homelab service keeps its whole log, set logging options max-size" \
                "${finding#"${REPO_ROOT}/"}"
        done <<<"${repo_output}"
    fi
fi

finish "compose log limits"
