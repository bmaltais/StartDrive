# UI standards

How StartDrive looks and behaves. **The shared rules are in the devkit: [scripts/devkit/docs/ui-standards.md](../scripts/devkit/docs/ui-standards.md)** (principles, windows, moving and resizing, remembered state, settings windows, applying settings, controls, words, notifications). Read it first. This file holds only where StartDrive differs from it or adds to it: its windows, its settings tables, its vocabulary, and the [decision log](#decision-log). Where the two disagree, the kit's wording wins unless this file says it is a difference.

**Both files are the source of truth for the UI.** If a change makes a design decision that neither covers, or goes against one, update the file it concerns in the same change and add a line to the [decision log](#decision-log) here. A UI change without a matching update is not finished.

## Differences from the shared rules

- **Failed settings.** The kit says a failed change is shown under the setting where the window can, otherwise as a notification. StartDrive splits it by kind: **a drive's setting says why under itself** (a red note), while **an app setting sends a critical notification** ("Setting was not applied" and the reason). Either way the control flips back on the read-back.
- **Accent.** Besides the one thing to do and the selected state, accent marks the state that matters here: mounted and moving.
- **The bar icon is on by default** here and off in StartAppImage; see [The bar icon](#the-bar-icon).
- **The manager has no search box** (see [The manager](#the-manager)); StartAppImage has one.

## Principle 8: never lose a file

The principles are the kit's; StartDrive adds an eighth. Anything that could drop an upload that has not finished says so first or is refused: clearing the cache waits for uploads, forgetting an account asks in a terminal and counts them.

The kit's fifth principle names this app's tools: the QML never edits files or runs `systemctl` or `rclone`; it asks `bin/startdrive`. A setting that exists in a window exists as a `set` or `setup` option.

## Windows

| Card | Width | Height | Moves | Resizes | Closes with |
|---|---|---|---|---|---|
| Manager | 640 (or the user's) | content, at least 300, up to 580 and the screen minus 80 | yes | yes | Esc, ✕, click outside |
| Settings window | 760 (or the user's) | 520 (or the user's), at most the screen minus 80 | yes | yes | Esc, ✕, click outside or on the dimmed manager |
| A drive's settings window | the settings window's | the settings window's | yes (same place as the settings window) | yes (same size) | Esc, ✕, click outside or on the dimmed manager |

- **Stacking.** The settings window and a drive's settings window float over the manager and only one of them is open at a time. Closing one returns the keyboard to the manager.
- **Opening a settings window while the manager is closed** (from the command line) opens the manager behind it.
- **Remembered state** is saved in `~/.config/startdrive/config` and read with `startdrive window`.
- **The terminal flows.** Signing in, forgetting an account, adding a remote and making your own Google key need a person at a keyboard (a browser, a confirmation, rclone's questionnaire), so they run in Omarchy's floating terminal and the card closes to get out of the way.

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

There are two, the app's and one per drive. `SetupView.qml` (the app's) and `SettingsView.qml` (one drive's) are thin files around the shared `SettingsWindow.qml`, as the kit describes; they share one size and position, so opening either puts the window in the same place. The window name is a drive's cloud icon and name, or "StartDrive", over "SETTINGS". A disabled setting says why in its hint ("Mount the drive to refresh its listing.", "Wait for 3 files to finish uploading.").

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

Opened from the cog on a row (or `s`, or `omarchy-shell io.github.bmaltais.startdrive settings <drive>`). The pages are `DriveModel.settingsPages`, so their wording and when a button is off are tested.

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

Each click runs `startdrive setup` (app) or `startdrive set` (drive) for that one setting; the rest is the kit's. A drive's setting shows its new value at once, and the next poll confirms it. For failure, see the [differences](#differences-from-the-shared-rules).

**Reset to defaults** (app settings) applies launcher entry, command line and bar icon on, size and position remembered. These values are the CLI's (`defaults` in `startdrive integration`), not written here or in the QML.

## Controls

The kit's. StartDrive's uses: the switch is also a drive's mount switch; the button is bordered for secondary (Connect, Add remote…), plain for a header action, and icon-only on a row with a tooltip; the field is not used by a drive's settings yet.

## Words

StartDrive's own, on top of the kit's:

- **Names.** The window is the **manager**; the others are the **settings window** and a drive's **settings**. A **drive** is a cloud account shown as a folder; **mounted** is when its folder is there. *Forget* an account (never "delete" or "remove": your files in the cloud are untouched). *Connect* signs in.
- **Verbs.** *Connect*, *Mount*, *Unmount*, *Open folder*, *Refresh*, *Clear*, *Forget…*, *Add remote…*, *Reset to defaults*. A trailing ellipsis only when the action asks for more input (a terminal, a questionnaire).

## The bar icon

**On by default** (see the decision log), switched in the settings window. It is the cloud glyph, at the end of the right section of the bar, and it is where sync status lives: an outline cloud when nothing is mounted, a cloud when drives are, an **upload cloud in accent** while files are on their way, and a **red alert cloud** when a mount failed or an upload could not be sent. "All synced" in the manager means it is safe to shut down; the icon is how you see it without opening anything. Left click opens or closes the manager (the same command as the launcher entry); right click looks at the drives again. It reads one word from `~/.cache/startdrive/status`, which the service rewrites whenever the state changes. StartAppImage has it off by default; here it is on because of the status above.

## Notifications

A problem is a system notification, once per problem and again if it returns: a drive that could not mount (critical), an upload that failed (critical), a shared Google key on a mounted drive (normal). Per drive, a **Notifications** switch turns them off. A failed app setting is a critical notification, because the settings window cannot show it in place.

## Verifying a UI change

Seen working in the test session ([testing.md](testing.md); it runs on demo drives, so click freely). Retake the README screenshots with `scripts/screenshots.sh` and `scripts/preview.sh` when the look changes, and the tour when a step of it changes ([recording-tours.md](recording-tours.md)).

## Shared UI code

The shared UI code is described in the kit's [Shared UI code](../scripts/devkit/docs/ui-standards.md#shared-ui-code): StartAppImage is the reference implementation, StartBar's settings window the reference design. StartDrive's copies are kept identical to StartAppImage's except for these additions, which belong upstream when the shared repo exists:

- `SettingsWindow`: the `action` field type (a button on the right), `titleGlyph` (an icon-font glyph where an app has no icon file), `initialPage` (the page `reset()` opens on).
- `SettingsWindow` search box and `Field`: `readOnly: !activeFocus` on the `TextInput` (marketplace review, see the decision log); belongs upstream so the other Start apps get it.
- `Switch.qml`: the switch pulled out of `SettingsWindow` so a row can use it too.

## Decision log

Newest first. One line each: what was decided, and why.

| Date | Decision | Why |
|---|---|---|
| 2026-10-17 | Text boxes (`Field`, the settings search box) are read-only until focused | Qt's `TextInput` re-reads the clipboard text on every clipboard change unless it is read-only; an idle box then never touches a foreign clipboard |
| 2026-10-15 | The shared parts of this file moved to the devkit's `ui-standards.md`; this file keeps only what is StartDrive's | Three apps carried three drifting copies of the same rules |
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
