#!/bin/bash
# This script is executed only once, when the database is first created.
# It sets up all required users and databases. The keycloak database is left empty on purpose:
# Keycloak creates its own schema on first boot and imports the realm itself.

# Exit immediately if any command fails
set -e

# The '-v ON_ERROR_STOP=1' flag ensures that the script will exit on any SQL error.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    ALTER USER postgres WITH PASSWORD 'local';

    CREATE USER keycloak WITH PASSWORD 'local';
    CREATE DATABASE keycloak;

    GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;

EOSQL

echo "Users and databases created successfully."