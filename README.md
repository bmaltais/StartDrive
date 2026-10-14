<p align="center">
  <img alt="The Cloud Drives panel: Google Drive mounted with Open, Unmount and Forget buttons, OneDrive and iCloud Drive waiting to be connected" src="screenshots/panel.png" width="372" />
</p>

<h1 align="center">Cloud Drives</h1>

<p align="center">
  <b>Your cloud drives as plain folders, from a bar widget for Omarchy.</b><br>
  Google Drive, OneDrive and iCloud Drive mounted under <code>~/Cloud</code>, with every
  credential kept in your login keyring.
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#tour">Tour</a> ·
  <a href="#commands">Commands</a> ·
  <a href="#security">Security</a> ·
  <a href="#update-and-remove">Update and remove</a>
</p>

## Install

```sh
omarchy plugin add https://github.com/bmaltais/omarchy-cloud-drives --enable
```

It adds a cloud icon to the bar. The first time you connect a drive, `rclone` and `fuse3` are installed with `omarchy pkg add` (one sudo prompt). Everything else (`secret-tool`, `gum`, `jq`, `curl`) ships with Omarchy.

```
~/Cloud/GoogleDrive
~/Cloud/OneDrive
~/Cloud/iCloudDrive
```

## Tour

### The panel

<img src="screenshots/panel.png" alt="The Cloud Drives panel listing three drives with their actions" width="372">

- **One row per drive.** A status dot and line (not connected, mounting, mounted, or failed and retrying), and for a mounted drive a storage meter with how much of the quota is used.
- **A switch to mount.** Flip it to mount or unmount. A folder button opens the drive in your file manager and a bin button forgets the account. Click anywhere else on the row to do its main thing: open it, mount it, or connect it.
- **Everything at once.** When more than one drive is connected, the switch in the header mounts or unmounts them all.
- **Keyboard first.** `j`/`k` move between drives, `h`/`l` between a row's controls, `Enter` activates. `m` mounts or unmounts, `o` opens, `f` forgets, `a` toggles all, `r` refreshes and Escape closes. Right-click the bar icon to refresh.
- **Quiet.** Connect and Forget open a floating terminal for the interactive bits (browser sign-in, 2FA, confirmation). Mount errors show in the panel.

### Colours

The panel follows the current Omarchy theme live: colours, fonts and the bar's own widgets.

## Commands

Run these with `omarchy-shell edbron.cloud-drives <command>`, for instance from a key binding:

| Command | Does |
|---|---|
| `state` | Prints the drives and their state as JSON |
| `refresh` | Re-reads the state |
| `toggle` | Opens or closes the panel |
| `mount ID` | Mounts a drive (`google`, `onedrive` or `icloud`) |
| `unmount ID` | Unmounts it |
| `connect ID` | Starts the sign-in for it |

The helper script also has `about <id>` (storage usage as JSON) and `mount-all` / `unmount-all`.

The helper script also works on its own:

```sh
~/.config/omarchy/plugins/edbron.cloud-drives/bin/omarchy-cloud-drives <state|setup|connect|disconnect|mount|unmount|open> [google|onedrive|icloud]
```

## Security

The rclone config is encrypted with a random 256-bit key that lives only in your login keyring. Google and OneDrive sign in with OAuth in your browser, and iCloud's password never appears in a command line, the environment or a log. Mounts are private to your user. The full model, the files the plugin touches and the Google client-id note are in [docs/SECURITY.md](docs/SECURITY.md).

## Update and remove

```sh
omarchy plugin update edbron.cloud-drives --yes && omarchy restart shell
```

Your drives and credentials are kept, since they live in rclone's config and your keyring and not in the plugin folder.

To remove it, forget each drive from the panel, then:

```sh
systemctl --user disable --now 'omarchy-cloud-drive@*'
rm ~/.config/systemd/user/omarchy-cloud-drive@.service ~/.config/environment.d/60-omarchy-cloud-drives.conf
secret-tool clear service omarchy-cloud-drives key config-password
omarchy plugin remove edbron.cloud-drives
```

## License

MIT
