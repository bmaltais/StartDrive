# shellcheck shell=bash
# Connecting a drive. Google and OneDrive sign in with OAuth in your browser;
# this code never sees those passwords. iCloud has no OAuth, so rclone needs
# the Apple ID password once, plus a 2FA code.
#
# Secrets must never be visible in argv (/proc/*/cmdline is world-readable)
# and rclone's CLI only takes remote parameters there, so the iCloud password
# goes through rclone's rc API on a private unix socket instead: the request
# body is built by jq from stdin and streamed to curl from stdin, so the
# password lives only in this shell's memory and in rclone's. The socket is in
# a 0700 tmpfs directory for the length of the sign-in only.

SIGNIN_DIR=""
SIGNIN_PID=""

signin_rc_start() {
  local run="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" i
  SIGNIN_DIR="$(umask 077 && mktemp -d "$run/startdrive-signin.XXXXXX")" || fail "cannot create a private socket directory"
  (umask 077 && exec rclone rcd --rc-addr "unix://$SIGNIN_DIR/rc.sock" --rc-no-auth --rc-serve=false -q 2>/dev/null) &
  SIGNIN_PID=$!
  for ((i = 0; i < 50; i++)); do
    [[ -S $SIGNIN_DIR/rc.sock ]] && return 0
    sleep 0.1
  done
  signin_rc_stop
  fail "rclone rc did not start"
}

signin_rc_stop() {
  if [[ -n $SIGNIN_PID ]]; then
    kill "$SIGNIN_PID" 2>/dev/null || true
    wait "$SIGNIN_PID" 2>/dev/null || true
    SIGNIN_PID=""
  fi
  if [[ -n $SIGNIN_DIR ]]; then
    rm -rf -- "$SIGNIN_DIR"
    SIGNIN_DIR=""
  fi
  return 0
}

signin_rc_call() { # <path>: JSON body on stdin, JSON reply on stdout
  curl -s --fail-with-body --unix-socket "$SIGNIN_DIR/rc.sock" -X POST \
    -H 'Content-Type: application/json' --data-binary @- "http://rc/$1"
}

# Create the iCloud remote with the password in the request body, then answer
# rclone's follow-up questions (the 2FA code).
signin_icloud() { # <remote> <apple id> <password>
  local remote="$1" reply state opt_name opt_help answer err
  signin_rc_start
  trap signin_rc_stop EXIT
  reply="$(printf '%s\n%s\n' "$2" "$3" | jq -Rn --arg name "$remote" \
    '[inputs] | {name: $name, type: "iclouddrive",
      parameters: {apple_id: .[0], password: .[1]},
      opt: {obscure: true, nonInteractive: true}}' | signin_rc_call config/create)" || {
    echo "iCloud sign-in failed: $(jq -r '.error // "unknown error"' <<<"$reply")" >&2
    return 1
  }
  while :; do
    err="$(jq -r '.Error // ""' <<<"$reply")"
    if [[ -n $err ]]; then
      echo "iCloud sign-in failed: $err" >&2
      return 1
    fi
    state="$(jq -r '.State // ""' <<<"$reply")"
    [[ -n $state ]] || break
    opt_name="$(jq -r '.Option.Name // ""' <<<"$reply")"
    opt_help="$(jq -r '.Option.Help // ""' <<<"$reply")"
    [[ -n $opt_help ]] && echo "$opt_help"
    if [[ $opt_name == *2fa* || $opt_name == *code* ]]; then
      answer="$(gum input --placeholder "2FA code")"
    else
      answer="$(gum input --placeholder "${opt_name:-answer}")"
    fi
    reply="$(printf '%s\n%s\n' "$state" "$answer" | jq -Rn --arg name "$remote" \
      '[inputs] | {name: $name, opt: {continue: true, nonInteractive: true, state: .[0], result: .[1]}}' |
      signin_rc_call config/update)" || {
      echo "iCloud sign-in failed: $(jq -r '.error // "unknown error"' <<<"$reply")" >&2
      return 1
    }
  done
}

connect_icloud() { # <remote>
  local remote="$1" apple_id pw
  echo "iCloud has no OAuth: rclone signs in with your Apple ID and a 2FA code."
  echo "Tip: use an app-specific password from https://account.apple.com/account/manage"
  echo "Advanced Data Protection must be OFF for this account (an Apple limitation)."
  apple_id="$(gum input --placeholder "Apple ID (email)")"
  [[ -n $apple_id ]] || fail "no Apple ID given"
  pw="$(gum input --password --placeholder "Password")"
  [[ -n $pw ]] || fail "no password given"
  if ! signin_icloud "$remote" "$apple_id" "$pw"; then
    unset pw
    signin_rc_stop
    rclone config delete "$remote" 2>/dev/null || true
    fail "could not sign in to iCloud"
  fi
  unset pw
  signin_rc_stop
  trap - EXIT
}

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
    case "$id" in
      google)
        echo "A browser window will open for Google sign-in."
        rclone config create "$remote" drive scope=drive config_is_local=true
        ;;
      onedrive)
        echo "A browser window will open for Microsoft sign-in, then pick your drive."
        rclone config create "$remote" onedrive
        ;;
      icloud) connect_icloud "$remote" ;;
    esac
    is_configured "$id" || fail "$name was not configured"
  fi
  echo "Testing the connection..."
  rclone about "$remote:" 2>/dev/null || rclone lsd --max-depth 1 "$remote:" >/dev/null
  systemctl --user enable "$(unit_of "$id")" 2>/dev/null || true
  cmd_mount "$id"
  echo "$name is mounted at $(mount_path "$id")"
}
