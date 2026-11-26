#!/bin/sh
# Creates one role and one database per app, from the PGAPP_<APP>_PASSWORD variables of the
# container (Komodo Variables, see apps/postgres/.komodo/komodo.toml): PGAPP_ACEROLA_SYNC_PASSWORD
# gives the role and the database `acerola_sync`, owned by it.
#
# Idempotent: an existing role only gets its password set again (so rotating the Komodo Variable
# and redeploying is enough), an existing database is left alone. The image's entrypoint runs it
# on the first boot (/docker-entrypoint-initdb.d); for an app added later, the Ansible step
# `postgres` runs it on the live container:
#
#   docker exec postgres sh /docker-entrypoint-initdb.d/10-apps.sh
set -eu

env | sed -n 's/^PGAPP_\([A-Z0-9_]*\)_PASSWORD=.*/\1/p' | sort | while read -r name; do
  app="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  password="$(printenv "PGAPP_${name}_PASSWORD")"

  psql -v ON_ERROR_STOP=1 -U postgres -d postgres -v app="$app" -v password="$password" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'app', :'password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app') \gexec
SELECT format('ALTER ROLE %I WITH PASSWORD %L', :'app', :'password') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'app', :'app')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'app') \gexec
SQL

  echo "postgres: role and database '$app' ready"
done
