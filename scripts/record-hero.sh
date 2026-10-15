#!/usr/bin/env bash
# Film screenshots/hero.gif, the tour at the top of the README, the way
# StartBar's is made: on a temporary virtual monitor (so your own screen and
# windows are never in the picture), one grim frame at a time, while the real
# pointer and keys drive the panel. ffmpeg then crops it and makes the GIF.
#
#   scripts/record-hero.sh [--install] [--out DIR]
#
#   --install   copy hero.gif over screenshots/ (default: leave it in --out)
#   --out DIR   where it goes (default: a new directory under $TMPDIR or /tmp)
#
# The tour only looks: it opens the panel with a click on the bar icon, expands
# Google Drive's details, walks the three tabs and the cursor with the keys, and
# closes. It never clicks a switch, picks a setting or touches a mount.
#
# While it runs it moves the real pointer, types arrow keys and the letter "d"
# into the panel, and focuses the virtual monitor; all of it is put back on exit.
# Needs ydotool and a writable /dev/uinput, grim, ffmpeg and a bar with the
# StartDrive icon on the right (ICON_FROM_RIGHT below is where it sits).
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
install=false
out=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --install) install=true; shift ;;
    --out) out=$2; shift 2 ;;
    -h | --help) sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "record-hero: unknown option $1" >&2; exit 2 ;;
  esac
done

for tool in jq grim hyprctl wtype ydotool ffmpeg; do
  command -v "$tool" >/dev/null || { echo "record-hero: $tool is not installed" >&2; exit 2; }
done
[[ -w /dev/uinput ]] || { echo "record-hero: /dev/uinput is not writable" >&2; exit 2; }

readonly ID=io.github.bmaltais.startdrive
readonly MON=STARTDRIVE-REC
readonly W=1280 H=800
# Where things sit on the virtual monitor, measured from its right edge and top.
readonly ICON_FROM_RIGHT=184 ICON_Y=13 # the bar icon
readonly COG_FROM_RIGHT=137 COG_Y=155  # the first drive's details button
# What the GIF shows: the right-hand part of the monitor, bar included.
readonly CROP_W=520 CROP_H=700

out=${out:-${TMPDIR:-/tmp}/startdrive-hero-$(date +%Y%m%d-%H%M%S)}
work=$out/work
mkdir -p "$work/frames"

export YDOTOOL_SOCKET="${XDG_RUNTIME_DIR:-/tmp}/.ydotool_socket"
if [[ ! -S $YDOTOOL_SOCKET ]]; then
  nohup ydotoold --socket-path="$YDOTOOL_SOCKET" --socket-own="$(id -u):$(id -g)" >/dev/null 2>&1 &
  sleep 1
fi

orig=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
rec_pid=""
cleanup() {
  if [[ -n $rec_pid ]]; then kill "$rec_pid" 2>/dev/null || true; fi
  omarchy-shell -q "$ID" close >/dev/null 2>&1 || true
  hyprctl dispatch "hl.dsp.focus({ monitor = \"$orig\" })" >/dev/null 2>&1 || true
  hyprctl output remove "$MON" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# To the right of every real monitor, so nothing is moved.
mx=$(hyprctl monitors -j | jq -r '[.[] | .x + .width] | max')
hyprctl output create headless "$MON" >/dev/null
hyprctl eval "hl.monitor({ output = \"$MON\", mode = \"${W}x${H}@60\", position = \"${mx}x0\", scale = 1 })" >/dev/null
sleep 1.5
hyprctl dispatch "hl.dsp.focus({ monitor = \"$MON\" })" >/dev/null

# at X Y: the pointer there, with a 1 px nudge so a hover fires. X and Y are on
# the virtual monitor.
at() {
  hyprctl dispatch "hl.dsp.cursor.move({ x = $((mx + $1)), y = $2 })" >/dev/null
  ydotool mousemove -x 1 -y 0
  ydotool mousemove -x -1 -y 0
}
click() { ydotool click 0xC0 >/dev/null; }

# glide X Y: move there in small steps, so the pointer is seen to travel.
gx=$((W / 2)) gy=400
glide() {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    at $((gx + ($1 - gx) * i / 8)) $((gy + ($2 - gy) * i / 8))
    sleep 0.03
  done
  gx=$1 gy=$2
}
key() { wtype -k "$1"; sleep "${2:-0.9}"; }

# Frames stamped with the time; each lasts until the next one.
(while :; do grim -c -t jpeg -q 92 -o "$MON" "$work/frames/$(date +%s%N).jpg"; done) &
rec_pid=$!

at $gx $gy
sleep 1.5

# 1. Open the panel from the bar.
glide $((W - ICON_FROM_RIGHT)) $ICON_Y; sleep 0.6
click
sleep 2.2

# 2. Look over the drives, then open Google Drive's details.
glide $((W - 330)) 285; sleep 0.9
glide $((W - 330)) 200; sleep 0.9
glide $((W - COG_FROM_RIGHT)) $COG_Y; sleep 0.6
click
sleep 1.8

# 3. The three tabs, with the keys: Down to the tab bar, then right and back.
key Down 0.9
key Right 1.6
key Right 1.6
key Right 1.6
key Left 1.0
key Left 1.4

# 4. Down onto the cache choices to show the cursor, then back up and close.
key Down 1.4
key Up 0.8
key Up 0.8
key Escape 1.5
glide $((W / 2)) 400
sleep 1.2

kill "$rec_pid" 2>/dev/null; wait "$rec_pid" 2>/dev/null || true
rec_pid=""

# One concat entry per frame, lasting until the next one.
prev=""; : >"$work/frames.txt"
for f in "$work"/frames/*.jpg; do
  [[ -s $f ]] || continue
  t=$(basename "$f" .jpg)
  [[ -n $prev ]] && printf "duration %s\n" "$(awk -v a="$prev_t" -v b="$t" 'BEGIN { printf "%.3f", (b - a) / 1e9 }')" >>"$work/frames.txt"
  printf "file '%s'\n" "$f" >>"$work/frames.txt"
  prev=$f; prev_t=$t
done
printf "file '%s'\n" "$prev" >>"$work/frames.txt"
ffmpeg -loglevel error -y -f concat -safe 0 -i "$work/frames.txt" -fps_mode vfr -c:v libx264 -pix_fmt yuv420p -crf 14 "$work/tour.mp4"
echo "record-hero: filmed $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$work/tour.mp4") s"

# Cropped to the panel and the bar above it, 10 fps, 128 colours.
ffmpeg -loglevel error -y -ss 0.5 -i "$work/tour.mp4" \
  -vf "crop=$CROP_W:$CROP_H:$((W - CROP_W)):0,fps=10,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -loop 0 "$out/hero.gif"
echo "record-hero: $out/hero.gif ($(du -h "$out/hero.gif" | cut -f1))"

if $install; then
  cp "$out/hero.gif" "$repo/screenshots/hero.gif"
  echo "record-hero: installed into screenshots/"
fi
