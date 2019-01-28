#!/usr/bin/env bash

set -euo pipefail

ROOT=$(dirname "$0")
MIGRATIONS_FOLDER="$ROOT/migrations"
FIXTURES_FOLDER="$ROOT/fixtures"
export DATABASE_URL="postgres://north_tests@127.0.0.1/north_tests"

log() {
    printf "[%s] [postgres] %s\\n" "$(date +%Y-%m-%dT%H:%M:%S)" "$@"
}

log "Cleaning up."
echo "drop database north_tests" | psql -dpostgres || true
echo "drop role north_tests" | psql -dpostgres || true
echo "create role north_tests with password 'north_tests' login" | psql -dpostgres
echo "create database north_tests" | psql -dpostgres
echo "grant all privileges on database north_tests to north_tests" | psql -dpostgres
rm -fr "$MIGRATIONS_FOLDER"
mkdir -p "$MIGRATIONS_FOLDER"

log "Creating first migration."
raco north create -p "$MIGRATIONS_FOLDER" add-users-table

log "Remove created migration."
rm "$MIGRATIONS_FOLDER/"*

log "Copy fixture migrations."
cp "$FIXTURES_FOLDER/"*.sql "$MIGRATIONS_FOLDER/"

log "Dry run migrations."
raco north migrate -p "$MIGRATIONS_FOLDER" | \
    diff - "$FIXTURES_FOLDER/01-dry-run-migrate.out"

log "Force migrate."
raco north migrate -fp "$MIGRATIONS_FOLDER" | \
    diff - "$FIXTURES_FOLDER/02-force-run-migrate.out"

log "Dry run rollback."
raco north rollback -p "$MIGRATIONS_FOLDER" | \
    diff - "$FIXTURES_FOLDER/03-dry-run-rollback.out"

log "Dry run full rollback."
raco north rollback -p "$MIGRATIONS_FOLDER" base | \
    diff - "$FIXTURES_FOLDER/04-dry-run-rollback.out"

log "Force run rollback."
raco north rollback -fp "$MIGRATIONS_FOLDER" | \
    diff - "$FIXTURES_FOLDER/05-force-run-rollback.out"

log "Dry run full rollback."
raco north rollback -p "$MIGRATIONS_FOLDER" base | \
    diff - "$FIXTURES_FOLDER/06-dry-run-rollback.out"

log "Force run full rollback."
raco north rollback -fp "$MIGRATIONS_FOLDER" base | \
    diff - "$FIXTURES_FOLDER/07-force-run-rollback.out"
