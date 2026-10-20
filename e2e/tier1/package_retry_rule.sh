#!/usr/bin/env bash
#
# Tier 1: every package manager on every system follows one retry rule.
#
# The rule, decided by the owner on 2026-10-15: one attempt with no package index refresh, then for a
# package that failed, wait, refresh that manager's own package index, and try again, four attempts in
# all, twenty seconds apart, and name every package still missing. A manager with no local index only
# waits. setup/ansible/tasks/install_role_packages.yaml holds the rule for the playbook,
# setup/windows/WindowsSoftware.ps1 for Windows, and install_one in each docs/manual/<os>/install.sh for
# the by-hand route.
#
# Before it, each install had its own numbers and none refreshed anything: apt and dnf retried the same
# command four times against the same stale index, flatpak four times, snap three, Homebrew four, the
# AUR five a minute apart, npm three, and thirty-odd single packages in the roles went through a package
# module with no retry at all, or with one whose failure stopped the role. A mirror that is behind the
# index answers 404 for a file, and asking again against the same index answers 404 again.
#
# Four parts, each able to fail on its own:
#   1. The rule's own numbers and refreshes in the shared file: retries 3, delay 20, and the refresh
#      each manager has, none for snap, never an install inside a refresh.
#   2. Every package install under setup/ansible goes through the shared file, except a manager with no
#      local index (the AUR helpers, npm, pip and pipx, SDKMAN, nvm, sdkmanager), which must retry three times
#      twenty seconds apart through until. No caller passes role_packages_retry_delay or
#      role_packages_log, which exist only for part 3.
#   3. The shared file run for real against a fake of each manager: a package that installs at once is
#      tried once and nothing is refreshed, a package that installs only after a refresh is refreshed
#      before its second attempt, a package that never installs is tried four times and named, and an
#      already installed snap counts as installed whatever snap exits.
#   4. install_one in each manual script, sourced and run against the same fakes, does the same, with
#      the same numbers, and the Arch script's refresh is a full upgrade, never a bare -Syy.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd ansible-playbook

info "Tier 1: every package manager follows the one retry rule"

cd "${REPO_ROOT}" || { fail "cannot reach the repository root" "${REPO_ROOT}"; finish "package retry rule"; }

require_python "every package manager follows the one retry rule" "package retry rule"

SHARED="setup/ansible/tasks/install_role_packages.yaml"

report_status=0
report="$("${PYTHON}" - "${SHARED}" <<'PYEOF'
import json
import pathlib
import re
import sys

import yaml

shared = pathlib.Path(sys.argv[1])
lines = []

# --- part 1: the rule itself ---------------------------------------------------------------------
REFRESH = {
    'apt': (r'\bapt-get update$', 'apt-get update'),
    'dnf': (r'^dnf makecache --refresh$', 'dnf makecache --refresh'),
    'rpm_url': (r'^dnf makecache --refresh$', 'dnf makecache --refresh, because dnf resolves what the rpm requires'),
    'pacman': (r'^pacman -Syy --noconfirm$', 'pacman -Syy on its own'),
    'flatpak': (r'^flatpak update --system --appstream\b', 'flatpak update --appstream'),
    'snap': (r'^$', 'no refresh, snapd keeps no index'),
    'brew': (r'\bbrew update$', 'brew update'),
    'brew_cask': (r'\bbrew update$', 'brew update'),
}
INSTALL_VERB = re.compile(r'\binstall\b|pacman\s+-S(?!y)')


