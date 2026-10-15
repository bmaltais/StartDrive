// The command line's input checks. Everything here fails before touching
// systemd, rclone or the keyring, so it is safe to run anywhere.
const test = require("node:test")
const assert = require("node:assert")
const { spawnSync } = require("node:child_process")
const path = require("node:path")
const fs = require("node:fs")
const os = require("node:os")

const script = path.join(__dirname, "..", "bin", "startdrive")
const run = (...args) => spawnSync(script, args, { encoding: "utf8" })

test("help lists the commands", () => {
  const r = run("--help")
  assert.strictEqual(r.status, 0)
  for (const word of ["state", "activity", "clear-cache", "set", "uninstall"]) assert.match(r.stdout, new RegExp(word))
})

test("an unknown command is refused", () => assert.strictEqual(run("nonsense").status, 2))

test("an unknown drive is refused", () => {
  for (const id of ["box", "r-", "r-../etc", "r-a b", "r-nothere", "r-$(id)", "--help"]) {
    const r = run("mount", id)
    assert.notStrictEqual(r.status, 0, id)
    assert.match(r.stderr, /unknown drive/, id)
  }
})

test("launch accepts add, and nothing else new", () => {
  const r = run("launch", "bogus")
  assert.match(r.stderr, /not an interactive command/)
})

test("settings accept only the allow-listed shapes", () => {
  const bad = [
    ["cache-size", "99X"], ["cache-size", "0G"], ["cache-size", "4G\nFOO=bar"], ["cache-size", "$(id)"],
    ["cache-age", "7d"], ["cache-age", "-1h"], ["read-only", "yes"], ["autostart", "1"], ["notifications", "no"], ["colour", "red"],
  ]
  for (const [key, value] of bad) {
    const r = run("set", "google", key, value)
    assert.notStrictEqual(r.status, 0, `${key}=${JSON.stringify(value)} should be refused`)
    assert.match(r.stderr, /invalid setting/)
  }
})

test("launch runs only the interactive commands", () => {
  for (const command of ["rm", "mount", "set", "clear-cache", "setup"]) {
    const r = run("launch", command, "google")
    assert.notStrictEqual(r.status, 0, command)
    assert.match(r.stderr, /not an interactive command/)
  }
})

// The panel's presets and the CLI's allow-list live in different languages; the
// presets must all be accepted by the CLI.
const root = path.join(__dirname, "..")
const bash = (script, env = {}) =>
  spawnSync("bash", ["-c", `source lib/common.sh; source lib/settings.sh; ${script}`], {
    cwd: root, encoding: "utf8", env: { ...process.env, ...env },
  })

test("every preset in the panel passes the CLI's allow-list", () => {
  const source = fs.readFileSync(path.join(root, "DriveModel.js"), "utf8").replace(/^\.pragma.*$/m, "")
  const M = new Function(source + "\nreturn { SETTINGS }")()
  for (const [key, setting] of Object.entries(M.SETTINGS)) {
    for (const option of setting.options || []) {
      assert.strictEqual(bash(`valid_setting ${key} ${option.value}`).status, 0, `${key}=${option.value}`)
    }
  }
})

test("settings are written whole and read back as the panel's JSON", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "startdrive-"))
  const env = { XDG_CONFIG_HOME: dir }
  try {
    const defaults = bash("settings_json google", env)
    // autostart is the unit's enablement, which belongs to the machine running the test.
    const { autostart, ...mount } = JSON.parse(defaults.stdout)
    assert.strictEqual(typeof autostart, "boolean")
    assert.deepStrictEqual(mount, { cacheSize: "4G", cacheAge: "72h", readOnly: false, notifications: true })
    assert.strictEqual(bash("write_settings google cache-size 10G && write_settings google read-only true", env).status, 0)
    const file = fs.readFileSync(path.join(dir, "startdrive", "GoogleDrive.env"), "utf8")
    assert.strictEqual(file, "RCLONE_VFS_CACHE_MAX_SIZE=10G\nRCLONE_VFS_CACHE_MAX_AGE=72h\nRCLONE_READ_ONLY=true\n")
    const stored = JSON.parse(bash("settings_json google", env).stdout)
    assert.deepStrictEqual([stored.cacheSize, stored.cacheAge, stored.readOnly], ["10G", "72h", true])
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})
