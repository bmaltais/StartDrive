// One drive: its cloud, name, status and storage, what is moving now, and its actions. The
// manager owns the cursor and every decision; this file only paints and says what was asked for.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "DriveModel.js" as Model

Rectangle {
  id: row

  property var drive: ({})
  property var activity: null        // this drive's entry of `startdrive activity`, or null
  property var usage: null           // { used, total } from `startdrive about`, or null
  property bool current: false       // under the keyboard cursor
  property bool working: false       // an action on this drive (or on all) is running
  property bool locked: false        // any action is running: the controls wait

  signal clickRequested()            // the row itself: connect, open or mount
  signal toggleRequested()
  signal openRequested()
  signal settingsRequested()
  signal forgetRequested()
  signal connectRequested()
  signal selectRequested()

  readonly property var status: Model.driveStatus(row.drive, row.activity, row.working)
  readonly property real fraction: Model.usageFraction(row.usage)
  readonly property string usageLine: row.drive.mounted ? Model.usageText(row.usage) : ""
  readonly property var transfer: row.drive.mounted ? Model.transferLine(row.activity) : null
  readonly property bool hot: hover.hovered || row.current

  implicitHeight: Math.max(Style.space(62), body.implicitHeight + Style.spacing.lg * 2)
  radius: Math.max(Style.cornerRadius, Style.space(6))
  color: Util.alpha(Color.foreground, row.hot ? 0.10 : 0.05)
  border.width: Style.normalBorderWidth
  border.color: row.current ? Util.alpha(Color.accent, 0.7) : Util.alpha(Color.foreground, 0.06)

  HoverHandler { id: hover }
  // The row itself is the main action; the buttons are above it and keep their own clicks.
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: { row.selectRequested(); row.clickRequested() }
  }

  RowLayout {
    id: body
    anchors.fill: parent
    anchors.leftMargin: Style.spacing.xxl
    anchors.rightMargin: Style.spacing.lg
    spacing: Style.spacing.xxl

    // The drive's cloud on a tile, dimmed until it is connected.
    Rectangle {
      Layout.preferredWidth: Style.space(36)
      Layout.preferredHeight: Style.space(36)
      Layout.alignment: Qt.AlignVCenter
      radius: Style.space(8)
      color: Util.alpha(Color.foreground, 0.10)
      opacity: row.drive.configured ? 1 : 0.55
      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: row.drive.glyph || ""
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.display
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: Style.spacing.xxs

      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: row.drive.name || row.drive.id
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.md
        Rectangle {
          id: dot
          visible: row.drive.configured
          Layout.preferredWidth: Style.space(7)
          Layout.preferredHeight: Style.space(7)
          radius: width / 2
          color: row.status.kind === "failed" ? Color.urgent
            : (row.status.kind === "synced" || row.status.kind === "working") ? Color.accent
            : Util.alpha(Color.foreground, 0.35)
          SequentialAnimation on opacity {
            running: row.status.kind === "working"
            loops: Animation.Infinite
            NumberAnimation { to: 0.25; duration: 500 }
            NumberAnimation { to: 1; duration: 500 }
          }
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: row.status.text
          color: row.status.kind === "failed" ? Color.urgent : row.status.kind === "working" ? Color.accent : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }

      // What is moving now: the first file, its progress and speed.
      ColumnLayout {
        Layout.fillWidth: true
        visible: row.transfer !== null
        spacing: Style.space(3)
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.lg
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText   // file names come from the cloud
            text: row.transfer ? row.transfer.name : ""
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }
          Text {
            textFormat: Text.PlainText
            text: row.transfer ? row.transfer.percent + "%"
              + (row.transfer.speed !== "" ? "  ·  " + row.transfer.speed : "")
              + (row.transfer.more > 0 ? "  ·  +" + row.transfer.more + " more" : "") : ""
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(3)
          radius: height / 2
          color: Util.alpha(Color.foreground, 0.12)
          Rectangle {
            width: parent.width * (row.transfer ? row.transfer.fraction : 0)
            height: parent.height
            radius: height / 2
            color: Color.accent
          }
        }
      }

      // Storage: a slim meter and the figures, once the drive reports them.
      ColumnLayout {
        Layout.fillWidth: true
        visible: row.usageLine !== "" && row.transfer === null
        spacing: Style.space(3)
        Rectangle {
          visible: row.fraction >= 0
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(3)
          radius: height / 2
          color: Util.alpha(Color.foreground, 0.12)
          Rectangle {
            width: Math.max(parent.height, parent.width * Math.max(0, row.fraction))
            height: parent.height
            radius: height / 2
            color: row.fraction > 0.9 ? Color.urgent : Color.accent
            Behavior on width { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
          }
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: row.usageLine
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    // Actions
    RowLayout {
      Layout.alignment: Qt.AlignVCenter
      spacing: Style.spacing.md

      Button {
        visible: row.drive.configured && row.drive.mounted
        iconText: ""
        tooltipText: "Open folder  (o)"
        onClicked: row.openRequested()
      }
      Button {
        visible: row.drive.configured
        iconText: ""
        tooltipText: "Settings  (s)"
        onClicked: row.settingsRequested()
      }
      Button {
        visible: row.drive.configured
        iconText: ""
        tooltipText: "Forget this account  (f)"
        enabled: !row.locked
        onClicked: row.forgetRequested()
      }
      Switch {
        visible: row.drive.configured
        Layout.alignment: Qt.AlignVCenter
        checked: !!row.drive.mounted || row.drive.unit === "activating"
        busy: row.working
        enabled: !row.locked
        onToggled: row.toggleRequested()
      }
      Button {
        visible: !row.drive.configured
        text: "Connect"
        iconText: ""
        bordered: true
        enabled: !row.locked
        onClicked: row.connectRequested()
      }
    }
  }
}
