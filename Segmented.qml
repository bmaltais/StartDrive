// A row of mutually exclusive choices, shown as small pills. Used for the
// cache settings, where the choices are few and a popup would be heavier than
// the control. `options` is [{ value, label }].

import QtQuick
import qs.Commons
import qs.Ui

Row {
  id: segmented

  property var options: []
  property string value: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool hasCursor: false
  property bool enabled: true

  signal picked(string value)
  signal hovered()

  spacing: Style.space(3)

  Repeater {
    model: segmented.options

    BorderSurface {
      id: pill
      required property var modelData
      readonly property bool selected: modelData.value === segmented.value
      readonly property bool hot: segmented.hasCursor || mouse.containsMouse

      implicitWidth: label.implicitWidth + Style.space(14)
      implicitHeight: label.implicitHeight + Style.space(8)
      radius: Style.cornerRadius
      opacity: segmented.enabled ? 1 : 0.5
      color: selected ? Style.selectedFillFor(segmented.foreground, Color.accent)
        : (hot ? Style.hoverFillFor(segmented.foreground, Color.accent) : "transparent")
      borderSpec: Border.controlSpec(selected ? "selected" : (hot ? "hover-cursor" : "normal"), segmented.foreground, Color.accent)

      Text {
        id: label
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: pill.modelData.label
        color: segmented.foreground
        font.family: segmented.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: pill.selected
      }

      MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: segmented.enabled
        cursorShape: Qt.PointingHandCursor
        onEntered: segmented.hovered()
        onClicked: segmented.picked(pill.modelData.value)
      }
    }
  }
}
