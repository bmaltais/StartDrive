# shellcheck shell=bash
# Machine setup: rclone, the keyring-held config key, the encrypted config and
# the systemd mount unit.

have_rclone() { command -v rclone >/dev/null; }
have_secret() { secret-tool lookup "${SECRET_ATTRS[@]}" >/dev/null 2>&1; }
config_encrypted() { have_rclone && [[ -f $RCLONE_CONFIG ]] && rclone config encryption check >/dev/null 2>&1; }

list_remotes() {
  have_rclone || return 0
  rclone listremotes 2>/dev/null | sed 's/:$//' || true
}
is_configured() { list_remotes | grep -qx "$(remote_of "$1")"; }

ensure_rclone() {
  have_rclone && return
  echo "Installing rclone..."
  omarchy-pkg-add rclone fuse3
}

ensure_secret() {
  have_secret && return
  echo "Creating a config encryption key in your login keyring..."
  # 256 random bits; never printed, never stored outside the keyring.
  head -c 32 /dev/urandom | base64 -w0 |
    secret-tool store --label="StartDrive: rclone config password" "${SECRET_ATTRS[@]}"
  have_secret || fail "could not store the key in the keyring (is gnome-keyring unlocked?)"
}

ensure_encrypted() {
  create_private_file "$RCLONE_CONFIG"
  config_encrypted && return
  echo "Encrypting the rclone config with the keyring key..."
  # With --password-command set, `encryption set` takes the new password from it.
  rclone config encryption set
  config_encrypted || fail "config encryption failed"
}

# Install the mount unit and the shell environment file, only touching them
# when their content changed so a plugin update is picked up on the next mount.
ensure_unit() {
  local src="$SD_HOME/systemd/${UNIT_TEMPLATE}.service" dest="$UNIT_DIR/${UNIT_TEMPLATE}.service"
  local env_line changed=0
  private_dir "$MOUNT_ROOT" "$CONFIG_DIR"
  [[ -d $MOUNT_ROOT && ! -L $MOUNT_ROOT ]] || fail "$MOUNT_ROOT is not a directory"

  if ! cmp -s "$src" "$dest" 2>/dev/null; then
    write_file "$dest" 0644 <"$src"
    changed=1
  fi
  # So plain `rclone` in your own terminal can read the encrypted config too.
  env_line="RCLONE_PASSWORD_COMMAND=\"$RCLONE_PASSWORD_COMMAND\""
  if [[ $(cat "$ENV_FILE" 2>/dev/null) != "$env_line" ]]; then
    printf '%s\n' "$env_line" | write_file "$ENV_FILE" 0644
  fi
  ((changed)) && systemctl --user daemon-reload
  return 0
}

has_legacy_units() {
  [[ -f $UNIT_DIR/${LEGACY_UNIT_TEMPLATE}.service ]]
}

# Move mounts from the pre-rebrand unit (omarchy-cloud-drive@) to ours,
# keeping each drive's mounted and login-mount state.
migrate_legacy() {
  has_legacy_units || return 0
  local id remote old enabled=() running=()
  ensure_unit
  for id in $(provider_ids); do
    remote="$(remote_of "$id")"
    old="${LEGACY_UNIT_TEMPLATE}${remote}.service"
    systemctl --user is-enabled --quiet "$old" 2>/dev/null && enabled+=("$id")
    systemctl --user is-active --quiet "$old" 2>/dev/null && running+=("$id")
    systemctl --user disable --now "$old" 2>/dev/null || true
  done
  rm -f "$UNIT_DIR/${LEGACY_UNIT_TEMPLATE}.service" "$LEGACY_ENV_FILE"
  systemctl --user daemon-reload
  for id in "${enabled[@]}"; do systemctl --user enable "$(unit_of "$id")" 2>/dev/null || true; done
  for id in "${running[@]}"; do systemctl --user start "$(unit_of "$id")" || true; done
  echo "Moved ${#running[@]} mount(s) to the StartDrive unit."
}

cmd_setup() {
  ensure_rclone
  ensure_secret
  ensure_encrypted
  ensure_unit
  migrate_legacy
  echo "StartDrive is ready. Folders appear under $MOUNT_ROOT"
}

# Remove everything StartDrive installed, leaving your files and rclone
# remotes alone. `--purge` also deletes the config key from the keyring, which
# makes the encrypted rclone config unreadable, so it asks first.
cmd_uninstall() {
  local purge="${1:-}" id
  for id in $(provider_ids); do
    systemctl --user disable --now "$(unit_of "$id")" 2>/dev/null || true
    rm -f -- "$(settings_file "$id")"
  done
  rm -f -- "$UNIT_DIR/${UNIT_TEMPLATE}.service" "$ENV_FILE"
  rmdir -- "$CONFIG_DIR" 2>/dev/null || true
  systemctl --user daemon-reload
  echo "Mount units and settings removed. Forget the drives first if you also want their accounts removed."
  if [[ $purge == --purge ]]; then
    gum confirm "Delete the config key from the keyring? The rclone config becomes unreadable." || exit 130
    secret-tool clear "${SECRET_ATTRS[@]}"
    echo "Keyring item removed."
  fi
}
