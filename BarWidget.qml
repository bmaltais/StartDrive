// The optional bar icon: a cloud that says how the drives are doing, and opens the manager.
// It is on the bar only when the user chose it in the settings window. What it draws comes from
// a file the service keeps up to date (idle, mounted, uploading, alert), because the icon and the
// service are separate instances.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "DriveModel.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.bmaltais.startdrive"

  readonly property string statusFile: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/startdrive/status"
  property string kind: "idle"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    path: root.statusFile
    // The file does not exist until the service has first looked at the drives (a fresh install): that is "idle", not an error.
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { var k = text().trim(); root.kind = Model.GLYPH[k] !== undefined ? k : "idle" }
    onLoadFailed: root.kind = "idle"
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.GLYPH[root.kind]
    // Accent while files are on their way up, red when something failed.
    active: root.kind === "uploading" || root.kind === "alert"
    useActiveColor: true
    activeColor: root.kind === "alert" ? Color.urgent : Color.accent
    onPressed: function (mouse) {
      if (!root.bar) return
      // Right click looks at the drives again; left click opens the manager.
      if (mouse === Qt.RightButton) root.bar.run("omarchy-shell io.github.bmaltais.startdrive refresh")
      else root.bar.run("omarchy-shell io.github.bmaltais.startdrive open")
    }
  }
}
