#!/bin/bash
# Records the README's clips of single windows (scripts/tours/*-clip.sh) and installs them in screenshots/.
# Each one is its own session, so this takes a few minutes. See docs/recording-tours.md ("What is StartDrive's").
#
#   scripts/clips.sh [CLIP...]     CLIP is manager, settings or app-settings (default: all three)
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
clips=("$@")
((${#clips[@]})) || clips=(manager settings app-settings)
for c in "${clips[@]}"; do
  [[ -f $HERE/tours/$c-clip.sh ]] || { echo "clips: no clip called $c" >&2; exit 2; }
  "$HERE/tour.sh" "$HERE/tours/$c-clip.sh" --install
done
