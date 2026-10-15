# shellcheck shell=bash
# Helpers for the tests: a tiny assertion set, and a throwaway folder removed at the end.
KIT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fails=0
ok() { :; }
check() { # DESCRIPTION CONDITION-COMMAND...
  local what=$1; shift
  if "$@"; then ok; else echo "FAILED: $what"; fails=$((fails + 1)); fi
}
finish() { ((fails == 0)); }
