// The manager: your drives, what each one is doing, and a way to add more. Opened from the
// launcher or the bar icon. Keyboard: Up/Down (or j/k) move, Enter does the row's main action,
// m mounts or unmounts, o opens the folder, s opens the settings, f forgets the account,
// a mounts or unmounts all, r refreshes, n adds a remote. Esc closes.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "DriveModel.js" as Model

FocusScope {
  id: view

  property var svc
  property int cursor: 0

  readonly property var cloud: view.svc.cloud
  readonly property var drives: view.cloud.drives
  readonly property var summary: view.cloud.summary
  readonly property var currentDrive: view.drives.length ? view.drives[Math.min(view.cursor, view.drives.length - 1)] : null
  readonly property string subtitle: {
    var s = view.summary
    var parts = []
    if (!view.cloud.rcloneInstalled && s.connected === 0) return "NOT SET UP"
    if (s.connected === 0) return "NO ACCOUNTS CONNECTED"
    parts.push(s.mounted + " MOUNTED")
    var line = Model.headline(s, view.cloud.secure, view.cloud.rcloneInstalled)
    if (s.mounted > 0 || s.errored > 0) parts.push(line.toUpperCase())
    return parts.join("  ·  ")
  }
  readonly property bool configWarning: view.summary.connected > 0 && !view.cloud.secure

  function move(dy) { view.cursor = Math.max(0, Math.min(view.drives.length - 1, view.cursor + dy)) }
  function focusList() { view.forceActiveFocus() }
  function short(path) {
    var home = Quickshell.env("HOME")
    return home !== "" && String(path).indexOf(home) === 0 ? "~" + String(path).substring(home.length) : path
  }

  onVisibleChanged: if (visible) { view.cursor = 0; view.forceActiveFocus() }
  onDrivesChanged: view.cursor = Math.max(0, Math.min(view.cursor, view.drives.length - 1))

  implicitHeight: col.implicitHeight + Style.spacing.panelPadding * 2

  Keys.onPressed: event => {
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    var d = view.currentDrive
    if (event.key === Qt.Key_Up || event.text === "k") { view.move(-1); event.accepted = true }
    else if (event.key === Qt.Key_Down || event.text === "j") { view.move(1); event.accepted = true }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (d) view.svc.dispatch(Model.clickAction(d), d)
      event.accepted = true
    } else if (event.text !== "") {
      var action = Model.keyAction(event.text, d, view.summary)
      if (action) { view.svc.dispatch(action, d); event.accepted = true }
    }
  }

  ColumnLayout {
    id: col
    anchors.fill: parent
    anchors.margins: Style.spacing.panelPadding
    spacing: Style.spacing.panelGap

    // Header
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.xxl

      Image {
        source: Qt.resolvedUrl("assets/startdrive.svg")
        sourceSize.width: Style.space(64)
        sourceSize.height: Style.space(64)
        Layout.preferredWidth: Style.space(32)
        Layout.preferredHeight: Style.space(32)
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Text {
          text: "StartDrive"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }
        Text {
          Layout.fillWidth: true
          elide: Text.ElideRight
          text: view.subtitle
          color: view.summary.errored > 0 || view.summary.failed > 0 ? Color.urgent : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }
      }
      Button {
        visible: view.summary.connected > 1
        text: view.summary.mounted === view.summary.connected ? "Unmount all" : "Mount all"
        enabled: !view.cloud.busy
        tooltipText: "Mount or unmount every drive  (a)"
        onClicked: view.svc.dispatch({ type: view.summary.mounted === view.summary.connected ? "unmountAll" : "mountAll" }, null)
      }
      Button {
        iconText: ""
        tooltipText: "Settings"
        onClicked: view.svc.showSetup()
      }
      Button {
        iconText: ""
        tooltipText: "Look at the drives again  (r)"
        iconSpinning: spin.running
        onClicked: { spin.restart(); view.svc.refreshAll() }
        Timer { id: spin; interval: 900 }
      }
      // Keeps clear of the close button in the card's corner.
      Item { Layout.preferredWidth: Style.space(24) }
    }

    // Section label
    Text {
      text: "DRIVES"
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }

    // List, with a scroll bar when there are more drives than fit
    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredHeight: list.contentHeight
      spacing: Style.spacing.md

      ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: contentHeight
        clip: true
        spacing: Style.spacing.lg
        model: view.drives
        currentIndex: view.cursor
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: DriveRow {
          required property var modelData
          required property int index
          width: ListView.view.width
          drive: modelData
          activity: view.cloud.activity[modelData.id] || null
          usage: view.cloud.usage[modelData.id] || null
          current: index === view.cursor
          working: view.cloud.busyId === modelData.id || view.cloud.busyId === "*"
          locked: view.cloud.busy
          onSelectRequested: { view.cursor = index; view.forceActiveFocus() }
          onClickRequested: view.svc.dispatch(Model.clickAction(modelData), modelData)
          onToggleRequested: view.svc.dispatch(Model.toggleAction(modelData), modelData)
          onOpenRequested: view.svc.dispatch({ type: "open" }, modelData)
          onSettingsRequested: view.svc.dispatch({ type: "settings" }, modelData)
          onForgetRequested: view.svc.dispatch({ type: "interactive", command: "disconnect" }, modelData)
          onConnectRequested: view.svc.dispatch({ type: "interactive", command: "connect" }, modelData)
        }
      }

      ScrollTrack {
        target: list
        Layout.fillHeight: true
        Layout.preferredWidth: implicitWidth
      }
    }

    // Nothing connected yet: say where the drives will appear.
    Text {
      Layout.fillWidth: true
      visible: view.summary.connected === 0
      wrapMode: Text.WordWrap
      text: "Connect a drive and it appears as a folder under " + view.short(view.cloud.mountRoot || "~/Cloud") + "."
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      Layout.fillWidth: true
      visible: view.configWarning
      wrapMode: Text.WordWrap
      text: "The rclone config is not keyring-encrypted. Reconnect a drive to fix this."
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    // Footer: add button on the left, the latest message or a hint on the right
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.xxl

      Button {
        text: "+  Add remote…"
        bordered: true
        enabled: !view.cloud.busy
        tooltipText: "Add any other rclone remote  (n)"
        onClicked: view.svc.dispatch({ type: "add" }, null)
      }
      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        text: view.svc.notice !== "" ? view.svc.notice : "Esc to close"
        color: view.svc.notice !== "" && view.svc.noticeIsError ? Color.urgent : Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
