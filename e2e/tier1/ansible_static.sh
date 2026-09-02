#!/usr/bin/env bash
#
# Tier 1: the playbook must parse, and it must parse quietly.
#
# The warning budget is the point. ansible.cfg once set `inventory = localhost,`, and
# because that setting is a comma-separated path list, the empty entry after the comma
# resolved to the config directory. Ansible then walked all of setup/ansible/ as an
# inventory source, tried to run callback_plugins/dual_logger.py as an inventory
# script, and printed 212 warnings on every invocation without an explicit -i. A real
# warning cannot be seen in that. See docs/regression_ledger.md.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/wsl_delegate.sh"

# Git Bash has no ansible-playbook, so this check re-runs itself inside WSL from there. The reasoning
# and the mechanism live in wsl_delegate.sh, shared with the other check that needs Ansible.
delegate_to_wsl_when_no_ansible e2e/tier1/ansible_static.sh

info "Tier 1: Ansible static checks"

cd "${ANSIBLE_DIR}" || { fail "cannot reach setup/ansible, so nothing below is checking the playbook" \
                        "${ANSIBLE_DIR}"; finish "Ansible static"; }

# Three of the blocks below run Python, and this file named it `${PYTHON:-python3}`, which is the
# mirror of the `${PYTHON:-python}` that made fourteen checks go quiet under WSL: it is Git Bash
# that has python and no python3. Resolved once here through the search common.sh owns, and if
# nothing answers then ansible-playbook, which is itself a Python program, cannot be here either.
require_python "the playbook, the tier 3 scenario files and the callback truncation" "Ansible static"

# --- syntax ------------------------------------------------------------------
syntax_out="$(ansible-playbook --syntax-check site.yaml 2>&1 || true)"
if grep -qE '^playbook: site\.yaml' <<<"${syntax_out}"; then
    pass "site.yaml parses"
else
    fail "site.yaml does not parse" "$(tail -5 <<<"${syntax_out}" | tr '\n' ' ')"
fi

# --- warning budget ----------------------------------------------------------
# Two warnings are correct and expected here: no inventory was passed, so only the
# implicit localhost exists and it does not match `all`. Anything beyond that is noise
# that will hide a real problem.
EXPECTED_WARNINGS=2
actual_warnings="$(grep -cE '\[WARNING\]|as an inventory source' <<<"${syntax_out}" || true)"
if [[ "${actual_warnings}" -le "${EXPECTED_WARNINGS}" ]]; then
    pass "syntax check emits at most ${EXPECTED_WARNINGS} warnings (got ${actual_warnings})"
else
    fail "syntax check emits ${actual_warnings} warnings, budget is ${EXPECTED_WARNINGS}" \
         "$(grep -E '\[WARNING\]|as an inventory source' <<<"${syntax_out}" | sort -u | head -5 | tr '\n' ' ')"
fi

# --- nothing may be parsed as inventory -------------------------------------
# Guards the specific failure above rather than only its symptom count.
if grep -qE 'as an inventory source|not a valid group definition' <<<"${syntax_out}"; then
    fail "files under setup/ansible are being parsed as inventory" \
         "$(grep -oE '[^ ]+ as an inventory source' <<<"${syntax_out}" | head -3 | tr '\n' ' ')"
else
    pass "no repository file is mistaken for an inventory source"
fi

# --- every verify and scenario file must parse too ---------------------------
# This was written as a loop over one filename, so the heading said "every" and the body checked one
# file. The scenario files existed on the day it was written and were never reached by it, which is
# what a loop that can only run once always means. They are not playbooks, so ansible-playbook is
# the wrong parser for them: they are variable files container.sh reads, and a broken one costs a
# tier 3 run its first twenty-five minutes before anything says why. So the playbook gets the
# playbook parser and the variable files get a YAML load, which is the whole of what they must
# survive. Finding none of them is a failure, since a scan over an empty set proves nothing.
if ansible-playbook --syntax-check "${E2E_ROOT}/tier3/verify.yaml" &>/dev/null; then
    pass "verify.yaml parses"
else
    fail "verify.yaml does not parse" \
         "$(ansible-playbook --syntax-check "${E2E_ROOT}/tier3/verify.yaml" 2>&1 | tail -3 | tr '\n' ' ')"
fi

scenario_status=0
scenario_probe="$("${PYTHON}" - "${E2E_ROOT}/tier3" <<'SCENARIOEOF'
import glob, os, sys

