#!/usr/bin/env bash
# The devkit's `tour`, run for this checkout (scripts/devkit; docs/testing.md).
export DEVKIT_APP_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
exec "$DEVKIT_APP_ROOT/scripts/devkit/bin/tour" "$@"
