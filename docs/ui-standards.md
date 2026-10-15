# UI standards

How StartDrive looks and behaves, and why. The goal is that it feels like the rest of the Start family (StartBar, StartAppImage) and like Omarchy itself, so a person who knows one knows them all. StartAppImage is the reference implementation of the shared parts (the window, the settings window, the controls, the recorder); this file says how StartDrive uses them and where it differs on purpose.

**This file is the source of truth for the UI.** Read it before you change anything visible. If a change makes a design decision that is not covered here, or goes against something that is, update this file in the same change and add a line to the [decision log](#decision-log). A UI change without a matching update here is not finished.

Sizes are written the way the code writes them: `space(n)` is `Style.space(n)`, which follows the user's font and spacing scale. Never hard-code pixels, colours or fonts.

## Principles

1. **Follow the theme, always.** Colours, fonts, corner radius and spacing come from the shell (`Color`, `Style`, `Util.alpha`). Nothing is hard-coded, so the UI follows the Omarchy theme live. Muted text is the foreground at about 55% opacity, hairlines about 14%.
2. **Same as the family where they overlap.** The windows, settings window and controls are StartAppImage's, which copied StartBar's settings window. When this file and StartAppImage's disagree on a shared part, ask which is right and fix the other one.
3. **Changes happen when you make them.** No Apply buttons (see [Applying settings](#applying-settings)). A change that cannot be made says so, next to the setting, and goes back.
4. **The window you came from stays.** A window opened from another one floats over it; closing it brings the first back.
5. **Everything in the UI has a command-line equivalent.** The QML never edits files or runs `systemctl` or `rclone`; it asks `bin/startdrive`. A setting that exists in a window exists as a `set` or `setup` option.
6. **Say what will happen.** Every setting has a one-line hint, written as what the setting does, in the present tense.
7. **Quiet by default.** Rarely used or destructive actions are small buttons, never the loudest thing. Colour (accent) is for the state that matters (mounted and moving, selected) and for the one thing to do.
8. **Never lose a file.** Anything that could drop an upload that has not finished says so first or is refused: clearing the cache waits for uploads, forgetting an account asks in a terminal and counts them.

## Windows

Every window is a card on a full-screen layer-shell overlay with a dimmed scrim. The card has the menu background, a hairline border at 14% foreground, the theme radius and a soft shadow.

| Card | Width | Height | Moves | Resizes | Closes with |
|---|---|---|---|---|---|
| Manager | 640 (or the user's) | content, at least 300, up to 580 and the screen minus 80 | yes | yes | Esc, ✕, click outside |
| Settings window | 760 (or the user's) | 520 (or the user's), at most the screen minus 80 | yes | yes | Esc, ✕, click outside or on the dimmed manager |
| A drive's settings window | the settings window's | the settings window's | yes (same place as the settings window) | yes (same size) | Esc, ✕, click outside or on the dimmed manager |

- **Dismissing.** Esc closes only the topmost window. In a settings window's search box, Esc clears the text first. A click on the scrim closes the topmost window.
- **Stacking.** The settings window and a drive's settings window float over the manager, which stays visible behind them under a 35% dark veil. Only one of them is open at a time. Closing one returns the keyboard to the manager.
- **Opening.** The manager opens where the user last left it (see [Remembered state](#remembered-state)). Opening a settings window while the manager is closed (from the command line) opens the manager behind it.
- **Close button.** A ✕ in the top-right corner of every card, 8 from the edges.
- **The terminal flows.** Signing in, forgetting an account, adding a remote and making your own Google key need a person at a keyboard (a browser, a confirmation, rclone's questionnaire), so they run in Omarchy's floating terminal and the card closes to get out of the way.

### Moving and resizing (manager and settings window)

- **Move** by dragging the top strip of the card, 60 high, whatever is not a control. The pointer is an open hand over it and a closed hand while dragging. Controls in the strip (search box, buttons) keep their own behaviour.
- **Resize** from the bottom-right corner: a 22 square handle with a small two-line grip and the diagonal resize pointer. The top-left corner stays put. Double-click it to go back to the default size and centre.
- **Limits.** The manager is at least 480 by 300, the settings window 560 by 360, both at most the screen minus 40. At least a 60 strip of the card always stays on screen.
- **Maths.** A card is centred plus an offset, so a resize shifts the centre by half the change.

### Remembered state

Size and position of each window are saved in `~/.config/startdrive/config` (`WIN_*` for the manager, `SETUP_*` for the settings windows) and restored on the next open, even after a shell restart. Two switches control it, under **Window**: *Remember size* and *Remember position*. Switching one off forgets the saved value and opens centred, at the default size. They are read with `startdrive window` and written when a drag or resize ends.

## The manager

```
┌────────────────────────────────────────────────────────┐
│ ☁  StartDrive          [Unmount all] [⚙] [⟳]        ✕ │  header
│    2 MOUNTED · UPLOADING 3 FILES · 2.4 MB/S             │
│ DRIVES                                                  │
│ ┌────────────────────────────────────────────────────┐ │
│ │ ▣ Google Drive                    [📂] [⚙] [🗑] [●━]│ │  one row per drive
│ │   ● Uploading 3 files · 2.4 MB/s                    │ │
│ │   Holiday 2026.mov        61% · 1.9 MB/s · +2 more  │ │  what is moving now
│ │   ━━━━━━━━━━━━━━━──────────                         │ │
│ └────────────────────────────────────────────────────┘ │
│ [+ Add remote…]                          Esc to close ◢│  footer
└────────────────────────────────────────────────────────┘
```

- **Header.** The cloud icon, the name, a count line in small capitals ("2 MOUNTED · ALL SYNCED", "NO ACCOUNTS CONNECTED"; red while something failed), then **Mount all** or **Unmount all** (only with more than one drive connected), settings (gear) and look again (refresh, spinning for a moment after a click). The close button is in the corner.
- **No search box.** There are a handful of drives, not dozens, so a search pill would only push them down; the keys below reach any of them in one or two presses. (StartAppImage has one because it can list many apps. If a drive list ever grows past a screen, add it there and here together.)
- **Row (62 high at least, 8 apart).** A tile with the drive's cloud (dimmed until it is connected), the name, a status dot and line, then the buttons: open folder (only while mounted), settings, forget, and the mount switch. A drive that is not connected has a **Connect** button instead. A click anywhere else on the row does its main action: connect, open the folder, or mount. The row under the keyboard cursor has an accent border.
- **Status.** The dot is accent when synced or working (pulsing while it works), red when failed, muted otherwise. The line says it in words: "Not connected", "Connected · not mounted", "Mounting…", "Mounted · synced", "Uploading 3 files · 2.4 MB/s", "2 files failed to upload", "Mount failed · retrying", "Shared Google key · may freeze". The words come from `DriveModel.driveStatus`, which is tested.
- **What is moving.** While files upload the row shows the first one (middle-elided name, percent, speed, "+N more") above a slim progress bar. Otherwise, once the drive reports it, a slim storage meter (red above 90%) and "6.4 GB of 276 GB". File names come from the cloud and are drawn as plain text.
- **Switch.** The family's 42 × 24 switch. It pulses while the mount or unmount runs and the row's controls wait.
- **Footer.** **Add remote…** on the left (it opens rclone's questionnaire for any other backend, so it has the ellipsis), the latest message or "Esc to close" on the right, the resize grip in the corner. A message stays six seconds; an error is red. A config that is not keyring-encrypted gets its own red line above the footer.
- **Empty.** With no account connected the list still shows the three built-in drives with their Connect buttons, and a line says where drives will appear (`~/Cloud`).
- **Keyboard.**

| Key | Does |
|---|---|
| Up, Down, `k`, `j` | Move the cursor |
| Enter | The row's main action |
| `m` | Mount or unmount (connect, if not connected) |
| `o` | Open the folder |
| `s` | The drive's settings |
| `f` | Forget the account |
| `a` | Mount or unmount all |
| `r` | Look at the drives again |
| `n` | Add a remote |
| Esc | Close |

  Every key has its letter in the tooltip of the button it matches ("Settings  (s)"). The letters are `DriveModel.keyAction`, which is tested, so a key and a click cannot disagree.

## Settings windows

There are two, the app's and one per drive, and they are the same component: `SettingsWindow.qml` draws the header, page list, rows and footer; `SetupView.qml` (the app's) and `SettingsView.qml` (one drive's) only say what the pages and settings are. A new settings window is a new thin file around `SettingsWindow`, never a new layout. They share one size and position, so opening either puts the window in the same place.

Modelled on StartBar's settings window.

```
┌──────────────────────────────────────────────────────────┐
│                  ( 🔍 Find a setting )                  ✕ │  header, 60
│ ☁ OneDrive    │ Cache                                     │
│   SETTINGS    │                                           │
│  Behaviour    │ Cache limit        [1 GB][4 GB][10 GB]…   │
│ ▌Cache        │ The most local disk the cache may use.    │  rows
│  Maintenance  │ ───────────────────────────────────────── │
│  Account      │ Keep files           [6 h][1 d][3 d]…     │
│ ───────────────────────────────────────────────────────── │
│ Changes apply instantly · Esc to close                   ◢│  footer, 52
└──────────────────────────────────────────────────────────┘
```

- **Header (60).** A centred search pill, "Find a setting", with the magnifier glyph. While there is text, the right side lists matching settings from every page under "Search results", each group headed by its page name. No match says "No setting matches “…”."
- **Page list (190 wide, left).** The window name (a drive's cloud icon and name, or "StartDrive") in bold with a small-caps "SETTINGS" under it, the same title-over-small-caps pattern as the manager's count line. Then one 38 high row per page. The title block and the page heading beside it are 48 high. The current page has a 22% accent fill and a 3 wide accent mark on the left, and bold text. Hover is the shell's hover fill. A click clears any search.
- **Heading.** The page name, body size + 8, bold, on the row of the window name.
- **Body.** Scrolls when the page is taller than the window, with the [scroll bar](#controls) in a gutter that is always reserved, so the width never changes.
- **Setting row.** The label (body size) with its hint under it (caption size, 55% opacity), the control on the right, a hairline at 50% under each row. A **note** can sit under the control: muted for information, accent for a done action, red for an error.
- **Disabled setting.** Dimmed to 40%, not clickable, and the hint says why ("Mount the drive to refresh its listing.", "Wait for 3 files to finish uploading.").
- **Footer (52).** A hairline above it. On the left one muted line: "Changes apply instantly · Esc to close". On the right the window's pills, 30 clear of the resize grip.

### The app's settings

| Page | Setting | Control | Option for `setup` |
|---|---|---|---|
| General | App launcher entry | switch | `--launcher` |
| General | Command line | switch | `--cli` |
| Bar | Bar icon | switch | `--bar-icon` |
| Window | Remember size | switch | `--remember-size` |
| Window | Remember position | switch | `--remember-position` |

A new setting goes on the page it belongs to, or a new page if none fits. Add it to the `pages` list in `SetupView.qml` (label, hint, control, key) and to `flags`, add the `setup` option, add it to `integration`, and add a row to this table.

### A drive's settings

Opened from the cog on a row (or `s`, or `omarchy-shell io.github.bmaltais.startdrive settings <drive>`). The window title is the drive's cloud and name. The pages are `DriveModel.settingsPages`, so their wording and when a button is off are tested.

| Page | Setting | Control | Applies with |
|---|---|---|---|
| Behaviour | Mount at login | switch | `set autostart` |
| Behaviour | Read-only | switch | `set read-only` |
| Behaviour | Notifications | switch | `set notifications` |
| Cache | Cache limit | choice: 1, 4, 10, 20, 50 GB | `set cache-size` |
| Cache | Keep files | choice: 6 h, 1, 3, 7, 30 d | `set cache-age` |
| Maintenance | Refresh listing | button, off unless mounted | `refresh-listing` |
| Maintenance | Clear cache | button, off while files upload, hint says how much is on disk | `clear-cache` |
| Account | Use my own Google key | button, only on the shared key | `client-id` (terminal) |
| Account | Forget this account | button | `disconnect` (terminal) |

- **The shared Google key.** A drive on rclone's shared Google key opens its settings on the **Account** page, where the fix is, and its row says "Shared Google key · may freeze" in red. Why it matters is in [SECURITY.md](SECURITY.md).
- **Feedback.** What a change or button did is said under it: "Saved and applied.", "Saved. Applies at the next mount, since files are still uploading.", "Cache cleared." (accent), or why it failed (red). The plain "Saved." is not repeated.
- **Buttons that open a terminal** end in an ellipsis ("Set up…", "Forget…") and close the card, as they leave the window for a terminal.

### Applying settings

- **Instantly.** Each click runs `startdrive setup` (app) or `startdrive set` (drive) for that one setting. Clicks queue and run one at a time, in order, so a quick second click is never dropped.
- **Read back.** When the queue is empty the window reads the real state back, so a switch always shows what the system has. A drive's setting shows its new value at once, and the next poll confirms it.
- **Failure.** An app setting that fails is announced with a critical notification ("Setting was not applied" and the reason) and its control flips back on the read-back. A drive's setting says why under itself.
- **Window stays open.** Applying never closes the window.
- **Reset to defaults** (app settings). A soft pill. The first click turns it red and asks "Click again to reset everything" for 3 seconds; the second click applies the defaults: launcher entry, command line and bar icon on, size and position remembered. These values are the CLI's (`defaults` in `startdrive integration`), not written here or in the QML.
- **First run.** The settings window opens once, a few seconds after the plugin first loads, showing what is on now. The footer has **Not now** and an accent-filled **Enable recommended**. After the first change or **Not now** it never opens by itself again.

## Controls

All are inline components or small files in this repo and use only theme tokens. Where one is shared with StartAppImage it is the same file.

| Control | Look | Used for |
|---|---|---|
| **Switch** (`Switch.qml`) | 42 × 24 pill; accent when on, 25% foreground when off; round knob in the menu background, 3 inset; the knob slides 100 ms, but not while the page is first shown; pulses while `busy` | on/off settings, and a drive's mount |
| **Choice** | Row of segments 28 high, 2 apart; selected is accent-filled with menu-background text, others 8% foreground; caption size. With many or long options (`stacked`) the segments wrap across the full width under the label, 6 apart | one of a few or several options |
| **Action** | A pill on the right of a row, 32 high, 8% foreground fill, hover fill, caption size | a button in a settings window |
| **Field** (`Field.qml`) | Single-line text box, 34 high, 6% foreground fill, border brightens on focus. In a settings window it sits under its label at full width and commits on Enter or when it loses focus; Esc drops the edit | text input (not used by a drive's settings yet) |
| **Pill** (`SettingsPill.qml`) | 32 high, 8% foreground fill, hover fill, caption size; `primary` is accent-filled and bold; `danger` is 50% red | footer actions |
| **Button** | The shell's `Button`; bordered for secondary (Connect, Add remote…), plain for a header action, icon-only on a row with a tooltip | rows, header, footer |
| **Scroll bar** (`ScrollTrack.qml`) | 6 wide, soft track at 8%, rounded thumb at 28% that brightens on hover and press; drag the thumb or click the track; shown only when the list overflows | long lists and pages |

Rules of thumb: one accent-filled thing per screen; selected means accent; hover is the shell's hover fill; nothing animates longer than 160 ms (the status dot and a busy switch pulse, which tells you something is running).

## Words

- **Case.** Sentence case for labels and hints. Page names are one word.
- **Names.** The window is the **manager**; the others are the **settings window** and a drive's **settings**. A **drive** is a cloud account shown as a folder; **mounted** is when its folder is there. *Forget* an account (never "delete" or "remove": your files in the cloud are untouched). *Connect* signs in.
- **Verbs.** *Connect*, *Mount*, *Unmount*, *Open folder*, *Refresh*, *Clear*, *Forget…*, *Add remote…*, *Reset to defaults*. A trailing ellipsis only when the action asks for more input (a terminal, a questionnaire).
- **Search box.** "Find a setting" in the settings window.
- **Hints.** One or two short sentences, saying what happens. No "please", no exclamation marks.
- **Errors.** Say what happened and what to do. They appear next to what caused them, or as a notification when the window is gone.
- **Footer hint.** "Esc to close" appears at the bottom of every card that closes with Esc.

## The bar icon

Optional, **on by default** (see the decision log), switched in the settings window. It is the cloud glyph, at the end of the right section of the bar, and it is where sync status lives: an outline cloud when nothing is mounted, a cloud when drives are, an **upload cloud in accent** while files are on their way, and a **red alert cloud** when a mount failed or an upload could not be sent. "All synced" in the manager means it is safe to shut down; the icon is how you see it without opening anything. Left click opens or closes the manager (the same command as the launcher entry); right click looks at the drives again. It reads one word from `~/.cache/startdrive/status`, which the service rewrites whenever the state changes.

## Notifications

- **A problem.** A system notification, once per problem and again if it returns: a drive that could not mount (critical), an upload that failed (critical), a shared Google key on a mounted drive (normal). Per drive, a **Notifications** switch turns them off.
- **App setting failed.** A critical notification, because the settings window cannot show it in place.

## Verifying a UI change

A change is done once it has been seen working in the test session: see [testing.md](testing.md) (`scripts/dev`; it runs on demo drives, so click freely). Retake the README screenshots with `scripts/screenshots.sh` and `scripts/preview.sh` when the look changes, and the tour when a step of it changes ([recording-tours.md](recording-tours.md)).

## The README tour

`screenshots/hero.avif` is recorded by an app-agnostic recorder. Guide, tour-file rules and the recorder's decision log: [recording-tours.md](recording-tours.md).

## Shared UI code

The controls above, `SettingsWindow`, the drag-and-resize behaviour and the tour recorder (`scripts/tour.sh`) are meant to be shared by every Start app, so each does not keep its own copy. That is not done yet; the proposal is a shared `StartUI` repository copied into each app (git subtree). Until it exists, StartAppImage is the reference implementation and StartBar's settings window is the reference design; StartDrive's copies are kept identical to StartAppImage's except for these additions, which belong upstream when the shared repo exists:

- `SettingsWindow`: the `action` field type (a button on the right), `titleGlyph` (an icon-font glyph where an app has no icon file), `initialPage` (the page `reset()` opens on).
- `Switch.qml`: the switch pulled out of `SettingsWindow` so a row can use it too.
- `scripts/dev move`: park the pointer before a screenshot. `scripts/nested/session.sh`'s sandbox is demo mode instead of copies of app data.

## Decision log

Newest first. One line each: what was decided, and why.

| Date | Decision | Why |
|---|---|---|
| 2026-10-15 | The bar icon is on by default here, unlike StartAppImage | It shows whether files are still uploading, which is what decides if it is safe to shut down; and every existing user already has it on the bar |
| 2026-10-15 | The panel under the bar icon became a manager window, with a settings window per drive and one for the app, built from the family's components | One look and one behaviour across the Start apps; the panel's inline tabs held settings that now have room, search and feedback |
| 2026-10-15 | A drive's details became pages (Behaviour, Cache, Maintenance, Account) of its settings window; what is moving stays on the row | Settings belong in the settings window; what is happening belongs where you look at the drives |
| 2026-10-15 | `SettingsWindow` got an `action` field type | Refresh, clear and forget are things to do, not things to set, and a settings window had nowhere for them |
| 2026-10-15 | An action's answer ("Cache cleared.") shows under its button | The manager's footer, where it was first shown, is behind the dimmed overlay |
| 2026-10-15 | The manager has no search box | Four drives do not need one, and it would push the list down; keys reach any row in one or two presses |
| 2026-10-15 | A drive on the shared Google key opens its settings on the Account page | The fix is there, and a person who clicked the warning wants it |
| 2026-10-15 | The test session, screenshots and tours run on demo drives | A nested session shares the user's systemd, keyring and rclone config, so a click on a mount switch would mount a real account |
| 2026-10-15 | `startdrive setup` is now the app's settings (as in the other Start apps); the machine setup is `prepare` | One verb with one meaning across the family; `prepare` was only ever run by `connect` |
| 2026-10-15 | UI changes are tested in a nested session (`scripts/dev`), not on the real desktop | Clicks and restarts on the real shell moved the maintainer's pointer and typed into their windows; see [testing.md](testing.md) |
