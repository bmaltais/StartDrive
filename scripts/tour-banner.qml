// The status strip the tour recorder (scripts/tour.sh) puts along the top of your screen, red with white text: which step the
// recording is on, a Cancel recording button, and at the end green ("saved") or grey ("cancelled"). The recording itself is
// shown in a view-only window below it. It redraws in place, so it does not flicker.
//
// Run by the recorder with `quickshell -n -p scripts/tour-banner.qml`, configured by environment:
//   TOUR_TITLE    the app's name
//   TOUR_SCREEN   the name of the monitor to appear on (the real one)
//   TOUR_ANSWER   a file that gets "cancel" written to it when the Cancel button is pressed
//   TOUR_STATUS   a file whose first line is "starting", "recording", "encoding", "done" or "cancelled" and the rest is the text to show
//   TOUR_STRIP_GAP, TOUR_STRIP_H   the strip's distance from the top and its height
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: root

  readonly property string appTitle: Quickshell.env("TOUR_TITLE") || "the app"
  property string statusText: ""
  // The first line of the status file says which state we are in: starting, recording, encoding, done or cancelled.
  readonly property string state: root.statusText.split("\n")[0]
  readonly property bool done: root.state === "done"
  readonly property bool encoding: root.state === "encoding"
  readonly property bool cancelled: root.state === "cancelled"
  readonly property bool over: root.done || root.encoding || root.cancelled
  property bool cancelling: false
  readonly property string statusBody: {
    var i = root.statusText.indexOf("\n")
    return i < 0 ? "" : root.statusText.substring(i + 1).replace(/\n+$/, "")
  }

  // The strip's place and height come from the recorder (scripts/nested/session.sh).
  readonly property int stripGap: Number(Quickshell.env("TOUR_STRIP_GAP")) || 24
  readonly property int stripHeight: Number(Quickshell.env("TOUR_STRIP_H")) || 170
  readonly property color red: "#c62828"
  readonly property color green: "#2e7d32"

  function cancel() {
    Quickshell.execDetached(["sh", "-c", "printf %s cancel > \"$1\"", "sh", Quickshell.env("TOUR_ANSWER")])
    root.cancelling = true
  }

  FileView {
    path: Quickshell.env("TOUR_STATUS")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.statusText = text()
  }

  PanelWindow {
    screen: {
      var name = Quickshell.env("TOUR_SCREEN")
      for (var i = 0; i < Quickshell.screens.length; i++) if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
      return Quickshell.screens[0]
    }
    anchors.top: true
    margins.top: root.stripGap
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "start-tour-banner"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    implicitWidth: 1280
    implicitHeight: root.over ? Math.min(124, root.stripHeight) : root.stripHeight
    color: "transparent"

    Rectangle {
      anchors.fill: parent
      radius: 14
      color: root.over ? (root.cancelled ? "#555555" : root.green) : root.red
      border.width: 3
      border.color: "white"

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18
        spacing: 8

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          color: "white"
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 20
          font.bold: true
          text: root.done ? "The tour is done"
            : root.cancelled ? "Recording cancelled"
            : root.encoding ? "Recording finished"
            : root.state === "starting" ? "Getting ready to record the " + root.appTitle + " tour. Not recording yet."
            : "Recording the " + root.appTitle + " tour in a test session. Watch it below."
        }

        Text {
          visible: root.over
          width: parent.width
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          color: "white"
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 19
          text: root.done ? "The recording is saved."
            : root.cancelled ? "Nothing was kept."
            : "Building the animation now."
        }

        Text {
          visible: !root.over && root.statusBody !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          color: "white"
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 18
          font.bold: true
          text: root.statusBody
        }

        // Stops the recording and throws the session away.
        Rectangle {
          visible: !root.over
          anchors.horizontalCenter: parent.horizontalCenter
          width: 190
          height: 40
          radius: 10
          color: cancelHover.hovered ? "#d84343" : "transparent"
          border.width: 3
          border.color: "white"
          Text {
            anchors.centerIn: parent
            text: root.cancelling ? "Cancelling..." : "Cancel recording"
            color: "white"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 17
            font.bold: true
          }
          HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { enabled: !root.cancelling; onTapped: root.cancel() }
        }
      }
    }
  }
}
