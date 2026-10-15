# Security

StartDrive is an Omarchy shell plugin. Omarchy runs plugins unsandboxed, with your permissions, inside the long-lived shell process, so this page lists everything the plugin does, installs and trusts. To report a vulnerability, open a private security advisory on the GitHub repository.

## What it runs

| Component | What it is | Privilege |
|---|---|---|
| `Panel.qml`, `DriveService.qml`, `DriveRow.qml`, `Segmented.qml`, `ScrollTrack.qml`, `DriveModel.js` | The bar widget, in the shell process | Your user. Runs `bin/startdrive` and `xdg-open` with argument arrays, never a shell string. |
| `bin/startdrive`, `lib/*.sh` | The command line the panel calls | Your user |
| `systemd/startdrive@.service` | A systemd **user** unit per drive, running `rclone mount` | Your user |
| `rclone`, `fuse3` | Installed on the first Connect with `omarchy pkg add` | **sudo**, once, through Omarchy's package helper. This is the only privileged step. |

Nothing else is installed, downloaded or built. There is no network access of its own: the only network traffic is rclone's, to the services you connect (Google, Microsoft, Dropbox, or any remote you add). There is no telemetry.

## Dependencies

`rclone`, `fuse3` (installed on demand), and `secret-tool` (libsecret), `gum`, `jq`, `curl`, `systemd`, `hyprctl`, `xdg-open` and `uwsm-app`, which ship with Omarchy.

## Secrets

- **The rclone config is encrypted.** It holds OAuth refresh tokens. Its password is 256 random bits stored only in the login keyring (`secret-tool`, item `service=omarchy-cloud-drives key=config-password`; the item keeps its original name so existing configs stay readable). rclone reads it through `RCLONE_PASSWORD_COMMAND`. It is never written to disk in the clear and never placed in an environment variable.
- **Google Drive, OneDrive and Dropbox** sign in with OAuth in your browser. The plugin never sees the password. Tokens can be revoked from your Google or Microsoft security page.

## Mounts

- Each drive is a user unit, `startdrive@<Remote>.service`, bound to the graphical session so it stops with it. Mounts are private (`umask 077`, no `allow_other`).
- The unit carries no systemd sandboxing on purpose: mount-namespace options would hide the FUSE mount from your session, and seccomp or `NoNewPrivileges` options break the setuid `fusermount3`. Unprivileged FUSE is the isolation boundary.
- **Remote-control socket.** Each mount runs rclone's remote-control API on a unix socket at `$XDG_RUNTIME_DIR/startdrive/<Remote>/rc.sock`, in a directory systemd creates with mode `0700` and removes when the mount stops. It carries no password because only your user can reach it. The panel uses it to read transfer activity and the cache size, to refresh directory listings, and to check that no uploads are pending before a restart or a cache purge.
- **The cache holds plaintext copies** of recently used files, and of uploads not yet sent, in `~/.cache/rclone/vfs/<Remote>`. Limit and age are settings; `startdrive clear-cache` deletes it and is refused while uploads are pending.

## Input handling

- A drive is one of a fixed list (`google`, `onedrive`, `dropbox`), or `r-<name>` for a remote you added with `startdrive add`. A name is accepted only if it matches `^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$` and exists in your rclone config; anything else is rejected before any path or unit name is built.
- Settings are validated against an allow-list of shapes (`^[1-9][0-9]{0,3}[MG]$` and so on) before they are written into the file systemd reads, so a value cannot add a variable or a line.
- `startdrive launch` only runs `connect` and `disconnect`, so the panel cannot be made to run another command in a terminal.
- File names shown in the panel come from the cloud. They are rendered as plain text, never as rich text, and are length-limited.
- Config files are written to a temporary file in the destination directory and renamed into place, so a planted symlink at a predictable path is replaced rather than written through.
- The cache is deleted only inside `~/.cache/rclone/vfs` and `vfsMeta`, and the path is checked before `rm`.

## Google client id

rclone's shared Google client id is being retired during 2026. To keep working long-term, create your own OAuth client (https://rclone.org/drive/#making-your-own-client-id) and run `rclone config update GoogleDrive client_id=… client_secret=…`.

## Files it touches

| Path | Purpose |
|---|---|
| `~/.config/rclone/rclone.conf` | The encrypted rclone config (0600) |
| `~/.config/systemd/user/startdrive@.service` | The mount unit template |
| `~/.config/startdrive/<Remote>.env` | Per-drive settings (0600) |
| `~/.config/environment.d/60-startdrive.conf` | Exports the password command so plain `rclone` in your terminal can read the config |
| `~/Cloud/<Remote>` | Mount points (the root is 0700) |
| `~/.cache/rclone/vfs*/<Remote>` | The cache |
| `$XDG_RUNTIME_DIR/startdrive/<Remote>/` | The remote-control socket, while mounted |
| Keyring item `service=omarchy-cloud-drives key=config-password` | The config key |

## Removing it

`startdrive uninstall` stops the mounts and removes the unit, the settings and the environment file. `--purge` also deletes the keyring item (which makes the encrypted rclone config unreadable, so it asks first). It never touches your files or your rclone remotes. See the README for the order.

## Upgrading from "Cloud Drives"

Earlier versions installed `omarchy-cloud-drive@.service` and `60-omarchy-cloud-drives.conf`. The first load of this version moves each drive's mounted and mount-at-login state to the new unit and removes the old files. Remote names, `~/Cloud` paths and the keyring item are unchanged.
