// A row of tabs drawn the way a browser draws them: the chosen tab is raised,
// joined to the content below it with no line between, and the others sit
// flat on a baseline. `options` is [{ value, label }]; the content under the
// tabs draws its own body, whose side and bottom lines continue the baseline.

import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: tabs

  property var options: []
  property string value: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool hasCursor: false
  readonly property color line: Util.alpha(foreground, 0.22)
  readonly property color fill: Util.alpha(foreground, 0.07)

  signal picked(string value)
  signal hovered()

  implicitHeight: row.implicitHeight

  Row {
    id: row
    spacing: 0

    Repeater {
      model: tabs.options

      Item {
        id: tab
        required property var modelData
        readonly property bool selected: modelData.value === tabs.value
        readonly property bool hot: mouse.containsMouse

        implicitWidth: label.implicitWidth + Style.space(22)
        implicitHeight: label.implicitHeight + Style.space(12)
        width: implicitWidth
        height: implicitHeight
        clip: true   // hides the rounded bottom of the shape below

        Rectangle {
          width: parent.width
          height: parent.height + Style.space(8)
          radius: Style.space(7)
          color: tab.selected ? tabs.fill : (tab.hot ? Util.alpha(tabs.foreground, 0.04) : "transparent")
          border.width: 1
          border.color: tab.selected ? tabs.line : (tab.hot ? Util.alpha(tabs.foreground, 0.12) : "transparent")
        }

        // The baseline, broken under the chosen tab so it opens into the body.
        Rectangle {
          visible: !tab.selected
          anchors.bottom: parent.bottom
          width: parent.width
          height: 1
          color: tabs.line
        }

        Text {
          id: label
          textFormat: Text.PlainText
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -Style.space(1)
          text: tab.modelData.label
          color: tabs.hasCursor && tab.selected ? Color.accent
            : tab.selected ? tabs.foreground : Util.alpha(tabs.foreground, 0.65)
          font.family: tabs.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: tab.selected
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: tabs.hovered()
          onClicked: tabs.picked(tab.modelData.value)
        }
      }
    }
  }

  // The baseline carries on to the right edge.
  Rectangle {
    anchors.left: row.right
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1
    color: tabs.line
  }
}
