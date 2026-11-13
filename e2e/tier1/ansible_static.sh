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

require_cmd ansible-playbook

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
         "$(grep -E '\[WARNING\]|as an inventory source' <<<"${syntax_out}" | sort -u | sed -n 1,5p | tr '\n' ' ')"
fi

# --- nothing may be parsed as inventory -------------------------------------
# Guards the specific failure above rather than only its symptom count.
if grep -qE 'as an inventory source|not a valid group definition' <<<"${syntax_out}"; then
    fail "files under setup/ansible are being parsed as inventory" \
         "$(grep -oE '[^ ]+ as an inventory source' <<<"${syntax_out}" | sed -n 1,3p | tr '\n' ' ')"
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

# --- the callback never drops a line the playbook marked as an error ---------
# The noise filter, IGNORE_PATTERNS, was applied to deliberate debug messages too, and the repository
# rescue's [ERROR] line said "the copy already installed", which is one of its patterns. So the whole
# line vanished from the console and from installation_errors.log, measured on 2026-10-10 in a Debian
# container. The real methods are driven end to end, display and both log files, with in-memory
# files standing in for installation_full.log and installation_errors.log. An earlier version of
# this probe replaced _write_log with a stub, so it proved the console kept the line while the real
# _write_log, which ran the same filter a second time, still dropped it from both files.
render_status=0
render_probe="$("${PYTHON}" - "${ANSIBLE_DIR}/callback_plugins/dual_logger.py" <<'PYEOF'
import importlib.util, io, sys

spec = importlib.util.spec_from_file_location("dual_logger_render_probe", sys.argv[1])
module = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(module)
except Exception as exc:                      # ansible not importable here, for instance
    print("SKIP {}".format(exc))
    sys.exit(0)

shown = []


class Display:
    def display(self, text):
        shown.append(text)


callback = module.CallbackModule()
callback._display = Display()
callback.full_log = io.StringIO()
callback.errors_log = io.StringIO()
callback.warnings_log = io.StringIO()
callback._log_initialized = True
noise = module.IGNORE_PATTERNS[0]
callback._render_message("[ERROR] The copy %s gets no updates.\nplain line %s" % (noise, noise), "INFO")
full_text = callback.full_log.getvalue()
errors_text = callback.errors_log.getvalue()

problems = []
if not any(text.strip().startswith("[ERROR]") and noise in text for text in shown):
    problems.append("dropped an [ERROR] line containing {!r} from the console".format(noise))
if not any(ln.strip().endswith("gets no updates.") and "[ERROR]" in ln for ln in full_text.splitlines()):
    problems.append("dropped an [ERROR] line containing {!r} from installation_full.log".format(noise))
if not any("[ERROR]" in ln and noise in ln for ln in errors_text.splitlines()):
    problems.append("dropped an [ERROR] line containing {!r} from installation_errors.log".format(noise))
if any(text.strip().startswith("plain line") for text in shown) or "plain line" in full_text:
    problems.append("stopped filtering an ordinary line containing {!r}".format(noise))
print("FAIL " + "; ".join(problems) if problems else "OK")
PYEOF
)" || render_status=$?
assert_python_ran "${render_status}" "Ansible static"
case "${render_probe}" in
    OK) pass "the callback keeps every [ERROR] line a debug message prints, whatever words it holds" ;;
    SKIP*) skip "the callback keeps every [ERROR] line" "${render_probe#SKIP }" ;;
    *) fail "the callback drops a line the playbook marked as an error" "${render_probe#FAIL }" ;;
esac

# --- the callback writes down every failed attempt of a retried task ---------
# The callback had no v2_runner_retry, so an attempt that failed and was then retried left nothing in
# any log. In sweep 38107292439 the SDKMAN installer died on its first attempt, its retry was skipped
# by a creates guard, and the only trace was a ten second gap before an ok line. The real hook is
# driven with a result shaped like the one ansible-core 2.19 hands it, and in-memory files stand in
# for the three logs, so a hook that prints to the console alone, or to the errors log, fails here.
retry_status=0
retry_probe="$("${PYTHON}" - "${ANSIBLE_DIR}/callback_plugins/dual_logger.py" <<'PYEOF'
import importlib.util, io, sys

spec = importlib.util.spec_from_file_location("dual_logger_retry_probe", sys.argv[1])
module = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(module)
except Exception as exc:                      # ansible not importable here, for instance
    print("SKIP {}".format(exc))
    sys.exit(0)

