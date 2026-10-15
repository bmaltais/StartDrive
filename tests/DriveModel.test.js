const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")

// DriveModel.js is a QML library; load it as a plain script.
const source = fs.readFileSync(path.join(__dirname, "..", "DriveModel.js"), "utf8").replace(/^\.pragma.*$/m, "")
const M = new Function(source + "\nreturn { formatBytes, formatSpeed, usageText, usageFraction, driveStatus, summarize, headline, rowControls, primaryControl, detailItems, navStops, DETAIL_TABS, stepOption, tildePath, GLYPH, CACHE_SIZES, CACHE_AGES, SETTINGS, DETAIL_SETTING, settingValue, withSetting, flipped, stepped, controlAction, detailAction, stepAction, alerts }")()

const drive = (over) => Object.assign({ id: "google", configured: true, mounted: true, unit: "active" }, over)

test("formatBytes", () => {
  assert.strictEqual(M.formatBytes(0), "0 B")
  assert.strictEqual(M.formatBytes(6373963295), "6.4 GB")
  assert.strictEqual(M.formatBytes(275956891648), "276 GB")
  assert.strictEqual(M.formatBytes(undefined), "")
})

test("usage", () => {
  assert.strictEqual(M.usageText({ used: 6373963295, total: 275956891648 }), "6.4 GB of 276 GB")
  assert.strictEqual(M.usageText({ used: 1500 }), "1.5 KB used")
  assert.strictEqual(M.usageText({}), "")
  assert.strictEqual(M.usageFraction({ used: 50, total: 100 }), 0.5)
  assert.strictEqual(M.usageFraction({ used: 500, total: 100 }), 1)
  assert.strictEqual(M.usageFraction({ used: 5 }), -1)
})

test("a drive's status line", () => {
  assert.strictEqual(M.driveStatus(drive({ configured: false, mounted: false }), null, false).text, "Not connected")
  assert.strictEqual(M.driveStatus(drive({ mounted: false, unit: "inactive" }), null, false).text, "Connected · not mounted")
  assert.strictEqual(M.driveStatus(drive({ unit: "failed", mounted: false }), null, false).kind, "failed")
  assert.strictEqual(M.driveStatus(drive(), null, true).text, "Unmounting…")
  assert.strictEqual(M.driveStatus(drive(), { uploading: 1, queued: 2, speed: 3100000, errored: 0 }, false).text, "Uploading 3 files · 3.1 MB/s")
  assert.strictEqual(M.driveStatus(drive(), { uploading: 0, queued: 1, speed: 0, errored: 0 }, false).text, "Uploading 1 file")
  assert.strictEqual(M.driveStatus(drive(), { uploading: 0, queued: 0, errored: 2 }, false).kind, "failed")
  assert.strictEqual(M.driveStatus(drive(), { uploading: 0, queued: 0, errored: 0 }, false).text, "Mounted · synced")
})

test("summary and bar glyph", () => {
  const drives = [drive(), drive({ id: "onedrive" }), drive({ id: "dropbox", configured: false, mounted: false })]
  const idle = M.summarize(drives, {})
  assert.deepStrictEqual([idle.connected, idle.mounted, idle.pending], [2, 2, 0])
  assert.strictEqual(idle.glyph, M.GLYPH.mounted)
  const up = M.summarize(drives, { google: { uploading: 1, queued: 0, speed: 5, errored: 0 } })
  assert.strictEqual(up.glyph, M.GLYPH.uploading)
  assert.strictEqual(M.headline(up, true, true), "Uploading 1 file · 5 B/s")
  const bad = M.summarize(drives, { google: { uploading: 1, queued: 0, errored: 1 } })
  assert.strictEqual(bad.glyph, M.GLYPH.alert)
  assert.strictEqual(M.summarize([drive({ mounted: false })], {}).glyph, M.GLYPH.idle)
  assert.strictEqual(M.headline(idle, true, true), "All synced")
  assert.strictEqual(M.headline(idle, false, true), "Config not encrypted")
  assert.strictEqual(M.headline(M.summarize([], {}), true, false), "Not set up · connect a drive to begin")
})

