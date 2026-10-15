#!/usr/bin/env bash
# Every check that needs no running shell: shell scripts, QML warnings, the plugin manifest, and the project's own rules.
# The pre-commit hook runs this; run it by hand any time.
#
#   scripts/check.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
fail=0
step() { # NAME COMMAND...
  local name=$1; shift
  if out=$("$@" 2>&1); then
    printf '  ok    %s\n' "$name"
  else
    printf '  FAIL  %s\n' "$name"
    printf '        %s\n' "${out//$'\n'/$'\n        '}"
    fail=1
  fi
}

# Icons in QML are private-use glyphs, and writing a file through a tool that drops them leaves an empty string where the
# icon was (it happened twice). An empty icon is never intended, so an empty `iconText` fails.
icons() {
  local hits
  hits=$(grep -nE 'iconText: *""' ./*.qml || true)
  [[ -z $hits ]] || { echo "empty iconText (an icon lost its glyph; write icons as \\uXXXX escapes):"; echo "$hits"; return 1; }
}

step "shell scripts (bash -n, shellcheck)" scripts/lint-sh.sh
step "project rules (detached launches, tour paths)" scripts/lint-rules.sh
step "CLI behaviour (tests/cli.sh)" tests/cli.sh
step "model, CLI input checks, marketplace rules (node --test)" node --test
step "QML (qmllint, new warnings only)" scripts/lint-qml.py
if command -v omarchy >/dev/null; then step "plugin manifest (omarchy plugin validate)" omarchy plugin validate .
else echo "  skip  plugin manifest (omarchy is not installed here)"; fi
step "QML icons (no empty iconText)" icons
exit $fail
