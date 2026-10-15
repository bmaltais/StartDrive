## Agent skills

### Issue tracker

Issues live in GitHub Issues (bmaltais/StartDrive), via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Testing

- **`scripts/dev`**: test every UI change in the nested test session, out of reach of the user's pointer and keyboard and of their real drives (it runs on the demo drives of `lib/demo.sh`). `scripts/dev up` (leave the view window on: `DEV_WATCH=0` hides it), then `open`, `setup`, `settings DRIVE_ID`, `shot FILE` (look at it), `click PX PY`, `move PX PY`, `key NAME`, `type TEXT`, `errors` (0 = clean). After an edit, `scripts/dev reload` (4 s, loads uncommitted files). Finish with `scripts/dev down`. `scripts/dev --help` lists the rest.
- **`scripts/check.sh`**: shellcheck, `tests/cli.sh`, `node --test`, qmllint, manifest. Runs in the pre-commit hook (`git config core.hooksPath .githooks`); commits go on a branch, never `main`.
- **`scripts/reload [open | setup | settings DRIVE_ID] [--shot FILE]`**: after finishing a change, run it so the user sees it in their real shell: it copies this checkout over the installed plugin (a plain folder copy, no commit or push needed; the first time it keeps the old one in `~/.local/share/startdrive-dev/plugin-before-reload`), restarts the shell and reports QML errors. The user asked for this to be done for them after every update, so do it without asking; it never touches drives or mounts. `scripts/pointer.sh` moves their real pointer: only when asked.
- **Never run the real CLI against the real machine to test a UI change**, and never list a path under a cloud mount (`~/Cloud`) anywhere that walks files (`TOUR_REAL_UNCHANGED`): it spends the drive's API quota. Demo mode (`STARTDRIVE_DEMO=1`) is how to run the CLI safely.
- Full guide, with `scripts/sheet` and what went wrong before: `docs/testing.md`.

## UI standards

`docs/ui-standards.md` says how the UI looks and behaves and why. Follow it for any visible change. When a change makes a design decision, or goes against what it says, update that file in the same change and add a line to its decision log. UI work is done once seen working in `scripts/dev`. The windows, settings window and controls are shared with the other Start apps (StartAppImage is the reference implementation, StartBar the reference design): keep them identical, and note any addition in "Shared UI code".

## Recorder

`docs/recording-tours.md` before changing `scripts/tour.sh`, `scripts/tours/`, `scripts/tour-banner.qml` or `scripts/nested/`. `scripts/screenshots.sh` and `scripts/preview.sh` retake the README images.