shown = []


class Display:
    def display(self, text):
        shown.append(text)


class Named:
    def __init__(self, name):
        self.name = name

    def get_name(self):
        return self.name


class Result:
    _host = Named("localhost")
    _task = Named("sdk_manager : Install the probe tool")
    _result = {
        "attempts": 2,
        "retries": 4,
        "rc": 23,
        "msg": "non-zero return code",
        "stderr": "\n".join(["noise line {}".format(n) for n in range(20)]
                            + ["curl: (56) probe archive connection reset"]),
    }


callback = module.CallbackModule()
callback._display = Display()
callback.full_log = io.StringIO()
callback.errors_log = io.StringIO()
callback.warnings_log = io.StringIO()
callback._log_initialized = True
callback._pending_phase = None
callback._pending_task = None
callback._task_start_ts = None
callback.v2_runner_retry(Result())
console = "\n".join(shown)
logs = {"the console": console,
        "installation_full.log": callback.full_log.getvalue(),
        "installation_warnings.log": callback.warnings_log.getvalue()}
wanted = ["Install the probe tool", "attempt 2 of 4", "non-zero return code", "rc: 23",
          "curl: (56) probe archive connection reset"]

problems = []
for where, text in logs.items():
    missing = [needle for needle in wanted if needle not in text]
    if missing:
        problems.append("{} lacks {}".format(where, ", ".join(repr(m) for m in missing)))
if "noise line 0" in console:
    problems.append("printed the whole stderr instead of its tail")
if callback.errors_log.getvalue():
    problems.append("wrote a tolerated retry to installation_errors.log")
print("FAIL " + "; ".join(problems) if problems else "OK")
PYEOF
)" || retry_status=$?
assert_python_ran "${retry_status}" "Ansible static"
case "${retry_probe}" in
    OK) pass "the callback writes each failed attempt of a retried task to the console, the full log and the warnings log" ;;
    SKIP*) skip "the callback writes each failed attempt of a retried task" "${retry_probe#SKIP }" ;;
    *) fail "a failed attempt of a retried task leaves no trace where it should" "${retry_probe#FAIL }" ;;
esac

# --- the summary names a package that installed on a retry once, as installed --------------------
# A package whose first attempt failed and whose retry installed it was listed under TOLERATED
# FAILURES for the first attempt and under INSTALLED for the retry, so one summary said both that it
# failed and that it installed. The real hooks are driven with results shaped like ansible-core's, in
# the order a run sends them: a first attempt in one task and its retry in a second task, the retry
# named once "Retry ..." as in install_role_packages.yaml and once "Install ...", a retry inside one task's own
# `until`, and a package that failed every attempt, which must stay a failure.
summary_status=0
summary_probe="$("${PYTHON}" - "${ANSIBLE_DIR}/callback_plugins/dual_logger.py" <<'PYEOF'
import importlib.util, io, sys

spec = importlib.util.spec_from_file_location("dual_logger_summary_probe", sys.argv[1])
module = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(module)
except Exception as exc:                      # ansible not importable here, for instance
    print("SKIP {}".format(exc))
    sys.exit(0)

shown = []


class Display:
    def display(self, text):
        shown.append(text)


class Named:
    def __init__(self, name):
        self.name = name

    def get_name(self):
        return self.name


class Stats:
    processed = {"localhost": 1}

    def summarize(self, host):
        return {"ok": 1, "changed": 1, "unreachable": 0, "failures": 0, "skipped": 0, "rescued": 0,
                "ignored": 0}


def result(task, item, rc, changed=False, **extra):
    r = type("Result", (), {})()
    r._host = Named("localhost")
    r._task = Named(task)
    r._result = dict({"item": item, "rc": rc, "changed": changed, "stdout": "", "stderr": "",
                      "msg": "non-zero return code" if rc else ""}, **extra)
    return r


