# shellcheck shell=bash
# Per-drive settings, stored as rclone environment variables in
# ~/.config/startdrive/<remote>.env and read by the mount unit.

# key|rclone environment variable|default. The mount settings, in the order they
# are written to the file. "autostart" is not here: it is the unit's enablement.
readonly -a SETTINGS=(
  "cache-size|RCLONE_VFS_CACHE_MAX_SIZE|4G"
  "cache-age|RCLONE_VFS_CACHE_MAX_AGE|72h"
  "read-only|RCLONE_READ_ONLY|false"
)

settings_file() { echo "$CONFIG_DIR/$(remote_of "$1").env"; }

setting_keys() {
  local row
  for row in "${SETTINGS[@]}"; do echo "${row%%|*}"; done
}

# setting_column <key> <2|3>: the environment variable or the default.
setting_column() {
  local row
  for row in "${SETTINGS[@]}"; do
    [[ ${row%%|*} == "$1" ]] && { cut -d'|' -f"$2" <<<"$row"; return; }
  done
}

# valid_setting <key> <value>: the allow-list. Values are written into a file
# systemd reads, so nothing outside these shapes is ever accepted.
valid_setting() {
  case "$1" in
    cache-size) [[ $2 =~ ^[1-9][0-9]{0,3}[MG]$ ]] ;;
    cache-age) [[ $2 =~ ^[1-9][0-9]{0,4}h$ ]] ;;
    read-only | autostart) [[ $2 == true || $2 == false ]] ;;
    *) return 1 ;;
  esac
}

# setting_value <id> <key>: the stored value, or the default.
setting_value() {
  local id="$1" key="$2" file name value
  file="$(settings_file "$id")"
  name="$(setting_column "$key" 2)"
  if [[ -r $file ]]; then
    value="$(sed -n "s/^${name}=//p" "$file" | tail -n1)"
  fi
  if [[ -n ${value:-} ]] && valid_setting "$key" "$value"; then
    echo "$value"
  else
    setting_column "$key" 3
  fi
}

# Whether the drive mounts at login: the state of the unit's enablement.
autostart_enabled() {
  systemctl --user is-enabled --quiet "$(unit_of "$1")" 2>/dev/null
}

# The panel's field for a key: cache-size -> cacheSize (see SETTINGS in DriveModel.js).
json_field() { sed -E 's/-(.)/\U\1/g' <<<"$1"; }

settings_json() { # <id>
  local auto=false key
  autostart_enabled "$1" && auto=true
  {
    for key in $(setting_keys); do printf '%s\t%s\n' "$(json_field "$key")" "$(setting_value "$1" "$key")"; done
    printf 'autostart\t%s\n' "$auto"
  } | jq -Rnc '[inputs | split("\t") | {key: .[0], value: (.[1] | if . == "true" then true elif . == "false" then false else . end)}] | from_entries'
}

# write_settings <id> <key> <value>: every mount setting, with <key> changed.
write_settings() {
  local id="$1" changed="$2" new="$3" key
  for key in $(setting_keys); do
    if [[ $key == "$changed" ]]; then
      echo "$(setting_column "$key" 2)=$new"
    else
      echo "$(setting_column "$key" 2)=$(setting_value "$id" "$key")"
    fi
  done | write_file "$(settings_file "$id")" 0600
}

# set <id> <key> <value>. Mount options take effect when the mount restarts:
# immediately if nothing is uploading, otherwise at the next mount.
cmd_set() {
  local id="$1" key="$2" value="$3" unit pending
  valid_setting "$key" "$value" || fail "invalid setting: $key=$value"
  unit="$(unit_of "$id")"

  if [[ $key == autostart ]]; then
    if [[ $value == true ]]; then systemctl --user enable "$unit" 2>/dev/null; else systemctl --user disable "$unit" 2>/dev/null; fi
    echo "Saved."
    return
  fi

  write_settings "$id" "$key" "$value"

  systemctl --user is-active --quiet "$unit" || { echo "Saved. Applies when mounted."; return; }
  if pending="$(pending_uploads "$id")" && ((pending == 0)); then
    systemctl --user restart "$unit"
    echo "Saved and applied."
  else
    echo "Saved. Applies at the next mount, since files are still uploading."
  fi
}
