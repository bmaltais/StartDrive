#!/usr/bin/env bash
# The guard in front of the session's PATH refuses the commands that would act on the real machine, and writes down each. systemctl and
# loginctl are replaced by stand-ins that only say they were reached, so a fault in the guard fails a test and never reaches the machine.
source "$(dirname "$0")/lib.sh"

# Builds the guard (with extra names) in a new folder.
TMP=$WORK/t; NEST=$TMP/nest; NEST_HOME=$NEST/home; NEST_BIN=$NEST/bin; REPO=$KIT
mkdir -p "$NEST_HOME" "$NEST_BIN"
standin() { printf '#!/bin/bash\necho "reached the real %s $*" >>%q\n' "$1" "$WORK/reached.log" >"$WORK/real-$1"; chmod +x "$WORK/real-$1"; }
standin systemctl; standin loginctl
export GUARD_SYSTEMCTL=$WORK/real-systemctl GUARD_LOGINCTL=$WORK/real-loginctl
DEVKIT_GUARD_EXTRA=(my-power-tool)
# shellcheck source=../lib/session.sh
source "$KIT/lib/session.sh"
sandbox_guard
check "the guard passes its own check" guard_check

refused() { wc -l <"$NEST/guard.log"; }
: >"$NEST/guard.log"
for name in omarchy-system omarchy-system-lock omarchy-system-sleep-lock poweroff reboot shutdown halt hyprlock uwsm my-power-tool; do
  check "$name is refused" bash -c "! $GUARD/$name any args"
done
check "every refusal is written down" test "$(refused)" -eq 10

: >"$NEST/guard.log"
for args in "poweroff" "--no-wall reboot" "suspend" "hibernate" "--user exit" "reboot --boot-loader-menu=0"; do
  # shellcheck disable=SC2086
  check "systemctl $args is refused" bash -c "! $GUARD/systemctl $args"
done
for args in "lock-session" "terminate-user me" "poweroff"; do
  # shellcheck disable=SC2086
  check "loginctl $args is refused" bash -c "! $GUARD/loginctl $args"
done
check "nine refusals written down" test "$(refused)" -eq 9
check "no refused command reached the real systemctl or loginctl" test ! -e "$WORK/reached.log"

check "systemctl passes on what does not act on the machine" "$GUARD/systemctl" --user is-active x
check "loginctl passes on show-session" "$GUARD/loginctl" show-session self
check "those two reached the stand-ins" test "$(wc -l <"$WORK/reached.log")" -eq 2
finish
