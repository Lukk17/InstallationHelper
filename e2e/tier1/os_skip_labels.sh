#!/usr/bin/env bash
#
# Tier 1: the callback leaves a skip out of every log as "not for this OS" only when the operating
# system decided it, and a skip the person caused, such as a toggle that is off, stays in
# installation_full.log and in installation_skipped.log.
#
# Until 2026-11-21 the callback hid a skip only when its false condition held distribution,
# architecture or virtualization_role as text, so the 193 conditions that test the family through
# ih_family or ih_base and the 60 that test the system through ansible_facts['system'] alone were
# written into the logs on every run, and a task named after a package manager was hidden whatever
# its condition said, docs/regression_ledger.md 10.385 and 10.387.
#
# Three halves.
#
# The probe lifts setup/ansible/callback_plugins/dual_logger.py and drives its real hooks with results
# shaped like the ones ansible-core sends, in-memory files standing in for the logs: the fact gathering
# and the derivation reporting a Debian machine, then skips of whole tasks and of install loop items
# for conditions that read only OS names, toggles, an OS test joined to a toggle with either side
# false, a false condition handed as a list, a condition the run has no OS values for yet, a negated
# toggle, a task named after a package manager, a loop whose every item was for another OS, and a
# condition that does not parse. The fact gathering hands its facts under the ansible_ prefix the
# setup module gives them, built from the bare keys, because no task reads them and top_level_facts
# fails a fixture key written under the name of a fact.
#
# The sweep hands every when condition under setup/ansible/ to the callback with no OS values known,
# and requires every condition that reads only the OS names the callback declares to be labelled not
# for this OS, and no other condition, so a condition the callback cannot read is named here.
#
# The run starts ansible-playbook through the shipped callback in a throwaway home, with the shipped
# setup/ansible/tasks/derive_os_facts.yaml deriving the gate's own family, and reads the logs it
# wrote, because only a real run shows what false_condition and the facts look like to the callback.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd ansible-playbook
require_python "the callback hides only the skips the operating system decided" "os skip labels"

LABEL="os skip labels"

info "Tier 1: the callback hides a skip as not for this OS only when the operating system decided it"

work_dir="$(mktemp -d)"
cleanup() { rm -rf -- "${work_dir}"; }
trap cleanup EXIT

probe_status=0
probe="$("${PYTHON}" - "${ANSIBLE_DIR}/callback_plugins/dual_logger.py" "${ANSIBLE_DIR}" <<'PYEOF'
import importlib.util
import io
import pathlib
import sys

import jinja2
import jinja2.nodes as nodes
import yaml

