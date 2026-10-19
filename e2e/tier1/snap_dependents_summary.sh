#!/usr/bin/env bash
#
# Tier 1: with install_snapd off, the playbook installs no snapd, skips every snap mapping, and says so
# at the end of the run, and on Ubuntu itself, where snapd ships with the system, it leaves snapd alone
# and skips nothing.
#
# Until 2026-10-18 roles/debian_core installed snapd on every Debian machine whatever install_snapd said,
# while every snap mapping went to snap whether or not anything had installed it, so turning the toggle
# off on Fedora or Arch would only have failed those packages four times each and ended the run failed
# for a choice the user made. setup/ansible/tasks/snap_availability.yaml now decides which requested
# mappings that skips, from manager snap in the dictionary and nothing else.
#
# Commit 0de82cc then put snapd under install_snapd on Ubuntu too, where it ships with the system, so
# turning the toggle off there would have skipped every snap mapping on a machine that has snapd, and the
# verification expected the playbook to install it. Owner decision 80: on Ubuntu the playbook never
# installs and never removes snapd and never touches its socket, and snap mappings install whatever
# install_snapd says. snap_availability.yaml answers that as ih_snapd_with_system. Commit c99ef74 keyed it
# on the Ubuntu lineage, ih_base, which also covers Pop!_OS and Linux Mint. Owner decision 84: only
# Ubuntu itself, the os-release ID ubuntu, and Pop!_OS and Linux Mint follow install_snapd like Debian.
# Asserted:
#   1. every task in arch_core, debian_core and fedora_core that installs snapd runs under install_snapd,
#      and every debian_core task that installs snapd or touches snapd.socket also runs only when
#      ih_snapd_with_system is false, after debian_core included snap_availability.yaml;
#   2. nothing in setup/ or docs/manual/ removes snapd: no package task with snapd and state absent, and
#      no remove, purge, erase or -R command naming snapd, nor a snap remove snapd of the whole snap;
#   3. the software installer includes snap_availability.yaml, drops ih_snap_skipped from its package
#      list before the snap install, site.yaml carries a [WARN] task reading ih_snap_skipped ahead of the
#      run's final verdict, and verify_install.yaml includes the same file, drops ih_snap_skipped from
#      what it expects and expects no snapd from the playbook while ih_snapd_with_system is true;
#   4. driven for real against a fixture dictionary, snap_availability.yaml skips exactly the requested
#      snap mappings with install_snapd off on Debian, on Pop!_OS and Linux Mint, which are Ubuntu lineage
#      under another os-release ID, and on Fedora, nothing with it on, and nothing on Ubuntu itself either
#      way, and the two shipped [WARN] tasks, lifted out of dynamic_install.yaml and site.yaml unchanged,
#      name every skipped one and nothing else.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd ansible-playbook
require_python "install_snapd off skips and names the snap mappings" "snap dependents summary"

AVAILABILITY="${ANSIBLE_DIR}/tasks/snap_availability.yaml"

info "Tier 1: install_snapd off skips and names the snap mappings"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

# --- 1, 2 and 3: the wiring ------------------------------------------------------------------------
report_status=0
report="$("${PYTHON}" - "${ANSIBLE_DIR}" "${work}" "${REPO_ROOT}" <<'PYEOF'
import pathlib
import re
import sys

import yaml

ansible, work, repo = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
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


def touches_socket(task):
    return any('snapd.socket' in str((task.get(key) or {}).get('name', '')) for key in
               ('ansible.builtin.systemd', 'systemd', 'ansible.builtin.systemd_service', 'systemd_service',
                'ansible.builtin.service', 'service') if isinstance(task.get(key), dict))


def includes(task, target):
    return any(target in str(task.get(key)) for key in
               ('ansible.builtin.include_tasks', 'include_tasks', 'ansible.builtin.import_tasks', 'import_tasks')
               if key in task)


installs = 0
debian_guarded = 0
for role in ('arch_core', 'debian_core', 'fedora_core'):
    path = ansible / 'roles' / role / 'tasks' / 'main.yaml'
    decided = False
    for task, cond in tasks_of(load(path)):
        if includes(task, 'tasks/snap_availability.yaml'):
            decided = True
        snapd_install = installs_snapd(task)
        if snapd_install:
            installs += 1
            if 'install_snapd' not in cond:
                lines.append('FAIL %s :: %s installs snapd without install_snapd in its conditions'
                             % (path.relative_to(ansible).as_posix(), task.get('name')))
        if role != 'debian_core' or not (snapd_install or touches_socket(task)):
            continue
        debian_guarded += 1
        if not re.search(r'not \(?ih_snapd_with_system\b', cond):
            lines.append('FAIL %s :: %s installs snapd or touches its socket without "not ih_snapd_with_system" in '
                         'its conditions, so it runs on Ubuntu, where snapd ships with the system'
                         % (path.relative_to(ansible).as_posix(), task.get('name')))
        elif not decided:
            lines.append('FAIL %s :: %s reads ih_snapd_with_system before the role includes '
                         'tasks/snap_availability.yaml, which is what sets it'
                         % (path.relative_to(ansible).as_posix(), task.get('name')))
