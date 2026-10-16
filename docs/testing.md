# Testing StartDrive

How a change gets checked, from the cheapest check to trying it in a live shell. Written so a person or an agent can pick it up cold. The test session, the recorder and `sheet` are the shared devkit's (`scripts/devkit`, a git submodule: clone with `--recurse-submodules`, or `git submodule update --init`); its guide is [scripts/devkit/docs/testing.md](../scripts/devkit/docs/testing.md), and how it works inside is in [how-it-works.md](../scripts/devkit/docs/how-it-works.md). This page is what is StartDrive's own, set in `devkit.conf`.

| You want to | Use | Touches your desktop? |
|---|---|---|
| know the scripts and QML are not broken, and the command line still behaves | `scripts/check.sh` (runs on every commit) | no |
| run only the command-line tests | `tests/cli.sh [word ...]` | no: a throwaway `$HOME`, on demo drives |
| run only the model and input-check tests | `node --test` | no |
| see the plugin run, click it, type into it | `scripts/dev` | no: a nested desktop out of reach of your mouse, on demo drives |
| watch that session | `scripts/dev watch` | a view-only window |
| try it on your own shell | `scripts/reload`, `scripts/pointer` | yes: restarts your shell, moves your pointer |
| look over a recording | `scripts/sheet` | no |
| record the README animations | `scripts/hero.sh`, `scripts/clips.sh` ([recording-tours.md](recording-tours.md)) | no |

**The rule: test in `scripts/dev`, not on the real desktop.** The test session also never touches your real drives: it runs in [demo mode](#demo-mode-fixture-drives-and-nothing-real). A click or key sent to the real shell moves your pointer and types into your windows, a shell restart makes the bar blink, and a window left over your pointer can leave it behaving oddly. The test session has none of that. Use `reload` and `pointer` only when the person asks to see it on their real shell.

## 1. Checks: `scripts/check.sh`

One command, no running shell needed: a wrapper of the devkit's `check` (shell scripts, the devkit's rules, qmllint, the manifest), plus this app's own steps from `devkit_check` in `devkit.conf`. The pre-commit hook runs it and refuses a commit on `main`; CI calls the kit's `app-check` workflow, which runs the same, skipping the QML and manifest steps where Qt and Omarchy are not installed.

```sh
scripts/check.sh          # all of it
scripts/qmllint            # qmllint, failing only on a warning the baseline does not list
omarchy plugin validate . # the manifest
node --test               # the model, the CLI's input checks, the rules for files still uploading, the marketplace rules
```

- **Enable the hook once per clone:** `scripts/devkit/bin/pre-commit --install` (writes `.githooks/pre-commit` and sets `core.hooksPath`). Override for the rare commit that must go on `main`: `ALLOW_MAIN=1 git commit`.
- **QML warnings.** `qmllint` cannot see Quickshell's or Omarchy's types, so about ninety warnings are standing noise, kept in `scripts/qmllint-baseline.txt`. A *new* one (a misspelt id, a removed property) fails. If it is a real name from the shell, accept it with `scripts/qmllint --update`. Three categories are bugs, never noise, and cannot be baselined (`property-override`, `id-shadows-member`, `duplicate-property-binding`): a property named `data`, `state` or `children` hides the item's own, which breaks the window silently. They fail the check even when listed, and `--update` refuses to write while one is present (tested in the devkit).
- **Project rules.** `scripts/check.sh` fails on an empty `iconText` (an icon whose glyph was lost in an edit; a `devkit_check` step) and runs the devkit's rules, which the kit documents (detached launches redirect their output, a sandbox never links the real `shell.json`). `devkit.conf` adds StartDrive's own rule: no `TOUR_REAL_UNCHANGED` names a cloud mount (`cloud_mounts`; `tests/cli.sh` proves it catches one). The shell scripts get `bash -n` and shellcheck (rules in `.shellcheckrc`). The scripts need the submodule: `git submodule update --init`.
- **Command-line tests.** `tests/cli.sh` runs `bin/startdrive` against a throwaway `$HOME` in demo mode and asserts exit codes, JSON and files on disk (state, activity, mount and unmount, settings, the launcher entry, the command-line link, the first-run answer, window memory). A test is a `t_*` function; name words on the command line select tests. One test puts shims for `systemctl`, `rclone`, `secret-tool` and the rest on `PATH` and fails if demo mode ever runs one. It never touches the network, the real home or the desktop, so it also runs in CI.
- **Node tests** (`node --test`, `tests/*.test.js`). `DriveModel.test.js` runs the rules of the UI (status lines, keys, the settings pages and their hints, notifications) with no shell. `cli.test.js` checks the input allow-lists, which fail before anything is run. `lifecycle.test.js` runs the rules that protect files still uploading against a fake `systemctl` and a fake rclone socket. `manifest.test.js` is the marketplace's rules, for CI.
- **What it cannot catch:** a layout that looks wrong, a click that misses, anything about the live shell. That is what the test session is for.

