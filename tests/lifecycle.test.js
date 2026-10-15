// The rules that protect files still uploading, run against a fake systemctl
// and a fake rclone remote-control socket, so no real mount is touched.
const test = require("node:test")
const assert = require("node:assert")
const { spawn } = require("node:child_process")
const fs = require("node:fs")
const http = require("node:http")
const os = require("node:os")
const path = require("node:path")

const root = path.join(__dirname, "..")

// A sandbox: fake systemctl on PATH (logging to calls.log), a cache holding
// one file, and, when `queue` is given, a mount answering vfs/queue with it.
async function sandbox({ active, queue }, script) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "sd-"))
  const bin = path.join(dir, "bin")
  const runtime = path.join(dir, "run")
  const cache = path.join(dir, "cache")
  fs.mkdirSync(bin)
  fs.mkdirSync(path.join(runtime, "startdrive", "GoogleDrive"), { recursive: true })
  fs.mkdirSync(path.join(cache, "rclone", "vfs", "GoogleDrive"), { recursive: true })
  fs.writeFileSync(path.join(cache, "rclone", "vfs", "GoogleDrive", "file"), "x")
  fs.writeFileSync(path.join(bin, "systemctl"),
    `#!/usr/bin/env bash\necho "$*" >>"${dir}/calls.log"\n[[ "$2" == is-active ]] && exit ${active ? 0 : 3}\nexit 0\n`, { mode: 0o755 })

  let server
  if (queue !== undefined) {
    server = http.createServer((req, res) => {
      res.setHeader("Content-Type", "application/json")
      res.end(JSON.stringify({ queue }))
    })
    await new Promise((resolve) => server.listen(path.join(runtime, "startdrive", "GoogleDrive", "rc.sock"), resolve))
  }
  try {
    const result = await new Promise((resolve) => {
      const child = spawn("bash", ["-c", `source lib/common.sh; source lib/system.sh; source lib/drive.sh; source lib/rc.sh; source lib/lifecycle.sh; source lib/cache.sh; source lib/settings.sh; ${script}`], {
        cwd: root,
        env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, XDG_RUNTIME_DIR: runtime, XDG_CACHE_HOME: cache, XDG_CONFIG_HOME: path.join(dir, "config"), RC_TIMEOUT: "3" },
      })
      let stdout = "", stderr = ""
      child.stdout.on("data", (d) => (stdout += d))
      child.stderr.on("data", (d) => (stderr += d))
      child.on("close", (status) => resolve({ status, stdout, stderr }))
    })
    const read = (f) => { try { return fs.readFileSync(f, "utf8") } catch { return "" } }
    result.calls = read(path.join(dir, "calls.log")).trim().split("\n").filter(Boolean)
    result.cached = fs.existsSync(path.join(cache, "rclone", "vfs", "GoogleDrive", "file"))
    return result
  } finally {
    if (server) await new Promise((resolve) => server.close(resolve))
    fs.rmSync(dir, { recursive: true, force: true })
  }
}

const stopped = (calls) => calls.some((c) => c.includes("stop "))
const started = (calls) => calls.some((c) => c.includes("start "))

test("clearing the cache of an unmounted drive just deletes it", async () => {
  const r = await sandbox({ active: false }, "cmd_clear_cache google")
  assert.strictEqual(r.status, 0, r.stderr)
  assert.strictEqual(r.cached, false)
  assert.ok(!stopped(r.calls) && !started(r.calls))
})

test("clearing the cache stops an idle mount, deletes, and mounts again", async () => {
  const r = await sandbox({ active: true, queue: [] }, "cmd_clear_cache google")
  assert.strictEqual(r.status, 0, r.stderr)
  assert.strictEqual(r.cached, false)
  assert.ok(stopped(r.calls) && started(r.calls))
})

test("clearing the cache is refused while files are uploading", async () => {
  const r = await sandbox({ active: true, queue: [{ uploading: true }, {}] }, "cmd_clear_cache google")
  assert.notStrictEqual(r.status, 0)
  assert.match(r.stderr, /2 file\(s\) are still uploading/)
  assert.strictEqual(r.cached, true)
  assert.ok(!stopped(r.calls))
})

test("clearing the cache is refused when the queue cannot be read", async () => {
  const r = await sandbox({ active: true }, "cmd_clear_cache google")
  assert.notStrictEqual(r.status, 0)
  assert.match(r.stderr, /cannot tell whether uploads are pending/)
  assert.strictEqual(r.cached, true)
  assert.ok(!stopped(r.calls))
})

test("a changed mount option restarts an idle mount and defers otherwise", async () => {
  const idle = await sandbox({ active: true, queue: [] }, "cmd_set google cache-size 10G")
  assert.match(idle.stdout, /Saved and applied/)
  assert.ok(idle.calls.some((c) => c.includes("restart ")))

  const busy = await sandbox({ active: true, queue: [{ uploading: true }] }, "cmd_set google cache-size 10G")
  assert.match(busy.stdout, /Applies at the next mount/)
  assert.ok(!busy.calls.some((c) => c.includes("restart ")))

  const unknown = await sandbox({ active: true }, "cmd_set google cache-size 10G")
  assert.match(unknown.stdout, /Applies at the next mount/)
  assert.ok(!unknown.calls.some((c) => c.includes("restart ")))

  const off = await sandbox({ active: false }, "cmd_set google cache-size 10G")
  assert.match(off.stdout, /Applies when mounted/)
})
