#!/usr/bin/env bash
#
# Tier 1: every task that reaches the network retries, or says in writing why it does not.
#
# One sweep on 2026-08-22 lost four cells to four separate network transients, none of them a fault
# of this repository and none of them survivable as the playbook then stood:
#
#   deb.debian.org   OpenSSL system call error: Broken pipe, at file 440 of 440 in a 1.15 GB batch
#   github.com       Connection reset by peer, downloading one of four Nerd Font files
#   github.com       [35] SSL connect error, fetching an AppImage inside a flatpak batch
#   python.org       curl (35) TLS connect error: unexpected eof, downloading a Python tarball
#
# Each one failed a whole scenario, and in two of them a batch is a single call, so one lost file
# meant thirty-four applications never installed. A provisioning run that gives up on the first
# dropped packet is not fit for the job it exists to do, on a laptop any more than on a runner.
#
# So the rule this enforces: a task that fetches something over the network carries retries. The
# exceptions are real but few, and each one is written down in network_retries_allowed.txt with the
# reason, because "this one cannot" is a claim that goes stale and should have to be re-read.
#
# Two shapes count as retrying. The keyword, retries with an until, which is what a normal task
# uses. And a loop written inside the body of a task launched with poll: 0, because Ansible's
# retries cannot reach an async task at all: retrying that would mean relaunching it, and the
# collector has no way to do so.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: network tasks retry"

ALLOWLIST="$(dirname "${BASH_SOURCE[0]}")/network_retries_allowed.txt"

report="$("${PYTHON:-python}" - "$(host_path "${ANSIBLE_DIR}")" "$(host_path "${ALLOWLIST}")" <<'PYEOF'
import pathlib, re, sys

try:
    import yaml
except ImportError as exc:
    print("SKIP no PyYAML for this interpreter: {}".format(exc))
    raise SystemExit(0)

ansible_dir, allowlist_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])

# Modules that fetch by definition, and the commands that do it inside a shell body.
NET_MODULES = (
    "ansible.builtin.get_url", "get_url", "ansible.builtin.uri", "uri",
    "ansible.builtin.git", "git", "community.general.flatpak",
    "community.general.homebrew", "community.general.homebrew_cask",
    "community.general.homebrew_tap", "community.general.npm", "npm",
)
FREEFORM = ("ansible.builtin.shell", "shell", "ansible.builtin.command", "command",
            "ansible.builtin.raw", "raw", "ansible.builtin.script", "script")
NET_TEXT = re.compile(
    r"\b(curl|wget|git clone|npm (?:i|install)|pip install|flatpak install|apt-get install|"
    r"dnf install|brew install|nvm install|pyenv install|fvm install|rustup)\b")
# unarchive is only a network task when its src is a URL; most callers here extract a local file.
URLISH = re.compile(r"https?://")

allowed = {}
for line in allowlist_path.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    name, _, reason = line.partition("|")
    allowed[name.strip()] = reason.strip()

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

def body_of(task, key):
    value = task.get(key)
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        return str(value.get("cmd", "") or value.get("_raw_params", ""))
    return ""

missing, seen_names = [], set()
for path in sorted(ansible_dir.rglob("*.yaml")):
    try:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception:
        continue
    for task in walk(doc):
        if not isinstance(task, dict) or "name" not in task:
            continue
        reaches_network = any(module in task for module in NET_MODULES)
        if not reaches_network:
            for key in FREEFORM:
                if NET_TEXT.search(body_of(task, key)):
                    reaches_network = True
                    break
        if not reaches_network:
            for key in ("ansible.builtin.unarchive", "unarchive"):
                params = task.get(key)
                if isinstance(params, dict) and URLISH.search(str(params.get("src", ""))):
                    reaches_network = True
        if not reaches_network:
            continue

        name = str(task["name"])
        seen_names.add(name)
        if "retries" in task:
            continue
        # A poll: 0 task cannot use the keyword, so its own body has to carry the loop.
        if task.get("poll") == 0 and "for attempt in" in "".join(body_of(task, k) for k in FREEFORM):
            continue
        if name in allowed:
            continue
        missing.append("{}: {}".format(path.name, name))

stale = [name for name in allowed if name not in seen_names]

if missing or stale:
    parts = []
    if missing:
        parts.append("no retry: " + "; ".join(missing))
    if stale:
        parts.append("allowlisted but no longer a network task: " + "; ".join(stale))
    print("FAIL " + " | ".join(parts))
else:
    print("OK {} network tasks, {} allowlisted".format(len(seen_names), len(allowed)))
PYEOF
)"

case "${report}" in
    OK*)   pass "every network task retries, or is allowlisted with a reason (${report#OK })" ;;
    SKIP*) skip "every network task retries" "${report#SKIP }" ;;
    *)     fail "a task that reaches the network has no retry behind it" "${report#FAIL }" ;;
esac

finish "network tasks retry"