# The two task names of setup/ansible/tasks/install_role_packages.yaml, read out of that file so a rename
# there cannot leave this probe driving names no run sends. Every apt, dnf, pacman, flatpak, snap and
# Homebrew install goes through them, from a role and from the software installer alike.
import pathlib, yaml
shared = yaml.safe_load(pathlib.Path(sys.argv[1]).parents[1].joinpath("tasks", "install_role_packages.yaml").read_text(encoding="utf-8"))
shared_names = [t["name"] for t in shared if isinstance(t, dict) and str(t.get("name", "")).startswith(("Install ", "Retry "))]
FIRST_NAME = next(n for n in shared_names if n.startswith("Install "))
RETRY_NAME = next(n for n in shared_names if n.startswith("Retry "))
FIRST = "virtualization_config : " + FIRST_NAME
RETRY = "virtualization_config : " + RETRY_NAME
FIRST_LOOP = "software_installer : " + FIRST_NAME
RETRY_LOOP = "software_installer : " + RETRY_NAME
OWN_UNTIL = "sdk_manager : Install all Java Temurin versions via SDKMAN (Linux/Mac)"

callback = module.CallbackModule()
callback._display = Display()
callback.full_log = io.StringIO()
callback.errors_log = io.StringIO()
callback.warnings_log = io.StringIO()
callback._log_initialized = True

callback.v2_runner_item_on_ok(result(FIRST, "docker", 1))
callback.v2_runner_item_on_ok(result(FIRST, "nope-never-installs", 1))
callback.v2_runner_item_on_ok(result(FIRST_LOOP, "steam", 1))
callback.v2_runner_retry(result(RETRY, "docker", 1, attempts=1, retries=3))
callback.v2_runner_item_on_ok(result(RETRY, "docker", 0, changed=True))
callback.v2_runner_item_on_ok(result(RETRY, "nope-never-installs", 1))
callback.v2_runner_item_on_ok(result(RETRY_LOOP, "steam", 0, changed=True))
callback.v2_runner_retry(result(OWN_UNTIL, "jq", 1, attempts=1, retries=4))
callback.v2_runner_retry(result(OWN_UNTIL, "jq", 1, attempts=2, retries=4))
callback.v2_runner_item_on_ok(result(OWN_UNTIL, "jq", 0, changed=True))
callback.v2_runner_item_on_ok(result(FIRST_LOOP, "ripgrep", 0, changed=True))
# After its items, a looped task sends one result of its own, carrying no item. Until 2026-10-15 a list
# of batch-era task names recorded that result as an installed package, so a real Debian defaults run
# listed "Install APT packages, one at a time" under INSTALLED beside the packages themselves.
for whole_task in (FIRST, RETRY, FIRST_LOOP, RETRY_LOOP):
    aggregate = result(whole_task, None, 0, changed=True)
    del aggregate._result["item"]
    callback.v2_runner_on_ok(aggregate)
callback.v2_playbook_on_stats(Stats())

summary = "\n".join(shown[next(i for i, t in enumerate(shown) if "PLAY RECAP" in t):])
sections = {}
current = None
for line in summary.splitlines():
    if "═══ " in line and " ═══" in line:
        current = line.split("═══ ", 1)[1].split(" (", 1)[0]
        sections[current] = []
    elif current:
        sections[current].append(line)
installed = "\n".join(sections.get("INSTALLED", []))
tolerated = "\n".join(sections.get("TOLERATED FAILURES", []))

problems = []
for name, retries in (("docker", "after 2 retries"), ("steam", "after 1 retry"), ("jq", "after 2 retries")):
    if name in tolerated:
        problems.append("{} installed on a retry and is still listed under TOLERATED FAILURES".format(name))
    if "{} ({})".format(name, retries) not in installed:
        problems.append("{} is not listed under INSTALLED as {!r}".format(name, "{} ({})".format(name, retries)))
if "ripgrep (" in installed or "ripgrep" not in installed:
    problems.append("ripgrep installed on its first attempt and is not listed as plainly installed")
for name in (FIRST_NAME, RETRY_NAME):
    if name in installed:
        problems.append("the task name {!r} is listed under INSTALLED as if it were a package".format(name))
if tolerated.count("nope-never-installs") != 1:
    problems.append("a package that failed every attempt is listed {} times under TOLERATED FAILURES, not once"
                    .format(tolerated.count("nope-never-installs")))
if "nope-never-installs" in installed:
    problems.append("a package that failed every attempt is listed under INSTALLED")
print("FAIL " + "; ".join(problems) if problems else "OK")
PYEOF
)" || summary_status=$?
assert_python_ran "${summary_status}" "Ansible static"
case "${summary_probe}" in
    OK) pass "the summary lists a package that installed on a retry once, as installed after its retries, and one that never installed as a failure" ;;
    SKIP*) skip "the summary lists a package that installed on a retry once" "${summary_probe#SKIP }" ;;
    *) fail "the summary misreports a package that installed on a retry" "${summary_probe#FAIL }" ;;
