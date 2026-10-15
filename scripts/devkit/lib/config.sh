# shellcheck shell=bash
# Finds the app a devkit command is run for and loads its devkit.conf (docs/configuration.md). Sourced by bin/dev and bin/tour.
#
# The app is the checkout the command is run in, or the one DEVKIT_APP_ROOT names (the app's own wrapper scripts set it). Its devkit.conf
# is plain bash: variables and, if it wants, functions (hooks). Defaults are set first, so a conf only says what differs.
#
# Sets: REPO (the app's root), DEVKIT (this kit's root), DEVKIT_NAME, and every variable the conf sets.

DEVKIT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

devkit_load_config() {
  REPO=${DEVKIT_APP_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
  DEVKIT_CONF=${DEVKIT_CONF:-$REPO/devkit.conf}
  [[ -f $DEVKIT_CONF ]] || { echo "devkit: no devkit.conf in $REPO (see $DEVKIT/docs/configuration.md; run from the app's checkout or set DEVKIT_APP_ROOT)" >&2; return 1; }
  # Defaults: what an app that sets nothing gets.
  TOUR_PLUGIN_ID=""
  TOUR_PLUGIN_ENTRY='{}'
  TOUR_PLUGIN_WIDGET=1
  TOUR_SANDBOX_COPY=()
  TOUR_SANDBOX_LINK=()
  TOUR_REAL_UNCHANGED=()
  DEVKIT_ENV=()
  DEVKIT_GUARD_EXTRA=()
  DEVKIT_LAYERS=()
  DEVKIT_NOISE=""
  DEVKIT_USAGE=""
  DEVKIT_NAME=""
  TOUR_TITLE=""
  # shellcheck disable=SC1090
  source "$DEVKIT_CONF"
  [[ -n $TOUR_PLUGIN_ID ]] || { echo "devkit: $DEVKIT_CONF must set TOUR_PLUGIN_ID (the plugin's id)" >&2; return 1; }
  : "${DEVKIT_NAME:=$(basename "$REPO" | tr '[:upper:]' '[:lower:]')}"
  : "${TOUR_TITLE:=$DEVKIT_NAME}"
  jq -e 'type == "object"' <<<"$TOUR_PLUGIN_ENTRY" >/dev/null 2>&1 || { echo "devkit: TOUR_PLUGIN_ENTRY in $DEVKIT_CONF is not a JSON object" >&2; return 1; }
}
