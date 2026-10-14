import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar widget + popup for Cloud Drives: one row per provider (Google Drive,
// OneDrive, iCloud Drive) with connect / mount / open / disconnect actions.
// All the work happens in bin/omarchy-cloud-drives; interactive steps
// (sign-in, 2FA, confirmations) run in a floating terminal.
Panel {
  id: root
  moduleName: "edbron.cloud-drives"
  ipcTarget: "edbron.cloud-drives"
  manageIpc: false

  readonly property string script: String(Qt.resolvedUrl("bin/omarchy-cloud-drives")).replace(/^file:\/\//, "")

  property bool rcloneInstalled: false
  property bool encrypted: false
  property bool keyring: false
  property string mountRoot: ""
  property var providers: []
  readonly property bool busy: busyId !== ""

  readonly property int mountedCount: {
    var n = 0
    for (var i = 0; i < providers.length; i++) if (providers[i].mounted) n++
    return n
  }
  readonly property int connectedCount: {
    var n = 0
    for (var i = 0; i < providers.length; i++) if (providers[i].configured) n++
    return n
  }
  readonly property bool secure: rcloneInstalled && encrypted && keyring
  readonly property color dim: Qt.darker(bar.foreground, 1.4)

  // Cursor: one row per provider; h/l moves across that row's controls.
  property bool cursorActive: false
  property int selectedIndex: 0
  property var actionCursor: ({})
  property string busyId: ""
  property string lastError: ""
  property var usage: ({})

  // The controls of a row, left to right. "toggle" (mount / unmount) and
  // "connect" are the row's primary action.
  function actionsFor(p) {
    if (!p) return []
    if (!p.configured) return ["connect"]
    return p.mounted ? ["open", "disconnect", "toggle"] : ["disconnect", "toggle"]
  }
  function primaryIndex(p) { return actionsFor(p).length - 1 }

  function actionCursorFor(row) {
    var acts = actionsFor(providers[row])
    var i = actionCursor[row]
    return i === undefined ? Math.max(0, acts.length - 1) : Math.min(i, acts.length - 1)
  }
  function setActionCursor(row, idx) {
    var next = Object.assign({}, actionCursor); next[row] = idx; actionCursor = next
  }
  function resetCursors() { actionCursor = ({}) }

  function moveCursor(delta) {
    var n = providers.length
    if (!n) return
    selectedIndex = Math.max(0, Math.min(n - 1, selectedIndex + delta))
  }
  function moveCursorH(delta) {
    var acts = actionsFor(providers[selectedIndex])
    if (!acts.length) return
    setActionCursor(selectedIndex, Math.max(0, Math.min(acts.length - 1, actionCursorFor(selectedIndex) + delta)))
  }
  function activateCursor() {
    var p = providers[selectedIndex]
    if (!p) return
    perform(actionsFor(p)[actionCursorFor(selectedIndex)], p)
  }

  // What a click on the row itself does: open it, mount it, or connect it.
  function rowPrimary(p) { return !p.configured ? "connect" : (p.mounted ? "open" : "toggle") }

  function perform(action, p) {
    if (action === "toggle") run(p.mounted || p.active ? "unmount" : "mount", p.id)
    else run(action, p.id)
  }

  function formatBytes(n) {
    if (n === undefined || n === null) return ""
    var units = ["B", "KB", "MB", "GB", "TB", "PB"], i = 0
    while (n >= 1000 && i < units.length - 1) { n /= 1000; i++ }
    return (n >= 100 || i === 0 ? Math.round(n) : n.toFixed(1)) + " " + units[i]
  }
  function usageText(id) {
    var u = usage[id]
    if (!u || u.used === undefined) return ""
    return u.total ? formatBytes(u.used) + " of " + formatBytes(u.total) : formatBytes(u.used) + " used"
  }
  function usageFraction(id) {
    var u = usage[id]
    return u && u.total && u.used !== undefined ? Math.max(0, Math.min(1, u.used / u.total)) : -1
  }
  function tildePath(p) { return String(p || "").replace(/^\/home\/[^\/]+/, "~") }

  function statusText(p) {
    if (!p.configured) return "Not connected"
    if (busyId === p.id) return p.mounted ? "Unmounting…" : "Mounting…"
    if (p.failed) return "Mount failed · retrying"
    if (p.mounted) return "Mounted"
    if (p.active) return "Mounting…"
    return "Connected · not mounted"
  }
  function statusColor(p) {
    if (p.failed) return bar.urgent
    if (p.mounted) return Color.accent
    return dim
  }

  property var aboutQueue: []
  function refreshUsage() {
    var q = []
    for (var i = 0; i < providers.length; i++) if (providers[i].mounted) q.push(providers[i].id)
    aboutQueue = q
    nextAbout()
  }
  function nextAbout() {
    if (aboutProc.running || !aboutQueue.length) return
    aboutProc.pid_id = aboutQueue[0]
    aboutQueue = aboutQueue.slice(1)
    aboutProc.command = [script, "about", aboutProc.pid_id]
    aboutProc.running = true
  }

  function refresh() { if (!stateProc.running) stateProc.running = true }

  // connect / disconnect need a terminal (browser sign-in, 2FA, confirm);
  // open is detached; mount / unmount run here and report failures.
  function run(action, id) {
    if (busyId !== "") return
    lastError = ""
    if (action === "connect" || action === "disconnect") {
      Quickshell.execDetached([script, "launch", action, id])
      close()
      return
    }
    if (action === "open") {
      Quickshell.execDetached([script, "open", id])
      close()
      return
    }
    busyId = id
    actionProc.command = [script, action, id]
    actionProc.running = true
  }

  function allMounted() { return connectedCount > 0 && mountedCount === connectedCount }
  function toggleAll() {
    if (busyId !== "") return
    lastError = ""
    busyId = "*"
    actionProc.command = [script, allMounted() ? "unmount-all" : "mount-all"]
    actionProc.running = true
  }

  function stateIpc() {
    return JSON.stringify({ rclone: rcloneInstalled, encrypted: encrypted, keyring: keyring, providers: providers })
  }

  IpcHandler {
    target: "edbron.cloud-drives"
    function state(): string { return root.stateIpc() }
    function refresh(): string { root.refresh(); return "ok" }
    function mount(id: string): string { root.run("mount", id); return "ok" }
    function unmount(id: string): string { root.run("unmount", id); return "ok" }
    function connect(id: string): string { root.run("connect", id); return "ok" }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) {
    refresh()
    refreshUsage()
    cursorActive = false
    selectedIndex = 0
    resetCursors()
    lastError = ""
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }
  onProvidersChanged: if (selectedIndex >= providers.length) selectedIndex = 0

  // Mounts can appear/vanish from the terminal flow, so poll: fast while
  // open, slow otherwise. Usage is slower still: it asks the cloud.
  Timer {
    interval: root.opened ? 2000 : 30000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }
  Timer {
    interval: 120000
    running: root.opened
    repeat: true
    onTriggered: root.refreshUsage()
  }

  Process {
    id: stateProc
    command: [root.script, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var s = JSON.parse(String(text || "{}"))
          root.rcloneInstalled = !!s.rclone
          root.encrypted = !!s.encrypted
          root.keyring = !!s.keyring
          root.mountRoot = s.root || ""
          root.providers = s.providers || []
        } catch (e) {
          root.providers = []
        }
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      id: actionErr
      waitForEnd: true
    }
    onExited: function(code) {
      if (code !== 0) {
        var lines = String(actionErr.text || "").trim().split("\n")
        root.lastError = lines[lines.length - 1] || "The action failed"
      }
      root.busyId = ""
      root.refresh()
      root.refreshUsage()
    }
  }

  Process {
    id: aboutProc
    property string pid_id: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var u = JSON.parse(String(text || "{}"))
          var next = Object.assign({}, root.usage)
          next[aboutProc.pid_id] = u
          root.usage = next
        } catch (e) {}
      }
    }
    onRunningChanged: if (!running) root.nextAbout()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.mountedCount > 0 ? "󰅟" : "󰅧"
    onPressed: function(b) {
      if (b === Qt.RightButton) { root.refresh(); root.refreshUsage() }
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(600))

    content: PanelKeyCatcher {
      id: keyCatcher
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var p = root.providers[root.selectedIndex]
        var k = String(t).toLowerCase()
        if (k === "r") { root.refresh(); root.refreshUsage() }
        else if (k === "a") root.toggleAll()
        else if (!p) return
        else if (k === "m") root.perform(p.configured ? "toggle" : "connect", p)
        else if (k === "o" && p.mounted) root.run("open", p.id)
        else if (k === "f" && p.configured) root.run("disconnect", p.id)
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          // ---------- Hero ----------
          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight

            PanelHero {
              id: hero
              width: parent.width
              title: "Cloud Drives"
              detail: root.connectedCount ? root.mountedCount + "/" + root.connectedCount : ""
              meta: {
                if (!root.rcloneInstalled) return "Not set up · connect a drive to begin"
                if (!root.connectedCount) return "No accounts connected"
                return root.secure ? "Keyring-encrypted" : "Config not encrypted"
              }
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              iconOpacity: root.mountedCount > 0 ? 1.0 : 0.5
              iconComponent: Component {
                Text {
                  text: root.mountedCount > 0 ? "󰅟" : "󰅧"
                  color: hero.foreground
                  font.family: hero.fontFamily
                  font.pixelSize: Style.font.display
                }
              }

              // Mount or unmount every connected drive at once.
              trailingControl: Component {
                ToggleSwitch {
                  id: allSwitch
                  visible: root.connectedCount > 1
                  checked: root.allMounted()
                  busy: root.busy
                  foreground: hero.foreground
                  onToggled: root.toggleAll()

                  PanelToolTip {
                    visible: allSwitch.containsMouse
                    text: root.allMounted() ? "Unmount all  (a)" : "Mount all  (a)"
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.lastError !== "" || (root.connectedCount > 0 && !root.secure)
            width: parent.width
            text: root.lastError !== "" ? root.lastError : "The rclone config is not keyring-encrypted. Reconnect a drive to fix this."
            color: root.bar.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Drives ----------
          Column {
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: provHeader.implicitHeight

              PanelSectionHeader {
                id: provHeader
                text: "DRIVES"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              // The mount root, as a link to the folder.
              Text {
                id: rootLink
                text: root.tildePath(root.mountRoot) + "  󰉋"
                color: rootMouse.containsMouse ? root.bar.foreground : root.dim
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  id: rootMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { Quickshell.execDetached(["xdg-open", root.mountRoot]); root.close() }
                }
                PanelToolTip {
                  visible: rootMouse.containsMouse
                  text: "Open " + root.tildePath(root.mountRoot)
                  fontFamily: root.bar.fontFamily
                }
              }
            }

            Column {
              id: driveColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.providers
                ProviderRow {
                  required property var modelData
                  required property int index
                  width: driveColumn.width
                  provider: modelData
                  rowIndex: index
                }
              }
            }
          }

          // ---------- Footnote ----------
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Sign in with your browser (Google, Microsoft) or Apple ID + 2FA (iCloud). Credentials stay in an rclone config encrypted with a key held only in your login keyring."
            color: root.dim
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  component ProviderRow: CursorSurface {
    id: row
    required property var provider
    required property int rowIndex
    readonly property var actions: root.actionsFor(provider)
    readonly property bool working: root.busyId === provider.id || root.busyId === "*"
    readonly property real fraction: root.usageFraction(provider.id)
    readonly property string usageLine: provider.mounted ? root.usageText(provider.id) : ""

    function hot(action) {
      return root.cursorActive && root.selectedIndex === rowIndex
        && row.actions[root.actionCursorFor(rowIndex)] === action
    }
    function claim(action) {
      root.cursorActive = true
      root.selectedIndex = rowIndex
      root.setActionCursor(rowIndex, row.actions.indexOf(action))
    }

    foreground: root.bar.foreground
    hasCursor: root.cursorActive && root.selectedIndex === rowIndex
    current: provider.mounted
    implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX + Style.spacing.md

    // The row itself: click for its primary action. Sits below the controls.
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.selectedIndex = row.rowIndex }
      onClicked: root.perform(root.rowPrimary(row.provider), row.provider)
    }

    Column {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(6)

      Row {
        width: parent.width
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          text: row.provider.glyph
          color: row.provider.configured ? root.bar.foreground : root.dim
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.display
          width: Style.space(28)
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          id: labels
          width: parent.width - Style.space(28) - controls.width - Style.space(20)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)

          Text {
            textFormat: Text.PlainText
            text: row.provider.name
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Row {
            spacing: Style.space(6)
            width: parent.width

            Rectangle {
              width: Style.space(7)
              height: width
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              visible: row.provider.configured
              color: root.statusColor(row.provider)
              opacity: row.working || row.provider.failed ? 0.6 : 1
              SequentialAnimation on opacity {
                running: row.working
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 500 }
                NumberAnimation { to: 1; duration: 500 }
              }
            }
            Text {
              textFormat: Text.PlainText
              text: root.statusText(row.provider)
              color: row.provider.failed ? root.bar.urgent : root.dim
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width - (row.provider.configured ? Style.space(13) : 0)
            }
          }
        }

        // ---- controls ----
        Row {
          id: controls
          spacing: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter

          PanelActionButton {
            visible: row.provider.configured && row.provider.mounted
            iconText: "󰉋"
            tooltipText: "Open in file manager  (o)"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            enabled: !root.busy
            hasCursor: row.hot("open")
            onHovered: function(on) { if (on) row.claim("open") }
            onClicked: root.run("open", row.provider.id)
          }

          PanelActionButton {
            visible: row.provider.configured
            iconText: "󰩹"
            tooltipText: "Forget this account  (f)"
            foreground: root.bar.foreground
            hoverColor: root.bar.urgent
            fontFamily: root.bar.fontFamily
            enabled: !root.busy
            hasCursor: row.hot("disconnect")
            onHovered: function(on) { if (on) row.claim("disconnect") }
            onClicked: root.run("disconnect", row.provider.id)
          }

          ToggleSwitch {
            id: mountSwitch
            visible: row.provider.configured
            anchors.verticalCenter: parent.verticalCenter
            cursorPad: Style.space(3)
            checked: row.provider.mounted || row.provider.active
            busy: row.working
            foreground: root.bar.foreground
            hasCursor: row.hot("toggle")
            onHovered: function(on) { if (on) row.claim("toggle") }
            onToggled: root.perform("toggle", row.provider)

            PanelToolTip {
              visible: mountSwitch.containsMouse
              text: (mountSwitch.checked ? "Unmount" : "Mount") + "  (m)"
              fontFamily: root.bar.fontFamily
            }
          }

          Button {
            visible: !row.provider.configured
            text: "Connect"
            iconText: "󰌘"
            fontSize: Style.font.caption
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.md
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            enabled: !root.busy
            hasCursor: row.hot("connect")
            onHovered: function(isHovered) { if (isHovered) row.claim("connect") }
            onClicked: root.run("connect", row.provider.id)
          }
        }
      }

      // Storage: a slim meter and the figures, once the drive reports them.
      Column {
        visible: row.usageLine !== ""
        width: parent.width - Style.space(38)
        x: Style.space(38)
        spacing: Style.space(4)

        Rectangle {
          visible: row.fraction >= 0
          width: parent.width
          height: Style.space(3)
          radius: height / 2
          color: Util.alpha(root.bar.foreground, 0.12)

          Rectangle {
            width: Math.max(parent.height, parent.width * Math.max(0, row.fraction))
            height: parent.height
            radius: height / 2
            color: row.fraction > 0.9 ? root.bar.urgent : Color.accent
            Behavior on width { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
          }
        }

        Text {
          textFormat: Text.PlainText
          text: row.usageLine
          color: root.dim
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
