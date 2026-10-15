# shellcheck shell=bash
# Acting on a mount without losing data. Files that have not finished
# uploading exist only in the VFS cache, so anything that stops a mount or
# deletes its cache asks here first. Whether uploads can be read at all is part
# of the answer: if the mount does not say, assume the worst.

# with_mount_stopped <id> <command...>: run a command on a drive that is not
# mounted. A running mount is stopped first and started again afterwards; it is
# left alone, and the command not run, while uploads are pending or unknown.
with_mount_stopped() {
  local id="$1" unit pending was_active=0 status=0
  shift
  unit="$(unit_of "$id")"
  if systemctl --user is-active --quiet "$unit"; then
    was_active=1
    pending="$(pending_uploads "$id")" ||
      fail "cannot tell whether uploads are pending; unmount and mount $(name_of "$id") again first"
    ((pending == 0)) || fail "$pending file(s) are still uploading; try again once they are done"
    systemctl --user stop "$unit"
  fi
  "$@" || status=$?
  if ((was_active)); then systemctl --user start "$unit" || status=$?; fi
  return "$status"
}

# restart_mount_if_idle <id>: restart a running mount so new mount options
# apply. Returns 1 and leaves it running while uploads are pending or unknown.
restart_mount_if_idle() {
  local id="$1" pending
  if pending="$(pending_uploads "$id")" && ((pending == 0)); then
    systemctl --user restart "$(unit_of "$id")"
  else
    return 1
  fi
}
