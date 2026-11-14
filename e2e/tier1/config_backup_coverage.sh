#!/usr/bin/env bash
#
# Tier 1: every configuration file the playbook changes is backed up before the change.
#
# On 2026-11-13 the owner ran setup.sh --software none --enable install_kicad9 on his configured
# CachyOS machine, and the run moved his ~/.config/environment.d/50-dev.conf into a backup folder,
# wrote 990-dev.conf and edited ~/.zshenv, with no notice. Owner decision 40: every configuration file
# a Linux or macOS run changes is copied into ~/.local/state/installation-helper/backup/<run time
# stamp>/<its absolute path> before its first change, and the end of the run lists every file changed
# or created and that folder. docs/regression_ledger.md 10.303. One mechanism does it:
# setup/ansible/tasks/config_backup.yaml copies every path in ih_config_files_all, from
# group_vars/all.yaml, in the pre_tasks of site.yaml, a role that learns a path only while it runs
# includes the same file with that path, and tasks/config_backup_report.yaml reports and keeps only the
# backups of what changed. So this asserts:
#
#   1. the mechanism is wired: site.yaml includes config_backup.yaml in its pre_tasks with
#      ih_config_files_all before the apt refresh and anything else that changes the machine, and
#      config_backup_report.yaml in its post_tasks after the cleanup and before the task that fails
#      the run, both tagged always. ih_config_files_all adds shell_startup_files,
#      interactive_rc_files and the files and keyrings of third_party_repositories to
#      ih_config_files, and callback_plugins/dual_logger.py prints what the report hands over.
#   2. every task under setup/ansible that writes or removes a file in a home directory or under
#      /etc, through blockinfile, lineinfile, ini_file, replace, copy, template, get_url, unarchive,
#      apt_repository, yum_repository, dconf, file with state absent, or a shell or command task that
#      edits such a file, is covered: its path is in ih_config_files, in the literal list of an include
#      of config_backup.yaml, or among the repository files of vars/, its loop runs over one of the
#      lists ih_config_files_all adds, or config_backup_targets.txt names what it writes, the include
#      that backs it up, or why what it writes is not configuration.
#   3. config_backup_targets.txt names only tasks that exist and need it, and every entry of
#      ih_config_files is written by some task, so neither list can outlive the code it describes.
#   4. no blockinfile, lineinfile, ini_file, replace, copy, template or file task that writes in the
#      home directory sets a mode, unless the mode is omitted where the path exists already or the
#      copy never replaces an existing file, so a run never changes the mode the user gave a file or
#      folder, docs/regression_ledger.md 10.309.
#   5. no task runs meta end_host, end_play or end_batch, which skip the always sections and the
#      post_tasks of site.yaml, where the sudoers grant is removed and this report is made,
#      docs/regression_ledger.md 10.307.
#   6. the listing configure_kde.yaml hands the backup before it applies the Konsave profile, run on
#      the shipped profile against three throwaway home folders, names every file that both sections
#      of the profile's conf.yaml write: the save section, which konsave -a copies, and the export
#      section, the themes, icons and wallpapers konsave -i copies over files of the same name. In an
#      empty home every export file is named or lies in a folder named as created, in a home where
#      every target holds something else every target is named, and in a home where every export
#      target already holds what konsave writes none is named, because thousands of icon files then
#      cost a loop item each in the backup and the report and change nothing. Until 2026-11-14 the
#      listing read the save section alone, docs/regression_ledger.md 10.349.
#   7. the probe, the listing and the backup include before the Konsave profile, lifted out of
#      configure_kde.yaml with become taken off, and config_backup_report.yaml, run with
#      ansible-playbook on a fixture home. Without --check, where one export file holds other bytes,
#      one is a symbolic link the run replaces with a file, as konsave does inside a folder, and one is
#      a link the run writes through, the backup keeps the file, the replaced link as a link and the
#      file written through the other, and the summary names exactly those three as changed. Under
#      --check the run succeeds and copies nothing. Until 2026-11-14 the listing did not run under
#      --check, so the include failed on an empty list, docs/regression_ledger.md 10.355, and the
#      backup followed every link, so it kept a replaced link only as a copy of what it pointed to and
#      named the link, not the file, when a run wrote through one, 10.357.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: every configuration file the playbook changes is backed up first"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "config backup coverage"; }

require_python "every configuration file the playbook changes is backed up first" "config backup coverage"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import json
import os
import pathlib
import pwd
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

import yaml

