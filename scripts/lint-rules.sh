#!/usr/bin/env bash
# Project rules that no linter knows, each one a mistake that cost a session. Run by scripts/check.sh.
#
#   scripts/lint-rules.sh              (LINT_RULES_ROOT=DIR checks another tree, for the tests)
#
# detached  The devkit's rules (scripts/devkit/bin/lint): a background launch (`setsid -f`) must redirect its own output (`2>&1` on the
#           launch), or `scripts/dev up | tail` waits until the background process ends (up to 30 minutes); and a tour must not copy or
#           link the real shell.json.
# tours     A tour's TOUR_REAL_UNCHANGED (and devkit.conf's) must not name a cloud mount (`Cloud`). The recorder fingerprints its paths by
#           walking them, and walking a live drive is slow and spends its API quota. This one is StartDrive's own.
set -uo pipefail
root=${LINT_RULES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
kit=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/devkit/bin/lint
cd "$root" || exit 1
fail=0

detached() {
  local out
  out=$("$kit" "$root" 2>&1) || { printf '%s\n' "$out"; return 1; }
}

tours() {
  local hits
  hits=$(grep -nE '^TOUR_REAL_UNCHANGED=.*(^|[ (/])Cloud([ )/]|$)' scripts/tours/*.sh devkit.conf 2>/dev/null || true)
  [[ -z $hits ]] || { echo "TOUR_REAL_UNCHANGED names a cloud mount (it is walked, which is slow and spends the drive's quota):"; printf '    %s\n' "${hits//$'\n'/$'\n    '}"; return 1; }
}

for rule in detached tours; do
  out=$($rule 2>&1) || { printf '%s\n' "$out"; fail=1; }
done
((fail == 0)) && echo "lint-rules: ok"
exit $fail