esac

# --- the terminal shows what installs, changes or fails, and the logs keep the rest ---------------
# A run that installed one application printed every skipped task of the whole playbook, hundreds of
# lines such as "skipping: [localhost] virtualization_config : Add current user to docker group
# (Linux) [toggle disabled (install_virt_manager=false)]", and its summary listed every disabled
# application. Three more defects came with it: a task-level skip of the build-list task was labelled
# "toggle disabled (install_software_installer : Build list of packages to dynamically install=false)",
# a condition on a registered or fact value was labelled as a toggle, and the error-details truncation
# kept 3 head and 6 tail lines, dropping the "error:" and "BUILD FAILED" lines between them.
#
# The real hooks are driven in the order a run sends them, with results shaped like the ones
# ansible-core 2.21 hands a callback, measured in a throwaway container, and in-memory files stand in
# for the four logs. Each line the probe prints is one assertion: PASS, FAIL or SKIP, a tab, the name,
# and for a failure a second tab and what went wrong.
terminal_status=0
terminal_probe="$("${PYTHON}" - "${ANSIBLE_DIR}/callback_plugins/dual_logger.py" <<'PYEOF'
import importlib.util, io, sys

spec = importlib.util.spec_from_file_location("dual_logger_terminal_probe", sys.argv[1])
module = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(module)
except Exception as exc:                      # ansible not importable here, for instance
    print("SKIP\tthe callback terminal and label checks\t{}".format(exc))
    sys.exit(0)

shown = []


class Display:
    def display(self, text):
        shown.append(text)


class Named:
    def __init__(self, name, action=""):
        self.name = name
        self.action = action
        self.ignore_errors = False

    def get_name(self):
        return self.name


class KeptLog(io.StringIO):
    def close(self):
        pass


class Stats:
    processed = {"localhost": 1}

    def summarize(self, host):
        return {"ok": 9, "changed": 2, "unreachable": 0, "failures": 1, "skipped": 4, "rescued": 0,
                "ignored": 0}


def result(task, action="", **fields):
    r = type("Result", (), {})()
    r._host = Named("localhost")
    r._task = Named(task, action)
    r._result = fields
    return r


def new_callback():
    del shown[:]
    callback = module.CallbackModule()
    callback._display = Display()
    callback.full_log = KeptLog()
    callback.errors_log = KeptLog()
    callback.warnings_log = KeptLog()
    callback.skipped_log = KeptLog()
    callback._log_initialized = True
    return callback


def start(callback, name):
    callback.v2_playbook_on_task_start(Named(name), False)


def report(name, problems):
    if problems:
        print("FAIL\t{}\t{}".format(name, "; ".join(problems)))
    else:
        print("PASS\t{}".format(name))


ENABLE = "linux_security : Enable the ClamAV database updater"
DOCKER_GROUP = "virtualization_config : Add current user to docker group (Linux)"
BUILD = "software_installer : Build list of packages to dynamically install"
KERNEL = "system_core : Read the running kernel release"
INSTALL = "software_installer : Install a package set one package at a time"
QUIET_NOTE = "software_installer : Say which mirror was chosen"
ARCH_WARN = "software_installer : Name every requested mapping skipped for this machine's processor architecture"
SERVICE = "waydroid : Start the Waydroid container service"
UNREACHABLE = "snapper : Read the root subvolume layout"
INCLUDED = "/work/setup/ansible/tasks/install_role_packages.yaml"
STEAM = {"key": "steam", "value": {"manager": "apt"}}
NPM_TOOLS = "ai_tools : Install the npm command line tools"
BUILD_CONDITION = "lookup('vars', 'install_' ~ item.key, default=false) | bool"

callback = new_callback()
callback.v2_playbook_on_start(type("Playbook", (), {"_entries": [Named("Installation Helper")]})())
callback.v2_playbook_on_play_start(Named("Installation Helper"))
start(callback, "linux_security : Install ClamAV (Fedora)")
callback.v2_runner_on_skipped(result("linux_security : Install ClamAV (Fedora)", changed=False,
                                     false_condition="ansible_facts['os_family'] == 'RedHat'",
                                     skip_reason="Conditional result was False"))