ANSIBLE = pathlib.Path('setup') / 'ansible'
SITE = ANSIBLE / 'site.yaml'
GROUP_VARS = ANSIBLE / 'group_vars'
ROLES = ANSIBLE / 'roles'
TASKS = ANSIBLE / 'tasks'
CALLBACK = ANSIBLE / 'callback_plugins' / 'dual_logger.py'
TARGETS = pathlib.Path('e2e') / 'tier1' / 'config_backup_targets.txt'
BACKUP_FILE = 'config_backup.yaml'
REPORT_FILE = 'config_backup_report.yaml'
MECHANISM = {TASKS / BACKUP_FILE, TASKS / REPORT_FILE}
SETS = ('shell_startup_files', 'interactive_rc_files', 'third_party_repositories')
TASK_KEYS = ('block', 'rescue', 'always')
PATH_MODULES = {'blockinfile': ('path', 'dest', 'destfile', 'name'), 'lineinfile': ('path', 'dest', 'destfile', 'name'),
                'ini_file': ('path', 'dest'), 'replace': ('path', 'dest', 'destfile', 'name'),
                'copy': ('dest',), 'template': ('dest',), 'get_url': ('dest',), 'unarchive': ('dest',),
                'file': ('path', 'dest', 'name')}
IMPLICIT = {'dconf': '{{ non_root_home }}/.config/dconf/user'}
SHELL_MODULES = {'shell', 'command'}
# A tool that writes a configuration file in the home directory without naming it.
CONFIG_TOOLS = re.compile(r'\b(kwriteconfig\d*|gsettings\s+set|dconf\s+(write|load|reset)|defaults\s+write|'
                          r'konsave\s+-[air]|xdg-mime\s+default|gnome-extensions\s+(enable|disable)|pipx\s+ensurepath|'
                          r'chsh|update-alternatives|debconf-set-selections)\b')
# A command that writes, moves or removes a file, which matters when it names a home or /etc path, and
# a redirect into such a path.
HOME_OR_ETC = r'(/etc/|\$HOME|\$\{HOME\}|~/|\{\{\s*(non_root_home|zsh_config_dir|dev_env_file\w*)\b)'
HOME_OR_ETC_PATH = re.compile(HOME_OR_ETC)
FILE_COMMANDS = re.compile(r'(^|[\s;&|(])(mv|cp|rm|ln|tee|sed\s+(-\w+\s+)*-i\w*)\s')
REDIRECT_INTO = re.compile(r'>{1,2}\s*["\']?' + HOME_OR_ETC)
REDIRECT = re.compile(r'>{1,2}\s*["\']?(/etc/[^\s"\';|&)]+)')
HOME_PREFIXES = ('/home/', '/Users/', '/root/', '/etc/', '/etc')

lines = []


def load(path):
    return yaml.safe_load(path.read_text(encoding='utf-8')) or []


def norm(text):
    text = str(text).strip().strip('"').strip("'").strip()
    head, *parts = text.split('{{')
    for part in parts:
        inner, closed, rest = part.partition('}}')
        head += '{{ ' + ' '.join(inner.split()) + ' }}' + rest if closed else '{{' + part
    return head


def module_of(task):
    for key, value in task.items():
        short = key.rsplit('.', 1)[-1]
        if short in PATH_MODULES or short in SHELL_MODULES or short in IMPLICIT or short in (
                'apt_repository', 'yum_repository', 'deb822_repository', 'include_tasks', 'import_tasks'):
            return short, value
    return None, None


def walk(tasks, inherited=None):
    """Every task, blocks included, with the vars of every block around it."""
    for task in tasks or []:
        if not isinstance(task, dict):
            continue
        scope_vars = dict(inherited or {})
        scope_vars.update(task.get('vars') or {})
        yield task, scope_vars
        for key in TASK_KEYS:
            if key in task:
                yield from walk(task[key], scope_vars)


# --- what the backup covers --------------------------------------------------------------------
all_vars = load(GROUP_VARS / 'all.yaml')
variables = {}
for path in sorted(GROUP_VARS.glob('*.yaml')) + sorted(ROLES.glob('*/defaults/main.yaml')) + sorted(ROLES.glob('*/vars/main.yaml')):
    for key, value in (load(path) or {}).items():
        variables.setdefault(key, value)

registry = all_vars.get('ih_config_files')
if not isinstance(registry, list) or len(registry) < 20:
    lines.append('FAIL ih_config_files in %s is not a list of at least 20 paths, so nothing below is proven'
                 % (GROUP_VARS / 'all.yaml').as_posix())
    registry = []
registry = {norm(entry) for entry in registry}
full_list = str(all_vars.get('ih_config_files_all', ''))
for needed in ('ih_config_files',) + SETS:
    if needed not in full_list:
        lines.append('FAIL ih_config_files_all in %s does not add %s, so the files it names are not backed up'
                     % ((GROUP_VARS / 'all.yaml').as_posix(), needed))
sets_covered = {name for name in SETS if name in full_list}

repository_files = set()
for path in sorted((ANSIBLE / 'vars').rglob('*.yaml')):
    repositories = (load(path) or {}).get('third_party_repositories') or {}
    for entry in repositories.values():
        for key in ('files', 'keyrings'):
            repository_files.update(norm(item) for item in (entry or {}).get(key) or [])
if len(repository_files) < 20:
    lines.append('FAIL only %d third-party repository files were read out of %s, so nothing about them is proven'
                 % (len(repository_files), (ANSIBLE / 'vars').as_posix()))


