# shellcheck shell=bash
# The nested session for the tour recorder (scripts/tour.sh), sourced by it.
#
# Instead of filming a hidden virtual monitor and driving your real mouse and keyboard, the tour runs inside a
# second Hyprland that opens as a window on your screen. In it runs a second Omarchy shell with only the app's
# plugin, in a sandbox home that holds copies of the app's data. So:
#   - you can watch it, in a window;
#   - your mouse and keyboard cannot reach it (the nested session switches off the two devices your seat gives it);
#   - the tour is driven over that session's own Wayland socket (a virtual pointer and virtual keyboard), so
#     nothing the tour does moves your pointer or types into your windows;
#   - the tour changes only the sandbox: your real settings, apps and files are not touched, so there is nothing
#     to put back.
# Needs: Hyprland, dbus-run-session, wtype, gcc and wayland-scanner (to build the pointer client, once per run).
# docs/recording-tours.md "Nested mode" says how it works.

NEST=$TMP/nest
NEST_HOME=$NEST/home
NEST_BIN=$NEST/bin
NEST_RT=${XDG_RUNTIME_DIR:-/run/user/$UID}
REAL_SIG=${HYPRLAND_INSTANCE_SIGNATURE:-}
REAL_WD=${WAYLAND_DISPLAY:-}
nest_pid=""
NSIG=""
NWD=""
NMON=""
NW=0
NH=0
VPTR=$NEST_BIN/vptr
# The status strip (scripts/tour-banner.qml) sits NEST_STRIP_GAP pixels from the top of your monitor and is NEST_STRIP_H high; the
# view window (nested_view_open) is centred below it.
NEST_STRIP_GAP=24
NEST_STRIP_H=170

real() { env HYPRLAND_INSTANCE_SIGNATURE="$REAL_SIG" WAYLAND_DISPLAY="$REAL_WD" "$@"; }

nested_requires() {
  local tool
  for tool in Hyprland dbus-run-session wtype gcc wayland-scanner pkg-config; do
    command -v "$tool" >/dev/null || { echo "tour: the recorder needs $tool" >&2; return 1; }
  done
  [[ -n $REAL_SIG && -n $REAL_WD ]] || { echo "tour: the recorder must run inside your Hyprland session" >&2; return 1; }
  [[ -n ${TOUR_PLUGIN_ID:-} ]] || { echo "tour: the tour file needs TOUR_PLUGIN_ID in the tour file (the plugin to load in the sandbox)" >&2; return 1; }
}

