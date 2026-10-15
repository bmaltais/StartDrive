# shellcheck shell=bash
# The plugin's own preferences and its desktop integration: the app launcher entry, the command-line link, the optional bar
# icon, the first-run answer and where the windows were last left. The UI never edits these; it asks `startdrive integration`
# for the state and `startdrive setup` to change it, the same as the other Start apps.

readonly PLUGIN_ID="io.github.bmaltais.startdrive"
readonly PREFS_FILE="$CONFIG_DIR/config"
readonly DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
readonly SVG_ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
readonly CLI_LINK="$HOME/.local/bin/startdrive"
readonly SELF="$SD_HOME/bin/startdrive"

# The recommended set, in one place: what a first run offers, what Reset goes back to, and what a preference reads as before
# anyone changed it. `integration` hands them to the UI as "defaults". The bar icon is on by default here (unlike the other
# Start apps) because it is where sync status lives: the upload and alert glyphs say whether it is safe to shut down.
readonly DEFAULT_LAUNCHER=true
readonly DEFAULT_CLI=true
readonly DEFAULT_BAR_ICON=true
readonly DEFAULT_REMEMBER=true

prefs_get() { sed -n "s/^$1=//p" "$PREFS_FILE" 2>/dev/null | head -n1 || true; }
prefs_set() { # KEY VALUE: replace or add one line
  { grep -v "^$1=" "$PREFS_FILE" 2>/dev/null || true; echo "$1=$2"; } | write_file "$PREFS_FILE" 0600
}
prefs_bool() { # KEY -> true|false; a key nobody set reads as the default for remembering
  local v; v="$(prefs_get "$1")"
  if [[ -z $v ]]; then echo "$DEFAULT_REMEMBER"; elif [[ $v == false ]]; then echo false; else echo true; fi
}
is_true() { [[ $1 == true ]]; }
short_home() { local p=$1; [[ $p == "$HOME"/* ]] && p="~${p#"$HOME"}"; printf '%s' "$p"; }

# With --json a failure is one JSON line on stdout, {ok:false, field, error}; field names the preference it was about.
JSON_RESULT=0
SETUP_FIELD="" SETUP_ERROR=""
setup_fail() {
  if [[ -z $SETUP_ERROR ]]; then SETUP_FIELD=$1 SETUP_ERROR=$2; fi
  if [[ $JSON_RESULT != 1 ]]; then echo "startdrive: $2" >&2; fi
}
refresh_desktop_db() { if command -v update-desktop-database >/dev/null; then update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true; fi; }

# ---- the app launcher entry ----------------------------------------------------
launcher_on() {
  mkdir -p -- "$DESKTOP_DIR" "$SVG_ICON_DIR"
  write_file "$DESKTOP_DIR/startdrive.desktop" 0644 <<DESKTOP
[Desktop Entry]
Type=Application
Name=StartDrive
GenericName=Cloud Drives
Comment=Mount Google Drive, OneDrive, Dropbox and more as folders
Exec="$SELF" ui
Icon=startdrive
Categories=System;Utility;FileTools;
Keywords=cloud;drive;google;onedrive;dropbox;rclone;mount;sync;
Terminal=false
DESKTOP
  write_file "$SVG_ICON_DIR/startdrive.svg" 0644 <"$SD_HOME/assets/startdrive.svg"
  refresh_desktop_db
}
launcher_off() {
  rm -f -- "$DESKTOP_DIR/startdrive.desktop" "$SVG_ICON_DIR/startdrive.svg"
  refresh_desktop_db
}

# ---- the command-line link -----------------------------------------------------
# ours | other | none: whose file, if any, sits at ~/.local/bin/startdrive
cli_state() {
  if [[ -L $CLI_LINK && $(realpath "$CLI_LINK" 2>/dev/null) == "$(realpath "$SELF")" ]]; then echo ours
  elif [[ -e $CLI_LINK || -L $CLI_LINK ]]; then echo other
  else echo none; fi
}
cli_on() {
  case "$(cli_state)" in
    ours) return 0 ;;
    other) setup_fail cli "$(short_home "$CLI_LINK") already exists and is not StartDrive, so it was left alone"; return 1 ;;
  esac
  mkdir -p -- "$(dirname "$CLI_LINK")"
  ln -s "$SELF" "$CLI_LINK"
}
cli_off() { [[ $(cli_state) != ours ]] || rm -f -- "$CLI_LINK"; }

# ---- the optional bar icon -----------------------------------------------------
# The plugin is also a bar widget. It sits on the bar only when the layout in shell.json lists it, so adding or removing the
# icon edits that layout and leaves the plugin itself enabled.
bar_shell_json() {
  local f="$HOME/.config/omarchy/shell.json"
  [[ -s $f ]] || f="${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json"
  printf '%s' "$f"
}
bar_icon_state() { # true | false
  local f; f="$(bar_shell_json)"
  if jq -e --arg id "$PLUGIN_ID" '[.bar.layout[]?[]? | if type == "object" then .id else . end] | index($id) != null' "$f" >/dev/null 2>&1; then
    echo true
  else
    echo false
  fi
}
# The jq programs that put the icon on the bar and take it off (run after NORMALIZE, from omarchy-shell-config). Omarchy counts a
# plugin as enabled when its id is in the bar layout or in `plugins`, and a plugin enabled as a bar widget is only in the layout.
# So taking the icon off would leave nothing that enables this plugin's service, and it would not load on the next restart:
# both programs make sure `plugins` lists it.
readonly BAR_KEEP_PLUGIN='.plugins |= (if any(.[]; (if type == "object" then .id else . end) == $id) then . else . + [{id: $id}] end)'
readonly BAR_ADD_JQ=".bar.layout.right += [{id: \$id}] | $BAR_KEEP_PLUGIN"
readonly BAR_REMOVE_JQ=".bar.layout |= with_entries(.value |= (if type == \"array\" then map(select((if type == \"object\" then .id else . end) != \$id)) else . end)) | $BAR_KEEP_PLUGIN"

bar_icon_set() {
  command -v omarchy-shell-config >/dev/null || { setup_fail barIcon "the Omarchy bar is not available here"; return 1; }
  if is_true "$1"; then
    [[ $(bar_icon_state) == true ]] && return 0
    ( source omarchy-shell-config; commit "$NORMALIZE | $BAR_ADD_JQ" --arg id "$PLUGIN_ID" )
  else
    [[ $(bar_icon_state) == false ]] && return 0
    ( source omarchy-shell-config; commit "$NORMALIZE | $BAR_REMOVE_JQ" --arg id "$PLUGIN_ID" )
  fi
}

# ---- integration: what is switched on, as JSON for the settings window -------------
cmd_integration() {
  local launcher=false finished=false
  [[ ! -f $DESKTOP_DIR/startdrive.desktop ]] || launcher=true
  # People who switched the launcher entry on before the first-run offer existed have already answered it.
  { [[ "$(prefs_get SETUP_DONE)" == 1 ]] || [[ $launcher == true ]]; } && finished=true
  jq -nc --argjson launcher "$launcher" --argjson finished "$finished" \
    --arg cli "$(cli_state)" --arg cliPath "$(short_home "$CLI_LINK")" --argjson baricon "$(bar_icon_state)" \
    --argjson rsize "$(prefs_bool REMEMBER_SIZE)" --argjson rpos "$(prefs_bool REMEMBER_POSITION)" \
    --argjson dlauncher "$DEFAULT_LAUNCHER" --argjson dcli "$DEFAULT_CLI" --argjson dbar "$DEFAULT_BAR_ICON" \
    --argjson dremember "$DEFAULT_REMEMBER" --arg root "$MOUNT_ROOT" \
    '{launcher: $launcher, cli: {state: $cli, path: $cliPath}, barIcon: $baricon, rememberSize: $rsize, rememberPosition: $rpos,
      done: $finished, root: $root,
      defaults: {launcher: $dlauncher, cli: $dcli, barIcon: $dbar, rememberSize: $dremember, rememberPosition: $dremember}}'
}

# setup [--launcher B] [--cli B] [--bar-icon B] [--remember-size B] [--remember-position B] [--done] [--json]
# Only what is named is touched. --done records that the first-run offer has been answered.
cmd_setup() {
  local launcher="" cli="" baricon="" rsize="" rpos="" mark=0 failed=0 a
  for a in "$@"; do [[ $a != --json ]] || JSON_RESULT=1; done
  setup_arg_fail() { if [[ $JSON_RESULT == 1 ]]; then jq -nc --arg e "$1" '{ok: false, field: "", error: $e}'; exit 1; else fail "$1"; fi; }
  while (($#)); do
    case $1 in
      --json) shift ;;
      --launcher | --cli | --bar-icon | --remember-size | --remember-position)
        [[ ${2:-} == true || ${2:-} == false ]] || setup_arg_fail "setup: $1 takes true or false"
        case $1 in
          --launcher) launcher=$2 ;; --cli) cli=$2 ;; --bar-icon) baricon=$2 ;;
          --remember-size) rsize=$2 ;; --remember-position) rpos=$2 ;;
        esac
        shift 2 ;;
      --done) mark=1; shift ;;
      *) setup_arg_fail "setup: unknown option $1" ;;
    esac
  done
  if [[ -n $launcher ]]; then if is_true "$launcher"; then launcher_on; else launcher_off; fi; fi
  if [[ -n $cli ]]; then if is_true "$cli"; then cli_on || failed=1; else cli_off; fi; fi
  # Switching one off also forgets what was saved, so the next open starts from the default.
  if [[ -n $rsize ]]; then
    prefs_set REMEMBER_SIZE "$rsize"
    is_true "$rsize" || { prefs_set WIN_W ""; prefs_set WIN_H ""; prefs_set SETUP_W ""; prefs_set SETUP_H ""; }
  fi
  if [[ -n $rpos ]]; then
    prefs_set REMEMBER_POSITION "$rpos"
    is_true "$rpos" || { prefs_set WIN_X ""; prefs_set WIN_Y ""; prefs_set SETUP_X ""; prefs_set SETUP_Y ""; }
  fi
  [[ $mark -eq 0 && -z $launcher$cli$baricon$rsize$rpos ]] || prefs_set SETUP_DONE 1
  # Last: changing the bar makes the shell reload its config, which can restart the plugin (and this process) part-way through.
  [[ -z $baricon ]] || bar_icon_set "$baricon" || failed=1
  if [[ $JSON_RESULT == 1 ]]; then
    if ((failed)); then jq -nc --arg field "$SETUP_FIELD" --arg error "$SETUP_ERROR" '{ok: false, field: $field, error: $error}'
    else jq -nc '{ok: true}'; fi
  fi
  return "$failed"
}

# window [--size WxH] [--offset X,Y] [--reset] [--setup-size WxH] [--setup-offset X,Y] [--reset-setup]
# The manager's and the settings window's size and offset from the screen centre. No option prints them as JSON.
cmd_window() {
  local k v out=()
  while (($#)); do
    case $1 in
      --size) [[ ${2:-} =~ ^[0-9]+x[0-9]+$ ]] || fail "window: --size takes WIDTHxHEIGHT"
        prefs_set WIN_W "${2%x*}"; prefs_set WIN_H "${2#*x}"; shift 2 ;;
      --offset) [[ ${2:-} =~ ^-?[0-9]+,-?[0-9]+$ ]] || fail "window: --offset takes X,Y"
        prefs_set WIN_X "${2%,*}"; prefs_set WIN_Y "${2#*,}"; shift 2 ;;
      --setup-size) [[ ${2:-} =~ ^[0-9]+x[0-9]+$ ]] || fail "window: --setup-size takes WIDTHxHEIGHT"
        prefs_set SETUP_W "${2%x*}"; prefs_set SETUP_H "${2#*x}"; shift 2 ;;
      --setup-offset) [[ ${2:-} =~ ^-?[0-9]+,-?[0-9]+$ ]] || fail "window: --setup-offset takes X,Y"
        prefs_set SETUP_X "${2%,*}"; prefs_set SETUP_Y "${2#*,}"; shift 2 ;;
      --reset) for k in WIN_W WIN_H WIN_X WIN_Y; do prefs_set "$k" ""; done; shift ;;
      --reset-setup) for k in SETUP_W SETUP_H SETUP_X SETUP_Y; do prefs_set "$k" ""; done; shift ;;
      *) fail "window: unknown option $1" ;;
    esac
  done
  for k in WIN_W WIN_H WIN_X WIN_Y SETUP_W SETUP_H SETUP_X SETUP_Y; do
    v="$(prefs_get "$k")"; [[ $v =~ ^-?[0-9]+$ ]] || v=0; out+=("$v")
  done
  # While remembering is off nothing saved is reported, whatever an older config still holds.
  if [[ $(prefs_bool REMEMBER_SIZE) == false ]]; then out[0]=0 out[1]=0 out[4]=0 out[5]=0; fi
  if [[ $(prefs_bool REMEMBER_POSITION) == false ]]; then out[2]=0 out[3]=0 out[6]=0 out[7]=0; fi
  jq -nc --argjson w "${out[0]}" --argjson h "${out[1]}" --argjson x "${out[2]}" --argjson y "${out[3]}" \
    --argjson sw "${out[4]}" --argjson sh "${out[5]}" --argjson sx "${out[6]}" --argjson sy "${out[7]}" \
    '{w: $w, h: $h, x: $x, y: $y, setup: {w: $sw, h: $sh, x: $sx, y: $sy}}'
}

# ui: toggle the manager window of the running plugin.
cmd_ui() {
  omarchy-shell "$PLUGIN_ID" open || fail "the StartDrive plugin is not running (omarchy plugin enable $PLUGIN_ID)"
}
