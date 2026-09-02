#!/usr/bin/env bash
# Regenerate the local certificate authority and the leaf it signs.
#
# Run from this directory. Both are committed, so this is only needed when a name
# is added, a key is rotated, or the ten years run out. Reissuing the leaf costs a
# rebuild of the Keycloak image, which copies it in, and a restart. Reissuing the
# authority also means re-importing it in every trust store that holds it, which is
# the operating system store and any JVM, Node or Python trust store set up from
# local-dev/auth/README.md.
set -euo pipefail

DAYS=3650

openssl req -x509 -newkey rsa:4096 -sha256 -days "$DAYS" -nodes \
  -config ca.cnf -keyout localhost-ca.key -out localhost-ca.crt

openssl req -new -newkey rsa:2048 -sha256 -nodes \
  -config leaf.cnf -keyout localhost.key -out localhost.csr

openssl x509 -req -in localhost.csr -sha256 -days "$DAYS" \
  -CA localhost-ca.crt -CAkey localhost-ca.key -CAcreateserial \
  -extfile leaf.cnf -extensions leaf_ext -out localhost.crt

rm -f localhost.csr localhost-ca.srl

openssl verify -CAfile localhost-ca.crt localhost.crt
