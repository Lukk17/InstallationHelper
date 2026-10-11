#!/usr/bin/env bash
#
# Tier 1: a dnf repository that checks its metadata signature can fetch that metadata unattended, and
# only with a key whose fingerprint was verified against a pin.
#
# GitHub sweep run 38107292439 failed every Fedora scenario on 2026-10-11 at "Fetch the metadata of one
# third-party repository on its own", which ran `dnf makecache --repo=tailscale-stable` and stopped at
#
#   Importing OpenPGP key 0x957F5868 ... Is this ok [y/N]:
#   repomd.xml GPG signature verification error: Signing key not found
#
# The Tailscale repository sets repo_gpgcheck. dnf5 5.4.2.1 imports the key that signs repomd.xml into
# a keyring of that repository's own (RepoPgp::import_key in libdnf5/repo/repo_pgp.cpp), asking first
# through the repokey_import callback in dnf5/context.cpp, which only --assumeyes answers. Importing the
# key with rpm_key does not reach that keyring. Until 2026-10-10 the first command to read the
# repository was `dnf install -y`, which answered for it, and the per-repository check that replaced it
# had no -y.
#
# -y answers yes to whatever key the .repo file names, so it is only safe beside a key that was checked
# first. This asserts, for every yum_repository under setup/ansible that sets repo_gpgcheck:
#
#   1. every `dnf makecache` under setup/ansible passes -y or --assumeyes;
#   2. its gpgkey is a local file:/// path, never a URL;
#   3. earlier in the same task list, a get_url with retries downloads that path from a pinned URL;
#   4. earlier still than the repository, a gpg --show-keys reads that path and an assert compares what
#      it registered with a pin whose name ends in _fingerprint and whose value is 40 hexadecimal digits;
#   5. that path is in the keyrings of the third_party_repositories entry naming the repository in
#      vars/RedHat.yaml, so the rescue removes a key that failed its check.
#
# A .repo written as text with repo_gpgcheck=1, by a shell printf or a copy, fails outright: nothing here
# can tie its key to a fingerprint. Finding no dnf makecache at all fails too, because then assertion 1
# means nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: a dnf repository with repo_gpgcheck fetches unattended and only with a verified key"

require_python "every repo_gpgcheck repository fetches unattended with a verified key" "repo metadata keys"

report_status=0
report="$("${PYTHON}" - "$(host_path "${REPO_ROOT}")" <<'PYEOF'
import pathlib
import re
import sys

try:
    import yaml
except ImportError as exc:
    print("SKIP no PyYAML for this interpreter: {}".format(exc))
    raise SystemExit(0)

root = pathlib.Path(sys.argv[1])
setup = root / 'setup'
ansible_dir = setup / 'ansible'
redhat = ansible_dir / 'vars' / 'RedHat.yaml'

sys.path.insert(0, str(setup / 'pinned_values'))
import pinned_values as reader

pins = reader.pins()

YUM_REPO = ('ansible.builtin.yum_repository', 'yum_repository')
GET_URL = ('ansible.builtin.get_url', 'get_url')
COMMANDS = ('ansible.builtin.command', 'command', 'ansible.builtin.shell', 'shell',
            'ansible.builtin.raw', 'raw')
ASSERT = ('ansible.builtin.assert', 'assert')
def templated_name(value):
    """The variable a value consisting of one bare Jinja expression names, or nothing."""
    text = str(value).strip()
    if not (text.startswith('{' '{') and text.endswith('}' '}')):
        return ''
    inner = text[2:-2].strip()
    return inner if re.fullmatch(r'[a-z0-9_]+', inner) else ''
INI_REPO_GPGCHECK = re.compile(r'repo_gpgcheck\s*=\s*(1|true|yes)\b', re.IGNORECASE)

failures = []

def task_lists(node):
    if isinstance(node, list):
        if any(isinstance(item, dict) for item in node):
            yield node
        for item in node:
            yield from task_lists(item)
    elif isinstance(node, dict):
        for key in ('block', 'rescue', 'always', 'tasks', 'pre_tasks', 'post_tasks', 'handlers'):
            if key in node:
                yield from task_lists(node[key])

def module_of(task, names):
    for name in names:
        if name in task:
            return task[name]
    return None

def command_text(task):
    params = module_of(task, COMMANDS)
    if isinstance(params, str):
        return params
    if isinstance(params, dict):
        argv = params.get('argv')
        if isinstance(argv, list):
            return ' '.join(str(item) for item in argv)
        if isinstance(argv, str):
            return argv
        return str(params.get('cmd', '') or params.get('_raw_params', ''))
    return ''

def truthy(value):
    return value is True or str(value).strip().lower() in ('1', 'true', 'yes')

def assumes_yes(text):
    return bool(re.search(r"(^|[\s'\"\[,])(-y|--assumeyes)($|[\s'\",\]])", text))

documents = []
for path in sorted(ansible_dir.rglob('*.yaml')) + sorted(ansible_dir.rglob('*.yml')):
    try:
        documents.append((path, yaml.safe_load(path.read_text(encoding='utf-8'))))
    except Exception as exc:
        failures.append('{} does not parse as YAML: {}'.format(path.relative_to(root).as_posix(), exc))

