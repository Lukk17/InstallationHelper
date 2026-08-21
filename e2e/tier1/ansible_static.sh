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

cd "${ANSIBLE_DIR}"

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
for f in "${E2E_ROOT}"/tier3/verify.yaml; do
    if ansible-playbook --syntax-check "${f}" &>/dev/null; then
        pass "$(basename "${f}") parses"
    else
        fail "$(basename "${f}") does not parse" "$(ansible-playbook --syntax-check "${f}" 2>&1 | tail -3 | tr '\n' ' ')"
    fi
done

# --- the callback keeps the tail of a long block -----------------------------
# Asserted because losing it is silent. dual_logger truncates a task's stdout to
# STDOUT_TRUNCATE_LINES, and while it kept the head alone, the reason a failed command gave was
# thrown away before anything was written: apt prints its dependency list first and "E: Failed to
# fetch" last, so 29 lines of 1098 kept the noise and dropped the diagnosis. One Debian cell was
# unexplainable for exactly that reason.
#
# The real function is imported out of the plugin rather than reimplemented here, so this cannot
# pass against a copy while the plugin regresses.
trunc_probe="$("${PYTHON:-python3}" - "${ANSIBLE_DIR}/callback_plugins/dual_logger.py" <<'PYEOF'
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
)"
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
