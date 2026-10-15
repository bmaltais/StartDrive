# Recording tours

How to record a short animation of a plugin being used, with `tour`: for a README, or a marketplace page. A recording is a story, not a feature list: one thing a person does per step, with a caption in plain words. Aim for about a minute and a half for a tour, and twenty seconds for a clip.

```sh
tour tours/hero.sh             # records it, leaves the result in /tmp/hero.avif for a look
tour tours/hero.sh --install   # records it and copies it to the tour's TOUR_OUT in your repo
bin/sheet /tmp/hero.avif       # one contact sheet of the whole recording, to check it at a glance
```

The tour runs in the [test session](testing.md), so **your mouse and keyboard stay yours** and nothing of yours is changed: a red strip along the top of your screen shows the step and has a **Cancel recording** button (Ctrl+C in the terminal does the same), and a view-only window shows the recording as it happens. Cancel and the run stops within a step, the sandbox is thrown away and nothing is kept. Do not run a tour and `dev` at the same time.

## What happens when you run it

1. **A far monitor** (`TOURTEST`, 1280×800) is created 20,000 px to the right of your screens.
2. **The sandbox** is built (a home with a minimal `shell.json` that loads the plugin from your checkout with the settings the tour starts from, links to your themes, the guard), and the tour's `tour_prepare` runs against it (`$HOME` is the sandbox).
3. **The nested session** starts and its shell comes up. The strip and the view window open on your screen.
4. `tour_setup` runs, then **filming starts**: `grim` takes a frame of the session over and over, each stamped with its time.
5. `tour_play` runs: the steps, moving a *virtual* pointer and typing on a *virtual* keyboard inside the session. Each `cap` shows a caption from then until the next one.
6. Filming stops and the session ends at once. The frames become a video, the captions are drawn on it with `ffmpeg`, and it becomes an AVIF or GIF (10 frames a second, 1000 px wide, or the width of the crop).
7. The recorder compares your real files (`TOUR_REAL_UNCHANGED`) with their fingerprints from before, and fails the run if any changed. The recording's frames (about 1.5 GB in `/tmp`) are removed. The same cleanup runs when you cancel, press Ctrl+C, or the run passes `TOUR_MAX_SECONDS`.

## Writing a tour

```bash
# shellcheck shell=bash
TOUR_OUT=screenshots/example.avif     # where --install puts the result; .avif or .gif picks the format

tour_play() {
  cap "Open the card"
  omarchy-shell io.example.hello open   # omarchy-shell, hyprctl and grim act on the nested session here
  wait_until "layer_up omarchy-hello" 20
  sleep 1.5
  cap "Click the button"
  click 640 446 1.2
}
```

`examples/hello/tours/hello.sh` is a complete one. The plugin's id and settings come from `devkit.conf`; a tour file may override them.

1. **Ask the plugin where things are**, instead of hard-coding pixels: an IPC `layout` returning rectangles of the screen (`omarchy-shell ID layout | jq …`). Where a window opens at a fixed place, read the pixels off `dev shot`, and reset anything remembered (a saved window size or place) in `tour_prepare`.
2. **Keys go only where the window is up.** `typed`, `esc` and `pressed` send keys only while the plugin's window is mapped (`DEVKIT_LAYERS` or `TOUR_LAYER`), or while `tour_keys_ok` says so, so keys can never land on anything else.
3. **Look at it, and tune the timing.** Run without `--install`, then `bin/sheet /tmp/example.avif --every 4`. Give each caption enough time to be read (the recorder holds it for its reading time), let animations finish before the next click, and use `wait_until` for what takes as long as it takes, not a fixed `sleep`.
4. **Make changes safe.** The tour runs in a sandbox, so what it changes is thrown away. Anything it must not touch is listed in `TOUR_REAL_UNCHANGED` (paths under your real `$HOME`): the recorder fingerprints them before and after and fails the run if one changed. Data the tour changes goes in `TOUR_SANDBOX_COPY`.
5. **Windows for the plugin to show** can be terminals posing as apps: `foot -a org.gnome.Nautilus -T Documents …` in the session gets the Files icon from the plugin. Put each on a workspace of its own (`hl.dsp.window.move({ workspace = "2", follow = false, … })`) so they do not cover the wallpaper, then switch to those workspaces and back so no window is "active".

## Clips

A tour with `TOUR_CROP=WxH+X+Y` keeps only that box of the session's screen, so a short tour of one part of a plugin can stand in for a still image in a README. No captions (the crop is small), and start and end on the same picture so the animation loops. A flat backdrop (`TOUR_BACKDROP=plain`, a full-screen `imv` window) suits a plugin whose windows are overlays; it hides a layer below it, so a bar or dock keeps the wallpaper.

## Reference

### Variables a tour file sets

