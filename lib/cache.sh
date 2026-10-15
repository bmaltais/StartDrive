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

# Delete the cache files of a drive that is not mounted. The only place the
# cache is removed, so the path check below guards every purge.
delete_cache_files() { # <id>
  local dir
  while read -r dir; do
    [[ $dir == "$CACHE_ROOT"/vfs/?* || $dir == "$CACHE_ROOT"/vfsMeta/?* ]] || fail "refusing to delete $dir"
    rm -rf -- "$dir"
  done < <(cache_dirs "$1")
}

# Delete the cache. A mounted drive is stopped for the purge and mounted again;
# the purge is refused while uploads are pending (lib/lifecycle.sh).
cmd_clear_cache() {
  with_mount_stopped "$1" delete_cache_files "$1"
  echo "Cache cleared."
}