## 2. The test session: `scripts/dev`

A second Hyprland with its own Omarchy shell, running this checkout as the plugin, driven over its own Wayland socket. `scripts/dev` is a wrapper of the devkit's `dev`; `scripts/dev --help` is the reference, with this app's commands (`open`, `setup`, `settings DRIVE_ID`, `close`, from `devkit.conf`). This is the shape of a session:

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

- **Pixels, clicks, `DEV_TTL`, `DEV_SIZE`** work as in the kit's [testing guide](../scripts/devkit/docs/testing.md): read the pixel off a `dev shot`, and look before you click, because a click outside the card closes it.
- **No commit or push is needed.** The plugin in the session is a link to this checkout, so `reload` loads what is on disk. (Your real shell is different: its plugin is a copy of this checkout, refreshed by `scripts/reload`, see section 3.)
- End it yourself with `down`; it closes itself after `DEV_TTL` seconds.
- **Your drives are safe.** The session shares your user's systemd, keyring and rclone config, so a click on a mount switch there could mount, or "forget", a real account. It cannot: the sandbox home has a marker file that puts `bin/startdrive` in demo mode (next section), and `devkit_sandbox` in `devkit.conf` puts the marker there, which the session refuses to start without. The devkit adds a second wall: a guard in front of `PATH` that refuses the power commands. Its bar starts with a "TEST SESSION" label, because the window's own title is fixed by the nested compositor ("aquamarine - WAYLAND-N") and the desktop inside looks exactly like yours. The first-run offer is marked answered in the sandbox, so no window opens by itself.

### Demo mode: fixture drives and nothing real

`STARTDRIVE_DEMO=1`, or the marker `~/.config/startdrive/demo/ENABLED`, makes the command line serve four fixture drives from `lib/demo.sh`: Google Drive (mounted, three files uploading, 11 of 15 GB used), OneDrive (mounted, synced), Dropbox (not connected) and an SFTP remote called Work-NAS (not mounted). Mounting, unmounting and the settings change files in the sandbox's own config folder; connecting, forgetting, opening a folder and the terminal flows only say what they would have done. Every tool that could reach the machine (`systemctl`, `rclone`, `secret-tool`, `fusermount3`, `hyprctl`, `xdg-open`, `gum`, `curl` ...) is shadowed by a function that refuses, so a code path nobody thought of fails loudly. The same drives are in every screenshot and recording, with no account names or file names of yours. To add a case (a failed drive, a full one), extend `lib/demo.sh` and add a test.

### Retaking the README screenshots: `scripts/screenshots.sh`

Runs the whole thing in the session: `up` (with `DEV_SIZE` if you want another screen), window sizes reset in the sandbox, a flat backdrop window behind the cards, then `open`, `setup` and `settings onedrive` (its Behaviour, Cache and Maintenance pages), a `shot` of each with the pointer parked in a corner of the backdrop, a crop centred on the screen, then `down`. `SHOTS_OUT=DIR` writes elsewhere, for a trial run. Then `scripts/preview.sh` rebuilds `preview.png`, the marketplace's picture, from them.

### Watching it

