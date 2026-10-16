// One drive's settings: when it mounts, how its cache behaves, upkeep, and its account. The look is
// SettingsWindow's, the same as the main settings window. Every change applies the moment it is made
// and goes to `startdrive set`; the buttons run the action they name. The pages and their rules are
// DriveModel.settingsPages (so they are tested without the shell).
import QtQuick
import qs.Commons
import qs.Ui
import "DriveModel.js" as Model

SettingsWindow {
  id: view

  property var svc
  readonly property var cloud: view.svc.cloud
  readonly property var drive: view.svc.settingsDrive || ({ settings: {} })
  readonly property var activity: view.cloud.activity[view.drive.id] || null

  title: view.drive.name || ""
  titleGlyph: view.drive.glyph || ""
  subtitle: "SETTINGS"
  footerText: "Changes apply instantly"

  pages: Model.settingsPages(view.drive, { pending: Model.pending(view.activity), busy: view.cloud.busy, notes: view.svc.settingNotes })
  values: view.drive.settings || ({})
  initialPage: Model.settingsStartPage(view.drive)

  onVisibleChanged: if (visible) view.reset()
  Component.onCompleted: if (visible) view.reset()

  onChanged: function (key, value) {
    var d = view.drive
    var setting = Model.FIELD_SETTING[key]
    if (setting) view.cloud.set(d.id, setting, String(value))
    else view.svc.driveAction(key, d)
  }
}
