#!/usr/bin/env bash
# Behaviour tests for bin/startdrive, run through its command line against a throwaway $HOME in demo mode (fixture drives, see
# lib/demo.sh). Nothing here touches the real home, systemd, rclone, the keyring, the network or the desktop. A test is a function
# named t_*. The input checks that fail before reaching any of those, and the rules about files still uploading, are in tests/*.test.js.
#
#   tests/cli.sh              all tests
#   tests/cli.sh mount set    only tests whose name contains one of the words
set -uo pipefail
# Run by git's pre-commit hook, git's own variables name the repository being committed. A test that makes a repository of its own would
# then add its files to that one's index, and the commit would hold nothing but a fixture (it did: a commit with one file, scripts/reload).
unset GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_COMMON_DIR

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLI="$ROOT/bin/startdrive"
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

# --- harness ------------------------------------------------------------------
PASS=0 FAIL=0 FAILED_NOW=0
OUT="" ERR="" CODE=0

fail() { printf '        %s\n' "$*"; FAILED_NOW=1; }
eq() { [[ $1 == "$2" ]] || fail "$3: expected [$2], got [$1]"; }
has() { [[ $1 == *"$2"* ]] || fail "${3:-output}: expected to contain [$2], got [$1]"; }
exists() { [[ -e $1 || -L $1 ]] || fail "expected to exist: ${1#"$HOME"/}"; }
absent() { [[ ! -e $1 && ! -L $1 ]] || fail "expected to be gone: ${1#"$HOME"/}"; }
ok() { [[ $CODE -eq 0 ]] || fail "expected success, exit $CODE: $ERR"; }
refused() { [[ $CODE -ne 0 ]] || fail "expected a failure, got success: $OUT"; has "$ERR" "$1" "error message"; }
jqv() { jq -r "$1" <<<"$OUT"; } # a value of the last command's JSON output

# cli ARGS...: run the command line in the fixture home; sets OUT ERR CODE.
cli() {
  local e="$SCRATCH/err"
  OUT=$(bash "$CLI" "$@" 2>"$e"); CODE=$?
  ERR=$(<"$e")
}

# Each test gets a home of its own, in demo mode, with the XDG variables of the real session unset.
fresh_home() {
  HOME=$(mktemp -d -p "$SCRATCH")
  export HOME STARTDRIVE_DEMO=1
  export XDG_RUNTIME_DIR=$HOME/run
  unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME STARTDRIVE_ROOT
  mkdir -p "$XDG_RUNTIME_DIR"
}

drive() { jq -c --arg id "$1" '.drives[] | select(.id == $id)' <<<"$OUT"; } # one drive of the last `state`

# --- state --------------------------------------------------------------------
t_state_lists_the_fixture_drives() {
  cli state; ok
  eq "$(jqv '[.drives[].id] | join(" ")')" "google onedrive dropbox r-Work-NAS" "ids"
  eq "$(jqv '[.drives[] | select(.configured) | .id] | join(" ")')" "google onedrive r-Work-NAS" "connected"
  eq "$(jqv '[.drives[] | select(.mounted) | .id] | join(" ")')" "google onedrive" "mounted"
  eq "$(jqv '.rclone, .encrypted, .keyring' | paste -sd' ')" "true true true" "machine"
}

t_state_carries_each_drives_settings() {
  cli state; ok
  eq "$(drive google | jq -c .settings)" '{"cacheSize":"4G","cacheAge":"72h","readOnly":false,"autostart":true,"notifications":true}' "settings"
}

t_activity_reports_the_uploading_drive() {
  cli activity; ok
  eq "$(jqv '.[0].id')" google "drive"
  eq "$(jqv '.[0].uploading + .[0].queued')" 3 "files waiting"
  eq "$(jqv '.[0].transfers | length')" 2 "transfers"
  eq "$(jqv '.[1].transfers | length')" 0 "the other drive"
}