`scripts/dev up` opens a view-only window of the session (`DEV_WATCH=0` for none; `scripts/dev watch` / `unwatch` later). How it works, and why the session's own window is never put on your screen, is in the kit's [how-it-works.md](../scripts/devkit/docs/how-it-works.md).

## 3. Your real desktop: `scripts/reload`, `scripts/pointer`

For when someone wants to see the change in their own shell. Both are wrappers of the devkit's `reload` and `pointer` (its `--help` is the reference).

- `scripts/reload [open | setup | settings DRIVE_ID] [--shot FILE]` copies this checkout over the installed plugin (the installed one is a plain copy, so the kit uses its `copy` mode: no commit or push), restarts the shell (the bar blinks), reports plugin errors, and optionally opens a window and screenshots it. `scripts/reload --check` only reports whether the installed plugin matches. What is StartDrive's own is in `devkit.conf`: `DEVKIT_RELOAD_READY=state` (wait for the service) and `reload_open` (`open` closes the manager first, so the toggle cannot hide it). The first time it keeps the old install in `~/.local/share/startdrive-dev/plugin-before-reload`, **outside** `plugins/`: a backup beside the plugin is scanned by the shell as a second copy of it.
- `scripts/pointer click PX PY` clicks the pixel PX,PY of a screenshot of the focused monitor (it works out the monitor's place and scale); `move` and `pos` likewise. It moves the real pointer, so only use it when asked.

## 4. Looking over a recording: `scripts/sheet`

`sheet FILE.avif|gif [--every S] [--width PX] [--cols N] [--out FILE]` makes one contact sheet image from an animation, so a whole recording can be checked at once.

## 5. What went wrong, and how it works inside

The design of the session (the far monitor, the virtual pointer and keyboard, the disabled host input, the guard, the noise filter) and what went wrong on the way to it (a window under the real pointer, a reused socket name, `pgrep -f` matching itself, a detached launch holding a pipe open, ffprobe reading one frame of an AVIF) are in the devkit: [how-it-works.md](../scripts/devkit/docs/how-it-works.md). Two lessons are this app's own:

- **A recorder must never walk a cloud mount.** `TOUR_REAL_UNCHANGED` fingerprints its paths recursively, and `~/Cloud` was once listed there: the recorder spent minutes walking the user's live Google Drive (slow, and it spends the API quota the README warns about) and looked hung. Nothing that holds a mount goes in that list; the fingerprint uses `find -xdev`, and the devkit's lint fails a tour that names one.
- **Icons lost in an edit.** Private-use glyphs in QML were dropped when files were rewritten, leaving `iconText: ""`; the check fails on it. Write icons as `\uXXXX` escapes.

## Where the files are

| Path | What it is |
|---|---|
| `scripts/check.sh`, `scripts/qmllint`, `qmllint-baseline.txt`, `.shellcheckrc` | the checks: wrappers of the devkit's `check` and `qmllint`, and their lists |
| `.githooks/pre-commit`, `.github/workflows/check.yml` | the hook (the kit's, installed by `pre-commit --install`) and the CI job (the kit's `app-check` workflow, with Node) |
| `tests/cli.sh`, `tests/*.test.js` | the command-line behaviour tests (demo mode) and the Node tests |
| `lib/demo.sh` | the fixture drives, and the refusing shims, of demo mode |
| `devkit.conf` | this app's settings for the devkit: the plugin, demo mode, the commands of `dev`, what a recording must not change |
| `scripts/devkit/` | the devkit, a submodule: the test session, the recorder, `sheet` and the lint rules. Not edited here: fix it in its repository, release, and move the pointer |
| `scripts/dev`, `scripts/tour.sh`, `scripts/sheet` | wrappers of the devkit's `dev`, `tour`, `sheet` |
| `scripts/reload`, `scripts/pointer` | wrappers of the devkit's, for the real desktop |
| `scripts/screenshots.sh`, `scripts/preview.sh` | the README screenshots and the marketplace picture |
| `scripts/tours/`, `scripts/hero.sh`, `scripts/clips.sh` | the tours ([recording-tours.md](recording-tours.md)) |
