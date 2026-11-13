#!/usr/bin/env bash
#
# Tier 1: a run of NVM, SDKMAN or Pyenv, picked-apps or full, wires that tool into a new terminal once,
# and only where nothing initializes it yet, owner decision 50.
#
# A picked-apps run, setup.sh --software none --enable install_nodejs, install_java or install_python,
# keeps the init lines the vendor installer or the user wrote, because it never removes anything. It
# still added the project's own shell init block beside them, so ~/.bashrc loaded nvm.sh twice,
# docs/regression_ledger.md 10.339. A full run removes the NVM and SDKMAN vendor lines, and still added
# the Pyenv block beside a `pyenv init -` line of the user's, 10.344. Now each of the three task files
# asks tasks/shell_init_lookup.yaml of sdk_manager first, in every run and after the full run's removal
# of the vendor lines, which searches every interactive rc file for the patterns of
# sdk_manager_shell_init in defaults/main.yaml, outside the project's own block.
#
# The tasks that wire each tool, from its environment block in dev_env_file_in_use to its shell init
# block in interactive_rc_files, are lifted out of the shipped task file as they are, with become taken
# off, and run with ansible-playbook against a fixture home directory. Per tool, once as a picked-apps
# run and once as a full run, each run twice:
#   1. every rc file that already initializes the tool by a line of the user's is left exactly as it
#      was. The file holding the vendor's lines is left as it was in a picked-apps run. A full run of
#      NVM or SDKMAN removes those lines from it and writes exactly one init block, and a full run of
#      Pyenv, which has no vendor lines to remove, leaves it as it was.
#   2. an rc file that does not, one that names the tool only in a comment, one that holds the
#      project's own block from an earlier run, and one that does not exist yet, each end with exactly
#      one init block of the tool, the stale block brought up to date.
#   3. the blocks of the other two tools, in the rc files and in the environment file, are left as they
#      were, and the environment file holds exactly one environment block of the tool.
#   4. the second run changes nothing.
# And an rc file that cannot be read, here a directory, fails the lookup rather than being taken as a
# file that initializes nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd ansible-playbook
require_python "a run wires NVM, SDKMAN and Pyenv into a terminal once" "picked apps shell init"

info "Tier 1: a picked-apps or full run wires NVM, SDKMAN and Pyenv into a terminal once"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

report_status=0
report="$("${PYTHON}" - "${ANSIBLE_DIR}" "${work}" <<'PYEOF'
import json
import os
import pathlib
import re
import subprocess
import sys

import yaml

ANSIBLE = pathlib.Path(sys.argv[1])
WORK = pathlib.Path(sys.argv[2])
ROLE = ANSIBLE / 'roles' / 'sdk_manager'
LOOKUP = ROLE / 'tasks' / 'shell_init_lookup.yaml'
BLOCKINFILE = ('ansible.builtin.blockinfile', 'blockinfile')
lines = []

