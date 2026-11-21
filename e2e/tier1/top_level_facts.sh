#!/usr/bin/env bash
#
# Tier 1: the playbook reads a fact only through ansible_facts, never as a top-level ansible_<fact>
# variable, and it still works when ansible-core stops injecting the facts as variables.
#
# ansible-core 2.20 and later print `[DEPRECATION WARNING]: INJECT_FACTS_AS_VARS default to `True` is
# deprecated` for every top-level fact a run reads, and the 2.21.5 source of ansible/vars/manager.py
# names 2.24 as the release that turns the setting off. From then on ansible_env, ansible_user_id,
# ansible_distribution and every other top-level fact is undefined, and a task that reads one stops the
# play. GitHub runs 44334164246 and 44334171501 printed the warning for group_vars/all.yaml:199:16,
# non_root_user, and sixteen more reads sat in four roles, docs/regression_ledger.md 10.379.
#
# Two halves.
#
# The static half reads every YAML file and template under setup/ansible/, e2e/tier1/ and e2e/tier3/ the
# way YAML does, parses every Jinja expression in them with Jinja's own parser, the text inside {{ }} and
# {% %} and the whole of a when, changed_when, failed_when, until, that or var, and fails a variable
# whose name starts with ansible_ and is not a magic variable, a connection variable, ansible_facts or
# one of the two variables a rescue gets. It fails the same name read through hostvars or vars, through
# lookup('vars'), or as a key of ansible_facts, where the facts carry no prefix, and a set_fact, vars,
# register or loop_var that defines a variable under such a name. The fixtures that hand facts to a
# lifted task, the Python under e2e/lib/ and the scripts under e2e/tier1/, fail a dictionary key or an
# extra variable under such a name, because a fixture that feeds ansible_architecture hides a task that
# reads it. The allowed names are the magic variables and connection variables of the special
# variables page of the Ansible documentation, read on 2026-11-21, every name in MAGIC_VARIABLE_MAPPING
# of the installed ansible-core, and ansible_failed_task and ansible_failed_result, which the strategy
# plugin sets for a rescue. Before it reads the repository it runs its reader against planted files and
# requires it to name exactly the planted reads, and it fails when it reads fewer files or fewer reads
# of ansible_facts than it was written against. It also reads OS_CONDITION_REGEX out of
# setup/ansible/callback_plugins/dual_logger.py and fails a name in it that no when condition of the
# playbook holds, because the callback hides a skip as "not for this OS" by those names, and
# ansible_system and os_family stayed in it long after the conditions stopped reading them,
# docs/regression_ledger.md 10.384.
#
# The runtime half runs ansible-playbook on this machine's own facts with the facts not injected,
# which e2e/lib/common.sh sets for every check, so every lifted task any check runs reads them the way
# a future ansible-core will. It first proves the setting is in force, ansible_env undefined and
# ansible_facts['env'] defined, then proves that setup/ansible/ansible.cfg alone, with the variable of
# common.sh taken away, keeps the facts from being injected too, because every run setup.sh starts reads
# that file and no other. Then it renders non_root_user out of the shipped group_vars/all.yaml, then
# requires every key the playbook reads through ansible_facts to be one this machine's facts carry, and
# every top-level ansible_<fact> name the static half found to resolve, which it cannot.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd ansible-playbook
require_python "the playbook reads facts only through ansible_facts" "top-level facts"

LABEL="top-level facts"
SELF="${BASH_SOURCE[0]##*/}"

info "Tier 1: the playbook reads facts only through ansible_facts and runs with the facts not injected"

work_dir="$(mktemp -d)"
cleanup() { rm -rf -- "${work_dir}"; }
trap cleanup EXIT

report_status=0
report="$("${PYTHON}" - "${REPO_ROOT}" "${SELF}" "${work_dir}/reads.json" <<'PYEOF'
import ast
import json
import pathlib
import re
import sys

import jinja2
import jinja2.nodes as nodes
import yaml

REPO = pathlib.Path(sys.argv[1])
SELF = sys.argv[2]
READS_OUT = pathlib.Path(sys.argv[3])

try:
    from ansible import constants as ansible_constants
    MAPPED = {name for names in getattr(ansible_constants, 'MAGIC_VARIABLE_MAPPING', {}).values() for name in names}
except ImportError:
    MAPPED = set()
if not MAPPED:
    print('FAIL MAGIC_VARIABLE_MAPPING of the installed ansible-core named no connection variable, so the '
          'allowed names cannot be read')
    sys.exit(0)