def walk(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for item in node:
            yield from walk(item)


try:
    shared_doc = yaml.safe_load(shared.read_text(encoding='utf-8'))
except (OSError, yaml.YAMLError) as exc:
    print('FAIL %s cannot be read, so the rule cannot be checked: %s' % (shared, exc))
    raise SystemExit(0)

rule = next((t.get('ansible.builtin.set_fact', {}).get('role_packages_rule') for t in walk(shared_doc)
             if isinstance(t, dict) and isinstance(t.get('ansible.builtin.set_fact'), dict)
             and 'role_packages_rule' in t['ansible.builtin.set_fact']), None)
if not isinstance(rule, dict):
    lines.append('FAIL %s settles no role_packages_rule, so there is no one rule to hold anything to' % shared)
    rule = {}
if rule.get('retries') != 3:
    lines.append('FAIL %s gives the rule retries %r, and the rule is three retries after the first '
                 'attempt, four in all' % (shared, rule.get('retries')))
if str(rule.get('delay', '')).replace(' ', '') != '{{role_packages_retry_delay|default(20)}}':
    lines.append('FAIL %s gives the rule delay %r, and the rule is twenty seconds' % (shared, rule.get('delay')))

managers = next((t['vars']['role_packages_managers'] for t in walk(shared_doc)
                 if isinstance(t, dict) and isinstance(t.get('vars'), dict)
                 and 'role_packages_managers' in t['vars']), {})
for manager, (pattern, wanted) in sorted(REFRESH.items()):
    entry = managers.get(manager)
    if not isinstance(entry, dict):
        lines.append('FAIL %s has no command for %s, so nothing in the playbook can install through it '
                     'under the rule' % (shared, manager))
        continue
    refresh = re.sub(r'\{\{.*?\}\}', '', str(entry.get('refresh', ''))).strip()
    if not re.search(pattern, refresh):
        lines.append('FAIL %s refreshes %s with %r before a retry, and the rule asks for %s'
                     % (shared, manager, entry.get('refresh'), wanted))
    if refresh and INSTALL_VERB.search(refresh):
        lines.append('FAIL %s refreshes %s with %r, which installs as well, so a refresh is no longer only '
                     'a refresh' % (shared, manager, refresh))
for manager in sorted(set(managers) - set(REFRESH)):
    lines.append('FAIL %s has a command for %s, which this check does not know the refresh of. Add it here '
                 'with the refresh its documentation names' % (shared, manager))

retry_tasks = [t for t in walk(shared_doc) if isinstance(t, dict) and str(t.get('name', '')).startswith('Retry')]
if not retry_tasks:
    lines.append('FAIL %s has no task named Retry ..., so nothing retries' % shared)
for task in retry_tasks:
    body = str(task.get('ansible.builtin.raw', ''))
    if body.find('refresh') < 0 or body.find('refresh') > body.find('.install'):
        lines.append('FAIL %s :: %s does not refresh before it installs' % (shared, task['name']))
    if str(task.get('retries', '')).replace(' ', '') != '{{role_packages_rule.retries-1}}':
        lines.append('FAIL %s :: %s retries %r times, not the rule\'s retries less the first attempt'
                     % (shared, task['name'], task.get('retries')))

# --- part 2: every install goes through the rule -------------------------------------------------
INDEXED_MODULES = {'apt', 'ansible.builtin.apt', 'dnf', 'ansible.builtin.dnf', 'pacman',
                   'community.general.pacman', 'package', 'ansible.builtin.package', 'yum',
                   'ansible.builtin.yum', 'homebrew', 'community.general.homebrew', 'homebrew_cask',
                   'community.general.homebrew_cask', 'flatpak', 'community.general.flatpak', 'snap',
                   'community.general.snap'}
UNINDEXED_MODULES = {'kewlfft.aur.aur': 'the AUR', 'community.general.npm': 'npm', 'npm': 'npm',
                     'ansible.builtin.pip': 'pip', 'pip': 'pip', 'community.general.pipx': 'pipx'}
SHELLS = {'command', 'ansible.builtin.command', 'shell', 'ansible.builtin.shell', 'raw', 'ansible.builtin.raw'}
INDEXED_COMMAND = re.compile(r'(?<![\w-])(?:pacman\s+-S[uyw]*\s+(?!-*c)|pacman\s+-S\s|apt-get\s+install|apt\s+install'
                             r'|dnf\s+(?:-y\s+)?install|flatpak\s+install(?!.*--bundle)|snap\s+install'
                             r'|brew\s+install)')
UNINDEXED_COMMAND = {re.compile(r'(?<![\w-])(?:paru|yay)\s+-S'): 'the AUR',
                     re.compile(r'(?<![\w-])npm\s+(?:i|install)\b'): 'npm',
                     re.compile(r'(?<![\w-])pipx\s+install\b'): 'pipx',
                     re.compile(r'(?<![\w-])pip3?\s+install\b'): 'pip',
                     re.compile(r'(?<![\w-])sdk\s+install\b'): 'SDKMAN',
                     re.compile(r'(?<![\w-])nvm\s+install\b'): 'nvm',
                     re.compile(r'(?<![\w-])sdkmanager(?:\.bat)?\s+(?!-)\S'): 'sdkmanager'}


def tasks(node, inherited_retry_pair=False):
    if isinstance(node, dict):
        if any(k in node for k in ('block', 'rescue', 'always')):
            for k in ('block', 'rescue', 'always'):
                yield from tasks(node.get(k))
            return
        yield node
    elif isinstance(node, list):
        for item in node:
            yield from tasks(item)


def body_of(task, key):
    value = task[key]
    if isinstance(value, dict):
        value = value.get('cmd') or value.get('_raw_params') or ' '.join(map(str, value.get('argv') or []))
    return str(value)


def retries_by_rule(task):
    return (str(task.get('retries')) == '3' and str(task.get('delay')) == '20' and 'until' in task)


REFRESH_FIRST = re.compile(r'(?<![\w-])(?:apt-get update|dnf makecache|pacman -Syy|flatpak update --appstream'
                           r'|brew update)\b[^\n]*?(?:&&|;|\n)\s*\S')


def own_retry_pair(task, file_tasks, key):
    """The rule written out by hand, for an install that needs something the shared file cannot give
    it, such as answers on stdin: a first attempt with no retries, and a sibling task named Retry ...
    whose body refreshes the index on its own invocation before installing, with the rule's three
    attempts after the first, twenty seconds apart."""
    def is_retry(candidate):
        body = next((body_of(candidate, k) for k in SHELLS if k in candidate), '')
        return (str(candidate.get('name', '')).startswith('Retry') and REFRESH_FIRST.search(body)
                and str(candidate.get('retries')) == '2' and str(candidate.get('delay')) == '20'
                and 'until' in candidate)
    if str(task.get('name', '')).startswith('Retry'):
        return bool(is_retry(task))
    return 'retries' not in task and any(is_retry(other) for other in file_tasks if other is not task)


read = installs = 0
for path in sorted(pathlib.Path('setup/ansible').rglob('*.yaml')):
    if path == shared:
        continue
    try:
        doc = yaml.safe_load(path.read_text(encoding='utf-8'))
    except (yaml.YAMLError, UnicodeDecodeError):
        continue
    file_tasks = [t for t in tasks(doc) if isinstance(t, dict) and isinstance(t.get('name'), str)]
    for task in file_tasks:
        read += 1
        label = '%s :: %s' % (path.as_posix(), task['name'])
        task_vars = task.get('vars') if isinstance(task.get('vars'), dict) else {}
        for key in ('role_packages_retry_delay', 'role_packages_log'):
            if key in task_vars:
                lines.append('FAIL %s passes %s, which only the e2e fake package manager runs may set, so '
                             'this set does not follow the rule\'s numbers' % (label, key))
        for key, value in task.items():
            if key in INDEXED_MODULES and isinstance(value, dict) and value.get('state') not in ('absent', 'latest') \
                    and (value.get('name') or value.get('pkg')):
                installs += 1
                lines.append('FAIL %s installs through %s, which cannot refresh the package index between '
                             'its own retries. Install it through %s' % (label, key, shared))
            if key in UNINDEXED_MODULES and isinstance(value, dict) and value.get('state') != 'absent':
                installs += 1
                if not retries_by_rule(task):
                    lines.append('FAIL %s installs from %s, which keeps no index to refresh, so the rule is '
                                 'three retries twenty seconds apart through until, and it has retries %r '
                                 'and delay %r' % (label, UNINDEXED_MODULES[key], task.get('retries'),
                                                   task.get('delay')))
            if key in SHELLS:
                text = body_of(task, key)
                if INDEXED_COMMAND.search(text):
                    installs += 1
                    if own_retry_pair(task, file_tasks, key):
                        continue
                    lines.append('FAIL %s installs with a command the rule covers, %r, outside %s, so its '
                                 'retry does not refresh the package index the way the rule says'
                                 % (label, INDEXED_COMMAND.search(text).group(0).strip(), shared))
                for pattern, tool in UNINDEXED_COMMAND.items():
                    if pattern.search(text):
                        installs += 1
                        if not retries_by_rule(task):
                            lines.append('FAIL %s installs with %s, which keeps no index to refresh, so the '
                                         'rule is three retries twenty seconds apart through until, and it '
                                         'has retries %r and delay %r' % (label, tool, task.get('retries'),
                                                                          task.get('delay')))
                        break

if not read or not installs:
    lines.append('FAIL %d tasks and %d package installs were read under setup/ansible, so part 2 proves '
                 'nothing' % (read, installs))
if not lines:
    lines.append('OK the rule is retries 3 and delay 20 with each manager\'s own refresh, and every one of '
                 '%d package installs in %d tasks follows it' % (installs, read))
print('\n'.join(lines))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "package retry rule"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "a package install does not follow the one retry rule" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the retry rule check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

# --- the fakes, shared by parts 3 and 4 ----------------------------------------------------------
# One script answering as every manager. It writes each call to FAKE_PM_LOG. A package called ok-*
# installs, flaky-* installs only once that manager has refreshed after its last failed attempt, or on
# its second attempt for snap, which has no index and stands for a transient failure,
# broken-* never installs, and present-* prints the manager's own already-present words, with snap
# exiting 1 as the Arch container measured.
work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT
mkdir -p "${work}/bin"
cat > "${work}/bin/fakepm" <<'FAKE'
#!/usr/bin/env bash
tool="$(basename "$0")"
log="${FAKE_PM_LOG:?}"
case "${tool} $*" in
    "apt-get update"*|"dnf makecache"*|"pacman -Syy"*|"pacman -Syu"*|"flatpak update"*|"brew update"*)
        echo "${tool} refresh" >> "${log}"; echo "refreshed"; exit 0 ;;
