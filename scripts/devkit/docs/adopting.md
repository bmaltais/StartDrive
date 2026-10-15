# Adopting the devkit in a plugin

For a new plugin: steps 1 to 4. For one of the three Start apps, which carry a copy of these scripts: all of it, one app at a time, checking against what it did before.

## 1. Put the kit in the repo

```sh
git subtree add --prefix scripts/devkit https://github.com/OWNER/omarchy-plugin-devkit v0.1.0 --squash
# later: git subtree pull --prefix scripts/devkit https://github.com/OWNER/omarchy-plugin-devkit vX.Y.Z --squash
```

A subtree keeps `git clone` working for everyone, and pins the version. (A submodule or a clone beside the repo works too; nothing in the kit cares where it lives, only `devkit.conf` has to be at the plugin's root.)

## 2. Write `devkit.conf` ([configuration.md](configuration.md))

At least `TOUR_PLUGIN_ID`. Add `DEVKIT_LAYERS` (the layer-shell names of the plugin's windows), `TOUR_PLUGIN_WIDGET=0` for a service, `TOUR_PLUGIN_ENTRY` for the settings the session starts from, and the commands that open its windows (`dev_cmd_*`).

## 3. Two-line wrappers, so `scripts/dev` is what people type

```bash
#!/usr/bin/env bash
export DEVKIT_APP_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
exec "$DEVKIT_APP_ROOT/scripts/devkit/bin/dev" "$@"
```

The same for `tour` (often `scripts/tour.sh`) and `sheet`. Run from the plugin's checkout, the kit finds it without `DEVKIT_APP_ROOT`; the wrapper makes it work from anywhere, and from a script.

## 4. Add the checks

`scripts/devkit/bin/lint` in the plugin's check script, and the devkit's scripts in its shellcheck list (`scripts/devkit/bin/*`, `scripts/devkit/lib/*.sh`). If the plugin's tests exercise the guard, point them at `scripts/devkit/lib/session.sh`.

## Moving a Start app off its copy

What changes in an app's files:

| Was (the copy) | Is (the kit) |
|---|---|
| `scripts/nested/session.sh`, `vptr.c`, `build.sh`, the Wayland XML | `scripts/devkit/lib/session.sh`, `vptr.c`, `build-vptr.sh`, the XML |
| `scripts/dev`, `scripts/tour.sh`, `scripts/sheet` | wrappers of `scripts/devkit/bin/dev`, `tour`, `sheet` |
| `scripts/dev-view.qml`, `scripts/tour-banner.qml` | `scripts/devkit/lib/…` (the view window's title comes from `DEVKIT_NAME`) |
| `TOUR_PLUGIN_ID`, `TOUR_SANDBOX_*`, `TOUR_REAL_UNCHANGED` set in `scripts/dev` and each tour | set once in `devkit.conf`; a tour may still override |
| `dev open`, `setup`, `settings ID`, `close` (`cmd_window`) | `dev_cmd_open` and the rest, in `devkit.conf`, using `dev_window` |
| `overlay_up` with the app's layer name written in | `DEVKIT_LAYERS`, or `devkit_window_up` |
| `ID`, the state folder `NAME-dev`, `QS_APP_ID=NAME-test-viewer` | `TOUR_PLUGIN_ID`, `DEVKIT_NAME` (set it to the old `NAME` and they are unchanged) |
| `sandbox_repoint` (demo mode, or rewriting copied manifests) | the `devkit_sandbox DIR` hook, and `DEVKIT_ENV=(STARTDRIVE_DEMO=1)` for the demo switch |
| tours that `source "$HERE/tours/common.sh"` | `source "$TOUR_DIR/common.sh"` (`HERE` is not set for a tour any more) |
| `scripts/lint-rules.sh` | `bin/lint` (the same rules, found by content and not by a list of paths) |
| (nothing) | the guard: the session refuses the plugin's power commands. StartDrive's demo mode already refuses every tool that could reach the machine; the guard is a second wall |
| a recording's frames left in `/tmp` | removed when the run ends (`TOUR_KEEP_TMP=1` keeps them) |

### StartDrive

A sketch from reading its copy, **not yet tried against the app**; step 5 below is how to find out.

```bash
TOUR_PLUGIN_ID=io.github.bmaltais.startdrive
DEVKIT_NAME=startdrive
DEVKIT_LAYERS=(omarchy-startdrive)
DEVKIT_ENV=(STARTDRIVE_DEMO=1)           # the CLI serves fixture drives and runs no systemd, rclone or keyring command
TOUR_SANDBOX_LINK=(.local/share/icons)
TOUR_REAL_UNCHANGED=(.config/omarchy/shell.json .config/startdrive .config/systemd/user .config/rclone .local/share/applications/startdrive.desktop .local/bin/startdrive)

devkit_sandbox() {                       # the sandbox is in demo mode, and the first-run offer is answered
  local h=$1
  mkdir -p "$h/.config/startdrive/demo"; : >"$h/.config/startdrive/demo/ENABLED"
  [[ -f $h/.config/startdrive/demo/ENABLED ]] || { echo "the sandbox could not be put in demo mode" >&2; return 1; }
  printf 'SETUP_DONE=1\n' >"$h/.config/startdrive/config"
}
DEVKIT_USAGE='  dev open | setup | settings DRIVE_ID | close'
dev_cmd_open() { nenv omarchy-shell -q "$ID" close 2>/dev/null || true; sleep 0.4; dev_window open "$ID" open; }
dev_cmd_setup() { dev_window setup "$ID" setup; }
dev_cmd_settings() { dev_window settings "$ID" settings "${1:?settings needs a drive id}"; }
dev_cmd_close() { nenv omarchy-shell "$ID" close; echo "dev close: closed"; }
```

It also has a bar widget (leave `TOUR_PLUGIN_WIDGET` at 1), keeps `dev move` (the kit has it), and its `tests/cli.sh` stays its own. Its tours' `TOUR_LAYER` is `DEVKIT_LAYERS`.

### StartAppImage

Also not yet tried. Its `devkit_sandbox` is the part that copies each AppImage a manifest names into the sandbox and points the `EXEC=`, `DESKTOP=` and `Exec=` paths at the copies (today `sandbox_repoint` in its `session.sh`), with `TOUR_SANDBOX_COPY=(.local/share/startappimage .local/share/applications)`. Keep that function as it is, in `devkit.conf`.

## Checking nothing broke

Per app, before deleting the copy: on a branch, add the kit and the conf, remove the copied files, and compare.

1. The app's own check (`scripts/check.sh`, `npm run check`) passes.
2. `scripts/dev up`, open each window with the app's commands, `dev shot` each, `dev errors` is 0, `dev down`.
3. Its smoke test and screenshots script give images of the same sizes as before (StartBar's did: 790×72, 276×209, 512×253 ...).
4. One tour, with the same crop, comes out the same length and size (StartBar's start-menu clip: 220 KB before, 224 KB after), and "your real files are unchanged" is printed.
5. The guard did its work: click the plugin's power buttons if it has any, and see `dev status` count the refusals.

StartBar's was done this way in a scratch checkout before the kit was published; the result is above. When the kit changes, update the three apps one at a time with `git subtree pull`, and run the same list.
