# Security model

- **rclone's config is encrypted.** It holds OAuth refresh tokens and (for
  iCloud) the session/trust token. The encryption password is 256 random bits
  stored *only* in your login keyring (gnome-keyring, via `secret-tool`).
  rclone reads it through `RCLONE_PASSWORD_COMMAND`; it is never written to
  disk in the clear and never placed in an environment variable.
- **Google / OneDrive** authenticate with OAuth in your browser; the plugin
  never sees your password. Tokens can be revoked at any time from your
  Google / Microsoft account security pages.
- **iCloud** has no OAuth. rclone's `iclouddrive` backend needs your Apple ID
  password once (stored obscured inside the encrypted config) plus a 2FA
  code. The password is handed to rclone through its rc API over a private
  unix socket (request body built from stdin), so neither the clear nor the
  obscured value ever appears in a command line, the environment, logs or a
  temporary file. Prefer an app-specific password. Advanced Data Protection must be
  off for that Apple ID (Apple does not expose ADP-protected data to
  third-party clients). This backend is marked experimental by rclone.
- **Mounts** are user-private (`umask 077`, no `allow_other`) and run as
  systemd user units (`omarchy-cloud-drive@<Remote>.service`) bound to the
  graphical session so they stop with it. The units deliberately carry no
  systemd sandboxing: mount-namespace options would hide the FUSE mount from
  your session, and seccomp/`NoNewPrivileges` options break the setuid
  `fusermount3`. Unprivileged FUSE is the isolation boundary.
- Google: rclone's shared client_id is being retired during 2026. To keep
  working long-term, create your own OAuth client
  (https://rclone.org/drive/#making-your-own-client-id) and run
  `rclone config update GoogleDrive client_id=… client_secret=…`.
- Mount root `~/Cloud` is `0700`; the VFS cache lives in `~/.cache/rclone`
  (max 4 GB, 72 h) — remember it holds plaintext copies of recently used files.
- `~/.config/environment.d/60-omarchy-cloud-drives.conf` exports the same
  `RCLONE_PASSWORD_COMMAND` so plain `rclone` in your terminal keeps working.

## Files it touches

| Path | Purpose |
|------|---------|
| `~/.config/rclone/rclone.conf` | encrypted rclone config (0600) |
| `~/.config/systemd/user/omarchy-cloud-drive@.service` | mount unit template |
| `~/.config/environment.d/60-omarchy-cloud-drives.conf` | password-command for your shell |
| `~/Cloud/<Remote>` | mount points |
| keyring item `service=omarchy-cloud-drives key=config-password` | config key |
