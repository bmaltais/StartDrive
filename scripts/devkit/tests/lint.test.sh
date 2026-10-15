#!/usr/bin/env bash
# bin/lint catches the mistakes it is for, passes the ones it should, and passes this kit.
source "$(dirname "$0")/lib.sh"

tree() { local d; d=$(mktemp -d -p "$WORK"); for f in "$@"; do mkdir -p "$d/$(dirname "${f%%=*}")"; printf '%b' "${f#*=}" >"$d/${f%%=*}"; done; echo "$d"; }
lint() { "$KIT/bin/lint" "$1" >/dev/null 2>&1; }

check "this kit passes its own rules" lint "$KIT"
check "detached: setsid -f without a redirect is caught" bash -c "! '$KIT/bin/lint' '$(tree 'scripts/dev=#!/usr/bin/env bash\nsetsid -f sleep 100\n')' >/dev/null 2>&1"
check "detached: a redirect on a continuation line passes" lint "$(tree 'lib/x.sh=# shellcheck shell=bash\nsetsid -f env A=1 \\\n  sleep 100 >/dev/null 2>&1\n')"
check "detached: a continuation line without one is caught" bash -c "! '$KIT/bin/lint' '$(tree 'lib/x.sh=# shellcheck shell=bash\nsetsid -f env A=1 \\\n  sleep 100\n')' >/dev/null 2>&1"
check "detached: a comment or a markdown file about setsid -f passes" lint "$(tree 'a.sh=#!/bin/bash\n# setsid -f is what to avoid\n' 'docs/x.md=Use setsid -f with 2>&1\n')"
check "detached: a launch inside a tests folder (a fixture) is not a launch" lint "$(tree 'tests/t.sh=#!/usr/bin/env bash
setsid -f sleep 9
')"
check "sandbox: a copy of the real shell.json is caught" bash -c "! '$KIT/bin/lint' '$(tree 'devkit.conf=# shellcheck shell=bash\nTOUR_SANDBOX_COPY=(.config/omarchy/shell.json)\n')' >/dev/null 2>&1"
check "sandbox: a link of it is caught" bash -c "! '$KIT/bin/lint' '$(tree 'devkit.conf=# shellcheck shell=bash\nTOUR_SANDBOX_LINK=(.local/share/icons .config/omarchy/shell.json)\n')' >/dev/null 2>&1"
check "sandbox: a comment about it passes" lint "$(tree 'devkit.conf=# shellcheck shell=bash\nTOUR_SANDBOX_COPY=()   # the sandbox has its own shell.json\n')"
finish