def scope_of(expression, local=None, depth=0):
    """in, out or unknown: whether a path expression is in a home directory or under /etc."""
    text = norm(expression)
    if text.startswith('~'):
        return 'in'
    if text.startswith('/'):
        return 'in' if text.startswith(HOME_PREFIXES) else 'out'
    match = re.match(r'^\{\{ ([A-Za-z_]\w*)\b', text)
    value = ((local or {}).get(match.group(1), variables.get(match.group(1))) if match else None)
    if isinstance(value, str) and depth < 10:
        return scope_of(value, local, depth + 1)
    return 'unknown'


def names_home_or_etc(text, local):
    """Whether a command names a home or /etc path, outright or through a variable that holds one."""
    if HOME_OR_ETC_PATH.search(text):
        return True
    return any(scope_of('{{ %s }}' % name, local) == 'in' for name in re.findall(r'\{\{\s*([A-Za-z_]\w*)', text))


task_files = [SITE] + sorted(TASKS.glob('*.yaml')) + sorted(ROLES.glob('*/tasks/*.yaml')) + sorted(ROLES.glob('*/handlers/*.yaml'))
include_literals = set()
tasks_by_file = {}
for path in task_files:
    doc = load(path)
    plays = doc if path == SITE else [{'tasks': doc}]
    found = []
    for play in plays:
        for section in ('pre_tasks', 'tasks', 'post_tasks', 'handlers'):
            for task, scope_vars in walk(play.get(section)):
                found.append((section, task, scope_vars))
                module, value = module_of(task)
                if module != 'include_tasks':
                    continue
                target = value.get('file') if isinstance(value, dict) else value
                if str(target or '').endswith('/' + BACKUP_FILE) or str(target or '') == 'tasks/' + BACKUP_FILE:
                    listed = (task.get('vars') or {}).get('config_backup_paths')
                    if isinstance(listed, list):
                        include_literals.update(norm(item) for item in listed)
    tasks_by_file[path] = found
covered = registry | include_literals | repository_files

# --- 1. the wiring -----------------------------------------------------------------------------
site = load(SITE)[0]
pre = site.get('pre_tasks') or []
post = site.get('post_tasks') or []


def include_index(section, name):
    for index, task in enumerate(section):
        module, value = module_of(task)
        target = value.get('file') if isinstance(value, dict) else value
        if module == 'include_tasks' and str(target or '').endswith(name):
            return index, task
    return None, None


backup_at, backup_task = include_index(pre, BACKUP_FILE)
refresh_at, _ = include_index(pre, 'apt_cache_refresh.yaml')
if backup_task is None:
    lines.append('FAIL the pre_tasks of %s do not include tasks/%s, so nothing is backed up before the roles run'
                 % (SITE.as_posix(), BACKUP_FILE))
else:
    if norm((backup_task.get('vars') or {}).get('config_backup_paths', '')) != '{{ ih_config_files_all }}':
        lines.append('FAIL the include of tasks/%s in the pre_tasks of %s does not hand it ih_config_files_all'
                     % (BACKUP_FILE, SITE.as_posix()))
    if refresh_at is None or backup_at > refresh_at:
        lines.append('FAIL the include of tasks/%s in %s does not come before the apt refresh, which can set '
                     'aside a sources file before it is backed up' % (BACKUP_FILE, SITE.as_posix()))
report_at, report_task = include_index(post, REPORT_FILE)
cleanup_at = next((i for i, t in enumerate(post) if t.get('name') == 'Clean up after the run'), None)
fail_at = next((i for i, t in enumerate(post) if t.get('name') == 'Fail the run because at least one role failed'), None)
if report_task is None:
    lines.append('FAIL the post_tasks of %s do not include tasks/%s, so the run never says what it changed'
                 % (SITE.as_posix(), REPORT_FILE))
elif cleanup_at is None or fail_at is None or not cleanup_at < report_at < fail_at:
    lines.append('FAIL the include of tasks/%s in %s is not between "Clean up after the run" and "Fail the run '
                 'because at least one role failed", so it misses a change or never runs in a failed run'
                 % (REPORT_FILE, SITE.as_posix()))
for task, name in ((backup_task, BACKUP_FILE), (report_task, REPORT_FILE)):
    if task is not None and 'always' not in str(task.get('tags', '')):
        lines.append('FAIL the include of tasks/%s in %s is not tagged always, so a run limited by --tags skips it'
                     % (name, SITE.as_posix()))
callback = CALLBACK.read_text(encoding='utf-8')
for key in ('ih_config_report', 'ih_config_backup_dir'):
    if '"%s"' % key not in callback:
        lines.append('FAIL %s never reads %s, so the end of the run does not list the configuration files it '
                     'changed or where their backup is' % (CALLBACK.as_posix(), key))