start(callback, ENABLE)
callback.v2_runner_on_ok(result(ENABLE, "ansible.builtin.systemd", changed=True))
start(callback, DOCKER_GROUP)
callback.v2_runner_on_skipped(result(DOCKER_GROUP, changed=False,
                                     false_condition="install_virt_manager | default(false) | bool",
                                     skip_reason="Conditional result was False"))
start(callback, BUILD)
callback.v2_runner_item_on_skipped(result(BUILD, "ansible.builtin.set_fact", changed=False, item=STEAM,
                                          false_condition=BUILD_CONDITION,
                                          skip_reason="Conditional result was False"))
callback.v2_runner_item_on_ok(result(BUILD, "ansible.builtin.set_fact", changed=False,
                                     item={"key": "ripgrep", "value": {"manager": "apt"}}))
callback.v2_runner_on_ok(result(BUILD, "ansible.builtin.set_fact", changed=False, msg="All items completed",
                                results=[]))
start(callback, NPM_TOOLS)
callback.v2_runner_item_on_skipped(result(NPM_TOOLS, "ansible.builtin.command", changed=False,
                                          item={"name": "opencode"},
                                          false_condition="install_opencode | default(false) | bool",
                                          skip_reason="Conditional result was False"))
callback.v2_runner_on_skipped(result(NPM_TOOLS, "ansible.builtin.command", changed=False,
                                     msg="All items skipped", results=[]))
start(callback, KERNEL)
callback.v2_runner_on_ok(result(KERNEL, "ansible.builtin.command", changed=False, rc=0,
                                stdout="6.1.0-quiet-probe"))
callback.v2_playbook_on_include(type("Included", (), {"_filename": INCLUDED})())
start(callback, INSTALL)
callback.v2_runner_item_on_ok(result(INSTALL, "ansible.builtin.raw", changed=True, rc=0, item="ripgrep"))
callback.v2_runner_item_on_ok(result(INSTALL, "ansible.builtin.raw", changed=False, rc=0, item="curl"))
callback.v2_runner_on_ok(result(INSTALL, "ansible.builtin.raw", changed=True, msg="All items completed",
                                results=[]))
start(callback, QUIET_NOTE)
callback.v2_runner_on_ok(result(QUIET_NOTE, "ansible.builtin.debug", changed=False,
                                msg="plain quiet note about the mirror"))
start(callback, ARCH_WARN)
callback.v2_runner_item_on_ok(result(ARCH_WARN, "ansible.builtin.debug", changed=False, item="gputest",
                                     msg="[WARN] Skipping gputest: the vendor publishes no build for this processor"))
callback.v2_runner_on_ok(result(ARCH_WARN, "ansible.builtin.debug", changed=False, msg="All items completed",
                                results=[]))
start(callback, SERVICE)
callback.v2_runner_on_failed(result(SERVICE, "ansible.builtin.systemd", changed=False, rc=5,
                                    msg="Could not find the requested service waydroid-container"))
start(callback, UNREACHABLE)
callback.v2_runner_on_unreachable(result(UNREACHABLE, "ansible.builtin.command", changed=False, unreachable=True,
                                         msg="Failed to create temporary directory /probe/.ansible/tmp"))
callback.v2_playbook_on_stats(Stats())

console = "\n".join(shown)
recap_at = next(i for i, text in enumerate(shown) if "PLAY RECAP" in text)
console_run = "\n".join(shown[:recap_at])
console_summary = "\n".join(shown[recap_at:])
full = callback.full_log.getvalue()
full_summary = full[full.index("PLAY RECAP"):]

problems = []
for needle in ("skipping:", "skipped:", "present: [localhost]", "ok: [localhost]", "included:",
               "6.1.0-quiet-probe", "plain quiet note", "All items completed", "TASK [" + DOCKER_GROUP,
               "TASK [" + BUILD, "TASK [" + NPM_TOOLS, "TASK [" + KERNEL, "TASK [" + QUIET_NOTE, "PHASE: system_core",
               "PHASE: virtualization_config", "PHASE: ai_tools"):
    if needle in console:
        problems.append("the terminal shows {!r}".format(needle))
if console.count("PLAY [Installation Helper]") != 1:
    problems.append("the terminal shows the PLAY line {} times, not once".format(console.count("PLAY [Installation Helper]")))
report("ok and skipped results stay off the terminal, and so does a header with nothing shown under it",
       problems)


