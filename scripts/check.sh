#!/usr/bin/env bash
# The devkit's `check`, run for this checkout (scripts/devkit, a submodule; docs/testing.md).
export DEVKIT_APP_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
kit=$DEVKIT_APP_ROOT/scripts/devkit/bin/check
[[ -x $kit ]] || { echo "scripts/devkit is empty: git submodule update --init scripts/devkit" >&2; exit 1; }
exec "$kit" "$@"
