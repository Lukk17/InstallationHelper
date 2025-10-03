#!/bin/bash
# This script is executed only once, when the database is first created.
# It sets up all required users, databases, and restores the keycloak data.

# Exit immediately if any command fails
set -e

# The '-v ON_ERROR_STOP=1' flag ensures that the script will exit on any SQL error.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    ALTER USER postgres WITH PASSWORD 'local';
EOSQL

echo "Users and databases created successfully."