# The markers are a contract with every machine already provisioned: a marker that changes makes
# blockinfile add a second block beside the old one. The first entry of initializes is the vendor's
# lines, the ones nvm_unix.yaml and sdkman_unix.yaml remove in a full run, and for Pyenv the snippet
# pyenv.run prints, which no run removes. vendor_removed says whether a full run removes them.
TOOLS = {
    'nvm': {
        'file': 'nvm_unix.yaml', 'toggle': 'install_nodejs', 'label': 'NVM', 'vendor_removed': True,
        'initializes': [
            'export NVM_DIR="$HOME/.nvm"\n'
            '[ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"  # This loads nvm\n'
            '[ -s "$NVM_DIR/bash_completion" ] && \\. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion\n',
            'source /usr/share/nvm/init-nvm.sh\n',
            'plugins=(\n  git\n  nvm\n)\nsource $ZSH/oh-my-zsh.sh\n',
        ],
        'does_not': ['# [ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"\nplugins=(git)\n'],
        'earlier': '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"',
    },
    'sdkman': {
        'file': 'sdkman_unix.yaml', 'toggle': 'install_java', 'label': 'SDKMAN', 'vendor_removed': True,
        'initializes': [
            '#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!\n'
            'export SDKMAN_DIR="$HOME/.sdkman"\n'
            '[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"\n',
            'source "$HOME/.sdkman/bin/sdkman-init.sh"\n',
        ],
        'does_not': ['# source "$HOME/.sdkman/bin/sdkman-init.sh"\n'],
        'earlier': '[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ] && . "$SDKMAN_DIR/bin/sdkman-init.sh"',
    },
    'pyenv': {
        'file': 'pyenv_unix.yaml', 'toggle': 'install_python', 'label': 'PYENV', 'vendor_removed': False,
        'initializes': [
            'export PYENV_ROOT="$HOME/.pyenv"\n'
            '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"\n'
            'eval "$(pyenv init - bash)"\n',
            'eval "$(pyenv init -)"\n',
            'plugins=(git pyenv)\n',
        ],
        'does_not': ['# eval "$(pyenv init - zsh)"\neval "$(pyenv init --path)"\n'],
        'earlier': 'command -v pyenv >/dev/null 2>&1 && eval "$(pyenv init - bash)"',
    },
}


def init_marker(tool, mark):
    return '# %s ANSIBLE %s SHELL INIT' % (mark, TOOLS[tool]['label'])


def env_marker(tool, mark):
    return '# %s ANSIBLE %s ENVIRONMENT' % (mark, TOOLS[tool]['label'])


def block(begin, end, body):
    return '%s\n%s\n%s\n' % (begin, body, end)


def blocks_of(text, begin, end):
    return re.findall(r'^%s\n.*?^%s\n' % (re.escape(begin), re.escape(end)), text, re.M | re.S)


def strip_become(node):
    if isinstance(node, dict):
        return {k: strip_become(v) for k, v in node.items() if k not in ('become', 'become_user')}
    if isinstance(node, list):
        return [strip_become(v) for v in node]
    return node


def lift(tool):
    """The tasks from the environment block to the shell init block of one tool, as shipped."""
    path = ROLE / 'tasks' / TOOLS[tool]['file']
    tasks = yaml.safe_load(path.read_text(encoding='utf-8')) or []
    env, init = [], []
    for index, task in enumerate(tasks):
        args = next((task[k] for k in BLOCKINFILE if isinstance(task, dict) and k in task), None)
        if not isinstance(args, dict):
            continue
        if 'dev_env_file' in str(args.get('path', '')):
            env.append(index)
        if 'interactive_rc_files' in str(task.get('loop', '')):
            init.append(index)
    if len(env) != 1 or len(init) != 1 or env[0] > init[0]:
        lines.append('FAIL %s should hold one blockinfile into dev_env_file_in_use followed by one into every '
                     'file of interactive_rc_files, and holds %d and %d' % (path.as_posix(), len(env), len(init)))
        return None
    lifted = WORK / ('%s.yaml' % tool)
    lifted.write_text(yaml.safe_dump(strip_become(tasks[env[0]:init[0] + 1]), sort_keys=False), encoding='utf-8')
    return lifted


def other_blocks(tool, marker):
    return ''.join(block(marker(o, 'BEGIN'), marker(o, 'END'), 'OTHER TOOL SENTINEL %s' % o)
                   for o in TOOLS if o != tool)


