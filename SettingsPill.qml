// A footer button of the settings windows: a soft pill; accent-filled for the one action to take,
// red while a destructive one waits for its second click.
import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: pill

  property string text: ""
  property bool primary: false
  property bool danger: false
  signal clicked()

  width: label.implicitWidth + Style.spacing.lg * 2
  height: Style.space(32)
  radius: Math.max(Style.cornerRadius, Style.space(5))
  color: pill.danger ? Util.alpha(Color.urgent, 0.5)
    : pill.primary ? Color.accent
    : (hover.hovered ? Style.hoverFillFor(Color.foreground, Color.accent) : Util.alpha(Color.foreground, 0.08))

  Text {
    id: label
    anchors.centerIn: parent
    text: pill.text
    color: pill.primary ? Color.menu.background : Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: pill.primary
  }
  HoverHandler { id: hover }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: pill.clicked()
  }
}
