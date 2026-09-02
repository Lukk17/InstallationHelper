#!/usr/bin/env bash
#
# Tier 1: the committed Keycloak realm export is one Keycloak will actually import.
#
# The local-dev stack seeds Keycloak from local-dev/auth/Keycloak/export/config/local-realm-export.json.
# The Dockerfile copies that file into /opt/keycloak/data/import/ and the entrypoint passes
# --import-realm, so a file Keycloak's import path refuses is not a warning in a log, it is a server
# that never starts. The regression ledger entry "The realm in the dump could not be imported by
# Keycloak's own importer" has the whole story: the first cold start crash looped for four minutes
# while the health check said `starting`, which is indistinguishable from a slow boot until somebody
# reads `docker logs`.
#
# That instance is fixed and this check is about the next one. --import-realm never touches a realm
# that already exists, so every machine whose database predates the fix still holds the object, and an
# export taken there and committed brings it straight back. The person doing that would see a green
# diff, a valid JSON file, and a stack that works on their machine.
#
# Four constructs belong to Keycloak's `scripts` feature, which is a preview feature and off unless
# the server is started with it on. What each one does to an import was measured rather than assumed,
# on quay.io/keycloak/keycloak:26.5 at the digest this repository's own Dockerfile pins, by importing
# a realm carrying it and reading what the server then did:
#
#   authorization policy, type js         the server exits 1 during import
#                                         `ERROR: Script upload is disabled`
#   authorization policy, type script-*   the server exits 1 during import
#                                         `ERROR: Couldn't find policy provider with type [script-probe.js]`
#   protocol mapper, oidc-script-based-   `Realm imported`, `Import finished successfully`, the server
#   protocol-mapper                       starts, and the mapper is gone: the client's
#                                         protocol-mappers/models answers `[ ]`
#   authenticator, auth-script-based      `Realm imported`, `Import finished successfully`, the server
#                                         starts, and the execution is stored verbatim on a flow that
#                                         cannot resolve its provider, so that flow's own /executions
#                                         endpoint answers 404 while the realm still names it as the
#                                         browser flow
#
# So the first two refuse to start and the last two are worse in a quieter way: the import reports
# success and the realm is not the realm that was exported. Both shapes are why this is parsed here
# rather than left to a person to notice, and both are the same underlying fact, that a realm carrying
# any of them can only be moved between machines by copying database tables underneath Keycloak, which
# is exactly what the SQL dump this seed replaced was doing.
#
# Deployed scripts, the ones shipped inside a JAR rather than uploaded in the realm, take a provider id
# of `script-<name>` in all four positions, which is why the prefix is matched as well as the exact
# ids. Not covered, and deliberately: whether the realm is otherwise semantically coherent. A client
# referring to a role that does not exist, a flow referring to a missing sub-flow, a mapper with a
# broken config, none of that is asked here, because answering it honestly means running Keycloak,
# which is not a tier 1 question. This check answers the one class that has already cost this
# repository a boot loop, plus the three cheap questions below.
#
# The three cheap ones are there because an export that imports cleanly and has lost its client is
# just as broken for a reader following the readme, which promises the realm `local`, the confidential
# client `local-client` and the test user `lukk`. Those cost the same milliseconds as the parse.
#
# The JSON is parsed rather than grepped. `kc.sh export` writes `"type" : "js"` with a space on each
# side of the colon, and the first guard written against this defect was
# `grep -c '"type": "js"'`, which answers 0 on every file including one carrying the policy. That
# wrong guard is its own entry in the ledger. Parsing sidesteps the question of how the exporter
# happens to space its punctuation this release.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

EXPORT_JSON="${REPO_ROOT}/local-dev/auth/Keycloak/export/config/local-realm-export.json"
KEYCLOAK_DOCKERFILE="${REPO_ROOT}/local-dev/auth/Keycloak/Dockerfile"

# What the documentation promises a reader will find in this realm.
EXPECTED_REALM="local"
EXPECTED_CLIENT="local-client"
EXPECTED_USER="lukk"

info "Tier 1: the Keycloak realm export Keycloak has to import"

