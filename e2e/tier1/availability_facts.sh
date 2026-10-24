#!/usr/bin/env bash
#
# Tier 1: every step the run no longer stops for is decided in one place, and every consumer reads it.
#
# On 2026-10-10 three steps stopped being fatal to the whole run, in the shape the paru fix set and
# e2e/tier1/paru_consumers.sh already guards. Each one now has a single fact, decided by one task file
# that the playbook and verify_install.yaml both include, and each consumer reads that fact, skips only
# what needs the step, and names it as NOT installed with the reason:
#
#   unavailable_repositories      a third-party repository that could not be added, decided by
#                                 setup/ansible/tasks/repository_availability.yaml. Until then one
#                                 vendor key host that did not answer ended the whole software phase.
#   steam_graphics_stack_aligned  the CachyOS 32-bit graphics alignment Steam needs, decided by
#                                 setup/ansible/tasks/steam_graphics_alignment.yaml. Until then a
#                                 failed alignment stopped the whole run inside arch_core.
#   env_variables_available       the project's environment file, decided by
#                                 setup/ansible/tasks/env_variables_availability.yaml for the
#                                 verification and set false by the env_variables rescue in site.yaml.
#                                 Until then that rescue re-raised and stopped every role after it.
#
# A convention is exactly what the next change forgets, and docs/regression_ledger.md defect class 2 is the cost of a
# second place deciding the same thing. So this asserts:
#
#   1. each fact is set only by its decider and the one rescue named above, and its decider is
#      included where the playbook and the verification need it;
#   2. every repository in software_installer/tasks/debian_repos.yaml and fedora_repos.yaml is its own
#      block, whose rescue includes repository_unavailable.yaml with a repository_key that names an
#      entry in vars/<family>.yaml third_party_repositories gated on the same toggle, every entry has
#      exactly one block, every block ends by fetching its own package lists or metadata, every Fedora
#      entry names the dnf ids of its repositories and every yum_repository a block writes is one of
#      them, and nothing that reaches the network sits outside a block. An entry with added_by is
#      written elsewhere, by setup.sh or a role, so it has no block, the file it names must write every
#      path and dnf id it claims, and the availability decider must leave it out;
#   2a. every literal sources or .repo path written anywhere under setup/ is a file of some entry or
#      one of the distribution's own files, because charm.list and waydroid.list were written outside
#      the entries and the first apt cache refresh then stopped the play for a dead repo.charm.sh;
#   2b. the first apt cache refresh of a Debian run, in the pre_tasks of site.yaml, goes through
#      setup/ansible/tasks/apt_cache_refresh.yaml, which fetches every third-party repository already
#      on the machine on its own, through the same check and rescue, before it refreshes everything.
#      Until 2026-10-10 a bare refresh there stopped the play for one vendor whose host was down.
#      It must also fetch every sources file this project does not manage on its own and set aside
#      one that does not answer, and the always section of site.yaml must put those back;
#   3. every per-package apt and dnf loop skips what repository_skipped_packages names, and that list
#      is built from unavailable_repositories in one place;
#   4. every other task gated on the toggle of a repository-backed package, outside Arch and macOS,
#      reads unavailable_repositories, so it cannot configure a package that was never installed;
#   5. the pacman loop reads steam_graphics_stack_aligned and ih_steam_packages, and the alignment
#      block's rescue sets it false;
#   6. sdk_manager is gated on env_variables_available, and the env_variables rescue sets it false and
#      no longer fails the play.
# The counts are reported and must not be zero, so a rewrite that hides everything from the parser
# fails here instead of passing over nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: every skipped step is decided in one place, and every consumer reads it"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "availability facts"; }

require_python "every skipped step is decided in one place, and every consumer reads it" "availability facts"

report_status=0
report="$("${PYTHON}" - <<'PYEOF'
import pathlib
import re

import yaml

