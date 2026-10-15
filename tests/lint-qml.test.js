// scripts/lint-qml.py must never let a real bug into the baseline: a property that shadows one of Item's own, a property bound twice.
// Needs qmllint, so it is skipped where Qt is not installed (CI).
const test = require("node:test")
const assert = require("node:assert")
const { spawnSync } = require("node:child_process")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")

const script = path.join(__dirname, "..", "scripts", "lint-qml.py")
const haveQmllint = ["qmllint", "qmllint6", "/usr/lib/qt6/bin/qmllint"].some((c) => spawnSync(c, ["--version"]).status === 0)

// A throwaway project with one QML file and an empty baseline.
function project(qml) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "lintqml-"))
  fs.mkdirSync(path.join(dir, "scripts"))
  fs.writeFileSync(path.join(dir, "scripts", "qmllint-baseline.txt"), "")
  fs.writeFileSync(path.join(dir, "Thing.qml"), qml)
  return dir
}
const lint = (dir, ...args) => spawnSync("python3", [script, ...args], { encoding: "utf8", env: { ...process.env, LINT_QML_ROOT: dir } })

test("a property that shadows an Item member fails, even with --update", { skip: !haveQmllint }, () => {
  const dir = project("import QtQuick\nItem {\n  property var data: ({})\n}\n")
  try {
    for (const args of [[], ["--update"]]) {
      const r = lint(dir, ...args)
      assert.strictEqual(r.status, 1, `lint-qml ${args.join(" ")} should fail: ${r.stdout}`)
      assert.match(r.stderr, /bugs, not noise/)
      assert.match(r.stderr, /property-override/)
    }
    assert.strictEqual(fs.readFileSync(path.join(dir, "scripts", "qmllint-baseline.txt"), "utf8"), "", "the baseline was not written")
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})

test("a property bound twice fails", { skip: !haveQmllint }, () => {
  const dir = project("import QtQuick\nItem {\n  width: 1\n  width: 2\n}\n")
  try {
    const r = lint(dir)
    assert.strictEqual(r.status, 1, r.stdout)
    assert.match(r.stderr, /duplicate-property-binding/)
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})

test("a clean file passes", { skip: !haveQmllint }, () => {
  const dir = project("import QtQuick\nItem {\n  property int count: 0\n}\n")
  try {
    const r = lint(dir)
    assert.strictEqual(r.status, 0, r.stderr)
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})
