#!/usr/bin/env bash
#
# Tier 1: nothing under e2e/ starts a privileged container except tier 3's own scenario container.
#
# Docker on the owner's computer does not remap users, so root inside a container is the real root of
# his kernel, and only the container's confinement stands between the two. On 2026-10-19 an agent
# started a throwaway container with seccomp, AppArmor and the system paths unconfined, ran
# `unshare --user --map-root-user --mount-proc` inside it, and wrote kernel.sysrq from 16 to 1 on the
# owner's kernel (docs/regression_ledger.md 10.143). Rule 7 of the section "MANDATORY: never run
# anything on the owner's computer for testing" in AGENTS.md forbids it, and this holds the scripts to
# the rule.
#
# Every file under e2e/ apart from the run logs is read, continuation lines joined, comment lines left
# out. A markdown page is read for its commands only, the lines of its fenced code blocks and each
# inline code span that is itself a container command, so prose naming a forbidden flag is not one. A command that starts or enters a container, docker run, create or exec, fails the check when it
# carries --privileged, --security-opt, --cap-add, or the host's pid, network or user namespace, or
# runs unshare, nsenter or sysctl -w, or writes under /proc or /sys. e2e/tier3/container.sh is the one
# exception, because it starts the scenario container that tier 3 runs only on a GitHub-hosted runner,
# which e2e/tier1/throwaway_machine_only.sh holds it to. This file is left out too, because the planted
# commands below are written in it.
#
# The scanner is first run over a planted file, one forbidden command per line, and must name every one
# of them and nothing on the clean lines beside them, so a scanner that has gone blind fails here
# rather than passing over the real tree. Proven on 2026-10-19 by running the gate on a copy of the
# finished tree with a docker run line carrying --security-opt seccomp=unconfined appended to
# e2e/tier2/resolve_packages.sh, which failed 1 of 2 and named that file and line.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: no container under e2e/ gets privileges on the owner's kernel"

require_python "no container under e2e/ gets privileges on the owner's kernel" "host container privileges"

planted="$(mktemp -d)"
trap 'rm -rf -- "${planted}"' EXIT
mkdir -p "${planted}/e2e/tier3" "${planted}/e2e/runs"
cat >"${planted}/e2e/planted.sh" <<'EOF'
docker run --rm --privileged debian:trixie true
docker run --rm \
    --security-opt seccomp=unconfined \
    debian:trixie true
docker run --rm --cap-add SYS_ADMIN debian:trixie true
docker run --rm --pid=host debian:trixie true
docker run --rm --network host debian:trixie true
docker run --rm --net=host debian:trixie true
docker run --rm --userns=host debian:trixie true
docker exec probe unshare --user --map-root-user --mount-proc true
docker exec probe nsenter -t 1 -m true
docker run --rm debian:trixie sysctl -w kernel.sysrq=1
docker run --rm debian:trixie sh -c 'echo 1 > /proc/sys/kernel/sysrq'
docker container run --rm --privileged debian:trixie true
MSYS_NO_PATHCONV=1 docker create --privileged debian:trixie
docker run --rm debian:trixie cat /proc/sys/kernel/sysrq
# docker run --rm --privileged debian:trixie true
docker run --rm -v "$PWD:/w:ro" debian:trixie true
EOF
cat >"${planted}/e2e/planted.md" <<'EOF'
A table row naming `docker run` and `--privileged` and `unshare` in prose is not a command.

```bash
docker run --rm --cap-add NET_ADMIN debian:trixie true
```

| Step | `docker exec probe nsenter -t 1 -m true` |
EOF
printf '%s\n' 'docker run -d --privileged debian:trixie true' >"${planted}/e2e/tier3/container.sh"
printf '%s\n' 'docker run --rm --privileged debian:trixie true' >"${planted}/e2e/runs/old.log"

