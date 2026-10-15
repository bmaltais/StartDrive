#!/bin/bash
# Retakes the README screenshots in the nested test session (scripts/dev), on a flat dark backdrop.
#
# Nothing touches your real desktop or your real drives: the session has its own screen and shell, and runs on the demo drives of
# lib/demo.sh (Google Drive uploading, OneDrive synced, Dropbox not connected, an SFTP remote not mounted). The view window shows
# what it is doing. Each card is captured with `dev shot` and cropped evenly around the centre of the screen, where the windows
# open. The sandbox's window sizes are reset first, so every window opens at its default.
# Needs: scripts/dev (see docs/testing.md), foot, magick (ImageMagick).
#
#   scripts/screenshots.sh
#
#   DEV_SIZE=WxH      the session's screen (default 1280x800); the crops are the same, so a bigger screen only adds backdrop
#   SHOTS_OUT=DIR     where the images go (default screenshots/)
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT=${SHOTS_OUT:-$HERE/screenshots}
DEV=$HERE/scripts/dev
STATE_DIR=${XDG_RUNTIME_DIR:-/run/user/$UID}/startdrive-dev
NEST_HOME=$STATE_DIR/nest/home
BG=2a2f3a
mkdir -p "$OUT"
TMP=$(mktemp -d)
cleanup() { kill "${BGWIN:-}" 2>/dev/null || true; "$DEV" down >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT

"$DEV" down >/dev/null 2>&1 || true
"$DEV" up
# shellcheck disable=SC1091
source "$STATE_DIR/state"
nest() { env STARTDRIVE_DEMO=1 HOME="$NEST_HOME" XDG_CONFIG_HOME="$NEST_HOME/.config" XDG_DATA_HOME="$NEST_HOME/.local/share" \
  XDG_STATE_HOME="$NEST_HOME/.local/state" XDG_CACHE_HOME="$NEST_HOME/.cache" \
  WAYLAND_DISPLAY="$NWD" HYPRLAND_INSTANCE_SIGNATURE="$NSIG" "$@"; }

# Default window sizes, so every card opens as a new user would see it.
nest "$HERE/bin/startdrive" window --reset --reset-setup >/dev/null

# The backdrop: a plain full-screen window inside the session, so no wallpaper, terminal text or cursor shows.
WAYLAND_DISPLAY=$NWD foot --fullscreen -o colors-dark.alpha=1 -o colors-dark.background=$BG \
  -o colors-dark.cursor="$BG $BG" -e sleep 900 >/dev/null 2>&1 &
BGWIN=$!
sleep 2

# shot <name> <out> <width> <height>: park the pointer in a corner of the backdrop, capture, then cut a box of that size centred on
# the screen (the card plus a 40 px margin of backdrop), which leaves the pointer out.
shot() {
  "$DEV" move 4 "$((NH - 4))" >/dev/null
  "$DEV" shot "$TMP/$1.png" >/dev/null
  local x=$(( (NW - $3) / 2 )) y=$(( (NH - $4) / 2 ))
  magick "$TMP/$1.png" -crop "$3x$4+$x+$y" +repage "$OUT/$2"
}

# The settings window opens on its first page; these are the page buttons of a window at its default size and place.
PAGE_X=316 BEHAVIOUR_Y=271 CACHE_Y=311 MAINTENANCE_Y=351

"$DEV" open;                           sleep 2; shot manager manager.png 720 540
"$DEV" close; "$DEV" setup;            sleep 2; shot window settings-window.png 840 600
"$DEV" close; "$DEV" settings onedrive; sleep 2
shot behaviour settings-behaviour.png 840 600
"$DEV" click "$PAGE_X" "$CACHE_Y" >/dev/null;       sleep 1; shot cache settings-cache.png 840 600
"$DEV" click "$PAGE_X" "$MAINTENANCE_Y" >/dev/null; sleep 1; shot maintenance settings-maintenance.png 840 600
"$DEV" close
echo "Updated $OUT/{manager,settings-window,settings-behaviour,settings-cache,settings-maintenance}.png"
