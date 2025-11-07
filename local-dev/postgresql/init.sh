#!/bin/bash
# This script is executed only once, when the database is first created.
# It sets up all required users, databases, and restores the keycloak data.

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

echo "Restoring Keycloak database from dump..."
# skipping line thats creating DB, as locale in dump are not cross-platform
# windows one will not work on linux and vice versa
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "keycloak" < /docker-entrypoint-initdb.d/keycloak-dump.sql
#grep -v "CREATE DATABASE keycloak WITH" /docker-entrypoint-initdb.d/keycloak-dump.sql | psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "keycloak"
echo "Keycloak database restored successfully."