scan() {
    "${PYTHON}" - "$1" <<'PYEOF'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
e2e = root / 'e2e'
exempt = {e2e / 'tier3' / 'container.sh', e2e / 'tier1' / 'host_container_privileges.sh'}
runs = e2e / 'runs'

container_command = re.compile(r'\bdocker\s+(container\s+)?(run|create|exec)\b')
forbidden = [
    ('--privileged', re.compile(r'(^|\s)--privileged\b')),
    ('--security-opt', re.compile(r'(^|\s)--security-opt\b')),
    ('--cap-add', re.compile(r'(^|\s)--cap-add\b')),
    ('the host pid namespace', re.compile(r'(^|\s)--pid[= ]+host\b')),
    ('the host network', re.compile(r'(^|\s)--(network|net)[= ]+host\b')),
    ('the host user namespace', re.compile(r'(^|\s)--userns[= ]+host\b')),
    ('unshare', re.compile(r'\bunshare\b')),
    ('nsenter', re.compile(r'\bnsenter\b')),
    ('sysctl -w', re.compile(r'\bsysctl\s+(-\w*\s+)*-w\b')),
    ('a write under /proc or /sys', re.compile(r'(>|\btee\s+(-a\s+)?)\s*/(proc|sys)/')),
]

inline_code = re.compile(r'`([^`]+)`')


def markdown_commands(text):
    commands = []
    fenced = False
    for line in text.splitlines():
        if line.lstrip().startswith('```'):
            fenced = not fenced
            commands.append('')
        elif fenced:
            commands.append(line)
        else:
            commands.append(' ; '.join(c for c in inline_code.findall(line) if container_command.search(c)))
    return commands


scanned = 0
for path in sorted(e2e.rglob('*')):
    if not path.is_file() or path in exempt or runs in path.parents:
        continue
    try:
        text = path.read_text(encoding='utf-8')
    except (UnicodeDecodeError, OSError):
        continue
    scanned += 1
    lines = markdown_commands(text) if path.suffix == '.md' else text.splitlines()
    number = 0
    while number < len(lines):
        start = number
        logical = lines[number]
        while logical.endswith('\\') and number + 1 < len(lines):
            number += 1
            logical = logical[:-1] + ' ' + lines[number]
        number += 1
        if logical.lstrip().startswith('#') or not container_command.search(logical):
            continue
        for name, pattern in forbidden:
            if pattern.search(logical):
                print('FOUND\t{}:{}\t{}'.format(path.relative_to(root), start + 1, name))
print('SCANNED\t{}'.format(scanned))
PYEOF
}

# --- the scanner, over a planted tree ---------------------------------------------------------------
planted_status=0
planted_report="$(scan "${planted}")" || planted_status=$?
assert_python_ran "${planted_status}" "host container privileges"
expected_planted="$(cat <<'EOF'
FOUND	e2e/planted.md:4	--cap-add
FOUND	e2e/planted.md:7	nsenter
FOUND	e2e/planted.sh:1	--privileged
FOUND	e2e/planted.sh:2	--security-opt
FOUND	e2e/planted.sh:5	--cap-add
FOUND	e2e/planted.sh:6	the host pid namespace
FOUND	e2e/planted.sh:7	the host network
FOUND	e2e/planted.sh:8	the host network
FOUND	e2e/planted.sh:9	the host user namespace
FOUND	e2e/planted.sh:10	unshare
FOUND	e2e/planted.sh:11	nsenter
FOUND	e2e/planted.sh:12	sysctl -w
FOUND	e2e/planted.sh:13	a write under /proc or /sys
FOUND	e2e/planted.sh:14	--privileged
FOUND	e2e/planted.sh:15	--privileged
SCANNED	2
EOF
)"
assert_eq "the scanner names every planted forbidden command, and not the comment, the read, the plain run, markdown prose, container.sh or the run logs" \
    "${expected_planted}" "${planted_report}"

# --- the real tree ----------------------------------------------------------------------------------
report_status=0
report="$(scan "${REPO_ROOT}")" || report_status=$?
assert_python_ran "${report_status}" "host container privileges"

found="$(grep '^FOUND' <<<"${report}" || true)"
scanned="$(awk -F'\t' '$1 == "SCANNED" { print $2 }' <<<"${report}")"
if [[ -z "${scanned}" || "${scanned}" -eq 0 ]]; then
    fail "the scanner read no file under e2e/, so it proves nothing" "${REPO_ROOT}/e2e"
elif [[ -z "${found}" ]]; then
    pass "none of ${scanned} files under e2e/ starts or enters a container with privileges on the host kernel, apart from e2e/tier3/container.sh"
else
    while IFS=$'\t' read -r _ where what; do
        fail "a container command under e2e/ asks for ${what}, which AGENTS.md rule 7 forbids on the owner's computer" "${where}"
    done <<<"${found}"
fi

finish "host container privileges"