# --- 2. every task that writes a configuration file -------------------------------------------
entries = {}
for number, raw in enumerate(TARGETS.read_text(encoding='utf-8').splitlines(), 1):
    if not raw.strip() or raw.lstrip().startswith('#'):
        continue
    fields = [field.strip() for field in raw.split('|', 2)]
    if len(fields) != 3 or not all(fields):
        lines.append('FAIL %s line %d is not "<task file> | <task name> | <what it writes>": %s'
                     % (TARGETS.as_posix(), number, raw))
        continue
    entries.setdefault((fields[0], fields[1]), []).append((number, fields[2]))
used_entries = set()


def item_targets(target, task):
    """The paths a looped task writes, or None when the loop cannot be read here."""
    loop = task.get('loop', task.get('with_items'))
    if isinstance(loop, list):
        resolved = []
        for element in loop:
            path = norm(target)
            if isinstance(element, dict):
                for key, value in element.items():
                    path = path.replace('{{ item.%s }}' % key, str(value))
            else:
                path = path.replace('{{ item }}', str(element))
            resolved.append(norm(path))
        return resolved
    loop_text = str(loop or '')
    for name in SETS:
        if name in loop_text and norm(target) in ('{{ item }}', '{{ item.0 }}', '{{ item.path }}'):
            return ['@' + name]
    return None


def is_covered(target):
    return target in covered or (target.startswith('@') and target[1:] in sets_covered)


def check_entries(path, task, name, reason_for_entry):
    """True when config_backup_targets.txt covers the task, failing on any entry that does not hold."""
    listed = entries.get((path.as_posix(), name))
    if not listed:
        lines.append('FAIL "%s" in %s %s, and no include of tasks/%s, entry of ih_config_files or line of %s '
                     'covers it, so the run changes that file with no backup'
                     % (name, path.as_posix(), reason_for_entry, BACKUP_FILE, TARGETS.as_posix()))
        return False
    used_entries.add((path.as_posix(), name))
    names = [t.get('name') for _, t, _ in tasks_by_file[path]]
    for number, value in listed:
        if value.startswith('not configuration:'):
            if not value.split(':', 1)[1].strip():
                lines.append('FAIL %s line %d gives no reason after "not configuration:"' % (TARGETS.as_posix(), number))
        elif value.startswith('backed up by:'):
            include = value.split(':', 1)[1].strip()
            hits = [t for _, t, _ in tasks_by_file[path] if t.get('name') == include]
            target = hits[0] if hits else {}
            module, body = module_of(target)
            file_name = body.get('file') if isinstance(body, dict) else body
            if module != 'include_tasks' or not str(file_name or '').endswith(BACKUP_FILE) \
                    or names.index(include) > names.index(name):
                lines.append('FAIL %s line %d names "%s" as the backup of "%s", and no include of tasks/%s of that '
                             'name comes before it in %s' % (TARGETS.as_posix(), number, include, name, BACKUP_FILE,
                                                            path.as_posix()))
        elif value in SETS:
            if value not in sets_covered:
                lines.append('FAIL %s line %d says "%s" writes the files of %s, which ih_config_files_all does not '
                             'add' % (TARGETS.as_posix(), number, name, value))
        elif not is_covered(norm(value)):
            lines.append('FAIL %s line %d says "%s" writes %s, which neither ih_config_files nor any include of '
                         'tasks/%s names' % (TARGETS.as_posix(), number, name, value, BACKUP_FILE))
    return True


written = set()
examined = 0
for path, found in tasks_by_file.items():
    if path in MECHANISM:
        continue
    for section, task, scope_vars in found:
        if any(key in task for key in TASK_KEYS):
            continue
        module, args = module_of(task)
        if module is None or module in ('include_tasks', 'import_tasks'):
            continue
        name = task.get('name', '(unnamed)')
        args = args if isinstance(args, dict) else {}
        targets = None
        if module in SHELL_MODULES:
            body = task[next(k for k in task if k.rsplit('.', 1)[-1] == module)]
            text = ' '.join(map(str, body.get('argv', []))) + ' ' + str(body.get('cmd', '')) \
                if isinstance(body, dict) else str(body)
            file_command = bool(FILE_COMMANDS.search(text) and names_home_or_etc(text, scope_vars))
            if not CONFIG_TOOLS.search(text) and not file_command and not REDIRECT_INTO.search(text):
                continue
            examined += 1
            redirects = [norm(r) for r in REDIRECT.findall(text)]
            only_covered_redirects = (redirects and all(r in covered for r in redirects)
                                      and not CONFIG_TOOLS.search(text) and not file_command)
            if only_covered_redirects:
                written.update(redirects)
            else:
                check_entries(path, task, name, 'is a shell or command task that edits a file in a home '
                                                'directory or under /etc')
            continue
        if module in IMPLICIT:
            targets = [norm(IMPLICIT[module])]
        elif module == 'apt_repository':
            targets = [norm('/etc/apt/sources.list.d/%s.list' % args['filename'])] if args.get('filename') else None
        elif module == 'yum_repository':
            repo = args.get('file') or args.get('name')
            targets = [norm('%s/%s.repo' % (args.get('reposdir', '/etc/yum.repos.d'), repo))] if repo else None
        elif module == 'deb822_repository':
            targets = [norm('/etc/apt/sources.list.d/%s.sources' % args['name'])] if args.get('name') else None
        else:
            if module == 'file' and str(args.get('state', '')) != 'absent':
                continue
            raw = next((args[key] for key in PATH_MODULES[module] if key in args), None)
            if raw is None:
                targets = None
            else:
                target = norm(raw)
                for local, value in scope_vars.items():
                    target = target.replace('{{ %s }}' % local, norm(value)) if isinstance(value, str) else target
                if scope_of(target) == 'out':
                    continue
                targets = item_targets(target, task) if re.search(r'\{\{ item\b', target) else [target]
                if targets is not None:
                    targets = [t for t in targets if t.startswith('@') or scope_of(t) != 'out']
                    if not targets:
                        continue
        examined += 1
        if targets is not None and all(is_covered(t) for t in targets):
            written.update(targets)
            continue
        check_entries(path, task, name, 'writes %s' % (', '.join(targets) if targets else 'a path read only while it runs'))