DOCUMENTED = {
    'ansible_check_mode', 'ansible_collection_name', 'ansible_config_file', 'ansible_dependent_role_names',
    'ansible_diff_mode', 'ansible_forks', 'ansible_index_var', 'ansible_inventory_sources', 'ansible_limit',
    'ansible_loop', 'ansible_loop_var', 'ansible_parent_role_names', 'ansible_parent_role_paths',
    'ansible_play_batch', 'ansible_play_hosts', 'ansible_play_hosts_all', 'ansible_play_name',
    'ansible_play_role_names', 'ansible_playbook_python', 'ansible_role_name', 'ansible_role_names',
    'ansible_run_tags', 'ansible_search_path', 'ansible_skip_tags', 'ansible_verbosity', 'ansible_version',
    'ansible_become_user', 'ansible_connection', 'ansible_host', 'ansible_python_interpreter', 'ansible_user',
}
RESCUE = {'ansible_failed_task', 'ansible_failed_result'}
ALLOWED = DOCUMENTED | MAPPED | RESCUE | {'ansible_facts'}

BARE = {'when', 'changed_when', 'failed_when', 'until', 'that', 'var'}
SET_FACT = {'set_fact', 'ansible.builtin.set_fact', 'ansible.legacy.set_fact'}
VARIABLE_FILE = re.compile(r'(^|/)(group_vars|host_vars|defaults|vars)/')
EXPRESSION = re.compile(r'\{\{.*?\}\}', re.S)
FIXTURE_KEY = re.compile(r'''(["'])(ansible_[a-z0-9_]+)\1\s*:''')
FIXTURE_EXTRA = re.compile(r'''(?:-e|--extra-vars)[\s=]+["']?(ansible_[a-z0-9_]+)=''')
ENVIRONMENT = jinja2.Environment(extensions=['jinja2.ext.do', 'jinja2.ext.loopcontrols'])


def is_fact_name(name):
    return name.startswith('ansible_') and name not in ALLOWED


def const_text(node):
    return node.value if isinstance(node, nodes.Const) and isinstance(node.value, str) else None


def expression_reads(tree):
    """(top-level fact names, keys read through ansible_facts, other wrong reads) of one parsed template."""
    top, keys, other = [], [], []
    for node in tree.find_all(nodes.Name):
        if is_fact_name(node.name):
            top.append(node.name)
    for node in tree.find_all((nodes.Getitem, nodes.Getattr)):
        key = const_text(node.arg) if isinstance(node, nodes.Getitem) else node.attr
        base = node.node
        if isinstance(base, nodes.Name) and base.name == 'ansible_facts':
            if key is None:
                continue
            if key.startswith('ansible_'):
                other.append("ansible_facts key '%s', where the facts carry no ansible_ prefix" % key)
            else:
                keys.append(key)
            continue
        if key is None or not is_fact_name(key):
            continue
        through_hostvars = isinstance(base, nodes.Getitem) and isinstance(base.node, nodes.Name) \
            and base.node.name == 'hostvars'
        through_vars = isinstance(base, nodes.Name) and base.name == 'vars'
        if through_hostvars or through_vars:
            other.append('%s read through %s' % (key, 'hostvars' if through_hostvars else 'vars'))
    for node in tree.find_all(nodes.Call):
        if isinstance(node.node, nodes.Name) and node.node.name in ('lookup', 'query', 'q'):
            arguments = [const_text(a) for a in node.args]
            if arguments and arguments[0] in ('vars', 'ansible.builtin.vars'):
                other += ["%s read through lookup('vars')" % a for a in arguments[1:] if a and is_fact_name(a)]
    return top, keys, other


def scalars(node, key=None, parent=None):
    """(scalar node, its key, the key of the mapping holding it) for every scalar of a YAML node."""
    if isinstance(node, yaml.ScalarNode):
        yield node, key, parent
    elif isinstance(node, yaml.SequenceNode):
        for item in node.value:
            yield from scalars(item, key, parent)
    elif isinstance(node, yaml.MappingNode):
        for key_node, value_node in node.value:
            name = key_node.value if isinstance(key_node, yaml.ScalarNode) else None
            yield key_node, '<key>', key
            yield from scalars(value_node, name, key)