esac
package="${!#}"
echo "${tool} install ${package}" >> "${log}"
case "${package}" in
    ok-*) echo "Installing ${package}"; exit 0 ;;
    present-*)
        case "${tool}" in
            apt-get) echo "0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded." ;;
            dnf) echo "Nothing to do." ;;
            pacman) echo " there is nothing to do" ;;
            flatpak) echo "Skipping: ${package} is already installed" ;;
            snap) echo "error: snap \"${package}\" is already installed, see 'snap help refresh'" >&2; exit 1 ;;
            *) echo "Warning: ${package} is already installed" >&2 ;;
        esac
        exit 0 ;;
    flaky-*)
        if [[ "${tool}" == snap && "$(grep -c "^${tool} install ${package}$" "${log}")" -gt 1 ]]; then
            echo "${package} installed"; exit 0
        fi
        last_fail="$(grep -n "^${tool} install ${package}$" "${log}" | tail -2 | head -1 | cut -d: -f1)"
        last_refresh="$(grep -n "^${tool} refresh$" "${log}" | tail -1 | cut -d: -f1)"
        if [[ -n "${last_refresh}" && "$(grep -c "^${tool} install ${package}$" "${log}")" -gt 1 \
              && "${last_refresh}" -gt "${last_fail}" ]]; then
            echo "Installing ${package}"; exit 0
        fi
        echo "error: failed retrieving file '${package}' from mirror : 404" >&2; exit 1 ;;
