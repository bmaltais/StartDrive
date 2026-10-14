# shellcheck shell=bash
# shellcheck disable=SC2034  # constants are used by the other modules
# Shared constants and small helpers. Sourced by bin/startdrive.

readonly MOUNT_ROOT="${STARTDRIVE_ROOT:-$HOME/Cloud}"
readonly CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly CONFIG_DIR="$CONFIG_HOME/startdrive"
readonly UNIT_DIR="$CONFIG_HOME/systemd/user"
readonly ENV_FILE="$CONFIG_HOME/environment.d/60-startdrive.conf"
readonly CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/rclone"
readonly RUN_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/startdrive"

readonly UNIT_TEMPLATE="startdrive@"
# Names used before the rebrand; setup migrates them (lib/system.sh).
readonly LEGACY_UNIT_TEMPLATE="omarchy-cloud-drive@"
readonly LEGACY_ENV_FILE="$CONFIG_HOME/environment.d/60-omarchy-cloud-drives.conf"

# The keyring item is deliberately unchanged by the rebrand: it holds the key
# of the existing, encrypted rclone config.
readonly -a SECRET_ATTRS=(service omarchy-cloud-drives key config-password)
export RCLONE_PASSWORD_COMMAND="secret-tool lookup ${SECRET_ATTRS[*]}"
export RCLONE_CONFIG="${RCLONE_CONFIG:-$CONFIG_HOME/rclone/rclone.conf}"

# id|rclone remote (also the folder under ~/Cloud)|backend|display name|glyph
readonly -a PROVIDERS=(
  "google|GoogleDrive|drive|Google Drive|󰊶"
  "onedrive|OneDrive|onedrive|OneDrive|󰏊"
  "icloud|iCloudDrive|iclouddrive|iCloud Drive|󰀸"
)

fail() {
  echo "startdrive: $*" >&2
  exit 1
}

provider_ids() {
  local row
  for row in "${PROVIDERS[@]}"; do echo "${row%%|*}"; done
}

# provider_field <id> <column 2-5>
provider_field() {
  local row
  for row in "${PROVIDERS[@]}"; do
    if [[ ${row%%|*} == "$1" ]]; then
      cut -d'|' -f"$2" <<<"$row"
      return
    fi
  done
  fail "unknown drive '$1' (use: $(provider_ids | paste -sd' '))"
}
remote_of() { provider_field "$1" 2; }
backend_of() { provider_field "$1" 3; }
name_of() { provider_field "$1" 4; }
glyph_of() { provider_field "$1" 5; }

unit_of() { echo "${UNIT_TEMPLATE}$(remote_of "$1").service"; }
mount_path() { echo "$MOUNT_ROOT/$(remote_of "$1")"; }

# private_dir <dir>...: create directories readable only by this user.
private_dir() {
  local dir
  for dir in "$@"; do
    (umask 077 && mkdir -p -- "$dir")
  done
}

# write_file <dest> <mode>: content on stdin. Written to a securely created
# temporary file beside the destination and renamed into place. rename(2) is
# atomic and never follows symlinks, so a planted link at the destination is
# replaced rather than written through, and there is no check/open race.
write_file() {
  local dest="$1" mode="$2" dir tmp
  dir="$(dirname "$dest")"
  private_dir "$dir"
  tmp="$(mktemp "$dir/.$(basename "$dest").XXXXXX")" || fail "cannot create a temporary file in $dir"
  if ! cat >"$tmp" || ! chmod "$mode" "$tmp" || ! mv -T -f "$tmp" "$dest"; then
    rm -f "$tmp"
    fail "cannot write $dest"
  fi
}

# create_private_file <path>: create an empty 0600 file only if nothing exists
# there. link(2) fails on any existing entry, symlinks included, so nothing
# else can be clobbered or written through.
create_private_file() {
  local dest="$1" dir tmp
  dir="$(dirname "$dest")"
  private_dir "$dir"
  tmp="$(mktemp "$dir/.$(basename "$dest").XXXXXX")" || fail "cannot create a temporary file in $dir"
  chmod 0600 "$tmp"
  ln "$tmp" "$dest" 2>/dev/null || true
  rm -f "$tmp"
  [[ -f $dest && ! -L $dest ]] || fail "$dest exists but is not a regular file"
}
