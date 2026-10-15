# Recording tours

`screenshots/hero.avif` (the tour at the top of the README) and the clips beside it are recorded with the shared devkit's recorder, in the nested test session, on the demo drives of `lib/demo.sh`. How the recorder works, every variable and helper of a tour file, clips, human-like input, reading time and troubleshooting are in the devkit's guide: [scripts/devkit/docs/recording-tours.md](../scripts/devkit/docs/recording-tours.md). This page is what is StartDrive's own.

```sh
scripts/hero.sh              # records the hero, leaves the result in /tmp/hero.avif for a look
scripts/hero.sh --install    # records it and copies it to screenshots/hero.avif
scripts/clips.sh [CLIP...]   # the clips: manager, settings, app-settings (default: all three), installed in screenshots/
scripts/sheet /tmp/hero.avif # a contact sheet of a recording, to check the whole of it at a glance
```

`scripts/tour.sh` is the devkit's `tour` run for this checkout; `scripts/hero.sh` is a shortcut for `scripts/tour.sh scripts/tours/hero.sh`. It takes a few minutes. **Your mouse and keyboard stay yours** and nothing of yours is changed: the tour runs in a sandbox on demo drives (nothing real: no mounts, no accounts, no files of yours), behind a guard, and the recorder proves it left your real files alone. Cancel any time (the red strip's button, or Ctrl+C).

## What is StartDrive's

- **`devkit.conf`** (repo root): the plugin id and layer (`omarchy-startdrive`), demo mode for everything in the session (`DEVKIT_ENV=(STARTDRIVE_DEMO=1)`), the `devkit_sandbox` hook (the marker file that puts the CLI in demo mode, the first-run answer, and a refusal to start if a real drive's settings were copied in), what a recording must leave unchanged (`TOUR_REAL_UNCHANGED`: your real `shell.json`, config, systemd units, rclone config, launcher entry and CLI link), and `dev open | setup | settings DRIVE_ID | close`.
- **Never list a cloud mount** (anything under `~/Cloud`) in `TOUR_REAL_UNCHANGED`: the recorder fingerprints its paths by walking them, and walking a live drive is slow and spends its API quota. `scripts/lint-rules.sh` fails on it.
- **`scripts/tours/hero.sh`**: the story (every drive in one window, with what is uploading and how much room is left; a switch to mount one as a folder; per-drive settings that apply at once; the keyboard; the app's own settings, the bar icon among them; a window that opens where it was left). In the sandbox it changes the saved size and place of both windows (reset to the defaults), a mount, a cache setting and the read-only flag of the demo drives, and the bar icon.
- **Clips** (`manager-clip.sh`, `settings-clip.sh`, `app-settings-clip.sh`): each window cropped as `screenshots.sh` crops it (720x540 at 280,130 for the manager, 840x600 at 220,100 for the settings windows), 14 to 18 seconds, on a flat backdrop (`TOUR_BACKDROP=plain`), opened in `tour_setup` and ending on the page they began on so that they loop.
- **Coordinates** are the session's 1280×800 screen, and do not change from run to run because `tour_prepare` resets the windows' saved size and place; take a `scripts/dev shot` to read a pixel.

## Decision log

Newest first. Moved here from the UI standards, since they are about the recorder, not the UI.

| Date | Decision | Why |
|---|---|---|
| 2026-10-15 | The test session and the recorder come from the shared devkit (`scripts/devkit`, [omarchy-plugin-devkit](https://github.com/bmaltais/omarchy-plugin-devkit)), configured by `devkit.conf`, instead of a copy kept here | Three apps carried three drifting copies; the recorder here left 1.5 GB of frames in `/tmp` per run, and the session had no guard against the Start menus' power commands. One place fixes them now |
| 2026-10-15 | StartDrive adopted the recorder, with a tour that runs on the demo drives of `lib/demo.sh`, and `TOUR_REAL_UNCHANGED` fingerprints with `find -xdev` | Its old recorder (`record-hero.sh`) moved the real pointer and typed into the real panel on a virtual monitor. The nested session shares the user's systemd and keyring, so only demo mode makes a click safe; and a fingerprint that listed `~/Cloud` walked a live Google Drive and looked hung |
| 2026-10-15 | The old mode (a virtual monitor filmed while the real mouse and keyboard were driven) is removed; the nested session is the only mode, with no `--nested`, `--yes`, `tour_restore` or `TOUR_RESTART_SHELL` | It took over the maintainer's input and changed the real app; the nested session does neither, and two modes doubled the code to keep working |
| 2026-10-15 | The recorder films a session on the far virtual monitor and shows it in a view-only window, with no confirmation step | The visible nested window let the nested compositor choose the cursor image under the pointer ("interacting weird"); nothing real is used, and Cancel is always on screen |
| 2026-10-15 | No shield over the nested window; the session disables the host pointer and keyboard instead, and the window is not pinned | The shield showed a block cursor and the window could not be dragged |
| 2026-10-15 | `TOUR_REAL_UNCHANGED` fingerprints and a `TOUR_MAX_SECONDS` watchdog | A tour must prove it left the real files alone and must not run forever |
| 2026-10-15 | The README hero sits in a `<picture>`, so GitHub does not turn it into a link to the image file | A click on the animation opened its file page, which is not what a viewer expects of a demo. GitHub links a bare `<img>`; not one in a `<picture>` |
| 2026-10-15 | The README hero is an animated AVIF (`screenshots/hero.avif`, about 0.4 MB at crf 40), not a GIF (3.3 MB), with no fallback | It plays in the browsers we use (checked on the maintainer's Omarchy browser) and on GitHub, and is eight times smaller. A `.gif` result is still one setting away for places that cannot show AVIF |
| 2026-10-15 | Tour captions stay up long enough to read (150 words a minute plus a moment, never under 2.5 s), and the pointer waits for the average reading time (238 wpm) before it moves after a new caption | Humans read slowly, and a caption that vanishes or a pointer that moves while it is being read makes the tour hard to follow |
| 2026-10-15 | The tour recorder moves and types like a person (Fitts's-law timing, minimum-jerk speed, a curved route with correlated wobble, rare overshoot, log-normal key gaps), from published research and open-source emulators; the red strip's size and the nested window's place are computed from one set of numbers | A pointer that glides in straight lines and keys at fixed intervals look fake; the strip had been covering the top of the window |
| 2026-10-15 | The nested recording window has a Cancel button, and the screen is given back as soon as filming stops, with "Recording finished, building the GIF" instead of looking stuck | Someone watching must be able to stop it if something goes wrong, and about 30 s of GIF building looked like a hang |
| 2026-10-15 | The tour recorder gets a `--nested` mode: the tour runs in a second Hyprland shown as a window, in a sandbox, driven over its own Wayland socket | You can watch it, your mouse and keyboard cannot disturb it, and it never changes your real settings or files. It is opt-in until it has been used on more setups |
| 2026-10-15 | The tour recorder asks for confirmation in a centred red window (Proceed / Cancel), then shows its progress in it, instead of a flickering terminal banner | A recording takes over the pointer and keyboard; people must agree to it first and be able to see it is on |
| 2026-10-15 | The README leads with a recorded tour (`screenshots/hero.avif`, an animated AVIF) made by an app-agnostic recorder that reads a per-app tour file | A still shows a look, not how the app is used; one recorder keeps every Start app's tour alike |
