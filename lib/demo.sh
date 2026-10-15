# shellcheck shell=bash
# Demo mode: fixture drives and no contact with the real machine. Loaded by bin/startdrive only when STARTDRIVE_DEMO=1 or the
# marker file $CONFIG_DIR/demo/ENABLED exists. The test session (scripts/dev), the screenshots and the tours run in it, because
# that session shares your user's systemd, keyring and rclone config: without this, a click on a mount switch there would mount
# a real account. Everything the real commands would ask of those is answered from files in $CONFIG_DIR/demo instead, and the
# tools themselves are shadowed by functions that refuse, so a code path nobody thought of fails loudly rather than reaching them.
#
# The fixture: Google Drive (mounted, three files uploading), OneDrive (mounted, synced), Dropbox (not connected) and an SFTP
# remote called Work-NAS (not mounted).

readonly DEMO_DIR="$CONFIG_DIR/demo"

demo_blocked() {
  echo "startdrive: demo mode refuses to run '$1'" >&2
  return 1
}
# Shadow every tool that could reach the real machine.
for _tool in systemctl rclone secret-tool fusermount3 hyprctl xdg-open uwsm-app omarchy-pkg-add omarchy-launch-floating-terminal-with-presentation gum curl; do
  eval "$_tool() { demo_blocked $_tool; }"
done
unset _tool

demo_seed() {
  [[ -e $DEMO_DIR/seeded ]] && return 0
  mkdir -p "$DEMO_DIR/mounted" "$DEMO_DIR/autostart"
  : >"$DEMO_DIR/mounted/GoogleDrive"
  : >"$DEMO_DIR/mounted/OneDrive"
  : >"$DEMO_DIR/autostart/GoogleDrive"
  : >"$DEMO_DIR/autostart/OneDrive"
  : >"$DEMO_DIR/seeded"
}
demo_seed

have_rclone() { return 0; }
have_secret() { return 0; }
config_encrypted() { return 0; }
has_legacy_units() { return 1; }
list_remotes() { printf '%s\n' GoogleDrive OneDrive Work-NAS; }
custom_dump() { echo '{"Work-NAS":"sftp"}'; }
shared_client_remotes() { return 0; }

is_mounted() { [[ -e $DEMO_DIR/mounted/$(remote_of "$1") ]]; }
unit_property() { # <unit> <property>
  local remote=${1#"$UNIT_TEMPLATE"}; remote=${remote%.service}
  if [[ $2 == ActiveState ]]; then [[ -e $DEMO_DIR/mounted/$remote ]] && echo active || echo inactive; fi
}
autostart_enabled() { [[ -e $DEMO_DIR/autostart/$(remote_of "$1") ]]; }
cache_bytes() {
  [[ ! -e $DEMO_DIR/cleared/$(remote_of "$1") ]] || { echo 0; return; }
  case "$(remote_of "$1")" in
    GoogleDrive) echo 1800000000 ;;
    OneDrive) echo 312000000 ;;
    *) echo 0 ;;
  esac
}
pending_uploads() { if [[ $(remote_of "$1") == GoogleDrive ]]; then echo 3; else echo 0; fi; }

drive_activity() {
  if [[ $(remote_of "$1") == GoogleDrive ]]; then
    jq -nc --arg id "$1" '{id: $id, uploading: 2, queued: 1, errored: 0, speed: 2400000, transfers: [
      {name: "Holiday 2026.mov", size: 1800000000, bytes: 1100000000, percentage: 61, speed: 1900000},
      {name: "Q3 report.pdf", size: 5400000, bytes: 3900000, percentage: 72, speed: 500000}]}'
  else
    jq -nc --arg id "$1" '{id: $id, uploading: 0, queued: 0, errored: 0, speed: 0, transfers: []}'
  fi
}

cmd_about() {
  case "$(remote_of "$1")" in
    GoogleDrive) echo '{"used":11200000000,"total":15000000000}' ;;
    OneDrive) echo '{"used":212000000000,"total":1100000000000}' ;;
    *) echo '{}' ;;
  esac
}

cmd_mount() {
  is_configured "$1" || fail "$(name_of "$1") is not connected yet"
  : >"$DEMO_DIR/mounted/$(remote_of "$1")"
}
cmd_unmount() { rm -f -- "$DEMO_DIR/mounted/$(remote_of "$1")"; }
cmd_open() { echo "Demo: would open $(mount_path "$1")"; }
cmd_launch() { echo "Demo: would run '${1:-}' in a terminal"; }
cmd_connect() { echo "Demo: would sign in to $(name_of "$1")"; }
cmd_disconnect() { echo "Demo: would forget $(name_of "$1")"; }
cmd_client_id() { echo "Demo: would set up a Google key"; }
cmd_add() { echo "Demo: would add a remote"; }
cmd_prepare() { echo "Demo: nothing to install"; }
migrate_legacy() { return 0; }
cmd_uninstall() { fail "demo mode does not uninstall anything"; }
cmd_refresh_listing() { echo "Directory listing refreshed."; }
cmd_clear_cache() {
  local pending; pending="$(pending_uploads "$1")"
  ((pending == 0)) || fail "$pending file(s) are still uploading; try again once they are done"
  mkdir -p "$DEMO_DIR/cleared"
  : >"$DEMO_DIR/cleared/$(remote_of "$1")"
  echo "Cache cleared."
}

# The real cmd_set restarts units; here a mount setting is only saved, and the two flags are files.
cmd_set() {
  local id="$1" key="$2" value="$3" remote
  valid_setting "$key" "$value" || fail "invalid setting: $key=$value"
  remote="$(remote_of "$id")"
  case "$key" in
    autostart)
      mkdir -p "$DEMO_DIR/autostart"
      if [[ $value == true ]]; then : >"$DEMO_DIR/autostart/$remote"; else rm -f -- "$DEMO_DIR/autostart/$remote"; fi ;;
    notifications)
      private_dir "$CONFIG_DIR"
      if [[ $value == true ]]; then rm -f -- "$CONFIG_DIR/$remote.quiet"; else : >"$CONFIG_DIR/$remote.quiet"; fi ;;
    *) write_settings "$id" "$key" "$value" ;;
  esac
  echo "Saved."
}
