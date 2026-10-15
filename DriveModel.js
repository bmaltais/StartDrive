// The rules of the manager, with no Quickshell imports so they run under Node
// (tests/DriveModel.test.js). A drive is one entry of `startdrive state`; an
// activity is one entry of `startdrive activity`.

.pragma library

var CACHE_SIZES = [
  { value: "1G", label: "1 GB" },
  { value: "4G", label: "4 GB" },
  { value: "10G", label: "10 GB" },
  { value: "20G", label: "20 GB" },
  { value: "50G", label: "50 GB" }
]

var CACHE_AGES = [
  { value: "6h", label: "6 h" },
  { value: "24h", label: "1 d" },
  { value: "72h", label: "3 d" },
  { value: "168h", label: "7 d" },
  { value: "720h", label: "30 d" }
]

// The per-drive settings. `key` is what `startdrive set` takes; `field` is
// where the drive's `settings` object carries it. Booleans travel as "true" /
// "false". Presets (`options`) must pass the CLI's allow-list in lib/settings.sh.
var SETTINGS = {
  "cache-size": { field: "cacheSize", options: CACHE_SIZES },
  "cache-age": { field: "cacheAge", options: CACHE_AGES },
  "read-only": { field: "readOnly", boolean: true },
  "autostart": { field: "autostart", boolean: true },
  "notifications": { field: "notifications", boolean: true }
}

// The settings window's field for each setting, and the key `startdrive set` takes for it.
var FIELD_SETTING = {
  cacheSize: "cache-size", cacheAge: "cache-age", readOnly: "read-only", autostart: "autostart",
  notifications: "notifications"
}

// A copy of the drive with one setting changed, to show it before the next poll.
function withSetting(drive, key, value) {
  var settings = Object.assign({}, drive.settings)
  settings[SETTINGS[key].field] = SETTINGS[key].boolean ? value === "true" : value
  return Object.assign({}, drive, { settings: settings })
}

// Glyphs from the Material Design set in the Nerd Font Omarchy ships.
var GLYPH = {
  idle: "\uDB80\uDD63",      // cloud outline  U+F0163
  mounted: "\uDB80\uDD5F",   // cloud          U+F015F
  uploading: "\uDB80\uDD67", // cloud upload   U+F0167
  alert: "\uDB82\uDDE0"      // cloud alert    U+F09E0
}

function formatBytes(n) {
  if (n === undefined || n === null || isNaN(n)) return ""
  var units = ["B", "KB", "MB", "GB", "TB", "PB"]
  var i = 0
  while (n >= 1000 && i < units.length - 1) { n /= 1000; i++ }
  return (n >= 100 || i === 0 ? Math.round(n) : n.toFixed(1)) + " " + units[i]
}

function formatSpeed(bytesPerSecond) {
  return bytesPerSecond > 0 ? formatBytes(bytesPerSecond) + "/s" : ""
}

function plural(n, one, many) { return n + " " + (n === 1 ? one : many) }

// "6.4 GB of 276 GB", or "6.4 GB used" when the backend reports no total.
function usageText(usage) {
  if (!usage || usage.used === undefined) return ""
  return usage.total ? formatBytes(usage.used) + " of " + formatBytes(usage.total) : formatBytes(usage.used) + " used"
}

// 0..1, or -1 when there is nothing to draw.
function usageFraction(usage) {
  if (!usage || !usage.total || usage.used === undefined) return -1
  return Math.max(0, Math.min(1, usage.used / usage.total))
}

function pending(activity) {
  return activity ? (activity.uploading || 0) + (activity.queued || 0) : 0
}

// What a row says about its drive. `kind` picks the dot colour and whether it
// pulses; `text` is the line under the name.
function driveStatus(drive, activity, working) {
  if (!drive.configured) return { kind: "none", text: "Not connected" }
  if (working) return { kind: "working", text: drive.mounted ? "Unmounting…" : "Mounting…" }
  if (drive.unit === "failed") return { kind: "failed", text: "Mount failed · retrying" }
  if (drive.unit === "activating") return { kind: "working", text: "Mounting…" }
  if (!drive.mounted) return { kind: "off", text: "Connected · not mounted" }
  if (drive.sharedClientId) return { kind: "failed", text: "Shared Google key · may freeze" }
  if (activity) {
    if (activity.errored > 0) return { kind: "failed", text: plural(activity.errored, "file", "files") + " failed to upload" }
    var n = pending(activity)
    if (n > 0) {
      var speed = formatSpeed(activity.speed)
      return { kind: "working", text: "Uploading " + plural(n, "file", "files") + (speed ? " · " + speed : "") }
    }
    return { kind: "synced", text: "Mounted · synced" }
  }
  return { kind: "synced", text: "Mounted" }
}