# The premise, asserted first because it is the only thing here that needs neither the export to
# exist nor a Python to read it with. Everything below matters only while this file is still what
# seeds the server, and a check that keeps asserting about a file nothing imports is a check that
# has quietly stopped meaning anything.
#
# Both halves are anchored to the directive that carries them rather than matched anywhere in the
# file. Written without the anchor, this passed over a Dockerfile whose COPY was commented out and
# whose entrypoint had lost the flag, with `# was: --import-realm` left behind, which is the exact
# state the assertion exists to refuse and the likeliest shape for a person to leave it in. The two
# are also counted separately, because they rot separately and one message covering both leaves the
# reader to diff the file to learn which happened.
copies_export=0
imports_realm=0
if [[ -f "${KEYCLOAK_DOCKERFILE}" ]]; then
    if grep -Eq '^[[:space:]]*COPY[[:space:]].*local-realm-export\.json[[:space:]]+/opt/keycloak/data/import/' "${KEYCLOAK_DOCKERFILE}"; then
        copies_export=1
    fi
    if grep -Eq '^[[:space:]]*(ENTRYPOINT|CMD)[[:space:]].*--import-realm' "${KEYCLOAK_DOCKERFILE}"; then
        imports_realm=1
    fi
fi

if [[ ! -f "${KEYCLOAK_DOCKERFILE}" ]]; then
    fail "the Keycloak Dockerfile is missing, so nothing here proves the export is still the seed" \
         "${KEYCLOAK_DOCKERFILE}"
elif [[ "${copies_export}" -eq 1 && "${imports_realm}" -eq 1 ]]; then
    pass "the Keycloak image still copies that export into /opt/keycloak/data/import/ and still starts with --import-realm"
else
    rotted=()
    [[ "${copies_export}" -eq 1 ]] || rotted+=("no COPY directive puts local-realm-export.json into /opt/keycloak/data/import/")
    [[ "${imports_realm}" -eq 1 ]] || rotted+=("no ENTRYPOINT or CMD passes --import-realm")
    fail "the Keycloak image no longer seeds itself from that export, so everything else this check asserts is about a file nothing reads" \
         "${KEYCLOAK_DOCKERFILE}: $(printf '%s; ' "${rotted[@]}")"
fi

if [[ ! -f "${EXPORT_JSON}" ]]; then
    fail "the committed realm export is missing, and the Keycloak image has nothing to seed from" \
         "${EXPORT_JSON}"
    finish "keycloak realm import"
fi

# Only the five assertions below need an interpreter, and the premise above has already reported, so
# a machine without Python loses those five rather than the whole check. That is the split
# common.sh's own note on require_python asks for.
require_python "the committed realm export is one Keycloak will import" "keycloak realm import"

# git is not involved here and the heredoc owns stdin, so the path and the two expected names are
# passed as arguments. Written to stdout as bytes for the reason control_characters.sh gives: a
# text-mode print on Windows would put a carriage return on the end of every count this reads back.
scan_status=0
report="$("${PYTHON}" - "${EXPORT_JSON}" "${EXPECTED_CLIENT}" "${EXPECTED_USER}" <<'PYEOF'
import json
import sys

path, expected_client, expected_user = sys.argv[1], sys.argv[2], sys.argv[3]

# Every position in a realm representation where the disabled `scripts` feature can appear. The value
# is what a key has to hold for the object to need that feature: an exact provider id, or the
# `script-` prefix every deployed script takes.
SCRIPT_CARRIERS = (
    ('type', ('js',), 'an authorization policy'),
    ('authenticator', ('auth-script-based',), 'an authenticator'),
    ('protocolMapper', ('oidc-script-based-protocol-mapper',), 'a protocol mapper'),
)
DEPLOYED_PREFIX = 'script-'


def report(*lines):
    sys.stdout.buffer.write(('\n'.join(lines) + '\n').encode('utf-8'))


