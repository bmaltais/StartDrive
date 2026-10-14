#!/usr/bin/env bash
# Lint every shell script in the plugin with the shellcheck tool.
set -euo pipefail
cd "$(dirname "$0")/.."
shellcheck -x -s bash bin/startdrive lib/*.sh scripts/*.sh .githooks/pre-commit
