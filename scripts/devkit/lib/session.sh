# shellcheck shell=bash
# The nested session, sourced by bin/dev (the test session) and bin/tour (the recorder).
#
# The plugin runs inside a second Hyprland that opens as a window of your compositor. In it runs a second Omarchy shell with only
# the app's plugin, in a sandbox home of its own. So:
#   - you can watch it, in a window;
#   - your mouse and keyboard cannot reach it (the nested session switches off the two devices your seat gives it);
#   - the tour is driven over that session's own Wayland socket (a virtual pointer and virtual keyboard), so
#     nothing the tour does moves your pointer or types into your windows;
#   - the tour changes only the sandbox: your real settings, apps and files are not touched, so there is nothing
#     to put back.
# Needs: Hyprland, dbus-run-session, wtype, gcc and wayland-scanner (to build the pointer client, once per run).
# docs/how-it-works.md says how it works. What an app sets is in docs/configuration.md; the variables used here are TOUR_PLUGIN_ID,
# TOUR_PLUGIN_ENTRY, TOUR_PLUGIN_WIDGET, TOUR_SANDBOX_COPY, TOUR_SANDBOX_LINK, DEVKIT_ENV, DEVKIT_GUARD_EXTRA, DEVKIT_NAME and the
# hook devkit_sandbox. The caller sets TMP (a folder for the session), REPO (the app's checkout, linked in as the plugin), W and H.

DEVKIT_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

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
# The status strip (lib/tour-banner.qml) sits NEST_STRIP_GAP pixels from the top of your monitor and is NEST_STRIP_H high; the
# view window (nested_view_open) is centred below it.
NEST_STRIP_GAP=24
NEST_STRIP_H=170

real() { env HYPRLAND_INSTANCE_SIGNATURE="$REAL_SIG" WAYLAND_DISPLAY="$REAL_WD" "$@"; }

