// One drive: a row with its status and controls, and under it (when expanded)
// the activity, cache and settings of that drive. The panel owns the cursor
// and every decision; this file only paints and reports what was clicked.

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "DriveModel.js" as Model

Column {
  id: card

  required property var drive
  required property var host      // Panel.qml: service, colours, cursor, actions

  readonly property var service: host.service
  readonly property var activity: service.activity[drive.id] || null
  readonly property var usage: service.usage[drive.id] || null
  readonly property bool expanded: host.expandedId === drive.id && drive.configured
  readonly property bool working: service.busyId === drive.id || service.busyId === "*"
  readonly property var status: Model.driveStatus(drive, activity, working)
  readonly property real fraction: Model.usageFraction(usage)
  readonly property string usageLine: drive.mounted ? Model.usageText(usage) : ""
  readonly property int pendingFiles: Model.pending(activity)
  readonly property color fg: host.foreground
  readonly property string fontFamily: host.fontFamily

  spacing: Style.space(4)

  // ---------------------------------------------------------------- the row
  CursorSurface {
    id: head
    width: parent.width
    foreground: card.fg
    hasCursor: card.host.isHot("row", card.drive.id, "")
    current: card.drive.mounted
    onHasCursorChanged: if (hasCursor) card.host.reveal(head)
    implicitHeight: headContent.implicitHeight + Style.spacing.rowPaddingX + Style.spacing.md

    // The row itself: click for its main action. Sits below the controls.
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: card.host.claim("row", card.drive.id, "")
      onClicked: card.host.perform(Model.clickControl(card.drive), card.drive)
    }

    Column {
      id: headContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(6)

      Row {
        width: parent.width
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          text: card.drive.glyph
          color: card.drive.configured ? card.fg : card.host.dim
          font.family: card.fontFamily
          font.pixelSize: Style.font.display
          width: Style.space(28)
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          width: parent.width - Style.space(28) - controls.width - Style.space(20)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)

          Text {
            textFormat: Text.PlainText
            text: card.drive.name
            color: card.fg
            font.family: card.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Row {
            spacing: Style.space(6)
            width: parent.width

            Rectangle {
              id: dot
              visible: card.drive.configured
              width: Style.space(7)
              height: width
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: card.status.kind === "failed" ? card.host.urgent
                : (card.status.kind === "synced" || card.status.kind === "working") ? Color.accent
                : card.host.dim
              SequentialAnimation on opacity {
                running: card.status.kind === "working"
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 500 }
                NumberAnimation { to: 1; duration: 500 }
              }
            }
            Text {
              textFormat: Text.PlainText
              text: card.status.text
              color: card.status.kind === "failed" ? card.host.urgent : card.host.dim
              font.family: card.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width - (dot.visible ? dot.width + parent.spacing : 0)
            }
          }
        }

        Row {
          id: controls
          spacing: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter

          PanelActionButton {
            visible: card.drive.configured && card.drive.mounted
            iconText: "󰉋"
            tooltipText: "Open in file manager  (o)"
            foreground: card.fg
            fontFamily: card.fontFamily
            hasCursor: card.host.isHot("row", card.drive.id, "open")
            onHovered: function (on) { if (on) card.host.claim("row", card.drive.id, "open") }
            onClicked: card.host.perform("open", card.drive)
          }

          PanelActionButton {
            visible: card.drive.configured
            iconText: card.expanded ? "󰅃" : "󰒓"
            tooltipText: card.expanded ? "Hide details  (d)" : "Details and settings  (d)"
            foreground: card.fg
            fontFamily: card.fontFamily
            hasCursor: card.host.isHot("row", card.drive.id, "details")
            onHovered: function (on) { if (on) card.host.claim("row", card.drive.id, "details") }
            onClicked: card.host.perform("details", card.drive)
          }

          PanelActionButton {
            visible: card.drive.configured
            iconText: "󰩹"
            tooltipText: "Forget this account  (f)"
            foreground: card.fg
            hoverColor: card.host.urgent
            fontFamily: card.fontFamily
            enabled: !card.service.busy
            hasCursor: card.host.isHot("row", card.drive.id, "disconnect")
            onHovered: function (on) { if (on) card.host.claim("row", card.drive.id, "disconnect") }
            onClicked: card.host.perform("disconnect", card.drive)
          }

          ToggleSwitch {
            id: mountSwitch
            visible: card.drive.configured
            anchors.verticalCenter: parent.verticalCenter
            cursorPad: Style.space(3)
            checked: card.drive.mounted || card.drive.unit === "activating"
            busy: card.working
            foreground: card.fg
            hasCursor: card.host.isHot("row", card.drive.id, "toggle")
            onHovered: function (on) { if (on) card.host.claim("row", card.drive.id, "toggle") }
            onToggled: card.host.perform("toggle", card.drive)

            PanelToolTip {
              visible: mountSwitch.containsMouse
              text: (mountSwitch.checked ? "Unmount" : "Mount") + "  (m)"
              fontFamily: card.fontFamily
            }
          }

          Button {
            visible: !card.drive.configured
            text: "Connect"
            iconText: "󰌘"
            fontSize: Style.font.caption
            foreground: card.fg
            fontFamily: card.fontFamily
            horizontalPadding: Style.spacing.md
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            enabled: !card.service.busy
            hasCursor: card.host.isHot("row", card.drive.id, "connect")
            onHovered: function (isHovered) { if (isHovered) card.host.claim("row", card.drive.id, "connect") }
            onClicked: card.host.perform("connect", card.drive)
          }
        }
      }

      // Storage: a slim meter and the figures, once the drive reports them.
      Column {
        visible: card.usageLine !== ""
        width: parent.width - Style.space(38)
        x: Style.space(38)
        spacing: Style.space(4)

        Rectangle {
          visible: card.fraction >= 0
          width: parent.width
          height: Style.space(3)
          radius: height / 2
          color: Util.alpha(card.fg, 0.12)

          Rectangle {
            width: Math.max(parent.height, parent.width * Math.max(0, card.fraction))
            height: parent.height
            radius: height / 2
            color: card.fraction > 0.9 ? card.host.urgent : Color.accent
            Behavior on width { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
          }
        }

        Text {
          textFormat: Text.PlainText
          text: card.usageLine
          color: card.host.dim
          font.family: card.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // ---------------------------------------------------------------- details
  Column {
    id: details
    visible: card.expanded
    width: parent.width - Style.space(16)
    x: Style.space(16)
    spacing: Style.space(4)

    // What is moving now: transfers from the mount's remote-control API.
    Column {
      width: parent.width
      spacing: Style.space(6)
      topPadding: Style.space(4)

      PanelSectionHeader {
        text: "ACTIVITY"
        foreground: card.fg
        fontFamily: card.fontFamily
      }

      Text {
        textFormat: Text.PlainText
        visible: !card.drive.mounted
        text: "Mount the drive to see its activity."
        color: card.host.dim
        font.family: card.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        textFormat: Text.PlainText
        visible: card.drive.mounted && (!card.activity || card.activity.transfers.length === 0)
        text: card.pendingFiles > 0 ? Model.plural(card.pendingFiles, "file", "files") + " waiting to upload" : "Nothing is uploading."
        color: card.host.dim
        font.family: card.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: card.activity ? card.activity.transfers.slice(0, 3) : []

        Column {
          id: transfer
          required property var modelData
          width: details.width
          spacing: Style.space(3)

          RowLayout {
            width: parent.width
            spacing: Style.space(8)
            Text {
              textFormat: Text.PlainText   // file names come from the cloud
              Layout.fillWidth: true
              text: transfer.modelData.name
              color: card.fg
              font.family: card.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }
            Text {
              textFormat: Text.PlainText
              text: Math.round(transfer.modelData.percentage) + "%" + (transfer.modelData.speed > 0 ? " · " + Model.formatSpeed(transfer.modelData.speed) : "")
              color: card.host.dim
              font.family: card.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(3)
            radius: height / 2
            color: Util.alpha(card.fg, 0.12)
            Rectangle {
              width: parent.width * Math.max(0, Math.min(1, transfer.modelData.percentage / 100))
              height: parent.height
              radius: height / 2
              color: Color.accent
            }
          }
        }
      }
    }

    PanelSeparator { foreground: card.fg }

    // The tabs and the body they open into, with no gap between.
    Column {
      width: parent.width
      spacing: 0

    Tabs {
      id: tabs
      width: parent.width
      options: Model.DETAIL_TABS
      value: card.host.detailTab
      foreground: card.fg
      fontFamily: card.fontFamily
      hasCursor: card.host.isHot("detail", card.drive.id, "tabs")
      onHasCursorChanged: if (hasCursor) card.host.reveal(tabs)
      onHovered: card.host.claim("detail", card.drive.id, "tabs")
      onPicked: function (v) { card.host.detailTab = v }
    }

    // The body the tabs open into: sides and bottom only, the top is the baseline.
    Item {
      id: tabBody
      width: parent.width
      implicitHeight: groups.implicitHeight + Style.space(8)
      height: implicitHeight

      Rectangle { anchors.fill: parent; color: tabs.fill; bottomLeftRadius: Style.space(7); bottomRightRadius: Style.space(7) }
      Rectangle { x: 0; width: 1; height: parent.height; color: tabs.line }
      Rectangle { x: parent.width - 1; width: 1; height: parent.height; color: tabs.line }
      Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: tabs.line }

      Column {
        id: groups
        x: Style.space(2)
        y: Style.space(4)
        width: parent.width - Style.space(4)
        spacing: 0
    Column {
      width: parent.width
      spacing: Style.space(4)
      visible: card.host.detailTab === "cache"

    DetailLine {
      itemKey: "cacheSize"
      stacked: true
      label: "Cache limit"
      hint: "The most local disk the cache may use"
      Segmented {
        options: Model.CACHE_SIZES
        value: card.drive.settings.cacheSize
        foreground: card.fg
        fontFamily: card.fontFamily
        enabled: !card.service.busy
        hasCursor: card.host.isHot("detail", card.drive.id, "cacheSize")
        onHovered: card.host.claim("detail", card.drive.id, "cacheSize")
        onPicked: function (v) { card.service.set(card.drive.id, "cache-size", v) }
      }
    }

    DetailLine {
      itemKey: "cacheAge"
      stacked: true
      label: "Keep files"
      hint: "How long unused files stay cached"
      Segmented {
        options: Model.CACHE_AGES
        value: card.drive.settings.cacheAge
        foreground: card.fg
        fontFamily: card.fontFamily
        enabled: !card.service.busy
        hasCursor: card.host.isHot("detail", card.drive.id, "cacheAge")
        onHovered: card.host.claim("detail", card.drive.id, "cacheAge")
        onPicked: function (v) { card.service.set(card.drive.id, "cache-age", v) }
      }
    }

    }

    Column {
      width: parent.width
      spacing: Style.space(4)
      visible: card.host.detailTab === "behaviour"

    Toggle {
      id: autoToggle
      width: parent.width
      label: "Mount at login"
      description: "Mount this drive when your session starts"
      checked: card.drive.settings.autostart
      foreground: card.fg
      fontFamily: card.fontFamily
      enabled: !card.service.busy
      hasCursor: card.host.isHot("detail", card.drive.id, "autostart")
      onHasCursorChanged: if (hasCursor) card.host.reveal(autoToggle)
      onHovered: function (on) { if (on) card.host.claim("detail", card.drive.id, "autostart") }
      onClicked: card.service.set(card.drive.id, "autostart", Model.flipped(card.drive, "autostart"))
    }

    Toggle {
      id: readOnlyToggle
      width: parent.width
      label: "Read-only"
      description: "Block writes and deletes through this folder"
      checked: card.drive.settings.readOnly
      foreground: card.fg
      fontFamily: card.fontFamily
      enabled: !card.service.busy
      hasCursor: card.host.isHot("detail", card.drive.id, "readOnly")
      onHasCursorChanged: if (hasCursor) card.host.reveal(readOnlyToggle)
      onHovered: function (on) { if (on) card.host.claim("detail", card.drive.id, "readOnly") }
      onClicked: card.service.set(card.drive.id, "read-only", Model.flipped(card.drive, "read-only"))
    }

    }

    Column {
      width: parent.width
      spacing: Style.space(4)
      visible: card.host.detailTab === "maintenance"

    DetailLine {
      visible: card.drive.mounted
      itemKey: "refresh"
      label: "Refresh listing"
      hint: "Look for changes made elsewhere"
      Button {
        text: "Refresh"
        iconText: "󰑐"
        fontSize: Style.font.caption
        foreground: card.fg
        fontFamily: card.fontFamily
        horizontalPadding: Style.spacing.md
        verticalPadding: Style.spacing.controlPaddingY
        bordered: true
        enabled: !card.service.busy
        hasCursor: card.host.isHot("detail", card.drive.id, "refresh")
        onHovered: function (on) { if (on) card.host.claim("detail", card.drive.id, "refresh") }
        onClicked: card.service.refreshListing(card.drive.id)
      }
    }

    DetailLine {
      itemKey: "clearCache"
      label: "Clear cache"
      hint: card.pendingFiles > 0 ? "Wait for uploads to finish" : (Model.formatBytes(card.drive.cacheBytes) || "0 B") + " on disk"
      Button {
        text: "Clear"
        iconText: "󰩹"
        fontSize: Style.font.caption
        foreground: card.fg
        fontFamily: card.fontFamily
        horizontalPadding: Style.spacing.md
        verticalPadding: Style.spacing.controlPaddingY
        bordered: true
        enabled: !card.service.busy && card.pendingFiles === 0
        hasCursor: card.host.isHot("detail", card.drive.id, "clearCache")
        onHovered: function (on) { if (on) card.host.claim("detail", card.drive.id, "clearCache") }
        onClicked: card.service.clearCache(card.drive.id)
      }
    }
    }
      }
    }
    }
  }

  // A labelled line with its control on the right, a cursor stop.
  component DetailLine: CursorSurface {
    id: line
    property string itemKey: ""
    property string label: ""
    property string hint: ""
    // Wide controls sit under their label instead of beside it.
    property bool stacked: false
    default property alias control: slot.data

    width: parent.width
    foreground: card.fg
    hasCursor: card.host.isHot("detail", card.drive.id, itemKey)
    onHasCursorChanged: if (hasCursor) card.host.reveal(line)
    implicitHeight: grid.implicitHeight + Style.spacing.xl

    GridLayout {
      id: grid
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      columns: line.stacked ? 1 : 2
      columnSpacing: Style.space(8)
      rowSpacing: Style.space(6)

      ColumnLayout {
        id: texts
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          textFormat: Text.PlainText
          text: line.label
          color: card.fg
          font.family: card.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          textFormat: Text.PlainText
          text: line.hint
          color: card.host.dim
          font.family: card.fontFamily
          font.pixelSize: Style.font.caption
          Layout.fillWidth: true
          elide: Text.ElideRight
        }
      }

      Item {
        id: slot
        Layout.alignment: line.stacked ? Qt.AlignLeft : Qt.AlignVCenter | Qt.AlignRight
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
      }
    }
  }
}
