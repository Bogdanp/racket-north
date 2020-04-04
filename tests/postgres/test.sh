#!/usr/bin/env bash

set -euo pipefail

ROOT=$(dirname "$0")
MIGRATIONS_FOLDER="$ROOT/migrations"
FIXTURES_FOLDER="$ROOT/fixtures"
export DATABASE_URL="${PG_DATABASE_URL:-postgres://north_tests@127.0.0.1/north_tests}"

log() {
    printf "[%s] [postgres] %s\\n" "$(date +%Y-%m-%dT%H:%M:%S)" "$@"
}

compare() {
    FIXTURE=$1
    shift
    shift

    log "Comparing '$*' to fixture $FIXTURE."
    OUTPUT=$("$@")
    if [ ! -f "$FIXTURES_FOLDER/$FIXTURE" ]; then
        echo "$OUTPUT" > "$FIXTURES_FOLDER/$FIXTURE"
    else
        if ! echo "$OUTPUT" | diff - "$FIXTURES_FOLDER/$FIXTURE"; then
            exit 1
        fi
    fi
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

compare 01-dry-run-migrate.out -- raco north migrate -p "$MIGRATIONS_FOLDER"
compare 02-force-run-migrate.out -- raco north migrate -fp "$MIGRATIONS_FOLDER"
compare 03-dry-run-rollback.out -- raco north rollback -p "$MIGRATIONS_FOLDER"
compare 04-dry-run-rollback.out -- raco north rollback -p "$MIGRATIONS_FOLDER" base
compare 05-force-run-rollback.out -- raco north rollback -fp "$MIGRATIONS_FOLDER"
compare 06-dry-run-rollback.out -- raco north rollback -p "$MIGRATIONS_FOLDER" base
compare 07-force-run-rollback.out -- raco north rollback -fp "$MIGRATIONS_FOLDER" base
