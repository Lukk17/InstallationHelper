#!/usr/bin/env bash
#
# Tier 2: the pacman consistency check of the software installer works on CachyOS.
#
# After the per-package pacman installs, setup/ansible/roles/software_installer/tasks/dynamic_install.yaml
# asks pacman whether the installed set is consistent. A bare `pacman -Dk` cannot answer that on
# CachyOS: CachyOS keeps a marker file, CACHY_UPDATE_NOTICE, in <DBPath>local, pacman reads it as a
# package record without a description, prints "error: 'CACHY_UPDATE_NOTICE': description file is
# missing", exits 1 and skips the dependency and conflict checks (docs/regression_ledger.md 10.161).
# The task now checks a copy of the database that leaves out every entry that is not a package
# directory.
#
# This takes the task's own command out of the YAML, so it tests what ships, and runs it in a
# throwaway non-privileged container of the image e2e/tier3/cachyos.Dockerfile pins, three times:
#
#   1. the bare `pacman -Dk` with the marker present still fails, which proves the container really
#      carries the defect the task works around. When CachyOS fixes pacman this fails and says so.
#   2. the task's command with the marker present finds no error and leaves the marker in place.
#   3. the task's command with the marker present and the record of readline removed names readline
#      as a missing dependency, so the copy did not make pacman blind.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/package_probe.sh"

require_cmd docker
require_python "the pacman consistency command could not be read from the task file" "pacman database check"

info "Tier 2: the pacman consistency check of the software installer works on CachyOS"

TASK_FILE="${REPO_ROOT}/setup/ansible/roles/software_installer/tasks/dynamic_install.yaml"
TASK_NAME="Ask pacman whether the installed set is consistent"

image="$(probe_image_for cachyos)"
if [[ -z "${image}" ]]; then
    fail "no image is pinned in e2e/tier3/cachyos.Dockerfile, so nothing was run" "${PROBE_TIER3_DIR}/cachyos.Dockerfile"
    finish "pacman database check"
fi

read_status=0
command_text="$("${PYTHON}" -I - "${TASK_FILE}" "${TASK_NAME}" <<'PYEOF'
import sys

import yaml


def tasks(node):
    if isinstance(node, list):
        for item in node:
            yield from tasks(item)
    elif isinstance(node, dict):
        if 'name' in node:
            yield node
        for value in node.values():
            yield from tasks(value)


path, name = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as handle:
    found = [task for task in tasks(yaml.safe_load(handle)) if task.get('name') == name]
if len(found) != 1:
    sys.exit('expected one task named %r in %s, found %d' % (name, path, len(found)))
shell = found[0].get('ansible.builtin.shell')
if not isinstance(shell, dict) or not isinstance(shell.get('cmd'), str):
    sys.exit('the task %r is not an ansible.builtin.shell task with a cmd' % name)
sys.stdout.write(shell['cmd'])
PYEOF
)" || read_status=$?
if [[ ${read_status} -ne 0 || -z "${command_text}" ]]; then
    fail "the consistency command could not be read from the task file" "${TASK_FILE}, Python exited ${read_status}"
    finish "pacman database check"
fi

probe_status=0
probe_out="$(timeout 900 docker run --rm "${image}" bash -c '
task_command="$1"
db="$(pacman-conf DBPath)"
printf "marker\n" >"${db%/}/local/CACHY_UPDATE_NOTICE"
out="$(pacman -Dk 2>&1)"; echo "BARE_RC $?"; printf "%s\n" "${out}" | sed "s/^/BARE /"
out="$(bash -c "${task_command}" 2>&1)"; echo "CLEAN_RC $?"; printf "%s\n" "${out}" | sed "s/^/CLEAN /"
[ -f "${db%/}/local/CACHY_UPDATE_NOTICE" ] && echo "MARKER_KEPT"
rm -rf "${db%/}"/local/readline-[0-9]*/
out="$(bash -c "${task_command}" 2>&1)"; echo "BROKEN_RC $?"; printf "%s\n" "${out}" | sed "s/^/BROKEN /"
echo PROBE_COMPLETE
' _ "${command_text}" 2>&1)" || probe_status=$?

if ! grep -qx 'PROBE_COMPLETE' <<<"${probe_out}"; then
    fail "the CachyOS container did not finish, so nothing was proved" \
         "docker run ${image} exited ${probe_status}: $(tail -3 <<<"${probe_out}" | tr '\n' ' ')"
    finish "pacman database check"
fi

rc_of() { sed -n "s/^$1_RC //p" <<<"${probe_out}"; }
lines_of() { sed -n "s/^$1 //p" <<<"${probe_out}" | tr '\n' ' '; }

if [[ "$(rc_of BARE)" != 0 ]] && grep -q "^BARE error: 'CACHY_UPDATE_NOTICE': description file is missing" <<<"${probe_out}"; then
    pass "a bare pacman -Dk still fails on the CachyOS marker file, so the container carries the defect the task works around"
else
    fail "a bare pacman -Dk no longer fails on the CachyOS marker file, so the copy in the task may be unnecessary now" \
         "exit $(rc_of BARE): $(lines_of BARE)"
fi

if [[ "$(rc_of CLEAN)" == 0 ]] && grep -qx 'CLEAN No database errors have been found!' <<<"${probe_out}" \
        && grep -qx 'CLEAN not a package record, left out of the copy pacman checks: CACHY_UPDATE_NOTICE' <<<"${probe_out}"; then
    pass "the task's command names the marker it leaves out and finds no error in a consistent CachyOS database"
else
    fail "the task's command does not pass a consistent CachyOS database" "exit $(rc_of CLEAN): $(lines_of CLEAN)"
fi

if grep -qx 'MARKER_KEPT' <<<"${probe_out}"; then
    pass "the task's command leaves the real database as it found it, marker included"
else
    fail "the marker file is gone from the real database after the task's command ran" "the command must work on a copy only"
fi

if [[ "$(rc_of BROKEN)" != 0 ]] && grep -q "^BROKEN error: missing 'readline' dependency for 'bash'" <<<"${probe_out}"; then
    pass "the task's command names readline as missing once its record is removed, so the copy still sees every package"
else
    fail "the task's command did not report the removed readline record" "exit $(rc_of BROKEN): $(lines_of BROKEN)"
fi

finish "pacman database check"