t_about_reports_storage() {
  cli about google; ok; eq "$(jqv '.total')" 15000000000 "total"
  cli about r-Work-NAS; ok; eq "$OUT" '{}' "a backend without a total"
}

# --- mounting -----------------------------------------------------------------
t_mount_and_unmount_change_the_state() {
  cli mount r-Work-NAS; ok
  cli state; eq "$(drive r-Work-NAS | jq .mounted)" true "mounted"
  cli unmount r-Work-NAS; ok
  cli state; eq "$(drive r-Work-NAS | jq .mounted)" false "unmounted"
}

t_an_unconnected_drive_cannot_be_mounted() {
  cli mount dropbox; refused "Dropbox is not connected yet"
}

t_an_unknown_drive_is_refused() {
  cli mount nonsense; refused "unknown drive"
  cli mount "r-a b"; refused "unknown drive"
}

t_unmount_all_and_mount_all() {
  cli unmount-all; ok
  cli state; eq "$(jqv '[.drives[] | select(.mounted)] | length')" 0 "mounted after unmount-all"
  cli mount-all; ok
  cli state; eq "$(jqv '[.drives[] | select(.mounted) | .id] | join(" ")')" "google onedrive r-Work-NAS" "mounted after mount-all"
}

# --- settings -----------------------------------------------------------------
t_set_saves_a_mount_setting() {
  cli set onedrive cache-size 10G; ok
  cli state; eq "$(drive onedrive | jq -r .settings.cacheSize)" 10G "cache size"
  has "$(<"$HOME/.config/startdrive/OneDrive.env")" "RCLONE_VFS_CACHE_MAX_SIZE=10G" "env file"
}

t_set_handles_the_flags() {
  cli set onedrive autostart false; ok
  cli set onedrive notifications false; ok
  cli set onedrive read-only true; ok
  cli state
  eq "$(drive onedrive | jq -c '[.settings.autostart, .settings.notifications, .settings.readOnly]')" "[false,false,true]" "flags"
}

t_set_refuses_a_value_outside_the_allow_list() {
  cli set onedrive cache-size 99X; refused "invalid setting"
  cli set onedrive cache-age "7d"; refused "invalid setting"
  cli set onedrive colour red; refused "invalid setting"
}

t_clear_cache_is_refused_while_files_upload() {
  cli clear-cache google; refused "still uploading"
  cli clear-cache onedrive; ok; has "$OUT" "Cache cleared" "output"
}

t_refresh_listing_answers() {
  cli refresh-listing onedrive; ok; has "$OUT" "refreshed" "output"
}

# --- demo mode keeps its hands off the machine --------------------------------
t_demo_mode_never_runs_the_real_tools() {
  local bin="$SCRATCH/shim" tool
  mkdir -p "$bin"
  for tool in systemctl rclone secret-tool fusermount3 hyprctl xdg-open uwsm-app omarchy-pkg-add gum curl; do
    printf '#!/bin/sh\necho "%s $*" >>"%s/ran"\n' "$tool" "$SCRATCH"  >"$bin/$tool"
    chmod +x "$bin/$tool"
  done
  rm -f "$SCRATCH/ran"
  PATH="$bin:$PATH" cli mount r-Work-NAS; ok
  PATH="$bin:$PATH" cli unmount r-Work-NAS; ok
  PATH="$bin:$PATH" cli set google autostart false; ok
  PATH="$bin:$PATH" cli open google; ok
  PATH="$bin:$PATH" cli launch disconnect google; ok
  PATH="$bin:$PATH" cli disconnect onedrive; ok
  PATH="$bin:$PATH" cli uninstall --purge; [[ $CODE -ne 0 ]] || fail "uninstall must not run in demo mode"
  [[ ! -e $SCRATCH/ran ]] || fail "a real tool ran: $(<"$SCRATCH/ran")"
}

t_demo_mode_is_also_switched_on_by_the_marker_file() {
  unset STARTDRIVE_DEMO
  mkdir -p "$HOME/.config/startdrive/demo"
  : >"$HOME/.config/startdrive/demo/ENABLED"
  cli state; ok
  eq "$(jqv '[.drives[].id] | join(" ")')" "google onedrive dropbox r-Work-NAS" "ids"
}