def read_yaml(rel, text, sink):
    for document in yaml.compose_all(text, Loader=yaml.SafeLoader):
        if document is None:
            continue
        if VARIABLE_FILE.search(rel) and isinstance(document, yaml.MappingNode):
            for key_node, _ in document.value:
                if isinstance(key_node, yaml.ScalarNode) and is_fact_name(key_node.value):
                    sink['problems'].append('%s:%d defines a variable named %s, the name of a fact'
                                            % (rel, key_node.start_mark.line + 1, key_node.value))
        for node, key, parent in scalars(document):
            line = node.start_mark.line + 1
            if node.tag != 'tag:yaml.org,2002:str':
                continue
            value = node.value
            if key == 'when':
                sink['conditions'].append((rel, ' '.join(value.split())))
            if key == '<key>':
                if (parent in SET_FACT or parent == 'vars') and is_fact_name(value):
                    sink['problems'].append('%s:%d defines a variable named %s, the name of a fact' % (rel, line, value))
                continue
            if key in ('register', 'loop_var') and is_fact_name(value.strip()):
                sink['problems'].append('%s:%d defines a variable named %s, the name of a fact'
                                        % (rel, line, value.strip()))
                continue
            if key in BARE and '{{' not in value and '{%' not in value:
                source = '{{ ' + value + ' }}'
            elif '{{' in value or '{%' in value or '{#' in value:
                source = value
            else:
                continue
            read_template(rel, line, source, sink, strict=key != 'var')


def read_template(rel, line, source, sink, strict):
    try:
        tree = ENVIRONMENT.parse(source)
    except jinja2.TemplateSyntaxError as error:
        if strict:
            sink['problems'].append('%s:%d does not parse as Jinja, so nothing in it was read: %s' % (rel, line, error))
        return
    sink['expressions'] += 1
    top, keys, other = expression_reads(tree)
    for name in top:
        sink['problems'].append('%s:%d reads %s, a top-level fact, where ansible_facts[%r] is meant'
                                % (rel, line, name, name[len('ansible_'):]))
        sink['top'].add(name)
    for text in other:
        sink['problems'].append('%s:%d reads %s' % (rel, line, text))
    sink['keys'].update(keys)
    sink['fact_reads'] += len(keys)


def read_fixture(rel, text, sink):
    for pattern in (FIXTURE_KEY, FIXTURE_EXTRA):
        for match in pattern.finditer(text):
            name = match.group(match.lastindex)
            if is_fact_name(name):
                sink['problems'].append('%s:%d hands a lifted task a variable named %s, the name of a fact, which '
                                        'no ansible-core defines once facts are not injected'
                                        % (rel, text.count('\n', 0, match.start()) + 1, name))
    for match in EXPRESSION.finditer(text):
        read_template(rel, text.count('\n', 0, match.start()) + 1, match.group(), sink, strict=False)


def new_sink():
    return {'problems': [], 'top': set(), 'keys': set(), 'expressions': 0, 'fact_reads': 0, 'conditions': []}


PLANTED_YAML = r"""
- name: every way a task reads a top-level fact
  ansible.builtin.set_fact:
    one: "{{ ansible_env.HOME }}"
    two: >-
      {{ ansible_facts['env'].HOME | default(ansible_user_id) }}
    three: "{{ hostvars[inventory_hostname]['ansible_distribution'] }}"
    four: "{{ lookup('ansible.builtin.vars', 'ansible_os_family') }}"
    five: "{{ ansible_facts.ansible_architecture }}"
    ansible_kernel: "{{ ansible_facts['kernel'] }}"
    sound_one: "{{ ansible_facts['env'].HOME }} {{ ansible_check_mode }} {{ job.ansible_job_id }}"
    sound_two: plain text naming ansible_env outside Jinja
    sound_three: !unsafe "{{ ansible_env }}"
    sound_four: "{% raw %}{{ ansible_env }}{% endraw %}"
    sound_five: "{{ ansible_play_hosts | length }} {{ ansible_loop.index | default(0) }} {{ ansible_become_user }}"
  when: ansible_system == 'Linux'
  register: ansible_hostname
- name: a rescue reads what the strategy sets
  ansible.builtin.debug:
    msg: "{{ ansible_failed_task.name }} {{ ansible_failed_result.msg | default('') }}"
  when:
    - ansible_facts['system'] == 'Linux'
"""
PLANTED_TEMPLATE = "{# ansible_env #}{{ ansible_date_time.iso8601 }} {{ ansible_facts['date_time'].iso8601 }}\n"
PLANTED_FIXTURE = """
'vars': {'ansible_facts': {'system': 'Linux'}, 'ansible_distribution': 'Debian', 'ansible_become': False},
ansible-playbook -e ansible_become=false -e ansible_machine=x86_64 play.yaml
ansible_python="$(command -v python3)"
docker ps --format '{{.Names}}'
"""
planted = new_sink()
read_yaml('planted.yaml', PLANTED_YAML, planted)
read_template('planted.j2', 1, PLANTED_TEMPLATE, planted, strict=True)
read_fixture('planted.sh', PLANTED_FIXTURE, planted)
wanted = ['reads ansible_env,', 'reads ansible_user_id,', 'ansible_distribution read through hostvars',
          'ansible_os_family read through lookup', "ansible_facts key 'ansible_architecture'",
          'defines a variable named ansible_kernel', 'reads ansible_system,', 'defines a variable named ansible_hostname',
          'reads ansible_date_time,', 'variable named ansible_distribution', 'variable named ansible_machine']
