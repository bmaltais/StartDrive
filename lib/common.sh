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

# id|rclone remote (also the folder under ~/Cloud)|backend|display name|glyph|sign-in
# The last column names how connecting works (lib/signin.sh): "oauth" opens
# your browser.
readonly -a PROVIDERS=(
  "google|GoogleDrive|drive|Google Drive|󰊶|oauth"
  "onedrive|OneDrive|onedrive|OneDrive|󰏊|oauth"
  "dropbox|Dropbox|dropbox|Dropbox|󰇣|oauth"
)

# Remotes you added yourself (with `startdrive add`) become drives too, under
# the id "r-<remote>". Only plain names are taken, since a name ends up in a
# unit name and a folder name; anything else in your rclone config is ignored.
readonly CUSTOM_PREFIX="r-"
readonly CUSTOM_GLYPH="󰅟"
readonly CUSTOM_REMOTE_RE='^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$'

fail() {
  echo "startdrive: $*" >&2
  exit 1
}

builtin_ids() {
  local row
  for row in "${PROVIDERS[@]}"; do echo "${row%%|*}"; done
}

is_builtin_remote() { # <remote name>
  local row
  for row in "${PROVIDERS[@]}"; do
    [[ $(cut -d'|' -f2 <<<"$row") == "$1" ]] && return 0
  done
  return 1
}

# One `rclone config dump` per run: the remote name -> backend type, as JSON.
CUSTOM_DUMP=""
custom_dump() {
  if [[ -z $CUSTOM_DUMP ]]; then
    if have_rclone; then
      CUSTOM_DUMP="$(rclone config dump 2>/dev/null | jq -c 'map_values(.type)' 2>/dev/null)" || CUSTOM_DUMP=""
    fi
    [[ -n $CUSTOM_DUMP ]] || CUSTOM_DUMP='{}'
  fi
  echo "$CUSTOM_DUMP"
}

custom_remotes() {
  custom_dump | jq -r 'keys[]' | while read -r remote; do
    [[ $remote =~ $CUSTOM_REMOTE_RE ]] && ! is_builtin_remote "$remote" && echo "$remote"
  done
}

provider_ids() {
  builtin_ids
  local remote
  while read -r remote; do [[ -n $remote ]] && echo "${CUSTOM_PREFIX}${remote}"; done < <(custom_remotes)
}

is_custom() { [[ $1 == "${CUSTOM_PREFIX}"?* ]]; }

# provider_field <id> <column 2-6>
provider_field() {
  local row remote type
  if is_custom "$1"; then
    remote="${1#"$CUSTOM_PREFIX"}"
    custom_remotes | grep -qx "$remote" || fail "unknown drive '$1'"
    type="$(custom_dump | jq -r --arg r "$remote" '.[$r] // "remote"')"
    case "$2" in
      2) echo "$remote" ;;
      3) echo "$type" ;;
      4) echo "$remote ($type)" ;;
      5) echo "$CUSTOM_GLYPH" ;;
      6) echo none ;;
    esac
    return
  fi
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
signin_of() { provider_field "$1" 6; }

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
