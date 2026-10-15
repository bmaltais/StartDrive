// The example plugin: a card in the middle of the screen with a button that counts clicks. `omarchy-shell io.example.hello open`
// shows it and `close` hides it. It is a service, so it has no bar widget; its window is the layer "omarchy-hello".
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
  id: root
  property var shell: null
  property bool shown: false
  property int clicks: 0

  IpcHandler {
    target: "io.example.hello"
    function open(): void { root.shown = true }
    function close(): void { root.shown = false }
    // Where the button is, in pixels of the screen, so a script does not have to find it in a picture.
    function layout(): string { return JSON.stringify({ shown: root.shown, button: card.buttonRect, clicks: root.clicks }) }
  }

  PanelWindow {
    id: window
    visible: root.shown
    color: "transparent"
    WlrLayershell.namespace: "omarchy-hello"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: 360
      height: 200
      radius: 14
      color: "#1e2230"
      border.color: "#3a4160"
      readonly property var buttonRect: {
        var p = button.mapToItem(null, 0, 0)
        return { x: Math.round(p.x + (window.screen.width - window.width) / 2), y: Math.round(p.y + (window.screen.height - window.height) / 2), width: button.width, height: button.height }
      }

      Text {
        anchors { top: parent.top; topMargin: 32; horizontalCenter: parent.horizontalCenter }
        text: root.clicks === 0 ? "Hello" : "Clicked " + root.clicks + (root.clicks === 1 ? " time" : " times")
        color: "#f2f2f2"
        font.pixelSize: 26
        textFormat: Text.PlainText
      }

      Rectangle {
        id: button
        anchors { bottom: parent.bottom; bottomMargin: 32; horizontalCenter: parent.horizontalCenter }
        width: 140
        height: 44
        radius: 8
        color: mouse.containsMouse ? "#5b7cfa" : "#4a68d8"
        Text { anchors.centerIn: parent; text: "Click me"; color: "white"; font.pixelSize: 16; textFormat: Text.PlainText }
        MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.clicks += 1 }
      }
    }

    // Escape closes it, as a person expects of a card.
    Item {
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.shown = false
    }
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
  }
}