def walk(node, pointer, found):
    if isinstance(node, dict):
        for key, exact, what in SCRIPT_CARRIERS:
            value = node.get(key)
            if not isinstance(value, str):
                continue
            if value in exact or value.startswith(DEPLOYED_PREFIX):
                found.append('%s/%s = %r, %s that needs the scripts feature%s'
                             % (pointer, key, value, what,
                                (', named %r' % node['name']) if isinstance(node.get('name'), str) else ''))
        for key, value in node.items():
            walk(value, '%s/%s' % (pointer, key), found)
    elif isinstance(node, list):
        for index, value in enumerate(node):
            walk(value, '%s/%d' % (pointer, index), found)


try:
    with open(path, 'rb') as handle:
        realm = json.loads(handle.read().decode('utf-8'))
except (OSError, UnicodeDecodeError, ValueError) as problem:
    report('PARSE no %s' % str(problem).replace('\n', ' '))
    raise SystemExit(0)

if not isinstance(realm, dict):
    report('PARSE no the top level is a %s rather than an object' % type(realm).__name__)
    raise SystemExit(0)

report('PARSE yes')

clients = realm.get('clients') if isinstance(realm.get('clients'), list) else []
users = realm.get('users') if isinstance(realm.get('users'), list) else []

offenders = []
walk(realm, '', offenders)

report('REALM %s' % (realm.get('realm') if isinstance(realm.get('realm'), str) else '<absent>'),
       'CLIENT %s %d' % ('yes' if any(c.get('clientId') == expected_client for c in clients) else 'no',
                         len(clients)),
       'USER %s %d' % ('yes' if any(u.get('username') == expected_user for u in users) else 'no',
                       len(users)),
       'SCRIPTS %d' % len(offenders))
for offender in offenders[:12]:
    report('OFFENDER %s' % offender)
PYEOF
)" || scan_status=$?
assert_python_ran "${scan_status}" "keycloak realm import"

parse=""
realm_name=""
client_line=""
user_line=""
scripts=""
offenders=()
while IFS= read -r line; do
    case "${line}" in
        PARSE\ *)    parse="${line#PARSE }" ;;
        REALM\ *)    realm_name="${line#REALM }" ;;
        CLIENT\ *)   client_line="${line#CLIENT }" ;;
        USER\ *)     user_line="${line#USER }" ;;
        SCRIPTS\ *)  scripts="${line#SCRIPTS }" ;;
        OFFENDER\ *) offenders+=("${line#OFFENDER }") ;;
    esac
done <<<"${report}"

if [[ "${parse}" == "yes" ]]; then
    pass "the committed realm export parses as JSON"
else
    fail "the committed realm export is not valid JSON, so Keycloak has nothing to import" \
         "${EXPORT_JSON}: ${parse#no }"
    # Everything below reads fields out of a document that did not parse, so there is nothing left
    # to ask.
    finish "keycloak realm import"
fi

assert_eq "the committed realm export declares the realm the documentation promises" \
          "${EXPECTED_REALM}" "${realm_name}"

if [[ "${client_line%% *}" == "yes" ]]; then
    pass "the realm carries the ${EXPECTED_CLIENT} client, one of its ${client_line#* } clients"
else
    fail "the realm has lost the ${EXPECTED_CLIENT} client, which every documented token command uses" \
         "${client_line#* } client(s) in ${EXPORT_JSON}"
fi

if [[ "${user_line%% *}" == "yes" ]]; then
    pass "the realm carries the ${EXPECTED_USER} test user, one of its ${user_line#* } users"
else
    fail "the realm has lost the ${EXPECTED_USER} test user, which the readme tells the reader to log in as" \
         "${user_line#* } user(s) in ${EXPORT_JSON}"
fi

if [[ -z "${scripts}" ]]; then
    fail "the scan did not report how many script objects the realm carries" \
         "expected a line reading 'SCRIPTS <count>'"
elif [[ "${scripts}" -eq 0 ]]; then
    pass "no object in the realm needs Keycloak's disabled scripts feature"
else
    fail "the realm carries ${scripts} object(s) that need Keycloak's disabled scripts feature, so a fresh clone either crash loops with 'Script upload is disabled' while its health check reports starting, or imports a realm quietly missing them" \
         "${EXPORT_JSON}: $(printf '%s; ' "${offenders[@]}")"
fi

finish "keycloak realm import"
