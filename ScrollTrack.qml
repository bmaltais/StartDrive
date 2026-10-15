// A thin scroll bar for a list, drawn like the rest of the Start family: a soft track,
// a rounded thumb that brightens on hover, drag the thumb or click the track.
// It only shows when the list is taller than the window; the wheel scrolls the list itself.
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: bar

  property Flickable target

  readonly property real extent: bar.target ? bar.target.contentHeight - bar.target.height : 0

  visible: bar.extent > 1
  implicitWidth: Style.spacing.md

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: Util.alpha(Color.foreground, 0.08)
  }

  Rectangle {
    id: thumb
    width: parent.width
    radius: width / 2
    height: bar.target ? Math.min(parent.height, Math.max(Style.space(28), parent.height * bar.target.height / bar.target.contentHeight)) : 0
    y: bar.extent > 0 ? (parent.height - height) * bar.target.contentY / bar.extent : 0
    color: Util.alpha(Color.foreground, mouse.pressed ? 0.55 : (mouse.containsMouse ? 0.4 : 0.28))
  }

  MouseArea {
    id: mouse
    // A wider target than the thin bar.
    anchors.fill: parent
    anchors.leftMargin: -Style.spacing.sm
    anchors.rightMargin: -Style.spacing.sm
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    function scrollTo(pointerY) {
      var room = bar.height - thumb.height
      if (room <= 0) return
      var top = Math.max(0, Math.min(pointerY - thumb.height / 2, room))
      bar.target.contentY = top / room * bar.extent
    }
    onPressed: function (m) { mouse.scrollTo(m.y) }
    onPositionChanged: function (m) { if (mouse.pressed) mouse.scrollTo(m.y) }
  }
}
