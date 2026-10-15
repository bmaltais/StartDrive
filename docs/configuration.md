# Configuring the devkit for a plugin

An app says what is its own in one file, `devkit.conf`, at the root of its checkout. It is plain bash: variables, and (if it wants) functions. `dev` and `tour` both source it, with defaults set first, so a conf only lists what differs. `lib/config.sh` loads it and tells you what is wrong with it.

Which checkout is "the app"? The one named by `DEVKIT_APP_ROOT` (the app's own wrapper scripts set it, see [adopting.md](adopting.md)), else the git root of the folder the command is run in. `DEVKIT_CONF` names another conf file.

```bash
# shellcheck shell=bash
TOUR_PLUGIN_ID=io.github.me.myplugin
TOUR_PLUGIN_WIDGET=0
TOUR_PLUGIN_ENTRY='{"colorScheme":"dark"}'
DEVKIT_LAYERS=(omarchy-myplugin)
```

## Variables

| Variable | Meaning | Default |
|---|---|---|
| `TOUR_PLUGIN_ID` | **Required.** The plugin's id (its `manifest.json` `id`). The checkout is linked into the session's plugins folder under it | |
| `DEVKIT_NAME` | A short lower-case name: the session's state folder (`$XDG_RUNTIME_DIR/NAME-dev`) and its view window (`NAME-test-viewer`, "NAME test session") | the checkout's folder name |
| `TOUR_TITLE` | The app's name for the recorder's strip and notifications | `DEVKIT_NAME` |
| `TOUR_PLUGIN_ENTRY` | A JSON object merged into the plugin's entry in the sandbox's `shell.json`: the settings the session starts with | `{}` |
| `TOUR_PLUGIN_WIDGET` | `0` for a plugin with no bar widget (a service): it is loaded, but not put on the Omarchy bar. `1` adds its id to the bar's right side if your bar layout lacks it | `1` |
| `DEVKIT_LAYERS=(ns …)` | Layer-shell namespaces of the plugin's windows. `dev` calls the window up when one is mapped (for `dev status`, the notes on input, `dev_window`), and `tour` sends keys (`typed`, `esc`, `pressed`) only while one is | none |
| `TOUR_SANDBOX_COPY=(path …)` | Paths under `$HOME` to *copy* into the sandbox: data the session changes | none |
| `TOUR_SANDBOX_LINK=(path …)` | Paths under `$HOME` to *link* read-only (icons) | none |
| `TOUR_REAL_UNCHANGED=(path …)` | Paths under your real `$HOME` that a recording must not change: fingerprinted before and after, and the run fails if one changed. Never name a mount (it would be walked) | none |
| `DEVKIT_ENV=(NAME=value …)` | Environment for everything in the session: a demo-mode switch, say | none |
| `DEVKIT_GUARD_EXTRA=(name …)` | Commands to refuse as well as the built-in list ([how-it-works.md](how-it-works.md#the-guard)): your own plugin's power or lock command, a tool that would touch real data | none |
| `DEVKIT_NOISE` | An extra regular expression: log lines matching it are not counted as the plugin's errors | none |
| `DEVKIT_USAGE` | Text added to `dev --help`, for the commands the conf defines | none |

## Hooks (functions in `devkit.conf`)

| Hook | Called | Use it to |
|---|---|---|
| `devkit_sandbox DIR` | while the sandbox home DIR is built, after the copies and links and the guard | make the sandbox safe for your plugin: a demo-mode marker file, rewrite paths in copied files so a change cannot reach a real one. Return non-zero to refuse to start |
| `devkit_window_up` | by `dev`, to ask whether the plugin's window is up | replace the `DEVKIT_LAYERS` check, for a window that is not a layer of its own. Helpers: `layer_mapped NS`, `nenv CMD…` (run a command in the session), `$ID` |
| `tour_keys_ok` | by `tour`, before each key | the same, for the recorder: say whether the window is up so `typed`/`esc`/`pressed` may send keys. May call `layer_up NS` (the recorder's) or `hyprctl` |
| `dev_cmd_NAME ARGS…` | `dev NAME ARGS…`, with the session known to be up | add a command: open a window, call the plugin's IPC. Helpers: `dev_window LABEL ARGS…` (calls `omarchy-shell ARGS` in the session, checks the window opened, says so), `nenv`, `$ID` |
| `tour_requires` | first, by `tour`, with your real home | check what the tour needs; print a reason and return non-zero if it is missing |

In a hook running in `dev`: `nenv COMMAND…` runs a command in the session's environment (its home, its guard, its compositor), `$ID` is the plugin id, `$NEST_HOME` the session's home, `$NSIG`/`$NWD` its Hyprland signature and Wayland socket, `shell_up` asks whether its shell answers.

## Commands `dev` has without any configuration

`up`, `down`, `status`, `reload`, `watch`, `unwatch`, `ipc TARGET METHOD [ARGS]` (the plugin's IPC, in the session), `run CMD…`, `windows`, `set JSON`, `env`, `click`, `rclick`, `scroll`, `move`, `type`, `key`, `shot`, `errors`. `dev --help` lists them with your own.

Environment: `DEV_SIZE=WxH` (the session's screen, default 1280x800), `DEV_WATCH=0` (no view window), `DEV_TTL=SECONDS` (it closes itself, default 1800), `DEV_QUIET=1` (no notes when the window is not up), `NEST_HOST_INPUT=1` (keep your mouse and keyboard on, for debugging the session by hand).

## What a tour file sets

A tour file is sourced by `tour` after `devkit.conf`, so it can override it (a tour can start the plugin from other settings than `dev` does). It sets `TOUR_OUT`, `TOUR_STEPS`, `TOUR_SIZE`, `TOUR_CROP`, `TOUR_MAX_SECONDS` and the rest of the table in [recording-tours.md](recording-tours.md#reference), and defines `tour_play`. `TOUR_DIR` is the folder the tour file is in, so a tour can `source "$TOUR_DIR/common.sh"` for what the app's tours share.
