// The rules of the panel, with no Quickshell imports so they run under Node
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

// The setting each detail item (a cursor stop) edits.
var DETAIL_SETTING = {
  cacheSize: "cache-size", cacheAge: "cache-age", readOnly: "read-only", autostart: "autostart",
  notifications: "notifications"
}

function settingValue(drive, key) {
  return String(drive.settings[SETTINGS[key].field])
}

// A copy of the drive with one setting changed, to show it before the next poll.
function withSetting(drive, key, value) {
  var settings = Object.assign({}, drive.settings)
  settings[SETTINGS[key].field] = SETTINGS[key].boolean ? value === "true" : value
  return Object.assign({}, drive, { settings: settings })
}

// The value a toggle sets next.
function flipped(drive, key) {
  return String(settingValue(drive, key) !== "true")
}

// The next preset of a choice setting, `delta` steps along.
function stepped(drive, key, delta) {
  return stepOption(SETTINGS[key].options, settingValue(drive, key), delta)
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

function isBusy(drive, activity) {
  return !!activity && (pending(activity) > 0)
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
  s.glyph = (s.failed || s.errored) ? GLYPH.alert : s.pending > 0 ? GLYPH.uploading : s.mounted > 0 ? GLYPH.mounted : GLYPH.idle
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

// ---- Keyboard cursor ----------------------------------------------------
// One flat list of stops: each drive's row, then (for the expanded drive) its
// detail items. `rowControls` are the buttons along a row; h/l walks them.

function rowControls(drive) {
  if (!drive.configured) return ["connect"]
  return drive.mounted ? ["open", "details", "disconnect", "toggle"] : ["details", "disconnect", "toggle"]
}

function primaryControl(drive) {
  var c = rowControls(drive)
  return c[c.length - 1]
}

// What a click on the row itself does: connect it, open it, or mount it.
function clickControl(drive) {
  if (!drive.configured) return "connect"
  return drive.mounted ? "open" : "toggle"
}

var DETAIL_TABS = [
  { value: "cache", label: "Cache" },
  { value: "behaviour", label: "Behaviour" },
  { value: "maintenance", label: "Maintenance" }
]

// The cursor stops of an expanded drive: its tab bar, then the open tab's items.
function detailItems(drive, tab) {
  var items = ["tabs"]
  if (tab === "behaviour") items.push("autostart", "readOnly", "notifications")
  else if (tab === "maintenance") {
    if (drive.mounted) items.push("refresh")
    items.push("clearCache")
  } else items.push("cacheSize", "cacheAge")
  return items
}

// ---- What a control does ------------------------------------------------
// Enter, a click and h/l all ask here and get an action back, so the keyboard
// and the pointer cannot disagree. Panel.dispatch carries the action out:
//   { type: "mount" | "unmount" | "open" | "details" | "refreshListing" | "clearCache" }
//   { type: "interactive", command: "connect" | "disconnect" }
//   { type: "set", key, value }   { type: "tab", value }

// A row's button (see rowControls).
function controlAction(control, drive) {
  switch (control) {
  case "toggle": return { type: (drive.mounted || drive.unit === "activating") ? "unmount" : "mount" }
  case "open": return { type: "open" }
  case "details": return { type: "details" }
  case "connect":
  case "disconnect": return { type: "interactive", command: control }
  }
  return null
}

// Enter or a click on a detail item (see detailItems).
function detailAction(drive, item) {
  var key = DETAIL_SETTING[item]
  if (key) return { type: "set", key: key, value: flipped(drive, key) }
  if (item === "refresh") return { type: "refreshListing" }
  if (item === "clearCache") return { type: "clearCache" }
  return null
}

// h or l (delta -1 or +1) on a detail item: the tabs and the choice settings.
function stepAction(drive, item, delta, tab) {
  if (item === "tabs") return { type: "tab", value: stepOption(DETAIL_TABS, tab, delta) }
  var key = DETAIL_SETTING[item]
  if (key && SETTINGS[key].options) return { type: "set", key: key, value: stepped(drive, key, delta) }
  return null
}

function navStops(drives, expandedId, tab) {
  var stops = []
  for (var i = 0; i < drives.length; i++) {
    stops.push({ kind: "row", id: drives[i].id })
    if (drives[i].configured && drives[i].id === expandedId) {
      var items = detailItems(drives[i], tab)
      for (var j = 0; j < items.length; j++) stops.push({ kind: "detail", id: drives[i].id, key: items[j] })
    }
  }
  return stops
}

function clamp(n, lo, hi) { return Math.max(lo, Math.min(hi, n)) }

// The option after `current` in `options` by `delta`, stopping at the ends.
function stepOption(options, current, delta) {
  var i = 0
  for (var k = 0; k < options.length; k++) if (options[k].value === current) i = k
  return options[clamp(i + delta, 0, options.length - 1)].value
}

// The nearest preset to a stored value, so a hand-edited setting still shows.
function hasOption(options, value) {
  for (var k = 0; k < options.length; k++) if (options[k].value === value) return true
  return false
}

// Hide the home directory in a path.
function tildePath(path) { return String(path || "").replace(/^\/home\/[^\/]+/, "~") }

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