for (file_name, name), listed in entries.items():
    for number, value in listed:
        if not value.startswith(('not configuration:', 'backed up by:')) and value not in SETS:
            written.add(norm(value))
    if (file_name, name) not in used_entries:
        lines.append('FAIL %s names "%s" in %s, which is no task there that writes a configuration file without '
                     'other cover, so the entry has outlived what it described'
                     % (TARGETS.as_posix(), name, file_name))

# --- 3. no path in ih_config_files that nothing writes ------------------------------------------
for entry in sorted(registry - written):
    lines.append('FAIL ih_config_files in %s names %s, which no task writes, so the list has drifted from the '
                 'code it describes' % ((GROUP_VARS / 'all.yaml').as_posix(), entry))
if examined < 60:
    lines.append('FAIL only %d tasks that write a configuration file were found, so nothing about them is proven'
                 % examined)


# --- 4. no mode forced on a file or folder the user may have already ---------------------------
def in_home(expression, local=None, depth=0):
    """Whether a path expression is in the user's home directory, as far as it can be read."""
    text = norm(expression)
    if text.startswith(('~', '/home/', '/Users/', '/root/', '{{ non_root_home', '@shell_startup_files',
                        '@interactive_rc_files')):
        return True
    match = re.match(r'^\{\{ ([A-Za-z_]\w*)\b', text)
    value = ((local or {}).get(match.group(1), variables.get(match.group(1))) if match else None)
    return isinstance(value, str) and depth < 10 and in_home(value, local, depth + 1)


MODE_MODULES = ('blockinfile', 'lineinfile', 'ini_file', 'replace', 'copy', 'template', 'file')
home_tasks = 0
for path, found in tasks_by_file.items():
    if path in MECHANISM:
        continue
    for section, task, scope_vars in found:
        module, args = module_of(task)
        if module not in MODE_MODULES or not isinstance(args, dict):
            continue
        if module == 'file' and str(args.get('state', 'file')) in ('absent', 'link', 'hard'):
            continue
        if module in ('copy', 'template') and str(args.get('force', 'true')).lower() in ('false', 'no'):
            continue
        raw = next((args[key] for key in PATH_MODULES[module] if key in args), None)
        if raw is None:
            continue
        target = norm(raw)
        targets = item_targets(target, task) if '{{ item' in target else [target]
        if not targets or not any(in_home(t, scope_vars) for t in targets):
            continue
        home_tasks += 1
        if 'mode' not in args or 'omit' in str(args['mode']):
            continue
        lines.append('FAIL "%s" in %s sets mode %s on %s, in the home directory, whether or not it exists '
                     'already, so a run overrides the mode the user gave it. Set a mode only where the task '
                     'creates it' % (task.get('name', '(unnamed)'), path.as_posix(), args['mode'], ', '.join(targets)))
if home_tasks < 20:
    lines.append('FAIL only %d tasks that write a file or a folder in the home directory were found, so nothing '
                 'about their mode is proven' % home_tasks)

# --- 5. nothing ends the play before the report and the cleanup --------------------------------
for path, found in tasks_by_file.items():
    for section, task, scope_vars in found:
        meta = task.get('ansible.builtin.meta', task.get('meta'))
        if str(meta).strip() in ('end_host', 'end_play', 'end_batch'):
            lines.append('FAIL "%s" in %s runs meta %s, which ends the play for the host and so skips the always '
                         'sections and the post_tasks of %s: the removal of the temporary sudoers grant and the '
                         'report of the configuration files. A role that has nothing to do ends with end_role'
                         % (task.get('name', '(unnamed)'), path.as_posix(), meta, SITE.as_posix()))

# --- 6. the Konsave listing names every file both sections of the profile write -----------------
KDE_TASKS = ROLES / 'kde_plasma_setup' / 'tasks' / 'configure_kde.yaml'
PROFILE = pathlib.Path('setup') / 'config' / 'lukk_desktop_profile.knsv'
KONSAVE_PLACES = {'$CONFIG_DIR': '/.config', '$SHARE_DIR': '/.local/share', '$BIN_DIR': '/.local/bin', '$HOME': ''}
OTHER_BYTES = b'not what the profile holds\n'