if installs < 3:
    lines.append('FAIL only %d snapd installs were found in arch_core, debian_core and fedora_core, so this '
                 'proves nothing about the other families' % installs)
if debian_guarded < 2:
    lines.append('FAIL only %d debian_core tasks install snapd or touch snapd.socket, expected the install and '
                 'the socket, so the parser no longer sees them' % debian_guarded)

PACKAGE_MODULES = ('apt', 'dnf', 'yum', 'package', 'pacman', 'community.general.pacman', 'snap',
                   'community.general.snap')
removals = []
for path in sorted(ansible.rglob('*.yaml')):
    try:
        document = load(path)
    except yaml.YAMLError as error:
        lines.append('FAIL %s does not parse, so it was not searched for a snapd removal: %s'
                     % (path.relative_to(ansible).as_posix(), error))
        continue
    entries = document if isinstance(document, list) else []
    plays = [play for play in entries if isinstance(play, dict) and 'hosts' in play]
    every = [pair for play in plays for section in ('pre_tasks', 'tasks', 'post_tasks', 'handlers')
             for pair in tasks_of(play.get(section))] + list(tasks_of([e for e in entries if e not in plays]))
    for task, _ in every:
        for key, args in task.items():
            short = key.rsplit('.', 1)[-1] if key.startswith('ansible.builtin.') else key
            if short in PACKAGE_MODULES and isinstance(args, dict) and 'snapd' in str(args.get('name', '')) \
                    and str(args.get('state', '')) in ('absent', 'removed'):
                removals.append('%s :: %s' % (path.relative_to(ansible).as_posix(), task.get('name')))
REMOVE = re.compile(r'\b(apt|apt-get|dnf|yum|pacman|paru|yay|zypper|rpm)\b[^#\n]*\s(remove|purge|autoremove|erase'
                    r'|-R[a-zA-Z]*|-e)\b[^#\n]*\bsnapd\b|\bsnap\s+remove\s+["\']?snapd\b(?![^#\n]*--revision)')
scanned = [p for p in sorted((repo / 'setup').rglob('*')) + sorted((repo / 'docs' / 'manual').rglob('*'))
           if p.is_file() and p.suffix in ('.yaml', '.yml', '.sh', '.ps1', '.psm1')]
for path in scanned:
    for number, line in enumerate(path.read_text(encoding='utf-8', errors='replace').splitlines(), 1):
        if REMOVE.search(line.split('#', 1)[0] if path.suffix in ('.yaml', '.yml', '.sh') else line):
            removals.append('%s:%d %s' % (path.relative_to(repo).as_posix(), number, line.strip()))
for removal in removals:
    lines.append('FAIL something removes snapd: %s' % removal)
if not removals:
    lines.append('OK nothing in %d files under setup/ and docs/manual/ removes snapd' % len(scanned))

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

verify = load(ansible / 'verify_install.yaml')
vflat = [t for play in verify for section in ('pre_tasks', 'tasks') for t, _ in tasks_of(play.get(section))]
vdumped = [text_of(t) for t in vflat]
v_include = next((i for i, d in enumerate(vdumped) if 'tasks/snap_availability.yaml' in d), None)
v_reject = next((i for i, d in enumerate(vdumped) if "reject('in', ih_snap_skipped" in d), None)
v_split = next((i for i, t in enumerate(vflat) if t.get('name') == 'Split the enabled software by package manager'), None)
if v_include is None or v_reject is None or v_split is None or not v_include < v_reject < v_split:
    lines.append('FAIL verify_install.yaml does not include tasks/snap_availability.yaml and drop ih_snap_skipped '
                 'from enabled_mapped before splitting it by manager (include %s, drop %s, split %s)'
                 % (v_include, v_reject, v_split))
if not any("'snapd'" in str(t) and 'ih_snapd_with_system' in str(t) and 'ih_companions_not_applicable' in str(t)
           for t in vflat):
    lines.append('FAIL verify_install.yaml does not name snapd as not applicable while ih_snapd_with_system is true, '
                 'so it expects snapd from the playbook on Ubuntu')

if not any(line.startswith('FAIL') for line in lines):
    lines.append('OK all %d snapd installs run under install_snapd, the %d debian_core snapd tasks skip Ubuntu '
                 'itself, the software installer drops ih_snap_skipped before the snap install, both [WARN] tasks '
                 'are in place, and the verification asks the same file' % (installs, debian_guarded))
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