nested_requires() {
  local tool
  for tool in Hyprland dbus-run-session wtype gcc wayland-scanner pkg-config; do
    command -v "$tool" >/dev/null || { echo "devkit: the session needs $tool" >&2; return 1; }
  done
  [[ -n $REAL_SIG && -n $REAL_WD ]] || { echo "devkit: this must run inside your Hyprland session" >&2; return 1; }
  [[ -n ${TOUR_PLUGIN_ID:-} ]] || { echo "devkit: TOUR_PLUGIN_ID is not set (devkit.conf in the app's root: the plugin to load in the sandbox)" >&2; return 1; }
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
  # TOUR_PLUGIN_ENTRY (a JSON object, default none) is merged into the plugin's entry: the settings the session starts with.
  # TOUR_PLUGIN_WIDGET=0 is for a plugin with no bar widget (a service): it is loaded, but not put on the bar.
  local entry=${TOUR_PLUGIN_ENTRY:-} widget=${TOUR_PLUGIN_WIDGET:-1}
  [[ -n $entry ]] || entry='{}'
  jq --arg id "$TOUR_PLUGIN_ID" --argjson entry "$entry" --argjson widget "$widget" '
      def own: map(select((if type == "object" then .id else . end) as $i | ($i | tostring | startswith("omarchy.")) or $i == $id));
      {version: 1, bar: ((.bar // {}) | .layout |= (. // {} | with_entries(.value |= (if type == "array" then own else . end)))),
       disabledPlugins: (.disabledPlugins // []),
       plugins: [{id: $id} + $entry]}
      | if $widget == 1 and ([.bar.layout[]?[]? | (if type == "object" then .id else . end)] | index($id)) == null
        then .bar.layout.right += [{id: $id}] else . end' "$real_cfg" >"$h/.config/omarchy/shell.json" ||
    jq -n --arg id "$TOUR_PLUGIN_ID" --argjson entry "$entry" --argjson widget "$widget" '{version: 1, bar: {layout: {left: [{id: "omarchy.menu"}], center: [{id: "omarchy.clock"}], right: (if $widget == 1 then [{id: $id}] else [] end)}}, plugins: [{id: $id} + $entry]}' >"$h/.config/omarchy/shell.json"
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
  if declare -F devkit_sandbox >/dev/null; then devkit_sandbox "$h" || return 1; fi
  if declare -F tour_sandbox >/dev/null; then tour_sandbox "$h"; fi
  "$DEVKIT_LIB/build-vptr.sh" "$NEST_BIN" >/dev/null || { echo "devkit: could not build the virtual pointer client" >&2; return 1; }
}

# The session must never reach your real machine. Its shell shares your user's systemd, your login session and your system
# bus, so a click on a plugin's Shut down, Restart, Sleep, Sign out or Lock would run the real command: the machine would
# go down, or the session you are working in would end or lock. So the session runs with a guard first on its PATH (sandbox_guard):
# a stand-in for each of those commands that refuses and writes the attempt to $NEST/guard.log. The guard is checked before the
# session starts (guard_check), and the session is not started without it.
GUARD=$NEST_BIN/guard

sandbox_guard() {
  local name verb
  mkdir -p "$GUARD"
  : >"$NEST/guard.log"
  # Refused whatever the arguments: they end, lock, suspend or restart the real machine or session. omarchy-system-lock also kills the
  # screensaver and locks 1Password, whichever session it is run from.
  for name in omarchy-system omarchy-system-lock omarchy-system-sleep-lock omarchy-system-sleep-monitor omarchy-system-lid-close \
    omarchy-system-lid-inhibit omarchy-system-wake omarchy-system-factory-reset omarchy-system-factory-reset-finish \
    poweroff reboot shutdown halt hyprlock uwsm "${DEVKIT_GUARD_EXTRA[@]:-}"; do
    [[ -n $name ]] || continue
    printf '#!/bin/bash\necho "$(date +%%T) %s $*" >>%q\necho "test session: %s refused (it would act on the real machine)" >&2\nexit 1\n' \
      "$name" "$NEST/guard.log" "$name" >"$GUARD/$name"
    chmod +x "$GUARD/$name"
  done
  # Refused for the verbs that act on the machine or the login session, passed on for anything else (the shell reads unit states).
  # GUARD_SYSTEMCTL and GUARD_LOGINCTL name the real programs, so a test can put a stand-in there and never reach the real ones.
  verb='poweroff|reboot|suspend|hibernate|hybrid-sleep|suspend-then-hibernate|halt|kexec|soft-reboot|rescue|emergency|exit|isolate|default'
  printf '#!/bin/bash\nfor a in "$@"; do\n  case $a in\n    %s)\n      echo "$(date +%%T) systemctl $*" >>%q\n      echo "test session: systemctl $a refused (it would act on the real machine)" >&2\n      exit 1 ;;\n  esac\ndone\n[ -z "${DEVKIT_GUARD_PROBE:-}" ] || { echo "$(date +%%T) PASSED systemctl $*" >>%q; exit 0; }\nexec %q "$@"\n' \
    "$verb" "$NEST/guard.log" "$NEST/guard.log" "${GUARD_SYSTEMCTL:-/usr/bin/systemctl}" >"$GUARD/systemctl"
  verb='lock-session|lock-sessions|unlock-session|unlock-sessions|terminate-session|terminate-user|terminate-seat|kill-session|kill-user|poweroff|reboot|suspend|hibernate|hybrid-sleep|suspend-then-hibernate|halt'
  printf '#!/bin/bash\nfor a in "$@"; do\n  case $a in\n    %s)\n      echo "$(date +%%T) loginctl $*" >>%q\n      echo "test session: loginctl $a refused (it would act on the real session)" >&2\n      exit 1 ;;\n  esac\ndone\n[ -z "${DEVKIT_GUARD_PROBE:-}" ] || { echo "$(date +%%T) PASSED loginctl $*" >>%q; exit 0; }\nexec %q "$@"\n' \
    "$verb" "$NEST/guard.log" "$NEST/guard.log" "${GUARD_LOGINCTL:-/usr/bin/loginctl}" >"$GUARD/loginctl"
  chmod +x "$GUARD/systemctl" "$GUARD/loginctl"
}

# Proves the guard is what the session will find, through a login shell as well (a plugin may run its commands with bash -lc, and
# a login shell reads /etc/profile, which can rebuild PATH), and that it refuses. The session is not started if this fails.
guard_check() {
  local name out
  for name in omarchy-system omarchy-system-lock systemctl loginctl poweroff hyprlock uwsm; do
    out=$(env PATH="$GUARD:$PATH" HOME="$NEST_HOME" bash -lc "command -v $name" 2>/dev/null) || out=""
    [[ $out == "$GUARD/$name" ]] || { echo "nested: the guard is not first on the session's PATH for $name (found '$out')" >&2; return 1; }
  done
  : >"$NEST/guard.log"
  # In probe mode the systemctl and loginctl stand-ins never pass a command on, so a verb the guard fails to refuse is reported ("PASSED")
  # and not run: a wrong list cannot suspend the machine this check runs on.
  env DEVKIT_GUARD_PROBE=1 PATH="$GUARD:$PATH" HOME="$NEST_HOME" bash -lc 'omarchy-system shutdown; systemctl poweroff; systemctl suspend; loginctl lock-session; omarchy-system-lock' >/dev/null 2>&1 || true
  if grep -q PASSED "$NEST/guard.log" || [[ $(wc -l <"$NEST/guard.log") -ne 5 ]]; then
    echo "nested: the guard did not refuse all five test commands (see $NEST/guard.log)" >&2; return 1
  fi
  : >"$NEST/guard.log"
}

sandbox_repoint() {
  # Nothing of the real config is copied in except what the app lists; the plugin's own settings are in shell.json, which
  # sandbox_build wrote. The guard comes with it.
  sandbox_guard
  guard_check
}

# From here on every command the tour runs, and the recorder's own helpers, act in the sandbox.
sandbox_enter() {
  export HOME=$NEST_HOME XDG_CONFIG_HOME=$NEST_HOME/.config XDG_DATA_HOME=$NEST_HOME/.local/share \
    XDG_STATE_HOME=$NEST_HOME/.local/state XDG_CACHE_HOME=$NEST_HOME/.cache PATH="$GUARD:$PATH"
  # DEVKIT_ENV: NAME=VALUE words an app wants in the session's environment (a demo-mode switch, say).
  local kv
  for kv in "${DEVKIT_ENV[@]:-}"; do
    if [[ -n $kv ]]; then export "${kv?}"; fi
  done
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
-- or send to the scratchpad. The recorder's and bin/dev's own input arrives as separate virtual devices and is unaffected.
-- (NEST_HOST_INPUT=1 leaves them on, for debugging the session by hand.)
if os.getenv("NEST_HOST_INPUT") ~= "1" then
  hl.device({ name = "wl_pointer", enabled = false })
  hl.device({ name = "wl_keyboard", enabled = false })
end
-- The shell starts once the session's window has its final size (nested_send_away creates the file NEST_GO): a shell that starts
-- while the window still has the size the host gave it keeps reporting that size as its screen's, long after the window is resized,
-- and a plugin that works out where things are from its screen (a `layout` that reports pixels) then answers with the wrong pixels.
hl.on("hyprland.start", function()
  local go = os.getenv("NEST_GO")
  local wait = go and ("while [ ! -e '" .. go .. "' ]; do sleep 0.1; done; ") or ""
  hl.exec_cmd(wait .. "QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 quickshell -n -p " .. (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/shell >> " .. (os.getenv("NEST_QS_LOG") or "/dev/null") .. " 2>&1")
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
    # A session that outlives this script (bin/dev): its own process group, found again by its environment, not a pid.
    setsid -f env -u HYPRLAND_INSTANCE_SIGNATURE -u HYPRLAND_CMD NEST_QS_LOG="$NEST/qs.log" NEST_GO="$NEST/go" \
      dbus-run-session --config-file="$NEST/dbus.conf" -- Hyprland -c "$NEST/hypr.lua" >"$NEST/hypr.log" 2>&1
    nest_pid=detached
  else
    env -u HYPRLAND_INSTANCE_SIGNATURE -u HYPRLAND_CMD NEST_QS_LOG="$NEST/qs.log" NEST_GO="$NEST/go" \
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
  # The window has its final size: the session's shell may start now (see hypr.lua in nested_start).
  : >"$NEST/go"
  return 0
}

# Processes that carry a given variable=value in their environment.
procs_with() { local p; for p in /proc/[0-9]*; do p=${p#/proc/}; [[ $p != "$$" && -r /proc/$p/environ ]] || continue
  tr '\0' '\n' </proc/"$p"/environ 2>/dev/null | grep -qx "$1" && echo "$p"; done 2>/dev/null || true; }

# A view-only window on your screen showing the session five times a second (lib/dev-view.qml). Drag it, cover it, resize it: your
# pointer is the normal arrow over it and nothing in it listens. The picture loop runs while the file LIVE_FILE is not empty.
nested_view_open() { # LIVE_FILE
  local live=$1 frame=$NEST/frame.jpg addr="" i ws mx my mw mh
  [[ -z $(procs_with "NEST_VIEW=1") ]] || return 0
  WAYLAND_DISPLAY=$NWD grim -t jpeg -q 75 "$frame" || { echo "tour: grim could not capture the session" >&2; return 1; }
  # Written to a temporary name and renamed so the window never reads half a file.
  setsid -f env NEST_VIEW=1 bash -c 'while [[ -s $2 ]]; do WAYLAND_DISPLAY=$1 grim -t jpeg -q 75 "$3.new" 2>/dev/null && mv -f "$3.new" "$3"; sleep 0.2; done' _ "$NWD" "$live" "$frame" >/dev/null 2>&1 </dev/null
  setsid -f env NEST_VIEW=1 QS_APP_ID="${DEVKIT_NAME:-app}-test-viewer" DEV_TITLE="${DEVKIT_NAME:-app} test session" DEV_FRAME="$frame" HOME="$REAL_HOME" XDG_CONFIG_HOME="$REAL_HOME/.config" XDG_DATA_HOME="$REAL_HOME/.local/share" XDG_STATE_HOME="$REAL_HOME/.local/state" XDG_CACHE_HOME="$REAL_HOME/.cache" \
    WAYLAND_DISPLAY="$REAL_WD" HYPRLAND_INSTANCE_SIGNATURE="$REAL_SIG" quickshell -n -p "$DEVKIT_LIB/dev-view.qml" >/dev/null 2>&1
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
nest_rclick() { WAYLAND_DISPLAY=$NWD "$VPTR" rclick "$1" "$2" "$NW" "$NH"; }
nest_scroll() { WAYLAND_DISPLAY=$NWD "$VPTR" scroll "$1" "$2" "$NW" "$NH" "$3"; }
nest_drag() { WAYLAND_DISPLAY=$NWD "$VPTR" drag "$gx" "$gy" "$NW" "$NH" "$1" "$2"; gx=$((gx + $1)); gy=$((gy + $2)); }
nest_type() { WAYLAND_DISPLAY=$NWD wtype -d 45 -- "$1"; }
nest_key() { WAYLAND_DISPLAY=$NWD wtype -k "$1"; }
