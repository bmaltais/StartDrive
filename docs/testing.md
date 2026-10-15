# Testing StartDrive

How a change gets checked, from the cheapest check to trying it in a live shell. Written so a person or an agent can pick it up cold, and so it can be improved: the last sections say how it works inside and what went wrong on the way.

| You want to | Use | Touches your desktop? |
|---|---|---|
| know the scripts and QML are not broken, and the command line still behaves | `scripts/check.sh` (runs on every commit) | no |
| run only the command-line tests | `tests/cli.sh [word ...]` | no: a throwaway `$HOME`, on demo drives |
| run only the model and input-check tests | `node --test` | no |
| see the plugin run, click it, type into it | `scripts/dev` | no: a nested desktop out of reach of your mouse, on demo drives |
| watch that session | `scripts/dev watch` | a view-only window |
| try it on your own shell | `scripts/reload`, `scripts/pointer.sh` | yes: restarts your shell, moves your pointer |
| look over a recording | `scripts/sheet` | no |
| record the README animation | `scripts/hero.sh` ([recording-tours.md](recording-tours.md)) | no |

**The rule: test in `scripts/dev`, not on the real desktop.** The test session also never touches your real drives: it runs in [demo mode](#demo-mode-fixture-drives-and-nothing-real). A click or key sent to the real shell moves your pointer and types into your windows, a shell restart makes the bar blink, and a window left over your pointer can leave it behaving oddly. The test session has none of that. Use `reload` and `pointer.sh` only when the person asks to see it on their real shell.

## 1. Checks: `scripts/check.sh`

One command, no running shell needed. The pre-commit hook runs it and refuses a commit on `main`; CI runs the shell and Node parts.

```sh
scripts/check.sh          # all of it
scripts/lint-sh.sh        # bash -n and shellcheck over every script (rules in .shellcheckrc)
scripts/lint-qml.py       # qmllint, failing only on a warning the baseline does not list
omarchy plugin validate . # the manifest
node --test               # the model, the CLI's input checks, the rules for files still uploading, the marketplace rules
```

- **Enable the hook once per clone:** `git config core.hooksPath .githooks`. Override for the rare commit that must go on `main`: `ALLOW_MAIN=1 git commit`.
- **QML warnings.** `qmllint` cannot see Quickshell's or Omarchy's types, so about ninety warnings are standing noise, kept in `scripts/qmllint-baseline.txt`. A *new* one (a misspelt id, a removed property) fails. If it is a real name from the shell, accept it with `scripts/lint-qml.py --update`. Three categories are bugs, never noise, and cannot be baselined (`property-override`, `id-shadows-member`, `duplicate-property-binding`): a property named `data`, `state` or `children` hides the item's own, which breaks the window silently. They fail the check even when listed, and `--update` refuses to write while one is present (`tests/lint-qml.test.js`). The idea is StartBar's, ported to Python.
- **Project rules** live in `scripts/check.sh` and `scripts/lint-rules.sh`: no empty `iconText` (an icon whose glyph was lost in an edit), the recorder's window geometry is computed, never typed, every `setsid -f` launch redirects its own output (`2>&1`; see section 6), and a tour's `TOUR_REAL_UNCHANGED` never names a cloud mount. `tests/cli.sh` proves each rule catches what it is for.
- **Command-line tests.** `tests/cli.sh` runs `bin/startdrive` against a throwaway `$HOME` in demo mode and asserts exit codes, JSON and files on disk (state, activity, mount and unmount, settings, the launcher entry, the command-line link, the first-run answer, window memory). A test is a `t_*` function; name words on the command line select tests. One test puts shims for `systemctl`, `rclone`, `secret-tool` and the rest on `PATH` and fails if demo mode ever runs one. It never touches the network, the real home or the desktop, so it also runs in CI.
- **Node tests** (`node --test`, `tests/*.test.js`). `DriveModel.test.js` runs the rules of the UI (status lines, keys, the settings pages and their hints, notifications) with no shell. `cli.test.js` checks the input allow-lists, which fail before anything is run. `lifecycle.test.js` runs the rules that protect files still uploading against a fake `systemctl` and a fake rclone socket. `manifest.test.js` is the marketplace's rules, for CI.
- **What it cannot catch:** a layout that looks wrong, a click that misses, anything about the live shell. That is what the test session is for.

## 2. The test session: `scripts/dev`

A second Hyprland with its own Omarchy shell, running this checkout as the plugin, driven over its own Wayland socket. `scripts/dev --help` is the reference; this is the shape of a session:

```sh
scripts/dev up                       # 2 s. a nested desktop, out of your mouse's reach, and a window showing it live
scripts/dev open                     # open the manager there (setup, settings DRIVE_ID such as onedrive, close)
scripts/dev shot /tmp/a.png          # screenshot it, then look at the file
scripts/dev click 826 387            # click the pixel you saw in the screenshot (move PX PY parks the pointer without clicking)
scripts/dev key j                    # press a key (the manager takes j and k, m, o, s, f ...); scripts/dev type TEXT for text
scripts/dev errors                   # what the plugin logged, noise removed (0 = clean)
# edit a .qml file ...
scripts/dev reload                   # 4 s. restarts the nested shell only; loads uncommitted files
scripts/dev down                     # always, when done
```

Every command prints one line and exits non-zero when it did not do what it says (`dev reload FAILED ... qml-errors 2`, `dev open: the window did NOT open`).

- **Pixels** are the session's screen, 1280×800 by default (`DEV_SIZE=1920x1200 scripts/dev up` for a larger one), 0,0 at the top-left, exactly as in a `dev shot`. Read the pixel off the screenshot and click it; nothing is scaled or offset.
- **A click outside the card closes it**, as it would for a person: screenshot before you click.
- **No commit or push is needed.** The plugin in the session is a link to this checkout, so `reload` loads what is on disk. (Your real shell is different: its plugin is a copy of this checkout, refreshed by `scripts/reload`, see section 3.)
- **It closes itself** after `DEV_TTL` seconds (default 1800), and a stale session is cleaned up by the next `up`. End it yourself with `down`: the session holds a virtual monitor and about a dozen processes.
- **Your drives are safe.** The session shares your user's systemd, keyring and rclone config, so a click on a mount switch there could mount, or "forget", a real account. It cannot: the sandbox home has a marker file that puts `bin/startdrive` in demo mode (next section), and `sandbox_repoint` in `scripts/nested/session.sh` refuses to start the session unless the marker is there and no real drive's settings were copied in. Its bar starts with a "TEST SESSION" label, because the window's own title is fixed by the nested compositor ("aquamarine - WAYLAND-N") and the desktop inside looks exactly like yours. The first-run offer is marked answered in the sandbox, so no window opens by itself.

### Demo mode: fixture drives and nothing real

`STARTDRIVE_DEMO=1`, or the marker `~/.config/startdrive/demo/ENABLED`, makes the command line serve four fixture drives from `lib/demo.sh`: Google Drive (mounted, three files uploading, 11 of 15 GB used), OneDrive (mounted, synced), Dropbox (not connected) and an SFTP remote called Work-NAS (not mounted). Mounting, unmounting and the settings change files in the sandbox's own config folder; connecting, forgetting, opening a folder and the terminal flows only say what they would have done. Every tool that could reach the machine (`systemctl`, `rclone`, `secret-tool`, `fusermount3`, `hyprctl`, `xdg-open`, `gum`, `curl` ...) is shadowed by a function that refuses, so a code path nobody thought of fails loudly. The same drives are in every screenshot and recording, with no account names or file names of yours. To add a case (a failed drive, a full one), extend `lib/demo.sh` and add a test.

### Retaking the README screenshots: `scripts/screenshots.sh`

Runs the whole thing in the session: `up` (with `DEV_SIZE` if you want another screen), window sizes reset in the sandbox, a flat backdrop window behind the cards, then `open`, `setup` and `settings onedrive` (its Behaviour, Cache and Maintenance pages), a `shot` of each with the pointer parked in a corner of the backdrop, a crop centred on the screen, then `down`. `SHOTS_OUT=DIR` writes elsewhere, for a trial run. Then `scripts/preview.sh` rebuilds `preview.png`, the marketplace's picture, from them.

### Watching it: `scripts/dev watch`

`up` opens it (`DEV_WATCH=0 scripts/dev up` for none; `dev watch` opens it later). It is an ordinary window (`scripts/dev-view.qml`) that shows the session five times a second. Drag it, cover it, resize it, send it to the scratchpad: your pointer is the normal arrow over it and a click does nothing, because nothing in it listens. `scripts/dev unwatch` closes it. It ends with the session. It shows the session's whole screen, so it looks empty until a plugin window is open (`dev open`).

The session's *own* window is never put on your screen. That was tried and it was wrong: see "What went wrong" below.

## 3. Your real desktop: `scripts/reload`, `scripts/pointer.sh`

For when someone wants to see the change in their own shell.

- `scripts/reload [open | setup | settings ID] [--shot FILE]` copies this checkout over the installed plugin (a plain copy: no commit or push), restarts the shell (the bar blinks), reports plugin errors, and optionally opens a window and screenshots it. It prints `reload ok branch@sha restart 3.9s qml-errors 0 window open up`. `scripts/reload --check` only reports whether the installed plugin matches. New QML only loads after a full shell restart (`omarchy plugin disable` and `enable` do **not** load it). The first time it keeps the old install in `~/.local/share/startdrive-dev/plugin-before-reload`, **outside** `plugins/`: a backup beside the plugin is scanned by the shell as a second copy of it.
- `scripts/pointer.sh click PX PY` clicks the pixel PX,PY of a screenshot of the focused monitor (it works out the monitor's place and scale). It moves the real pointer, so only use it when asked.

## 4. Looking over a recording: `scripts/sheet`

`scripts/sheet FILE.avif|gif [--every S] [--width PX] [--cols N] [--out FILE]` makes one contact sheet image from an animation, so a whole recording can be checked at once. It knows that an AVIF holds two video streams (the still cover, then the animation) and reads the second.

## 5. How it works inside

```
scripts/dev ──► scripts/nested/session.sh ──► Hyprland (nested) ──► quickshell: the Omarchy shell + this plugin
   │                  (sandbox, start, stop)         │ a window of your compositor, moved to a virtual monitor
   │                                                 │   at x = 20000, which a real pointer cannot reach
   ├─ click, type, key ──► scripts/nested/vptr (virtual pointer) and wtype (virtual keyboard), on the session's socket
   ├─ shot ───────────────► grim, on the session's socket
   └─ errors ─────────────► the session's shell log, filtered
```

- **`scripts/nested/session.sh`** is shared with the recorder (`scripts/tour.sh`). It builds the sandbox home (Omarchy's themes copied, a `shell.json` that keeps your bar layout but only Omarchy's own widgets plus this plugin, the plugin linked to the checkout, a marker that puts the CLI in demo mode and the first-run answer), starts the nested Hyprland under its own D-Bus that starts nothing, and stops everything it started.
- **Input.** `scripts/nested/vptr.c` is a tiny client of the `wlr-virtual-pointer` protocol (built on first use into the session's folder). Keys use `wtype`. Both talk to the nested compositor's socket, so nothing reaches your real seat.
- **Your mouse and keyboard are switched off inside the session.** The host seat gives the nested compositor two devices, `wl_pointer` and `wl_keyboard`; its config disables both (`hl.device({ name = ..., enabled = false })`). The virtual devices are separate and keep working. This was checked with a control: the same real click closes a card when the devices are left on (`NEST_HOST_INPUT=1`) and does nothing when they are off.
- **The far monitor.** `up` creates a headless monitor `DEVTEST` 20,000 px to the right and moves the window there. Sliding a mouse off the edge of your screen stops at the edge, so the window cannot be reached. `down` removes the monitor.
- **The noise filter.** `errors` and `reload` count only lines that name this plugin's files (`io.github.bmaltais.startdrive`) and carry a warning or error, minus known noise (layout "recursive rearrange", "Local plugin changed", qmlscanner, portal, `qt.svg`). Omarchy's own errors (for example the bar's "Cannot assign to read-only property moduleName" for the label widget) are not ours and are not counted.

## 6. What went wrong on the way, and the rule it left

Each of these cost a round of testing; they are why the design is what it is.

- **Never put the nested compositor's window under a real pointer.** While a pointer is over it, the nested compositor chooses the cursor image: it hid the pointer, showed a hand, and left the pointer behaving oddly after a window drag. A transparent *shield* over the window cured the input but showed a "block" cursor and stopped the window being dragged, since it is a separate overlay. Hence the far monitor for the session and the separate view window for watching. The recorder's `--nested` mode uses the same far monitor and view window.
- **Do not change the nested compositor's cursor options at runtime** (`hl.config({ cursor = ... })` through `hyprctl eval`): it crashed the nested Hyprland.
- **A reused socket name hid the session.** The nested compositor's socket is `wayland-N` and the number is reused, so finding "the new socket" by a name that was absent before failed after an aborted cleanup left a stale file. It is found by being created after the start, and `down` removes its own socket and instance folder.
- **`pgrep -f` matches its own shell.** A pattern passed to `pgrep -f` in a command line also matches that command line. Find processes by an environment marker (`procs_with` in `scripts/dev`) or use a `[x]` bracket pattern.
- **Plugin reload does not load QML.** Only a full shell restart does. Both `reload` and `dev reload` do that restart.
- **A recorder must never walk a cloud mount.** `TOUR_REAL_UNCHANGED` fingerprints its paths recursively, and `~/Cloud` was once listed there: the recorder spent minutes walking the user's live Google Drive (slow, and it spends the API quota the README warns about) and looked hung, with no red strip and no view window. Nothing that holds a mount goes in that list, and the fingerprint now uses `find -xdev`, which does not cross into another filesystem.
- **A background process that keeps the caller's output open makes `dev up | tail` hang.** The TTL watcher and the view window's frame loop were launched without redirecting their own output, so a pipe on `dev up` stayed open until they ended (up to 30 minutes), the next command in the chain never ran, and the session sat ready with nobody driving it. Every detached launch now ends in `>/dev/null 2>&1 </dev/null`; keep that on any new one.
- **`DEV_WATCH=0` hides the view window.** `scripts/dev up` opens it unless that is set; a session started without it looks like nothing is happening. It also looks empty until a plugin window is open (`dev open`).
- **Icons lost in an edit.** Private-use glyphs in QML were dropped when files were rewritten, leaving `iconText: ""`; `check.sh` now fails on it. Write icons as `\uXXXX` escapes.
- **ffprobe reads one frame of an AVIF.** It shows the still cover image first; the animation is the second video stream (`-f mov -map 0:v:1`). `scripts/sheet` does this for you.

## 7. Limits, and ideas for improving it

- **Hyprland only, and a newer Hyprland than 0.56 may change the Lua API** (`hl.dsp.window.move`, `hl.device`, `hl.monitor`) that `scripts/nested/session.sh` and `scripts/dev` use.
- **One session at a time** (a fixed state folder and monitor name).
- **The view window is a picture, not the session**: five frames a second, so a fast animation looks choppy, and the cursor of the session is whatever the screenshot has in it.
- **`dev click` has no hover, drag or scroll.** `vptr` can drag (the recorder uses it); `dev` could expose `drag` and `scroll`.
- **Ideas:** a `dev run SCRIPT` that replays a list of steps and fails on the first miss (a smoke test for CI-less checking); `dev shot --diff` against the last shot; installing `wl-mirror` or a Quickshell `ScreencopyView` would replace the five-frames-a-second picture with a live one.

## Where the files are

| Path | What it is |
|---|---|
| `scripts/check.sh`, `lint-sh.sh`, `lint-qml.py`, `qmllint-baseline.txt`, `.shellcheckrc` | the checks |
| `.githooks/pre-commit`, `.github/workflows/check.yml` | the hook (refuses `main`, runs the checks) and the CI job (shellcheck, the CLI tests, the Node tests) |
| `tests/cli.sh`, `tests/*.test.js` | the command-line behaviour tests (demo mode) and the Node tests |
| `lib/demo.sh` | the fixture drives, and the refusing shims, of demo mode |
| `scripts/dev`, `scripts/dev-view.qml` | the test session and its view window |
| `scripts/nested/` | session start/stop and the virtual pointer, shared with the recorder |
| `scripts/reload`, `scripts/pointer.sh` | for the real desktop |
| `scripts/sheet` | contact sheets |
| `scripts/screenshots.sh`, `scripts/preview.sh` | the README screenshots and the marketplace picture |
| `scripts/tour.sh`, `scripts/tours/`, `scripts/tour-banner.qml` | the recorder ([recording-tours.md](recording-tours.md)) |