esac
echo "error: target not found: ${package}" >&2
exit 1
FAKE
chmod +x "${work}/bin/fakepm"
for tool in apt-get dnf pacman flatpak snap brew; do ln -s fakepm "${work}/bin/${tool}"; done
printf '#!/usr/bin/env bash\nexec "$@"\n' > "${work}/bin/sudo"
chmod +x "${work}/bin/sudo"

# calls <log> <tool> <package> -> the number of install attempts of that package
calls() { grep -c "^$2 install $3$" "$1" || true; }

# refreshed_between <log> <tool> <package> -> yes when a refresh of that tool sits between the
# package's first and second attempt
refreshed_between() {
    awk -v tool="$2" -v pkg="$3" '
        $0 == tool " install " pkg { seen++; if (seen == 2) { print (refresh ? "yes" : "no"); exit } next }
        seen == 1 && $0 == tool " refresh" { refresh = 1 }' "$1"
}

# judge <label> <log> <tool> <manager-has-index> <missing-list-text>
judge() {
    local label="$1" log="$2" tool="$3" indexed="$4" missing="$5" problems=() suffix="$6"
    [[ "$(calls "${log}" "${tool}" "ok-${suffix}")" -eq 1 ]] \
        || problems+=("ok-${suffix} was tried $(calls "${log}" "${tool}" "ok-${suffix}") times, not once")
    [[ "$(calls "${log}" "${tool}" "flaky-${suffix}")" -eq 2 ]] \
        || problems+=("flaky-${suffix} was tried $(calls "${log}" "${tool}" "flaky-${suffix}") times, not twice")
    [[ "$(calls "${log}" "${tool}" "broken-${suffix}")" -eq 4 ]] \
        || problems+=("broken-${suffix} was tried $(calls "${log}" "${tool}" "broken-${suffix}") times, not four")
    [[ "$(calls "${log}" "${tool}" "present-${suffix}")" -eq 1 ]] \
        || problems+=("present-${suffix}, already installed, was tried $(calls "${log}" "${tool}" "present-${suffix}") times, not once")
    if [[ "${indexed}" == yes ]]; then
        [[ "$(refreshed_between "${log}" "${tool}" "flaky-${suffix}")" == yes ]] \
            || problems+=("flaky-${suffix} was retried without a refresh of ${tool}'s index before it")
        local first_refresh first_flaky
        first_refresh="$(grep -n "^${tool} refresh$" "${log}" | head -1 | cut -d: -f1 || true)"
        first_flaky="$(grep -n "^${tool} install flaky-${suffix}$" "${log}" | head -1 | cut -d: -f1 || true)"
        [[ -n "${first_refresh}" && -n "${first_flaky}" && "${first_refresh}" -gt "${first_flaky}" ]] \
            || problems+=("${tool} refreshed before any attempt had failed")
    elif grep -q "^${tool} refresh$" "${log}"; then
        problems+=("${tool} keeps no index and something refreshed it")
    fi
    [[ "${missing}" == *"broken-${suffix}"* ]] || problems+=("broken-${suffix} is not named as missing")
    for name in ok flaky present; do
        [[ "${missing}" != *"${name}-${suffix}"* ]] || problems+=("${name}-${suffix} is named as missing")
    done
    if [[ ${#problems[@]} -eq 0 ]]; then
        pass "${label}"
    else
        fail "${label}" "$(printf '%s; ' "${problems[@]}")calls: $(tr '\n' ' ' < "${log}")"
    fi
}

# --- part 3: the shared file, run for real --------------------------------------------------------
cat > "${work}/play.yaml" <<'PLAY'
- hosts: localhost
  connection: local
  gather_facts: false
  vars:
    ih_family: Debian
  tasks:
    - name: Run the real shared file against the fake manager
      ansible.builtin.include_tasks:
        file: "{{ repo }}/setup/ansible/tasks/install_role_packages.yaml"
      vars:
        role_packages: ["ok-x", "flaky-x", "broken-x", "present-x"]
        role_packages_purpose: the fake set
        role_packages_manager: "{{ manager }}"
        role_packages_retry_delay: 0
        role_packages_log: "{{ fake_log }}"
    - name: Report what the shared file left behind
      ansible.builtin.debug:
        msg: "FAKE-RESULT missing={{ role_packages_missing | join(',') }} failed={{ any_role_failed | default(false) }} reasons={{ not_installed_with_reason | default([]) | join(',') }}"
PLAY

for manager in apt dnf pacman flatpak snap brew brew_cask; do
    case "${manager}" in
        apt) tool=apt-get ;; brew_cask) tool=brew ;; *) tool="${manager}" ;;
    esac
    indexed=yes
    [[ "${manager}" == snap ]] && indexed=no
    log="${work}/${manager}.log"
    : > "${log}"
    out="$(FAKE_PM_LOG="${log}" PATH="${work}/bin:${PATH}" ANSIBLE_STDOUT_CALLBACK=default \
        ansible-playbook "${work}/play.yaml" -i localhost, \
        -e ansible_become=false -e "repo=${REPO_ROOT}" -e "manager=${manager}" \
        -e "fake_log=${work}/${manager}.tee" </dev/null 2>&1)" || true
    missing="$(grep -o 'FAKE-RESULT missing=[^ ]*' <<<"${out}" | head -1 || true)"
    if [[ -z "${missing}" ]]; then
        fail "the shared file runs against a fake ${manager}" "the play did not finish: $(grep -m3 -E 'ERROR|fatal' <<<"${out}" | tr '\n' ' ')"
        continue
    fi
    if ! grep -q 'failed=True' <<<"$(grep -o 'FAKE-RESULT.*' <<<"${out}" | head -1 || true)" \
        || ! grep -qE '\[ERROR\] ([a-z-]+, )*broken-x(, [a-z-]+)*, from the fake set' <<<"${out}"; then
        fail "${manager}: a package that never installs fails the run and is named in an [ERROR] line" \
             "$(grep -o 'FAKE-RESULT[^"]*' <<<"${out}" | head -1)"
    fi
    judge "${manager}: one attempt without a refresh, then wait, $([[ ${indexed} == yes ]] && echo "refresh ${tool}'s index, " )retry, four attempts, the failure named" \
        "${log}" "${tool}" "${indexed}" "${missing}" x
