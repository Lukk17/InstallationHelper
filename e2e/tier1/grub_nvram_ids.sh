#!/usr/bin/env bash
#
# Tier 1: removing this distribution's GRUB deletes the NVRAM boot entries that load it, and only those.
#
# "Identify NVRAM Boot IDs whose loader path is this distro's GRUB" in
# setup/ansible/roles/systemd_boot/tasks/remove_grub.yaml wrote its regexes with doubled backslashes
# inside a folded scalar. In every ansible-core setup/setup.sh accepts, 2.19.0 up to 2.23.0, a Jinja
# string literal keeps each backslash as written, so the loader path test asked for two backslashes
# where efibootmgr prints one, matched nothing, and no stale entry was ever deleted,
# docs/regression_ledger.md 10.371. So this asserts, for Ubuntu, Debian, Arch Linux, Fedora, CentOS
# and a distribution the map does not name:
#
#   1. the tasks from "Map distro to its GRUB EFI directory name" and from "Dump NVRAM boot entries
#      verbosely" to "Remove stale GRUB NVRAM entries for this distro", lifted as shipped with become
#      taken off, run with ansible-playbook against a fake efibootmgr that a PATH of the play's own
#      finds, proven before anything runs, and that prints a boot entry list in the two forms efivar
#      writes, `HD(...)/File(\EFI\ubuntu\shimx64.efi)` before efivar 38 and `HD(...)/\EFI\ubuntu\shimx64.efi`
#      from 38 on.
#   2. grub_nvram_ids names exactly the Boot IDs whose loader path lies in \EFI\<the distribution's
#      folder>\, active or not, in either form, and none whose label alone names the distribution,
#      whose folder only starts with that name, or that loads Windows, systemd-boot or the fallback.
#   3. the fake efibootmgr was asked `-v` once and `-b <id> -B` once for each of those IDs and for
#      nothing else.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd ansible-playbook
require_python "removing this distribution's GRUB deletes its NVRAM boot entries and only those" "GRUB NVRAM entries"

info "Tier 1: removing this distribution's GRUB deletes the NVRAM boot entries that load it, and only those"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

report_status=0
report="$("${PYTHON}" - "${REPO_ROOT}" "${work}" <<'PYEOF'
import json
import os
import pathlib
import subprocess
import sys

import yaml

REPO = pathlib.Path(sys.argv[1])
WORK = pathlib.Path(sys.argv[2])
TASKS = REPO / 'setup' / 'ansible' / 'roles' / 'systemd_boot' / 'tasks' / 'remove_grub.yaml'
MAP = 'Map distro to its GRUB EFI directory name'
FIRST = 'Dump NVRAM boot entries verbosely'
LAST = 'Remove stale GRUB NVRAM entries for this distro'
DISK = 'HD(1,GPT,0b5e1c2a-4f3d-4e6b-9a51-6d2f0c7e8a19,0x800,0x100000)'
lines = []

# What efibootmgr -v prints: BootXXXX, an asterisk for an active entry or a space, the label, a tab
# and the device path, whose file node efivar before 38 writes as File(...) and from 38 on bare.
ENTRIES = [
    'BootCurrent: 0003',
    'Timeout: 1 seconds',
    'BootOrder: 0003,0001,0000,0004,0005,0006,0007,0008,0009,000A,000B',
    'Boot0000* Windows Boot Manager\t%s/\\EFI\\Microsoft\\Boot\\bootmgfw.efi' % DISK,
    'Boot0001* Linux Boot Manager\t%s/\\EFI\\systemd\\systemd-bootx64.efi' % DISK,
    'Boot0003* ubuntu\t%s/\\EFI\\ubuntu\\shimx64.efi' % DISK,
    'Boot0004  ubuntu\t%s/File(\\EFI\\ubuntu\\grubx64.efi)' % DISK,
    'Boot0005* debian\t%s/File(\\EFI\\debian\\shimx64.efi)' % DISK,
    'Boot0006* Fedora\t%s/\\EFI\\fedora\\shimx64.efi' % DISK,
    'Boot0007* arch\t%s/\\EFI\\arch\\grubx64.efi' % DISK,
    'Boot0008* ubuntu\t%s/\\EFI\\ubuntu-old\\shimx64.efi' % DISK,
    'Boot0009* ubuntu\t%s/\\EFI\\Microsoft\\Boot\\bootmgfw.efi' % DISK,
    'Boot000A* UEFI OS\t%s/\\EFI\\BOOT\\BOOTX64.EFI' % DISK,
    'Boot000B* debian\t%s/File(\\EFI\\debian\\grubx64.efi)' % DISK,
]
CASES = [
    ('Ubuntu', ['0003', '0004']),
    ('Debian', ['0005', '000B']),
    ('Archlinux', ['0007']),
    ('Fedora', ['0006']),
    ('CentOS', []),
    ('Linuxmint', []),
]