# --- integration: launcher entry, command-line link, bar icon -----------------
t_integration_reports_a_fresh_home() {
  cli integration; ok
  eq "$(jqv '.launcher')" false "launcher"
  eq "$(jqv '.cli.state')" none "cli"
  eq "$(jqv '.done')" false "done"
  eq "$(jqv '[.rememberSize, .rememberPosition] | join(" ")')" "true true" "remember"
  eq "$(jqv '[.defaults.launcher, .defaults.cli, .defaults.barIcon] | join(" ")')" "true true true" "defaults"
}

t_setup_adds_and_removes_the_launcher_entry() {
  local d="$HOME/.local/share/applications/startdrive.desktop" i="$HOME/.local/share/icons/hicolor/scalable/apps/startdrive.svg"
  cli setup --launcher true; ok
  exists "$d"; exists "$i"
  has "$(<"$d")" "Name=StartDrive" "entry"
  has "$(<"$d")" "$ROOT/bin/startdrive\" ui" "entry runs the manager"
  has "$(<"$d")" "Icon=startdrive" "entry"
  cli integration; eq "$(jqv '.launcher')" true "launcher"
  cli setup --launcher false; ok
  absent "$d"; absent "$i"
}

t_setup_links_the_command_line() {
  cli setup --cli true; ok
  eq "$(readlink "$HOME/.local/bin/startdrive")" "$ROOT/bin/startdrive" "link"
  cli integration; eq "$(jqv '.cli.state')" ours "state"
  cli setup --cli true; ok
  cli setup --cli false; ok
  absent "$HOME/.local/bin/startdrive"
}

t_setup_leaves_a_foreign_file_at_the_link_alone() {
  mkdir -p "$HOME/.local/bin"; echo mine >"$HOME/.local/bin/startdrive"
  cli setup --cli true --json; [[ $CODE -ne 0 ]] || fail "expected a failure"
  eq "$(jqv '.ok')" false "ok"; eq "$(jqv '.field')" cli "field"; has "$(jqv '.error')" "already exists" "error"
  eq "$(<"$HOME/.local/bin/startdrive")" mine "the file"
  cli integration; eq "$(jqv '.cli.state')" other "state"
  cli setup --cli false; ok
  eq "$(<"$HOME/.local/bin/startdrive")" mine "still there after switching off"
}

t_setup_answers_the_first_run_offer() {
  cli integration; eq "$(jqv '.done')" false "before"
  cli setup --done; ok
  cli integration; eq "$(jqv '.done')" true "after"
}

t_a_change_counts_as_answering_the_first_run_offer() {
  cli setup --remember-size false; ok
  cli integration; eq "$(jqv '.done')" true "after a change"
}

t_the_launcher_entry_counts_as_answered() {
  cli setup --launcher true; ok
  rm -f "$HOME/.config/startdrive/config"
  cli integration; eq "$(jqv '.done')" true "launcher on"
}

t_setup_rejects_bad_input() {
  cli setup --nonsense; refused "unknown option"
  cli setup --launcher maybe; refused "takes true or false"
  cli setup --bar-icon; refused "takes true or false"
  cli setup --bogus --json; [[ $CODE -ne 0 ]] || fail "expected a failure"
  eq "$(jqv '.ok')" false "json"
}

t_setup_json_reports_success() {
  cli setup --launcher true --json; ok; eq "$(jqv '.ok')" true "ok"
}

