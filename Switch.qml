// The Start family's on/off switch: a 42 x 24 pill, accent when on, with a round knob that slides 100 ms
// (but not while the page is first shown). `busy` pulses it while the change it asked for is made.
import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: sw

  property bool checked: false
  property bool busy: false
  signal toggled()

  implicitWidth: Style.space(42)
  implicitHeight: Style.space(24)
  width: implicitWidth
  height: implicitHeight
  radius: height / 2
  color: sw.checked ? Color.accent : Util.alpha(Color.foreground, 0.25)
  property real pulse: 1
  opacity: sw.busy ? sw.pulse : (sw.enabled ? 1 : 0.5)

  // The Loader hands over the real value just after this is created; animating only
  // once that has settled keeps the knob from sliding into place when the page opens.
  property bool settled: false
  Component.onCompleted: Qt.callLater(function () { sw.settled = true })

  SequentialAnimation on pulse {
    running: sw.busy
    loops: Animation.Infinite
    NumberAnimation { to: 0.45; duration: 500 }
    NumberAnimation { to: 1; duration: 500 }
  }

  Rectangle {
    width: parent.height - 6
    height: width
    radius: width / 2
    y: 3
    x: sw.checked ? parent.width - width - 3 : 3
    color: Color.menu.background
    Behavior on x { enabled: sw.settled; NumberAnimation { duration: 100 } }
  }
  MouseArea {
    anchors.fill: parent
    enabled: sw.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: sw.toggled()
  }
}
