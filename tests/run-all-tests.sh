#!/usr/bin/env bash

set -euo pipefail

log () {
    printf "[%s] [run-all-tests.sh] %s\n" "$(date +%Y-%m-%dT%H:%M:%S)" "$@"
}

PASSED=0
FAILED=0

while read -r test; do
    log "Running test '$test'."
    if ! bash "$test"; then
        log "Test '$test' FAILED."
        FAILED=$((FAILED+1))
    else
        log "Test '$test' PASSED."
        PASSED=$((PASSED+1))
    fi
done < <(find . -type f -name "test.sh")

log "$PASSED PASSED, $FAILED FAILED"
if [ $FAILED -gt 0 ]; then
    exit 1
fi