def in_order(text, needles):
    position = 0
    for needle in needles:
        found = text.find(needle, position)
        if found < 0:
            return needle
        position = found + len(needle)
    return None


problems = []
for needles in (("TASK [" + ENABLE + "]", "CHANGED: [localhost]"),
                ("PHASE: software_installer", "TASK [" + INSTALL + "]", "INSTALLED: [localhost] ripgrep"),
                ("TASK [" + ARCH_WARN + "]", "[WARN] Skipping gputest"),
                ("PHASE: waydroid", "TASK [" + SERVICE + "]", "FAILED: [localhost] => TASK: " + SERVICE,
                 "Could not find the requested service waydroid-container"),
                ("TASK [" + UNREACHABLE + "]", "unreachable: [localhost] TASK: " + UNREACHABLE,
                 "Failed to create temporary directory /probe/.ansible/tmp")):
    missing = in_order(console_run, needles)
    if missing:
        problems.append("the terminal lacks {!r} in its place".format(missing))
report("changed, failed and unreachable results, with their reasons, and deliberate [WARN] messages reach the terminal under their own headers",
       problems)

problems = []
for where, text in (("the terminal", console_run), ("installation_full.log", full)):
    missing = in_order(text, ("PHASE: linux_security", ENABLE))
    if missing:
        problems.append("{} lacks {!r} before the first result of the role".format(where, missing))
report("a role whose first task does not apply to this OS keeps its phase banner", problems)

problems = []
for needle in ("skipping: [localhost] " + DOCKER_GROUP, "skipped: [localhost] software_installer → steam",
               "skipped: [localhost] ai_tools → opencode", "present: [localhost] curl", "included: " + INCLUDED, "6.1.0-quiet-probe",
               "plain quiet note", "TASK [" + KERNEL + "]", "PHASE: system_core"):
    if needle not in full:
        problems.append("installation_full.log lacks {!r}".format(needle))
if "ai_tools → opencode [toggle disabled (install_opencode=false)]" not in callback.skipped_log.getvalue():
    problems.append("installation_skipped.log lacks the opencode item and its reason")
report("installation_full.log and installation_skipped.log still hold every ok and skipped line", problems)

problems = []
for name in ("steam", "opencode"):
    if name in console_summary:
        problems.append("the terminal summary names {}, whose toggle is off".format(name))
if "INSTALLED" not in console_summary or "ripgrep" not in console_summary:
    problems.append("the terminal summary lacks the installed ripgrep")
if "curl" not in console_summary:
    problems.append("the terminal summary lacks curl, which was asked for and already present")
if not any("SKIPPED (1)" in text and callback.skipped_log_path in text for text in shown[recap_at:]):
    problems.append("the terminal summary does not say how many items were skipped and where they are listed")
if "opencode" not in full_summary:
    problems.append("the summary in installation_full.log no longer lists the skipped opencode")
report("the terminal summary lists only what the run was asked to install", problems)

callback = new_callback()
noise = ["compiling unit {}".format(n) for n in range(300)]
build_log = list(noise)
build_log[120] = "src/probe.c:12:5: error: 'probe_t' undeclared (first use in this function)"
build_log[200] = "BUILD FAILED in 41s"
build_log[230] = "fatal: unable to access 'https://probe.invalid/repo.git/'"
build_log[240] = "ERROR: Could not find a version that satisfies the requirement probe"
build_log[250] = "Error: Cannot find module 'probe'"
markers = [build_log[i] for i in (120, 200, 230, 240, 250)]
failed = result("sdk_manager : Build the probe from source", "ansible.builtin.shell", changed=False, rc=2,
                msg="non-zero return code", stderr="\n".join(build_log), stderr_lines=build_log)
details = "\n".join(callback._extract_error_details(failed))
flood = ["x.c:{}: error: cascade {}".format(n, n) for n in range(500)]
kept = module.CallbackModule._truncate_lines(flood, module.STDOUT_TRUNCATE_LINES)
retry = callback._retry_details({"attempts": 1, "retries": 3, "rc": 1, "msg": "non-zero return code",
                                 "stderr": "\n".join(["E: Unable to locate package probe"] + noise[:20])})

problems = []
for marker in markers:
    if marker not in details:
        problems.append("the failure details dropped {!r}".format(marker))
