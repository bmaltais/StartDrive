const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")

// DriveModel.js is a QML library; load it as a plain script.
const source = fs.readFileSync(path.join(__dirname, "..", "DriveModel.js"), "utf8").replace(/^\.pragma.*$/m, "")
const M = new Function(source + "\nreturn { formatBytes, formatSpeed, usageText, usageFraction, driveStatus, summarize, headline, GLYPH, CACHE_SIZES, CACHE_AGES, SETTINGS, FIELD_SETTING, withSetting, clickAction, toggleAction, keyAction, transferLine, settingsPages, settingsStartPage, alerts }")()

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
  assert.strictEqual(idle.kind, "mounted")
  const up = M.summarize(drives, { google: { uploading: 1, queued: 0, speed: 5, errored: 0 } })
  assert.strictEqual(up.glyph, M.GLYPH.uploading)
  assert.strictEqual(up.kind, "uploading")
  assert.strictEqual(M.headline(up, true, true), "Uploading 1 file · 5 B/s")
  const bad = M.summarize(drives, { google: { uploading: 1, queued: 0, errored: 1 } })
  assert.strictEqual(bad.glyph, M.GLYPH.alert)
  assert.strictEqual(bad.kind, "alert")
  assert.strictEqual(M.summarize([drive({ mounted: false })], {}).glyph, M.GLYPH.idle)
  assert.strictEqual(M.headline(idle, true, true), "All synced")
  assert.strictEqual(M.headline(idle, false, true), "Config not encrypted")
  assert.strictEqual(M.headline(M.summarize([], {}), true, false), "Not set up · connect a drive to begin")
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

const settings = { cacheSize: "4G", cacheAge: "72h", readOnly: false, autostart: true, notifications: true }

test("a setting changes in a copy, to show before the next poll", () => {
  const d = drive({ settings })
  const next = M.withSetting(d, "read-only", "true")
  assert.strictEqual(next.settings.readOnly, true)
  assert.strictEqual(d.settings.readOnly, false, "the original is untouched")
  assert.strictEqual(M.withSetting(d, "cache-size", "10G").settings.cacheSize, "10G")
})

test("every settings field maps to a setting the CLI knows", () => {
  for (const setting of Object.values(M.FIELD_SETTING)) assert.ok(M.SETTINGS[setting], setting)
  const fields = M.settingsPages(drive({ settings, sharedClientId: true }), {}).flatMap((p) => p.fields)
  for (const f of fields.filter((f) => f.type === "bool" || f.type === "choice")) assert.ok(M.FIELD_SETTING[f.key], f.key)
})

test("a click or Enter on a row connects, opens or mounts", () => {
  assert.deepStrictEqual(M.clickAction(drive({ configured: false, mounted: false })), { type: "interactive", command: "connect" })
  assert.deepStrictEqual(M.clickAction(drive()), { type: "open" })
  assert.deepStrictEqual(M.clickAction(drive({ mounted: false, unit: "inactive" })), { type: "mount" })
})

test("the switch mounts, or unmounts a drive that is mounted or on its way", () => {
  assert.deepStrictEqual(M.toggleAction(drive()), { type: "unmount" })
  assert.deepStrictEqual(M.toggleAction(drive({ mounted: false, unit: "activating" })), { type: "unmount" })
  assert.deepStrictEqual(M.toggleAction(drive({ mounted: false, unit: "inactive" })), { type: "mount" })
})

test("keys: one letter, one action, and only where it makes sense", () => {
  const summary = M.summarize([drive(), drive({ id: "onedrive", mounted: false })], {})
  assert.deepStrictEqual(M.keyAction("r", null, summary), { type: "refresh" })
  assert.deepStrictEqual(M.keyAction("N", null, summary), { type: "add" })
  assert.deepStrictEqual(M.keyAction("a", null, summary), { type: "mountAll" })
  const all = M.summarize([drive(), drive({ id: "onedrive" })], {})
  assert.deepStrictEqual(M.keyAction("a", null, all), { type: "unmountAll" })
  assert.strictEqual(M.keyAction("a", null, M.summarize([], {})), null, "nothing connected, nothing to mount")
  assert.deepStrictEqual(M.keyAction("m", drive(), summary), { type: "unmount" })
  assert.deepStrictEqual(M.keyAction("m", drive({ configured: false, mounted: false }), summary), { type: "interactive", command: "connect" })
  assert.deepStrictEqual(M.keyAction("o", drive(), summary), { type: "open" })
  assert.strictEqual(M.keyAction("o", drive({ mounted: false }), summary), null)
  assert.deepStrictEqual(M.keyAction("s", drive(), summary), { type: "settings" })
  assert.strictEqual(M.keyAction("s", drive({ configured: false, mounted: false }), summary), null)
  assert.deepStrictEqual(M.keyAction("f", drive(), summary), { type: "interactive", command: "disconnect" })
  assert.strictEqual(M.keyAction("f", drive({ configured: false, mounted: false }), summary), null)
  assert.strictEqual(M.keyAction("m", null, summary), null, "no row under the cursor")
  assert.strictEqual(M.keyAction("x", drive(), summary), null)
})

