// StartDrive: the bar widget and its panel. DriveService.qml owns the data and
// every call to bin/startdrive, DriveModel.js the rules, DriveRow.qml the
// look of one drive. This file wires them to the bar, the keyboard and IPC.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "DriveModel.js" as Model

Panel {
  id: root
  moduleName: "io.github.bmaltais.startdrive"
  ipcTarget: "io.github.bmaltais.startdrive"
  manageIpc: false

  // ---- what DriveRow reads ------------------------------------------------
  readonly property alias service: service
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property string expandedId: ""
  property string detailTab: "cache"

  // ---- keyboard cursor ----------------------------------------------------
  // One flat list of stops (Model.navStops): each drive's row, then the
  // detail items of the expanded drive. h/l walks a row's controls or changes
  // a choice; Enter activates.
  property bool cursorActive: false
  property int navIndex: 0
  property var controlCursor: ({})
  readonly property var stops: Model.navStops(service.drives, expandedId, detailTab)
  readonly property var stop: stops.length ? stops[Math.min(navIndex, stops.length - 1)] : null

  readonly property Item flick: panel.loadedContent ? panel.loadedContent.flick : null

  function controlsOf(id) {
    var d = service.drive(id)
    return d ? Model.rowControls(d) : []
  }
  function controlIndex(id) {
    var controls = controlsOf(id)
    var i = controlCursor[id]
    return i === undefined ? controls.length - 1 : Math.min(i, controls.length - 1)
  }
  function setControlIndex(id, i) {
    var next = Object.assign({}, controlCursor)
    next[id] = i
    controlCursor = next
  }

  function isHot(kind, id, key) {
    if (!cursorActive || !stop || stop.kind !== kind || stop.id !== id) return false
    if (kind === "detail") return stop.key === key
    return key === "" || controlsOf(id)[controlIndex(id)] === key
  }

  function claim(kind, id, key) {
    cursorActive = true
    for (var i = 0; i < stops.length; i++) {
      var s = stops[i]
      if (s.kind === kind && s.id === id && (kind === "row" || s.key === key)) { navIndex = i; break }
    }
    if (kind === "row" && key !== "") setControlIndex(id, controlsOf(id).indexOf(key))
  }

  function move(dy) {
    cursorActive = true
    navIndex = Math.max(0, Math.min(stops.length - 1, navIndex + dy))
  }

  function moveHorizontal(dx) {
    if (!stop) return
    if (stop.kind === "row") {
      var controls = controlsOf(stop.id)
      setControlIndex(stop.id, Math.max(0, Math.min(controls.length - 1, controlIndex(stop.id) + dx)))
    } else if (stop.key === "tabs") {
      detailTab = Model.stepOption(Model.DETAIL_TABS, detailTab, dx)
    } else if (stop.key === "cacheSize") {
      var d = service.drive(stop.id)
      service.set(stop.id, "cache-size", Model.stepOption(Model.CACHE_SIZES, d.settings.cacheSize, dx))
    } else if (stop.key === "cacheAge") {
      var e = service.drive(stop.id)
      service.set(stop.id, "cache-age", Model.stepOption(Model.CACHE_AGES, e.settings.cacheAge, dx))
    }
  }

  function activate() {
    if (!stop) return
    var d = service.drive(stop.id)
    if (!d) return
    if (stop.kind === "row") { perform(controlsOf(stop.id)[controlIndex(stop.id)], d); return }
    if (stop.key === "autostart") service.set(d.id, "autostart", String(!d.settings.autostart))
    else if (stop.key === "readOnly") service.set(d.id, "read-only", String(!d.settings.readOnly))
    else if (stop.key === "refresh") service.refreshListing(d.id)
    else if (stop.key === "clearCache") service.clearCache(d.id)
  }

  function perform(control, d) {
    switch (control) {
    case "toggle":
      if (d.mounted || d.unit === "activating") service.unmount(d.id)
      else service.mount(d.id)
      break
    case "open": service.openDrive(d.id); close(); break
    case "connect":
    case "disconnect": service.interactive(control, d.id); close(); break
    case "details": toggleDetails(d.id); break
    }
  }

  function toggleDetails(id) {
    expandedId = expandedId === id ? "" : id
    if (expandedId !== "") service.refreshUsage()
    claim("row", id, "")
  }

  // Keep the cursor's item inside the visible part of the panel.
  function reveal(item) {
    if (!flick || !item) return
    Qt.callLater(function () {
      if (!item) return
      var margin = Style.space(6)
      var top = item.mapToItem(flick.contentItem, 0, 0).y
      var bottom = top + item.height
      var maxY = Math.max(0, flick.contentHeight - flick.height)
      if (top < flick.contentY + margin) flick.contentY = Math.max(0, top - margin)
      else if (bottom > flick.contentY + flick.height - margin) flick.contentY = Math.min(maxY, bottom + margin - flick.height)
    })
  }

  // ---- bar ------------------------------------------------------------------
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    service.panelOpen = opened
    if (!opened) return
    cursorActive = false
    navIndex = 0
    controlCursor = ({})
    service.error = ""
    service.notice = ""
    service.refresh()
    service.refreshActivity()
    service.refreshUsage()
    if (flick) flick.contentY = 0
    Qt.callLater(function () { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }
  onStopsChanged: if (navIndex >= stops.length) navIndex = Math.max(0, stops.length - 1)

  DriveService {
    id: service
    script: String(Qt.resolvedUrl("bin/startdrive")).replace(/^file:\/\//, "")
  }

  IpcHandler {
    target: "io.github.bmaltais.startdrive"
    function state(): string { return JSON.stringify({ drives: service.drives, activity: service.activity }) }
    function refresh(): string { service.refresh(); service.refreshActivity(); return "ok" }
    function mount(id: string): string { service.mount(id); return "ok" }
    function unmount(id: string): string { service.unmount(id); return "ok" }
    function mountAll(): string { service.mountAll(); return "ok" }
    function unmountAll(): string { service.unmountAll(); return "ok" }
    function connect(id: string): string { service.interactive("connect", id); return "ok" }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: service.summary.glyph
    onPressed: function (b) {
      if (b === Qt.RightButton) { service.refresh(); service.refreshActivity() }
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
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(640))

    content: PanelKeyCatcher {
      id: keys
      property alias flick: flick
      implicitHeight: top.height + Style.space(10) + column.implicitHeight
      anchors.fill: parent

      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.move(dy)
        else if (dx !== 0) root.moveHorizontal(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activate()
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        var key = String(t).toLowerCase()
        var d = root.stop ? service.drive(root.stop.id) : null
        if (key === "r") { service.refresh(); service.refreshActivity(); service.refreshUsage() }
        else if (key === "n") { service.addRemote(); root.close() }
        else if (key === "a") { if (service.summary.mounted === service.summary.connected) service.unmountAll(); else service.mountAll() }
        else if (!d) return
        else if (key === "m") root.perform(d.configured ? "toggle" : "connect", d)
        else if (key === "o" && d.mounted) root.perform("open", d)
        else if (key === "f" && d.configured) root.perform("disconnect", d)
        else if (key === "d" && d.configured) root.toggleDetails(d.id)
      }

      // The title, the all-drives switch and the section header stay put; only
      // the drives scroll beneath them.
      Column {
        id: top
        width: parent.width
        spacing: Style.space(12)

          // ---------- Hero ----------
          PanelHero {
            id: hero
            width: parent.width
            title: "StartDrive"
            meta: Model.headline(service.summary, service.secure, service.rcloneInstalled)
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: service.summary.mounted > 0 ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: service.summary.glyph
                color: service.summary.errored || service.summary.failed ? root.urgent : hero.foreground
                font.family: hero.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            // Mount or unmount every connected drive at once.
            trailingControl: Component {
              ToggleSwitch {
                id: allSwitch
                visible: service.summary.connected > 1
                checked: service.summary.mounted === service.summary.connected
                busy: service.busy
                foreground: hero.foreground
                onToggled: checked ? service.unmountAll() : service.mountAll()

                PanelToolTip {
                  visible: allSwitch.containsMouse
                  text: (allSwitch.checked ? "Unmount all" : "Mount all") + "  (a)"
                  fontFamily: hero.fontFamily
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: service.error !== "" ? service.error
              : (service.summary.connected > 0 && !service.secure) ? "The rclone config is not keyring-encrypted. Reconnect a drive to fix this."
              : service.notice
            color: service.error !== "" || !service.secure ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.foreground }

            Item {
              width: parent.width
              implicitHeight: header.implicitHeight

              PanelSectionHeader {
                id: header
                text: "DRIVES"
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

            }
      }

      ScrollTrack {
        id: scrollTrack
        flick: flick
        foreground: root.foreground
        anchors.top: flick.top
        anchors.bottom: flick.bottom
        anchors.right: parent.right
      }

      Flickable {
        id: flick
        anchors.top: top.bottom
        anchors.topMargin: Style.space(10)
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: scrollTrack.gutter + scrollTrack.width
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

            Column {
              id: driveColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: service.drives
                DriveRow {
                  required property var modelData
                  width: driveColumn.width
                  drive: modelData
                  host: root
                }
              }
            }

            // Any other rclone backend, through rclone's own questionnaire.
            Button {
              text: "Add remote…"
              iconText: "󰐕"
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.md
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              enabled: !service.busy
              onClicked: { service.addRemote(); root.close() }
            }
        }
      }
    }
  }
}
