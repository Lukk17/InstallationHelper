#!/usr/bin/env bash
#
# Tier 1: the compose files parse and resolve, and the documentation links point at files that exist.
#
# local-dev/ and homelab/ are two thirds of this repository and until now had no test of any kind.
# Everything the harness does is about setup/, so a broken compose file or a documentation link
# pointing at a renamed page would have shipped unnoticed, and the markdown filename rename earlier
# in this project's history is exactly the change that breaks links quietly.
#
# Two questions are asked here, both cheap and both static:
#
#   1. Every compose file resolves. `docker compose config` is the only thing that answers this
#      honestly, because it merges, interpolates and validates in one pass, and a file that parses as
#      YAML can still be a compose file docker refuses. It needs no daemon: config reads and prints.
#   2. Every relative markdown link anywhere in the repository points at a path that exists, and
#      every heading anchor at a heading that exists. Links with a scheme are somebody else's
#      problem and are not fetched here, that is what tier 2 is for.
#
# A missing docker binary is a skip rather than a pass, for the reason the rest of the harness gives:
# silence and success have to be told apart. docker_usable asks more than command -v: with Docker
# Desktop's WSL integration off, the docker on PATH is a stub that prints "The command 'docker'
# could not be found in this WSL 2 distro." to stdout and keeps going rather than failing cleanly,
# which read as a real but empty service name below and crashed the check with no FAIL and no
# tally, caught only once run.sh started checking for one. docker info is the same reachability
# test require_docker_host in host.sh uses for tier 2 and 3, asked here without exiting the gate.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: compose files and documentation links"

docker_usable() { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }

# --- compose files resolve ------------------------------------------------------------------------
mapfile -t compose_files < <(
    find "${REPO_ROOT}/local-dev" "${REPO_ROOT}/homelab" \
        -type f \( -name '*compose*.yaml' -o -name '*compose*.yml' \) 2>/dev/null | sort
)

