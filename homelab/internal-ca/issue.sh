#!/bin/sh
# -----------------------------------------------------------------------------
# Script: issue.sh
# Description: Issues the leaf certificate for the .internal names from the local CA, and installs the Nginx Proxy Manager include that serves it on port 443.
# Usage: issue.sh
# Requires: POSIX sh, openssl 3, base64, run by the internal-ca service of homelab/compose.yaml
# Environment:
#   INTERNAL_CA_CERT_B64  base64 of the CA certificate in PEM form
#   INTERNAL_CA_KEY_B64   base64 of the CA private key in PEM form
#   INTERNAL_DNS_NAMES    comma separated names, each ending in .internal
# Files:
#   /internal-ca/server_proxy.conf  the include, copied to /data/nginx/custom/server_proxy.conf
#   /data/custom_ssl/internal/      fullchain.pem and privkey.pem, owned like /data/custom_ssl
# The leaf is issued again when it is missing, when the name list changed, when another CA signed it, or when fewer than 30 days remain.
# Exit codes:
#   0  success, the certificate was issued or is still good
#   1  general error
#   2  misuse (a variable is empty, a name is not under .internal)
#   3  the CA is unusable (not a CA, key does not match, no name constraint for .internal)
# -----------------------------------------------------------------------------
set -eu

readonly LEAF_DAYS=397
readonly RENEW_SECONDS=2592000
readonly TEMPLATE=/internal-ca/server_proxy.conf
readonly CERT_DIR=/data/custom_ssl/internal
readonly CUSTOM_DIR=/data/nginx/custom
readonly OWNER_REFERENCE=/data/custom_ssl
readonly NAME_PATTERN='^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+internal$'

log() { printf '[internal-ca] %s\n' "$*"; }
die() { printf '[internal-ca] ERROR: %s\n' "$2" >&2; exit "$1"; }

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

# Prints the wanted names, lowercased, sorted and unique, one per line.
wanted_names() {
    printf '%s\n' "${INTERNAL_DNS_NAMES}" | tr ',' '\n' | tr -d ' \t\r' | tr 'A-Z' 'a-z' | sed '/^$/d' | sort -u
}

# Prints the DNS names in the subjectAltName of $1, sorted, one per line.
certificate_names() {
    openssl x509 -in "$1" -noout -ext subjectAltName 2>/dev/null | sed '1d' | tr ',' '\n' | sed -n 's/^ *DNS://p' | sort -u
}

load_ca() {
    [ -n "${INTERNAL_CA_CERT_B64:-}" ] || die 2 "INTERNAL_CA_CERT_B64 is empty"
    [ -n "${INTERNAL_CA_KEY_B64:-}" ] || die 2 "INTERNAL_CA_KEY_B64 is empty"
    printf '%s' "${INTERNAL_CA_CERT_B64}" | base64 -d >"${work}/ca.crt" 2>/dev/null || die 3 "INTERNAL_CA_CERT_B64 is not valid base64"
    (umask 077 && printf '%s' "${INTERNAL_CA_KEY_B64}" | base64 -d >"${work}/ca.key" 2>/dev/null) || die 3 "INTERNAL_CA_KEY_B64 is not valid base64"
    openssl x509 -in "${work}/ca.crt" -noout 2>/dev/null || die 3 "INTERNAL_CA_CERT_B64 does not hold a PEM certificate"
    openssl x509 -in "${work}/ca.crt" -noout -ext basicConstraints 2>/dev/null | grep -q 'CA:TRUE' || die 3 "the CA certificate does not say CA:TRUE"
    constraints="$(openssl x509 -in "${work}/ca.crt" -noout -ext nameConstraints 2>/dev/null || true)"
    case "${constraints}" in
        *critical*DNS:internal*) ;;
        *) die 3 "the CA certificate has no critical name constraint permitting DNS:internal, so a leaked key could sign any name" ;;
    esac
    ca_public="$(openssl x509 -in "${work}/ca.crt" -noout -pubkey)"
    key_public="$(openssl pkey -in "${work}/ca.key" -pubout 2>/dev/null)" || die 3 "INTERNAL_CA_KEY_B64 does not hold a PEM private key"
    [ "${ca_public}" = "${key_public}" ] || die 3 "the CA private key does not belong to the CA certificate"
}

