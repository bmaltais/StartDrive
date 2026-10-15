# shellcheck shell=bash
# Talking to a running mount through rclone's remote-control API, over the
# private unix socket the mount unit creates (systemd/startdrive@.service).

mount_sock() { echo "$RUN_DIR/$(remote_of "$1")/rc.sock"; }

# mount_rc <id> <rc path> [json body]: the JSON reply on stdout. Fails when the
# mount is not running or predates the socket, and gives up after
# ${RC_TIMEOUT:-8} seconds so a busy mount cannot freeze the panel.
mount_rc() {
  local id="$1" path="$2" body="${3:-}" sock
  [[ -n $body ]] || body='{}'
  sock="$(mount_sock "$id")"
  [[ -S $sock ]] || return 1
  curl -sS --fail-with-body --max-time "${RC_TIMEOUT:-8}" --unix-socket "$sock" -X POST \
    -H 'Content-Type: application/json' --data-binary "$body" "http://rc/$path"
}

# Transfers for one mounted drive, as one JSON object. This deliberately avoids
# rclone's vfs/stats: it walks every cached directory taking each one's lock,
# so behind a slow listing it blocks, and polling it piles up blocked requests.
# vfs/queue (the upload queue) and core/stats (transfers) take no directory lock.
drive_activity() {
  local id="$1" queue core
  queue="$(RC_TIMEOUT=3 mount_rc "$id" vfs/queue)" || return 1
  core="$(RC_TIMEOUT=3 mount_rc "$id" core/stats)" || return 1
  # The replies hold the names of your cloud files, so they go in on stdin: an
  # argument would show up in `ps` for every other user on the machine.
  { printf '%s\n' "$queue"; printf '%s\n' "$core"; } | jq -sc --arg id "$id" '
    .[0] as $queue | .[1] as $core
    | ($queue.queue // []) as $q
    | {
        id: $id,
        uploading: ([$q[] | select(.uploading)] | length),
        queued: ([$q[] | select(.uploading | not)] | length),
        errored: ([$q[] | select((.tries // 0) >= 3)] | length),
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
    is_mounted "$id" || continue
    out+=("$(drive_activity "$id" 2>/dev/null)") || true
  done
  printf '%s\n' "${out[@]}" | jq -sc '[.[] | select(. != null)]'
}

# Files still on their way to the cloud: uploading plus queued. Fails when the
# count cannot be read, so callers can refuse a destructive step.
pending_uploads() {
  mount_rc "$1" vfs/queue | jq -e '(.queue // []) | length'
}
