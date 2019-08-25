#!/usr/bin/env bash

set -euo pipefail

ROOT=$(dirname "$0")
MIGRATIONS_FOLDER="$ROOT/migrations"
FIXTURES_FOLDER="$ROOT/fixtures"
EXPECTED_OUTPUT="$FIXTURES_FOLDER/expected-output"
export DATABASE_URL="sqlite:$ROOT/db.sqlite"

log() {
    printf "[%s] [issue-003] %s\\n" "$(date +%Y-%m-%dT%H:%M:%S)" "$@"
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
rm -f "$ROOT/db.sqlite"
rm -fr "$MIGRATIONS_FOLDER"
mkdir -p "$MIGRATIONS_FOLDER"

log "Installing broken fixtures."
cp "$FIXTURES_FOLDER/"*.sql "$MIGRATIONS_FOLDER/"

log "Creating a new migration."
OUTFILE="$(mktemp)"
if raco north create -p "$MIGRATIONS_FOLDER" add-users-table >"$OUTFILE" 2>&1; then
    log "Command did not return non-zero exit code.  Output:"
    cat "$OUTFILE"
    exit 1
fi

log "Comparing output."
diff "$OUTFILE" "$EXPECTED_OUTPUT"