try:
    import yaml
except ImportError as exc:
    print("SKIP {}".format(exc))
    sys.exit(0)

root = sys.argv[1]
paths = sorted(glob.glob(os.path.join(root, "scenarios", "*.yaml")))
paths += sorted(glob.glob(os.path.join(root, "container_limits*.yaml")))
if not paths:
    print("FAIL no scenario or limits file was found under {}".format(root))
    sys.exit(0)

problems = []
for path in paths:
    try:
        with open(path, encoding="utf-8") as handle:
            document = yaml.safe_load(handle)
    except Exception as exc:
        problems.append("{}: {}".format(os.path.basename(path), str(exc).replace("\n", " ")))
        continue
    if not isinstance(document, dict):
        problems.append("{}: loads as {}, not as a mapping of variables".format(
            os.path.basename(path), type(document).__name__))

print("FAIL " + "; ".join(problems) if problems else "OK {}".format(len(paths)))
SCENARIOEOF
)" || scenario_status=$?
assert_python_ran "${scenario_status}" "Ansible static"
case "${scenario_probe}" in
    OK*)   pass "all ${scenario_probe#OK } tier 3 scenario and limits files load as YAML mappings" ;;
    SKIP*) skip "the tier 3 scenario and limits files load as YAML mappings" "${scenario_probe#SKIP }" ;;
    *)     fail "a tier 3 scenario or limits file does not load, so the scenario dies inside the container" \
                "${scenario_probe#FAIL }" ;;
esac

# --- every free-form module body survives split_args -------------------------
# The hole this closes cost every Linux run for eleven hours. ansible-playbook --syntax-check above
# passed while setup/ansible/roles/sdk_manager/tasks/pyenv_unix.yaml could not be loaded at all,
# because --syntax-check follows import_tasks and does not follow include_tasks, and that file is
# reached through the dynamic one. Every scenario died at parse time with "failed at splitting
# arguments, either an unbalanced jinja2 block or quotes" while the gate said the tree was fine.
#
# The cause is worth knowing before reading the check. Ansible runs split_args over a free-form
# module argument, the body of shell, command, raw and script, before anything executes, and it
# counts quotes across the entire string, comment lines included. Three words ending in apostrophe s
# inside a comment is an odd number of single quotes, and the file stops loading. Nothing about that
# is visible in a diff or in YAML validity.
#
# So every task file is walked here, including the ones no static analysis reaches, and every
# free-form body is handed to Ansible's own splitter rather than to a quote counter of my own.
# block, rescue and always are descended into, because a task nested in a rescue parses the same way
# and would otherwise be skipped by this.
ansible_python="$(head -1 "$(command -v ansible-playbook)" 2>/dev/null | sed 's/^#!//; s/ .*//')"
# The interpreter behind ansible-playbook is wanted here rather than any interpreter, because this
# probe imports ansible itself. The fallback is the one common.sh resolved, not a second search
# that can find nothing and take the script down on the assignment.
[[ -x "${ansible_python}" ]] || ansible_python="${PYTHON}"
split_status=0
split_probe="$("${ansible_python}" - "${ANSIBLE_DIR}" <<'PYEOF'
import pathlib, sys, yaml

try:
    from ansible.parsing.splitter import split_args
except Exception as exc:
    print("SKIP ansible is not importable from this interpreter: {}".format(exc))
    sys.exit(0)

FREEFORM = ("ansible.builtin.shell", "shell", "ansible.builtin.command", "command",
            "ansible.builtin.raw", "raw", "ansible.builtin.script", "script")

def walk(node):
    if isinstance(node, list):
        for item in node:
            for found in walk(item):
                yield found
    elif isinstance(node, dict):
        yield node
        for key in ("block", "rescue", "always"):
            if key in node:
                for found in walk(node[key]):
                    yield found

broken, bodies = [], 0
for path in sorted(pathlib.Path(sys.argv[1]).rglob("*.yaml")):
    try:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception as exc:
        # Reported, not skipped. Saying the syntax check owns this would repeat the mistake that
        # made this check necessary: it does not follow include_tasks, so an unparseable file
        # reached only that way is invisible to it too, and skipping here would hide it twice.
        broken.append("{}: will not parse as YAML at all ({})".format(
            path.name, str(exc).splitlines()[0]))
        continue
    for task in walk(doc):
        for key in FREEFORM:
            body = task.get(key)
            if isinstance(body, str):
                bodies += 1
                try:
                    split_args(body)
                except Exception as exc:
                    broken.append("{}: {} ({})".format(
                        path.name, task.get("name") or "unnamed task",
                        str(exc).splitlines()[0]))
