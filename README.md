<p align="center">
  <img alt="A tour of StartDrive: opening the panel from the bar, a drive's details, and the Cache, Behaviour and Maintenance tabs" src="screenshots/hero.gif" width="520" />
</p>

<h1 align="center">StartDrive</h1>

<p align="center">
  <b>Your cloud drives as folders, for Omarchy.</b><br>
  Google Drive, OneDrive, Dropbox and any other rclone backend, mounted under <code>~/Cloud</code>
  with live upload activity, cache controls and per-drive settings, all a click away.
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#tour">Tour</a> ·
  <a href="#configure">Configure</a> ·
  <a href="#commands">Commands</a> ·
  <a href="#security">Security</a> ·
  <a href="#update-and-remove">Update and remove</a> ·
  <a href="#contributing">Contributing</a>
</p>

> **Omarchy 4.5:** StartDrive is compatible with the windowed mode coming in Omarchy 4.5.

## Install

```sh
omarchy plugin add https://github.com/bmaltais/StartDrive.git --enable
```

It adds a cloud icon to the bar, on the right by default. The first time you connect a drive, `rclone` and `fuse3` are installed with `omarchy pkg add` (one sudo prompt, the only privileged step). Everything else (`secret-tool`, `gum`, `jq`, `curl`) comes with Omarchy.

```
~/Cloud/GoogleDrive
~/Cloud/OneDrive
~/Cloud/Dropbox
```

## Tour

### The panel

<img src="screenshots/panel.png" alt="The panel listing Google Drive, OneDrive and Dropbox, with an Add remote button" width="400">

- **One row per drive.** A status dot and line: not connected, mounting, mounted, synced, uploading (with the speed) or failed. A mounted drive also shows a storage meter.
- **A switch to mount.** A folder button opens the drive in your file manager, a cog opens its details, a bin forgets the account. Click anywhere else on the row for its main action.
- **Sync status.** Uploads are written to a local cache first and sent in the background, so the panel tells you when they are still on their way. The bar icon turns into an upload cloud while files are moving and into an alert cloud if one fails to upload. "All synced" means it is safe to shut down.
- **Everything at once.** With more than one drive connected, the header switch mounts or unmounts them all.
- **Any other remote.** **Add remote…** runs rclone's questionnaire in a terminal for any other backend (SFTP, WebDAV, S3, B2 ...). A remote named with letters, digits, `-` or `_` then shows up as a drive.

### Keyboard

`j`/`k` move, `h`/`l` move along a row or change a choice, and `Enter` activates. `m` mounts or unmounts, `o` opens, `d` shows details, `f` forgets, `a` toggles all, `r` refreshes, `n` adds a remote. Escape closes the panel.

### Details

<table>
  <tr>
    <th>Cache</th>
    <th>Behaviour</th>
    <th>Maintenance</th>
  </tr>
  <tr valign="top">
    <td><img src="screenshots/details.png" alt="A drive's details with the Cache tab open: activity, cache limit and keep-files choices"></td>
    <td><img src="screenshots/behaviour.png" alt="The Behaviour tab: mount at login and read-only"></td>
    <td><img src="screenshots/maintenance.png" alt="The Maintenance tab: refresh listing and clear cache"></td>
  </tr>
</table>

The cog opens a drive's details: the files being transferred right now, each with its progress and speed, and the settings in three tabs, so only the group you want is open.

### Colours

Colours and fonts follow the current Omarchy theme live, in the panel and in the bar icon.

## Configure

Changes apply as you make them, from the details of each drive.

- **Cache.** Choose how much disk the cache may use (1 to 50 GB) and how long unused files stay (6 hours to 30 days).
- **Behaviour.** Mount at login, and read-only to block writes and deletes through the folder.
- **Maintenance.** Refresh the directory listing when something changed in the cloud, or clear the cache to delete the plaintext copies rclone keeps. Clearing is refused while uploads are pending, because those files exist only in the cache.

A change to a mounted drive is applied at once if nothing is uploading, and at the next mount otherwise.

### Settings files

Each drive's settings are saved in `~/.config/startdrive/<remote>.env`, as the rclone variables the mount reads, which you can also edit by hand:

```sh
RCLONE_VFS_CACHE_MAX_SIZE=10G
RCLONE_VFS_CACHE_MAX_AGE=72h
RCLONE_READ_ONLY=false
```

Every setting, its default and accepted values, the `startdrive set` command, and when a change applies are in [docs/SETTINGS.md](docs/SETTINGS.md).

## Commands

Run these with `omarchy-shell io.github.bmaltais.startdrive <command>`, for instance from a key binding:

| Command | Does |
|---|---|
| `toggle`, `open`, `close` | Shows or hides the panel |
| `state` | Prints the drives and their activity as JSON |
| `refresh` | Re-reads the state |
| `mount ID`, `unmount ID` | Mounts or unmounts a drive (`google`, `onedrive`, `dropbox`, or `r-<name>` for a remote you added) |
| `mountAll`, `unmountAll` | Does it for every connected drive |
| `connect ID` | Starts the sign-in in a terminal |

The helper script works on its own too: run `~/.config/omarchy/plugins/io.github.bmaltais.startdrive/bin/startdrive --help`.

## Security

Plugins run unsandboxed, so this one keeps its footprint small and documents it. The rclone config is encrypted with a random 256-bit key that lives only in your login keyring. Google Drive, OneDrive and Dropbox sign in with OAuth in your browser, so no password passes through the plugin. Mounts are private to your user, and the remote-control socket each mount opens sits in a `0700` directory. The full model, every dependency and privilege boundary, and the files the plugin touches are in [docs/SECURITY.md](docs/SECURITY.md).

## Update and remove

```sh
omarchy plugin update io.github.bmaltais.startdrive --yes && omarchy restart shell
```

Your drives and credentials are kept: they live in rclone's config and your keyring, not in the plugin folder. A copy installed before the rename to StartDrive moves its mounts to the new unit the first time the panel loads.

To remove it, first forget each drive you no longer want from the panel, then:

```sh
~/.config/omarchy/plugins/io.github.bmaltais.startdrive/bin/startdrive uninstall   # add --purge to also delete the keyring key
omarchy plugin remove io.github.bmaltais.startdrive
```

`uninstall` stops the mounts and removes the systemd unit, the per-drive settings and the shell environment file. It never touches your files in the cloud or the rclone remotes.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development install and the checks.

## License

MIT