ANSIBLE = pathlib.Path('setup') / 'ansible'
SITE = (ANSIBLE / 'site.yaml').as_posix()
VERIFY = (ANSIBLE / 'verify_install.yaml').as_posix()
TASKS_DIR = ANSIBLE / 'tasks'
SOFTWARE = ANSIBLE / 'roles' / 'software_installer' / 'tasks'
DYNAMIC = (SOFTWARE / 'dynamic_install.yaml').as_posix()
DEBIAN_REPOS = (SOFTWARE / 'debian_repos.yaml').as_posix()
FEDORA_REPOS = (SOFTWARE / 'fedora_repos.yaml').as_posix()
RESCUE_FILE = 'repository_unavailable.yaml'
CHECK_FILES = {'Debian': 'debian_repository_check.yaml', 'RedHat': 'fedora_repository_check.yaml'}
RECHECK_FILE = 'debian_repository_recheck.yaml'
APT_REFRESH = (TASKS_DIR / 'apt_cache_refresh.yaml').as_posix()
ARCH_CORE = (ANSIBLE / 'roles' / 'arch_core' / 'tasks' / 'main.yaml').as_posix()

# Task files that are included only on Arch or only on macOS, so a toggle there cannot belong to a
# Debian or Fedora repository. Named rather than inferred, and each one says why.
ARCH_OR_MAC_ONLY = {
    (SOFTWARE / 'arch_prereqs.yaml').as_posix(): 'dynamic_install.yaml includes it only on Archlinux',
    (SOFTWARE / 'macos_install.yaml').as_posix(): 'dynamic_install.yaml includes it only on Darwin',
}
NOT_CONSUMERS = {DEBIAN_REPOS, FEDORA_REPOS, VERIFY,
                 (SOFTWARE / RESCUE_FILE).as_posix(), (SOFTWARE / RECHECK_FILE).as_posix(), APT_REFRESH,
                 (TASKS_DIR / 'repository_availability.yaml').as_posix()}
NOT_CONSUMERS |= {(SOFTWARE / name).as_posix() for name in CHECK_FILES.values()}

FACTS = {
    'unavailable_repositories': {
        'decider': (TASKS_DIR / 'repository_availability.yaml').as_posix(),
        'rescue_setters': set(),
        'includers': [DYNAMIC, VERIFY],
    },
    'steam_graphics_stack_aligned': {
        'decider': (TASKS_DIR / 'steam_graphics_alignment.yaml').as_posix(),
        'rescue_setters': {ARCH_CORE},
        'includers': [ARCH_CORE, VERIFY],
    },
    'env_variables_available': {
        'decider': (TASKS_DIR / 'env_variables_availability.yaml').as_posix(),
        'rescue_setters': {SITE},
        'includers': [VERIFY],
    },
}

CONTAINER_MODULES = {'ansible.builtin.include_tasks', 'include_tasks', 'ansible.builtin.import_tasks',
                     'import_tasks', 'ansible.builtin.import_role', 'import_role',
                     'ansible.builtin.include_role', 'include_role'}
REPORT_MODULES = {'ansible.builtin.set_fact', 'set_fact', 'ansible.builtin.debug', 'debug'}
NETWORK_MODULES = {'ansible.builtin.get_url', 'get_url', 'ansible.builtin.rpm_key', 'rpm_key',
                   'ansible.builtin.yum_repository', 'yum_repository',
                   'ansible.builtin.apt_repository', 'apt_repository', 'ansible.builtin.copy', 'copy',
                   'ansible.builtin.shell', 'shell', 'ansible.builtin.command', 'command'}

lines = []


def as_text(value):
    if value is None:
        return ''
    if isinstance(value, str):
        return value
    return yaml.safe_dump(value, default_flow_style=True, width=100000)


def walk(tasks, ancestors=()):
    """Yields (task, ancestors), ancestors being the enclosing block tasks, outermost first."""
    if not isinstance(tasks, list):
        return
    for task in tasks:
        if not isinstance(task, dict):
            continue
        yield task, ancestors
        for key in ('block', 'rescue', 'always'):
            if key in task:
                yield from walk(task[key], ancestors + (task,))


def combined_when(task, ancestors):
    return ' and '.join(as_text(t.get('when')) for t in ancestors + (task,) if t.get('when'))


