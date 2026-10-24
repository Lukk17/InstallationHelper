# AGENTS.md for local-dev/

Rules for the local development stack. The services, ports, credentials and the Keycloak realm import are in [README_LOCAL_DEV.md](README_LOCAL_DEV.md), and [local-dev-docker-compose.yaml](local-dev-docker-compose.yaml) is the source of truth for images, ports and pins.

### Before you work here

1. Before changing an image version, read "Refreshing an image pin" in [README_LOCAL_DEV.md](README_LOCAL_DEV.md).
2. Before changing the Keycloak realm or the Postgres image, read the Services section of [README_LOCAL_DEV.md](README_LOCAL_DEV.md) and [auth/Keycloak/README.md](auth/Keycloak/README.md).
3. Before adding a page here, add it to the "Configuration deep-dives" table of [README_LOCAL_DEV.md](README_LOCAL_DEV.md), which is this folder's documentation map.

### Rules no check catches

1. No tier of the e2e harness starts this stack. [../e2e/tier1/compose_and_docs.sh](../e2e/tier1/compose_and_docs.sh) only proves the compose file parses, and [../e2e/tier1/keycloak_realm_import.sh](../e2e/tier1/keycloak_realm_import.sh) only reads the realm export. Say so when you report a change here as verified.
2. `--import-realm` imports only a realm that is absent. Editing the realm export changes nothing on a machine whose `postgres_data` volume already exists.
3. When a port, a credential or an image changes, update the Services table in [README_LOCAL_DEV.md](README_LOCAL_DEV.md) in the same change.