spec = importlib.util.spec_from_file_location("dual_logger_os_skip_probe", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
ANSIBLE = pathlib.Path(sys.argv[2])
HIDDEN = "not for this OS"
OS_VARIABLES = getattr(module, "OS_VARIABLES", frozenset())
OS_FACT_KEYS = getattr(module, "OS_FACT_KEYS", frozenset())
INSTALL = "software_installer : Install a package set one package at a time"
GATHERED = {"system": "Linux", "distribution": "Debian", "distribution_version": "13.2",
            "architecture": "x86_64", "virtualization_role": "host", "kernel": "6.12.0"}
DEBIAN_FACTS = {"ansible_" + key: value for key, value in GATHERED.items()}
DEBIAN_DERIVED = {"ih_family": "Debian", "ih_base": "debian", "ih_os_release_id": "debian",
                  "ih_supported_families": ["Debian", "RedHat", "Archlinux", "Darwin", "Windows"]}
TOGGLES = ("install_lm_studio", "install_virt_manager", "install_stable_diffusion")


class Named:
    def __init__(self, name, action=""):
        self.name = name
        self.action = action
        self.ignore_errors = False

    def get_name(self):
        return self.name


class Display:
    def display(self, text):
        pass


class KeptLog(io.StringIO):
    def close(self):
        pass


def result(task, action="ansible.builtin.debug", **fields):
    r = type("Result", (), {})()
    r._host = Named("localhost")
    r._task = Named(task, action)
    r._result = fields
    return r


def new_callback(debian):
    callback = module.CallbackModule()
    callback._display = Display()
    for name in ("full_log", "errors_log", "warnings_log", "skipped_log"):
        setattr(callback, name, KeptLog())
    callback._log_initialized = True
    if debian:
        callback.v2_runner_on_ok(result("Gathering Facts", "gather_facts", changed=False, ansible_facts=DEBIAN_FACTS))
        callback.v2_runner_on_ok(result("Derive the OS family this playbook will branch on", "ansible.builtin.set_fact",
                                        changed=False, ansible_facts=DEBIAN_DERIVED))
    return callback


def report(name, problems):
    print("FAIL\t{}\t{}".format(name, "; ".join(problems)) if problems else "PASS\t{}".format(name))


def send(hook, r, problems, what):
    try:
        hook(r)
    except Exception as error:
        problems.append("{!r} made the callback raise {}: {}".format(what, type(error).__name__, error))


def judge(cases, debian=True, item_too=True):
    """Skip a whole task and an install loop item for each case, and name every one logged otherwise than wanted."""
    callback = new_callback(debian)
    problems = []
    for number, (condition, _) in enumerate(cases):
        task = "probe_role : Probe task {}".format(number)
        send(callback.v2_runner_on_skipped, result(task, changed=False, false_condition=condition,
                                                   skip_reason="Conditional result was False"), problems, condition)
        if item_too:
            send(callback.v2_runner_item_on_skipped,
                 result(INSTALL, "ansible.builtin.raw", changed=False, item="probe-item-{}".format(number),
                        false_condition=condition, skip_reason="Conditional result was False"), problems, condition)
    full, skipped = callback.full_log.getvalue(), callback.skipped_log.getvalue()
    for number, (condition, wanted) in enumerate(cases):
        task_line = "skipping: [localhost] probe_role : Probe task {} [".format(number)
        item_line = "software_installer → probe-item-{} [".format(number)
        if wanted == HIDDEN:
            for where, text, needle in (("installation_full.log", full, "Probe task {} [".format(number)),
                                        ("installation_full.log", full, "probe-item-{} [".format(number)),
                                        ("installation_skipped.log", skipped, "probe-item-{} [".format(number))):
                if needle in text:
                    problems.append("{!r} reached {}".format(condition, where))
            continue
        if task_line + wanted + "]" not in full:
            got = next((line.split(task_line, 1)[1].rstrip("]") for line in full.splitlines() if task_line in line),
                       "no line at all")
            problems.append("{!r} logged the task as [{}], not [{}]".format(condition, got, wanted))
        if item_too and item_line + wanted + "]" not in skipped:
            problems.append("{!r} did not write the item into installation_skipped.log as [{}]".format(condition, wanted))
    return problems


missing_toggles = [name for name in TOGGLES if name not in new_callback(False)._toggles]
report("the toggles this probe uses are declared in group_vars, so the callback knows them",
       ["not declared: " + ", ".join(missing_toggles)] if missing_toggles else [])

report("a skip whose false condition reads only OS names is left out of installation_full.log and installation_skipped.log",
       judge([("ih_family == 'RedHat'", HIDDEN), ("ih_family in ['Archlinux', 'Darwin']", HIDDEN),
              ("ih_base == 'ubuntu'", HIDDEN), ("ih_os_release_id == 'cachyos'", HIDDEN),
              ("ih_family not in ih_supported_families", HIDDEN), ("ansible_facts['system'] == 'Darwin'", HIDDEN),
              ("ansible_facts.system == 'Darwin'", HIDDEN), ("ansible_facts['system'] | default('') == 'Darwin'", HIDDEN),
              ("ansible_facts['distribution'] == 'Ubuntu'", HIDDEN), ("ansible_facts['architecture'] == 'arm64'", HIDDEN),
              ("ansible_facts['distribution_version'] is version('15.0', '>=')", HIDDEN),
              ("ih_family == 'Debian' and ansible_facts['virtualization_role'] == 'guest'", HIDDEN),
              ("ansible_facts['architecture'] != 'arm64' or ansible_facts['distribution_version'] is version('15.0', '<')", HIDDEN)]))

report("a toggle that is off is logged as a disabled toggle",
       judge([("install_lm_studio | bool", "toggle disabled (install_lm_studio=false)"),
              ("install_virt_manager | default(false) | bool", "toggle disabled (install_virt_manager=false)")]))

report("an OS test joined to a toggle is judged by the part that was false",
       judge([("ansible_facts['system'] == 'Linux' and install_lm_studio | bool", "toggle disabled (install_lm_studio=false)"),
              ("ih_family != 'Windows' and install_stable_diffusion | bool", "toggle disabled (install_stable_diffusion=false)"),
              ("ih_family in ['Debian', 'RedHat', 'Archlinux'] and install_virt_manager | default(false) | bool",
               "toggle disabled (install_virt_manager=false)"),
              ("ansible_facts['system'] == 'Darwin' and install_virt_manager | default(false) | bool", HIDDEN),
              ("ih_family == 'Archlinux' and install_lm_studio | bool", HIDDEN),
              ("ansible_facts['system'] == 'Linux' and (install_kde_plasma | default(false) | bool or configure_kde_plasma | default(false) | bool)",
               "condition not met: ansible_facts['system'] == 'Linux' and (install_kde_plasma | default(false) | bool or configure_kde_plasma | default(false) | bool)"),
              ("ih_family == 'Debian' and 'openrazer' in (enabled_mapped | default([]))",
               "condition not met: ih_family == 'Debian' and 'openrazer' in (enabled_mapped | default([]))"),
              ("ih_family == 'Debian' and not (install_lm_studio | bool)",
               "condition not met: ih_family == 'Debian' and not (install_lm_studio | bool)")]))

report("a false condition handed as a list is judged item by item",
       judge([(["ih_family == 'Debian'", "install_lm_studio | bool"], "toggle disabled (install_lm_studio=false)"),
              (["ih_family == 'RedHat'", "install_lm_studio | bool"], HIDDEN),
              (["ih_family == 'RedHat'", False], "condition not met")]))

report("an OS test the run has not reported a value for hides nothing beside another part",
       judge([("ansible_facts['system'] == 'Linux' and install_lm_studio | bool",
               "condition not met: ansible_facts['system'] == 'Linux' and install_lm_studio | bool"),
              ("ansible_facts['system'] == 'Darwin' and install_lm_studio | bool",
               "condition not met: ansible_facts['system'] == 'Darwin' and install_lm_studio | bool"),
              ("ih_family == 'RedHat'", HIDDEN)], debian=False))

report("a condition that does not parse is named as it is",
       judge([("ih_family ==", "condition not met: ih_family ==")]))

callback = new_callback(True)
NAMED = (("site : Clean Flatpak unused runtimes", "not (ih_picked_apps_run | bool)"),
         ("site : Clean APT cache (Debian)", "playbook_succeeded | bool"),
         ("ai_tools : Install Claude Desktop via AUR (Arch Linux)", "claude_desktop_arch_check.rc != 0"))
for task, condition in NAMED:
    callback.v2_runner_on_skipped(result(task, changed=False, false_condition=condition,
                                         skip_reason="Conditional result was False"))
full = callback.full_log.getvalue()
report("a task named after a package manager is judged by its condition, not by its name",
       ["{!r} is not logged as condition not met: {}".format(task, condition) for task, condition in NAMED
        if "skipping: [localhost] {} [condition not met: {}]".format(task, condition) not in full])

callback = new_callback(True)
LOOP_OS = "software_installer : Install the Arch Linux probe packages"
LOOP_TOGGLE = "software_installer : Install the toggled probe packages"
callback.v2_runner_on_skipped(result(LOOP_OS, changed=False, msg="All items skipped", results=[
    {"item": "alpha", "false_condition": "ih_family == 'Archlinux' and item == 'alpha'"},
    {"item": "beta", "false_condition": "ih_family == 'Archlinux' and item == 'alpha'"}]))
callback.v2_runner_on_skipped(result(LOOP_TOGGLE, changed=False, msg="All items skipped", results=[
    {"item": "gamma", "false_condition": "ih_family == 'Debian' and install_lm_studio | bool"}]))
full = callback.full_log.getvalue()
problems = []
if LOOP_OS in full:
    problems.append("the loop whose every item was for Arch Linux left a line in installation_full.log")
if "skipping: [localhost] {} [every item skipped]".format(LOOP_TOGGLE) not in full:
    problems.append("the loop whose item was skipped by a toggle left no 'every item skipped' line")
report("a loop whose every item was for another OS leaves no task line, and any other loop does", problems)

ENVIRONMENT = jinja2.Environment(extensions=["jinja2.ext.do", "jinja2.ext.loopcontrols"])


def scalars(node, key=None):
    if isinstance(node, yaml.ScalarNode):
        yield node, key
    elif isinstance(node, yaml.SequenceNode):
        for item in node.value:
            yield from scalars(item, key)
    elif isinstance(node, yaml.MappingNode):
        for key_node, value_node in node.value:
            yield from scalars(value_node, key_node.value if isinstance(key_node, yaml.ScalarNode) else None)


def reads_only_os(tree):
    names = [read.name for read in tree.find_all(nodes.Name)]
    keys = [read.attr if isinstance(read, nodes.Getattr) else getattr(read.arg, "value", None)
            for read in tree.find_all((nodes.Getitem, nodes.Getattr))
            if isinstance(read.node, nodes.Name) and read.node.name == "ansible_facts"]
    return bool(names) and set(names) <= OS_VARIABLES | {"ansible_facts"} \
        and len(keys) == names.count("ansible_facts") and set(keys) <= OS_FACT_KEYS


conditions = []
for path in sorted(ANSIBLE.rglob("*")):
    if path.is_file() and path.suffix in (".yaml", ".yml"):
        for document in yaml.compose_all(path.read_text(encoding="utf-8"), Loader=yaml.SafeLoader):
            for node, key in scalars(document) if document is not None else ():
                if key == "when" and node.tag == "tag:yaml.org,2002:str":
                    conditions.append(("{}:{}".format(path.relative_to(ANSIBLE.parent.parent).as_posix(),
                                                      node.start_mark.line + 1), " ".join(node.value.split())))
callback = new_callback(False)
problems, pure = [], 0
for where, text in conditions:
    try:
        only_os = reads_only_os(ENVIRONMENT.parse("{{ " + text + " }}"))
    except jinja2.TemplateSyntaxError as error:
        problems.append("{} does not parse as Jinja: {}".format(where, error))
        continue
    pure += only_os
    label = callback._categorise_skip(result("probe_role : Sweep", false_condition=text), None)
    if only_os and label != HIDDEN:
        problems.append("{} reads only OS names and is labelled [{}]: {}".format(where, label, text))
    elif not only_os and label == HIDDEN:
        problems.append("{} reads more than OS names and is hidden with no OS value known: {}".format(where, text))
if len(conditions) < 500 or pure < 250:
    problems.append("the sweep read {} when conditions, {} of them only OS names, fewer than it was written against".format(
        len(conditions), pure))
report("every when condition under setup/ansible/ that reads only OS names is hidden, and no other, of {} read, {} of them only OS names".format(
    len(conditions), pure), problems)
PYEOF
)" || probe_status=$?
assert_python_ran "${probe_status}" "${LABEL}"

