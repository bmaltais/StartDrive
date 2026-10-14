# shellcheck shell=bash
# Talking to a running mount through rclone's remote-control API, over the
# private unix socket the mount unit creates (systemd/startdrive@.service).

mount_sock() { echo "$RUN_DIR/$(remote_of "$1")/rc.sock"; }

# mount_rc <id> <rc path> [json body]: the JSON reply on stdout. Fails when the
# mount is not running or predates the socket.
mount_rc() {
  local id="$1" path="$2" body="${3:-}" sock
  [[ -n $body ]] || body='{}'
  sock="$(mount_sock "$id")"
  [[ -S $sock ]] || return 1
  curl -sS --fail-with-body --max-time 8 --unix-socket "$sock" -X POST \
    -H 'Content-Type: application/json' --data-binary "$body" "http://rc/$path"
}

# Transfer and cache figures for one mounted drive, as one JSON object.
drive_activity() {
  local id="$1" vfs core
  vfs="$(mount_rc "$id" vfs/stats)" || return 1
  core="$(mount_rc "$id" core/stats)" || return 1
  jq -nc --arg id "$id" --argjson vfs "$vfs" --argjson core "$core" '
    ($vfs.diskCache // {}) as $disk
    | {
        id: $id,
        uploading: ($disk.uploadsInProgress // 0),
        queued: ($disk.uploadsQueued // 0),
        errored: ($disk.erroredFiles // 0),
        outOfSpace: ($disk.outOfSpace // false),
        cacheBytes: ($disk.bytesUsed // 0),
        cacheFiles: ($disk.files // 0),
        speed: ($core.speed // 0),
        transfers: [ ($core.transferring // [])[:4][]
          | {name: (.name // "")[:160], size: (.size // 0), bytes: (.bytes // 0),
             percentage: (.percentage // 0), speed: (.speed // 0)} ]
      }'
}

# Activity for every mounted drive: a JSON array. Drives whose socket is not
# answering are left out.
cmd_activity() {
  local id out=()
  for id in $(provider_ids); do
    mountpoint -q "$(mount_path "$id")" 2>/dev/null || continue
    out+=("$(drive_activity "$id" 2>/dev/null)") || true
  done
  printf '%s\n' "${out[@]}" | jq -sc '[.[] | select(. != null)]'
}

# Files still on their way to the cloud: uploading plus queued. Fails when the
# count cannot be read, so callers can refuse a destructive step.
pending_uploads() {
  mount_rc "$1" vfs/stats | jq -e '(.diskCache.uploadsInProgress // 0) + (.diskCache.uploadsQueued // 0)'
}
