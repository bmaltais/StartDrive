// A scroll bar for a Flickable, drawn like StartBar's settings window: a thin
// track down the right edge and a thumb as long as the visible share, there
// only while the content is taller than the view, so a panel that scrolls is
// seen to. Drag the thumb or click the track; the wheel scrolls the flickable.

import QtQuick
import qs.Commons

Item {
  id: track

  required property Flickable flick
  property color foreground: Color.foreground

  // The room the panel keeps free beside the content, always, so content does
  // not shift sideways when the bar appears.
  readonly property int gutter: Style.spacing.lg
  readonly property real extent: flick.contentHeight - flick.height

  visible: extent > 1
  width: Style.spacing.md

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: Util.alpha(track.foreground, 0.08)
  }

  Rectangle {
    id: thumb
    width: parent.width
    radius: width / 2
    height: Math.min(parent.height, Math.max(Style.space(28), parent.height * track.flick.height / Math.max(1, track.flick.contentHeight)))
    y: track.extent > 0 ? (parent.height - height) * track.flick.contentY / track.extent : 0
    color: Util.alpha(track.foreground, mouse.pressed ? 0.55 : (mouse.containsMouse ? 0.4 : 0.28))
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
      var room = track.height - thumb.height
      if (room <= 0) return
      var top = Math.max(0, Math.min(pointerY - thumb.height / 2, room))
      track.flick.contentY = top / room * track.extent
    }
    onPressed: function (m) { scrollTo(m.y) }
    onPositionChanged: function (m) { if (pressed) scrollTo(m.y) }
  }
}
