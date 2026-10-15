#!/bin/bash
# Records the tour at the top of the README. A shortcut for: scripts/tour.sh scripts/tours/hero.sh [--install]
exec "$(dirname "${BASH_SOURCE[0]}")/tour.sh" "$(dirname "${BASH_SOURCE[0]}")/tours/hero.sh" "$@"
