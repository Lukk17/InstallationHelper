#!/usr/bin/env bash
#
# Tier 1: a vendor installer piped into a shell and guarded by `creates` under the user's home must
# not be the only thing that wires its tool into the user's shell.
#
# Such an installer writes its own init lines into .bashrc or .zshrc on the one run that reaches its
# last step, and `creates` skips it on every run after its guard file appears. GitHub sweep run
# 38107292439, CachyOS GNOME full: the SDKMAN installer's first attempt failed after copying
# bin/sdkman-init.sh and before reaching its rc step, the retry was skipped because that file
# existed, and verify_install.yaml found `sdk` and `java` on disk but UNREACHABLE from zsh. NVM and
# pyenv had already been given an unconditional blockinfile of their own for the same reason, and
# SDKMAN had not.
#
# So the rule: every task file holding a shell or command task whose body pipes curl or wget into a
# shell and whose `creates` points under {{ non_root_home }} also holds a blockinfile task, with no
# `when` on it, writing either the environment file every shell and the desktop session read,
# dev_env_file, or every interactive rc file, a loop over interactive_rc_files. Since 2026-10-15
# those two replace apps_config/env.sh. A file whose tool is reached some other way is listed in
# vendor_installer_shell_init_allowed.txt with the reason, and an entry that no longer names such a
# file fails as well, so the list cannot outlive what it excuses.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: home-directory vendor installers have an unconditional shell init of the project's own"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "vendor installer shell init"; }

require_python "home-directory vendor installers have an unconditional shell init" "vendor installer shell init"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re

import yaml

ROLES = pathlib.Path('setup/ansible/roles')
ALLOWLIST = pathlib.Path('e2e/tier1/vendor_installer_shell_init_allowed.txt')
FREEFORM = ('ansible.builtin.shell', 'shell', 'ansible.builtin.command', 'command')
BLOCKINFILE = ('ansible.builtin.blockinfile', 'community.general.blockinfile', 'blockinfile')
PIPE_TO_SHELL = re.compile(r'\b(curl|wget)\b[^\n]*\|\s*(\w+=\S*\s+)*(ba|z)?sh\b')
HOME_GUARD = re.compile(r'^\{\{\s*non_root_home\s*\}\}/')
ENV_TARGETS = 'dev_env_file or every file in interactive_rc_files'


def walk(tasks):
    for task in tasks or []:
        if not isinstance(task, dict):
            continue
        yield task
        for key in ('block', 'rescue', 'always'):
            yield from walk(task.get(key))


def module_args(task, modules):
    for name in modules:
        if name in task:
            return name, task[name]
    return None, None


def home_installer(task):
    name, body = module_args(task, FREEFORM)
    if name is None:
        return False
    args = task.get('args') if isinstance(task.get('args'), dict) else {}
    if isinstance(body, dict):
        args = {**body, **args}
        body = body.get('cmd', body.get('_raw_params', ''))
    creates = str(args.get('creates', ''))
    return bool(PIPE_TO_SHELL.search(str(body or ''))) and bool(HOME_GUARD.match(creates))


def env_init(task):
    name, args = module_args(task, BLOCKINFILE)
    if name is None or not isinstance(args, dict) or 'when' in task:
        return False
    path = str(args.get('path', ''))
    return 'dev_env_file' in path or ('item' in path and 'interactive_rc_files' in str(task.get('loop', '')))


allowed = {}
try:
    for raw in ALLOWLIST.read_text(encoding='utf-8').splitlines():
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        path, sep, reason = line.partition('|')
        if not sep or not reason.strip():
            print('FAIL %s has an entry without a reason after a pipe: %s' % (ALLOWLIST.as_posix(), line))
            raise SystemExit(0)
        allowed[path.strip()] = reason.strip()
except OSError as exc:
    print('FAIL %s could not be read: %s' % (ALLOWLIST.as_posix(), exc))
    raise SystemExit(0)

files = sorted(ROLES.glob('*/tasks/**/*.yaml'))
if not files:
    print('FAIL no task file was found under %s, so there was nothing to check' % ROLES.as_posix())
    raise SystemExit(0)

installer_files = []
for path in files:
    try:
        tasks = yaml.safe_load(path.read_text(encoding='utf-8'))
    except (OSError, yaml.YAMLError) as exc:
        print('FAIL %s could not be read as YAML: %s' % (path.as_posix(), exc))
        continue
    if not isinstance(tasks, list):
        continue
    flat = list(walk(tasks))
    installers = [t.get('name', '<unnamed>') for t in flat if home_installer(t)]
    if not installers:
        continue
    rel = path.as_posix()
    installer_files.append(rel)
    if any(env_init(t) for t in flat):
        print('OK %s: "%s" has an unconditional shell init block in %s beside it'
              % (rel, '", "'.join(installers), ENV_TARGETS))
    elif rel in allowed:
        print('OK %s: "%s" is allowlisted, %s' % (rel, '", "'.join(installers), allowed[rel]))
    else:
        print('FAIL %s: "%s" pipes a download into a shell behind a creates guard under the user\'s home, '
              'and nothing in the same file writes an unconditional blockinfile into %s. The vendor '
              'installer is then the only thing wiring the tool into the shell, and once its guard file '
              'exists it never runs again, which is how sweep 38107292439 left sdk and java unreachable '
              'from zsh on CachyOS GNOME full.' % (rel, '", "'.join(installers), ENV_TARGETS))

if not installer_files:
    print('FAIL no home-directory vendor installer was found at all, so this check proved nothing. '
          'If they are really all gone, delete this check rather than letting it pass over nothing.')
for path in sorted(set(allowed) - set(installer_files)):
    print('FAIL %s lists %s, which no longer holds a home-directory vendor installer, so the entry '
          'excuses nothing and should go' % (ALLOWLIST.as_posix(), path))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "vendor installer shell init"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "${line#FAIL }" ;;
    esac
done <<<"${report}"
[[ -z "${report}" ]] && fail "the vendor installer shell init check printed nothing" "expected OK or FAIL lines"

finish "vendor installer shell init"