def examples(paths):
    return ', '.join(sorted(paths)[:3])


def profile_members():
    """Each file of the profile as (section kind, archive name, location template, path under it)."""
    with zipfile.ZipFile(PROFILE) as archive:
        conf = yaml.safe_load(archive.read('conf.yaml')) or {}
        for name in archive.namelist():
            kind, _, rest = name.partition('/')
            section, _, under = rest.partition('/')
            sections = (conf.get(kind) or {}) if kind in ('save', 'export') else {}
            if section in sections and under and not name.endswith('/'):
                yield kind, name, str(sections[section].get('location', '')), under


def target_of(home, location, under):
    for placeholder, suffix in KONSAVE_PLACES.items():
        location = location.replace(placeholder, home + suffix)
    return os.path.normpath(os.path.join(location, under))


def run_listing(script, home):
    run = subprocess.run([sys.executable, '-I', '-c', script, str(PROFILE.resolve()), home],
                         capture_output=True, text=True, check=False)
    if run.returncode != 0:
        return None, (run.stderr.strip().splitlines() or ['no error text'])[-1]
    return set(json.loads(run.stdout)), None


kde_tasks = [task for task, _ in walk(load(KDE_TASKS))]
backup_reads = [re.search(r'(\w+)\.stdout\s*\|\s*from_json\b', norm((task.get('vars') or {}).get('config_backup_paths', '')))
                for task in kde_tasks if module_of(task)[0] == 'include_tasks']
listing_task = next((task for task in kde_tasks for read in backup_reads
                     if read and task.get('register') == read.group(1)), None)
listing_argv = ((module_of(listing_task)[1] or {}).get('argv') or []) if listing_task else []
listing_script = listing_argv[listing_argv.index('-c') + 1] if '-c' in listing_argv[:-1] else None
members = list(profile_members()) if PROFILE.is_file() else []
konsave_written, konsave_fresh = 0, 0
if listing_script is None:
    lines.append('FAIL %s backs up no list printed by a python -c task, so which files the Konsave profile '
                 'writes is not checked' % KDE_TASKS.as_posix())
elif not any(kind == 'export' for kind, *_ in members) or not any(kind == 'save' for kind, *_ in members):
    lines.append('FAIL %s holds %d files under its save and export sections, so the Konsave listing is not '
                 'proven against both' % (PROFILE.as_posix(), len(members)))
else:
    with tempfile.TemporaryDirectory() as scratch, zipfile.ZipFile(PROFILE) as archive:
        for scenario in ('an empty home', 'a home where every target holds something else',
                         'a home where every export target holds what konsave writes'):
            home = os.path.join(scratch, str(len(os.listdir(scratch))))
            os.makedirs(os.path.join(home, '.config'))
            os.makedirs(os.path.join(home, '.local', 'share'))
            targets = {kind: {} for kind in ('save', 'export')}
            for kind, name, location, under in members:
                targets[kind][target_of(home, location, under)] = name
            for kind, written in targets.items():
                for path, name in written.items():
                    if scenario == 'an empty home' or (scenario.startswith('a home where every export')
                                                       and kind == 'save'):
                        continue
                    os.makedirs(os.path.dirname(path), exist_ok=True)
                    with open(path, 'wb') as handle:
                        handle.write(OTHER_BYTES if 'something else' in scenario else archive.read(name))
            listed, error = run_listing(listing_script, home)
            if listed is None:
                lines.append('FAIL the Konsave listing in %s stopped in %s: %s'
                             % (KDE_TASKS.as_posix(), scenario, error))
                continue
            konsave_written = sum(len(written) for written in targets.values())
            konsave_fresh = len(listed) if scenario == 'an empty home' else konsave_fresh
            missing_save = set(targets['save']) - listed
            covered = {path for path in targets['export']
                       if path in listed or any(path.startswith(entry + os.sep) for entry in listed)}
            if missing_save:
                lines.append('FAIL in %s the Konsave listing in %s leaves out %d of the %d files the save section '
                             'of %s writes, such as %s, so konsave -a overwrites them with no backup'
                             % (scenario, KDE_TASKS.as_posix(), len(missing_save), len(targets['save']),
                                PROFILE.as_posix(), examples(missing_save)))
            if scenario == 'a home where every export target holds what konsave writes':
                if covered:
                    lines.append('FAIL in %s the Konsave listing in %s names %d export files that konsave rewrites '
                                 'with the same bytes, such as %s, so each costs a loop item in the backup and in '
                                 'the report and none can change' % (scenario, KDE_TASKS.as_posix(), len(covered),
                                                                     examples(covered)))
                continue
            uncovered = set(targets['export']) - (covered if scenario == 'an empty home' else listed)
            if uncovered:
                lines.append('FAIL in %s the Konsave listing in %s leaves out %d of the %d files the export '
                             'section of %s writes, such as %s, so konsave -i overwrites the themes, icons and '
                             'wallpapers there with no backup, or creates them with none named as created'
                             % (scenario, KDE_TASKS.as_posix(), len(uncovered), len(targets['export']),
                                PROFILE.as_posix(), examples(uncovered)))


