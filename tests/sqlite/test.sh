#!/usr/bin/env bash

set -euo pipefail

ROOT=$(dirname "$0")
MIGRATIONS_FOLDER="$ROOT/migrations"
FIXTURES_FOLDER="$ROOT/fixtures"
export DATABASE_URL="sqlite:$ROOT/db.sqlite"

log() {
    printf "[%s] [sqlite] %s\\n" "$(date +%Y-%m-%dT%H:%M:%S)" "$@"
}

log "Cleaning up."
rm -f "$ROOT/db.sqlite"
rm -fr "$MIGRATIONS_FOLDER"
mkdir -p "$MIGRATIONS_FOLDER"

log "Creating first migration."
raco north create -m "$MIGRATIONS_FOLDER" add-users-table

log "Remove created migration."
rm "$MIGRATIONS_FOLDER/"*

log "Copy fixture migrations."
cp "$FIXTURES_FOLDER/"*.sql "$MIGRATIONS_FOLDER/"

log "Dry run migrations."
raco north migrate -m "$MIGRATIONS_FOLDER" | \
    diff - "$FIXTURES_FOLDER/01-dry-run-migrate.out"

log "Force migrate."
raco north migrate -fm "$MIGRATIONS_FOLDER" | \
    diff - "$FIXTURES_FOLDER/02-force-run-migrate.out"

log "Dry run rollback."
raco north rollback -m "$MIGRATIONS_FOLDER" | \
    diff - "$FIXTURES_FOLDER/03-dry-run-rollback.out"

log "Dry run full rollback."
raco north rollback -m "$MIGRATIONS_FOLDER" base | \
    diff - "$FIXTURES_FOLDER/04-dry-run-rollback.out"

log "Force run rollback."
raco north rollback -fm "$MIGRATIONS_FOLDER" | \
    diff - "$FIXTURES_FOLDER/05-force-run-rollback.out"

log "Dry run full rollback."
raco north rollback -m "$MIGRATIONS_FOLDER" base | \
    diff - "$FIXTURES_FOLDER/06-dry-run-rollback.out"

log "Force run full rollback."
raco north rollback -fm "$MIGRATIONS_FOLDER" base | \
    diff - "$FIXTURES_FOLDER/07-force-run-rollback.out"
