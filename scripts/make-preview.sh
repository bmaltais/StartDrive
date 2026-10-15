#!/usr/bin/env bash
# Compose preview.png, the marketplace's picture of StartDrive, from the shots
# in screenshots/: the panel and a drive's three detail tabs, on a dark
# gradient with the name and a badge. The look follows StartBar's preview.
#
#   scripts/make-preview.sh [OUT]      (default: preview.png at the repo root)
#
# Needs ImageMagick. Retake the shots first if the panel's look changed: the
# crops below drop each shot's 4 px edge, so a changed shot may need new numbers.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
shots=$repo/screenshots
out=${1:-$repo/preview.png}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
font=/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf
[[ -f $font ]] || font=DejaVu-Sans-Bold

# card IN OUT: drop the edges, scale to 85%, round the corners and add a shadow.
card() {
  local in=$1 dest=$2 w h
  magick "$in" -crop "$(($(magick identify -format %w "$in") - 10))x$(($(magick identify -format %h "$in") - 10))+4+4" +repage -resize 85% "$work/c.png"
  w=$(magick identify -format %w "$work/c.png"); h=$(magick identify -format %h "$work/c.png")
  magick "$work/c.png" -alpha set \
    \( -size "${w}x${h}" xc:none -fill white -draw "roundrectangle 0,0 $((w - 1)),$((h - 1)) 9,9" \) \
    -compose DstIn -composite "$work/r.png"
  magick "$work/r.png" \( +clone -background black -shadow 70x22+0+16 \) +swap -background none -layers merge +repage "$dest"
}

card "$shots/panel.png" "$work/panel.png"
card "$shots/details.png" "$work/details.png"
card "$shots/behaviour.png" "$work/behaviour.png"
card "$shots/maintenance.png" "$work/maintenance.png"

# The badge above the name: a pill sized to its text.
magick -background none -fill '#e8dcff' -font "$font" -pointsize 21 \
  label:"Compatible with Omarchy 4.5 windowed mode" -trim +repage "$work/badge-text.png"
bw=$(( $(magick identify -format %w "$work/badge-text.png") + 36 ))
bh=$(( $(magick identify -format %h "$work/badge-text.png") + 18 ))
magick -size "${bw}x${bh}" xc:none -fill 'rgba(255,255,255,0.13)' -draw "roundrectangle 0,0 $((bw - 1)),$((bh - 1)) $((bh / 2)),$((bh / 2))" \
  -stroke 'rgba(205,188,245,0.45)' -strokewidth 1 -fill none -draw "roundrectangle 0,0 $((bw - 1)),$((bh - 1)) $((bh / 2)),$((bh / 2))" \
  "$work/badge-text.png" -gravity center -compose over -composite "$work/badge.png"

magick -size 1600x900 radial-gradient:'#2a1650-#0a0816' \
  \( -size 1100x1100 radial-gradient:'rgba(226,72,128,0.55)-rgba(226,72,128,0)' \) -geometry +900-420 -compose plus -composite \
  \( -size 1000x1000 radial-gradient:'rgba(86,120,255,0.40)-rgba(86,120,255,0)' \) -geometry -380+420 -compose plus -composite \
  -compose over \
  -font "$font" -fill white -pointsize 84 -annotate +72+150 "StartDrive" \
  -fill '#cdbcf5' -pointsize 30 -annotate +76+205 "Your cloud drives as folders, for Omarchy" \
  "$work/badge.png" -geometry +76+30 -composite \
  "$work/panel.png" -geometry +30+340 -composite \
  "$work/details.png" -geometry +400+250 -composite \
  "$work/behaviour.png" -geometry +790+310 -composite \
  "$work/maintenance.png" -geometry +1170+110 -composite \
  "$out"

echo "make-preview: wrote $out ($(magick identify -format '%wx%h' "$out"))"
