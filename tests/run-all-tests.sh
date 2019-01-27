#!/usr/bin/env bash

set -euo pipefail

find . -type f -name "test.sh" -exec bash \{\} \;
