// The Omarchy plugin marketplace's rules for a listing, checked without Omarchy
// installed (the pre-commit hook also runs `omarchy plugin validate`).
const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")

const root = path.join(__dirname, "..")
const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))

test("all required manifest fields are present", () => {
  assert.strictEqual(manifest.schemaVersion, 1)
  for (const field of ["id", "name", "version", "author", "description"]) {
    assert.strictEqual(typeof manifest[field], "string", field)
    assert.ok(manifest[field].length > 0, field)
  }
  assert.ok(manifest.version.length <= 64)
  assert.ok(Array.isArray(manifest.kinds) && manifest.kinds.length > 0)
  assert.strictEqual(typeof manifest.entryPoints, "object")
})

test("the id is namespaced and not first-party", () => {
  assert.match(manifest.id, /^[A-Za-z0-9][A-Za-z0-9._-]*$/)
  assert.ok(!manifest.id.includes(".."))
  assert.ok(!manifest.id.startsWith("omarchy."))
  assert.ok(manifest.id.includes("."), "namespaced, e.g. io.github.<user>.<name>")
})

test("a service stays loaded, and the bar icon is optional", () => {
  assert.ok(manifest.kinds.includes("service"))
  assert.strictEqual(manifest.keepLoaded, true)
  assert.ok(manifest.entryPoints.service)
  assert.strictEqual(manifest.activation, undefined, "the service is always loaded")
})

test("a bar-widget declares its entry point and widget block", () => {
  assert.ok(manifest.kinds.includes("bar-widget"))
  assert.ok(manifest.entryPoints.barWidget)
  assert.ok(["left", "center", "tray", "right"].includes(manifest.barWidget.defaultSection))
})

test("entry points are safe relative paths to files that exist", () => {
  for (const file of Object.values(manifest.entryPoints)) {
    assert.ok(!path.isAbsolute(file) && !file.includes(".."), file)
    assert.ok(fs.statSync(path.join(root, file)).isFile(), file)
  }
})

test("the repository has a README and a license, and no clonedFrom", () => {
  assert.ok(fs.existsSync(path.join(root, "README.md")))
  assert.ok(fs.existsSync(path.join(root, "LICENSE")))
  assert.strictEqual(manifest.omarchy, undefined)
})

test("no symlinks anywhere in the plugin folder", () => {
  const found = []
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.name === ".git" || entry.name === "node_modules") continue
      const full = path.join(dir, entry.name)
      if (entry.isSymbolicLink()) found.push(full)
      else if (entry.isDirectory()) walk(full)
    }
  }
  walk(root)
  assert.deepStrictEqual(found, [])
})

test("QML never starts a second Quickshell or evaluates strings as commands", () => {
  for (const file of fs.readdirSync(root).filter((f) => f.endsWith(".qml"))) {
    const text = fs.readFileSync(path.join(root, file), "utf8")
    assert.ok(!/\bquickshell\b.*execDetached\(\["quickshell/i.test(text), file)
    assert.ok(!/\bbash\b.*-c|\beval\(/.test(text), `${file} runs a shell string`)
  }
})
