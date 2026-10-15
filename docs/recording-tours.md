# Recording tours

How to record a short animation that shows an app being used, with `scripts/tour.sh`. It made `screenshots/hero.avif`, the tour at the top of the README. The recorder is **not specific to StartDrive**: every Start app can use it, each with its own *tour file* that says what to do.

- [Run the StartDrive tour](#run-the-startdrive-tour)
- [What you need](#what-you-need)
- [What happens when you run it](#what-happens-when-you-run-it)
- [Writing a tour for an app](#writing-a-tour-for-an-app)
- [Clips of one window](#clips-of-one-window)
- [Reference](#reference)
- [How it works inside](#how-it-works-inside)
- [Troubleshooting](#troubleshooting)
- [Human-like input](#human-like-input)
- [Reading time](#reading-time)
- [The test session it runs in](#the-test-session-it-runs-in)
- [Using it in another Start app](#using-it-in-another-start-app)

## Run the StartDrive tour

```sh
scripts/hero.sh              # records it, leaves the result in /tmp/hero.avif for a look
scripts/hero.sh --install    # records it and copies it to screenshots/hero.avif
```

`scripts/hero.sh` is a shortcut for `scripts/tour.sh scripts/tours/hero.sh`. It takes a little over two minutes, of which the tour itself is about one. A red strip appears along the top of your screen with a **Cancel recording** button, and a view-only window below it shows the recording as it happens. **Your mouse and keyboard stay yours** and nothing of yours is changed: the tour runs in a sandbox. Cancel any time (the button, or Ctrl+C in the terminal): the run stops within a step, the sandbox is thrown away and nothing is kept.

Retake the tour when a step of it changes (a button moves, a label is renamed), and look at the result before you commit it: it clicks the real app at fixed places, so a changed layout makes it miss. `scripts/sheet /tmp/hero.avif` makes a contact sheet of it.

## What you need

- **Hyprland** (it uses its `hyprctl` and the `hl.*` Lua API of 0.56) on **Omarchy**, and you run the recorder from inside it.
- **Tools**: `hyprctl`, `jq`, `grim`, `ffmpeg` (with `drawtext`, and `libaom-av1` for an `.avif`), ImageMagick (`magick`), `quickshell`, `wtype`, `dbus-run-session`, and `gcc`, `wayland-scanner` and `pkg-config` with the Wayland client library (to build the pointer client on the first run; Arch: `wayland`, `wayland-protocols`, `gcc`). The recorder checks for them and says which one is missing. (`imv` too, for `TOUR_BACKDROP=plain`.)
- **The demo drives.** Nothing else needs installing: the tour runs on the fixture drives of `lib/demo.sh` (see [testing.md](testing.md#demo-mode-fixture-drives-and-nothing-real)), the same in every recording.
- A monitor tall enough for the strip and the view window (about 1,050 px).

## What happens when you run it

1. **A far monitor** (`TOURTEST`, 1280×800) is created 20,000 px to the right of your screens, out of reach of a real pointer.
2. **The sandbox** is built: a home with *copies* of what the tour file lists, a minimal `shell.json` that loads only this plugin (linked to your checkout, so it shows the code you are working on), and links to your themes. The tour's `tour_prepare` runs against it (`$HOME` is the sandbox).
3. **The nested session** starts: a second Hyprland and a second Omarchy shell (your bar layout, the theme's wallpaper) as a window of your compositor, which is sent to the far monitor. The red strip and the **view window** open on your screen.
4. `tour_setup` runs, then **filming starts**: `grim` takes a frame of the session over and over, each stamped with its time.
5. `tour_play` runs: the steps, moving a *virtual* pointer and typing on a *virtual* keyboard inside the session. Each `cap` shows a caption from then until the next one, and the strip shows the step.
6. Filming stops and the session ends at once. The frames become a video, the captions are drawn on it with `ffmpeg`, and it is turned into an AVIF or GIF (10 frames a second, 1000 px wide).
7. The recorder compares your real files (`TOUR_REAL_UNCHANGED`) with their fingerprints from before, and fails the run if any changed. The strip turns green and says the recording is saved. The same cleanup runs when you cancel, press Ctrl+C, or the run passes `TOUR_MAX_SECONDS`.

## Writing a tour for an app

A tour is a story, not a feature list: one thing a person does per step, with a caption in plain words ("One click to update"). Aim for under a minute.

### 1. A minimal tour file

This one opens StartDrive's manager and a drive's settings. It is a complete tour (add `TOUR_PLUGIN_ID` for the plugin to load, as `scripts/tours/hero.sh` does):

```bash
# shellcheck shell=bash
TOUR_TITLE=StartDrive                 # the app's name, for the banner
TOUR_OUT=screenshots/example.avif     # where --install puts the result; .avif or .gif picks the format
TOUR_LAYER=omarchy-startdrive         # the app window's layer-shell name (see below)

tour_play() {
  cap "Open the manager"
  omarchy-shell io.github.bmaltais.startdrive open
  sleep 1.5
  glide 640 300
  sleep 1

  cap "Open a drive's settings"
  click 826 387 1.2
  sleep 1.5
  esc; sleep 0.5
}
```

Run it with `scripts/tour.sh path/to/example.tour.sh` (add `--install` to copy the result to `TOUR_OUT`).

### 2. Find the window's layer name

Keys and typing are only sent while the app's window is up in the session, so they can never land on anything else. The recorder finds it by its layer-shell namespace, `TOUR_LAYER`. For a Quickshell plugin this is its `WlrLayershell.namespace`; it is also what `scripts/dev status` looks for when it says the window is open. Without `TOUR_LAYER`, `typed` and `esc` do nothing.

### 3. Find where to click

Coordinates are the session's screen, `0,0` at its top-left, 1280×800, and do not change from run to run **if the window opens the same way each time**. Make that so: reset anything remembered (a saved window size or position) in `tour_prepare`, which runs against the sandbox.

To read coordinates, use the test session ([testing.md](testing.md)): `scripts/dev up`, open the app, `scripts/dev shot /tmp/a.png` and look at it. The pixel you see is the coordinate you use. `scripts/dev click X Y` takes you to the next state; take a screenshot at every state the tour passes through, and write the coordinates down as you go. `scripts/dev down` when done.

### 4. Look at it, and tune the timing

Run without `--install`, then look at the result. A contact sheet shows every step at a glance: `scripts/sheet /tmp/example.avif --every 4`.

Give each caption enough time to be read (about 3 seconds for a short one), and let animations finish before the next click. Use `wait_until` for things that take as long as they take (a download), not a fixed `sleep`.

### 5. Making changes safe

The tour runs in a sandbox, so what it changes is thrown away. Anything it must not touch is listed in `TOUR_REAL_UNCHANGED` (paths under your real `$HOME`): the recorder fingerprints them before and after and fails the run if one changed. For data the tour changes, list it in `TOUR_SANDBOX_COPY` so the sandbox has its own copy. The StartDrive tour, for example, resets the windows' saved size and place, makes one app look a version behind, and switches the bar icon off and on, all in the sandbox's copy.

## Clips of one window

A tour with `TOUR_CROP=WxH+X+Y` keeps only that box of the session's screen, so a short tour of one window can stand in for a still image. `scripts/tours/settings-clip.sh` is the example: the settings window cropped as `screenshots.sh` crops it (840x600 at 220,100), about 18 seconds, 48 KB as an AVIF.

- **No captions**, or one: the crop is small. A clip is meant to be read as a picture.
- **Loop it.** Open the window in `tour_setup` (before filming) and end `tour_play` on the page the clip began on, so the loop has no jump.
- **Flat backdrop**: set `TOUR_BACKDROP=plain` and `TOUR_BG` in the tour file, as the stills have.
- Run it like any tour: `scripts/tour.sh scripts/tours/settings-clip.sh [--install]`. Each run starts its own session (about two minutes of set-up), so a clip costs about as much as the hero tour.

## Reference

### Variables a tour file sets

| Variable | Meaning | Default |
|---|---|---|
| `TOUR_TITLE` | The app's name, for the strip. **Required.** | |
| `TOUR_OUT` | The result's path in the repo, used by `--install`. Its extension picks the format: `.avif` (animated AVIF) or `.gif` | `screenshots/hero.avif` |
| `TOUR_LAYER` | The app window's layer-shell namespace; needed for `typed` and `esc` | none |
| `TOUR_STEPS` | How many steps (`cap` calls), for "Step 2 of 6" | unknown |
| `TOUR_SIZE` | The session's screen, `WxH` | `1280x800` |
| `TOUR_CROP` | `WxH+X+Y`: keep only that box of the screen, for a clip of one window (see [Clips of one window](#clips-of-one-window)) | the whole screen |
| `TOUR_BG` | With `TOUR_BACKDROP=plain`, the backdrop colour (default: the theme's wallpaper) | `#262a36` |
| `TOUR_PLUGIN_ID` | **Required.** The plugin's id, to load in the sandbox | |
| `TOUR_SANDBOX_COPY=(path …)` | Paths under `$HOME` to *copy* into the sandbox: the data the tour changes (e.g. `.local/share/myapp`; StartDrive's tour copies nothing, since it runs on fixture drives) | none |
| `TOUR_SANDBOX_LINK=(path …)` | Paths under `$HOME` to *link* read-only (e.g. icons) | none |
| `TOUR_REAL_UNCHANGED=(path …)` | Paths under your real `$HOME` that must not change: fingerprinted (name, size, mtime) before and after; a difference fails the run (exit 1) and keeps nothing | none |
| `TOUR_MAX_SECONDS` | Stop a tour that runs longer than this, as a stuck step would | `300` |
| `TOUR_FONT` | The caption font file | JetBrains Mono Nerd Font Bold |
| `TOUR_GIF_WIDTH` | The width in pixels of the result, whichever format (10 frames a second) | `1000`, or the width of `TOUR_CROP` if smaller |
| `TOUR_AVIF_CRF` | AVIF quality, lower is sharper and bigger: 24 is 0.9 MB, 32 is 0.6 MB, 40 is 0.4 MB for the StartDrive tour | `40` |
| `TOUR_GIF_COLORS` | For a `.gif` result: its palette size. 64 posterizes a photo wallpaper; 256 is smoother but about 1.2 MB bigger | `128` |

### Functions a tour file defines

| Function | Runs | Use it to |
|---|---|---|
| `tour_requires` | first | check what the tour needs; print a reason and return non-zero if it is missing |
| `tour_prepare` | before the session starts, with `$HOME` the sandbox | reset to a known state |
| `tour_sandbox DIR` | while the sandbox is built (optional) | adjust the copies, e.g. give an app its own copy of a file the tour will overwrite |
| `tour_setup` | once the session is up, just before filming | make the changes that must be visible in the film |
| `tour_play` | while filming. **Required.** | the steps |

### Helpers for `tour_play`

| Helper | Does |
|---|---|
| `cap "text"` | Shows this caption, at the bottom, from now until the next `cap`. Also updates the strip. Avoid `:` and `'` in the text (they are special to `ffmpeg`). |
| `glide X Y` | Moves the pointer there in small steps, so it is seen to travel. |
| `click X Y [pause]` | Glides there, clicks, then waits `pause` seconds (default 0.9). |
| `drag DX DY` | Presses the button where the pointer is, moves by that much, lets go. The move is a little larger than asked, so check what it does. |
| `typed "text"` | Types it, slowly enough to be seen. |
| `esc` | Presses and releases Escape. |
| `wait_until 'command' [seconds]` | Polls a shell command until it succeeds, up to `seconds` (default 30). |
| `at X Y` | Puts the pointer there at once. |
| `W`, `H`, `TMP`, `REPO` | The session's size, a scratch folder and the repo root. |

Other commands in `tour_play` are ordinary shell: opening the app (`omarchy-shell … open`), `sleep`, reading files. `$HOME` is the sandbox while `tour_prepare`, `tour_setup` and `tour_play` run, and `omarchy-shell`, `hyprctl` and `grim` act on the nested session, so a tour file works out paths when it uses them (`$HOME/…` inside a function), not when the file loads. `tour_requires` runs with your real home, before the sandbox exists.

## How it works inside

- **A nested session**, because the real desktop is yours: the recorder must not touch it or be disturbed by it. Frames are taken with `grim` (cursor included) from the session's own Wayland socket, in a loop, each file named for the time it was taken. How the session is built, kept out of reach and watched: [the section below](#the-test-session-it-runs-in) and [testing.md](testing.md).
- **Frame timing.** The frames are joined with `ffmpeg`'s concat demuxer, each shown for the time until the next one, so the video plays at the speed things really happened even though grabs take a variable time.
- **Captions** are drawn by `ffmpeg`'s `drawtext`, each enabled between the time it was said and the time of the next.
- **The result** is an **animated AVIF** by default (AV1 video in an image file, made with `libaom-av1`; `TOUR_AVIF_CRF`, default 40) at 10 frames a second and 1000 px wide: 79 seconds of UI in about 0.4 MB. It plays in an `<img>` in modern browsers, and GitHub serves it as `image/avif` and keeps `<img>` and `<picture>` tags for it (tested on GitHub with a throwaway branch). A `.gif` (`TOUR_OUT=....gif`) is the fallback for anywhere that cannot show AVIF: a two-pass palette (`palettegen`, `paletteuse`), 128 colours (`TOUR_GIF_COLORS`), 3.3 MB for the same tour. Measured on one recording: for the GIF, lowering the frame rate saves little (10 to 6 fps: 4.7 to 4.0 MB, as only the changed parts of a frame are stored) while width and colours matter most (900 px: 2.8 MB; 64 colours: 3.5 MB but the photo wallpaper bands; 256 colours: 5.9 MB). A WebM is about 0.8 MB but a `<video>` of a repo file is not known to play in a GitHub README, and an animated WebP came out bigger than the GIF. **ffprobe shows an AVIF's first image only** (the still cover); the animation is the second video stream, so use `ffprobe -f mov` or `-map 0:v:1`.
- **The pointer and keys** are a virtual pointer (`scripts/nested/vptr.c`, the `wlr-virtual-pointer` protocol) and `wtype`, both on the session's socket, so nothing reaches your real seat.
- **The red strip** (`scripts/tour-banner.qml`), run by `quickshell` as its own small instance next to the Omarchy shell: a top-anchored, always-on-top layer-shell window on your real monitor, with a **Cancel recording** button (it writes a file the recorder watches) and a text file the recorder rewrites at each step. It turns green at the end and grey when cancelled. It redraws in place, so it does not flicker, and takes no keyboard focus. Notifications cannot do this job: they would show on whichever screen has focus.
- **Keys only when the app is up.** `typed` and `esc` check that the app's layer is mapped in the session first. Otherwise the keys would go to whatever else is there.

## Troubleshooting

- **"window not up, skipped keys …"**: the app's window was not up when the keys were due, so they were not sent. A step before it did not open the window, or closed it (a single Esc already closes some windows, so a second Esc has nothing to close). Fix the earlier step; use `wait_until` rather than `sleep` if the window can be slow.
- **Clicks miss**: the layout is not what you measured. The usual cause is a remembered size or position: reset it in `tour_prepare` (the sandbox's copy).
- **Toggles**: an `open` command that is a toggle closes the window when it is already up. Make sure of the state a step starts in.
- **Frames look empty or half-drawn at the start or end**: the first second is cut on purpose. Add a `sleep` at the start of the first step if the app needs longer to appear.
- **A run was killed with `kill -9`**: the cleanup did not run. `hyprctl output remove TOURTEST`, and stop the leftovers: the `quickshell` running `tour-banner.qml` and `dev-view.qml`, and the nested Hyprland (they carry the sandbox's `XDG_CONFIG_HOME`, see `nested_procs` in `scripts/nested/session.sh`). Nothing of yours needs restoring.
- **The GIF is too big**: shorten the tour, lower the frame rate or width, or reduce `max_colors` in the last `ffmpeg` command of `scripts/tour.sh`.
- **A "Process crashed: xdg-desktop-portal-hyprland" notice** ): a portal started inside the nested session and died when its compositor went. The recorder now gives the nested session a D-Bus that starts nothing by itself and stops its processes before the compositor, so this should not appear; if it does, `coredumpctl list` shows which process, and the notice (critical, so it stays up) can be cleared with `omarchy-notification-dismiss "Process crashed"`.
- **A step waits forever**: `TOUR_MAX_SECONDS` (default 300) ends the run and says so.

## Human-like input

People do not move a mouse in straight lines at a steady speed or type at metronome intervals, and a GIF of a robot looks fake. By default (`TOUR_HUMAN=1`) the recorder moves and types the way the research and the existing emulators describe. `TOUR_HUMAN=0` gives plain, even motion; `TOUR_SEED=N` makes the randomness repeatable for a run you want to reproduce.

**The pointer** (`glide`, `click`, `drag` in `scripts/tour.sh`, `scripts/nested/vptr.c`):

| What a person does | How it is modelled | From |
|---|---|---|
| Longer or smaller targets take longer | Movement time = 0.15 + 0.12 · log2(distance / 40 + 1) seconds, so a 100 px move takes about 0.3 s and a 1,100 px move about 0.9 s. The constants are typical mouse values I chose, not measurements of anyone | Fitts's law |
| Starts slowly, is fastest in the middle, arrives slowly | The position follows the minimum-jerk curve 10t³ − 15t⁴ + 6t⁵ | Flash & Hogan 1985 |
| A gently curved route, not an S | A cubic Bézier whose two control points are on the same side of the straight line, at most about 15 px off it | [ghost-cursor](https://github.com/Xetera/ghost-cursor) |
| Drifts a little as the hand moves | Correlated noise like WindMouse's "wind": each step's wind is the last one divided by √3 plus a small random kick, fading out near the target | [WindMouse](https://windmouse.readthedocs.io/en/latest/algorithm.html) |
| Overshoots a far target and corrects | A move over 500 px overshoots by 2 to 5 px in about 30% of cases, then settles back in three small steps (500 px is ghost-cursor's `overshootThreshold`) | ghost-cursor |
| Does not hit the exact pixel | The pointer settles within 2 px of the target, and clicks where it is | ghost-cursor (random point in the element) |
| Rests before clicking | A random 0.15 to 0.45 s pause | |

**Typing** (`type_chars`): one key at a time, each gap drawn from a **log-normal** distribution (median 118 ms, so a mean near 130 to 140 ms, like a fairly fast typist), never below about 60 ms, a little quicker when the next key is under the other hand (about 7%), a little slower when it is under the same hand (about 6%), and 35% slower after a space, where a person reads ahead. In a test of 408 gaps this gave a mean of 138 ms, a median of 123, a minimum of 64 and a skewness of 1.7. Those figures come from the study the model is built on:

- Dhakal, Feit, Kristensson and Oulasvirta, **["Observations on Typing from 136 Million Keystrokes"](https://userinterfaces.aalto.fi/136Mkeystrokes/)**, CHI 2018 ([paper](https://www.pokristensson.com/pubs/DhakalEtAlCHI2018.pdf)). Their 168,000 typists averaged 51.6 words per minute and a **mean inter-key interval of 238.7 ms (SD 111.6) with a lower bound near 60 ms**; the distribution is right-skewed (skewness 1.98); fast typists average about 120 ms; key presses last about 116 ms whoever is typing; and hand alternation predicts speed better than repeated letters. The tour deliberately types faster than the average person, so it reads well in a GIF.

**Not modelled** (so you know the limits): typing mistakes and corrections, key rollover (pressing the next key before releasing the last, which the study found in 25% of keystrokes), key-press duration, pauses to think, and a pointer that wanders while "resting". A step that waits (`sleep`) still waits exactly that long.

## Reading time

A caption that vanishes before it can be read is useless, and a viewer reads a new caption before looking at what the pointer does. Both are modelled from reading research, and both can be tuned:

| What | Rule | Default |
|---|---|---|
| **How long a caption stays up** (`TOUR_READ_WPM`) | Held at least 0.95 s (to notice it, plus the 0.15 s gap before the next) plus its words at 150 words a minute, and never under 2.5 s. A 10-word caption is up at least 5 s; a 14-word one 6.5 s. The tour waits out what is missing before the next caption. `0` turns it off | 150 |
| **How long the pointer waits before it moves** (`TOUR_LEAD_WPM`) | The first pointer or key action after a caption waits 0.5 s plus the caption's words at 238 words a minute (a little different each time, ×0.9 to ×1.2): about 3 s for 10 words. Opening a window is not input, so it appears with the caption and there is something to look at while reading. `0` turns it off | 238 |

The numbers come from:

- Brysbaert, **["How many words do we read per minute? A review and meta-analysis of reading rate"](https://www.gwern.net/doc/psychology/linguistics/2019-brysbaert.pdf)**, *Journal of Memory and Language*, 2019: 190 studies and 18,573 participants give an average silent reading rate for English adults of **238 words a minute** for non-fiction (260 for fiction), with most adults between 175 and 300; children, older adults and people reading in a second language are slower. The *lead* uses the average, the *hold* uses 150, well below the slow end, because a viewer is also following a moving picture.
- **Subtitle standards**, the closest everyday case of short text on a moving picture: the BBC's are described as 160 to 180 words a minute and Netflix's English guide as at most 20 characters a second for adults (17 for children), with a minimum of about 0.83 s per subtitle. I read these from secondary summaries ([Nimdzi](https://www.nimdzi.com/speed-in-audiovisual-translation/), [Titlevision](https://titlevision.dk/sm/reading_speed.htm)), not from the guides themselves, so check the current guides if you depend on the exact figures.

The tour prints the result for each caption (`tour: caption 3 (4 words) on screen 4.3 s (reading time 2.5 s)`), so you can see that every caption was up long enough. Reading time is why the StartDrive tour is about 75 seconds and not 50.

## The test session it runs in

The session is shared with `scripts/dev` ([testing.md](testing.md) has the full account); this is what matters for recording.

- **You can cancel it.** The red strip's **Cancel recording** stops the tour at once (within a step), throws the sandbox away, and turns the strip grey with "Recording cancelled"; nothing is kept. Ctrl+C in the terminal does the same, and so does the time limit (`TOUR_MAX_SECONDS`): the message says which one ended the run.
- **You can watch it.** The session's own window sits on a far virtual monitor (20,000 px to the right), which no real pointer can reach. What you watch is a **view-only window** (`scripts/dev-view.qml`, window class `startdrive-test-viewer`) centred on your screen, showing the session five times a second. Drag, resize or cover it: your pointer is the normal arrow over it and nothing in it listens. (A visible nested window had let the nested compositor choose the cursor image under your pointer.)
- **Your mouse and keyboard cannot reach it,** and it does not use them: the session also disables the two host input devices it is given (`wl_pointer`, `wl_keyboard`; `NEST_HOST_INPUT=1` keeps them), and the tour is driven by the virtual devices.
- **It changes nothing of yours, and proves it.** The sandbox home holds copies; `TOUR_REAL_UNCHANGED` fingerprints the real files before and after.
- **Nothing is left behind.** At the end everything the session started (its compositor, shell, its own D-Bus, file watchers), the view window and the far monitor are stopped or removed. The session has a D-Bus of its own that starts nothing by itself, so it does not launch portals that would crash and make Omarchy show a crash notice.

### What I know does not work or is untested

- A first run builds the pointer client; if the build fails the recorder stops with that message.
- Several monitors: the strip and the view window go on the monitor that was focused when you started. Not tested with more than one.
- The nested session is Hyprland-in-Hyprland. A compositor that is not Hyprland, or a Hyprland that changes its Lua configuration API, will need changes in `scripts/nested/session.sh`.
- The sandbox's home differs from yours, so a path shown in the UI (the mount folder, for instance) is the sandbox's full path rather than `~/Cloud`.
- A tour file must not edit `scripts/tour.sh` while a run is going: bash reads a script as it runs, and a run is garbled by a change.

## Using it in another Start app

The recorder has no StartDrive in it. To use it for another app:

1. Copy `scripts/tour.sh` into the app's repo (it will live in a shared repository when the Start apps get one, see "Shared UI code" in [ui-standards.md](ui-standards.md)).
2. Copy `scripts/nested/` and `scripts/dev-view.qml` too (the session). Write the app's tour file in its `scripts/tours/` (start from the minimal tour above, and copy `scripts/tours/hero.sh` for a worked example with `tour_prepare` and `TOUR_REAL_UNCHANGED`).
3. Set `TOUR_TITLE`, `TOUR_OUT` and `TOUR_LAYER`, find the coordinates, and run it without `--install` until it reads well.
4. Add `screenshots/hero.avif` (or wherever `TOUR_OUT` points) to the app's README, and a line to its contributing notes about retaking it. Put the image in a `<picture>` so that clicking it does nothing:

   ```html
   <p align="center">
     <picture>
       <img alt="What the tour shows" src="screenshots/hero.avif" width="100%" />
     </picture>
   </p>
   ```

   GitHub wraps a plain `<img>` (and a Markdown `![](…)`) in a link to the image file, so a click opens the file's page. It does not do that for an image inside `<picture>` (checked with GitHub's Markdown renderer). `width="100%"` keeps it within a narrow page, as `<picture>` loses GitHub's `max-width`.

## Lessons

- **Do not change the nested compositor's cursor options at runtime** (`hl.config({ cursor = ... })` through `hyprctl eval`): it crashed the nested Hyprland.
- **A transparent shield over the nested window** (tried first, to keep your pointer out) showed a "block" cursor and stopped the window being dragged. Disabling the host input devices replaced it.
- **A reused socket name** (`wayland-N`) hid the new session; it is found by being created after the start, not by a name that was absent.

## Decision log

Newest first. Moved here from the UI standards, since they are about the recorder, not the UI.

| Date | Decision | Why |
|---|---|---|
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