test("a row shows the first transfer and how many more wait", () => {
  assert.strictEqual(M.transferLine(null), null)
  assert.strictEqual(M.transferLine({ uploading: 0, queued: 2, transfers: [] }), null)
  const line = M.transferLine({ uploading: 2, queued: 1, transfers: [{ name: "a.mov", percentage: 61.4, speed: 1900000 }, { name: "b.pdf", percentage: 5, speed: 0 }] })
  assert.deepStrictEqual([line.name, line.percent, line.speed, line.more], ["a.mov", 61, "1.9 MB/s", 2])
  assert.strictEqual(M.transferLine({ uploading: 1, queued: 0, transfers: [{ name: "x", percentage: 250 }] }).percent, 100)
})

test("a drive's settings window has four pages and starts on the first", () => {
  const pages = M.settingsPages(drive({ settings }), { pending: 0 })
  assert.deepStrictEqual(pages.map((p) => p.title), ["Behaviour", "Cache", "Maintenance", "Account"])
  assert.strictEqual(M.settingsStartPage(drive({ settings })), 0)
  assert.strictEqual(M.settingsStartPage(drive({ settings, sharedClientId: true })), 3, "the shared key goes straight to its fix")
  const keys = pages.flatMap((p) => p.fields.map((f) => f.key))
  assert.deepStrictEqual(keys, ["autostart", "readOnly", "notifications", "cacheSize", "cacheAge", "refresh", "clearCache", "forget"])
  assert.deepStrictEqual(pages[1].fields[0].options, M.CACHE_SIZES)
})

test("maintenance explains why a button is off", () => {
  const field = (d, ctx, key) => M.settingsPages(d, ctx).flatMap((p) => p.fields).find((f) => f.key === key)
  const idle = drive({ settings, mounted: false, cacheBytes: 0 })
  assert.strictEqual(field(idle, { pending: 0 }, "refresh").disabled, true)
  assert.match(field(idle, { pending: 0 }, "refresh").hint, /Mount the drive/)
  assert.strictEqual(field(drive({ settings }), { pending: 0 }, "refresh").disabled, false)
  const waiting = field(drive({ settings }), { pending: 3 }, "clearCache")
  assert.strictEqual(waiting.disabled, true)
  assert.match(waiting.hint, /3 files/)
  assert.match(field(drive({ settings, cacheBytes: 312000000 }), { pending: 0 }, "clearCache").hint, /^312 MB on disk/)
  assert.strictEqual(field(drive({ settings }), { pending: 0, busy: true }, "forget").disabled, true)
})

test("the Google key action is offered only on the shared key", () => {
  const keys = (d) => M.settingsPages(d, { pending: 0 })[3].fields.map((f) => f.key)
  assert.deepStrictEqual(keys(drive({ settings })), ["forget"])
  assert.deepStrictEqual(keys(drive({ settings, sharedClientId: true })), ["clientId", "forget"])
})

test("a button's answer goes under the button", () => {
  const pages = M.settingsPages(drive({ settings }), { pending: 0, notes: { clearCache: { kind: "ok", text: "Cache cleared." } } })
  const clear = pages[2].fields.find((f) => f.key === "clearCache")
  assert.deepStrictEqual(clear.note, { kind: "ok", text: "Cache cleared." })
  assert.strictEqual(pages[2].fields.find((f) => f.key === "refresh").note.text, "")
})

test("feedback goes under the setting it is about", () => {
  const pages = M.settingsPages(drive({ settings }), { pending: 0, notes: { cacheSize: { kind: "bad", text: "nope" } } })
  assert.deepStrictEqual(pages[1].fields[0].note, { kind: "bad", text: "nope" })
  assert.strictEqual(pages[1].fields[1].note.text, "")
})
