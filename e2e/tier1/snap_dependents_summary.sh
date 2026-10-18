#!/usr/bin/env bash
#
# Tier 1: with install_snapd off, the playbook installs no snapd, skips every snap mapping, and says so
# at the end of the run.
#
# Until 2026-10-18 roles/debian_core installed snapd on every Debian machine whatever install_snapd said,
# while every snap mapping went to snap whether or not anything had installed it, so turning the toggle
# off on Fedora or Arch would only have failed those packages four times each and ended the run failed
# for a choice the user made. setup/ansible/tasks/snap_availability.yaml now decides which requested
# mappings that skips, from manager snap in the dictionary and nothing else. Asserted:
#   1. every task in arch_core, debian_core and fedora_core that installs snapd runs under install_snapd;
#   2. the software installer includes snap_availability.yaml, drops ih_snap_skipped from its package
#      list before the snap install, and site.yaml carries a [WARN] task reading ih_snap_skipped ahead of
#      the run's final verdict;
#   3. driven for real against a fixture dictionary, snap_availability.yaml skips exactly the requested
#      snap mappings with install_snapd off and nothing with it on, and the two shipped [WARN] tasks,
#      lifted out of dynamic_install.yaml and site.yaml unchanged, name every one of them.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd ansible-playbook
require_python "install_snapd off skips and names the snap mappings" "snap dependents summary"

AVAILABILITY="${ANSIBLE_DIR}/tasks/snap_availability.yaml"

info "Tier 1: install_snapd off skips and names the snap mappings"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

# --- 1 and 2: the wiring ---------------------------------------------------------------------------
report_status=0
report="$("${PYTHON}" - "${ANSIBLE_DIR}" "${work}" <<'PYEOF'
import pathlib
import re
import sys

import yaml

ansible, work = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
lines = []


def tasks_of(node, inherited=''):
    if not isinstance(node, list):
        return
    for task in node:
        if not isinstance(task, dict):
            continue
        cond = task.get('when')
        text = ' and '.join(p for p in [inherited] + ([str(c) for c in cond] if isinstance(cond, list)
                                                       else [] if cond is None else [str(cond)]) if p)
        yield task, text
        for section in ('block', 'rescue', 'always'):
            yield from tasks_of(task.get(section), text)


def load(path):
    return yaml.safe_load(path.read_text(encoding='utf-8')) or []


SHELLS = ('ansible.builtin.command', 'command', 'ansible.builtin.shell', 'shell', 'ansible.builtin.raw', 'raw')


def installs_snapd(task):
    listed = (task.get('vars') or {}).get('role_packages')
    if 'companion_packages.snapd' in str(listed) or (isinstance(listed, list) and 'snapd' in listed):
        return True
    return any(re.search(r'\s-S\b.*\bsnapd\b', str(task[key])) for key in SHELLS if key in task)


installs = 0
for role in ('arch_core', 'debian_core', 'fedora_core'):
    path = ansible / 'roles' / role / 'tasks' / 'main.yaml'
    for task, cond in tasks_of(load(path)):
        if not installs_snapd(task):
            continue
        installs += 1
        if 'install_snapd' not in cond:
            lines.append('FAIL %s :: %s installs snapd without install_snapd in its conditions'
                         % (path.relative_to(ansible).as_posix(), task.get('name')))
if installs < 3:
    lines.append('FAIL only %d snapd installs were found in arch_core, debian_core and fedora_core, so this '
                 'proves nothing about the other families' % installs)

dispatch = load(ansible / 'roles' / 'software_installer' / 'tasks' / 'dynamic_install.yaml')
flat = [t for t, _ in tasks_of(dispatch)]
names = [str(t.get('name', '')) for t in flat]


def text_of(node):
    if isinstance(node, dict):
        return ' '.join(text_of(v) for v in node.values())
    if isinstance(node, list):
        return ' '.join(text_of(v) for v in node)
    return ' '.join(str(node).split())


dumped = [text_of(t) for t in flat]
include = next((i for i, d in enumerate(dumped) if 'tasks/snap_availability.yaml' in d), None)
reject = next((i for i, d in enumerate(dumped) if "rejectattr('key', 'in', ih_snap_skipped" in d), None)
snap = next((i for i, n in enumerate(names) if n == 'Install Snap packages, one at a time'), None)
warn = next((t for t in flat if 'ih_snap_skipped | dict2items' in text_of(t) and '[WARN]' in text_of(t)), None)
if include is None or reject is None or snap is None or not include < reject < snap:
    lines.append('FAIL dynamic_install.yaml does not include tasks/snap_availability.yaml and drop ih_snap_skipped '
                 'before "Install Snap packages, one at a time" (include %s, drop %s, snap install %s)'
                 % (include, reject, snap))
if warn is None:
    lines.append('FAIL dynamic_install.yaml names no skipped snap mapping in a [WARN] line')
else:
    (work / 'dispatch_warn.yaml').write_text(yaml.safe_dump([warn], sort_keys=False), encoding='utf-8')