# The jq programs behind the bar icon switch, on a sample layout (the real ones run after Omarchy's own NORMALIZE and are applied by
# omarchy-shell-config, which would reload the real shell, so they are not run here).
t_the_bar_icon_programs_keep_the_service_enabled() {
  SD_HOME=$ROOT
  # shellcheck source=/dev/null
  source "$ROOT/lib/common.sh"; source "$ROOT/lib/prefs.sh"
  local base='{"bar":{"layout":{"right":[{"id":"x"},{"id":"io.github.bmaltais.startdrive"}]}}}' stub='.plugins = (.plugins // [])' off on
  off=$(jq -c --arg id "$PLUGIN_ID" "$stub | $BAR_REMOVE_JQ" <<<"$base")
  eq "$(jq -c '.bar.layout.right' <<<"$off")" '[{"id":"x"}]' "layout after switching off"
  eq "$(jq -c '.plugins' <<<"$off")" '[{"id":"io.github.bmaltais.startdrive"}]' "still enabled as a plugin after switching off"
  on=$(jq -c --arg id "$PLUGIN_ID" "$stub | $BAR_ADD_JQ" <<<"$off")
  eq "$(jq -c '.bar.layout.right | map(.id)' <<<"$on")" '["x","io.github.bmaltais.startdrive"]' "layout after switching on"
  eq "$(jq -c '.plugins | length' <<<"$on")" 1 "the plugin is listed once"
  eq "$(jq -c '.plugins | length' < <(jq -c --arg id "$PLUGIN_ID" "$stub | $BAR_REMOVE_JQ" <<<"$on"))" 1 "and still once after another round"
}

# The same programs after Omarchy's real NORMALIZE, when Omarchy is installed here (read only: nothing is committed).
t_the_bar_icon_programs_run_after_omarchys_normalize() {
  local lib=${OMARCHY_PATH:-/usr/share/omarchy}/bin/omarchy-shell-config
  [[ -f $lib ]] || { echo "        (skipped: Omarchy is not installed here)"; return 0; }
  SD_HOME=$ROOT
  # shellcheck source=/dev/null
  source "$ROOT/lib/common.sh"; source "$ROOT/lib/prefs.sh"
  OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy} source "$lib"
  local out
  out=$(jq -c --arg id "$PLUGIN_ID" "$NORMALIZE | $BAR_ADD_JQ" <<<'{}'); eq "$(jq -c '.bar.layout.right' <<<"$out")" '[{"id":"io.github.bmaltais.startdrive"}]' "added to an empty config"
  eq "$(jq -c '.plugins' <<<"$out")" '[{"id":"io.github.bmaltais.startdrive"}]' "listed as a plugin"
  out=$(jq -c --arg id "$PLUGIN_ID" "$NORMALIZE | $BAR_REMOVE_JQ" <<<"$out"); eq "$(jq -c '.bar.layout.right' <<<"$out")" '[]' "removed"
  eq "$(jq -c '.plugins | length' <<<"$out")" 1 "still enabled"
}

# --- scripts/reload ------------------------------------------------------------
# On a clean working tree it once exited silently (a `&&` that returned 1 under set -e), which only showed once everything was committed.
t_reload_check_reports_on_a_clean_git_tree() {
  local repo=$SCRATCH/reload-repo
  mkdir -p "$repo/scripts" "$HOME/.config/omarchy/plugins/io.github.bmaltais.startdrive"
  cp "$ROOT/scripts/reload" "$repo/scripts/reload"
  git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t add -A
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m init
  OUT=$(bash "$repo/scripts/reload" --check 2>"$SCRATCH/err"); CODE=$?
  has "$OUT" "reload check:" "it says something"
  has "$OUT" "main@" "it names the branch and commit"
  [[ $OUT != *"+local"* ]] || fail "a clean tree is not +local: $OUT"
}

# --- window memory -----------------------------------------------------------
t_window_starts_at_zero_and_remembers_what_it_is_given() {
  cli window; ok; eq "$OUT" '{"w":0,"h":0,"x":0,"y":0,"setup":{"w":0,"h":0,"x":0,"y":0}}' "fresh"
  cli window --size 700x600 --offset 10,-5 --setup-size 800x500 --setup-offset -20,30; ok
  eq "$OUT" '{"w":700,"h":600,"x":10,"y":-5,"setup":{"w":800,"h":500,"x":-20,"y":30}}' "saved"
}