# --- 7. the backup before the Konsave profile, run for real and under --check -------------------
def strip_become(node):
    if isinstance(node, dict):
        return {key: strip_become(value) for key, value in node.items() if key not in ('become', 'become_user')}
    if isinstance(node, list):
        return [strip_become(value) for value in node]
    return node


def write_yaml(path, data):
    with open(path, 'w', encoding='utf-8') as handle:
        yaml.safe_dump(data, handle, sort_keys=False)


def run_konsave_backup(work, home, fixture, check):
    """The shipped probe, listing, backup and report, become taken off, run on one fixture home."""
    extra = dict(fixture, non_root_home=home, non_root_user=pwd.getpwuid(os.getuid()).pw_name,
                 ih_run_timestamp=FIXTURE_STAMP, os_dict={'software_mapping': {'pipx': {'package': 'pipx'}}})
    extra_file = os.path.join(work, 'extra-%s.json' % os.path.basename(home))
    with open(extra_file, 'w', encoding='utf-8') as handle:
        json.dump(extra, handle)
    env = dict(os.environ, ANSIBLE_STDOUT_CALLBACK='default', ANSIBLE_FORCE_COLOR='0', ANSIBLE_NOCOLOR='1',
               ANSIBLE_LOCALHOST_WARNING='false', ANSIBLE_RETRY_FILES_ENABLED='false')
    done = subprocess.run(['ansible-playbook', '-i', 'localhost,', os.path.join(work, 'ansible', 'play.yaml'),
                           '-e', '@' + extra_file] + (['--check'] if check else []),
                          cwd=work, env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, check=False)
    output = done.stdout + done.stderr
    fatal = [line.strip() for line in output.splitlines() if line.startswith(('fatal:', 'ERROR!', '[ERROR]'))]
    return done.returncode, (fatal or output.strip().splitlines()[-1:] or ['no output'])[0]


FIXTURE_STAMP = '2026-11-14T00-00-00Z'
konsave_top = load(KDE_TASKS)
listing_when = str(listing_task.get('when', '')) if listing_task else ''
probe_task = next((task for task in konsave_top if task.get('register') and task['register'] in listing_when
                   and task.get('register') != (listing_task or {}).get('register')), None)
backup_include = next((task for task, read in zip([t for t in kde_tasks if module_of(t)[0] == 'include_tasks'],
                                                  backup_reads) if read), None)
in_folders = [member for member in members if member[0] == 'export' and '/' in member[3]]
konsave_runs = 0
if shutil.which('ansible-playbook') is None:
    lines.append('FAIL ansible-playbook is not on PATH in the gate, so the backup before the Konsave profile is not run')
elif not (listing_task and probe_task and backup_include and len(in_folders) >= 3):
    lines.append('FAIL %s holds no profile probe, listing and backup include this check can lift and run, or %s '
                 'holds fewer than three export files inside a folder, so the backup before the Konsave profile '
                 'is not run' % (KDE_TASKS.as_posix(), PROFILE.as_posix()))
