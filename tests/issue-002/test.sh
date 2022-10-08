#!/usr/bin/env bash

set -euo pipefail

ROOT=$(realpath "$(dirname "$0")")
MIGRATIONS_FOLDER="$ROOT/migrations"
FIXTURES_FOLDER="$ROOT/fixtures"
export DATABASE_URL="${DATABASE_URL:-postgres://north_tests@127.0.0.1/north_tests}"
export PG_DATABASE_URL="${PG_DATABASE_URL:-postgres://postgres@127.0.0.1/postgres}"

log() {
    printf "[%s] [issue-002] %s\\n" "$(date +%Y-%m-%dT%H:%M:%S)" "$@"
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
log "DATABASE_URL=$DATABASE_URL"
log "PG_DATABASE_URL=$PG_DATABASE_URL"
psql "$PG_DATABASE_URL" <<EOF
DROP DATABASE IF EXISTS north_tests;
DROP ROLE IF EXISTS north_tests;
CREATE ROLE north_tests WITH PASSWORD 'north_tests' LOGIN;
CREATE DATABASE north_tests;
GRANT ALL PRIVILEGES ON DATABASE north_tests TO north_tests;
EOF
rm -fr "$MIGRATIONS_FOLDER"
mkdir -p "$MIGRATIONS_FOLDER"

log "Installing broken fixture."
cp "$FIXTURES_FOLDER/20200820-broken.sql" "$MIGRATIONS_FOLDER/"

OUTFILE="$(mktemp)"
if raco north migrate -f -p "$MIGRATIONS_FOLDER" >"$OUTFILE" 2>&1; then
    log "Command did not return non-zero exit code.  Output:"
    cat "$OUTFILE"
    exit 1
else
    log "Comparing output."
    psql --no-psqlrc -t "$DATABASE_URL" >"$OUTFILE" 2>&1 <<EOF
SELECT relname FROM pg_stat_user_tables ORDER BY relname
EOF
    diff "$OUTFILE" "$ROOT/fixtures/broken.out"
fi

log "Installing valid fixture."
rm -fr "$MIGRATIONS_FOLDER"
mkdir -p "$MIGRATIONS_FOLDER"
cp "$FIXTURES_FOLDER/20200820-valid.sql" "$MIGRATIONS_FOLDER/"

OUTFILE="$(mktemp)"
if ! raco north migrate -f -p "$MIGRATIONS_FOLDER" >"$OUTFILE" 2>&1; then
    log "Command failed.  Output:"
    cat "$OUTFILE"
    exit 1
else
    log "Comparing output."
    psql --no-psqlrc -t "$DATABASE_URL" >"$OUTFILE" 2>&1 <<EOF
SELECT relname FROM pg_stat_user_tables ORDER BY relname
EOF
    diff "$OUTFILE" "$ROOT/fixtures/valid.out"
fi
