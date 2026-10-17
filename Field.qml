// A single-line text field in the Start family's look.
import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: field

  property alias text: input.text
  property string placeholder: ""
  readonly property bool focused: input.focused
  signal accepted()
  signal escaped()      // Escape was pressed in the box; the key still goes on to the window

  function focusInput() { input.focusInput() }

  implicitHeight: Style.space(34)
  radius: Math.max(Style.cornerRadius, Style.space(5))
  color: Util.alpha(Color.foreground, 0.06)
  border.width: Style.normalBorderWidth
  border.color: Util.alpha(Color.foreground, input.focused ? 0.30 : 0.12)

  EntryText {
    id: input
    anchors.fill: parent
    anchors.leftMargin: Style.spacing.xxl
    anchors.rightMargin: Style.spacing.xxl
    color: Color.foreground
    selectionColor: Util.alpha(Color.accent, 0.4)
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    placeholder: field.placeholder
    onAccepted: field.accepted()
    onEscapePressed: function (event) { field.escaped(); event.accepted = false }
  }
}
