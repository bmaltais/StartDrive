# shellcheck shell=bash
# Connecting a drive. Every built-in drive signs in with OAuth: rclone opens your
# browser and this code never sees the password. Anything else is added with
# rclone's own questionnaire (cmd_add).

# ---- the oauth method --------------------------------------------------------

signin_oauth() { # <id>
  local id="$1" remote backend
  local -a extra=()
  remote="$(remote_of "$id")"
  backend="$(backend_of "$id")"
  case "$id" in
    google) extra=(scope=drive config_is_local=true) ;;
    onedrive) echo "You will pick which drive to use after signing in." ;;
  esac
  echo "A browser window will open for $(name_of "$id") sign-in."
  rclone config create "$remote" "$backend" "${extra[@]}"
}

# ---- the commands ------------------------------------------------------------

cmd_connect() {
  local id="$1" remote name
  remote="$(remote_of "$id")"
  name="$(name_of "$id")"
  cmd_setup
  if is_configured "$id"; then
    echo "$name is already connected."
  else
    echo
    echo "Connecting $name ..."
    [[ $(signin_of "$id") == oauth ]] || fail "$name has no sign-in of its own; add remotes with: startdrive add"
    signin_oauth "$id"
    is_configured "$id" || fail "$name was not configured"
  fi
  echo "Testing the connection..."
  rclone about "$remote:" 2>/dev/null || rclone lsd --max-depth 1 "$remote:" >/dev/null
  systemctl --user enable "$(unit_of "$id")" 2>/dev/null || true
  cmd_mount "$id"
  echo "$name is mounted at $(mount_path "$id")"
}

# Add any other rclone backend (SFTP, WebDAV, S3, Backblaze B2 ...) with rclone's
# own questionnaire. The new remote shows up in the panel as a drive on the
# next refresh, if its name is plain letters, digits, "-" or "_".
cmd_add() {
  cmd_setup
  echo "Add a remote with rclone's questionnaire: choose n) New remote, then follow the prompts."
  echo "Name it with letters, digits, - or _ and it appears in the panel."
  rclone config
}

# Give a Google drive its own OAuth client. Without one, rclone uses a Google
# project whose API quota every rclone user shares; when it runs out Google
# answers 403 rateLimitExceeded and listings stall for tens of seconds.
cmd_client_id() {
  local id="$1" remote client_id client_secret
  [[ $(backend_of "$id") == drive ]] || fail "$(name_of "$id") is not a Google Drive"
  remote="$(remote_of "$id")"
  is_configured "$id" || fail "$(name_of "$id") is not connected yet"
  cat <<'GUIDE'
Google Drive is using rclone's shared client id, so its API quota is shared with
every other rclone user and the drive can freeze when it runs out. Your own
client id fixes that. It takes about five minutes, once:

  1. Open https://console.cloud.google.com/ and create a project.
  2. APIs & Services > Library: enable the "Google Drive API".
  3. OAuth consent screen: choose External, fill in the app name and your email,
     add yourself as a test user, then Publish the app so the sign-in does not
     expire after a week.
  4. Credentials > Create credentials > OAuth client ID > "Desktop app".
  5. Copy the client ID and client secret it shows.

Full guide: https://rclone.org/drive/#making-your-own-client-id
GUIDE
  echo
  read -r -p "Client ID (empty to cancel): " client_id
  [[ -n $client_id ]] || exit 130
  read -r -s -p "Client secret: " client_secret
  echo
  [[ -n $client_secret ]] || fail "no client secret given"
  rclone config update "$remote" client_id="$client_id" client_secret="$client_secret" >/dev/null
  echo "A browser window will open to sign in again."
  rclone config reconnect "$remote:"
  systemctl --user restart "$(unit_of "$id")" 2>/dev/null || true
  echo "Done. $(name_of "$id") now uses your own client id."
}
