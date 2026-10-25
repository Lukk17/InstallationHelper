#!/usr/bin/env bash
#
# Tier 1: every list of the homelab's .internal names holds the same names as the one setup table.
#
# homelab/nginx_proxy_manager.md keeps every .internal name in one table, under "Every .internal name".
# The same names are listed again as the INTERNAL_DNS_NAMES example in homelab/internal_ca.md, the
# names the https certificate covers, and in the services table of homelab/README_HOMELAB.md. Until
# 2026-10-25 the proxy page spread them over three tables, the services table had no proxmox.internal
# although the certificate covered it, and nothing compared any of the lists, docs/regression_ledger.md
# 10.205.
#
# The setup table must be the only table on its page whose first column is "Domain name". Every comma
# list of two or more .internal names on a line of internal_ca.md or README_HOMELAB.md that names
# INTERNAL_DNS_NAMES or <names> must hold exactly the table's names, and at least one such list must
# exist, because a comparison against nothing proves nothing. The Internal name column of the services
# table must hold the same set. homepage_dashboard.md and uptime_kuma.md name only some of the names on
# purpose, so every name they do mention must be in the table.
#
# The reader is first run against planted pages and must report exactly the planted mismatches, so a
# reader that finds nothing cannot pass for pages that agree.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

info "Tier 1: every list of .internal names matches the setup table"

require_python "every list of .internal names matches the setup table" "internal names parity"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

# compare <homelab dir>  ->  prints "FAIL<tab><where><tab><why>" per mismatch, then "COUNT<tab><names><tab><lists>"
compare() {
    "${PYTHON}" -I - "$1" <<'PYEOF'
import pathlib
import re
import sys

ROOT = pathlib.Path(sys.argv[1])
NAME = re.compile(r'(?<![\w.-])([a-z0-9-]+\.internal)\b')
NAME_LIST = re.compile(r'(?<![\w.-])[a-z0-9-]+\.internal(?:,[a-z0-9-]+\.internal)+(?![\w.-])')
failures = []


def cells(line):
    return [c.strip() for c in line.strip().strip('|').split('|')]


def tables(path):
    """Every table on the page, as (header, [(line number, cells)])."""
    lines = path.read_text(encoding='utf-8').splitlines()
    found = []
    i = 0
    while i < len(lines):
        if lines[i].startswith('|') and i + 1 < len(lines) and lines[i + 1].startswith('|') and set(lines[i + 1].replace('|', '').strip()) <= set('-: '):
            header = cells(lines[i])
            rows = []
            i += 2
            while i < len(lines) and lines[i].startswith('|'):
                rows.append((i + 1, cells(lines[i])))
                i += 1
            found.append((header, rows))
        else:
            i += 1
    return found


def report(where, got, expected):
    for name in sorted(got - expected):
        failures.append((where, 'lists {}, which the setup table does not'.format(name)))
    for name in sorted(expected - got):
        failures.append((where, 'lacks {}, which the setup table lists'.format(name)))


setup_page = ROOT / 'nginx_proxy_manager.md'
setup_tables = [t for t in tables(setup_page) if t[0] and t[0][0] == 'Domain name']
if len(setup_tables) != 1 or not setup_tables[0][1]:
    print('FAIL\t{}\texpected exactly one table whose first column is Domain name, with rows, found {}'.format(setup_page.name, len(setup_tables)))
    raise SystemExit
expected = set()
for number, row in setup_tables[0][1]:
    names = NAME.findall(row[0])
    if len(names) != 1:
        failures.append(('{}:{}'.format(setup_page.name, number), 'the Domain name cell holds {} .internal names, not one'.format(len(names))))
    expected.update(names)

lists = 0
for page in ('internal_ca.md', 'README_HOMELAB.md'):
    for number, line in enumerate((ROOT / page).read_text(encoding='utf-8').splitlines(), 1):
        if 'INTERNAL_DNS_NAMES' not in line and '<names>' not in line:
            continue
        for found in NAME_LIST.findall(line):
            lists += 1
            report('{}:{}'.format(page, number), set(found.split(',')), expected)
if lists == 0:
    failures.append(('internal_ca.md', 'no INTERNAL_DNS_NAMES example lists the names, so there is nothing to compare'))

services_page = ROOT / 'README_HOMELAB.md'
services = [t for t in tables(services_page) if 'Internal name' in t[0]]
if len(services) != 1 or not services[0][1]:
    failures.append((services_page.name, 'expected exactly one table with an Internal name column, with rows, found {}'.format(len(services))))
else:
    header, rows = services[0]
    column = header.index('Internal name')
    got = {name for _, row in rows for name in NAME.findall(row[column])}
    report('{}:{}'.format(services_page.name, rows[0][0]), got, expected)

for page in ('homepage_dashboard.md', 'uptime_kuma.md'):
    for number, line in enumerate((ROOT / page).read_text(encoding='utf-8').splitlines(), 1):
        for name in sorted(set(NAME.findall(line)) - expected):
            failures.append(('{}:{}'.format(page, number), 'names {}, which the setup table does not'.format(name)))

for where, why in failures:
    print('FAIL\t{}\t{}'.format(where, why))
print('COUNT\t{}\t{}'.format(len(expected), lists))
PYEOF
}

