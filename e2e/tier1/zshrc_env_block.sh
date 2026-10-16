#!/usr/bin/env bash
#
# Tier 1: the checked-in zsh configuration keeps the environment out of .zshrc, and reaches the
# machine in a form a second run leaves alone.
#
# Four assertions, each for a defect this layout has already had.
#
#   1. setup/config/zsh/.zshrc exports nothing and assigns no PATH outside a comment. A variable set
#      there misses every desktop application, because Plasma starts its session through a
#      non-interactive login zsh that never reads .zshrc, which is how the owner's machine lost
#      ANDROID_HOME, JAVA_HOME and seven more in /proc/<plasmashell>/environ on 2026-10-13. The same
#      file also carried two PATH entries that were files, not directories.
#   2. shell_zsh writes that file as one marked block with blockinfile, read from the file itself,
#      rather than copying it whole. A whole-file copy without the markers is what made blockinfile
#      insert its block again on every second run in GitHub sweep run 38107292439, Arch idempotency.
#   3. The ZSH= line in that file names the directory shell_zsh installs Oh My Zsh into, the
#      shell_zsh_oh_my_zsh_dir default, with {{ non_root_home }} read as $HOME.
#   4. The zsh environment import env_variables writes declares `typeset -U path PATH` before it
#      imports ~/.config/environment.d, so a shell started from a shell does not repeat every entry.
#
# A task that can no longer be found fails rather than passing over nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: the checked-in .zshrc carries no environment, and reaches the machine as a marked block"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "zshrc env block"; }

require_python "the checked-in .zshrc carries no environment, and reaches the machine as a marked block" "zshrc env block"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re

import yaml

TEMPLATE = pathlib.Path('setup/config/zsh/.zshrc')
SHELL_ZSH_TASKS = pathlib.Path('setup/ansible/roles/shell_zsh/tasks/oh_my_zsh.yaml')
SHELL_ZSH_DEFAULTS = pathlib.Path('setup/ansible/roles/shell_zsh/defaults/main.yaml')
ENV_TASKS = pathlib.Path('setup/ansible/roles/env_variables/tasks/env_unix.yaml')
BASE_TASK = 'Write the checked-in zsh configuration into $ZDOTDIR/.zshrc'
IMPORT_TASK = 'Import environment.d into every zsh (Linux/macOS)'
BLOCKINFILE = ('ansible.builtin.blockinfile', 'community.general.blockinfile', 'blockinfile')
ENVIRONMENT_LINE = re.compile(r'^\s*(export\s|PATH=|path=|path\+=|PATH\+=)')


def load(path):
    try:
        return yaml.safe_load(path.read_text(encoding='utf-8'))
    except (OSError, yaml.YAMLError) as exc:
        print('FAIL %s could not be read as YAML: %s' % (path.as_posix(), exc))
        return None


def blockinfile_args(tasks, name, source):
    task = next((t for t in tasks or [] if isinstance(t, dict) and t.get('name') == name), None)
    if task is None:
        print('FAIL %s no longer has a task named "%s", so this check cannot know what it writes'
              % (source.as_posix(), name))
        return None
    args = next((task[m] for m in BLOCKINFILE if m in task), None)
    if not isinstance(args, dict):
        print('FAIL "%s" in %s is not a blockinfile task' % (name, source.as_posix()))
        return None
    return args


try:
    text = TEMPLATE.read_text(encoding='utf-8')
except OSError as exc:
    print('FAIL %s could not be read: %s' % (TEMPLATE.as_posix(), exc))
    raise SystemExit(0)

offending = [(n, line) for n, line in enumerate(text.splitlines(), 1)
             if not line.lstrip().startswith('#') and ENVIRONMENT_LINE.match(line)]
if offending:
    print('FAIL %s sets environment at %s. That file is read by interactive shells only, so a variable '
          'or PATH entry set there never reaches a desktop application. It belongs in the environment '
          'file env_variables writes, ~/.config/environment.d/50-dev.conf.'
          % (TEMPLATE.as_posix(), ', '.join('line %d "%s"' % (n, line.strip()) for n, line in offending)))
else:
    print('OK %s exports nothing and assigns no PATH outside a comment' % TEMPLATE.as_posix())

base = blockinfile_args(load(SHELL_ZSH_TASKS), BASE_TASK, SHELL_ZSH_TASKS)
if base is not None:
    block = str(base.get('block', ''))
    if 'lookup(' not in block or 'config/zsh/.zshrc' not in block or '{mark}' not in str(base.get('marker', '')):
        print('FAIL "%s" in %s does not write %s as a marked block read from the file, so the file on the '
              'machine and the one in the repository can drift, or a second run can insert it again'
              % (BASE_TASK, SHELL_ZSH_TASKS.as_posix(), TEMPLATE.as_posix()))
    else:
        print('OK "%s" writes %s as one marked block read from the file' % (BASE_TASK, TEMPLATE.as_posix()))

defaults = load(SHELL_ZSH_DEFAULTS) or {}
omz_dir = str(defaults.get('shell_zsh_oh_my_zsh_dir', '')).replace('{{ non_root_home }}', '$HOME')
zsh_lines = [line.strip() for line in text.splitlines() if re.match(r'^\s*(export\s+)?ZSH=', line)]
expected = 'ZSH="%s"' % omz_dir
if not omz_dir:
    print('FAIL %s has no shell_zsh_oh_my_zsh_dir, so where Oh My Zsh is installed is unknown'
          % SHELL_ZSH_DEFAULTS.as_posix())
elif zsh_lines != [expected]:
    print('FAIL %s sets ZSH as %s where %s installs Oh My Zsh into %s, so every new shell would look for '
          'oh-my-zsh.sh in the wrong place. Expected exactly one line: %s'
          % (TEMPLATE.as_posix(), zsh_lines or 'nothing', SHELL_ZSH_DEFAULTS.as_posix(), omz_dir, expected))
else:
    print('OK %s sets ZSH to %s, the directory shell_zsh installs Oh My Zsh into' % (TEMPLATE.as_posix(), omz_dir))

env = blockinfile_args(load(ENV_TASKS), IMPORT_TASK, ENV_TASKS)
if env is not None:
    lines = [line.strip() for line in str(env.get('block', '')).splitlines()]
    typeset = next((i for i, line in enumerate(lines) if line == 'typeset -U path PATH'), None)
    importer = next((i for i, line in enumerate(lines) if 'environment.d' in line), None)
    if typeset is None or importer is None or typeset > importer:
        print('FAIL "%s" in %s does not declare `typeset -U path PATH` before it imports environment.d, so '
              'a shell started from a shell repeats every PATH entry the import prepends'
              % (IMPORT_TASK, ENV_TASKS.as_posix()))
    else:
        print('OK "%s" declares typeset -U path PATH before the environment.d import' % IMPORT_TASK)
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "zshrc env block"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "${line#FAIL }" ;;
    esac
done <<<"${report}"
[[ -z "${report}" ]] && fail "the zshrc block check printed nothing" "expected OK or FAIL lines"

finish "zshrc env block"