test("row controls", () => {
  assert.deepStrictEqual(M.rowControls(drive({ configured: false, mounted: false })), ["connect"])
  assert.deepStrictEqual(M.rowControls(drive()), ["open", "details", "disconnect", "toggle"])
  assert.deepStrictEqual(M.rowControls(drive({ mounted: false })), ["details", "disconnect", "toggle"])
  assert.strictEqual(M.primaryControl(drive()), "toggle")
})

test("cursor stops include only the expanded drive's details", () => {
  const drives = [drive(), drive({ id: "onedrive", mounted: false }), drive({ id: "dropbox", configured: false, mounted: false })]
  assert.strictEqual(M.navStops(drives, "").length, 3)
  const stops = M.navStops(drives, "onedrive", "maintenance")
  assert.deepStrictEqual(stops.map((s) => s.kind + ":" + s.id + (s.key ? ":" + s.key : "")), [
    "row:google", "row:onedrive",
    "detail:onedrive:tabs", "detail:onedrive:clearCache",
    "row:dropbox"])
  assert.ok(M.navStops(drives, "google", "maintenance").some((s) => s.key === "refresh"))
  assert.strictEqual(M.navStops(drives, "dropbox", "cache").length, 3, "an unconnected drive has no details")
})

test("each tab has its own cursor stops", () => {
  assert.deepStrictEqual(M.detailItems(drive(), "cache"), ["tabs", "cacheSize", "cacheAge"])
  assert.deepStrictEqual(M.detailItems(drive(), "behaviour"), ["tabs", "autostart", "readOnly", "notifications"])
})

test("stepOption stops at the ends and tolerates unknown values", () => {
  assert.strictEqual(M.stepOption(M.CACHE_SIZES, "4G", 1), "10G")
  assert.strictEqual(M.stepOption(M.CACHE_SIZES, "50G", 1), "50G")
  assert.strictEqual(M.stepOption(M.CACHE_SIZES, "1G", -1), "1G")
  assert.strictEqual(M.stepOption(M.CACHE_SIZES, "7G", 1), "4G")
})

test("tildePath", () => assert.strictEqual(M.tildePath("/home/bernard/Cloud/X"), "~/Cloud/X"))

test("settings read, change and step through their one table", () => {
  const d = drive({ settings: { cacheSize: "4G", cacheAge: "72h", readOnly: false, autostart: true } })
  assert.strictEqual(M.settingValue(d, "cache-size"), "4G")
  assert.strictEqual(M.settingValue(d, "read-only"), "false")
  assert.strictEqual(M.flipped(d, "read-only"), "true")
  assert.strictEqual(M.flipped(d, "autostart"), "false")
  assert.strictEqual(M.stepped(d, "cache-age", 1), "168h")
  const next = M.withSetting(d, "read-only", "true")
  assert.strictEqual(next.settings.readOnly, true)
  assert.strictEqual(d.settings.readOnly, false, "the original is untouched")
  assert.strictEqual(M.withSetting(d, "cache-size", "10G").settings.cacheSize, "10G")
})

test("every detail item that edits a setting names a real one", () => {
  for (const setting of Object.values(M.DETAIL_SETTING)) assert.ok(M.SETTINGS[setting], setting)
})

test("a row button maps to one action", () => {
  assert.deepStrictEqual(M.controlAction("toggle", drive()), { type: "unmount" })
  assert.deepStrictEqual(M.controlAction("toggle", drive({ mounted: false, unit: "activating" })), { type: "unmount" })
  assert.deepStrictEqual(M.controlAction("toggle", drive({ mounted: false, unit: "inactive" })), { type: "mount" })
  assert.deepStrictEqual(M.controlAction("disconnect", drive()), { type: "interactive", command: "disconnect" })
  assert.deepStrictEqual(M.controlAction("connect", drive()), { type: "interactive", command: "connect" })
  assert.deepStrictEqual(M.controlAction("open", drive()), { type: "open" })
  assert.deepStrictEqual(M.controlAction("details", drive()), { type: "details" })
  assert.strictEqual(M.controlAction("nonsense", drive()), null)
})

