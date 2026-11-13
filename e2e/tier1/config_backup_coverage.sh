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

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: every configuration file the playbook changes is backed up first"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "config backup coverage"; }

require_python "every configuration file the playbook changes is backed up first" "config backup coverage"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re

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
                          r'konsave\s+-a|xdg-mime\s+default|gnome-extensions\s+(enable|disable)|pipx\s+ensurepath|'
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

if not lines:
    lines.append('OK the backup is wired into site.yaml and the summary, all %d tasks that write a file in a '
                 'home directory or under /etc are covered by %d paths of ih_config_files, %d literal include '
                 'paths, %d repository files or %d lines of %s, none of the %d tasks that write in the home '
                 'directory forces a mode on what may exist already, and nothing ends the play early'
                 % (examined, len(registry), len(include_literals), len(repository_files),
                    sum(len(v) for v in entries.values()), TARGETS.as_posix(), home_tasks))
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