makecache = []
gpgcheck_repos = []
for path, doc in documents:
    for tasks in task_lists(doc):
        for index, task in enumerate(tasks):
            if not isinstance(task, dict):
                continue
            text = command_text(task)
            if 'dnf' in text and 'makecache' in text:
                makecache.append((path, task.get('name', '?'), text))
            params = module_of(task, YUM_REPO)
            if isinstance(params, dict) and truthy(params.get('repo_gpgcheck', False)):
                gpgcheck_repos.append((path, tasks, index, params))

for path in sorted(setup.rglob('*')):
    if not path.is_file() or '__pycache__' in path.parts or path.suffix in ('.pyc', '.png', '.jpg', '.knsv'):
        continue
    try:
        text = path.read_text(encoding='utf-8')
    except (UnicodeDecodeError, OSError):
        continue
    for number, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith('#'):
            continue
        if INI_REPO_GPGCHECK.search(line):
            failures.append('{}:{} writes repo_gpgcheck as text, where nothing can tie its key to a '
                            'fingerprint. Write it with yum_repository and a verified local key instead'
                            .format(path.relative_to(root).as_posix(), number))

if not makecache:
    failures.append('no dnf makecache was found under setup/ansible, so nothing here can be checked')

if gpgcheck_repos:
    for path, name, text in makecache:
        if not assumes_yes(text):
            failures.append('{}: "{}" runs dnf makecache without -y or --assumeyes, so dnf asks to import '
                            'the metadata key of a repo_gpgcheck repository and fails on "Signing key not found"'
                            .format(path.relative_to(root).as_posix(), name))

try:
    entries = (yaml.safe_load(redhat.read_text(encoding='utf-8')) or {}).get('third_party_repositories') or {}
except Exception as exc:
    entries = {}
    failures.append('{} could not be read: {}'.format(redhat.relative_to(root).as_posix(), exc))

for path, tasks, index, params in gpgcheck_repos:
    repo = params.get('name', '?')
    where = '{}: repository {}'.format(path.relative_to(root).as_posix(), repo)
    keys = params.get('gpgkey')
    keys = keys if isinstance(keys, list) else [keys]
    if not keys or any(not isinstance(key, str) or not key.startswith('file:///') for key in keys):
        failures.append('{} sets repo_gpgcheck with gpgkey {}, which is not a local file:/// key, so '
                        'dnf makecache -y imports whatever that address serves'.format(where, keys))
        continue
    earlier = [task for task in tasks[:index] if isinstance(task, dict)]
    for key in keys:
        local = key[len('file://'):]
        downloads = [task for task in earlier
                     if isinstance(module_of(task, GET_URL), dict)
                     and module_of(task, GET_URL).get('dest') == local]
        if not downloads:
            failures.append('{}: no get_url before it downloads {}'.format(where, local))
        for task in downloads:
            if templated_name(module_of(task, GET_URL).get('url', '')) not in pins:
                failures.append('{}: the get_url of {} fetches {} rather than exactly one pinned value'
                                .format(where, local, module_of(task, GET_URL).get('url')))
            if 'retries' not in task:
                failures.append('{}: the get_url of {} has no retries'.format(where, local))
        listings = [task for task in earlier
                    if 'gpg' in command_text(task) and '--show-keys' in command_text(task)
                    and local in command_text(task) and task.get('register')]
        if not listings:
            failures.append('{}: nothing before it reads the fingerprint of {} with gpg --show-keys'
                            .format(where, local))
            continue
        registers = {task['register'] for task in listings}
        verified = False
        for task in earlier:
            params_assert = module_of(task, ASSERT)
            if not isinstance(params_assert, dict):
                continue
            text = yaml.safe_dump({'that': params_assert.get('that'), 'vars': task.get('vars')})
            if not any(register in text for register in registers):
                continue
            for pin in re.findall(r'\b([a-z0-9_]+_fingerprint)\b', text):
                if re.fullmatch(r'[0-9A-F]{40}', pins.get(pin, '')):
                    verified = True
        if not verified:
            failures.append('{}: no assert before it compares what gpg read from {} with a pinned '
                            '_fingerprint of 40 hexadecimal digits'.format(where, local))
        owners = [entry for entry in entries.values()
                  if isinstance(entry, dict) and repo in (entry.get('repo_ids') or [])]
        if not owners or not any(local in (entry.get('keyrings') or []) for entry in owners):
            failures.append('{}: {} is not in the keyrings of its third_party_repositories entry in '
                            'vars/RedHat.yaml, so the rescue leaves a key that failed its check on disk'
                            .format(where, local))

if failures:
    print('FAIL ' + ' | '.join(failures))
else:
    print('OK {} dnf makecache call(s), {} repo_gpgcheck repository(s)'.format(len(makecache), len(gpgcheck_repos)))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "repo metadata keys"

case "${report}" in
    OK*)   pass "every repo_gpgcheck repository fetches unattended with a verified local key (${report#OK })" ;;
    SKIP*) skip "every repo_gpgcheck repository fetches unattended with a verified key" "${report#SKIP }" ;;
    *)     fail "a repo_gpgcheck repository would stop at a key prompt or trust an unverified key" "${report#FAIL }" ;;
esac

finish "repo metadata keys"