def module_of(task):
    for key in task:
        if '.' in key or key in CONTAINER_MODULES or key in NETWORK_MODULES:
            if key not in ('name', 'when', 'tags', 'vars', 'loop', 'register', 'become'):
                return key
    return None


def include_target(task):
    for key in CONTAINER_MODULES:
        if key in task:
            target = task[key]
            if isinstance(target, dict):
                target = target.get('file') or target.get('name') or ''
            return str(target)
    return ''


task_files = [ANSIBLE / 'site.yaml', ANSIBLE / 'verify_install.yaml']
task_files += sorted(TASKS_DIR.glob('*.yaml'))
task_files += sorted((ANSIBLE / 'roles').glob('*/tasks/*.yaml'))
docs = {}
for path in task_files:
    try:
        doc = yaml.safe_load(path.read_text(encoding='utf-8'))
    except (yaml.YAMLError, UnicodeDecodeError) as exc:
        lines.append('FAIL %s does not parse, so nothing in it was checked: %s' % (path.as_posix(), exc))
        continue
    if isinstance(doc, list) and doc and isinstance(doc[0], dict) and 'hosts' in doc[0]:
        play_tasks = []
        for play in doc:
            for section in ('pre_tasks', 'tasks', 'post_tasks'):
                play_tasks += play.get(section) or []
        doc = play_tasks
    docs[path.as_posix()] = doc if isinstance(doc, list) else []

if not docs:
    print('FAIL no task file under setup/ansible could be read, so this check proves nothing')
    raise SystemExit(0)

# --- 1. one decider per fact ------------------------------------------------------------------
for fact, spec in FACTS.items():
    setters = set()
    includers = set()
    for where, tasks in docs.items():
        for task, _ in walk(tasks):
            set_fact = task.get('ansible.builtin.set_fact', task.get('set_fact'))
            if isinstance(set_fact, dict) and fact in set_fact:
                setters.add(where)
            if include_target(task).endswith('tasks/' + pathlib.Path(spec['decider']).name):
                includers.add(where)
    allowed = {spec['decider']} | spec['rescue_setters']
    extra = sorted(setters - allowed)
    if extra:
        lines.append('FAIL %s is set in %s as well as by %s, which is a second place deciding the '
                     'same thing' % (fact, ', '.join(extra), ' and '.join(sorted(allowed))))
    if spec['decider'] not in setters:
        lines.append('FAIL %s does not set %s, so every consumer reads a fact nothing decides'
                     % (spec['decider'], fact))
    for rescue_setter in sorted(spec['rescue_setters']):
        if rescue_setter not in setters:
            lines.append('FAIL %s no longer sets %s in its rescue, so a failure there is not recorded '
                         'for the consumers' % (rescue_setter, fact))
    for includer in spec['includers']:
        if includer not in includers:
            lines.append('FAIL %s does not include %s, so it answers the %s question some other way '
                         'or not at all' % (includer, spec['decider'], fact))

