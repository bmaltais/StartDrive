#!/bin/bash
# Builds preview.png (1600x900), the marketplace's picture: the title, a tagline and the windows from screenshots/, on a gradient.
# Run scripts/screenshots.sh first so the windows are current. Needs ImageMagick (magick).
#
#   scripts/preview.sh [OUT]      (default: preview.png at the repo root; SHOTS=DIR reads the screenshots from elsewhere)
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
SHOTS=${SHOTS:-$HERE/screenshots}
OUT=${1:-$HERE/preview.png}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FONT=${PREVIEW_FONT:-JetBrainsMono-NF-Bold}
R=12   # the cards' corner radius, in pixels

# card <name> <scale %>: the card alone (the screenshot minus its 40 px margin), with rounded corners, saved as
# $TMP/<name>.png, and its blurred shadow as $TMP/<name>-shadow.png.
card() {
  local w h
  magick "$SHOTS/$1.png" -shave 40x40 +repage -resize "$2%" +repage "$TMP/$1-raw.png"
  w=$(magick identify -format %w "$TMP/$1-raw.png"); h=$(magick identify -format %h "$TMP/$1-raw.png")
  magick "$TMP/$1-raw.png" -alpha set \
    \( +clone -alpha transparent -fill white -draw "roundrectangle 0,0 $((w-1)),$((h-1)) $R,$R" \) \
    -compose DstIn -composite "$TMP/$1.png"
  magick "$TMP/$1.png" -background black -shadow 70x24+0+0 +repage "$TMP/$1-shadow.png"
}

ARGS=()
# place <name> <x> <y>: shadow (a little lower), then the card, on top of what is there.
place() {
  local w h sw sh
  w=$(magick identify -format %w "$TMP/$1.png"); h=$(magick identify -format %h "$TMP/$1.png")
  sw=$(magick identify -format %w "$TMP/$1-shadow.png"); sh=$(magick identify -format %h "$TMP/$1-shadow.png")
  ARGS+=( "$TMP/$1-shadow.png" -geometry "+$(( $2 - (sw - w) / 2 ))+$(( $3 - (sh - h) / 2 + 16 ))" -composite )
  ARGS+=( "$TMP/$1.png" -geometry "+$2+$3" -composite )
}

card manager 104
card settings-behaviour 68
card settings-cache 74
place manager 56 330
place settings-behaviour 1020 500
place settings-cache 900 100

magick -size 1600x900 xc:'#13151f' \
  \( -size 1500x1500 radial-gradient:'#5d3180-#5d318000' \) -geometry +700+-520 -compose over -composite \
  \( -size 1100x1100 radial-gradient:'#2f4a8a-#2f4a8a00' \) -geometry -300+400 -compose over -composite \
  -font "$FONT" \
  -fill none -stroke '#8a82b0' -strokewidth 2 -draw "roundrectangle 76,36 330,76 20,20" \
  -stroke none -fill '#d8d2f0' -pointsize 22 -annotate +98+64 "An Omarchy plugin" \
  -fill white -pointsize 100 -annotate +72+180 "StartDrive" \
  -fill '#bfa8ff' -pointsize 32 -annotate +78+236 "Your cloud drives as folders, for Omarchy" \
  "${ARGS[@]}" \
  "$OUT"
echo "Wrote $OUT"
