# StartDrive settings and behaviour

The full reference. Everything here can be changed from a drive's settings window (the cog on its row in the manager), so you rarely need to use the command line or edit a file by hand. The settings of the app itself (launcher entry, command line, bar icon, window memory) are [further down](#the-apps-own-settings).

## Settings

Each drive has its own settings. They are saved per drive in `~/.config/startdrive/<Remote>.env` (mode 0600), as the rclone variables the mount unit reads, except mount at login, which is the state of the drive's systemd unit (`startdrive@<Remote>.service`).

```sh
# ~/.config/startdrive/GoogleDrive.env
RCLONE_VFS_CACHE_MAX_SIZE=10G
RCLONE_VFS_CACHE_MAX_AGE=72h
RCLONE_READ_ONLY=false
```

| Setting | Key | Default | Accepts | Stored as |
| --- | --- | --- | --- | --- |
| Cache limit | `cache-size` | `4G` | a size in `M` or `G`, 1 to 9999 (the settings window offers 1, 4, 10, 20 and 50 GB) | `RCLONE_VFS_CACHE_MAX_SIZE` |
| Keep files | `cache-age` | `72h` | hours, 1 to 99999 (the settings window offers 6 h, 1 d, 3 d, 7 d and 30 d) | `RCLONE_VFS_CACHE_MAX_AGE` |
| Read-only | `read-only` | `false` | `true` or `false` | `RCLONE_READ_ONLY` |
| Mount at login | `autostart` | `false` | `true` or `false` | the unit's enablement |
| Notifications | `notifications` | `true` | `true` or `false` | a `<remote>.quiet` file in `~/.config/startdrive` (present = off) |

A value outside these shapes is never written. A hand-edited file with one is read as if the line were missing, and the default is used.

### When a change applies

- **Mount at login** takes effect at once and does not touch a running mount.
- **The other three** are mount options, so a mounted drive has to restart for them. StartDrive restarts it straight away if nothing is uploading, and leaves it running otherwise: the setting is saved and applies at the next mount. The same goes when the upload queue cannot be read, since files not yet uploaded exist only in the cache.
- A drive that is not mounted just saves the setting.

### The command line

```sh
startdrive set <drive> <key> <value>
startdrive set google cache-size 10G
startdrive set onedrive read-only true
```

`<drive>` is `google`, `onedrive`, `dropbox`, or `r-<name>` for a remote you added. The script is `~/.config/omarchy/plugins/io.github.bmaltais.startdrive/bin/startdrive`; `startdrive --help` lists every command.

### Where each one is in the settings window

| Page | Settings |
| --- | --- |
| Behaviour | Mount at login, Read-only, Notifications |
| Cache | Cache limit, Keep files |
| Maintenance | Refresh listing, Clear cache |
| Account | Use my own Google key (only on the shared key), Forget this account |

A change applies the moment you make it, and what it did is said under the setting ("Saved and applied.", or why it could not be). Several quick changes are made one after another, in order.

## The app's own settings

The gear in the manager's header opens the app's settings window. Each is a switch, applied at once, and each has a `startdrive setup` option:

| Page | Setting | Option | Default |
| --- | --- | --- | --- |
| General | App launcher entry | `--launcher true\|false` | on |
| General | Command line (`~/.local/bin/startdrive`) | `--cli true\|false` | on |
| Bar | Bar icon | `--bar-icon true\|false` | on |
| Window | Remember size | `--remember-size true\|false` | on |
| Window | Remember position | `--remember-position true\|false` | on |

They are kept in `~/.config/startdrive/config`, along with where the windows were last left (`startdrive window` prints it) and whether the first-run offer has been answered. `startdrive integration` prints what is switched on, as JSON. The first time the plugin runs, the window opens once to offer the recommended set (**Enable recommended**) or to leave it (**Not now**). The command line link is never put over a file that is not StartDrive's.

## The cache

rclone keeps plaintext copies of recently used files, and the data of uploads not yet sent, in `~/.cache/rclone/vfs/<Remote>`.

- **Clear cache** deletes it. A mounted drive is stopped for the purge and mounted again.
- **It is refused while uploads are pending or cannot be counted**, because those files exist only in the cache.
- **Refresh listing** forgets the cached directory listings so the next access asks the cloud again. It needs the drive mounted.

## Forgetting a drive

The bin in a drive's row, **Forget this account** on its Account page, or `startdrive disconnect <drive>`, asks first (in a terminal), and warns if files have not finished uploading. It unmounts the drive, disables its unit, deletes the rclone remote, the drive's settings file and its cache, and removes its empty folder under `~/Cloud`. Your files in the cloud are never touched.

## Keyboard

| Key | Does |
| --- | --- |
| `j` / `k` | Move down and up |
| `Up` / `Down` | The same |
| `Enter` | The row's main action: connect, open the folder, or mount |
| `m` | Mount or unmount (connect, if the drive is not connected) |
| `o` | Open the folder in the file manager |
| `s` | Open the drive's settings |
| `f` | Forget the drive |
| `a` | Mount or unmount every drive |
| `r` | Look at the drives again |
| `n` | Add a remote |
| Escape | Close the topmost window |

Inside a settings window, type to search the settings, click a page on the left, and press Escape to go back to the manager.