// Totals for the header and the bar icon.
function summarize(drives, activities) {
  var s = { connected: 0, mounted: 0, pending: 0, errored: 0, speed: 0, failed: 0 }
  for (var i = 0; i < drives.length; i++) {
    var d = drives[i]
    if (d.configured) s.connected++
    if (d.mounted) s.mounted++
    if (d.unit === "failed") s.failed++
    var a = activities[d.id]
    if (a) {
      s.pending += pending(a)
      s.errored += a.errored || 0
      s.speed += a.speed || 0
    }
  }
  s.kind = (s.failed || s.errored) ? "alert" : s.pending > 0 ? "uploading" : s.mounted > 0 ? "mounted" : "idle"
  s.glyph = GLYPH[s.kind]
  return s
}

function headline(summary, secure, rcloneInstalled) {
  if (!rcloneInstalled) return "Not set up · connect a drive to begin"
  if (!summary.connected) return "No accounts connected"
  if (summary.errored) return plural(summary.errored, "file", "files") + " failed to upload"
  if (summary.pending > 0) {
    var speed = formatSpeed(summary.speed)
    return "Uploading " + plural(summary.pending, "file", "files") + (speed ? " · " + speed : "")
  }
  if (!secure) return "Config not encrypted"
  return summary.mounted > 0 ? "All synced" : "Nothing mounted"
}

// ---- What a click or a key does ----------------------------------------------
// A click on a row, Enter and the letter keys all ask here and get an action back, so the keyboard and the pointer cannot
// disagree. Service.qml carries the action out:
//   { type: "mount" | "unmount" | "open" | "settings" | "mountAll" | "unmountAll" | "refresh" | "add" }
//   { type: "interactive", command: "connect" | "disconnect" }

// What a click on the row itself (or Enter) does: connect it, open it, or mount it.
function clickAction(drive) {
  if (!drive.configured) return { type: "interactive", command: "connect" }
  return drive.mounted ? { type: "open" } : { type: "mount" }
}

function toggleAction(drive) {
  return { type: (drive.mounted || drive.unit === "activating") ? "unmount" : "mount" }
}

// A letter typed in the manager. `drive` is the row under the cursor (or null); `summary` is summarize()'s result.
function keyAction(key, drive, summary) {
  switch (String(key).toLowerCase()) {
  case "r": return { type: "refresh" }
  case "n": return { type: "add" }
  case "a":
    if (!summary || summary.connected < 1) return null
    return { type: summary.mounted === summary.connected ? "unmountAll" : "mountAll" }
  }
  if (!drive) return null
  switch (String(key).toLowerCase()) {
  case "m": return drive.configured ? toggleAction(drive) : { type: "interactive", command: "connect" }
  case "o": return drive.mounted ? { type: "open" } : null
  case "s": return drive.configured ? { type: "settings" } : null
  case "f": return drive.configured ? { type: "interactive", command: "disconnect" } : null
  }
  return null
}

// The transfer a row shows under its status while files are moving: the first one, and how many more are waiting.
function transferLine(activity) {
  if (!activity || !activity.transfers || activity.transfers.length === 0) return null
  var t = activity.transfers[0]
  return {
    name: t.name,
    percent: Math.round(Math.max(0, Math.min(100, t.percentage || 0))),
    fraction: Math.max(0, Math.min(1, (t.percentage || 0) / 100)),
    speed: formatSpeed(t.speed),
    more: Math.max(0, pending(activity) - 1)
  }
}

