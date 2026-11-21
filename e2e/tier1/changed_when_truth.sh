#!/usr/bin/env bash
#
# Tier 1: a task that changes the machine never claims it changed nothing.
#
# "Add Flathub repository (Linux)" in system_core carried changed_when: false, so a run that added the
# Flathub remote to a machine without one reported ok for it, and so did thirteen other tasks that
# remove runtimes, packages, older Homebrew versions and snap revisions, write desktop settings or
# reload udev,
# docs/regression_ledger.md 10.364. A recap that says ok where the machine changed hides the change
# from the person reading it and from the idempotency scenario of tier 3. So this asserts, for every
# task with changed_when: false in site.yaml, the shared tasks and every role's tasks and handlers:
#
#   1. a command, shell or raw task whose command line holds a word that changes the machine, such as
#      remote-add, uninstall, remove, clean, update, install, gsettings set, kwriteconfig, xdg-mime
#      default, writeConfig, osascript, gnome-extensions enable, udevadm control or trigger, rm, mv, cp,
#      sed -i, tee, systemctl enable or a redirect into a file, and every task of a module that changes
#      the machine, is named in changed_when_false_allowed.txt with the reason the claim is true: a
#      cache refresh or a cache clean, which is an act rather than a state, the run's own bookkeeping,
#      an async start whose change is reported where it is collected, or a command that only reads.
#   2. every line of that file names a task that still exists in that file and still carries
#      changed_when: false, so the list cannot go stale.
#   3. the tasks fixed by 10.364 report a change from what they read before and after, through
#      their register and a changed_when that reads it, rather than changed_when: false.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_python "a task that changes the machine never claims it changed nothing" "changed when truth"

info "Tier 1: a task that changes the machine never claims it changed nothing"

report_status=0
report="$("${PYTHON}" - "${REPO_ROOT}" <<'PYEOF'
import pathlib
import re
import sys

import yaml

REPO = pathlib.Path(sys.argv[1])
ANSIBLE = REPO / 'setup' / 'ansible'
ROLES = ANSIBLE / 'roles'
ALLOWED = REPO / 'e2e' / 'tier1' / 'changed_when_false_allowed.txt'
TASK_KEYS = ('block', 'rescue', 'always')
COMMANDS = ('command', 'shell', 'raw')
CHANGING_MODULES = ('apt', 'apt_repository', 'apt_key', 'dnf', 'yum', 'yum_repository', 'rpm_key', 'package',
                    'pacman', 'homebrew', 'homebrew_cask', 'snap', 'flatpak', 'flatpak_remote', 'copy', 'template',
                    'file', 'lineinfile', 'blockinfile', 'replace', 'ini_file', 'user', 'group', 'systemd',
                    'systemd_service', 'service', 'get_url', 'unarchive', 'pip', 'npm', 'git', 'cron', 'mount',
                    'make', 'dconf', 'osx_defaults', 'sysctl', 'modprobe', 'locale_gen', 'timezone', 'alternatives',
                    'kernel_blacklist', 'xattr', 'authorized_key', 'hostname')
MUTATING = re.compile('|'.join((
    r'\bremote-add\b', r'\buninstall\b', r'\b(?:auto)?remove\b', r'\bclean\b', r'\bupdate\b', r'\binstall\b',
    r'\bmakecache\b', r'\bpacman\s+-S', r'\bgsettings\s+set\b', r'\bkwriteconfig\d*\b', r'\bxdg-mime\s+default\b',
    r'\bwriteConfig\b', r'\bosascript\b', r'\bgnome-extensions\s+(?:enable|disable)\b', r'\budevadm\s+(?:control|trigger)\b',
    r'(?:^|[\s;|&(])(?:rm|mv|cp)\s', r'\s-delete\b', r'\bsed\s+-i', r'\btee\b', r'\bmkdir\b', r'\bln\s+-s',
    r'\bch(?:mod|own|grp)\b', r'\bdconf\s+(?:write|load|reset)\b', r'\bdefaults\s+write\b',
    r'\bsystemctl\s+(?:--user\s+)?(?:enable|disable|start|stop|restart|reload|daemon-reload|mask|unmask)\b',
    r'\bgit\s+(?:clone|checkout|fetch|pull|init|config)\b', r'\bsnap\s+(?:refresh|set)\b', r'\blocale-gen\b',
    r'\b(?:useradd|usermod|groupadd)\b', r'\bkillall\b', r'(?<![0-9&>])>>?\s*(?!/dev/null|&)[/~$"\']',
)))
FIXED = {
    'roles/system_core/tasks/base_utils.yaml': ('Add Flathub repository (Linux)',),
    'site.yaml': ('Clean Flatpak unused runtimes', 'Remove disabled Snap revisions', 'Cleanup Homebrew cache (macOS)',
                  'Remove orphaned packages (Fedora)'),
    'roles/linux_crypto_hardware/tasks/main.yaml': ('Reload udev rules', 'Trigger udev for currently-connected devices'),
    'roles/kde_plasma_setup/tasks/configure_kde.yaml': ('Set KDE Wallpaper', 'Set Spectacle Shortcut'),
    'roles/macos_core/tasks/main.yaml': ('Set macOS Wallpaper',),
    'roles/gnome_setup/tasks/configure_gnome.yaml': ('Set Default Apps via xdg-mime',
                                                     'Enable Dash to Dock and Disable Ubuntu Dock',
                                                     'Set Gnome Screenshot Shortcut'),
    'roles/shell_zsh/tasks/terminal_config.yaml': ('Configure GNOME Terminal to use ZSH',),
}
lines = []