named = [next((p for p in planted['problems'] if w in p), None) for w in wanted]
if len(planted['problems']) != len(wanted) or None in named:
    print('FAIL the reader, run against planted files, named %d reads where it must name exactly the %d planted ones: %s'
          % (len(planted['problems']), len(wanted), ' | '.join(planted['problems']) or 'none'))
    sys.exit(0)
planted_conditions = [text for _, text in planted['conditions']]
if planted_conditions != ["ansible_system == 'Linux'", "ansible_facts['system'] == 'Linux'"]:
    print('CALLBACK_FAIL the reader, run against planted files, collected the when conditions %r where it must '
          'collect the one written as a string and the one written as a list' % planted_conditions)
    sys.exit(0)

sink = new_sink()
files = 0
roots = [REPO / 'setup' / 'ansible', REPO / 'e2e' / 'tier1', REPO / 'e2e' / 'tier3']
for root in roots:
    for path in sorted(root.rglob('*')):
        if not path.is_file() or path.suffix not in ('.yaml', '.yml', '.j2'):
            continue
        rel = path.relative_to(REPO).as_posix()
        files += 1
        text = path.read_text(encoding='utf-8')
        if path.suffix == '.j2':
            read_template(rel, 1, text, sink, strict=True)
            continue
        try:
            read_yaml(rel, text, sink)
        except yaml.YAMLError as error:
            sink['problems'].append('%s does not parse as YAML: %s' % (rel, error))

shipped_keys, shipped_reads = set(sink['keys']), sink['fact_reads']
fixtures = sorted((REPO / 'e2e' / 'lib').glob('*.py')) + sorted((REPO / 'e2e' / 'tier1').rglob('*.sh')) \
    + sorted((REPO / 'e2e' / 'tier1').rglob('*.py'))
for path in fixtures:
    if path.name == SELF:
        continue
    files += 1
    read_fixture(path.relative_to(REPO).as_posix(), path.read_text(encoding='utf-8'), sink)

if files < 100 or shipped_reads < 100:
    print('FAIL the reader read %d files and %d reads of ansible_facts, fewer than it was written against, so '
          'nothing is proven' % (files, shipped_reads))
    sys.exit(0)
for problem in sink['problems']:
    print('FAIL %s' % problem)
if not sink['problems']:
    print('OK the %d Jinja expressions of the %d files read name no top-level fact, read %d facts through '
          'ansible_facts, and the reader named the %d planted reads' % (sink['expressions'], files, shipped_reads, len(wanted)))

CALLBACK = 'setup/ansible/callback_plugins/dual_logger.py'
os_pattern = None
for node in ast.walk(ast.parse((REPO / CALLBACK).read_text(encoding='utf-8'))):
    if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'OS_CONDITION_REGEX' for t in node.targets) \
            and isinstance(node.value, ast.Call) and node.value.args and isinstance(node.value.args[0], ast.Constant) \
            and isinstance(node.value.args[0].value, str):
        os_pattern = node.value.args[0].value
shipped_conditions = [text for rel, text in sink['conditions'] if rel.startswith('setup/ansible/')]
if os_pattern is None or re.search(r'[\\()\[\]?*+{}^$.]', os_pattern):
    print('CALLBACK_FAIL OS_CONDITION_REGEX in %s is not a literal string of names joined by |, so the names it '
          'hides a skip by cannot be read: %r' % (CALLBACK, os_pattern))
elif len(shipped_conditions) < 500:
    print('CALLBACK_FAIL the reader collected %d when conditions under setup/ansible/, fewer than it was written '
          'against, so nothing is proven about OS_CONDITION_REGEX' % len(shipped_conditions))
