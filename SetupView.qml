// The settings window: launcher entry, command line, bar icon and the windows' memory. Shown once
// after the plugin is enabled, and again from the manager's gear button. Every change applies the
// moment it is made, as in StartBar; a change that cannot be made flips back and says why. The
// look is SettingsWindow's.
import QtQuick
import qs.Commons
import qs.Ui

SettingsWindow {
  id: view

  property var svc
  // key -> value, what the controls show. Filled from the system by refreshVals().
  property var vals: ({})

  readonly property var integ: view.svc.integ
  readonly property bool cliBlocked: !!(view.integ.cli && view.integ.cli.state === "other")

  title: "StartDrive"
  subtitle: "SETTINGS"
  values: view.vals
  footerText: view.integ.done ? "Changes apply instantly" : "Choose what to switch on. Changes apply instantly."

  // ---- what there is to set -----------------------------------------------------
  pages: [
    { title: "General", fields: [
      { key: "launcher", type: "bool", label: "App launcher entry",
        hint: "Adds StartDrive to the app launcher (SUPER + space) to open the manager." },
      { key: "cli", type: "bool", label: "Command line", disabled: view.cliBlocked,
        hint: view.cliBlocked
          ? view.integ.cli.path + " already exists and is not StartDrive, so it is left alone."
          : "Links " + (view.integ.cli ? view.integ.cli.path : "") + " so you can run startdrive in a terminal." }
    ] },
    { title: "Bar", fields: [
      { key: "barIcon", type: "bool", label: "Bar icon",
        hint: "A cloud on the Omarchy bar that opens the manager. It turns into an upload cloud while files are on their way, and a red alert cloud if one fails. You can drag it around the bar." }
    ] },
    { title: "Window", fields: [
      { key: "rsize", type: "bool", label: "Remember size",
        hint: "The manager reopens at the size you gave it. Drag its bottom-right corner to resize." },
      { key: "rpos", type: "bool", label: "Remember position",
        hint: "The manager reopens where you left it. Drag its top strip to move it. Switched off, it opens centred." }
    ] }
  ]

  // The command-line options that make each setting happen.
  readonly property var flags: ({
    launcher: "--launcher", cli: "--cli", barIcon: "--bar-icon", rsize: "--remember-size", rpos: "--remember-position"
  })

  onChanged: function (key, value) {
    var next = Object.assign({}, view.vals)
    next[key] = value
    view.vals = next
    view.svc.applySetting([view.flags[key], String(value)])
  }

  // What is switched on right now, read back from the system.
  function refreshVals() {
    var i = view.integ
    if (!i.cli) return
    view.vals = { launcher: i.launcher, cli: i.cli.state === "ours", barIcon: i.barIcon, rsize: i.rememberSize, rpos: i.rememberPosition }
  }
  onVisibleChanged: if (visible) { view.reset(); view.confirmingReset = false; view.refreshVals() }
  Connections {
    target: view.svc
    // Not while changes are still being made: the read-back would undo a click.
    function onIntegChanged() { if (view.visible && !view.svc.setupBusy) view.refreshVals() }
  }

  // The recommended set, in one go: what a first run offers, and what Reset goes back to.
  property bool confirmingReset: false
  Timer { id: resetTimer; interval: 3000; onTriggered: view.confirmingReset = false }
  function applyDefaults() {
    var d = view.integ.defaults  // the CLI's recommended set
    if (!d) return
    var v = { launcher: d.launcher, cli: d.cli && !view.cliBlocked, barIcon: d.barIcon, rsize: d.rememberSize, rpos: d.rememberPosition }
    view.vals = v
    var args = []
    for (var k in v) args.push(view.flags[k], String(v[k]))
    view.svc.applySetting(args)
  }

  // ---- footer ----------------------------------------------------------------------------
  // A first run offers the recommended set in one click, or to leave it for later.
  SettingsPill {
    visible: !view.integ.done
    text: "Not now"
    onClicked: view.svc.skipSetup()
  }
  SettingsPill {
    visible: !view.integ.done
    text: "Enable recommended"
    primary: true
    onClicked: view.applyDefaults()
  }
  // Afterwards, the one quiet way back.
  SettingsPill {
    visible: !!view.integ.done
    text: view.confirmingReset ? "Click again to reset everything" : "Reset to defaults"
    danger: view.confirmingReset
    onClicked: {
      if (view.confirmingReset) { view.confirmingReset = false; resetTimer.stop(); view.applyDefaults() }
      else { view.confirmingReset = true; resetTimer.restart() }
    }
  }
}
