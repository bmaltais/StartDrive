// The view window for bin/dev watch: an ordinary window that shows a live picture of the nested test session.
//
// It is not the session's own window. That one belongs to the nested compositor, which decides what cursor your pointer shows over
// it, and which left your pointer hidden or odd when it was moved or dropped. This is a plain window of its own: your pointer is
// the normal arrow over it, you can drag it, cover it, resize it or send it to the scratchpad, and a click or key does nothing,
// because nothing here listens. The picture is a screenshot of the session taken five times a second by bin/dev.
//
// Environment: DEV_FRAME is the picture's path (a JPEG that is replaced in place); DEV_TITLE names the session in the window's title.
import QtQuick
import Quickshell

ShellRoot {
  FloatingWindow {
    title: (Quickshell.env("DEV_TITLE") || "test session") + " (view only: clicks and keys do nothing here)"
    implicitWidth: 960
    implicitHeight: 600
    color: "#101218"

    // Two pictures, the next one loaded behind the one on show and brought forward only once it is ready: with one image whose
    // source changes, Qt blanks it while the new file loads, which showed as a flicker five times a second.
    Item {
      id: stage
      anchors.fill: parent
      property int n: 0
      property Image front: imgA
      property Image back: imgB
      readonly property string base: "file://" + Quickshell.env("DEV_FRAME") + "?"

      function swapIfReady(image) {
        if (image !== stage.back || image.status !== Image.Ready) return
        var shown = stage.front
        stage.front = stage.back
        stage.back = shown
        stage.front.z = 1
        stage.back.z = 0
      }

      Image {
        id: imgA
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        cache: false
        asynchronous: true
        z: 1
        source: stage.base + "0"
        onStatusChanged: stage.swapIfReady(imgA)
      }
      Image {
        id: imgB
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        cache: false
        asynchronous: true
        z: 0
        onStatusChanged: stage.swapIfReady(imgB)
      }
      Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: if (stage.back.status !== Image.Loading) stage.back.source = stage.base + (++stage.n)
      }
    }
  }
}