// ---- A drive's settings window ----------------------------------------------------
// The pages of SettingsWindow for one drive. `ctx` is { pending: files still uploading, busy: an action is running,
// notes: { fieldKey: { kind, text } } feedback under a setting }. The window's value for a field is drive.settings[key];
// a change to a field in FIELD_SETTING is `startdrive set`, and an "action" field is a button.
function settingsPages(drive, ctx) {
  var notes = ctx.notes || {}
  function note(key) { return notes[key] || { kind: "muted", text: "" } }
  var waiting = ctx.pending > 0
  var cache = [
    { key: "cacheSize", type: "choice", label: "Cache limit", options: CACHE_SIZES,
      hint: "The most local disk the cache may use.", note: note("cacheSize") },
    { key: "cacheAge", type: "choice", label: "Keep files", options: CACHE_AGES,
      hint: "How long unused files stay in the cache.", note: note("cacheAge") }
  ]
  var account = []
  if (drive.sharedClientId) {
    account.push({ key: "clientId", type: "action", label: "Use my own Google key", buttonText: "Set up\u2026", disabled: !!ctx.busy,
      hint: "This drive uses rclone's shared Google key. Google limits it for everyone, so the folder can freeze. Your own key takes about five minutes, once." })
  }
  account.push({ key: "forget", type: "action", label: "Forget this account", buttonText: "Forget\u2026", disabled: !!ctx.busy,
    hint: "Disconnects the drive and removes its credentials from this machine. Your files in the cloud are not touched. A terminal asks you to confirm." })
  return [
    { title: "Behaviour", fields: [
      { key: "autostart", type: "bool", label: "Mount at login", hint: "Mounts this drive when your session starts.", note: note("autostart") },
      { key: "readOnly", type: "bool", label: "Read-only", hint: "Blocks writes and deletes through the folder.", note: note("readOnly") },
      { key: "notifications", type: "bool", label: "Notifications", hint: "Tells you when this drive fails to mount or upload.", note: note("notifications") }
    ] },
    { title: "Cache", fields: cache },
    { title: "Maintenance", fields: [
      { key: "refresh", type: "action", label: "Refresh listing", buttonText: "Refresh", disabled: !drive.mounted || !!ctx.busy, note: note("refresh"),
        hint: drive.mounted ? "Looks for changes made elsewhere in the cloud." : "Mount the drive to refresh its listing." },
      { key: "clearCache", type: "action", label: "Clear cache", buttonText: "Clear", disabled: waiting || !!ctx.busy, note: note("clearCache"),
        hint: waiting ? "Wait for " + plural(ctx.pending, "file", "files") + " to finish uploading."
          : (formatBytes(drive.cacheBytes) || "0 B") + " on disk. Deletes the plaintext copies rclone keeps." }
    ] },
    { title: "Account", fields: account }
  ]
}

// The page to open first: a drive on the shared Google key goes straight to the fix.
function settingsStartPage(drive) { return drive.sharedClientId ? 3 : 0 }

// What deserves a desktop notification. `state` is { drives, activity }; `announced` holds the keys already shown, so
// a condition that lasts is said once. A key is forgotten when its condition
// clears, so it is announced again if it returns. Returns the notifications to
// show: { key, title, body, urgent }.
function alerts(state, announced) {
  var out = []
  var seen = {}

  function consider(key, active, title, body, urgent) {
    if (!active) return
    seen[key] = true
    if (announced[key]) return
    announced[key] = true
    out.push({ key: key, title: title, body: body, urgent: !!urgent })
  }

  for (var j = 0; j < state.drives.length; j++) {
    var d = state.drives[j]
    if (!d.configured || (d.settings && d.settings.notifications === false)) continue
    var act = state.activity[d.id]
    consider(d.id + ":failed", d.unit === "failed",
      d.name + " could not mount", "It will retry in a few seconds. Open StartDrive for details.", true)
    consider(d.id + ":upload", !!act && act.errored > 0,
      d.name + ": upload failed", plural(act ? act.errored : 0, "file", "files") + " could not be uploaded.", true)
    consider(d.id + ":shared", !!d.sharedClientId && d.mounted,
      d.name + " may freeze",
      "It uses rclone's shared Google key, which Google limits. Open StartDrive and set up your own key.", false)
  }
  for (var key in announced) if (!seen[key]) delete announced[key]
  return out
}
