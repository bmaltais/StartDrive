# How it works, and what went wrong on the way

```
dev ──► lib/session.sh ──► Hyprland (nested) ──► quickshell: the Omarchy shell + your plugin
 │        (sandbox, guard, start, stop)    │ a window of your compositor, moved to a virtual monitor
 │                                         │   at x = 20000, which a real pointer cannot reach
 ├─ click, move, rclick, scroll ► lib/vptr (a virtual-pointer client) on the session's socket
 ├─ type, key ───────────► wtype (virtual keyboard), on the session's socket
 ├─ shot ────────────────► grim, on the session's socket
 ├─ ipc, dev_cmd_* ──────► omarchy-shell, on the session's socket (the plugin's IPC)
 └─ errors ──────────────► the session's shell log, filtered
```

- **`lib/session.sh`** builds the sandbox home (Omarchy's themes copied, a `shell.json` that keeps your bar layout but only Omarchy's own widgets, with the plugin's entry holding `TOUR_PLUGIN_ENTRY`, the plugin linked to the checkout), builds the guard, starts the nested Hyprland under its own D-Bus that starts nothing, and stops everything it started. `dev` and `tour` both source it.
- **Input.** `lib/vptr.c` is a tiny client of the `wlr-virtual-pointer` protocol (built on first use into the session's folder; it can move, click, right-click, scroll and drag). Keys use `wtype`. Both talk to the nested compositor's socket, so nothing reaches your real seat. The virtual pointer produces real motion, so a hover opens a popup the way a real mouse's does.
- **Your mouse and keyboard are switched off inside the session.** The host seat gives the nested compositor two devices, `wl_pointer` and `wl_keyboard`; its config disables both (`hl.device({ name = ..., enabled = false })`). The virtual devices are separate and keep working.
- **The far monitor.** `up` creates a headless monitor 20,000 px to the right and moves the window there. Sliding a mouse off the edge of your screen stops at the edge, so the window cannot be reached. `down` removes the monitor.
- **The shell starts last.** Hyprland starts the session's shell only once the window has its final size (`nested_send_away` creates a file the start waits for). Started earlier, the shell keeps reporting the window's first size as its screen's, and a plugin that works out where things are from its screen then answers with pixels that are wrong by the difference.
- **The noise filter.** `dev errors` and `dev reload` count only lines that name the plugin (`TOUR_PLUGIN_ID`) and carry a warning or error, minus known noise (layout "recursive rearrange", "Local plugin changed", qmlscanner, portal, `qt.svg`, and `DEVKIT_NOISE`). Omarchy's own errors are not the plugin's and are not counted.
- **The recorder** (`bin/tour`) films the same session: a `grim` frame over and over, each stamped with its time, joined with `ffmpeg`'s concat demuxer so the video plays at the speed things really happened, captions drawn with `drawtext`, the result an animated AVIF or a GIF. A red strip (`lib/tour-banner.qml`) with a Cancel button sits on your screen while it films, and the run's frames (about 1.5 GB) are removed when it ends.

## The guard

The session shares your user's systemd, login session and system bus. So it runs with a guard first on its `PATH` (`sandbox_guard` in `lib/session.sh`):

- **Refused whatever the arguments:** `omarchy-system`, `omarchy-system-lock`, `-sleep-lock`, `-sleep-monitor`, `-lid-close`, `-lid-inhibit`, `-wake`, `-factory-reset`, `-factory-reset-finish`, `poweroff`, `reboot`, `shutdown`, `halt`, `hyprlock`, `uwsm`, and whatever `DEVKIT_GUARD_EXTRA` adds. (`omarchy-system-lock` also kills the screensaver and locks 1Password, whichever session runs it.)
- **Refused for the verbs that act on the machine or the login session, passed on for anything else:** `systemctl` (`poweroff`, `reboot`, `suspend`, `hibernate`, `hybrid-sleep`, `halt`, `kexec`, `rescue`, `emergency`, `exit`, `isolate` ...) and `loginctl` (`lock-session`, `terminate-*`, `kill-*`, `poweroff`, `reboot`, `suspend` ...). The shell reads unit states, so the rest must work.
- **Each refusal is written to `guard.log`** in the session's folder, and `dev status` counts them.
- **The session is not started unless the guard works** (`guard_check`). A login shell (which a plugin's `bash -lc` is, and which reads `/etc/profile`, and can rebuild `PATH`) is asked where each of the commands is, and the check stops if one is not the guard's. Then five commands are run in *probe mode*: the `systemctl` and `loginctl` stand-ins never pass a command on, so a verb the guard fails to refuse is reported and **not run**: a wrong list cannot suspend the machine the check runs on. This was caught by breaking the list on purpose.
- **`GUARD_SYSTEMCTL` and `GUARD_LOGINCTL`** name the real programs, so a test can put a stand-in there (`tests/guard.test.sh` does).

## What went wrong on the way, and the rule it left

Each of these cost a round of testing; they are why the design is what it is.

- **Never put the nested compositor's window under a real pointer.** While a pointer is over it, the nested compositor chooses the cursor image: it hid the pointer, showed a hand, and left the pointer behaving oddly after a window drag. A transparent *shield* over the window cured the input but showed a "block" cursor and stopped the window being dragged. Hence the far monitor for the session and the separate view window for watching.
- **Do not change the nested compositor's cursor options at runtime** (`hl.config({ cursor = ... })` through `hyprctl eval`): it crashed the nested Hyprland.
- **A reused socket name hid the session.** The nested compositor's socket is `wayland-N` and the number is reused, so finding "the new socket" by a name that was absent before failed after an aborted cleanup left a stale file. It is found by being created after the start, and `down` removes its own socket and instance folder.
- **`pgrep -f` matches its own shell.** Find processes by an environment marker (`procs_with`) or use a `[x]` bracket pattern.
- **Plugin reload does not load QML.** Only a full shell restart does; `dev reload` does that restart, in the session.
- **A background process that keeps the caller's output open makes `dev up | tail` hang.** Every detached launch ends in `>/dev/null 2>&1 </dev/null`; `bin/lint` fails on one that does not.
- **A shell that starts before its window has its final size reports the wrong screen.** A plugin's `layout` put things 188 px left and 38 px high of where they were. The shell now starts after the resize.
- **A window moved off the workspace in view is still the "active window".** A plugin that puts focus back to the window that had it after a hover then switches to that window's workspace, and a film stays on the wrong workspace for good. After posing windows on other workspaces, switch to them and back (`hyprctl dispatch 'hl.dsp.focus({ workspace = "N" })'`), which clears it.
- **A recording left 1.5 GB in `/tmp`, and `/tmp` is memory.** A few runs filled it, and then everything that writes there failed, the session included (a recording that took 92 seconds took 153 and showed the wallpaper for a minute). `tour` removes its folder when it ends; `TOUR_KEEP_TMP=1` keeps it for a run that went wrong.
- **A `[[ x ]] && cmd` as the last line of a loop or function kills a `set -e` script** when the test is false. `sandbox_enter` did, and `dev up` exited with no message. Use `if`.
- **A recorder must never walk a cloud mount.** `TOUR_REAL_UNCHANGED` fingerprints its paths recursively (`find -xdev`); one that named a live drive spent minutes walking it and looked hung.
- **ffprobe reads one frame of an AVIF.** It shows the still cover image first; the animation is the second video stream (`-f mov -map 0:v:1`). `bin/sheet` does this for you.
- **A popup that closes itself a moment after it opens** (a plugin's, found in StartBar). A popup with a compositor grab (`grabFocus`) is sent a pointer enter at its corner the moment it opens, before the compositor has placed it, whether or not the pointer is near. Hover handling that treats that as "the pointer entered the menu" and the next motion as "left" closes the popup 300 ms later. It showed on a bar at the top or left edge, where the popup opens next to the pointer (probably why not on the others). The Wayland log shows it: run the session's shell with `WAYLAND_DEBUG=1` and read the `wl_pointer.leave`, `wl_pointer.enter` (at -0.0078,-0.0078) and `xdg_popup.configure` lines. The fix is in the plugin: ignore hover changes for the first quarter second after a popup opens.
- **A plugin that keeps state in a file of `$XDG_RUNTIME_DIR`** (a lock, a saved focus) shares it with your real shell: the session uses the same runtime directory, because the nested compositor needs your compositor's socket there. StartBar's Peek did, and a Peek in the session could restore the wrong workspace on the real desktop. Name such files for `$HYPRLAND_INSTANCE_SIGNATURE`.

## Limits

- **Hyprland only, and a newer Hyprland than 0.56 may change the Lua API** (`hl.dsp.window.move`, `hl.device`, `hl.monitor`) that `lib/session.sh` uses.
- **One session at a time** (a fixed state folder per app and monitor name). A `tour` and `dev` use different monitors but would race for the nested compositor's socket: do not run both.
- **One monitor.** A plugin with something per monitor needs the real desktop to try a second one.
- **The view window is a picture, not the session**: five frames a second, so a fast animation looks choppy.
- **`dev` has no drag** (`vptr` can; the recorder's `drag` uses it).