# --- 2. one block per repository ----------------------------------------------------------------
repository_blocks = 0
for repos_file, family in ((DEBIAN_REPOS, 'Debian'), (FEDORA_REPOS, 'RedHat')):
    vars_path = ANSIBLE / 'vars' / ('%s.yaml' % family)
    entries = (yaml.safe_load(vars_path.read_text(encoding='utf-8')) or {}).get('third_party_repositories') or {}
    if not entries:
        lines.append('FAIL %s has no third_party_repositories, so %s cannot be checked against it'
                     % (vars_path.as_posix(), repos_file))
        continue
    seen = {}
    for task in docs.get(repos_file, []):
        label = '%s :: %s' % (repos_file, task.get('name', '<unnamed>'))
        if 'block' not in task:
            if module_of(task) in NETWORK_MODULES:
                lines.append('FAIL %s reaches the network or writes a repository outside a block with '
                             'a rescue, so one vendor that does not answer ends the software phase '
                             'again' % label)
            continue
        repository_blocks += 1
        keys = [((t.get('vars') or {}).get('repository_key'))
                for t, _ in walk(task.get('rescue') or [])
                if include_target(t).endswith(RESCUE_FILE)]
        if len(keys) != 1 or not keys[0]:
            lines.append('FAIL %s has no rescue that includes %s with a repository_key, so a failure '
                         'there is neither undone nor named' % (label, RESCUE_FILE))
            continue
        key = keys[0]
        seen[key] = seen.get(key, 0) + 1
        if key not in entries:
            lines.append('FAIL %s names repository_key %s, which %s third_party_repositories does not '
                         'carry' % (label, key, vars_path.as_posix()))
        if not re.search(r'\binstall_%s\b' % re.escape(key), as_text(task.get('when'))):
            lines.append('FAIL %s is not gated on install_%s, so its repository is set up under one '
                         'toggle and decided under another' % (label, key))
        check_file = CHECK_FILES[family]
        checks = [t for t, _ in walk(task['block']) if include_target(t).endswith(check_file)
                  and (t.get('vars') or {}).get('repository_key') == key]
        if not checks:
            lines.append('FAIL %s does not fetch its own repository through %s, so a host that does '
                         'not answer is not caught by this block' % (label, check_file))
        if family == 'RedHat' and key in entries:
            repo_ids = (entries[key] or {}).get('repo_ids') or []
            if not repo_ids:
                lines.append('FAIL %s third_party_repositories entry %s has no repo_ids, so %s has '
                             'nothing to hand dnf' % (vars_path.as_posix(), key, check_file))
            for written, _ in walk(task['block']):
                module = written.get('ansible.builtin.yum_repository', written.get('yum_repository'))
                if isinstance(module, dict) and module.get('name') not in repo_ids:
                    lines.append('FAIL %s writes the dnf repository %s, which repo_ids for %s in %s '
                                 'does not name, so its metadata is never checked'
                                 % (label, module.get('name'), key, vars_path.as_posix()))
    for key in sorted(entries):
        added_by = (entries[key] or {}).get('added_by')
        if added_by:
            # Written outside the repository blocks, so it has none, and the file it names must be the
            # one that writes every path and every dnf id the entry claims.
            writer = pathlib.Path(added_by)
            writer_text = writer.read_text(encoding='utf-8') if writer.is_file() else ''
            if not writer_text:
                lines.append('FAIL %s third_party_repositories entry %s says it is added by %s, which '
                             'is not a file in this repository' % (vars_path.as_posix(), key, added_by))
                continue
            claimed = list((entries[key] or {}).get('files') or [])
            claimed += ['[%s]' % repo_id for repo_id in (entries[key] or {}).get('repo_ids') or []]
            for needle in claimed:
                if needle not in writer_text:
                    lines.append('FAIL %s third_party_repositories entry %s names %s, which %s never '
                                 'writes, so the entry checks a file nothing creates'
                                 % (vars_path.as_posix(), key, needle, added_by))
            if seen.get(key, 0):
                lines.append('FAIL %s third_party_repositories entry %s is added by %s and also has a '
                             'block in %s, which is two places adding it'
                             % (vars_path.as_posix(), key, added_by, repos_file))
            continue
        if seen.get(key, 0) != 1:
            lines.append('FAIL %s third_party_repositories carries %s, and %s has %d blocks for it '
                         'instead of exactly one' % (vars_path.as_posix(), key, repos_file, seen.get(key, 0)))

