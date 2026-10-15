#!/usr/bin/env bash
# lib/config.sh finds the app and loads its devkit.conf, with defaults for what it leaves out, and says what is wrong when it is not usable.
source "$(dirname "$0")/lib.sh"
# shellcheck source=../lib/config.sh
source "$KIT/lib/config.sh"

app=$WORK/MyApp; mkdir -p "$app"
loads() { ( export DEVKIT_APP_ROOT=$app; devkit_load_config >/dev/null 2>&1 ); }

check "no devkit.conf is an error" bash -c "! (DEVKIT_APP_ROOT='$app'; source '$KIT/lib/config.sh'; devkit_load_config) 2>/dev/null"
printf 'TOUR_TITLE=x\n' >"$app/devkit.conf"
check "a conf without TOUR_PLUGIN_ID is an error" bash -c "! (DEVKIT_APP_ROOT='$app'; source '$KIT/lib/config.sh'; devkit_load_config) 2>/dev/null"
printf 'TOUR_PLUGIN_ID=io.example.my\nTOUR_PLUGIN_ENTRY=notjson\n' >"$app/devkit.conf"
check "a TOUR_PLUGIN_ENTRY that is not a JSON object is an error" bash -c "! (DEVKIT_APP_ROOT='$app'; source '$KIT/lib/config.sh'; devkit_load_config) 2>/dev/null"

printf 'TOUR_PLUGIN_ID=io.example.my\n' >"$app/devkit.conf"
( DEVKIT_APP_ROOT=$app; devkit_load_config && {
    [[ $REPO == "$app" ]] && [[ $DEVKIT_NAME == myapp ]] && [[ $TOUR_TITLE == myapp ]] && [[ $TOUR_PLUGIN_WIDGET == 1 ]] \
      && [[ $TOUR_PLUGIN_ENTRY == '{}' ]] && ((${#TOUR_SANDBOX_COPY[@]} == 0)) && ((${#DEVKIT_GUARD_EXTRA[@]} == 0)); } ) 2>/dev/null
check "a minimal conf gets the defaults (name from the folder, entry {}, bar widget on)" test $? -eq 0

cat >"$app/devkit.conf" <<'CONF'
TOUR_PLUGIN_ID=io.example.my
DEVKIT_NAME=mine
TOUR_TITLE="My App"
TOUR_PLUGIN_WIDGET=0
TOUR_PLUGIN_ENTRY='{"a":1}'
DEVKIT_LAYERS=(omarchy-mine)
DEVKIT_GUARD_EXTRA=(mine-shutdown)
devkit_window_up() { :; }
CONF
( DEVKIT_APP_ROOT=$app; devkit_load_config && [[ $DEVKIT_NAME == mine && $TOUR_TITLE == "My App" && $TOUR_PLUGIN_WIDGET == 0 && $TOUR_PLUGIN_ENTRY == '{"a":1}' ]] \
    && [[ ${DEVKIT_LAYERS[0]} == omarchy-mine && ${DEVKIT_GUARD_EXTRA[0]} == mine-shutdown ]] && declare -F devkit_window_up >/dev/null ) 2>/dev/null
check "a conf's own values and hooks are loaded" test $? -eq 0
finish
