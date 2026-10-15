# Contributing to StartDrive

## Layout

| Path | What it is |
|---|---|
| `manifest.json` | The Omarchy plugin manifest (a `service` that stays loaded, plus an optional `bar-widget`) |
| `Service.qml` | State for the windows, the settings machinery, the IPC entry points, the bar icon's status file and the window |
| `DriveService.qml` | The drives: data, polling, and every call about them to the CLI |
| `ManagerView.qml`, `DriveRow.qml` | The manager and the look of one drive |
| `SettingsWindow.qml` | The settings window component: header, page list, rows, footer. Both settings windows are built on it |
| `SetupView.qml` | The app's settings: launcher entry, command line, bar icon, window memory |
| `SettingsView.qml` | One drive's settings: behaviour, cache, maintenance, account |
| `SettingsPill.qml`, `Switch.qml`, `Field.qml`, `ScrollTrack.qml` | The small controls |
| `BarWidget.qml` | The optional Omarchy bar icon |
| `DriveModel.js` | The rules (status text, totals, keys, the settings pages, notifications). No Quickshell imports, so Node tests it |
| `bin/startdrive`, `lib/*.sh` | The command line: state, mounts, sign-in, cache, settings, integration. It is the only part that touches the machine |
| `lib/demo.sh` | Demo mode: fixture drives, and nothing real is touched. What the test session runs on |
| `systemd/startdrive@.service` | The mount unit |
| `assets/` | The launcher and window icon |
| `screenshots/`, `preview.png` | Images used by the README and the marketplace; retake them with `scripts/screenshots.sh`, then `scripts/preview.sh` |
| `scripts/tour.sh`, `tours/`, `hero.sh`, `devkit.conf` | The tour recorder (the shared devkit's, in `scripts/devkit`) run for this checkout, and this app's tours; `devkit.conf` is what the devkit needs to know about the app. `screenshots/hero.avif` (the animation at the top of the README) is retaken with `scripts/hero.sh --install` when a step of the tour changes. The recorder is app-agnostic. See [docs/recording-tours.md](docs/recording-tours.md) |
| `scripts/check.sh`, `lint-sh.sh`, `lint-qml.py`, `.githooks/`, `.github/workflows/check.yml` | The checks, the pre-commit hook (`git config core.hooksPath .githooks` once per clone; it refuses commits on `main`) and the CI job |
| `scripts/dev`, `sheet`, `reload`, `pointer.sh` | Testing tools: a nested test session, the real-shell reload, a pointer click, contact sheets. See [docs/testing.md](docs/testing.md) |
| `tests/cli.sh`, `tests/*.test.js` | Command-line behaviour tests (demo mode) and Node tests for the model, input checks, upload safety and the marketplace rules |
| `docs/omarchy-plugins.md` | How Omarchy enables and loads this plugin, and what picks up each kind of change |
| `docs/testing.md` | How a change is checked and tried, and what went wrong before |
| `docs/ui-standards.md` | How the UI looks and behaves, and why. Read it before changing the UI, and update it when a design decision changes |
| `docs/SETTINGS.md`, `docs/SECURITY.md` | Every setting, and everything the plugin runs, installs and trusts. Keep SECURITY true: any new dependency, command, file or privilege goes in it |

The QML never touches the machine itself: it asks `bin/startdrive` and reads its JSON (`state`, `activity`, `about`, `integration`, `window`).

## Test it without touching your drives

```sh
scripts/dev up                    # a nested desktop, out of your mouse's reach, with a view window on your screen
scripts/dev open                  # open the manager there (also: setup, settings onedrive, close)
scripts/dev shot /tmp/a.png       # look at it, then click what you saw: scripts/dev click 826 387
scripts/dev errors                # 0 = clean
scripts/dev reload                # after an edit: loads uncommitted files
scripts/dev down
```

It runs on demo drives (`lib/demo.sh`), so a click on a mount switch or a forgotten account changes nothing real. UI work is done once seen working there. [docs/testing.md](docs/testing.md) has the rest, including `scripts/reload` for your real shell (ask first: it restarts it).

## Development install

To run it in your own shell, the plugin folder may not contain symlinks and the shell's watcher does not follow them, so the installed plugin is a plain copy of the checkout. One command makes it, restarts the shell and reports QML errors:

```sh
scripts/reload open      # or: setup, settings onedrive; add --shot FILE for a screenshot
```

It is a `service` with `keepLoaded`, so the shell keeps the running copy and does not reload it when a file changes: the restart is part of it. The first time, it keeps the old install in `~/.local/share/startdrive-dev/plugin-before-reload` (to go back: `rm -rf` the plugin folder, copy that one into its place, `omarchy restart shell`). `scripts/reload --check` says whether the installed copy matches the checkout. For a first install, `omarchy plugin add` or `omarchy plugin enable io.github.bmaltais.startdrive` once; if the manifest changed, `omarchy-shell shell rescanPlugins` first. Your drives and mounts are not touched: they live in systemd, rclone and the keyring.

## Checks

```sh
git config core.hooksPath .githooks   # once per clone
scripts/check.sh                      # shellcheck, CLI tests, node tests, qmllint, manifest, icons
```

The pre-commit hook runs `scripts/check.sh` and refuses a commit on `main`: work on a branch. CI runs the shell and Node parts (QML and the manifest validator need Qt and Omarchy). `qmllint` cannot see Quickshell's types, so its standing noise is in `scripts/qmllint-baseline.txt` and only a new warning fails; accept a real new name with `scripts/lint-qml.py --update` after reading what it adds. Before a release, confirm the marketplace rules: `omarchy plugin validate .`, no symlinks, a README and a LICENSE, and a namespaced id.

Write icons in QML as `\uXXXX` escapes: a file written through a tool that drops private-use glyphs leaves an empty `iconText`, and `scripts/check.sh` fails on it.

## README images

`screenshots/` holds the manager and the settings windows, and `hero.avif`, the tour at the top of the README. `scripts/screenshots.sh` retakes the stills in the nested session on the demo drives and `scripts/preview.sh` rebuilds `preview.png`, the marketplace's picture, from them. `scripts/hero.sh --install` films the tour again in the same kind of session: it takes about two and a half minutes, your mouse and keyboard stay yours, a red strip with **Cancel recording** shows on your screen, and it proves your real files are unchanged. Look at the result (`scripts/sheet screenshots/hero.avif`) before committing it. They need `foot`, ImageMagick, `ffmpeg` with `libaom-av1`, `grim`, `wtype` and a C compiler (for the pointer client); the recorder names any it cannot find.