# --- 2a. every repository file written under setup/ has an entry ----------------------------------
# Until 2026-10-10 the per-repository recheck before the first apt cache refresh covered only the
# entries above, while setup.sh wrote charm.list for gum and the waydroid role wrote waydroid.list,
# and the refresh still read both, so a dead repo.charm.sh stopped the play in the pre_tasks. Any
# literal sources or .repo path anything under setup/ writes must be an entry's file, or one of the
# distribution's own files, so the next one cannot be left out the same way.
SOURCE_PATHS = {
    'Debian': re.compile(r'/etc/apt/sources\.list\.d/[A-Za-z0-9_.:-]+\.(?:list|sources)\b'),
    'RedHat': re.compile(r'/etc/yum\.repos\.d/[A-Za-z0-9_.:-]+\.repo\b'),
}
written_paths = 0
for family, pattern in SOURCE_PATHS.items():
    vars_path = ANSIBLE / 'vars' / ('%s.yaml' % family)
    vars_doc = yaml.safe_load(vars_path.read_text(encoding='utf-8')) or {}
    known = set(vars_doc.get('distribution_sources_files') or [])
    for entry in (vars_doc.get('third_party_repositories') or {}).values():
        known |= set((entry or {}).get('files') or [])
    writers = [pathlib.Path('setup') / 'setup.sh'] + sorted(ANSIBLE.rglob('*.yaml'))
    for writer in writers:
        if writer.parent.name == 'vars':
            continue
        try:
            text = writer.read_text(encoding='utf-8')
        except (OSError, UnicodeDecodeError):
            continue
        for found in sorted(set(pattern.findall(text))):
            written_paths += 1
            if found not in known:
                lines.append('FAIL %s names the repository file %s, which no %s third_party_repositories '
                             'entry and no distribution_sources_files entry names, so nothing that checks '
                             'the repositories of this project one at a time knows about it, and on Debian one '
                             'dead host behind it stops the first apt cache refresh of a run'
                             % (writer.as_posix(), found, vars_path.as_posix()))
if written_paths == 0:
    lines.append('FAIL no repository file path was found anywhere under setup/, so the parser lost them')
# An entry another file adds is not one the software installer could fail to add, so the decider must
# leave it out, or Waydroid's repository, which its role writes later in the run, reads as unavailable.
if 'added_by' not in as_text(docs.get(FACTS['unavailable_repositories']['decider'], [])):
    lines.append('FAIL %s does not leave out the entries with added_by, so a repository setup.sh or a '
                 'later role adds is reported as one the software installer could not add'
                 % FACTS['unavailable_repositories']['decider'])

if repository_blocks == 0:
    lines.append('FAIL no repository block was found at all, so the repository half of this check '
                 'proves nothing')

# --- 2b. the first apt cache refresh of the run ---------------------------------------------------
site_play = yaml.safe_load((ANSIBLE / 'site.yaml').read_text(encoding='utf-8')) or []
pre_tasks = [t for play in site_play for t in (play.get('pre_tasks') or [])]
for task, _ in walk(pre_tasks):
    apt = task.get('ansible.builtin.apt', task.get('apt'))
    if isinstance(apt, dict) and apt.get('update_cache'):
        lines.append('FAIL %s :: %s refreshes the apt cache in the pre_tasks without %s, so one '
                     'third-party repository whose host is down stops the play before any rescue'
                     % (SITE, task.get('name', '<unnamed>'), APT_REFRESH))
if not any(include_target(t).endswith('tasks/apt_cache_refresh.yaml') for t, _ in walk(pre_tasks)):
    lines.append('FAIL the pre_tasks of %s do not include %s, so the first apt cache refresh of the '
                 'run does not check the third-party repositories already on the machine first'
                 % (SITE, APT_REFRESH))
refresh_tasks = docs.get(APT_REFRESH, [])
recheck_at = [i for i, t in enumerate(refresh_tasks) if include_target(t).endswith(RECHECK_FILE)]
apt_at = [i for i, t in enumerate(refresh_tasks)
          if any((c.get('ansible.builtin.apt') or c.get('apt') or {}).get('update_cache')
                 for c, _ in walk([t]))]
refresh_text = as_text(refresh_tasks)
if 'distribution_sources_files' not in refresh_text or '.installation-helper.disabled' not in refresh_text:
    lines.append('FAIL %s does not fetch the sources files this project does not manage on their own '
                 'and set aside one that does not answer, so a dead personal repository stops the play '
                 'in the pre_tasks' % APT_REFRESH)
site_always = [a for play in site_play for blk, _ in walk(play.get('tasks') or [])
               for a in (blk.get('always') or [])]
if not any(include_target(t).endswith('tasks/apt_sources_restore.yaml') for t in site_always):
    lines.append('FAIL the always section of %s does not include tasks/apt_sources_restore.yaml, so a '
                 'sources file set aside for the run is not put back' % SITE)
if len(recheck_at) != 1 or len(apt_at) != 1 or recheck_at[0] > apt_at[0]:
    lines.append('FAIL %s should include %s once and refresh the apt cache once, after it'
                 % (APT_REFRESH, RECHECK_FILE))
