// A settings window in the Start family's look, modelled on StartBar's: a header with a search
// box, the pages down the left, the settings of the chosen page on the right, and a footer.
// It only draws; whoever uses it says what the pages are, what the values are, and what to do
// when one changes.
//
//   pages   [{ title, fields: [field] }]
//   field   { key, type: "bool" | "choice" | "text" | "action", label, hint,
//             options: [{ value, label }]   (choice)
//             stacked: true                 (choice or text: the control goes under the label, full width)
//             placeholder                   (text)
//             buttonText, danger            (action: a button on the right; it emits changed(key, true) when clicked)
//             disabled: true                (dimmed, not clickable)
//             note: { kind: "ok"|"bad"|"muted", text }   (a line of feedback under the control) }
//   values  { key: value }
//
// Signals: changed(key, value) when a switch or choice is clicked, an action button is pressed, or a text is
// committed (Enter, or the box losing focus with a new text); edited(key, text) on every keystroke in a text box.
// Anything placed inside the window goes in the footer, on the right.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: win

  property string title: ""
  // A small-caps line under the title that says what the window is for ("SETTINGS", maybe more).
  property string subtitle: ""
  property string titleIcon: ""                  // a file path, or empty
  property string titleGlyph: ""                 // an icon-font glyph, when there is no file (a drive's cloud)
  property int initialPage: 0                    // the page reset() goes back to
  // The title block and the page heading beside it share one height.
  readonly property real headHeight: win.subtitle !== "" ? Style.space(48) : Style.space(40)
  property var pages: []
  property var values: ({})
  property string footerText: ""
  property string searchPlaceholder: "Find a setting"
  default property alias footerActions: footerRow.data

  // The page shown (an index into pages) and what is typed in the search box.
  property int page: 0
  property string query: ""
  readonly property bool searching: win.query.trim() !== ""

  signal changed(string key, var value)
  signal edited(string key, string text)

  readonly property color hairline: Util.alpha(Color.foreground, 0.14)
  readonly property real rowRadius: Math.max(Style.cornerRadius, Style.space(5))

  implicitHeight: Style.space(520)

  function reset() { win.page = Math.max(0, Math.min(win.initialPage, win.pages.length - 1)); win.query = ""; search.text = "" }

  function matches(field) {
    var q = win.query.trim().toLowerCase()
    return (field.label + " " + (field.hint || "")).toLowerCase().indexOf(q) !== -1
  }
  readonly property var shownGroups: {
    if (win.pages.length === 0) return []
    if (!win.searching) return [win.pages[Math.min(win.page, win.pages.length - 1)]]
    var out = []
    for (var i = 0; i < win.pages.length; i++) {
      var fields = win.pages[i].fields.filter(win.matches)
      if (fields.length) out.push({ title: win.pages[i].title, fields: fields })
    }
    return out
  }
  onPageChanged: body.contentY = 0
  onQueryChanged: body.contentY = 0

  // ---- header: the search box, centred, with room for the close button ---------------
  Item {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(60)

    Rectangle {
      anchors.centerIn: parent
      width: Math.min(Style.space(380), parent.width - Style.space(120))
      height: Style.space(34)
      radius: height / 2
      color: Util.alpha(Color.foreground, 0.06)
      border.width: Style.normalBorderWidth
      border.color: Util.alpha(Color.foreground, search.focused ? 0.30 : 0.12)

      Text {
        id: glass
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.xxxl
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      EntryText {
        id: search
        anchors.fill: parent
        anchors.leftMargin: Style.spacing.xxxl + glass.width + Style.spacing.md
        anchors.rightMargin: Style.spacing.xxxl
        color: Color.foreground
        selectionColor: Util.alpha(Color.accent, 0.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        maximumLength: 64
        placeholder: win.searchPlaceholder
        onTextChanged: if (win.query !== search.text) win.query = search.text
        // Escape clears a search first, then closes the window.
        onEscapePressed: function (event) {
          if (search.text !== "") { search.text = ""; event.accepted = true } else event.accepted = false
        }
      }
    }
  }

  // ---- left: the window's name and one item per page ---------------------------------
  Item {
    id: side
    anchors.top: header.bottom
    anchors.bottom: footer.top
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.lg
    width: Style.space(190)

    Item {
      id: titleRow
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: win.headHeight

      Image {
        id: titleImage
        visible: win.titleIcon !== "" && status === Image.Ready
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(24)
        height: Style.space(24)
        source: win.titleIcon !== "" ? "file://" + win.titleIcon : ""
        sourceSize.width: Style.space(48)
        sourceSize.height: Style.space(48)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
      }
      Text {
        id: titleGlyphText
        visible: !titleImage.visible && win.titleGlyph !== ""
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(24)
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: win.titleGlyph
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.display
      }
      Column {
        readonly property bool lead: titleImage.visible || titleGlyphText.visible
        anchors.left: titleImage.visible ? titleImage.right : titleGlyphText.visible ? titleGlyphText.right : parent.left
        anchors.leftMargin: lead ? Style.spacing.md : 0
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: win.title
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body + 3
          font.bold: true
        }
        Text {
          visible: win.subtitle !== ""
          width: parent.width
          elide: Text.ElideRight
          text: win.subtitle
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }
      }
    }

    Column {
      anchors.top: titleRow.bottom
      anchors.topMargin: Style.spacing.sm
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(2)

      // The models are counts, not the arrays: when what a page says changes (a note, a hint),
      // the rows stay where they are, so a text box being typed into is not rebuilt.
      Repeater {
        model: win.pages.length

        delegate: Rectangle {
          id: nav
          required property int index
          readonly property var pageData: win.pages[nav.index] || ({ title: "" })
          readonly property bool current: !win.searching && win.page === nav.index
          width: parent.width
          height: Style.space(38)
          radius: win.rowRadius
          color: nav.current ? Util.alpha(Color.accent, 0.22)
            : (navHover.hovered ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent")

          // The mark beside the current page.
          Rectangle {
            visible: nav.current
            anchors.left: parent.left
            anchors.leftMargin: Style.space(3)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(3)
            height: Style.space(16)
            radius: width / 2
            color: Color.accent
          }
          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            text: nav.pageData.title
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: nav.current
          }
          HoverHandler { id: navHover }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { search.text = ""; win.query = ""; win.page = nav.index }
          }
        }
      }
    }
  }

  // ---- right: the page heading and its settings --------------------------------------
  Text {
    id: heading
    anchors.top: header.bottom
    anchors.left: side.right
    anchors.leftMargin: Style.spacing.lg * 2
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.lg
    height: win.headHeight
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
    text: win.searching ? "Search results" : (win.pages.length ? win.pages[Math.min(win.page, win.pages.length - 1)].title : "")
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body + 8
    font.bold: true
  }

  Flickable {
    id: body
    anchors.top: heading.bottom
    anchors.bottom: footer.top
    anchors.left: side.right
    anchors.right: parent.right
    anchors.leftMargin: Style.spacing.lg * 2
    // Room for the scroll bar's gutter, always: sizing the body by whether it scrolls
    // would change its width, and with it its height.
    anchors.rightMargin: Style.spacing.lg + Style.spacing.lg + Style.spacing.xs
    contentHeight: rows.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: rows
      width: body.width

      Text {
        visible: win.searching && win.shownGroups.length === 0
        width: rows.width
        wrapMode: Text.WordWrap
        topPadding: Style.spacing.md
        text: "No setting matches “" + win.query.trim() + "”."
        color: Util.alpha(Color.foreground, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Repeater {
        model: win.shownGroups.length

        delegate: Column {
          id: group
          required property int index
          readonly property var groupData: win.shownGroups[group.index] || ({ title: "", fields: [] })
          width: rows.width

          // Search results come from several pages: say which.
          Text {
            visible: win.searching
            topPadding: Style.spacing.md
            bottomPadding: Style.spacing.xs
            text: group.groupData.title
            color: Util.alpha(Color.foreground, 0.7)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Repeater {
            model: group.groupData.fields.length

            delegate: Item {
              id: row
              required property int index
              readonly property var field: group.groupData.fields[row.index] || ({ key: "", type: "bool", label: "" })
              readonly property var value: win.values[row.field.key]
              readonly property bool live: !row.field.disabled
              readonly property bool stacked: row.field.type === "text" || row.field.stacked === true
              readonly property real noteHeight: note.visible ? note.implicitHeight + Style.spacing.xs : 0

              width: group.width
              opacity: row.live ? 1 : 0.4
              height: (row.stacked
                ? labels.implicitHeight + Style.spacing.sm + editor.height
                : Math.max(labels.implicitHeight, editor.height)) + row.noteHeight + Style.spacing.md * 2

              Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Util.alpha(win.hairline, 0.5)
              }

              Column {
                id: labels
                anchors.top: parent.top
                anchors.topMargin: Style.spacing.md
                anchors.left: parent.left
                width: row.stacked ? parent.width : parent.width - editor.width - Style.spacing.xxl
                Text {
                  width: parent.width
                  elide: Text.ElideRight
                  text: row.field.label
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                Text {
                  visible: !!row.field.hint
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: row.field.hint || ""
                  color: Util.alpha(Color.foreground, 0.55)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              Loader {
                id: editor
                enabled: row.live
                // Stacked: under the label, full width. Otherwise on the right of the row.
                anchors.top: row.stacked ? labels.bottom : undefined
                anchors.topMargin: Style.spacing.sm
                anchors.left: row.stacked ? parent.left : undefined
                anchors.right: parent.right
                anchors.verticalCenter: row.stacked ? undefined : parent.verticalCenter
                anchors.verticalCenterOffset: row.stacked ? 0 : -row.noteHeight / 2
                sourceComponent: row.field.type === "bool" ? switchEditor
                  : row.field.type === "action" ? actionEditor
                  : row.field.type === "text" ? textEditor
                  : row.stacked ? flowEditor : choiceEditor
                onLoaded: {
                  item.field = Qt.binding(function () { return row.field })
                  item.value = Qt.binding(function () { return row.value })
                }
                Connections {
                  target: editor.item
                  ignoreUnknownSignals: true
                  function onCommit(next) { win.changed(row.field.key, next) }
                  function onTyped(text) { win.edited(row.field.key, text) }
                }
              }

              Text {
                id: note
                visible: !!(row.field.note && row.field.note.text)
                anchors.top: row.stacked ? editor.bottom : labels.bottom
                anchors.topMargin: Style.spacing.xs
                anchors.left: parent.left
                width: row.stacked ? parent.width : labels.width
                wrapMode: Text.WordWrap
                text: row.field.note ? row.field.note.text : ""
                color: !row.field.note ? Color.muted
                  : row.field.note.kind === "bad" ? Color.urgent
                  : row.field.note.kind === "ok" ? Color.accent : Util.alpha(Color.foreground, 0.55)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      Item { width: 1; height: Style.spacing.md }
    }
  }

  ScrollTrack {
    target: body
    anchors.top: body.top
    anchors.bottom: body.bottom
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.lg
    width: Style.spacing.md
  }

  // ---- footer: what to know on the left, the actions on the right ---------------------------
  Item {
    id: footer
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(52)

    // Sets the footer apart from the settings above it.
    Rectangle {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.spacing.lg
      anchors.rightMargin: Style.spacing.lg
      height: 1
      color: Util.alpha(win.hairline, 0.5)
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.lg
      anchors.right: footerRow.left
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      text: win.footerText + (win.footerText !== "" ? "   ·   " : "") + "Esc to close"
      color: Util.alpha(Color.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Row {
      id: footerRow
      anchors.right: parent.right
      // Leaves room for the resize grip in the corner.
      anchors.rightMargin: Style.space(30)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.md
    }
  }

  // ---- editors: each is given `field` and `value` and emits commit(next) ----------------
  Component {
    id: switchEditor
    Switch {
      id: sw
      property var field: null
      property var value: false
      signal commit(var next)
      checked: !!sw.value
      onToggled: sw.commit(!sw.value)
    }
  }

  // A button on the right of the setting, for something to do rather than something to set.
  Component {
    id: actionEditor
    SettingsPill {
      id: act
      property var field: null
      property var value: null
      signal commit(var next)
      text: act.field && act.field.buttonText ? act.field.buttonText : ""
      danger: !!(act.field && act.field.danger)
      onClicked: act.commit(true)
    }
  }

  // The choices as segments in a row, on the right of the setting.
  Component {
    id: choiceEditor
    Row {
      id: choices
      property var field: null
      property var value: null
      signal commit(var next)
      spacing: 2

      Repeater {
        model: choices.field ? choices.field.options : []
        delegate: Segment {
          selected: choices.value === modelData.value
          text: modelData.label
          onClicked: choices.commit(modelData.value)
        }
      }
    }
  }

  // The same choices wrapping across the full width, under the label: for many or long options.
  Component {
    id: flowEditor
    Flow {
      id: flow
      property var field: null
      property var value: null
      signal commit(var next)
      width: parent ? parent.width : 0
      spacing: Style.spacing.md

      Repeater {
        model: flow.field ? flow.field.options : []
        delegate: Segment {
          selected: flow.value === modelData.value
          text: modelData.label
          onClicked: flow.commit(modelData.value)
        }
      }
    }
  }

  // A text box under the label: commits on Enter or when it loses focus with a new text.
  Component {
    id: textEditor
    Field {
      id: box
      property var field: null
      property var value: ""
      signal commit(var next)
      signal typed(string text)
      width: parent ? parent.width : 0
      placeholder: box.field && box.field.placeholder ? box.field.placeholder : ""

      // The saved value shows, until the person starts typing.
      Binding { target: box; property: "text"; value: box.value === undefined || box.value === null ? "" : String(box.value); when: !box.focused }
      onTextChanged: if (box.focused) box.typed(box.text)
      function submit() { if (box.text !== String(box.value === undefined || box.value === null ? "" : box.value)) box.commit(box.text) }
      onAccepted: box.submit()
      onFocusedChanged: if (!box.focused) box.submit()
      // Escape drops what was typed, then closes the window: nothing is saved by leaving.
      onEscaped: box.text = box.value === undefined || box.value === null ? "" : String(box.value)
    }
  }

  // One segment of a choice.
  component Segment: Rectangle {
    id: seg
    property string text: ""
    property bool selected: false
    signal clicked()
    width: segLabel.implicitWidth + Style.spacing.lg * 2
    height: Style.space(28)
    radius: Math.max(Style.cornerRadius, Style.space(5))
    color: seg.selected ? Color.accent
      : (segHover.hovered ? Style.hoverFillFor(Color.foreground, Color.accent) : Util.alpha(Color.foreground, 0.08))
    Text {
      id: segLabel
      anchors.centerIn: parent
      text: seg.text
      color: seg.selected ? Color.menu.background : Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    HoverHandler { id: segHover }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: seg.clicked()
    }
  }
}