else:
    names = os_pattern.split('|')
    dead = [name for name in names if not any(name in text for text in shipped_conditions)]
    for name in dead:
        print('CALLBACK_FAIL OS_CONDITION_REGEX in %s names %s, which no when condition under setup/ansible/ '
              'holds, so the callback can never hide a skip by it and the condition it was meant for reads '
              'another name' % (CALLBACK, name))
    if not dead:
        print('CALLBACK_OK every one of the %d names of OS_CONDITION_REGEX in %s is in a when condition of the '
              'playbook, of the %d read' % (len(names), CALLBACK, len(shipped_conditions)))
READS_OUT.write_text(json.dumps({'ih_fact_keys': sorted(shipped_keys | {'env'}),
                                 'ih_top_level_names': sorted(sink['top'])}), encoding='utf-8')
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "${LABEL}"

while IFS= read -r line; do
    case "${line}" in
        CALLBACK_OK*)   pass "${line#CALLBACK_OK }" ;;
        CALLBACK_FAIL*) fail "the callback hides a skip as not for this OS only by names a condition holds" "${line#CALLBACK_FAIL }" ;;
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "the playbook reads facts only through ansible_facts" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the top-level fact reader printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

if [[ ! -s "${work_dir}/reads.json" ]]; then
    fail "the reader handed the runtime half the facts the playbook reads" "nothing was written to reads.json"
    finish "${LABEL}"
fi

# --- the runtime half ------------------------------------------------------------------------------

cat >"${work_dir}/play.yaml" <<EOF
- hosts: localhost
  connection: local
  gather_facts: true
  vars_files:
    - ${ANSIBLE_DIR}/group_vars/all.yaml
  tasks:
    - name: Ask whether the facts are injected as top-level variables
      ansible.builtin.debug:
        msg: "IH_INJECTION ansible_env={{ 'undefined' if ansible_env is undefined else 'defined' }} env={{ 'defined' if ansible_facts['env'] is defined else 'undefined' }}"
    - name: Render non_root_user out of the shipped group_vars/all.yaml
      ansible.builtin.debug:
        msg: "IH_NON_ROOT_USER={{ non_root_user }}"
      ignore_errors: true
    - name: Ask for every key the playbook reads through ansible_facts
      ansible.builtin.debug:
        msg: "IH_FACT_KEY {{ item }} {{ 'resolves' if item in ansible_facts else 'UNDEFINED' }}"
      loop: "{{ ih_fact_keys }}"
    - name: Ask for every top-level fact name the reader found
      ansible.builtin.debug:
        msg: "IH_TOP_LEVEL {{ item }} {{ 'UNDEFINED' if lookup('ansible.builtin.vars', item, default='IH_ABSENT') == 'IH_ABSENT' else 'resolves' }}"
      loop: "{{ ih_top_level_names }}"
EOF

play_status=0
play_out="$(ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_FORCE_COLOR=0 \
    ansible-playbook -i localhost, "${work_dir}/play.yaml" -e "@${work_dir}/reads.json" 2>&1)" || play_status=$?

if [[ ${play_status} -ne 0 ]]; then
    fail "the play that renders the facts with ANSIBLE_INJECT_FACT_VARS=${ANSIBLE_INJECT_FACT_VARS:-unset} finished" \
         "ansible-playbook exited ${play_status}: $(grep -E 'fatal:|ERROR|undefined' <<<"${play_out}" | sed -n 1,3p | tr '\n' ' ')"
    finish "${LABEL}"
fi

injection="$(grep -oE 'IH_INJECTION ansible_env=[a-z]+ env=[a-z]+' <<<"${play_out}" | sed -n 1p || true)"
if [[ "${injection}" == "IH_INJECTION ansible_env=undefined env=defined" ]]; then
    pass "with ANSIBLE_INJECT_FACT_VARS=${ANSIBLE_INJECT_FACT_VARS:-unset} ansible_env is undefined and ansible_facts['env'] is defined, so every lifted task in the gate reads facts the way a future ansible-core gives them"
else
    fail "every check runs ansible-playbook with the facts not injected" \
         "ANSIBLE_INJECT_FACT_VARS is ${ANSIBLE_INJECT_FACT_VARS:-unset} here where e2e/lib/common.sh must export False, and the play answered '${injection:-nothing}'"
fi