for task in refresh_tasks:
    if re.search(r'\binstall_', as_text(task.get('when')) + as_text(task.get('loop'))):
        lines.append('FAIL %s :: %s reads a toggle, so it checks only the repositories asked for in '
                     'this run while the refresh reads every sources file on the machine alike'
                     % (APT_REFRESH, task.get('name', '<unnamed>')))
recheck_blocks = [t for t in docs.get((SOFTWARE / RECHECK_FILE).as_posix(), []) if 'block' in t]
fetches = recheck_blocks and any(include_target(t).endswith(CHECK_FILES['Debian'])
                                 for t, _ in walk(recheck_blocks[0]['block']))
undoes = recheck_blocks and any(include_target(t).endswith(RESCUE_FILE)
                                for t, _ in walk(recheck_blocks[0].get('rescue') or []))
if len(recheck_blocks) != 1 or not fetches or not undoes:
    lines.append('FAIL %s should be one block that fetches through %s and rescues through %s, the '
                 'check and the rescue every repository block uses'
                 % ((SOFTWARE / RECHECK_FILE).as_posix(), CHECK_FILES['Debian'], RESCUE_FILE))

# --- 3. the per-package loops, and 4. everything else gated on a repository toggle --------------
repo_keys = set()
for family in ('Debian', 'RedHat'):
    entries = (yaml.safe_load((ANSIBLE / 'vars' / ('%s.yaml' % family)).read_text(encoding='utf-8'))
               or {}).get('third_party_repositories') or {}
    repo_keys |= {k for k, v in entries.items()
                  if not (v or {}).get('updates_only') and not (v or {}).get('added_by')}

loop_consumers = 0
toggle_consumers = 0
skip_list_setters = set()
for where, tasks in docs.items():
    for task, ancestors in walk(tasks):
        if 'block' in task:
            continue
        label = '%s :: %s' % (where, task.get('name', '<unnamed>'))
        when = combined_when(task, ancestors)
        set_fact = task.get('ansible.builtin.set_fact', task.get('set_fact'))
        if isinstance(set_fact, dict) and 'repository_skipped_packages' in set_fact:
            skip_list_setters.add(where)
            if 'unavailable_repositories' not in as_text(task) and set_fact['repository_skipped_packages'] != []:
                lines.append('FAIL %s builds repository_skipped_packages without reading '
                             'unavailable_repositories' % label)
        loop = as_text(task.get('loop'))
        # The apt and dnf lists go through setup/ansible/tasks/install_role_packages.yaml since
        # 2026-10-15, like the pacman list below, so the skip can sit in the include's vars as well as
        # in a when on a loop.
        for manager in ('apt', 'dnf'):
            if 'software_installer_batches.%s' % manager in loop + as_text(task.get('vars')):
                loop_consumers += 1
                if 'repository_skipped_packages' not in when + as_text(task.get('vars')):
                    lines.append('FAIL %s installs every %s package without skipping what '
                                 'repository_skipped_packages names, so a package whose repository '
                                 'could not be added is asked for anyway' % (label, manager))
        # The pacman list goes through setup/ansible/tasks/install_role_packages.yaml since 2026-10-15,
        # so it is filtered in the include's vars rather than skipped item by item in a when.
        pacman_list = loop + as_text(task.get('vars'))
        if 'software_installer_batches.pacman' in pacman_list:
            loop_consumers += 1
            reads = when + as_text(task.get('vars'))
            if 'steam_graphics_stack_aligned' not in reads or 'ih_steam_packages' not in reads:
                lines.append('FAIL %s installs every pacman package without reading both '
                             'steam_graphics_stack_aligned and ih_steam_packages, so Steam is asked for on '
                             'a CachyOS machine whose 32-bit graphics stack could not be aligned' % label)
        if where in NOT_CONSUMERS or where in ARCH_OR_MAC_ONLY or where == SITE:
            continue
        # An include is a container and set_fact or debug only report, so none of them can act on a
        # package that is not there.
        if module_of(task) in CONTAINER_MODULES or module_of(task) in REPORT_MODULES:
            continue
        if "ih_family == 'Archlinux'" in when or "ih_family == 'Darwin'" in when:
            continue
        for key in sorted(repo_keys):
            if re.search(r'\binstall_%s\b' % re.escape(key), when):
                toggle_consumers += 1
                if 'unavailable_repositories' not in when:
                    lines.append('FAIL %s is gated on install_%s, whose package comes from a '
                                 'third-party repository on Debian or Fedora, and does not read '
                                 'unavailable_repositories, so it acts on a package that was never '
                                 'installed when that repository could not be added' % (label, key))
                break

