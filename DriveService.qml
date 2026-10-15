// Everything the panel knows about the drives, and the only thing that talks
// to bin/startdrive. State, transfer activity and storage usage are polled
// (faster while the panel is open); actions run one at a time and report back
// through `notice` and `error`.

import QtQuick
import Quickshell
import Quickshell.Io
import "DriveModel.js" as Model

Item {
  id: service

  required property string script
  property bool panelOpen: false

  property bool rcloneInstalled: false
  property bool encrypted: false
  property bool keyring: false
  property string mountRoot: ""
  property var drives: []
  property var activity: ({})   // drive id -> one entry of `startdrive activity`
  property var usage: ({})      // drive id -> { used, total } from `startdrive about`

  // "" when idle, a drive id while one of its actions runs, "*" for all drives.
  property string busyId: ""
  property string error: ""
  property string notice: ""

  readonly property bool busy: busyId !== ""
  readonly property var summary: Model.summarize(drives, activity)
  readonly property bool secure: rcloneInstalled && encrypted && keyring

  function drive(id) {
    for (var i = 0; i < drives.length; i++) if (drives[i].id === id) return drives[i]
    return null
  }

  function refresh() { if (!stateProc.running) stateProc.running = true }
  function refreshActivity() { if (!activityProc.running) activityProc.running = true }

  function refreshUsage() {
    var queue = []
    for (var i = 0; i < drives.length; i++) if (drives[i].mounted) queue.push(drives[i].id)
    aboutQueue = queue
    nextAbout()
  }

  // Run a non-interactive action (mount, unmount, set, clear-cache...). Only
  // one at a time: the panel disables its controls while `busy`.
  function run(args, who) {
    if (busy) return
    error = ""
    notice = ""
    busyId = who
    actionProc.command = [script].concat(args)
    actionProc.running = true
  }

  function mount(id) { run(["mount", id], id) }
  function unmount(id) { run(["unmount", id], id) }
  function mountAll() { run(["mount-all"], "*") }
  function unmountAll() { run(["unmount-all"], "*") }
  function clearCache(id) { run(["clear-cache", id], id) }
  function refreshListing(id) { run(["refresh-listing", id], id) }

  // Settings show their new value at once; the next poll confirms it.
  function set(id, key, value) {
    var field = ({ "cache-size": "cacheSize", "cache-age": "cacheAge", "read-only": "readOnly", "autostart": "autostart" })[key]
    var next = drives.map(function (d) {
      if (d.id !== id) return d
      var settings = Object.assign({}, d.settings)
      settings[field] = (key === "read-only" || key === "autostart") ? value === "true" : value
      return Object.assign({}, d, { settings: settings })
    })
    drives = next
    run(["set", id, key, value], id)
  }

  // Steps that need you (sign-in, 2FA, confirmation) run in a floating terminal.
  function interactive(command, id) {
    Quickshell.execDetached([script, "launch", command, id])
  }
  function addRemote() { Quickshell.execDetached([script, "launch", "add"]) }
  function openDrive(id) { Quickshell.execDetached([script, "open", id]) }
  function openRoot() { Quickshell.execDetached(["xdg-open", mountRoot]) }

  property var aboutQueue: []
  function nextAbout() {
    if (aboutProc.running || aboutQueue.length === 0) return
    aboutProc.driveId = aboutQueue[0]
    aboutQueue = aboutQueue.slice(1)
    aboutProc.command = [script, "about", aboutProc.driveId]
    aboutProc.running = true
  }

  Component.onCompleted: refresh()

  // Mounts change under us (terminal flows, failures), so poll: quickly while
  // the panel is open, slowly otherwise. Usage asks the cloud, so it is rarer.
  Timer {
    interval: service.panelOpen ? 2000 : 30000
    running: true
    repeat: true
    onTriggered: service.refresh()
  }
  Timer {
    interval: service.panelOpen ? 2000 : 10000
    running: service.summary.mounted > 0
    repeat: true
    onTriggered: service.refreshActivity()
  }
  Timer {
    interval: 120000
    running: service.panelOpen
    repeat: true
    onTriggered: service.refreshUsage()
  }

  Process {
    id: stateProc
    command: [service.script, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var s
        try { s = JSON.parse(String(text || "{}")) } catch (e) { return }
        service.rcloneInstalled = !!s.rclone
        service.encrypted = !!s.encrypted
        service.keyring = !!s.keyring
        service.mountRoot = s.root || ""
        service.drives = s.drives || []
        // Mounts from before the rebrand are moved to the new unit, once.
        if (s.legacy && !migrateProc.running) migrateProc.running = true
      }
    }
  }

  Process {
    id: activityProc
    command: [service.script, "activity"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = {}
          var list = JSON.parse(String(text || "[]"))
          for (var i = 0; i < list.length; i++) next[list[i].id] = list[i]
          service.activity = next
        } catch (e) { /* keep the last figures */ }
      }
    }
  }

  Process {
    id: aboutProc
    property string driveId: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = Object.assign({}, service.usage)
          next[aboutProc.driveId] = JSON.parse(String(text || "{}"))
          service.usage = next
        } catch (e) { /* no usage for this drive */ }
      }
    }
    onRunningChanged: if (!running) service.nextAbout()
  }

  Process {
    id: migrateProc
    command: [service.script, "migrate"]
    onRunningChanged: if (!running) service.refresh()
  }

  Process {
    id: actionProc
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function (code) {
      var last = function (text) {
        var lines = String(text || "").trim().split("\n")
        return lines[lines.length - 1]
      }
      if (code !== 0) service.error = last(actionErr.text) || "The action failed"
      else service.notice = last(actionOut.text)
      service.busyId = ""
      service.refresh()
      service.refreshActivity()
      service.refreshUsage()
    }
  }
}