tasks = yaml.safe_load(TASKS.read_text(encoding='utf-8')) or []
names = [str(t.get('name', '')) for t in tasks]
missing = [n for n in (MAP, FIRST, LAST) if n not in names]
if missing or names.index(FIRST) > names.index(LAST):
    print('FAIL %s no longer holds the tasks %s in that order, so nothing could be lifted'
          % (TASKS.relative_to(REPO).as_posix(), ', '.join('"%s"' % n for n in (MAP, FIRST, LAST))))
    sys.exit(0)


def strip(task):
    return {k: v for k, v in task.items() if k not in ('become', 'become_user')}


lifted = [strip(tasks[names.index(MAP)])] + [strip(t) for t in tasks[names.index(FIRST):names.index(LAST) + 1]]
fake_bin = WORK / 'fake-bin'
fake_bin.mkdir()
(WORK / 'entries.txt').write_text('\n'.join(ENTRIES) + '\n', encoding='utf-8')
fake = fake_bin / 'efibootmgr'
fake.write_text('#!/bin/sh\nprintf "%%s\\n" "$*" >> "$IH_EFIBOOTMGR_LOG"\n'
                'if [ "$1" = "-v" ]; then cat \'%s\'; fi\n' % (WORK / 'entries.txt'), encoding='utf-8')
fake.chmod(0o755)
fake_path = '%s:%s' % (fake_bin, os.environ.get('PATH', ''))

plays = []
for distribution, _ in CASES:
    case = WORK / distribution
    case.mkdir()
    # Defect class 16: the PATH the play hands its tasks must find the fake before the real tool.
    resolved = subprocess.run(['/bin/sh', '-c', 'command -v efibootmgr'], env=dict(os.environ, PATH=fake_path),
                              stdin=subprocess.DEVNULL, capture_output=True, text=True).stdout.strip()
    if resolved != str(fake):
        print('FAIL the PATH handed to the lifted tasks finds efibootmgr at %s, not at the fake %s, so no run was '
              'started' % (resolved or 'nothing', fake))
        sys.exit(0)
    plays.append({
        'name': distribution, 'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
        'environment': {'PATH': fake_path, 'IH_EFIBOOTMGR_LOG': str(case / 'calls.log')},
        'vars': {'ansible_facts': {'distribution': distribution}},
        'tasks': lifted + [{'name': 'Record the answer', 'ansible.builtin.copy': {
            'dest': str(case / 'answer.json'),
            'content': '{{ {"dir": distro_grub_efi_dir, "ids": grub_nvram_ids} | to_json }}'}}],
    })
(WORK / 'play.yaml').write_text(yaml.safe_dump(plays, sort_keys=False), encoding='utf-8')
(WORK / 'empty.cfg').write_text('[defaults]\n', encoding='utf-8')
env = dict(os.environ, ANSIBLE_CONFIG=str(WORK / 'empty.cfg'), ANSIBLE_STDOUT_CALLBACK='default', ANSIBLE_NOCOLOR='1',
           ANSIBLE_LOCALHOST_WARNING='false', ANSIBLE_RETRY_FILES_ENABLED='false')
done = subprocess.run(['ansible-playbook', '-i', 'localhost,', str(WORK / 'play.yaml')], cwd=WORK, env=env,
                      stdin=subprocess.DEVNULL, capture_output=True, text=True)
if done.returncode != 0:
    output = done.stdout + done.stderr
    fatal = [l.strip() for l in output.splitlines() if l.startswith(('fatal:', 'ERROR!', '[ERROR]'))]
    print('FAIL the lifted tasks of %s stopped with exit %d: %s'
          % (TASKS.relative_to(REPO).as_posix(), done.returncode, (fatal or [' '.join(output.split()[-40:])])[0]))
    sys.exit(0)

for distribution, expected in CASES:
    case = WORK / distribution
    answer = json.loads((case / 'answer.json').read_text(encoding='utf-8'))
    calls = (case / 'calls.log').read_text(encoding='utf-8').splitlines() if (case / 'calls.log').is_file() else []
    wanted_calls = ['-v'] + ['-b %s -B' % i for i in expected]
    problems = []
    if answer['ids'] != expected:
        problems.append('grub_nvram_ids is %s where %s, the entries that load \\EFI\\%s\\, was expected'
                        % (answer['ids'], expected, answer['dir']))
    if calls != wanted_calls:
        problems.append('efibootmgr was called as %s where %s was expected' % (calls, wanted_calls))
    if problems:
        lines.append('FAIL %s: %s' % (distribution, '; '.join(problems)))
    else:
        lines.append('OK %s: the entries that load \\EFI\\%s\\ are %s, and efibootmgr deleted exactly those'
                     % (distribution, answer['dir'], ', '.join('Boot' + i for i in expected) or 'none'))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "GRUB NVRAM entries"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "removing this distribution's GRUB deletes its NVRAM boot entries and only those" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the GRUB NVRAM check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "GRUB NVRAM entries"