if "compiling unit 150" in details:
    problems.append("the failure details kept a plain line from the middle")
if details.count(markers[0]) != 1:
    problems.append("the failure details print {!r} {} times, once from stderr and again from stderr_lines"
                    .format(markers[0], details.count(markers[0])))
if len(kept) > 2 * module.STDOUT_TRUNCATE_LINES:
    problems.append("500 error lines came back as {} lines, which floods".format(len(kept)))
if flood[0] not in kept or flood[-1] not in kept or "x.c:10: error: cascade 10" not in "\n".join(kept):
    problems.append("a flood of error lines lost its head, its tail or its first middle error")
if not any("truncated" in line for line in kept):
    problems.append("a flood of error lines does not say lines were removed")
if not any("E: Unable to locate package probe" in line for line in retry):
    problems.append("a failed attempt's stderr dropped the apt error line before its last lines")
report("a truncated block keeps every error line between its head and its tail, up to a cap, and the failure details print it once", problems)

callback = new_callback()
LABELS = (
    ("software_installer : Build list of packages to dynamically install", None,
     {"msg": "All items skipped", "results": [{"item": STEAM, "false_condition": BUILD_CONDITION}]}),
    ("virtualization_config : Toggle alone", "toggle disabled (install_virt_manager=false)",
     {"false_condition": "install_virt_manager | default(false) | bool"}),
    ("software_installer : Fact beside a toggle", None,
     {"false_condition": "install_kicad9 | default(false) | bool and kicad9_appimage_applies | bool"}),
    ("sdk_manager : Registered value", None, {"false_condition": "install_failures | length > 0"}),
    ("software_installer : Fact named like a toggle", None, {"false_condition": "allow_failures | bool"}),
    ("systemd_boot : Negated toggle", None,
     {"false_condition": "not (setup_systemd_boot | default(false) | bool) or not (efi_dir.stat.exists | default(false))"}),
)
for task, _, fields in LABELS:
    callback.v2_runner_on_skipped(result(task, changed=False, skip_reason="Conditional result was False", **fields))
callback.v2_runner_item_on_skipped(result(BUILD, "ansible.builtin.set_fact", changed=False, item=STEAM,
                                          false_condition=BUILD_CONDITION,
                                          skip_reason="Conditional result was False"))
labels = {}
for line in callback.full_log.getvalue().splitlines():
    for task, _, _ in LABELS:
        marker = "skipping: [localhost] {} [".format(task)
        if marker in line:
            labels[task] = line.split(marker, 1)[1].rsplit("]", 1)[0]

problems = []
for task, wanted, fields in LABELS:
    label = labels.get(task)
    if label is None:
        problems.append("no skip line for {!r}".format(task))
    elif wanted is not None and label != wanted:
        problems.append("{!r} is labelled {!r}, not {!r}".format(task, label, wanted))
    elif wanted is None and label.startswith("toggle disabled"):
        problems.append("{!r} is labelled {!r}, but no toggle alone decided it".format(task, label))
    elif wanted is None and "false_condition" in fields and fields["false_condition"] not in label:
        problems.append("{!r} is labelled {!r}, which does not name its condition".format(task, label))
if "software_installer → steam [toggle disabled (install_steam=false)]" not in callback.full_log.getvalue():
    problems.append("an item the build-list task skipped is no longer labelled by its own toggle")
report("a skip is labelled toggle disabled only when a declared toggle alone decided it", problems)

# ansible-core 2.19 and later put "(traceback unavailable)" in `exception` when tracebacks are off,
# and the callback printed it on the terminal under every failure as "Exception (full):".
callback = new_callback()
NO_TRACE = "linux_security : Update the ClamAV database"
REAL_TRACE = "linux_security : Read the ClamAV configuration"
start(callback, NO_TRACE)
callback.v2_runner_on_failed(result(NO_TRACE, "ansible.builtin.command", changed=False, rc=1,
                                    msg="freshclam could not reach the mirror",
                                    exception="(traceback unavailable)"))
start(callback, REAL_TRACE)
callback.v2_runner_on_failed(result(REAL_TRACE, "ansible.builtin.slurp", changed=False,
                                    msg="the probe module crashed",
                                    exception="Traceback (most recent call last):\n  File \"probe.py\", line 3\nValueError: probe traceback line"))
console = "\n".join(shown)
full = callback.full_log.getvalue()

