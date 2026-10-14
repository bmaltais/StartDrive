# shellcheck shell=bash
# shellcheck disable=SC2034  # SETTING_KEYS documents the allow-list
# Per-drive settings, stored as rclone environment variables in
# ~/.config/startdrive/<remote>.env and read by the mount unit.

readonly SETTING_KEYS=(cache-size cache-age read-only autostart)
readonly DEFAULT_CACHE_SIZE=4G
readonly DEFAULT_CACHE_AGE=72h

settings_file() { echo "$CONFIG_DIR/$(remote_of "$1").env"; }

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

env_name() {
  case "$1" in
    cache-size) echo RCLONE_VFS_CACHE_MAX_SIZE ;;
    cache-age) echo RCLONE_VFS_CACHE_MAX_AGE ;;
    read-only) echo RCLONE_READ_ONLY ;;
  esac
}

# setting_value <id> <key>: the stored value, or the default.
setting_value() {
  local id="$1" key="$2" file name value
  file="$(settings_file "$id")"
  name="$(env_name "$key")"
  if [[ -r $file ]]; then
    value="$(sed -n "s/^${name}=//p" "$file" | tail -n1)"
  fi
  if [[ -n ${value:-} ]] && valid_setting "$key" "$value"; then
    echo "$value"
    return
  fi
  case "$key" in
    cache-size) echo "$DEFAULT_CACHE_SIZE" ;;
    cache-age) echo "$DEFAULT_CACHE_AGE" ;;
    read-only) echo false ;;
  esac
}

# Whether the drive mounts at login: the state of the unit's enablement.
autostart_enabled() {
  systemctl --user is-enabled --quiet "$(unit_of "$1")" 2>/dev/null
}

settings_json() { # <id>
  local auto=false
  autostart_enabled "$1" && auto=true
  jq -nc --arg size "$(setting_value "$1" cache-size)" --arg age "$(setting_value "$1" cache-age)" \
    --argjson ro "$(setting_value "$1" read-only)" --argjson auto "$auto" \
    '{cacheSize: $size, cacheAge: $age, readOnly: $ro, autostart: $auto}'
}

write_settings() { # <id> <size> <age> <read-only>
  {
    echo "RCLONE_VFS_CACHE_MAX_SIZE=$2"
    echo "RCLONE_VFS_CACHE_MAX_AGE=$3"
    echo "RCLONE_READ_ONLY=$4"
  } | write_file "$(settings_file "$1")" 0600
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

  local size age ro
  size="$(setting_value "$id" cache-size)"
  age="$(setting_value "$id" cache-age)"
  ro="$(setting_value "$id" read-only)"
  case "$key" in
    cache-size) size="$value" ;;
    cache-age) age="$value" ;;
    read-only) ro="$value" ;;
  esac
  write_settings "$id" "$size" "$age" "$ro"

  systemctl --user is-active --quiet "$unit" || { echo "Saved. Applies when mounted."; return; }
  if pending="$(pending_uploads "$id")" && ((pending == 0)); then
    systemctl --user restart "$unit"
    echo "Saved and applied."
  else
    echo "Saved. Applies at the next mount, since files are still uploading."
  fi
}