if broken:
    print("FAIL " + " | ".join(broken))
else:
    print("OK {}".format(bodies))
PYEOF
)" || split_status=$?
assert_python_ran "${split_status}" "Ansible static"
case "${split_probe}" in
    OK*) pass "all ${split_probe#OK } free-form shell, command, raw and script bodies split cleanly, included files too" ;;
    SKIP*) skip "every free-form module body survives split_args" "${split_probe#SKIP }" ;;
    *) fail "a module body cannot be parsed, so the file it is in will not load at run time"             "${split_probe#FAIL }" ;;
esac

# --- the callback keeps the tail of a long block -----------------------------
# Asserted because losing it is silent. dual_logger truncates a task's stdout to
# STDOUT_TRUNCATE_LINES, and while it kept the head alone, the reason a failed command gave was
# thrown away before anything was written: apt prints its dependency list first and "E: Failed to
# fetch" last, so 29 lines of 1098 kept the noise and dropped the diagnosis. One Debian cell was
# unexplainable for exactly that reason.
#
# The real function is imported out of the plugin rather than reimplemented here, so this cannot
# pass against a copy while the plugin regresses.
trunc_status=0
trunc_probe="$("${PYTHON}" - "${ANSIBLE_DIR}/callback_plugins/dual_logger.py" <<'PYEOF'
import importlib.util, sys

spec = importlib.util.spec_from_file_location("dual_logger_probe", sys.argv[1])
module = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(module)
except Exception as exc:                      # ansible not importable here, for instance
    print("SKIP {}".format(exc))
    sys.exit(0)

truncate = module.CallbackModule._truncate_lines
limit = module.STDOUT_TRUNCATE_LINES
lines = ["line {}".format(n) for n in range(500)]
lines[-1] = "E: Failed to fetch"
out = truncate(lines, limit)

problems = []
if len(out) > limit:
    problems.append("returned {} lines for a limit of {}".format(len(out), limit))
if out[0] != "line 0":
    problems.append("dropped the head, first line is {!r}".format(out[0]))
if out[-1] != "E: Failed to fetch":
    problems.append("dropped the tail, last line is {!r}".format(out[-1]))
if not any("truncated" in ln for ln in out):
    problems.append("said nothing about the lines it removed")
short = ["only", "two", "lines"]
if truncate(short, limit) != short:
    problems.append("mangled a block shorter than the limit")
print("FAIL " + "; ".join(problems) if problems else "OK")
PYEOF
)" || trunc_status=$?
assert_python_ran "${trunc_status}" "Ansible static"
case "${trunc_probe}" in
    OK) pass "the callback keeps both the head and the tail when it truncates a long block" ;;
    SKIP*) skip "the callback keeps both ends when it truncates" "${trunc_probe#SKIP }" ;;
    *) fail "the callback truncation loses the end of a long block, which is where failures explain themselves"             "${trunc_probe#FAIL }" ;;
esac

# --- optional linters --------------------------------------------------------
# Reported, never required. Making the gate depend on a tool that may not be installed
# would mean the gate silently stops running, which is its own failure mode.
if command -v yamllint &>/dev/null; then
    if yamllint -d "{extends: relaxed, rules: {line-length: disable}}" "${ANSIBLE_DIR}" &>/dev/null; then
        pass "yamllint clean"
    else
        fail "yamllint reports problems" "$(yamllint -d '{extends: relaxed, rules: {line-length: disable}}' "${ANSIBLE_DIR}" 2>&1 | head -5 | tr '\n' ' ')"
    fi
else
    warn "yamllint not installed, skipping. Install with: pip install --user yamllint"
fi

if command -v ansible-lint &>/dev/null; then
    if ansible-lint --nocolor -q site.yaml &>/dev/null; then
        pass "ansible-lint clean"
    else
        warn "ansible-lint reports findings, not treated as a failure yet:"
        ansible-lint --nocolor -q site.yaml 2>&1 | head -15 | sed 's/^/       /'
    fi
else
    warn "ansible-lint not installed, skipping. Install with: pip install --user ansible-lint"
fi

finish "Ansible static checks"