problems = []
for where, text in (("the terminal", console), ("installation_full.log", full),
                    ("installation_errors.log", callback.errors_log.getvalue())):
    if "traceback unavailable" in text:
        problems.append("{} shows the placeholder '(traceback unavailable)'".format(where))
if "ValueError: probe traceback line" in console:
    problems.append("the terminal shows a real traceback")
if "Full result" in console:
    problems.append("the terminal dumps the whole result of a failure that carries an exception field")
if "ValueError: probe traceback line" not in full:
    problems.append("installation_full.log lacks the real traceback")
for needle in ("freshclam could not reach the mirror", "the probe module crashed"):
    if needle not in console:
        problems.append("the terminal lacks the failure reason {!r}".format(needle))
report("a failure shows no traceback on the terminal, and only a real one reaches installation_full.log", problems)

# The heartbeat printed "running: <task>" as a permanent terminal line for any task over two seconds,
# so a task that then ended ok left a line behind under no header. It has to stay a live, erasable
# status line on a terminal, nothing on output that is not a terminal, and a line in the full log.
import threading, time


class Terminal(io.StringIO):
    def __init__(self, interactive):
        super().__init__()
        self.interactive = interactive

    def isatty(self):
        return self.interactive


def heartbeat_run(interactive, task):
    callback = new_callback()
    callback._heartbeat_tick = 0.05
    callback._status_stream = Terminal(interactive)
    callback._live_terminal = interactive
    start(callback, task)
    callback._heartbeat_task_started -= 10
    deadline = time.monotonic() + 3
    while "running: " + task not in callback.full_log.getvalue() and time.monotonic() < deadline:
        threading.Event().wait(0.05)
    callback.v2_runner_on_ok(result(task, "ansible.builtin.command", changed=False, rc=0))
    return callback, "\n".join(shown)


LONG_OK = "system_core : Refresh the package index"
problems = []
callback, console = heartbeat_run(True, LONG_OK)
status = callback._status_stream.getvalue()
if "running" in console or LONG_OK in console:
    problems.append("a task that ended ok left a permanent heartbeat line on the terminal")
if LONG_OK not in status:
    problems.append("the terminal got no live status line while the task ran")
if not status.endswith("\r\x1b[K"):
    problems.append("the live status line was not erased when the task ended, the stream ends {!r}".format(status[-30:]))
if "running: " + LONG_OK not in callback.full_log.getvalue():
    problems.append("installation_full.log lacks the heartbeat line")
callback, console = heartbeat_run(False, LONG_OK)
if "running" in console or callback._status_stream.getvalue():
    problems.append("output that is not a terminal got heartbeat text it can never erase")
report("the heartbeat is an erasable status line on a terminal and leaves nothing behind for a task that ends ok",
       problems)
PYEOF
)" || terminal_status=$?
assert_python_ran "${terminal_status}" "Ansible static"
while IFS=$'\t' read -r verdict name detail; do
    case "${verdict}" in
        PASS) pass "${name}" ;;
        SKIP) skip "${name}" "${detail}" ;;
        *) fail "${name:-the callback terminal probe printed no verdict}" "${detail}" ;;
    esac
done <<<"${terminal_probe}"

# --- optional linters --------------------------------------------------------
# Reported, never required. Making the gate depend on a tool that may not be installed
# would mean the gate silently stops running, which is its own failure mode.
if command -v yamllint &>/dev/null; then
    if yamllint -d "{extends: relaxed, rules: {line-length: disable}}" "${ANSIBLE_DIR}" &>/dev/null; then
        pass "yamllint clean"
    else
        fail "yamllint reports problems" "$(yamllint -d '{extends: relaxed, rules: {line-length: disable}}' "${ANSIBLE_DIR}" 2>&1 | sed -n 1,5p | tr '\n' ' ')"
    fi
else
    warn "yamllint not installed, skipping. Install with: pip install --user yamllint"
fi

if command -v ansible-lint &>/dev/null; then
    if ansible-lint --nocolor -q site.yaml &>/dev/null; then
        pass "ansible-lint clean"
    else
        warn "ansible-lint reports findings, not treated as a failure yet:"
        { ansible-lint --nocolor -q site.yaml 2>&1 || true; } | sed -n 1,15p | sed 's/^/       /'
    fi
else
    warn "ansible-lint not installed, skipping. Install with: pip install --user ansible-lint"
fi

finish "Ansible static checks"
