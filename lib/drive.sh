# shellcheck shell=bash
# Drive state and the everyday actions: mount, unmount, open, usage.

is_mounted() { mountpoint -q "$(mount_path "$1")" 2>/dev/null; }

# unit_property <unit> <property>: one value from `systemctl show`.
unit_property() {
  systemctl --user show "$1" -p "$2" 2>/dev/null | sed -n "s/^$2=//p"
}

drive_state_json() { # <id> <configured: true|false>
  local id="$1" configured="$2" mounted=false unit_state
  is_mounted "$id" && mounted=true
  unit_state="$(unit_property "$(unit_of "$id")" ActiveState)"
  jq -nc --arg id "$id" --arg remote "$(remote_of "$id")" --arg name "$(name_of "$id")" \
    --arg glyph "$(glyph_of "$id")" --arg path "$(mount_path "$id")" --arg unit "${unit_state:-inactive}" \
    --argjson configured "$configured" --argjson mounted "$mounted" \
    --argjson settings "$(settings_json "$id")" --argjson cacheBytes "$(cache_bytes "$id")" \
    '{id: $id, remote: $remote, name: $name, glyph: $glyph, path: $path, unit: $unit,
      configured: $configured, mounted: $mounted, settings: $settings, cacheBytes: $cacheBytes}'
}

cmd_state() {
  local remotes id configured rows=() rclone=false encrypted=false keyring=false legacy=false
  remotes="$(list_remotes)"
  for id in $(provider_ids); do
    configured=false
    grep -qx "$(remote_of "$id")" <<<"$remotes" && configured=true
    rows+=("$(drive_state_json "$id" "$configured")")
  done
  have_rclone && rclone=true
  config_encrypted && encrypted=true
  have_secret && keyring=true
  has_legacy_units && legacy=true
  jq -nc --argjson rclone "$rclone" --argjson encrypted "$encrypted" --argjson keyring "$keyring" \
    --argjson legacy "$legacy" --arg root "$MOUNT_ROOT" \
    --argjson drives "$(printf '%s\n' "${rows[@]}" | jq -sc .)" \
    '{rclone: $rclone, encrypted: $encrypted, keyring: $keyring, legacy: $legacy, root: $root, drives: $drives}'
}

cmd_mount() {
  local id="$1"
  is_configured "$id" || fail "$(name_of "$id") is not connected yet"
  ensure_unit
  systemctl --user start "$(unit_of "$id")"
}

cmd_unmount() {
  local id="$1"
  systemctl --user stop "$(unit_of "$id")" 2>/dev/null || true
  # A lazy unmount is the fallback for a mount whose process is already gone.
  ! is_mounted "$id" || fusermount3 -uz "$(mount_path "$id")" || true
}

# mount-all / unmount-all: every connected drive; one failing does not stop the rest.
cmd_all() { # <mount|unmount>
  local id
  for id in $(provider_ids); do
    is_configured "$id" || continue
    "cmd_$1" "$id" || true
  done
}

# Used and total bytes as JSON; {} when the backend does not report them.
cmd_about() {
  local id="$1"
  is_configured "$id" || { echo '{}'; return; }
  timeout 20 rclone about --json "$(remote_of "$id"):" 2>/dev/null |
    jq -c '{used: (.used // (.total - .free)), total: .total} | with_entries(select(.value != null))' 2>/dev/null ||
    echo '{}'
}

window_for() { # <title>: the address of a mapped window with that title
  hyprctl clients -j | jq -r --arg t "$1" '[.[] | select(.title == $t and .mapped)] | .[0].address // empty'
}

focus_window() { # <address>
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" >/dev/null 2>&1 ||
    hyprctl dispatch focuswindow "address:$1" >/dev/null 2>&1 || true
}

# Open the folder, reusing a file-manager window already showing it, and focus
# the result (it may land on another monitor's workspace).
cmd_open() {
  local id="$1" remote dir addr="" i
  remote="$(remote_of "$id")"
  dir="$(mount_path "$id")"
  is_mounted "$id" || cmd_mount "$id"
  addr="$(window_for "$remote")"
  if [[ -z $addr ]]; then
    setsid uwsm-app -- xdg-open "$dir" >/dev/null 2>&1 &
    for ((i = 0; i < 50; i++)); do
      addr="$(window_for "$remote")"
      [[ -n $addr ]] && break
      sleep 0.1
    done
  fi
  [[ -n $addr ]] && focus_window "$addr"
  return 0
}

# Run one of our interactive commands in a floating terminal, for the steps
# that need you (browser sign-in, 2FA, confirmation). Only those commands are
# accepted, so this cannot be used to run anything else.
cmd_launch() {
  local command="${1:-}" id="${2:-}"
  case "$command" in
    connect | disconnect) ;;
    *) fail "launch: '$command' is not an interactive command" ;;
  esac
  remote_of "$id" >/dev/null
  exec omarchy-launch-floating-terminal-with-presentation "$(printf '%q ' "$SD_HOME/bin/startdrive" "$command" "$id")"
}

cmd_disconnect() {
  local id="$1" name pending prompt
  name="$(name_of "$id")"
  prompt="Disconnect $name and forget its credentials on this machine?"
  if pending="$(pending_uploads "$id" 2>/dev/null)" && ((pending > 0)); then
    prompt="$pending file(s) have not finished uploading to $name and will be lost. $prompt"
  fi
  gum confirm "$prompt" || exit 130
  cmd_unmount "$id"
  systemctl --user disable "$(unit_of "$id")" 2>/dev/null || true
  is_configured "$id" && rclone config delete "$(remote_of "$id")"
  rm -f -- "$(settings_file "$id")"
  while read -r dir; do
    [[ $dir == "$CACHE_ROOT"/vfs/?* || $dir == "$CACHE_ROOT"/vfsMeta/?* ]] && rm -rf -- "$dir"
  done < <(cache_dirs "$id")
  rmdir "$(mount_path "$id")" 2>/dev/null || true
  echo "$name disconnected."
}
