import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Reqall in the bar: one icon, one panel. The panel is a synopsis of the
// signed-in account (recent memories, open work, project count) and turns
// into a sign-in prompt when there are no working credentials. Main.qml owns
// the data; this file owns the button, the popup, and keyboard navigation.
Panel {
  id: root
  moduleName: "reqall.memory"
  ipcTarget: "reqall.memory"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // Bar glyph, chosen by the barIcon setting: a monochrome Nerd Font brain
  // (default), the head-with-gear that echoes the Reqall logo, or the colour
  // brain emoji for people who want it to pop.
  readonly property string barIcon: String(setting("barIcon", "brain"))
  readonly property string glyph: barIcon === "emoji" ? "\u{1F9E0}"
    : barIcon === "head-cog" ? "\u{F133C}"   // nf-md-head_cog
    : "\u{F09D1}"                            // nf-md-brain
  readonly property string logoSource: Qt.resolvedUrl("assets/reqall-mark.png")

  // Countdowns and "updated" read this instead of Date.now() so the panel
  // keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  // ------------------------------------------------------------- cursor
  //
  // Two navigable sections: the action buttons under the hero, then the
  // recent-memory rows. j/k walk between them, h/l walk along the buttons.
  property bool cursorActive: false
  property string focusSection: "actions"
  property int actionIndex: 0
  property int recentIndex: 0

  readonly property var actions: {
    var _ = reqall.revision
    return buildActions()
  }
  readonly property var recent: reqall.recent
  readonly property bool signedIn: reqall.signedIn
  readonly property bool needsAuth: reqall.auth === "none" || reqall.auth === "invalid" || reqall.auth === "paused"

  function buildActions() {
    var list = []
    if (reqall.auth === "ok") {
      list.push({ id: "open", label: "Open Reqall", icon: "\u{F059F}" })       // nf-md-web
      list.push({ id: "add", label: "Quick add", icon: "\u{F0415}" })          // nf-md-plus
      list.push({ id: "refresh", label: "Refresh", icon: "\u{F0450}" })        // nf-md-refresh
    } else if (reqall.auth === "loading") {
      list.push({ id: "refresh", label: "Refresh", icon: "\u{F0450}" })
    } else if (reqall.auth === "error") {
      list.push({ id: "refresh", label: "Retry", icon: "\u{F0450}" })
      list.push({ id: "open", label: "Open Reqall", icon: "\u{F059F}" })
    } else {
      list.push({ id: "signin", label: "Sign in / Sign up", icon: "\u{F0342}" }) // nf-md-login
      list.push({ id: "apikey", label: "Get API key", icon: "\u{F0306}" })       // nf-md-key
      if (reqall.hasCli) list.push({ id: "cli", label: "CLI login", icon: "" }) // nf-fa-terminal
      list.push({ id: "refresh", label: "Refresh", icon: "\u{F0450}" })
    }
    return list
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  function openUrl(url) {
    if (root.bar) root.bar.run("omarchy-launch-browser " + Model.shellQuote(url))
    root.close()
  }

  function runAction(id) {
    switch (id) {
    case "open": openUrl(reqall.url + "/dashboard"); break
    case "add": openUrl(reqall.url + "/app"); break
    case "signin": openUrl(reqall.url + "/auth/login"); break
    case "apikey": openUrl(reqall.url + "/dashboard#keys"); break
    case "cli":
      if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation reqall login")
      root.close()
      break
    case "refresh": reqall.refresh(); break
    }
  }

  function openRecord(record) {
    if (!record) return
    openUrl(reqall.url + "/dashboard#records")
  }

  function ensureCursor() {
    if (actions.length === 0 && recent.length > 0) focusSection = "recent"
    if (focusSection === "recent" && recent.length === 0) focusSection = "actions"
    actionIndex = clamp(actionIndex, 0, Math.max(0, actions.length - 1))
    recentIndex = clamp(recentIndex, 0, Math.max(0, recent.length - 1))
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (focusSection === "actions") {
      if (dx !== 0) actionIndex = clamp(actionIndex + dx, 0, actions.length - 1)
      if (dy > 0 && recent.length > 0) { focusSection = "recent"; recentIndex = 0 }
    } else {
      if (dy < 0) {
        if (recentIndex > 0) recentIndex--
        else if (actions.length > 0) focusSection = "actions"
      } else if (dy > 0 && recentIndex < recent.length - 1) {
        recentIndex++
      }
    }
    scrollCursorIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "actions") {
      if (actions.length > 0) runAction(actions[actionIndex].id)
    } else if (recent.length > 0) {
      openRecord(recent[recentIndex])
    }
  }

  function setActionCursor(index) {
    cursorActive = true
    focusSection = "actions"
    actionIndex = index
  }

  function setRecentCursor(index) {
    cursorActive = true
    focusSection = "recent"
    recentIndex = index
    scrollCursorIntoView()
  }

  function scrollItemIntoView(item) {
    if (!item || !panelFlick) return
    var top = item.mapToItem(column, 0, 0).y
    var bottom = top + item.height
    if (top < panelFlick.contentY) panelFlick.contentY = Math.max(0, top - Style.space(8))
    else if (bottom > panelFlick.contentY + panelFlick.height)
      panelFlick.contentY = Math.min(Math.max(0, panelFlick.contentHeight - panelFlick.height), bottom - panelFlick.height + Style.space(8))
  }

  function scrollCursorIntoView() {
    if (focusSection === "actions") { panelFlick.contentY = 0; return }
    if (recentColumn && recentIndex >= 0 && recentIndex < recentColumn.children.length)
      scrollItemIntoView(recentColumn.children[recentIndex])
  }

  function updatedText() {
    if (reqall.loading && !reqall.data) return "Loading…"
    if (!reqall.fetchedAtMs) return ""
    var rel = Model.relativeTime(new Date(reqall.fetchedAtMs).toISOString(), nowMs)
    return (reqall.loading ? "Refreshing · " : "Updated ") + rel
  }

  function emptyStateText() {
    switch (reqall.auth) {
    case "loading": return "Fetching your memories…"
    case "none":
      return "Sign in to see recent memories and open work here. After signing in, create an API key on the dashboard and paste it into this widget's settings, or add it to ~/.config/reqall/env."
    case "invalid":
      return (reqall.message || "Credentials rejected") + ". Create a fresh API key on the dashboard and update this widget's settings or ~/.config/reqall/env."
    case "paused":
      return (reqall.message || "API key paused") + ". Reactivate it on the dashboard."
    case "error":
      return reqall.message || "Reqall could not be reached."
    default:
      return recent.length === 0 ? "No memories yet. Anything your agents or CLI record shows up here." : ""
    }
  }

  // Every bar is a separate surface, so refreshes come from one place.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    focusSection = "actions"
    actionIndex = 0
    recentIndex = 0
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    if (Date.now() - reqall.fetchedAtMs > 60000) reqall.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Main {
    id: reqall
    settings: root.settings
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { reqall.refresh(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    active: reqall.auth === "invalid" || reqall.auth === "paused"
    opacity: reqall.auth === "none" ? 0.55 : 1.0
    tooltipText: ""
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.openUrl(reqall.url + "/dashboard")
      else if (buttonCode === Qt.MiddleButton) reqall.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; root.ensureCursor(); return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") reqall.refresh()
        else if (t === "o" || t === "O") root.openUrl(reqall.url + "/dashboard")
        else if ((t === "a" || t === "A") && root.signedIn) root.openUrl(reqall.url + "/app")
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Hero: mark · Reqall · status ----------
          PanelHero {
            width: parent.width
            title: "Reqall"
            meta: Model.statusLine(reqall.data)
            detail: root.signedIn && reqall.counts ? Model.compactCount(reqall.counts.records) + " memories" : ""
            foreground: root.foreground
            fontFamily: root.fontFamily

            // The Reqall mark is a detailed illustration, so it gets more room
            // than a glyph would and falls back to the glyph if the asset is
            // missing. It dims when there is nothing to show behind it.
            iconComponent: Component {
              Item {
                width: Style.space(40)
                height: Style.space(40)
                opacity: root.needsAuth ? 0.55 : 1.0

                Image {
                  id: logoImage
                  anchors.fill: parent
                  source: root.logoSource
                  sourceSize.width: Style.space(40) * 2
                  sourceSize.height: Style.space(40) * 2
                  fillMode: Image.PreserveAspectFit
                  smooth: true
                  mipmap: true
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  visible: logoImage.status !== Image.Ready
                  text: root.glyph
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
            }
          }

          // ---------- Actions ----------
          Flow {
            id: actionRow
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.actions

              Button {
                required property var modelData
                required property int index
                text: modelData.label
                iconText: modelData.icon
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                hasCursor: root.cursorActive && root.focusSection === "actions" && root.actionIndex === index
                iconSpinning: modelData.id === "refresh" && reqall.loading
                onHovered: function(isHovered) { if (isHovered) root.setActionCursor(index) }
                onClicked: root.runAction(modelData.id)
              }
            }
          }

          // ---------- Empty / problem state ----------
          Text {
            visible: text !== ""
            width: parent.width
            text: root.emptyStateText()
            color: reqall.auth === "invalid" || reqall.auth === "paused" || reqall.auth === "error" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            lineHeight: 1.2
          }

          // ---------- Usage ----------
          PanelSeparator {
            visible: statsSection.visible
            foreground: root.foreground
          }

          Column {
            id: statsSection
            visible: root.signedIn && !!reqall.counts
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: reqall.setting("project", "") !== "" ? String(reqall.setting("project", "")).toUpperCase() : "USAGE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              StatTile { label: "MEMORIES"; value: reqall.counts ? reqall.counts.records : 0 }
              StatTile { label: "OPEN TODOS"; value: reqall.counts ? reqall.counts.openTodos : 0 }
              StatTile { label: "OPEN ISSUES"; value: reqall.counts ? reqall.counts.openIssues : 0; hot: reqall.counts && reqall.counts.openIssues > 0 }
              StatTile { label: "PROJECTS"; value: reqall.counts ? reqall.counts.projects : 0 }
            }
          }

          // ---------- Recent memories ----------
          PanelSeparator {
            visible: recentSection.visible
            foreground: root.foreground
          }

          Column {
            id: recentSection
            visible: root.signedIn && root.recent.length > 0
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "RECENT MEMORIES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: recentColumn
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: root.recent

                RecordRow {
                  required property var modelData
                  required property int index
                  width: parent.width
                  record: modelData
                  rowIndex: index
                }
              }
            }
          }

          // ---------- Footer ----------
          Text {
            width: parent.width
            topPadding: Style.space(2)
            text: {
              var parts = []
              var updated = root.updatedText()
              if (updated) parts.push(updated)
              if (reqall.source && root.signedIn) parts.push("key: " + reqall.source)
              parts.push("r refresh")
              if (root.signedIn) parts.push("o open")
              return parts.join(" · ")
            }
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // One number with a small-caps label under it.
  component StatTile: Column {
    id: tile
    property string label: ""
    property var value: 0
    property bool hot: false

    Layout.fillWidth: true
    spacing: Style.space(3)

    Text {
      textFormat: Text.PlainText
      text: Model.compactCount(tile.value)
      color: tile.hot ? root.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      font.bold: true
    }

    Text {
      textFormat: Text.PlainText
      text: tile.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
      elide: Text.ElideRight
      width: parent.width
    }
  }

  // A recent memory: kind glyph, title, project, and how long ago it changed.
  component RecordRow: CursorSurface {
    id: row
    property var record: null
    property int rowIndex: -1

    hasCursor: root.cursorActive && root.focusSection === "recent" && root.recentIndex === rowIndex
    foreground: root.foreground
    implicitHeight: rowLayout.implicitHeight + Style.space(10)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setRecentCursor(row.rowIndex)
      onClicked: root.openRecord(row.record)
    }

    RowLayout {
      id: rowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: Model.kindGlyph(row.record ? row.record.kind : "")
        color: row.record && row.record.kind === "issue" && row.record.status === "open" ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.preferredWidth: Style.space(18)
        horizontalAlignment: Text.AlignHCenter
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: row.record ? String(row.record.title || "") : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: row.record
            ? [String(row.record.project_name || ""), Model.kindLabel(row.record.kind), String(row.record.status || "")].filter(function(s) { return s !== "" }).join(" · ")
            : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        textFormat: Text.PlainText
        text: row.record ? Model.relativeTime(row.record.updated_at, root.nowMs) : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }
}
