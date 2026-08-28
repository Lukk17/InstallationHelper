#!/usr/bin/env bash
#
# Tier 1: this project never changes a screen lock, idle or session-restore setting, on any platform.
#
# It is the owner's machine and the owner's decision how long it waits before locking. A provisioning
# run has no business overriding it, and the way it happened here is worth naming because it looks
# harmless in a diff: the KDE role applies a konsave profile, konsave copies each config file in its
# manifest over the live one, and the profile carried a `kscreenlockerrc` holding nothing but a
# version stanza. Applying that does not merge, it replaces, so a machine configured never to lock
# silently went back to Plasma's default of locking after five minutes. `ksmserverrc` was in there too,
# which takes the Session Restore choice with it.
#
# Nothing warns you. The run reports success, the setting is gone, and the connection between the two
# is a config file inside a 18 megabyte archive that nobody opens.
#
# So the rule is a rule rather than a preference, and it holds on every platform: no lock timeout, no
# autolock flag, no idle delay, no screensaver password, no session-restore mode, not in an Ansible
# task, not in a dconf key, not in a `defaults write`, not in a registry value, and not smuggled in
# inside the konsave archive. If a user wants the machine to lock, they will say so themselves.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: nothing here changes a screen lock, idle or session setting"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "desktop settings"; }

report="$("${PYTHON:-python}" - <<'PYEOF'
import pathlib
import re
import zipfile

REPO = pathlib.Path('.')
SETUP = REPO / 'setup'

# Every way the four platforms spell "lock the screen after a while" or "restore my session".
# Plasma writes kscreenlockerrc and ksmserverrc, GNOME writes the org.gnome.desktop.screensaver and
# session schemas through dconf or gsettings, macOS writes com.apple.screensaver with `defaults`, and
# Windows keeps it in registry values under the desktop key and in powercfg's console-lock setting.
FORBIDDEN = [
    (re.compile(r'kscreenlockerrc'), 'the Plasma screen locker configuration'),
    (re.compile(r'ksmserverrc'), 'the Plasma session manager configuration'),
    (re.compile(r'org\.gnome\.desktop\.screensaver'), 'the GNOME screensaver schema'),
    (re.compile(r'org\.gnome\.desktop\.session[/ ]*(?:idle-delay)?'), 'the GNOME session idle delay'),
    (re.compile(r'com\.apple\.screensaver'), 'the macOS screensaver defaults domain'),
    (re.compile(r'askForPassword'), 'the macOS lock-on-wake setting'),
    (re.compile(r'ScreenSaverIsSecure|ScreenSaveTimeOut|ScreenSaveActive'),
     'a Windows screen saver registry value'),
    (re.compile(r'CONSOLELOCK|DISPLAYIDLE|-setdisplaysleep|-setcomputersleep'),
     'a console lock or display idle power setting'),
    (re.compile(r'\bloginctl\s+lock-session\b'), 'an explicit session lock'),
]

# Reading the state is fine and the playbook does it in three places to find out whether a desktop
# session exists. Only writing is banned, so a read-only query is not a hit.
ALLOWED_READS = re.compile(r'loginctl\s+show-user|gsettings\s+get|defaults\s+read|kreadconfig')

SCAN_SUFFIXES = ('.yaml', '.yml', '.sh', '.ps1', '.psm1', '.py', '.toml')

hits = []
files_read = 0

for path in sorted(SETUP.rglob('*')):
    if not path.is_file() or path.suffix not in SCAN_SUFFIXES:
        continue
    try:
        text = path.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        continue
    files_read += 1
    for number, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if stripped.startswith('#') or stripped.startswith('//'):
            continue
        if ALLOWED_READS.search(line):
            continue
        for pattern, what in FORBIDDEN:
            if pattern.search(line):
                hits.append('%s:%d writes %s' % (path.as_posix(), number, what))

# The konsave archive is the path that actually bit a machine, and it is a binary so no grep over the
# tree would ever have found it. Its manifest and its saved files are both read here.
profiles = sorted(SETUP.rglob('*.knsv'))
profiles_read = 0
for profile in profiles:
    try:
        archive = zipfile.ZipFile(profile)
    except zipfile.BadZipFile:
        hits.append('%s is not a readable archive, so this check cannot see inside it'
                    % profile.as_posix())
        continue
    profiles_read += 1
    names = archive.namelist()
    for name in names:
        for pattern, what in FORBIDDEN:
            if pattern.search(name):
                hits.append('%s carries %s as %s, and applying the profile overwrites whatever the '
                            'user set' % (profile.as_posix(), what, name))
    if 'conf.yaml' in names:
        manifest = archive.read('conf.yaml').decode('utf-8', 'replace')
        for number, line in enumerate(manifest.splitlines(), start=1):
            if line.strip().startswith('#'):
                continue
            for pattern, what in FORBIDDEN:
                if pattern.search(line):
                    hits.append('%s lists %s in its konsave manifest at conf.yaml:%d, so the next '
                                'save will pick it up again' % (profile.as_posix(), what, number))

lines = []
if not files_read or not profiles_read:
    lines.append('FAIL read %d source files and %d konsave profiles, so this check proves nothing'
                 % (files_read, profiles_read))
else:
    for hit in sorted(set(hits)):
        lines.append('FAIL %s. This project does not change lock, idle or session settings on any '
                     'platform.' % hit)
    if not hits:
        lines.append('OK %d source files and %d konsave profiles read, nothing changes a lock, idle '
                     'or session setting' % (files_read, profiles_read))

print('\n'.join(lines))
PYEOF
)"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "something changes a screen lock, idle or session setting" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the desktop settings check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "desktop settings"