t_window_reset_forgets_the_manager_but_not_the_settings_window() {
  cli window --size 700x600 --setup-size 800x500 >/dev/null
  cli window --reset; ok
  eq "$(jqv '[.w, .h, .setup.w, .setup.h] | join(" ")')" "0 0 800 500" "after reset"
  cli window --reset-setup; ok
  eq "$(jqv '.setup.w')" 0 "after reset-setup"
}

t_switching_off_remembering_forgets_and_hides_what_was_saved() {
  cli window --size 700x600 --offset 10,-5 >/dev/null
  cli setup --remember-position false; ok
  cli window; eq "$(jqv '[.w, .h, .x, .y] | join(" ")')" "700 600 0 0" "position forgotten, size kept"
  cli setup --remember-size false; ok
  cli window; eq "$(jqv '[.w, .h] | join(" ")')" "0 0" "size forgotten"
  cli integration; eq "$(jqv '[.rememberSize, .rememberPosition] | join(" ")')" "false false" "switches"
}

t_window_rejects_bad_input() {
  cli window --size big; refused "WIDTHxHEIGHT"
  cli window --offset 1,; refused "X,Y"
  cli window --bogus; refused "unknown option"
}

# --- project rules (scripts/lint-rules.sh) ---------------------------------------
# rules DIR: run the rules against a tree; sets OUT ERR CODE.
rules() {
  OUT=$(LINT_RULES_ROOT=$1 bash "$ROOT/scripts/lint-rules.sh" 2>"$SCRATCH/err"); CODE=$?
  ERR=$(<"$SCRATCH/err")
}

t_rules_pass_on_this_repo() {
  rules "$ROOT"; ok; has "$OUT" "lint-rules: ok" "output"
}

t_rules_catch_a_detached_launch_that_keeps_the_pipe_open() {
  local d=$SCRATCH/tree1; mkdir -p "$d/scripts"
  printf '%s\n' '#!/usr/bin/env bash' 'setsid -f env X=1 bash -c "sleep 9" _ "$a"' >"$d/scripts/dev"
  rules "$d"; [[ $CODE -ne 0 ]] || fail "expected a failure: $OUT"
  has "$OUT" "scripts/dev: setsid -f without 2>&1" "message"
}

t_rules_accept_a_detached_launch_whose_redirect_is_on_a_continuation_line() {
  local d=$SCRATCH/tree2; mkdir -p "$d/scripts/nested"
  cat >"$d/scripts/nested/session.sh" <<'SH'
#!/usr/bin/env bash
setsid -f env X=1 \
  some-command >"$log" 2>&1
SH
  rules "$d"; ok
}

t_rules_catch_a_tour_that_fingerprints_a_cloud_mount() {
  local d=$SCRATCH/tree3; mkdir -p "$d/scripts/tours"
  printf '%s\n' 'TOUR_REAL_UNCHANGED=(.config/startdrive Cloud)' >"$d/scripts/tours/bad.sh"
  rules "$d"; [[ $CODE -ne 0 ]] || fail "expected a failure: $OUT"
  has "$OUT" "names a cloud mount" "message"
  printf '%s\n' 'TOUR_REAL_UNCHANGED=(.config/startdrive .local/bin/startdrive)' >"$d/scripts/tours/bad.sh"
  rules "$d"; ok
}

# --- runner -------------------------------------------------------------------
want=("$@")
selected() {
  local w; (( ${#want[@]} )) || return 0
  for w in "${want[@]}"; do [[ $1 == *"$w"* ]] && return 0; done
  return 1
}

while read -r t; do
  selected "$t" || continue
  FAILED_NOW=0
  if ( fresh_home; "$t"; exit $FAILED_NOW ) >"$SCRATCH/test.out" 2>&1; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n' "${t#t_}"
    sed 's/^/        /' "$SCRATCH/test.out"
  fi
done < <(declare -F | awk '{print $3}' | grep '^t_')

printf 'tests/cli.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