else:
    with tempfile.TemporaryDirectory() as work:
        os.makedirs(os.path.join(work, 'ansible', 'tasks'))
        os.symlink(os.path.abspath(PROFILE.parent), os.path.join(work, 'config'))
        for name in (BACKUP_FILE, REPORT_FILE):
            write_yaml(os.path.join(work, 'ansible', 'tasks', name), strip_become(load(TASKS / name)))
        lifted_names = [task.get('name') for task in konsave_top]
        lifted = konsave_top[konsave_top.index(probe_task):lifted_names.index(backup_include.get('name')) + 1]
        write_yaml(os.path.join(work, 'ansible', 'konsave.yaml'), strip_become(lifted))
        write_yaml(os.path.join(work, 'ansible', 'backup_vars.yaml'),
                   {key: all_vars[key] for key in ('ih_config_backup_root', 'ih_config_backup_dir', 'ih_config_states')})
        write_yaml(os.path.join(work, 'ansible', 'play.yaml'), [{
            'hosts': 'localhost', 'connection': 'local', 'gather_facts': False, 'vars_files': ['backup_vars.yaml'],
            'tasks': [
                {'name': 'The shipped backup before the Konsave profile', 'ansible.builtin.include_tasks': 'konsave.yaml'},
                {'name': 'Do what konsave does inside a folder to one link, and write through another',
                 'ansible.builtin.shell': 'rm -f -- "$REPLACED" && printf "konsave wrote this\\n" > "$REPLACED" && '
                                          'printf "written through the link\\n" > "$THROUGH" && '
                                          'printf "konsave wrote this\\n" > "$PLAIN"',
                 'environment': {'REPLACED': '{{ replaced }}', 'THROUGH': '{{ through }}', 'PLAIN': '{{ plain }}'}},
                {'name': 'Do what konsave -r does to the copy it stored', 'ansible.builtin.file': {
                    'path': '{{ saved }}', 'state': 'absent'}},
                {'name': 'The shipped report', 'ansible.builtin.include_tasks': 'tasks/' + REPORT_FILE},
                {'name': 'Keep what the report found', 'ansible.builtin.copy': {
                    'content': '{{ config_report | default({}) | to_json }}', 'dest': '{{ report_file }}'}}]}])
        for check in (False, True):
            mode = 'under --check' if check else 'without --check'
            home = os.path.join(work, 'check' if check else 'real')
            dotfiles = os.path.join(work, 'dotfiles-' + os.path.basename(home))
            os.makedirs(os.path.join(home, '.config'))
            os.makedirs(os.path.join(home, '.local', 'share'))
            os.makedirs(dotfiles)
            plain, replaced, through = (target_of(home, member[2], member[3]) for member in in_folders[:3])
            for path in (plain, replaced, through):
                os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(plain, 'wb') as handle:
                handle.write(OTHER_BYTES)
            pointed = {}
            for link in (replaced, through):
                pointed[link] = os.path.join(dotfiles, os.path.basename(link))
                with open(pointed[link], 'wb') as handle:
                    handle.write(OTHER_BYTES)
                os.symlink(pointed[link], link)
            saved = os.path.join(home, '.config', 'konsave', 'profiles', 'lukk_desktop_profile')
            saved_file = os.path.join(saved, 'conf.yaml')
            os.makedirs(saved)
            with open(saved_file, 'wb') as handle:
                handle.write(OTHER_BYTES)
            report_file = os.path.join(work, 'report-%s.json' % os.path.basename(home))
            status, first_error = run_konsave_backup(work, home, {'plain': plain, 'replaced': replaced,
                                                                  'through': through, 'saved': saved,
                                                                  'report_file': report_file}, check)
            backup = os.path.join(home, '.local', 'state', 'installation-helper', 'backup', FIXTURE_STAMP)
            if status != 0:
                lines.append('FAIL the probe, listing, backup and report of %s, run %s on a fixture home, failed with '
                             'exit %d: %s' % (KDE_TASKS.as_posix(), mode, status, first_error))
                continue
            if check:
                if os.path.exists(backup):
                    lines.append('FAIL the backup before the Konsave profile, run under --check, wrote %s, where a '
                                 'run under --check copies nothing' % backup)
                else:
                    konsave_runs += 1
                continue
            with open(report_file, encoding='utf-8') as handle:
                report_found = json.load(handle)
            problems = []
            if not os.path.isfile(backup + plain) or os.path.islink(backup + plain):
                problems.append('%s, a file konsave overwrites, has no copy in the backup' % plain)
            if not os.path.islink(backup + replaced) or os.readlink(backup + replaced) != pointed[replaced]:
                problems.append('%s, a link into %s that konsave replaces with a file, is not kept in the backup as '
                                'that link' % (replaced, dotfiles))
            if not os.path.isfile(backup + pointed[through]) or os.path.islink(backup + pointed[through]):
                problems.append('%s, which konsave wrote through the link %s, has no copy in the backup'
                                % (pointed[through], through))
            if not os.path.isfile(backup + saved_file):
                problems.append('%s, the copy of the profile konsave -r removes, has no copy in the backup' % saved_file)
            if set(report_found.get('removed') or []) != {saved_file}:
                problems.append('the summary lists as removed %s where it should list exactly %s'
                                % (sorted(report_found.get('removed') or []), [saved_file]))
            expected = {plain, replaced, pointed[through]}
            if set(report_found.get('changed') or []) != expected:
                problems.append('the summary lists as changed %s where it should list exactly %s'
                                % (sorted(report_found.get('changed') or []), sorted(expected)))
            if problems:
                lines.append('FAIL the backup before the Konsave profile, run without --check on a home where one '
                             'export file holds other bytes, one is a link konsave replaces and one a link written '
                             'through, with a copy of the profile konsave stored on an earlier run: %s' % '. '.join(problems))
            else:
                konsave_runs += 1

if not lines:
    lines.append('OK the backup is wired into site.yaml and the summary, all %d tasks that write a file in a '
                 'home directory or under /etc are covered by %d paths of ih_config_files, %d literal include '
                 'paths, %d repository files or %d lines of %s, none of the %d tasks that write in the home '
                 'directory forces a mode on what may exist already, nothing ends the play early, and the '
                 'Konsave listing names each of the %d files the save and export sections of the profile write, '
                 'in %d paths for an empty home, and the backup and report around it passed %d of 2 fixture runs, '
                 'keeping a file and two links and naming each change without --check and copying nothing under --check'
                 % (examined, len(registry), len(include_literals), len(repository_files),
                    sum(len(v) for v in entries.values()), TARGETS.as_posix(), home_tasks, konsave_written,
                    konsave_fresh, konsave_runs))
print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "config backup coverage"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a configuration file can change with no backup" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the config backup check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "config backup coverage"