def run(tool, home, rc_files, picked):
    extra = {
        'non_root_home': str(home), 'non_root_user': os.environ.get('USER', 'root'),
        'interactive_rc_files': rc_files, 'shell_startup_files': [r['path'] for r in rc_files],
        'dev_env_file_in_use': str(home / 'env.conf'),
        'ih_picked_apps_run': picked, 'ih_picked_toggles': [TOOLS[tool]['toggle']] if picked else [],
    }
    (WORK / 'extra.json').write_text(json.dumps(extra), encoding='utf-8')
    (WORK / 'play.yaml').write_text(yaml.safe_dump([{
        'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
        'vars_files': [str(ROLE / 'defaults' / 'main.yaml')],
        'tasks': [{'name': 'The shipped wiring of %s' % tool,
                   'ansible.builtin.include_tasks': str(WORK / ('%s.yaml' % tool))}],
    }], sort_keys=False), encoding='utf-8')
    env = dict(os.environ, ANSIBLE_STDOUT_CALLBACK='default', ANSIBLE_FORCE_COLOR='0', ANSIBLE_NOCOLOR='1',
               ANSIBLE_LOCALHOST_WARNING='false', ANSIBLE_RETRY_FILES_ENABLED='false')
    done = subprocess.run(['ansible-playbook', '-i', 'localhost,', str(WORK / 'play.yaml'),
                           '-e', '@' + str(WORK / 'extra.json')],
                          cwd=WORK, env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True)
    return done.returncode, done.stdout + done.stderr


def snapshot(paths):
    return {p: (p.read_text(encoding='utf-8') if p.is_file() else None) for p in paths}


def exercise(tool, spec, picked):
    """One kind of run of one tool against a fresh fixture home, run twice. Returns 1 when it ran."""
    kind = 'picked-apps' if picked else 'full'
    begin, end = init_marker(tool, 'BEGIN'), init_marker(tool, 'END')
    home = WORK / ('home-%s-%s' % (kind, tool))
    home.mkdir()
    rc_files, left_alone, written, vendor = [], [], [], None
    for number, text in enumerate(spec['initializes']):
        path = home / ('initializes-%d.rc' % number)
        path.write_text('# the user\'s own rc file\n' + text + other_blocks(tool, init_marker), encoding='utf-8')
        rc_files.append({'shell': 'bash' if number % 2 == 0 else 'zsh', 'path': str(path)})
        if number == 0 and spec['vendor_removed'] and not picked:
            vendor = path
            written.append(path)
        else:
            left_alone.append(path)
    for number, text in enumerate(spec['does_not']):
        path = home / ('does-not-%d.rc' % number)
        path.write_text('# the user\'s own rc file\n' + text + other_blocks(tool, init_marker), encoding='utf-8')
        rc_files.append({'shell': 'zsh', 'path': str(path)})
        written.append(path)
    stale = home / 'earlier-run.rc'
    stale.write_text('# written by an earlier run\n' + block(begin, end, spec['earlier'] + '\n# STALE BLOCK OF AN EARLIER RUN')
                     + other_blocks(tool, init_marker), encoding='utf-8')
    rc_files.append({'shell': 'bash', 'path': str(stale)})
    written.append(stale)
    missing = home / 'not-there-yet.rc'
    rc_files.append({'shell': 'zsh', 'path': str(missing)})
    written.append(missing)
    env_file = home / 'env.conf'
    env_file.write_text(other_blocks(tool, env_marker), encoding='utf-8')
    paths = [pathlib.Path(r['path']) for r in rc_files] + [env_file]
    before = snapshot(paths)

    status, output = run(tool, home, rc_files, picked)
    if status != 0:
        lines.append('FAIL the %s run of %s failed: %s' % (kind, tool, ' '.join(
            l.strip() for l in output.splitlines() if l.startswith(('fatal', 'failed', 'ERROR')))[:600]))
        return 1
    after = snapshot(paths)

    for path in left_alone:
        if after[path] != before[path]:
            lines.append('FAIL a %s run of %s changed %s, which already initializes %s by a line of its own, so '
                         'the tool is now loaded twice: %r' % (kind, tool, path.name, tool, before[path].splitlines()[1]))
        else:
            lines.append('OK a %s run of %s left %s alone, which already initializes it with %r'
                         % (kind, tool, path.name, before[path].splitlines()[1]))
    for path in written:
        text = after[path] or ''
        found = blocks_of(text, begin, end)
        kept = [l for l in spec['initializes'][0].splitlines() if l in text.splitlines()] if path == vendor else []
        if len(found) != 1 or text.count(begin) != 1:
            lines.append('FAIL a %s run of %s left %d init blocks of it in %s, which did not initialize it, so a '
                         'new terminal %s' % (kind, tool, text.count(begin), path.name,
                                              'cannot reach it' if not found else 'loads it twice'))
        elif 'STALE BLOCK' in text:
            lines.append('FAIL a %s run of %s kept the stale init block of an earlier run in %s rather than '
                         'bringing it up to date, so its own block was taken for a line of the user\'s'
                         % (kind, tool, path.name))
        elif kept:
            lines.append('FAIL a full run of %s kept the vendor\'s lines in %s beside its init block, so the tool '
                         'is loaded twice: %r' % (tool, path.name, kept[0]))
        elif path == vendor:
            lines.append('OK a full run of %s removed the vendor\'s lines from %s and wrote exactly one init block '
                         'of it' % (tool, path.name))
        else:
            lines.append('OK a %s run of %s wrote exactly one init block of it into %s' % (kind, tool, path.name))
    for path in written + left_alone:
        for other in TOOLS:
            if other == tool:
                continue
            marker_pair = (init_marker(other, 'BEGIN'), init_marker(other, 'END'))
            if blocks_of(after[path] or '', *marker_pair) != blocks_of(before[path] or '', *marker_pair):
                lines.append('FAIL a %s run of %s changed the %s init block in %s' % (kind, tool, other, path.name))
    env_text = after[env_file] or ''
    if env_text.count(env_marker(tool, 'BEGIN')) != 1:
        lines.append('FAIL a %s run of %s left %d environment blocks of it in %s, expected one'
                     % (kind, tool, env_text.count(env_marker(tool, 'BEGIN')), env_file.name))
    for other in TOOLS:
        if other != tool:
            pair = (env_marker(other, 'BEGIN'), env_marker(other, 'END'))
            if blocks_of(env_text, *pair) != blocks_of(before[env_file], *pair):
                lines.append('FAIL a %s run of %s changed the %s environment block' % (kind, tool, other))

    status, output = run(tool, home, rc_files, picked)
    if status != 0 or snapshot(paths) != after:
        changed = [p.name for p in paths if snapshot([p])[p] != after[p]]
        lines.append('FAIL a second %s run of %s %s' % (
            kind, tool, 'failed' if status != 0 else 'changed %s again, so the block is not written once' % ', '.join(changed)))
    else:
        lines.append('OK a second %s run of %s changed nothing in the %d files' % (kind, tool, len(paths)))
    return 1


