# Contributing to StartDrive

## Layout

| Path | What it is |
|---|---|
| `manifest.json` | The Omarchy plugin manifest (a `bar-widget`) |
| `Panel.qml` | The bar widget: wiring, keyboard cursor, IPC |
| `DriveService.qml` | Data and every call to the CLI |
| `DriveRow.qml`, `Segmented.qml`, `ScrollTrack.qml` | The look of one drive, its choices and the scroll bar |
| `DriveModel.js` | The rules (status text, totals, cursor stops). No Quickshell imports, so Node tests it |
| `bin/startdrive`, `lib/*.sh` | The command line: state, mounts, sign-in, cache, settings |
| `systemd/startdrive@.service` | The mount unit |
| `tests/` | Node tests for the model, the CLI's input checks and the marketplace rules |

## Development install

Plugin folders may not contain symlinks, and the shell's watcher does not follow them, so copy the checkout in instead of linking it:

```sh
P=~/.config/omarchy/plugins/io.github.bmaltais.startdrive
mkdir -p "$P" && tar --exclude=.git --exclude=tests -cf - . | tar -xf - -C "$P"
omarchy plugin enable io.github.bmaltais.startdrive
omarchy restart shell
```

Re-run the copy after each edit and check `journalctl --user -t omarchy-shell` for QML warnings.

## Checks

```sh
git config core.hooksPath .githooks   # once per clone
npm run check                         # node tests, shellcheck, omarchy plugin validate
```

CI runs the tests and shellcheck. Before a release, confirm the marketplace rules: `omarchy plugin validate .`, no symlinks, a README and a LICENSE, and a namespaced id. Keep [docs/SECURITY.md](docs/SECURITY.md) true: any new dependency, command, file or privilege goes in it.

## README images

`screenshots/` holds the panel and tab shots, and `hero.gif`, the tour at the top of the README. `scripts/record-hero.sh --install` films the tour again on a temporary virtual monitor, so none of your own windows are in it; it moves the real pointer and types into the panel for about 40 seconds, and only looks (it never clicks a switch or changes a setting). It needs `ydotool` with a writable `/dev/uinput`, `grim` and `ffmpeg`, and the installed plugin must be the version you want to film. `preview.png`, the marketplace's picture, is a collage of the shots: `scripts/make-preview.sh` rebuilds it after you retake any of them.