| Variable | Meaning | Default |
|---|---|---|
| `TOUR_TITLE` | The app's name, for the strip (`devkit.conf` or `DEVKIT_NAME`) | |
| `TOUR_PLUGIN_ID` | **Required** (`devkit.conf`). The plugin's id, to load in the sandbox | |
| `TOUR_PLUGIN_ENTRY` | A JSON object merged into the plugin's entry in the sandbox's `shell.json`: the settings and Pins it starts with | `{}` |
| `TOUR_PLUGIN_WIDGET` | `0` for a plugin with no bar widget (a service): loaded, not put on the Omarchy bar | `1` |
| `TOUR_OUT` | The result's path in the repo, used by `--install`. Its extension picks the format: `.avif` (animated AVIF) or `.gif` | `screenshots/hero.avif` |
| `TOUR_LAYER` | The app window's layer-shell namespace; needed for `typed`, `esc` and `pressed` unless the tour defines `tour_keys_ok` | none |
| `TOUR_STEPS` | How many steps (`cap` calls), for "Step 2 of 6" | unknown |
| `TOUR_SIZE` | The session's screen, `WxH` | `1280x800` |
| `TOUR_CROP` | `WxH+X+Y`: keep only that box of the screen, for a clip | the whole screen |
| `TOUR_BACKDROP` / `TOUR_BG` | `plain` puts a flat colour over the wallpaper (see Clips) | the wallpaper |
| `TOUR_SANDBOX_COPY=(path …)` | Paths under `$HOME` to *copy* into the sandbox | none |
| `TOUR_SANDBOX_LINK=(path …)` | Paths under `$HOME` to *link* read-only (the icons) | none |
| `TOUR_REAL_UNCHANGED=(path …)` | Paths under your real `$HOME` that must not change: fingerprinted (name, size, mtime) before and after; a difference fails the run (exit 1) and keeps nothing | none |
| `TOUR_MAX_SECONDS` | Stop a tour that runs longer than this, as a stuck step would | `300` |
| `TOUR_FONT` | The caption font file | JetBrains Mono Nerd Font Bold |
| `TOUR_GIF_WIDTH` | The width in pixels of the result, whichever format (10 frames a second) | `1000`, or the width of `TOUR_CROP` if smaller |
| `TOUR_AVIF_CRF` | AVIF quality, lower is sharper and bigger | `40` |
| `TOUR_GIF_COLORS` | For a `.gif` result: its palette size | `128` |
| `TOUR_KEEP_TMP` | `1` keeps the run's folder (frames, the session's log) in `/tmp`, for looking at a run that went wrong | `0` |

### Functions a tour file defines

| Function | Runs | Use it to |
|---|---|---|
| `tour_requires` | first, with your real home | check what the tour needs; print a reason and return non-zero if it is missing |
| `tour_prepare` | before the session starts, with `$HOME` the sandbox | reset to a known state |
| `tour_sandbox DIR` | while the sandbox is built (optional) | adjust the copies |
| `tour_setup` | once the session is up, just before filming | make the changes that must be visible in the film. The recorder's helpers (`wait_until`, `layer_up`, `glide`, `cap` ...) do not exist yet: use plain shell, `hyprctl` and your own functions |
| `tour_keys_ok` | before each key | say whether the window is up |
| `tour_play` | while filming. **Required** | the steps |

### Helpers for `tour_play`

| Helper | Does |
|---|---|
| `cap "text"` | Shows this caption, at the bottom, from now until the next `cap`. Also updates the strip. Avoid `:` and `'` in the text (they are special to `ffmpeg`). |
| `glide X Y` | Moves the pointer there in small steps, so it is seen to travel. Over something that opens on hover, it opens after its delay. |
| `click X Y [pause]`, `rclick X Y [pause]` | Glides there, clicks with the left or right button, then waits `pause` seconds (default 0.9). |
| `scroll X Y N [pause]` | Glides there and turns the wheel N notches (positive: down). |
| `drag DX DY` | Presses the button where the pointer is, moves by that much, lets go. |
| `typed "text"` | Types it, slowly enough to be seen. |
| `esc`, `pressed KEY` | Presses Escape, or that key (`Return`, `Down`, `BackSpace` ...). |
| `wait_until 'command' [seconds]` | Polls a shell command until it succeeds, up to `seconds` (default 30). |
| `at X Y` | Puts the pointer there at once. |
| `W`, `H`, `TMP`, `REPO`, `TOUR_DIR` | The session's size, a scratch folder, the app's root, the folder the tour file is in. |

Other commands in `tour_play` are ordinary shell: `hyprctl`, `omarchy-shell` and `grim` act on the nested session, so a tour file works out paths when it uses them (`$HOME/…` inside a function), not when the file loads.

## How it works inside

The same as the test session ([how-it-works.md](how-it-works.md)), plus:

