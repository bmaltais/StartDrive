// The text of a single-line box that never reads the clipboard. Qt's TextInput re-reads the clipboard on every change
// unless it is read-only, so this one is always read-only and the keys it takes are handled here: type, Backspace,
// Delete, the cursor keys (the TextInput's own), selecting and copying. No paste and no input methods.
import QtQuick
import qs.Commons

Item {
  id: entry

  property string text: ""
  property string placeholder: ""
  property int maximumLength: 256
  property alias color: input.color
  property alias selectionColor: input.selectionColor
  property alias font: input.font
  readonly property bool focused: input.activeFocus
  signal accepted()
  signal escapePressed(var event)   // set event.accepted to say whether the key stops here

  function focusInput() { input.forceActiveFocus() }

  // Replace the selection (or nothing, at the cursor) with s, and put the cursor after it.
  function put(s) {
    var a = Math.min(input.selectionStart, input.selectionEnd)
    var b = Math.max(input.selectionStart, input.selectionEnd)
    var room = entry.maximumLength - (entry.text.length - (b - a))
    if (room <= 0 && s !== "") return
    s = s.slice(0, Math.max(room, 0))
    entry.text = entry.text.slice(0, a) + s + entry.text.slice(b)
    input.cursorPosition = a + s.length
  }
  function erase(back) {
    if (input.selectionStart !== input.selectionEnd) { entry.put(""); return }
    var p = input.cursorPosition
    if (back ? p === 0 : p >= entry.text.length) return
    var a = back ? p - 1 : p
    entry.text = entry.text.slice(0, a) + entry.text.slice(a + 1)
    input.cursorPosition = a
  }

  TextInput {
    id: input
    anchors.fill: parent
    verticalAlignment: TextInput.AlignVCenter
    clip: true
    readOnly: true
    text: entry.text
    Keys.onPressed: function (event) {
      var mod = event.modifiers & (Qt.ControlModifier | Qt.MetaModifier)
      if (event.key === Qt.Key_Backspace) { entry.erase(true); event.accepted = true }
      else if (event.key === Qt.Key_Delete) { entry.erase(false); event.accepted = true }
      else if (mod !== 0) { event.accepted = event.matches(StandardKey.Paste) || event.matches(StandardKey.Cut) }
      else if (event.text.length > 0 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
        entry.put(event.text); event.accepted = true
      }
    }
    Keys.onReturnPressed: entry.accepted()
    Keys.onEnterPressed: entry.accepted()
    Keys.onEscapePressed: function (event) { entry.escapePressed(event) }

    Text {
      visible: entry.text === ""
      anchors.verticalCenter: parent.verticalCenter
      text: entry.placeholder
      color: Color.muted
      font: input.font
    }
  }
}
