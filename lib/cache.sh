# shellcheck shell=bash
# The VFS cache: rclone keeps plaintext copies of recently used files (and the
# data of uploads not yet sent) under ~/.cache/rclone/vfs/<remote>.

cache_dirs() { # <id>
  local remote; remote="$(remote_of "$1")"
  echo "$CACHE_ROOT/vfs/$remote"
  echo "$CACHE_ROOT/vfsMeta/$remote"
}

cache_bytes() { # <id>: size on disk, mounted or not
  local dir total=0 size
  while read -r dir; do
    [[ -d $dir ]] || continue
    size="$(du -sb -- "$dir" 2>/dev/null | cut -f1)" || size=0
    total=$((total + ${size:-0}))
  done < <(cache_dirs "$1")
  echo "$total"
}

# Forget cached directory listings so the next access asks the cloud again.
cmd_refresh_listing() {
  mount_rc "$1" vfs/forget >/dev/null || fail "$(name_of "$1") is not mounted"
  echo "Directory listing refreshed."
}

# Delete the cache. A mounted drive is stopped for the purge and mounted again;
# files that have not finished uploading exist only in the cache, so the purge
# is refused while any are pending.
cmd_clear_cache() {
  local id="$1" unit dir was_active=0 pending
  unit="$(unit_of "$id")"
  if systemctl --user is-active --quiet "$unit"; then
    was_active=1
    pending="$(pending_uploads "$id")" ||
      fail "cannot tell whether uploads are pending; unmount and mount $(name_of "$id") again first"
    ((pending == 0)) || fail "$pending file(s) are still uploading; try again once they are done"
    systemctl --user stop "$unit"
  fi
  while read -r dir; do
    [[ $dir == "$CACHE_ROOT"/vfs/?* || $dir == "$CACHE_ROOT"/vfsMeta/?* ]] || fail "refusing to delete $dir"
    rm -rf -- "$dir"
  done < <(cache_dirs "$id")
  ((was_active)) && systemctl --user start "$unit"
  echo "Cache cleared."
}