while IFS=$'\t' read -r verdict name detail; do
    case "${verdict}" in
        PASS) pass "${name}" ;;
        FAIL) fail "${name}" "${detail}" ;;
        *)    [[ -n "${verdict}" ]] && fail "the callback probe printed something unexpected" "${verdict} ${name} ${detail}" ;;
    esac
done <<<"${probe}"

# --- the run ---------------------------------------------------------------------------------------

cat >"${work_dir}/play.yaml" <<EOF
- hosts: localhost
  connection: local
  gather_facts: true
  vars:
    install_lm_studio: false
    install_virt_manager: true
  pre_tasks:
    - ansible.builtin.import_tasks: ${ANSIBLE_DIR}/tasks/derive_os_facts.yaml
  tasks:
    - name: IHPROBE_OS family of another family
      ansible.builtin.debug: {msg: never}
      when: ih_family == 'IHPROBE_NO_FAMILY'
    - name: IHPROBE_OS system of another system
      ansible.builtin.debug: {msg: never}
      when: ansible_facts['system'] == 'IHPROBE_NO_SYSTEM'
    - name: IHPROBE_OS another system beside a toggle that is on
      ansible.builtin.debug: {msg: never}
      when: ansible_facts['system'] == 'IHPROBE_NO_SYSTEM' and install_virt_manager | default(false) | bool
    - name: IHPROBE_OS a list whose family item is false
      ansible.builtin.debug: {msg: never}
      when:
        - ih_family == 'IHPROBE_NO_FAMILY'
        - install_virt_manager | bool
    - name: Install IHPROBE_OS packages of another family
      ansible.builtin.debug: {msg: "{{ item }}"}
      loop: [alpha, beta]
      when: ih_family == 'IHPROBE_NO_FAMILY' and item == 'alpha'
    - name: IHPROBE_TOGGLE this system beside a toggle that is off
      ansible.builtin.debug: {msg: never}
      when: ansible_facts['system'] == ansible_facts['system'] and ih_family == ih_family and install_lm_studio | bool
    - name: IHPROBE_TOGGLE a list whose toggle item is false
      ansible.builtin.debug: {msg: never}
      when:
        - ih_family == ih_family
        - install_lm_studio | bool
    - name: Install IHPROBE_TOGGLE packages
      ansible.builtin.debug: {msg: "{{ item }}"}
      loop: [gamma]
      when: ih_family == ih_family and install_lm_studio | bool
