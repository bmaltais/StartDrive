#!/usr/bin/env bash
# pointer.sh: click what you can see in a screenshot. Drives the real pointer (ydotool + hyprctl), for trying the live shell.
#
#   scripts/pointer.sh click PX PY [right]   click at pixel PX,PY of the FOCUSED monitor, as in a `grim -o` screenshot of it
#   scripts/pointer.sh move PX PY            put the pointer there (a hover fires), no click
#   scripts/pointer.sh pos                   where the pointer is, in the same pixels
#
# PX,PY are the pixels you read off a screenshot of the focused monitor; this works out the monitor's place in the layout
# (a second monitor does not start at 0,0) and its scale, so no coordinate is ever halved or offset by hand.
# A click goes to whatever is under the pointer: look at a screenshot first, because a click outside a window
# can close it. Needs ydotool and a writable /dev/uinput.
set -euo pipefail

export YDOTOOL_SOCKET="${XDG_RUNTIME_DIR:-/tmp}/.ydotool_socket"
if [[ ! -S $YDOTOOL_SOCKET ]]; then
  nohup ydotoold --socket-path="$YDOTOOL_SOCKET" --socket-own="$(id -u):$(id -g)" >/dev/null 2>&1 &
  sleep 1
fi

read -r mx my scale < <(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.x) \(.y) \(.scale)"')
to_global() { awk -v m="$1" -v p="$2" -v s="$scale" 'BEGIN { printf "%d", m + p / s }'; }
to_pixel() { awk -v g="$1" -v m="$2" -v s="$scale" 'BEGIN { printf "%d", (g - m) * s }'; }
warp() { # PX PY: move there with real motion, so a hover fires
  hyprctl dispatch "hl.dsp.cursor.move({ x = $(to_global "$mx" "$1"), y = $(to_global "$my" "$2") })" >/dev/null
  ydotool mousemove -x 1 -y 0
  ydotool mousemove -x -1 -y 0
}

case ${1:-} in
  click)
    [[ $# -ge 3 ]] || { echo "usage: pointer.sh click PX PY [right]" >&2; exit 2; }
    warp "$2" "$3"
    sleep 0.4
    if [[ ${4:-} == right ]]; then ydotool click 0xC1 >/dev/null; else ydotool click 0xC0 >/dev/null; fi
    echo "clicked $2,$3 on $(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')"
    ;;
  move)
    [[ $# -ge 3 ]] || { echo "usage: pointer.sh move PX PY" >&2; exit 2; }
    warp "$2" "$3"
    ;;
  pos)
    read -r gx gy < <(hyprctl cursorpos -j | jq -r '"\(.x) \(.y)"')
    echo "$(to_pixel "$gx" "$mx"),$(to_pixel "$gy" "$my")"
    ;;
  *) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//' >&2; exit 2 ;;
esac