test("every control the cursor can reach has an action", () => {
  for (const d of [drive(), drive({ mounted: false }), drive({ configured: false, mounted: false })]) {
    for (const c of M.rowControls(d)) assert.ok(M.controlAction(c, d), c)
  }
})

test("a detail item activates to a setting, a refresh or a purge", () => {
  const d = drive({ settings: { cacheSize: "4G", cacheAge: "72h", readOnly: false, autostart: true } })
  assert.deepStrictEqual(M.detailAction(d, "readOnly"), { type: "set", key: "read-only", value: "true" })
  assert.deepStrictEqual(M.detailAction(d, "autostart"), { type: "set", key: "autostart", value: "false" })
  assert.deepStrictEqual(M.detailAction(d, "refresh"), { type: "refreshListing" })
  assert.deepStrictEqual(M.detailAction(d, "clearCache"), { type: "clearCache" })
  assert.strictEqual(M.detailAction(d, "tabs"), null)
})

test("every detail item the cursor can reach reacts to Enter or to h/l", () => {
  const d = drive({ settings: { cacheSize: "4G", cacheAge: "72h", readOnly: false, autostart: true } })
  for (const tab of M.DETAIL_TABS.map((t) => t.value)) {
    for (const item of M.detailItems(d, tab)) {
      assert.ok(M.detailAction(d, item) || M.stepAction(d, item, 1, tab), `${tab}/${item}`)
    }
  }
})

test("h and l step the tabs and the choice settings, and ignore toggles", () => {
  const d = drive({ settings: { cacheSize: "4G", cacheAge: "72h", readOnly: false, autostart: true } })
  assert.deepStrictEqual(M.stepAction(d, "tabs", 1, "cache"), { type: "tab", value: "behaviour" })
  assert.deepStrictEqual(M.stepAction(d, "cacheSize", -1, "cache"), { type: "set", key: "cache-size", value: "1G" })
  assert.deepStrictEqual(M.stepAction(d, "cacheAge", 1, "cache"), { type: "set", key: "cache-age", value: "168h" })
  assert.strictEqual(M.stepAction(d, "readOnly", 1, "behaviour"), null)
  assert.strictEqual(M.stepAction(d, "clearCache", 1, "maintenance"), null)
})

test("a mounted drive on the shared Google key shows a warning status", () => {
  const shared = drive({ sharedClientId: true })
  const status = M.driveStatus(shared, null, false)
  assert.strictEqual(status.kind, "failed")
  assert.match(status.text, /Shared Google key/)
  assert.strictEqual(M.driveStatus(drive(), null, false).kind, "synced")
})

test("alerts say a problem once, and again if it returns", () => {
  const announced = {}
  const failed = { drives: [drive({ name: "Google Drive", unit: "failed", mounted: false })], activity: {} }
  const ok = { drives: [drive({ name: "Google Drive" })], activity: {} }
  assert.strictEqual(M.alerts(failed, announced).length, 1)
  assert.strictEqual(M.alerts(failed, announced).length, 0)
  assert.strictEqual(M.alerts(ok, announced).length, 0)
  assert.strictEqual(M.alerts(failed, announced).length, 1)
})

test("alerts cover upload failures and the shared Google key", () => {
  const state = {
    drives: [drive({ name: "Google Drive", sharedClientId: true }), drive({ id: "r-x", name: "X", configured: false, sharedClientId: true })],
    activity: { google: { errored: 2 } },
  }
  const keys = M.alerts(state, {}).map((a) => a.key).sort()
  assert.deepStrictEqual(keys, ["google:shared", "google:upload"])
})

test("a drive with notifications off raises no alerts", () => {
  const state = { drives: [drive({ unit: "failed", mounted: false, settings: { notifications: false } })], activity: {} }
  assert.strictEqual(M.alerts(state, {}).length, 0)
})