EOF

home="${work_dir}/home"
mkdir -p "${home}"
run_status=0
run_out="$(env -u SUDO_USER HOME="${home}" ANSIBLE_CALLBACK_PLUGINS="${ANSIBLE_DIR}/callback_plugins" \
    ANSIBLE_STDOUT_CALLBACK=dual_logger ANSIBLE_FORCE_COLOR=0 \
    ansible-playbook -i localhost, "${work_dir}/play.yaml" 2>&1)" || run_status=$?
full_log="${home}/installation_full.log"
skipped_log="${home}/installation_skipped.log"

if [[ ${run_status} -ne 0 || ! -s "${full_log}" || ! -f "${skipped_log}" ]]; then
    fail "a real play through the shipped callback finished and wrote installation_full.log" \
         "ansible-playbook exited ${run_status}: $(grep -E 'ERROR|fatal:' <<<"${run_out}" | sed -n 1,3p | tr '\n' ' ')"
    finish "${LABEL}"
fi

full="$(<"${full_log}")"
skipped="$(<"${skipped_log}")"
if [[ "${full}" != *"TASK [Derive the OS family this playbook will branch on]"* ]]; then
    fail "the real play derived the family through the shipped derive_os_facts.yaml" "installation_full.log has no line for that task"
fi
if [[ "${full}" == *IHPROBE_OS* || "${skipped}" == *alpha* || "${skipped}" == *beta* ]]; then
    fail "a real run leaves the tasks and items for another family or system out of installation_full.log and installation_skipped.log" \
         "$(grep -E 'IHPROBE_OS|alpha|beta' "${full_log}" "${skipped_log}" | sed -n 1,4p | tr '\n' ' ')"
else
    pass "a real run leaves the tasks and items for another family or system out of installation_full.log and installation_skipped.log"
fi
toggle_label="[toggle disabled (install_lm_studio=false)]"
missing=()
for needle in "IHPROBE_TOGGLE this system beside a toggle that is off ${toggle_label}" \
              "IHPROBE_TOGGLE a list whose toggle item is false ${toggle_label}" "skipped: [localhost] gamma ${toggle_label}"; do
    [[ "${full}" == *"${needle}"* ]] || missing+=("${needle}")
done
[[ "${skipped}" == *"gamma ${toggle_label}"* ]] || missing+=("installation_skipped.log: gamma ${toggle_label}")
if [[ ${#missing[@]} -eq 0 ]]; then
    pass "a real run logs every skip of a toggle that is off as a disabled toggle, in installation_full.log and installation_skipped.log"
else
    fail "a real run logs every skip of a toggle that is off as a disabled toggle, in installation_full.log and installation_skipped.log" "missing: ${missing[*]}"
fi

finish "${LABEL}"