if skip_list_setters != {DYNAMIC}:
    lines.append('FAIL repository_skipped_packages is set in %s rather than only in %s'
                 % (', '.join(sorted(skip_list_setters)) or 'no file at all', DYNAMIC))
if loop_consumers < 3:
    lines.append('FAIL only %d per-package apt, dnf and pacman loops were found, fewer than the three '
                 'there are, so the parser lost them' % loop_consumers)

# --- 5. and 6. the two rescues ------------------------------------------------------------------
# The alignment installs mesa-git and lib32-mesa-git one per call since 2026-10-15, so the block is
# found by the task whose loop names both and whose command installs the loop item.
align_blocks = [t for t, _ in walk(docs.get(ARCH_CORE, []))
                if 'block' in t and any('pacman -S --needed {{ item' in as_text(c)
                                        and 'mesa-git' in as_text(c.get('loop'))
                                        and 'lib32-mesa-git' in as_text(c.get('loop'))
                                        for c, _ in walk(t['block']))]
if len(align_blocks) != 1:
    lines.append('FAIL %s should hold exactly one block around the CachyOS alignment and holds %d'
                 % (ARCH_CORE, len(align_blocks)))
else:
    rescue = as_text(align_blocks[0].get('rescue'))
    if 'steam_graphics_stack_aligned' not in rescue or 'any_role_failed' not in rescue or '[ERROR]' not in rescue:
        lines.append('FAIL the CachyOS alignment rescue in %s does not set steam_graphics_stack_aligned '
                     'false, any_role_failed and an [ERROR] line together' % ARCH_CORE)

site_blocks = [t for t, _ in walk(docs.get(SITE, [])) if 'block' in t]
env_blocks = [t for t in site_blocks if 'env_variables' in as_text(t.get('block'))
              and 'import_role' in as_text(t.get('block')) and len(t['block']) == 1]
sdk_blocks = [t for t in site_blocks if "name: sdk_manager" in as_text(t.get('block'))
              and len(t['block']) == 1]
if len(env_blocks) != 1:
    lines.append('FAIL %s should import env_variables in exactly one block and does so in %d'
                 % (SITE, len(env_blocks)))
else:
    rescue = as_text(env_blocks[0].get('rescue'))
    if 'fail' in [module_of(t) for t, _ in walk(env_blocks[0].get('rescue') or [])] \
            or 'ansible.builtin.fail' in rescue:
        lines.append('FAIL the env_variables rescue in %s fails the play again, which stops every '
                     'role after it' % SITE)
    if 'env_variables_available: false' not in rescue or 'any_role_failed: true' not in rescue:
        lines.append('FAIL the env_variables rescue in %s does not record the failure and set '
                     'env_variables_available false' % SITE)
if len(sdk_blocks) != 1:
    lines.append('FAIL %s should import sdk_manager in exactly one block and does so in %d'
                 % (SITE, len(sdk_blocks)))
elif 'env_variables_available' not in as_text(sdk_blocks[0].get('when')):
    lines.append('FAIL sdk_manager in %s is not gated on env_variables_available, so it runs after an '
                 'env_variables failure and installs SDKs no shell can find' % SITE)

if not lines:
    lines.append('OK %d repository blocks, %d per-package loops and %d other repository consumers all '
                 'read their fact, and each of the %d facts has one decider'
                 % (repository_blocks, loop_consumers, toggle_consumers, len(FACTS)))

print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "availability facts"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a skipped step is decided in more than one place or a consumer ignores it" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the availability check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "availability facts"