done

# --- part 4: install_one in the manual scripts ----------------------------------------------------
# The rule's numbers are the shared file's: retries 3 is four attempts, and the delay is twenty seconds.
for script in docs/manual/arch/install.sh docs/manual/debian-ubuntu/install.sh docs/manual/fedora/install.sh docs/manual/macos/install.sh; do
    if [[ ! -f "${script}" ]]; then
        fail "${script} exists" "the manual route cannot be checked without it"
        continue
    fi
    attempts="$(sed -nE 's/^INSTALL_ATTEMPTS=([0-9]+)$/\1/p' "${script}")"
    delay="$(sed -nE 's/^INSTALL_RETRY_DELAY=([0-9]+)$/\1/p' "${script}")"
    if [[ "${attempts}" != 4 || "${delay}" != 20 ]]; then
        fail "${script}: install_one tries four times, twenty seconds apart, as the shared file does" \
             "INSTALL_ATTEMPTS=${attempts:-unset} INSTALL_RETRY_DELAY=${delay:-unset}"
        continue
    fi
    # The definitions only, never the script's own top level, which would install for real.
    functions="${work}/$(basename "$(dirname "${script}")").functions"
    awk '/^(install_one|refresh_[a-z_]+|no_refresh)\(\) \{/ { copy = 1 } copy { print } copy && /(^|; )}$/ { copy = 0 }' \
        "${script}" > "${functions}"
    if ! grep -q '^install_one() {' "${functions}"; then
        fail "${script}: install_one is defined" "no install_one() { ... } block was found"
        continue
    fi
    refreshers="$(grep -oE '^refresh_[a-z_]+' "${functions}" | sort -u)"
    if [[ -z "${refreshers}" ]]; then
        fail "${script}: each manager has a refresh function install_one calls before a retry" "none was found"
        continue
    fi
    if [[ "${script}" == *arch* ]] && ! grep -A3 '^refresh_pacman() {' "${functions}" | grep -qE 'pacman -Syu\b'; then
        fail "${script}: the pacman refresh before a retry is a full upgrade" \
             "refresh_pacman must run pacman -Syu, because a bare -Syy followed by an install is a partial upgrade"
    fi
    for refresher in ${refreshers}; do
        case "${refresher}" in
            refresh_pacman) tool=pacman ;; refresh_apt) tool=apt-get ;; refresh_dnf) tool=dnf ;;
            refresh_flatpak) tool=flatpak ;; refresh_brew) tool=brew ;;
            *) fail "${script}: ${refresher} refreshes a manager this check knows" "add it to this check"; continue ;;
        esac
        log="${work}/manual-${tool}.log"
        : > "${log}"
        missing="$(FAKE_PM_LOG="${log}" PATH="${work}/bin:${PATH}" bash -c '
            set -uo pipefail
            INSTALL_ATTEMPTS=4 INSTALL_RETRY_DELAY=20
            FAILED=()
            source "$1"
            sleep() { echo "sleep $1" >> "${FAKE_PM_LOG}"; }
            shift 1
            refresher="$1" tool="$2"
            for package in ok-m flaky-m broken-m present-m; do
                install_one "${package}" "${refresher}" "${tool}" install "${package}" >/dev/null 2>&1
            done
            printf "%s\n" "${FAILED[*]:-}"' _ "${functions}" "${refresher}" "${tool}")"
        if [[ "$(grep -c '^sleep 20$' "${log}" || true)" -lt 1 ]]; then
            fail "${script}: ${refresher} retries wait twenty seconds" "no sleep 20 was seen: $(tr '\n' ' ' < "${log}")"
        fi
        judge "${script}: install_one with ${refresher} tries once without a refresh, then waits, refreshes, retries, four attempts, the failure named" \
            "${log}" "${tool}" yes "${missing}" m
    done
done

finish "package retry rule"