planted="${work}/homelab"
mkdir -p "${planted}"
cat >"${planted}/nginx_proxy_manager.md" <<'EOF'
| Domain name | Scheme | Forward hostname |
|---|---|---|
| `alpha.internal` | http | `alpha` |
| `beta.internal` | https | `<proxmox-host>` |
EOF
cat >"${planted}/internal_ca.md" <<'EOF'
| `INTERNAL_DNS_NAMES` | Every name in the setup table, separated by commas |

<names>          alpha.internal,gamma.internal
EOF
cat >"${planted}/README_HOMELAB.md" <<'EOF'
| Service | Internal name | Host port |
|---|---|---|
| Alpha | `alpha.internal` | 1 |
| Beta | `beta.internal`, on the host | 2 |
| Redis | none, TCP only | 3 |
| Epsilon | `epsilon.internal` | 4 |
EOF
cat >"${planted}/homepage_dashboard.md" <<'EOF'
        href: http://alpha.internal
        description: also at \\alpha.internal\files, see host.docker.internal
EOF
cat >"${planted}/uptime_kuma.md" <<'EOF'
Open `http://delta.internal` once the proxy entry exists, never an `.internal` name as a target.
EOF

expected_planted="$(printf '%s\t%s\t%s\n' \
    FAIL internal_ca.md:3 'lists gamma.internal, which the setup table does not' \
    FAIL internal_ca.md:3 'lacks beta.internal, which the setup table lists' \
    FAIL README_HOMELAB.md:3 'lists epsilon.internal, which the setup table does not' \
    FAIL uptime_kuma.md:1 'names delta.internal, which the setup table does not')"
expected_planted+=$'\nCOUNT\t2\t1'

status=0
planted_output="$(compare "${planted}" 2>&1)" || status=$?
if [[ ${status} -eq 0 && "${planted_output}" == "${expected_planted}" ]]; then
    pass "the reader reports exactly the four planted mismatches"
else
    fail "the reader reports exactly the four planted mismatches" \
         "exit ${status}. Output: ${planted_output}"
fi

status=0
report="$(compare "${REPO_ROOT}/homelab" 2>&1)" || status=$?
assert_python_ran "${status}" "internal names parity"

failures="$(grep '^FAIL' <<<"${report}" || true)"
counted="$(awk -F'\t' '$1 == "COUNT" {print $2 " names, compared with " $3 " INTERNAL_DNS_NAMES example(s)"}' <<<"${report}")"
if [[ -z "${failures}" && -n "${counted}" ]]; then
    pass "every list of .internal names matches the setup table in homelab/nginx_proxy_manager.md, ${counted}"
else
    while IFS=$'\t' read -r _ where why; do
        fail "a list of .internal names disagrees with the setup table in homelab/nginx_proxy_manager.md" "homelab/${where}: ${why}"
    done <<<"${failures}"
fi

finish "internal names parity"
