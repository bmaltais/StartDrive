# Testing StartDrive

How a change gets checked, from the cheapest check to trying it in a live shell. The test session itself (`scripts/dev`), the recorder (`scripts/tour.sh`) and `scripts/sheet` are the shared devkit's, in `scripts/devkit` ([omarchy-plugin-devkit](https://github.com/bmaltais/omarchy-plugin-devkit)); its guides say how they work and why: [testing](../scripts/devkit/docs/testing.md), [how it works, and what went wrong on the way](../scripts/devkit/docs/how-it-works.md), [configuration](../scripts/devkit/docs/configuration.md). This page is what is StartDrive's own.

| You want to | Use | Touches your desktop? |
|---|---|---|
| know the scripts and QML are not broken, and the command line still behaves | `scripts/check.sh` (runs on every commit) | no |
| run only the command-line tests | `tests/cli.sh [word ...]` | no: a throwaway `$HOME`, on demo drives |
| run only the model and input-check tests | `node --test` | no |
| see the plugin run, click it, type into it | `scripts/dev` | no: a nested desktop out of reach of your mouse, on demo drives, behind a guard |
| watch that session | `scripts/dev watch` | a view-only window |
| try it on your own shell | `scripts/reload`, `scripts/pointer.sh` | yes: restarts your shell, moves your pointer |
| look over a recording | `scripts/sheet` | no |
| record the README animations | `scripts/hero.sh`, `scripts/clips.sh` ([recording-tours.md](recording-tours.md)) | no |

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

`scripts/dev` is the devkit's `dev`, run for this checkout; `devkit.conf` tells it the plugin's id and layer, that everything in the session runs in demo mode (`DEVKIT_ENV`, below), and the commands `open`, `setup`, `settings DRIVE_ID` and `close`.

```sh
scripts/dev up                       # a nested desktop, out of your mouse's reach, and a window showing it live
scripts/dev open                     # open the manager there (setup, settings DRIVE_ID such as onedrive, close)
scripts/dev shot /tmp/a.png          # screenshot it, then look at the file
scripts/dev click 826 387            # click the pixel you saw in the screenshot (move PX PY parks the pointer without clicking)
scripts/dev key j                    # press a key (the manager takes j and k, m, o, s, f ...); scripts/dev type TEXT for text
scripts/dev errors                   # what the plugin logged, noise removed (0 = clean)
# edit a .qml file ...
scripts/dev reload                   # restarts the nested shell only; loads uncommitted files
scripts/dev down                     # always, when done
```

Every command prints one line and exits non-zero when it did not do what it says. Pixels, the time limit, the guard that refuses the power commands, and the rest: the devkit's [testing guide](../scripts/devkit/docs/testing.md).

### Demo mode: fixture drives and nothing real

`STARTDRIVE_DEMO=1`, or the marker `~/.config/startdrive/demo/ENABLED`, makes the command line serve four fixture drives from `lib/demo.sh`: Google Drive (mounted, three files uploading, 11 of 15 GB used), OneDrive (mounted, synced), Dropbox (not connected) and an SFTP remote called Work-NAS (not mounted). Mounting, unmounting and the settings change files in the sandbox's own config folder; connecting, forgetting, opening a folder and the terminal flows only say what they would have done. Every tool that could reach the machine (`systemctl`, `rclone`, `secret-tool`, `fusermount3`, `hyprctl`, `xdg-open`, `gum`, `curl` ...) is shadowed by a function that refuses, so a code path nobody thought of fails loudly. The same drives are in every screenshot and recording, with no account names or file names of yours. To add a case (a failed drive, a full one), extend `lib/demo.sh` and add a test.

### Retaking the README screenshots: `scripts/screenshots.sh`

Runs the whole thing in the session: `up` (with `DEV_SIZE` if you want another screen), window sizes reset in the sandbox, a flat backdrop window behind the cards, then `open`, `setup` and `settings onedrive` (its Behaviour, Cache and Maintenance pages), a `shot` of each with the pointer parked in a corner of the backdrop, a crop centred on the screen, then `down`. `SHOTS_OUT=DIR` writes elsewhere, for a trial run. Then `scripts/preview.sh` rebuilds `preview.png`, the marketplace's picture, from them.

## 3. Your real desktop: `scripts/reload`, `scripts/pointer.sh`

For when someone wants to see the change in their own shell.

- `scripts/reload [open | setup | settings ID] [--shot FILE]` copies this checkout over the installed plugin (a plain copy: no commit or push), restarts the shell (the bar blinks), reports plugin errors, and optionally opens a window and screenshots it. It prints `reload ok branch@sha restart 3.9s qml-errors 0 window open up`. `scripts/reload --check` only reports whether the installed plugin matches. New QML only loads after a full shell restart (`omarchy plugin disable` and `enable` do **not** load it). The first time it keeps the old install in `~/.local/share/startdrive-dev/plugin-before-reload`, **outside** `plugins/`: a backup beside the plugin is scanned by the shell as a second copy of it.
- `scripts/pointer.sh click PX PY` clicks the pixel PX,PY of a screenshot of the focused monitor (it works out the monitor's place and scale). It moves the real pointer, so only use it when asked.

## StartDrive's own lessons

- **A recorder must never walk a cloud mount.** `TOUR_REAL_UNCHANGED` fingerprints its paths recursively, and `~/Cloud` was once listed there: the recorder spent minutes walking the user's live Google Drive (slow, and it spends the API quota the README warns about) and looked hung, with no red strip and no view window. Nothing that holds a mount goes in that list, and the fingerprint now uses `find -xdev`, which does not cross into another filesystem.
- **Icons lost in an edit.** Private-use glyphs in QML were dropped when files were rewritten, leaving `iconText: ""`; `check.sh` now fails on it. Write icons as `\uXXXX` escapes.

## Where the files are

| Path | What it is |
|---|---|
| `devkit.conf` | what the devkit needs to know about this plugin: its id, layer, demo mode (`DEVKIT_ENV`, the sandbox hook), commands |
| `scripts/devkit/` | the devkit (a git subtree: `git subtree pull --prefix scripts/devkit https://github.com/bmaltais/omarchy-plugin-devkit vX.Y.Z --squash`) |
| `scripts/dev`, `scripts/tour.sh`, `scripts/sheet` | two-line wrappers of the devkit's `dev`, `tour`, `sheet` for this checkout |
| `scripts/check.sh`, `lint-sh.sh`, `lint-rules.sh`, `lint-qml.py`, `qmllint-baseline.txt`, `.shellcheckrc` | the checks |
| `.githooks/pre-commit`, `.github/workflows/check.yml` | the hook (refuses `main`, runs the checks) and the CI job (shellcheck, the CLI tests, the Node tests) |
| `tests/cli.sh`, `tests/*.test.js` | the command-line behaviour tests (demo mode) and the Node tests |
| `lib/demo.sh` | the fixture drives, and the refusing shims, of demo mode |
| `scripts/screenshots.sh`, `scripts/preview.sh` | the README screenshots and the marketplace picture |
| `scripts/tours/`, `scripts/hero.sh`, `scripts/clips.sh` | the tours ([recording-tours.md](recording-tours.md)) |
| `scripts/reload`, `scripts/pointer.sh` | for the real desktop |