def load(path):
    return yaml.safe_load(path.read_text(encoding='utf-8')) or []


def walk(tasks):
    for task in tasks or []:
        if isinstance(task, dict):
            yield task
            for key in TASK_KEYS:
                yield from walk(task.get(key))


def module_of(task):
    for key in task:
        short = key.rsplit('.', 1)[-1]
        if short in COMMANDS + CHANGING_MODULES and (
                key == short or key.startswith(('ansible.builtin.', 'community.general.', 'ansible.posix.'))):
            return short, task[key]
    return None, None


def command_text(value):
    if isinstance(value, dict):
        value = value.get('cmd') or value.get('argv') or value.get('_raw_params') or ''
    if isinstance(value, list):
        value = ' '.join(str(v) for v in value)
    return str(value or '')


def claims_nothing(task):
    value = task.get('changed_when', None)
    return value is False or (isinstance(value, str) and value.strip().lower() == 'false')


allowed = {}
for raw in ALLOWED.read_text(encoding='utf-8').splitlines() if ALLOWED.is_file() else []:
    if not raw.strip() or raw.lstrip().startswith('#'):
        continue
    parts = [p.strip() for p in raw.split('|')]
    if len(parts) != 3 or not all(parts):
        lines.append('FAIL %s line is not "<file under setup/ansible> | <task name> | <reason>": %s'
                     % (ALLOWED.relative_to(REPO).as_posix(), raw))
        continue
    allowed[(parts[0], parts[1])] = parts[2]
if not ALLOWED.is_file():
    lines.append('FAIL %s is missing, so no task with changed_when: false can say why that is true'
                 % ALLOWED.relative_to(REPO).as_posix())

files = [ANSIBLE / 'site.yaml'] + sorted((ANSIBLE / 'tasks').glob('*.yaml')) + \
    sorted(ROLES.glob('*/tasks/*.yaml')) + sorted(ROLES.glob('*/handlers/*.yaml'))
claimed = {}
flagged = 0
for path in files:
    doc = load(path)
    plays = doc if path.name == 'site.yaml' and path.parent == ANSIBLE else [{'tasks': doc}]
    relative = path.relative_to(ANSIBLE).as_posix()
    tasks = [t for play in plays for s in ('pre_tasks', 'tasks', 'post_tasks', 'handlers') for t in walk(play.get(s))]
    by_name = {t.get('name'): t for t in tasks}
    for task in tasks:
        if not claims_nothing(task):
            continue
        name = task.get('name', '(unnamed)')
        claimed[(relative, name)] = task
        module, value = module_of(task)
        if module in COMMANDS:
            found = MUTATING.search(command_text(value))
            if not found:
                continue
            why = 'runs %s, which changes the machine' % found.group(0).strip()
        elif module in CHANGING_MODULES:
            why = 'is a %s task, which changes the machine' % module
        else:
            continue
        flagged += 1
        if (relative, name) not in allowed:
            lines.append('FAIL "%s" in setup/ansible/%s %s, carries changed_when: false, and %s does not say why '
                         'it changes nothing, docs/regression_ledger.md 10.364'
                         % (name, relative, why, ALLOWED.relative_to(REPO).as_posix()))
    for name in FIXED.get(relative, ()):
        task = by_name.get(name)
        register = (task or {}).get('register')
        changed = str((task or {}).get('changed_when', ''))
        if not task or claims_nothing(task) or not register or register not in changed:
            lines.append('FAIL "%s" in setup/ansible/%s does not report a change through its register %s and a '
                         'changed_when that reads it, docs/regression_ledger.md 10.364'
                         % (name, relative, register or '(none)'))
for (relative, name) in sorted(set(allowed) - set(claimed)):
    lines.append('FAIL %s names "%s" in setup/ansible/%s, which has no task of that name with changed_when: false'
                 % (ALLOWED.relative_to(REPO).as_posix(), name, relative))
if len(claimed) < 40:
    lines.append('FAIL only %d tasks with changed_when: false were read, so nothing about them is proven' % len(claimed))
elif not any(l.startswith('FAIL') for l in lines):
    lines.append('OK each of the %d tasks with changed_when: false that runs a changing command or module, out of %d '
                 'with changed_when: false, is named with its reason in %s, and the %d tasks 10.364 fixed report '
                 'their change' % (flagged, len(claimed), ALLOWED.relative_to(REPO).as_posix(),
                                   sum(len(v) for v in FIXED.values())))
print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "changed when truth"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a task that changes the machine claims it changed nothing" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the changed when truth check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "changed when truth"