if [[ ${#compose_files[@]} -eq 0 ]]; then
    fail "no compose files found under local-dev/ or homelab/, so this check proves nothing" \
         "${REPO_ROOT}"
elif ! docker_usable; then
    skip "every compose file resolves" "no docker here that both exists and answers docker info, and only docker can answer this"
else
    broken=()
    for f in "${compose_files[@]}"; do
        # --dry-run is not it: config is the validating read, and it needs no daemon. Stderr is kept
        # because that is where the reason lives when it refuses.
        # --no-interpolate on purpose. These files read secrets from a .env this repository does not
        # commit, so interpolation fails on a missing SEARXNG_SECRET and says nothing about whether
        # the file is valid. Without interpolation the merge and the schema are still checked, which
        # is the part a reader can get wrong.
        if ! out="$(docker compose -f "$(host_path "${f}")" config --no-interpolate 2>&1)"; then
            broken+=("$(basename "$(dirname "${f}")")/$(basename "${f}"): $(head -1 <<<"${out}")")
        fi
    done
    if [[ ${#broken[@]} -eq 0 ]]; then
        pass "all ${#compose_files[@]} compose files under local-dev/ and homelab/ resolve"
    else
        fail "${#broken[@]} of ${#compose_files[@]} compose files do not resolve" "${broken[*]}"
    fi
fi

# --- every service names an image -----------------------------------------------------------------
# A service with neither image nor build is a service that can never start, and compose config does
# not object to it.
# Asked of compose rather than of the indentation. The first version of this counted every key at two
# spaces, which catches volumes: and networks: entries as well as services and reported three healthy
# files as broken. compose knows what a service is, so it is the one to ask.
missing_image=()
services_seen=0
# Both ways this cannot run are named. It used to be one `command -v docker` guard around the
# loop, so a machine without docker walked no service at all and then printed the pass line for a
# question nobody had asked.
if ! docker_usable; then
    skip "every service in those files names an image or a build context" \
         "no docker here that both exists and answers docker info, and only docker knows what counts as a service"
elif ! PYTHON="$(find_runnable_python)"; then
    skip "every service in those files names an image or a build context" \
         "no Python 3.11 or newer on PATH (tried python3, python and py), so compose's own JSON could not be read"
else
    for f in "${compose_files[@]}"; do
        while IFS= read -r svc; do
            [[ -z "${svc}" ]] && continue
            services_seen=$((services_seen + 1))
            body="$(docker compose -f "$(host_path "${f}")" config --no-interpolate --format json 2>/dev/null                 | "${PYTHON}" -c "
import json, sys
name = sys.argv[1]
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
s = (d.get('services') or {}).get(name) or {}
print('yes' if ('image' in s or 'build' in s) else 'no')
" "${svc}" 2>/dev/null)"
            [[ "${body}" == no ]] && missing_image+=("$(basename "${f}"): ${svc}")
        done < <(docker compose -f "$(host_path "${f}")" config --services 2>/dev/null || true)
    done

    if [[ "${services_seen}" -eq 0 ]]; then
        fail "not one service was found in any compose file, so this check proves nothing" \
             "${#compose_files[@]} file(s) were read"
    elif [[ ${#missing_image[@]} -eq 0 ]]; then
        pass "all ${services_seen} services in those files name an image or a build context"
    else
        fail "${#missing_image[@]} compose file(s) have a service with nothing to run" "${missing_image[*]}"
    fi
fi

# --- documentation links point at something -------------------------------------------------------
# Every markdown file git would ship, tracked or new, so the ignored trees (e2e/runs, e2e/.cache, any
# node_modules) are left out by .gitignore rather than by a list kept here, and the three tracked
# directory symlinks into .agents/ are listed once as links instead of read twice. A relative link
# must name a path that exists with exactly that case, because GitHub serves a case-sensitive tree
# and a Windows or macOS filesystem would hide the difference. A fragment must name a heading or an
# explicit HTML anchor in the markdown file it points at. Links with a scheme are tier 2's business.
#
# Two exclusions, both named in the output. Files under openspec/schemas/*/templates/ are copied to
# another directory before anyone reads them, so their links resolve from the destination and not
# from where they sit. A link to a file a proposal plans to create is listed in
# doc_links_allowed.txt with the reason, and an entry whose target now exists or that no link uses
# any longer fails, so the list cannot outlive what it excuses.
#
# This section asked only local-dev/ and homelab/ until 2026-10-15, and with grep rather than a
# parser. Pointed at the rest of the tree it found four links to files deleted months earlier.
joined() { local out; printf -v out '%s; ' "$@"; printf '%s' "${out%; }"; }

docs_claim="every relative documentation link in the repository points at a file and heading that exist"
if ! command -v git >/dev/null 2>&1; then
    skip "${docs_claim}" "no git here, and only git knows which markdown files the repository ships"
elif ! PYTHON="$(find_runnable_python)"; then
    skip "${docs_claim}" "no Python 3.11 or newer on PATH (tried python3, python and py), so the links could not be parsed"
else
    links_status=0
    links_report="$(cd "${REPO_ROOT}" && "${PYTHON}" - <<'PYEOF'
import os
import re
import subprocess
import sys
import unicodedata
from urllib.parse import unquote

ALLOWLIST = 'e2e/tier1/doc_links_allowed.txt'
TEMPLATE_TREE = re.compile(r'^openspec/schemas/[^/]+/templates/')
FENCE = re.compile(r'^ {0,3}(`{3,}|~{3,})')
HEADING = re.compile(r'^ {0,3}#{1,6}[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$')
INLINE_CODE = re.compile(r'(`+)(.+?)\1')
INLINE_LINK = re.compile(r'!?\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*(<[^>]*>|[^\s)]+(?:\([^\s)]*\)[^\s)]*)*)'
                         r'(?:\s+(?:"[^"]*"|\'[^\']*\'|\([^)]*\)))?\s*\)')
REFERENCE_DEFINITION = re.compile(r'^ {0,3}\[[^\]]+\]:\s*(<[^>]*>|\S+)')
HTML_LINK = re.compile(r'<(?:a|img)\b[^>]*?\b(?:href|src)\s*=\s*"([^"]*)"', re.IGNORECASE)
HTML_ANCHOR = re.compile(r'<a\b[^>]*?\b(?:id|name)\s*=\s*"([^"]*)"', re.IGNORECASE)
SCHEME = re.compile(r'^[A-Za-z][A-Za-z0-9+.-]*:')


# Bytes rather than print, for the carriage return reason control_characters.sh records.
def report(*lines):
    sys.stdout.buffer.write(('\n'.join(lines) + '\n').encode('utf-8'))


def read(path):
    with open(path, encoding='utf-8', errors='replace') as handle:
        return handle.read()


def prose_lines(text):
    fence = None
    for number, line in enumerate(text.split('\n'), 1):
        match = FENCE.match(line)
        if fence:
            if match and match.group(1)[0] == fence[0] and len(match.group(1)) >= len(fence):
                fence = None
            continue
        if match:
            fence = match.group(1)
        elif not line.startswith(('    ', '\t')):
            yield number, line


# GitHub's rule: the heading's text, lowercased, keeping letters, marks, numbers, spaces, hyphens and
# underscores, spaces turned into hyphens, and a repeat numbered from -1.
def slug(heading):
    text = re.sub(r'<[^>]+>', '', heading)
    text = INLINE_CODE.sub(lambda m: m.group(2), text)
    text = re.sub(r'!?\[([^\]]*)\]\([^)]*\)', r'\1', text)
    kept = (c for c in text.strip().lower() if c in ' -_' or unicodedata.category(c)[0] in 'LMN')
    return ''.join(kept).replace(' ', '-')


anchor_cache = {}


def anchors_of(path):
    if path not in anchor_cache:
        found, seen = set(), {}
        for _, line in prose_lines(read(path)):
            found.update(HTML_ANCHOR.findall(line))
            match = HEADING.match(line)
            if match:
                base = slug(match.group(1))
                found.add(base if base not in seen else '%s-%d' % (base, seen[base]))
                seen[base] = seen.get(base, 0) + 1
        anchor_cache[path] = found
    return anchor_cache[path]


def exists_with_exact_case(relative):
    current = '.'
    for part in relative.split('/'):
        if part == '.':
            continue
        try:
            if part not in os.listdir(current):
                return False
        except OSError:
            return False
        current = os.path.join(current, part)
    return True


def targets_in(text):
    for number, line in prose_lines(text):
        line = INLINE_CODE.sub('', line)
        for target in INLINE_LINK.findall(line) + HTML_LINK.findall(line):
            yield number, target
        match = REFERENCE_DEFINITION.match(line)
        if match:
            yield number, match.group(1)


listing = subprocess.run(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', '*.md'],
                         capture_output=True)
if listing.returncode != 0:
    report('ERROR git ls-files failed: %s' % listing.stderr.decode('utf-8', 'replace').strip().replace('\n', ' '))
    raise SystemExit(0)

allowed, allowlist_errors = {}, []
for number, line in enumerate(read(ALLOWLIST).split('\n') if os.path.isfile(ALLOWLIST) else [], 1):
    if not line.strip() or line.startswith('#'):
        continue
    pair, bar, reason = line.partition(' | ')
    source, arrow, target = pair.partition(' -> ')
    if not (bar and arrow and reason.strip()):
        allowlist_errors.append('%s line %d does not read as "<file> -> <target> | <reason>"' % (ALLOWLIST, number))
        continue
    allowed[(source.strip(), target.strip())] = False

paths = sorted({p for p in listing.stdout.decode('utf-8', 'surrogateescape').split('\0') if p})
files, links, anchors, excluded, dead = 0, 0, 0, [], []
for path in paths:
    if not os.path.isfile(path):
        continue
    if TEMPLATE_TREE.match(path):
        excluded.append(path)
        continue
    files += 1
    directory = os.path.dirname(path)
    for number, raw in targets_in(read(path)):
        target = raw[1:-1] if raw.startswith('<') and raw.endswith('>') else raw
        if not target or SCHEME.match(target):
            continue
        location, _, fragment = target.partition('#')
        location = unquote(location.split('?', 1)[0])
        where = '%s:%d -> %s' % (path, number, raw)
        anchor_file = path
        if location:
            links += 1
            resolved = os.path.normpath(os.path.join(directory, location)).replace(os.sep, '/')
            if location.startswith('/'):
                dead.append(where + ' (an absolute path, which means nothing on another machine)')
                continue
            if resolved == '..' or resolved.startswith('../'):
                dead.append(where + ' (outside the repository)')
                continue
            if (path, resolved) in allowed:
                allowed[(path, resolved)] = True
                continue
            if not exists_with_exact_case(resolved):
                dead.append(where)
                continue
            anchor_file = resolved
        if fragment and anchor_file.endswith('.md') and os.path.isfile(anchor_file):
            anchors += 1
            if unquote(fragment) not in anchors_of(anchor_file):
                dead.append(where + ' (no heading or anchor by that name)')

stale = []
for (source, target), used in sorted(allowed.items()):
    if exists_with_exact_case(target):
        stale.append('%s -> %s now exists' % (source, target))
    elif not used:
        stale.append('%s -> %s is linked from nowhere' % (source, target))

report('FILES %d' % files, 'LINKS %d' % links, 'ANCHORS %d' % anchors, 'ALLOWED %d' % len(allowed),
       'EXCLUDED %d %s' % (len(excluded), ' '.join(excluded)),
       *('DEAD ' + d for d in dead), *('STALE ' + s for s in stale), *('ERROR ' + e for e in allowlist_errors))
PYEOF
)" || links_status=$?
    assert_python_ran "${links_status}" "compose files and documentation links"

    md_files=0 n_links=0 n_anchors=0 n_allowed=0 excluded=""
    dead_links=() stale_allowed=() link_errors=()
    while IFS= read -r line; do
        case "${line}" in
            FILES\ *)    md_files="${line#FILES }" ;;
            LINKS\ *)    n_links="${line#LINKS }" ;;
            ANCHORS\ *)  n_anchors="${line#ANCHORS }" ;;
            ALLOWED\ *)  n_allowed="${line#ALLOWED }" ;;
            EXCLUDED\ *) excluded="${line#EXCLUDED }" ;;
            DEAD\ *)     dead_links+=("${line#DEAD }") ;;
            STALE\ *)    stale_allowed+=("${line#STALE }") ;;
            ERROR\ *)    link_errors+=("${line#ERROR }") ;;
        esac
    done <<<"${links_report}"

    if [[ ${#link_errors[@]} -gt 0 ]]; then
        fail "the documentation link scan could not read its inputs" "$(joined "${link_errors[@]}")"
    elif [[ "${n_links}" -eq 0 ]]; then
        fail "no relative markdown links found anywhere in the repository, so this check proves nothing" \
             "${md_files} markdown file(s) were read, and README.md alone links a dozen"
    elif [[ ${#dead_links[@]} -eq 0 ]]; then
        pass "all ${n_links} relative links and ${n_anchors} heading anchors in ${md_files} markdown files point at something that exists"
    else
        fail "${#dead_links[@]} of ${n_links} relative documentation links or anchors point at nothing" \
             "$(joined "${dead_links[@]}")"
    fi

    if [[ ${#stale_allowed[@]} -eq 0 ]]; then
        pass "all ${n_allowed} planned link targets in e2e/tier1/doc_links_allowed.txt are still planned and still linked"
    else
        fail "${#stale_allowed[@]} entries in e2e/tier1/doc_links_allowed.txt no longer excuse anything" \
             "$(joined "${stale_allowed[@]}")"
    fi

    if [[ -n "${excluded}" && "${excluded}" != "0 " ]]; then
        dim "${excluded%% *} file(s) not scanned, because their links resolve from where they are copied to: ${excluded#* }"
    fi
fi

finish "compose files and documentation links"