cat >"${work_dir}/cfg_play.yaml" <<'EOF'
- hosts: localhost
  connection: local
  gather_facts: true
  tasks:
    - name: Ask whether the shipped ansible.cfg alone keeps the facts from being injected
      ansible.builtin.debug:
        msg: "IH_CFG_INJECTION ansible_env={{ 'undefined' if ansible_env is undefined else 'defined' }} env={{ 'defined' if ansible_facts['env'] is defined else 'undefined' }}"
EOF

cfg_status=0
cfg_out="$(env -u ANSIBLE_INJECT_FACT_VARS ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg" ANSIBLE_STDOUT_CALLBACK=default \
    ANSIBLE_CACHE_PLUGIN=memory ANSIBLE_FORCE_COLOR=0 ansible-playbook -i localhost, "${work_dir}/cfg_play.yaml" 2>&1)" \
    || cfg_status=$?
cfg_injection="$(grep -oE 'IH_CFG_INJECTION ansible_env=[a-z]+ env=[a-z]+' <<<"${cfg_out}" | sed -n 1p || true)"
if [[ ${cfg_status} -eq 0 && "${cfg_injection}" == "IH_CFG_INJECTION ansible_env=undefined env=defined" ]]; then
    pass "setup/ansible/ansible.cfg alone, with ANSIBLE_INJECT_FACT_VARS unset, keeps ansible_env undefined and ansible_facts['env'] defined, so every run setup.sh starts reads facts the way the gate does"
elif [[ ${cfg_status} -ne 0 ]]; then
    fail "the play that reads setup/ansible/ansible.cfg alone finished" \
         "ansible-playbook exited ${cfg_status}: $(grep -E 'ERROR|fatal:' <<<"${cfg_out}" | sed -n 1,2p | tr '\n' ' ')"
else
    fail "setup/ansible/ansible.cfg keeps the facts from being injected in every run setup.sh starts" \
         "with ANSIBLE_INJECT_FACT_VARS unset and ANSIBLE_CONFIG=setup/ansible/ansible.cfg the play answered '${cfg_injection:-nothing}', so inject_facts_as_vars = False is missing from its [defaults]"
fi

expected_user="${SUDO_USER:-$(id -un)}"
rendered_user="$(grep -oE 'IH_NON_ROOT_USER=[^"]*' <<<"${play_out}" | sed -n 1p || true)"
if [[ "${rendered_user}" == "IH_NON_ROOT_USER=${expected_user}" ]]; then
    pass "group_vars/all.yaml renders non_root_user as ${expected_user} with the facts not injected"
else
    fail "group_vars/all.yaml renders non_root_user with the facts not injected" \
         "expected ${expected_user}, got '${rendered_user#IH_NON_ROOT_USER=}': $(grep -oE "'[A-Za-z_]+' is undefined" <<<"${play_out}" | sort -u | tr '\n' ' ')"
fi

mapfile -t fact_lines < <(grep -oE 'IH_FACT_KEY [a-z0-9_]+ [A-Za-z]+' <<<"${play_out}" | sort -u)
absent=()
for entry in "${fact_lines[@]}"; do
    read -r _ key answer <<<"${entry}"
    [[ "${answer}" == resolves ]] || absent+=("${key}")
done
if [[ ${#fact_lines[@]} -lt 2 ]]; then
    fail "the play asked for the keys the playbook reads through ansible_facts" "it answered ${#fact_lines[@]} keys"
elif [[ ${#absent[@]} -eq 0 ]]; then
    pass "every one of the ${#fact_lines[@]} keys the playbook reads through ansible_facts is one this machine's facts carry"
else
    fail "every key the playbook reads through ansible_facts is one this machine's facts carry" \
         "absent: ${absent[*]}, so the read names no fact or a fact of another system"
fi

mapfile -t top_lines < <(grep -oE 'IH_TOP_LEVEL ansible_[a-z0-9_]+ [A-Za-z]+' <<<"${play_out}" | sort -u)
undefined_reads=()
for entry in "${top_lines[@]}"; do
    read -r _ name answer <<<"${entry}"
    [[ "${answer}" == UNDEFINED ]] && undefined_reads+=("${name}")
done
if [[ ${#undefined_reads[@]} -eq 0 ]]; then
    pass "no top-level fact name the playbook or a fixture reads comes back undefined with the facts not injected"
else
    fail "every top-level name the playbook and the fixtures read resolves with the facts not injected" \
         "undefined: ${undefined_reads[*]}, so every task reading one stops the play once ansible-core turns INJECT_FACTS_AS_VARS off"
fi

finish "${LABEL}"