# A home of its own for the nested session: the Omarchy themes it needs, a minimal shell config that loads only
# the app's plugin (linked to this checkout, so the tour shows the code you are working on), and copies of the
# data the tour file lists. Nothing here points back at your real files except read-only links.
sandbox_build() {
  local h=$NEST_HOME rel
  mkdir -p "$h/.config/omarchy/plugins" "$h/.local/share" "$h/.local/state/omarchy" "$h/.cache" "$NEST_BIN"
  for rel in branding defaults extensions hooks themed themes; do
    [[ -e $HOME/.config/omarchy/$rel ]] && cp -a "$HOME/.config/omarchy/$rel" "$h/.config/omarchy/"
  done
  [[ -e $HOME/.local/state/omarchy/current ]] && ln -s "$HOME/.local/state/omarchy/current" "$h/.local/state/omarchy/current"
  ln -s "$REPO" "$h/.config/omarchy/plugins/$TOUR_PLUGIN_ID"
  # The bar is your real one, so it looks like your desktop: its settings, and the layout kept to Omarchy's own widgets
  # (other plugins are left out: they would start their own services) plus this app.
  local real_cfg=$HOME/.config/omarchy/shell.json
  [[ -s $real_cfg ]] || real_cfg=${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json
  jq --arg id "$TOUR_PLUGIN_ID" '
      def own: map(select((if type == "object" then .id else . end) as $i | ($i | tostring | startswith("omarchy.")) or $i == $id));
      {version: 1, bar: ((.bar // {}) | .layout |= (. // {} | with_entries(.value |= (if type == "array" then own else . end)))),
       plugins: [{id: $id}]}
      | if ([.bar.layout[]?[]? | (if type == "object" then .id else . end)] | index($id)) == null
        then .bar.layout.right += [{id: $id}] else . end' "$real_cfg" >"$h/.config/omarchy/shell.json" ||
    jq -n --arg id "$TOUR_PLUGIN_ID" '{version: 1, bar: {layout: {left: [{id: "omarchy.menu"}], center: [{id: "omarchy.clock"}], right: [{id: $id}]}}, plugins: [{id: $id}]}' >"$h/.config/omarchy/shell.json"
  # A test session says what it is on its own bar: the nested desktop looks exactly like yours, and its window title is fixed
  # by the nested compositor ("aquamarine - WAYLAND-N"), so this is the only way to tell them apart.
  if [[ -n ${NEST_LABEL:-} ]]; then
    jq --arg label "$NEST_LABEL" '.bar.layout.left = [{id: "sandbox-label", type: "command", exec: ("echo " + ($label | @sh)), interval: 3600}] + (.bar.layout.left // [])' \
      "$h/.config/omarchy/shell.json" >"$h/shell.json.new" && mv "$h/shell.json.new" "$h/.config/omarchy/shell.json"
  fi
  for rel in "${TOUR_SANDBOX_COPY[@]:-}"; do
    [[ -n $rel && -e $HOME/$rel ]] || continue
    mkdir -p "$h/$(dirname "$rel")"
    cp -a "$HOME/$rel" "$h/$rel"
  done
  for rel in "${TOUR_SANDBOX_LINK[@]:-}"; do
    [[ -n $rel && -e $HOME/$rel ]] || continue
    mkdir -p "$h/$(dirname "$rel")"
    ln -s "$HOME/$rel" "$h/$rel"
  done
  sandbox_repoint "$h" || return 1
  if declare -F tour_sandbox >/dev/null; then tour_sandbox "$h"; fi
  "$HERE/nested/build.sh" "$NEST_BIN" >/dev/null || { echo "tour: could not build the virtual pointer client" >&2; return 1; }
}

# The session must never reach your real drives: its shell shares your user's systemd, keyring and rclone config, so a click on a
# mount switch would mount (or a "forget" would remove) a real account. So the sandbox is put in demo mode: a marker file in its own
# config folder makes bin/startdrive serve fixture drives and run no systemd, rclone, keyring or file-manager command at all
# (lib/demo.sh). Nothing of the real config is copied in, and the session refuses to start unless the marker is there.
sandbox_repoint() {
  local h=$1
  mkdir -p "$h/.config/startdrive/demo"
  : >"$h/.config/startdrive/demo/ENABLED"
  [[ -f $h/.config/startdrive/demo/ENABLED ]] || { echo "nested: could not switch the sandbox to demo mode" >&2; return 1; }
  # The first-run offer has been answered, so no window opens by itself over what is being filmed or tested.
  printf 'SETUP_DONE=1\n' >"$h/.config/startdrive/config"
  # A real drive's settings or state in the sandbox would mean something was copied that should not have been.
  if compgen -G "$h/.config/startdrive/*.env" >/dev/null; then
    echo "nested: the sandbox holds a real drive's settings; list nothing of .config/startdrive in TOUR_SANDBOX_COPY" >&2
    return 1
  fi
}

# From here on every command the tour runs, and the recorder's own helpers, act in the sandbox.
sandbox_enter() {
  export STARTDRIVE_DEMO=1 HOME=$NEST_HOME XDG_CONFIG_HOME=$NEST_HOME/.config XDG_DATA_HOME=$NEST_HOME/.local/share \
    XDG_STATE_HOME=$NEST_HOME/.local/state XDG_CACHE_HOME=$NEST_HOME/.cache
}

nested_start() {
  local before_wins sig sock i addr started
  # The session is found by being created after this point, not by having a name that was absent before: its socket is called
  # wayland-N and the number is reused, so a stale file of an earlier session would hide it.
  started=$(( $(date +%s) - 1 ))
  before_wins=$(real hyprctl clients -j | jq -r '.[].address')
  cat >"$NEST/hypr.lua" <<'LUA'
-- A bare nested session for the tour recorder. None of Omarchy's own autostart: it would push this session's
-- environment into your real one.
hl.config({
  general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true, force_default_wallpaper = 0, disable_watchdog_warning = true },
  animations = { enabled = false },
})
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
-- The host's mouse and keyboard reach this session as two devices of its Wayland backend. Switched off here, so nothing the
-- person at the real desktop does can move, click or type into it, even though it is an ordinary window they can cover, move
-- or send to the scratchpad. The recorder's and scripts/dev's own input arrives as separate virtual devices and is unaffected.
-- (NEST_HOST_INPUT=1 leaves them on, for debugging the session by hand.)
if os.getenv("NEST_HOST_INPUT") ~= "1" then
  hl.device({ name = "wl_pointer", enabled = false })
  hl.device({ name = "wl_keyboard", enabled = false })
end
hl.on("hyprland.start", function()
  hl.exec_cmd("QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 quickshell -n -p " .. (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/shell >> " .. (os.getenv("NEST_QS_LOG") or "/dev/null") .. " 2>&1")
end)
LUA
  # Its own D-Bus, and one that starts nothing by itself: the usual one launches portals, file services and
  # accessibility daemons that this session does not need, and a portal that has no real display crashes.
  mkdir -p "$NEST/dbus-services"
  cat >"$NEST/dbus.conf" <<CONF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
  <servicedir>$NEST/dbus-services</servicedir>
</busconfig>
CONF
  : >"$NEST/qs.log"
  if [[ -n ${NEST_DETACH:-} ]]; then
    # A session that outlives this script (scripts/dev): its own process group, found again by its environment, not a pid.
    setsid -f env -u HYPRLAND_INSTANCE_SIGNATURE -u HYPRLAND_CMD NEST_QS_LOG="$NEST/qs.log" \
      dbus-run-session --config-file="$NEST/dbus.conf" -- Hyprland -c "$NEST/hypr.lua" >"$NEST/hypr.log" 2>&1
    nest_pid=detached
  else
    env -u HYPRLAND_INSTANCE_SIGNATURE -u HYPRLAND_CMD NEST_QS_LOG="$NEST/qs.log" \
      dbus-run-session --config-file="$NEST/dbus.conf" -- Hyprland -c "$NEST/hypr.lua" >"$NEST/hypr.log" 2>&1 &
    nest_pid=$!
  fi
  for i in $(seq 1 60); do
    sig=$(find "$NEST_RT/hypr" -mindepth 1 -maxdepth 1 -type d -newermt "@$started" -printf '%f\n' 2>/dev/null | head -n1)
    sock=$(find "$NEST_RT" -maxdepth 1 -name 'wayland-[0-9]*' ! -name '*.lock' -newermt "@$started" -printf '%f\n' 2>/dev/null | head -n1)
    [[ -n $sig && -n $sock ]] && break
    sleep 0.5
  done
  [[ -n $sig && -n $sock ]] || { echo "tour: the nested session did not start (see $NEST/hypr.log)" >&2; return 1; }
  NSIG=$sig
  NWD=$sock
  # Its window on the real screen: found by being new, then sized, placed and left unfocused.
  for i in $(seq 1 30); do
    addr=$(comm -13 <(echo "$before_wins" | sort) <(real hyprctl clients -j | jq -r '.[].address' | sort) | head -n1)
    [[ -n $addr ]] && break
    sleep 0.3
  done
  [[ -n $addr ]] || { echo "tour: the nested session's window did not appear" >&2; return 1; }
  NEST_ADDR=$addr
}

# ---- keeping the session's window out of reach, and watching it through a view window -----------------------
# The nested compositor's window must never sit under a real pointer: while the pointer is over it, the nested compositor chooses the
# cursor image (hidden, a hand, ...). So the window lives on a virtual monitor 20,000 px to the right, which a real pointer cannot
# reach, and what you watch is a separate view-only window showing screenshots of it.
FAR_MON=${FAR_MON:-DEVTEST}
FAR_X=${FAR_X:-20000}

nested_far_up() {
  real hyprctl output create headless "$FAR_MON" >/dev/null
  real hyprctl eval "hl.monitor({ output = \"$FAR_MON\", mode = \"${W}x${H}@60\", position = \"${FAR_X}x0\", scale = 1 })" >/dev/null
  sleep 0.8
}
nested_far_down() { real hyprctl output remove "$FAR_MON" >/dev/null 2>&1 || true; }

# The window goes to the far monitor at the session's own size, and the real keyboard goes back to what had it.
nested_send_away() { # [PREVIOUS_FOCUS_ADDRESS]
  real hyprctl dispatch "hl.dsp.window.resize({ x = $W, y = $H, exact = true, window = \"address:$NEST_ADDR\" })" >/dev/null
  real hyprctl dispatch "hl.dsp.window.move({ monitor = \"$FAR_MON\", window = \"address:$NEST_ADDR\" })" >/dev/null
  real hyprctl dispatch "hl.dsp.window.move({ x = $FAR_X, y = 0, exact = true, window = \"address:$NEST_ADDR\" })" >/dev/null
  # The taskbar lists this window, and a click there asks the compositor to focus it, which moves the pointer onto a monitor nobody can
  # reach: the pointer disappears. A window that refuses focus cannot be clicked to there.
  real hyprctl dispatch "hl.dsp.window.set_prop({ prop = \"no_focus\", value = \"1\", window = \"address:$NEST_ADDR\" })" >/dev/null
  real hyprctl dispatch "hl.dsp.window.set_prop({ prop = \"no_follow_mouse\", value = \"1\", window = \"address:$NEST_ADDR\" })" >/dev/null
  [[ -n ${1:-} ]] && real hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" >/dev/null
  return 0
}

# Processes that carry a given variable=value in their environment.
procs_with() { local p; for p in /proc/[0-9]*; do p=${p#/proc/}; [[ $p != "$$" && -r /proc/$p/environ ]] || continue
  tr '\0' '\n' </proc/"$p"/environ 2>/dev/null | grep -qx "$1" && echo "$p"; done 2>/dev/null || true; }

# A view-only window on your screen showing the session five times a second (scripts/dev-view.qml). Drag it, cover it, resize it: your
# pointer is the normal arrow over it and nothing in it listens. The picture loop runs while the file LIVE_FILE is not empty.
nested_view_open() { # LIVE_FILE
  local live=$1 frame=$NEST/frame.jpg addr="" i ws mx my mw mh
  [[ -z $(procs_with "NEST_VIEW=1") ]] || return 0
  WAYLAND_DISPLAY=$NWD grim -t jpeg -q 75 "$frame" || { echo "tour: grim could not capture the session" >&2; return 1; }
  # Written to a temporary name and renamed so the window never reads half a file.
  setsid -f env NEST_VIEW=1 bash -c 'while [[ -s $2 ]]; do WAYLAND_DISPLAY=$1 grim -t jpeg -q 75 "$3.new" 2>/dev/null && mv -f "$3.new" "$3"; sleep 0.2; done' _ "$NWD" "$live" "$frame" >/dev/null 2>&1 </dev/null
  setsid -f env NEST_VIEW=1 QS_APP_ID=startdrive-test-viewer DEV_FRAME="$frame" HOME="$REAL_HOME" XDG_CONFIG_HOME="$REAL_HOME/.config" XDG_DATA_HOME="$REAL_HOME/.local/share" XDG_STATE_HOME="$REAL_HOME/.local/state" XDG_CACHE_HOME="$REAL_HOME/.cache" \
    WAYLAND_DISPLAY="$REAL_WD" HYPRLAND_INSTANCE_SIGNATURE="$REAL_SIG" quickshell -n -p "$HERE/dev-view.qml" >/dev/null 2>&1
  for i in $(seq 1 20); do
    addr=$(real hyprctl clients -j | jq -r '[.[] | select(.title | test("view only"))][0].address // empty')
    [[ -n $addr ]] && break
    sleep 0.25
  done
  [[ -n $addr ]] || { echo "tour: the view window did not open" >&2; return 1; }
  # It opens on the focused monitor, which may be the far one: put it on yours, centred.
  read -r ws mx my mw mh < <(real hyprctl monitors -j | jq -r --arg far "$FAR_MON" '[.[] | select(.name != $far)] | (map(select(.focused))[0] // .[0]) | "\(.activeWorkspace.id) \(.x) \(.y) \(.width) \(.height)"')
  real hyprctl dispatch "hl.dsp.window.move({ workspace = \"$ws\", follow = false, window = \"address:$addr\" })" >/dev/null
  real hyprctl dispatch "hl.dsp.window.resize({ x = 960, y = 600, exact = true, window = \"address:$addr\" })" >/dev/null
  real hyprctl dispatch "hl.dsp.window.move({ x = $((mx + (mw - 960) / 2)), y = $((my + (mh - 600) / 2)), exact = true, window = \"address:$addr\" })" >/dev/null
  real hyprctl dispatch "hl.dsp.window.alter_zorder({ mode = \"top\", window = \"address:$addr\" })" >/dev/null
}
nested_view_close() { local p; for p in $(procs_with "NEST_VIEW=1"); do kill "$p" 2>/dev/null || true; done; }

nested_wait_ready() {
  local i
  for i in $(seq 1 60); do
    if env WAYLAND_DISPLAY="$NWD" HYPRLAND_INSTANCE_SIGNATURE="$NSIG" omarchy-shell shell ping >/dev/null 2>&1; then break; fi
    sleep 0.5
  done
  NMON=$(env HYPRLAND_INSTANCE_SIGNATURE=$NSIG hyprctl monitors -j | jq -r '.[0].name')
  read -r NW NH < <(env HYPRLAND_INSTANCE_SIGNATURE=$NSIG hyprctl monitors -j | jq -r '.[0] | "\(.width) \(.height)"')
  echo "tour: nested session $NSIG on $NWD, $NMON ${NW}x${NH}" >&2
}

# From here on `hyprctl`, `omarchy-shell` and friends act on the nested session.
nested_enter() { export WAYLAND_DISPLAY=$NWD HYPRLAND_INSTANCE_SIGNATURE=$NSIG; }

# Calls "$1 PID COMMAND" for each process that carries the sandbox's XDG_CONFIG_HOME: everything the nested session
# started (its compositor, shell, its own D-Bus, portals, file watchers). Mine alone: the check is the sandbox's path.
nested_procs() {
  local p comm
  for p in /proc/[0-9]*; do
    p=${p#/proc/}
    [[ $p != "$$" && -r /proc/$p/environ ]] || continue
    if tr '\0' '\n' </proc/"$p"/environ 2>/dev/null | grep -qx "XDG_CONFIG_HOME=$NEST_HOME/.config"; then
      comm=$(cat /proc/"$p"/comm 2>/dev/null)
      "$1" "$p" "$comm"
    fi
  done 2>/dev/null
}
_nested_term() { [[ $2 == Hyprland ]] || kill -TERM "$1" 2>/dev/null; }
_nested_kill() { kill -KILL "$1" 2>/dev/null; }

nested_stop() {
  [[ -n $nest_pid ]] || return 0
  # What runs inside goes first, then the compositor: a portal that loses its compositor crashes, and Omarchy tells you.
  nested_procs _nested_term || true
  sleep 1.5
  env HYPRLAND_INSTANCE_SIGNATURE="$NSIG" hyprctl dispatch "hl.dsp.exit()" >/dev/null 2>&1 || true
  sleep 1.5
  [[ $nest_pid == detached ]] || kill "$nest_pid" 2>/dev/null || true
  nest_pid=""
  nested_procs _nested_kill || true
  # What a compositor that was killed rather than quit leaves behind: its instance folder and Wayland socket.
  [[ -n $NSIG ]] && rm -rf "${NEST_RT:?}/hypr/$NSIG"
  [[ -n $NWD ]] && rm -f "${NEST_RT:?}/$NWD" "${NEST_RT:?}/$NWD.lock"
}

# ---- input: over the nested session's own socket --------------------------------------------------------
nest_at() { WAYLAND_DISPLAY=$NWD "$VPTR" move "$1" "$2" "$NW" "$NH"; }
nest_click() { WAYLAND_DISPLAY=$NWD "$VPTR" click "$1" "$2" "$NW" "$NH"; }
nest_move() { WAYLAND_DISPLAY=$NWD "$VPTR" move "$1" "$2" "$NW" "$NH"; }
nest_drag() { WAYLAND_DISPLAY=$NWD "$VPTR" drag "$gx" "$gy" "$NW" "$NH" "$1" "$2"; gx=$((gx + $1)); gy=$((gy + $2)); }
nest_type() { WAYLAND_DISPLAY=$NWD wtype -d 45 -- "$1"; }
nest_key() { WAYLAND_DISPLAY=$NWD wtype -k "$1"; }