site = load(ansible / 'site.yaml')
post = [t for play in site for t, _ in tasks_of(play.get('post_tasks'))]
site_warn = next((i for i, t in enumerate(post) if 'ih_snap_skipped' in text_of(t) and '[WARN]' in text_of(t)), None)
verdict = next((i for i, t in enumerate(post) if str(t.get('name', '')).startswith('Fail the run')), None)
if site_warn is None or verdict is None or site_warn > verdict:
    lines.append('FAIL site.yaml has no [WARN] post task reading ih_snap_skipped ahead of the run\'s final verdict')
else:
    (work / 'site_warn.yaml').write_text(yaml.safe_dump([post[site_warn]], sort_keys=False), encoding='utf-8')

if not lines:
    lines.append('OK all %d snapd installs run under install_snapd, the software installer drops ih_snap_skipped '
                 'before the snap install, and both [WARN] tasks are in place' % installs)
print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "snap dependents summary"
while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "install_snapd is not wired the way the summary needs" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the wiring check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

if [[ ! -f "${AVAILABILITY}" || ! -f "${work}/dispatch_warn.yaml" || ! -f "${work}/site_warn.yaml" ]]; then
    fail "the skip could not be driven" "tasks/snap_availability.yaml or one of the two [WARN] tasks is missing"
    finish "snap dependents summary"
fi

# --- 3: driven for real ----------------------------------------------------------------------------
# Three fixture mappings: a requested snap mapping, a snap mapping nobody asked for, and a requested
# flatpak one. Only the first may be skipped, and only with install_snapd off.
cat > "${work}/play.yaml" <<'PLAY'
- hosts: localhost
  connection: local
  gather_facts: false
  vars:
    os_dict:
      software_mapping:
        fixture_snap_wanted: { manager: "snap", package: "fixture-snap-wanted" }
        fixture_snap_unwanted: { manager: "snap", package: "fixture-snap-unwanted" }
        fixture_flatpak_wanted: { manager: "flatpak", package: "org.example.Wanted" }
    install_fixture_snap_wanted: true
    install_fixture_snap_unwanted: false
    install_fixture_flatpak_wanted: true
  tasks:
    - name: Decide through the shipped file
      ansible.builtin.include_tasks: "{{ availability }}"
    - name: Report the decision
      ansible.builtin.debug:
        msg: "IH_SNAP skipped={{ ih_snap_skipped | list | sort | join(',') }}"
    - name: The software installer's own warning task
      ansible.builtin.include_tasks: "{{ work }}/dispatch_warn.yaml"
    - name: site.yaml's own warning task
      ansible.builtin.include_tasks: "{{ work }}/site_warn.yaml"
PLAY

drive() {
    ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_FORCE_COLOR=0 \
        ansible-playbook -i localhost, "${work}/play.yaml" \
        -e "availability=${AVAILABILITY}" -e "work=${work}" -e "install_snapd=$1" </dev/null 2>&1 || true
}

off="$(drive false)"
on="$(drive true)"
problems=()
grep -q 'IH_SNAP skipped=fixture_snap_wanted"' <<<"${off}" \
    || problems+=("with install_snapd off it skipped [$(grep -o 'IH_SNAP skipped=[^"]*' <<<"${off}" | head -1)], expected fixture_snap_wanted alone")
grep -q 'IH_SNAP skipped="' <<<"${on}" \
    || problems+=("with install_snapd on it skipped [$(grep -o 'IH_SNAP skipped=[^"]*' <<<"${on}" | head -1)], expected nothing")
grep -q '\[WARN\] Skipping install_fixture_snap_wanted:' <<<"${off}" \
    || problems+=("the software installer's [WARN] does not name install_fixture_snap_wanted")
grep -qE '\[WARN\] install_snapd is off.*install_fixture_snap_wanted' <<<"${off}" \
    || problems+=("site.yaml's [WARN] does not name install_fixture_snap_wanted")
grep -q 'fixture_snap_unwanted' <<<"$(grep '"msg": "\[WARN\]' <<<"${off}" || true)" \
    && problems+=("a [WARN] names fixture_snap_unwanted, which nobody asked for")
grep -q '"msg": "\[WARN\]' <<<"${on}" && problems+=("with install_snapd on a [WARN] still names a skip: $(grep -m1 '\[WARN\]' <<<"${on}")")
if ! grep -q 'IH_SNAP skipped=' <<<"${off}"; then
    problems=("the play did not finish: $(grep -m3 -E 'ERROR|fatal' <<<"${off}" | tr '\n' ' ')")
fi
if [[ ${#problems[@]} -eq 0 ]]; then
    pass "with install_snapd off exactly the requested snap mapping is skipped and both [WARN] lines name it, with it on nothing is"
else
    fail "install_snapd off does not skip and name the snap mappings" "$(printf '%s; ' "${problems[@]}")"
fi

finish "snap dependents summary"