if LOOKUP.is_file():
    (WORK / LOOKUP.name).write_text(yaml.safe_dump(strip_become(yaml.safe_load(LOOKUP.read_text(encoding='utf-8'))),
                                                   sort_keys=False), encoding='utf-8')

cases = 0
for tool, spec in TOOLS.items():
    if lift(tool) is None:
        continue
    cases += exercise(tool, spec, True)
    cases += exercise(tool, spec, False)

# --- a file that cannot be read is not a file that initializes nothing --------------------------
if (WORK / 'nvm.yaml').is_file():
    home = WORK / 'home-unreadable'
    (home / 'a-directory.rc').mkdir(parents=True)
    status, output = run('nvm', home, [{'shell': 'bash', 'path': str(home / 'a-directory.rc')}], True)
    cases += 1
    failed_at = None
    for line in output.splitlines():
        if line.startswith('TASK ['):
            failed_at = line[6:line.rindex(']')]
        elif line.startswith(('fatal: [localhost]', 'failed: [localhost]')):
            break
    else:
        failed_at = None
    if status != 0 and failed_at and failed_at.startswith('Read each interactive rc file'):
        lines.append('OK an rc file that cannot be read stops the lookup, at "%s"' % failed_at)
    else:
        lines.append('FAIL an rc file that cannot be read did not stop the lookup: ansible-playbook exited %d and '
                     'failed at %s' % (status, '"%s"' % failed_at if failed_at else 'no task'))

if cases < 7:
    lines.append('FAIL only %d runs were made, so nothing about the three tools is proven' % cases)
print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "picked apps shell init"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a run does not wire its tool into a terminal exactly once" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the picked apps shell init check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "picked apps shell init"
