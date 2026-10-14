// The command line's input checks. Everything here fails before touching
// systemd, rclone or the keyring, so it is safe to run anywhere.
const test = require("node:test")
const assert = require("node:assert")
const { spawnSync } = require("node:child_process")
const path = require("node:path")

const script = path.join(__dirname, "..", "bin", "startdrive")
const run = (...args) => spawnSync(script, args, { encoding: "utf8" })

test("help lists the commands", () => {
  const r = run("--help")
  assert.strictEqual(r.status, 0)
  for (const word of ["state", "activity", "clear-cache", "set", "uninstall"]) assert.match(r.stdout, new RegExp(word))
})

test("an unknown command is refused", () => assert.strictEqual(run("nonsense").status, 2))

test("an unknown drive is refused", () => {
  const r = run("mount", "dropbox")
  assert.notStrictEqual(r.status, 0)
  assert.match(r.stderr, /unknown drive/)
})

test("settings accept only the allow-listed shapes", () => {
  const bad = [
    ["cache-size", "99X"], ["cache-size", "0G"], ["cache-size", "4G\nFOO=bar"], ["cache-size", "$(id)"],
    ["cache-age", "7d"], ["cache-age", "-1h"], ["read-only", "yes"], ["autostart", "1"], ["colour", "red"],
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