check_names() {
    [ -n "${INTERNAL_DNS_NAMES:-}" ] || die 2 "INTERNAL_DNS_NAMES is empty"
    wanted_names >"${work}/names"
    [ -s "${work}/names" ] || die 2 "INTERNAL_DNS_NAMES holds no name"
    bad="$(grep -Ev "${NAME_PATTERN}" "${work}/names" || true)"
    [ -z "${bad}" ] || die 2 "not a plain name under .internal: $(printf '%s' "${bad}" | tr '\n' ' ')"
}

# Prints why the current leaf must be issued again, or nothing when it is still good.
reason_to_issue() {
    leaf="${CERT_DIR}/fullchain.pem"
    if [ ! -s "${leaf}" ] || [ ! -s "${CERT_DIR}/privkey.pem" ]; then
        echo "no certificate yet"
    elif ! openssl verify -CAfile "${work}/ca.crt" -purpose sslserver "${leaf}" >/dev/null 2>&1; then
        echo "the certificate does not verify against the current CA"
    elif ! openssl x509 -in "${leaf}" -noout -checkend "${RENEW_SECONDS}" >/dev/null 2>&1; then
        echo "fewer than 30 days remain"
    elif [ "$(certificate_names "${leaf}")" != "$(cat "${work}/names")" ]; then
        echo "the name list changed"
    fi
}

issue() {
    first="$(head -n 1 "${work}/names")"
    alt_names="$(sed 's/^/DNS:/' "${work}/names" | paste -s -d ',' -)"
    cat >"${work}/leaf.ext" <<EOF
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
subjectAltName = ${alt_names}
EOF
    (umask 077 && openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "${work}/privkey.pem" 2>/dev/null)
    openssl req -new -key "${work}/privkey.pem" -subj "/CN=${first}" -out "${work}/leaf.csr"
    openssl x509 -req -in "${work}/leaf.csr" -CA "${work}/ca.crt" -CAkey "${work}/ca.key" \
        -set_serial "0x$(openssl rand -hex 16)" -days "${LEAF_DAYS}" -sha256 -extfile "${work}/leaf.ext" \
        -out "${work}/fullchain.pem" 2>/dev/null
    openssl verify -CAfile "${work}/ca.crt" -purpose sslserver "${work}/fullchain.pem" >/dev/null \
        || die 1 "the new certificate does not verify against the CA"

    owner="$(stat -c '%u:%g' "${OWNER_REFERENCE}")"
    mkdir -p "${CERT_DIR}"
    chmod 755 "${CERT_DIR}"
    install -m 600 -o "${owner%:*}" -g "${owner#*:}" "${work}/privkey.pem" "${CERT_DIR}/privkey.pem.new"
    install -m 644 -o "${owner%:*}" -g "${owner#*:}" "${work}/fullchain.pem" "${CERT_DIR}/fullchain.pem.new"
    mv -f "${CERT_DIR}/privkey.pem.new" "${CERT_DIR}/privkey.pem"
    mv -f "${CERT_DIR}/fullchain.pem.new" "${CERT_DIR}/fullchain.pem"
}

install_include() {
    [ -s "${TEMPLATE}" ] || die 1 "the include template ${TEMPLATE} is missing"
    owner="$(stat -c '%u:%g' "${OWNER_REFERENCE}")"
    mkdir -p "${CUSTOM_DIR}"
    install -m 644 -o "${owner%:*}" -g "${owner#*:}" "${TEMPLATE}" "${CUSTOM_DIR}/server_proxy.conf.new"
    mv -f "${CUSTOM_DIR}/server_proxy.conf.new" "${CUSTOM_DIR}/server_proxy.conf"
}

main() {
    [ "$#" -eq 0 ] || die 2 "issue.sh takes no arguments, it reads INTERNAL_CA_CERT_B64, INTERNAL_CA_KEY_B64 and INTERNAL_DNS_NAMES"
    load_ca
    check_names
    reason="$(reason_to_issue)"
    if [ -n "${reason}" ]; then
        log "issuing a new certificate: ${reason}"
        issue
    else
        log "the certificate is still good, nothing issued"
    fi
    install_include
    log "names: $(paste -s -d ' ' "${work}/names")"
    log "$(openssl x509 -in "${CERT_DIR}/fullchain.pem" -noout -enddate)"
    log "CA: $(openssl x509 -in "${work}/ca.crt" -noout -subject -fingerprint -sha256 | paste -s -d ' ' -)"
}

main "$@"