# --- 4: driven for real ----------------------------------------------------------------------------
# Three fixture mappings: a requested snap mapping, a snap mapping nobody asked for, and a requested
# flatpak one. Only the first may be skipped, and only with install_snapd off on a machine where snapd
# is not part of the system.
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
        msg: "IH_SNAP skipped={{ ih_snap_skipped | list | sort | join(',') }} with_system={{ ih_snapd_with_system | default('undefined') }}"
    - name: The software installer's own warning task
      ansible.builtin.include_tasks: "{{ work }}/dispatch_warn.yaml"
    - name: site.yaml's own warning task
      ansible.builtin.include_tasks: "{{ work }}/site_warn.yaml"
PLAY

# drive <install_snapd> <ih_family> <ih_base> <ih_os_release_id>  ->  the play's output
drive() {
    ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_FORCE_COLOR=0 \
        ansible-playbook -i localhost, "${work}/play.yaml" \
        -e "availability=${AVAILABILITY}" -e "work=${work}" -e "install_snapd=$1" \
        -e "ih_family=$2" -e "ih_base=$3" -e "ih_os_release_id=$4" </dev/null 2>&1 || true
}

problems=()
# The cases where install_snapd off skips the requested snap mapping: Debian, Pop!_OS and Linux Mint,
# the last two Ubuntu lineage under their own os-release ID, and Fedora. Each is family, lineage and ID,
# and the problems below name the machine by its ID.
for machine in "Debian:debian:debian" "Debian:ubuntu:pop" "Debian:ubuntu:linuxmint" "RedHat:fedora:fedora"; do
    IFS=: read -r family lineage id <<<"${machine}"
    off="$(drive false "${family}" "${lineage}" "${id}")"
    on="$(drive true "${family}" "${lineage}" "${id}")"
    if ! grep -q 'IH_SNAP skipped=' <<<"${off}"; then
        problems+=("${id}: the play did not finish: $(grep -m3 -E 'ERROR|fatal' <<<"${off}" | tr '\n' ' ')")
        continue
    fi
    grep -q 'IH_SNAP skipped=fixture_snap_wanted with_system=False"' <<<"${off}" \
        || problems+=("${id}: with install_snapd off it decided [$(grep -o 'IH_SNAP skipped=[^"]*' <<<"${off}" | head -1)], expected fixture_snap_wanted alone and snapd not part of the system")
    grep -q 'IH_SNAP skipped= with_system=False"' <<<"${on}" \
        || problems+=("${id}: with install_snapd on it decided [$(grep -o 'IH_SNAP skipped=[^"]*' <<<"${on}" | head -1)], expected nothing")
    grep -q '\[WARN\] Skipping install_fixture_snap_wanted:' <<<"${off}" \
        || problems+=("${id}: the software installer's [WARN] does not name install_fixture_snap_wanted")
    grep -qE '\[WARN\] install_snapd is off.*install_fixture_snap_wanted' <<<"${off}" \
        || problems+=("${id}: site.yaml's [WARN] does not name install_fixture_snap_wanted")
    grep -q 'fixture_snap_unwanted' <<<"$(grep '"msg": "\[WARN\]' <<<"${off}" || true)" \
        && problems+=("${id}: a [WARN] names fixture_snap_unwanted, which nobody asked for")
    grep -q '"msg": "\[WARN\]' <<<"${on}" && problems+=("${id}: with install_snapd on a [WARN] still names a skip: $(grep -m1 '\[WARN\]' <<<"${on}")")
done
# Ubuntu itself: snapd ships with the system, so nothing is skipped and nothing is warned about either way.
for toggle in false true; do
    ubuntu="$(drive "${toggle}" Debian ubuntu ubuntu)"
    grep -q 'IH_SNAP skipped= with_system=True"' <<<"${ubuntu}" \
        || problems+=("ubuntu: with install_snapd ${toggle} it decided [$(grep -o 'IH_SNAP skipped=[^"]*' <<<"${ubuntu}" | head -1)], expected nothing skipped and snapd part of the system")
    grep -q '"msg": "\[WARN\]' <<<"${ubuntu}" \
        && problems+=("ubuntu: with install_snapd ${toggle} a [WARN] claims a snap mapping is skipped: $(grep -m1 '\[WARN\]' <<<"${ubuntu}")")
done
if [[ ${#problems[@]} -eq 0 ]]; then
    pass "with install_snapd off exactly the requested snap mapping is skipped on Debian, Pop!_OS, Linux Mint and Fedora and both [WARN] lines name it, with it on nothing is, and on Ubuntu itself nothing is either way"
else
    fail "install_snapd does not skip and name the snap mappings as it should" "$(printf '%s; ' "${problems[@]}")"
fi

finish "snap dependents summary"
