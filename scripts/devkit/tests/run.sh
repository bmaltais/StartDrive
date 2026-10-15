#!/usr/bin/env bash
# Runs every tests/*.test.sh and says which failed. No Hyprland is needed: these test the guard, the config and the lint rules.
#
#   tests/run.sh [NAME...]     NAME selects tests whose file name contains it
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
fail=0; n=0
for t in *.test.sh; do
  [[ $# -eq 0 ]] || { m=0; for w in "$@"; do [[ $t == *"$w"* ]] && m=1; done; ((m)) || continue; }
  n=$((n + 1))
  if out=$(bash "$t" 2>&1); then echo "  ok    $t"; else echo "  FAIL  $t"; printf '        %s\n' "${out//$'\n'/$'\n        '}"; fail=1; fi
done
echo "tests: $n files, $([[ $fail -eq 0 ]] && echo all passed || echo FAILED)"
exit $fail