- **Frame timing.** The frames are joined with `ffmpeg`'s concat demuxer, each shown for the time until the next one, so the video plays at the speed things really happened even though grabs take a variable time. **Captions** are drawn by `drawtext`, each enabled between the time it was said and the time of the next.
- **The result** is an **animated AVIF** by default (AV1 video in an image file, made with `libaom-av1`; `TOUR_AVIF_CRF`) at 10 frames a second: the hero is about 0.5 MB, a GIF of it several times that. It plays in an `<img>` in modern browsers, and GitHub serves it as `image/avif`. A `.gif` (`TOUR_OUT=....gif`) is the fallback for anywhere that cannot show AVIF. **ffprobe shows an AVIF's first image only** (the still cover); the animation is the second video stream, so use `ffprobe -f mov` or `-map 0:v:1`.
- **The red strip** (`lib/tour-banner.qml`), run by `quickshell` as its own small instance: a top-anchored, always-on-top layer-shell window on your real monitor, with a **Cancel recording** button (it writes a file the recorder watches) and a text file the recorder rewrites at each step. It turns green at the end and grey when cancelled.

## Troubleshooting

- **"window not up, skipped keys …"**: the plugin's window was not up when the keys were due. A step before it did not open it, or closed it (a single Escape may close a window that has nothing to back out of). Fix the earlier step; use `wait_until` rather than `sleep` if the window can be slow.
- **Clicks miss**: the layout is not what you measured. Ask the plugin where things are (an IPC `layout`) rather than hard-coding pixels, and reset anything remembered (a saved window size or place) in `tour_prepare`.
- **The film is on the wrong workspace after a hover**: a posed window was left as the active window; switch to its workspace and back ([how-it-works.md](how-it-works.md#what-went-wrong-on-the-way-and-the-rule-it-left)).
- **The run is slow and the film shows the wallpaper**: `/tmp` was full. Look at `df -h /tmp`; a run removes its frames now, an older recorder may not have.
- **A run was killed with `kill -9`**: the cleanup did not run. `hyprctl output remove TOURTEST`, and stop the leftovers: the `quickshell` running `tour-banner.qml` and `dev-view.qml`, and the nested Hyprland (they carry the sandbox's `XDG_CONFIG_HOME`, see `nested_procs` in `lib/session.sh`). Nothing of yours needs restoring. Remove the run's folder in `/tmp` by hand (`TOUR_KEEP_TMP` or a killed run leaves it).
- **The AVIF is too big**: shorten the tour, raise `TOUR_AVIF_CRF`, or lower the width.
- **A step waits forever**: `TOUR_MAX_SECONDS` ends the run and says so.

## Human-like input

People do not move a mouse in straight lines at a steady speed or type at metronome intervals, and an animation of a robot looks fake. By default (`TOUR_HUMAN=1`) the recorder moves and types the way the research and the existing emulators describe. `TOUR_HUMAN=0` gives plain, even motion; `TOUR_SEED=N` makes the randomness repeatable.

**The pointer** (`glide`, `click`, `drag`; `lib/vptr.c`): movement time follows Fitts's law (0.15 + 0.12 · log2(distance / 40 + 1) seconds), speed the minimum-jerk curve (Flash & Hogan 1985), the route a cubic Bézier bowed to one side by at most about 15 px (as in [ghost-cursor](https://github.com/Xetera/ghost-cursor)), with correlated wobble like [WindMouse](https://windmouse.readthedocs.io/en/latest/algorithm.html), an overshoot of 2 to 5 px on a move over 500 px in about 30 % of cases, a landing within 2 px of the target, and a rest of 0.15 to 0.45 s before a click.

**Typing** (`type_chars`): each gap is log-normal (median 118 ms, never below about 60 ms), a little quicker when the next key is under the other hand, slower after a space. The figures come from Dhakal, Feit, Kristensson and Oulasvirta, ["Observations on Typing from 136 Million Keystrokes"](https://userinterfaces.aalto.fi/136Mkeystrokes/), CHI 2018. Not modelled: mistakes and corrections, key rollover, pauses to think.

## Reading time

A caption that vanishes before it can be read is useless, and a viewer reads a new caption before looking at what the pointer does. A caption is held at least 0.95 s plus its words at 150 a minute (`TOUR_READ_WPM`), and never under 2.5 s; the first pointer or key action after a caption waits 0.5 s plus its words at 238 a minute (`TOUR_LEAD_WPM`, the average silent reading rate for English adults, Brysbaert 2019). `0` turns either off. The tour prints the result for each caption (`tour: caption 3 (4 words) on screen 4.3 s (reading time 2.5 s)`).

## Putting it in a README

Put the image in a `<picture>` so that clicking it does nothing: GitHub wraps a plain `<img>` (and a Markdown `![](…)`) in a link to the image file, but not one inside `<picture>`. `width="100%"` keeps it within a narrow page, as `<picture>` loses GitHub's `max-width`.

```html
<p align="center">
  <picture>
    <img alt="What the tour shows" src="screenshots/hero.avif" width="100%" />
  </picture>
</p>
```
