#!/usr/bin/env bash

set -euo pipefail

ROOT=$(realpath "$(dirname "$0")")
MIGRATIONS_FOLDER="$ROOT/migrations"
FIXTURES_FOLDER="$ROOT/fixtures"
export DATABASE_URL="${DATABASE_URL:-postgres://north_tests@127.0.0.1/north_tests}"
export PG_DATABASE_URL="${PG_DATABASE_URL:-postgres://postgres@127.0.0.1/postgres}"

log() {
    printf "[%s] [postgres] %s\\n" "$(date +%Y-%m-%dT%H:%M:%S)" "$@"
}

scrubbed() {
    echo "$1" | sed -E "s|$ROOT||g"
}

compare() {
    FIXTURE=$1
    shift
    shift

    log "Comparing '$*' to fixture $FIXTURE."
    OUTPUT=$("$@")
    if [ ! -f "$FIXTURES_FOLDER/$FIXTURE" ]; then
        scrubbed "$OUTPUT" > "$FIXTURES_FOLDER/$FIXTURE"
    else
        if ! scrubbed "$OUTPUT" | diff - "$FIXTURES_FOLDER/$FIXTURE"; then
            exit 1
        fi
    fi
}

log "Cleaning up."
log "DATABASE_URL=$DATABASE_URL"
psql "$PG_DATABASE_URL" <<EOF
DROP DATABASE IF EXISTS north_tests;
DROP ROLE IF EXISTS north_tests;
CREATE ROLE north_tests WITH PASSWORD 'north_tests' LOGIN;
CREATE DATABASE north_tests;
GRANT ALL PRIVILEGES ON DATABASE north_tests TO north_tests;
EOF
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
