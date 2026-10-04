import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Reqall in the bar: one icon, one panel. The panel is a synopsis of the
// signed-in account (recent memories, open work, project count) with a
// Remember form for adding a record, and turns into a sign-in prompt when
// there are no working credentials. Main.qml owns the data; this file owns
// the button, the popup, the form, and keyboard navigation.
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

  // ------------------------------------------------------------- Remember
  //
  // Project picker, title, body, kind. While any of its fields has focus the
  // key catcher stands aside (`blocked`), so typing goes to the field; Esc
  // hands the keys back to the panel cursor, and `a` or `/` returns.
  readonly property string currentProject: String(reqall.setting("project", ""))
  property var formProject: null
  property string formKind: "auto"
  property string projectQuery: ""
  property int pickerIndex: 0
  property string formStatus: ""
  property bool formError: false
  readonly property bool formFocused: projectField.activeFocus || titleField.activeFocus
    || bodyArea.activeFocus || kindRow.activeFocus
  readonly property bool pickerOpen: projectField.activeFocus
  readonly property var pickerRows: Model.rankProjects(reqall.projects, projectQuery, currentProject, reqall.usedProjects, 6)
  readonly property bool canRemember: signedIn && !!formProject && titleField.text.trim() !== "" && !reqall.saving

  // The current filter project if there is one, else the last one used.
  function preselectProject() {
    if (formProject || reqall.projects.length === 0) return
    var pick = Model.findProject(reqall.projects, currentProject)
    for (var i = 0; !pick && i < reqall.usedProjects.length; i++)
      pick = Model.findProject(reqall.projects, reqall.usedProjects[i])
    if (pick) setFormProject(pick)
  }

  function setFormProject(project) {
    formProject = project ? { id: project.id, name: project.name } : null
    projectQuery = ""
    projectField.text = formProject ? formProject.name : ""
  }

  function focusForm() {
    if (!signedIn) return
    cursorActive = false
    projectField.forceActiveFocus()
  }

  function leaveForm() {
    keyCatcher.forceActiveFocus()
  }

  function movePicker(delta) {
    pickerIndex = clamp(pickerIndex + delta, 0, Math.max(0, pickerRows.length - 1))
  }

  function pickProject(row) {
    if (!row) return
    setFormProject(row)
    titleField.forceActiveFocus()
  }

  function submitForm() {
    if (reqall.saving) return
    if (!formProject) { formError = true; formStatus = "Pick a project first"; projectField.forceActiveFocus(); return }
    if (titleField.text.trim() === "") { formError = true; formStatus = "Give it a title"; titleField.forceActiveFocus(); return }
    formError = false
    formStatus = "Saving…"
    reqall.remember(formProject, titleField.text, bodyArea.text, formKind)
  }

  // Tab / Shift+Tab / Ctrl+Enter / Esc, shared by every form field. Returns
  // true when it handled the key.
  function formKey(event, field) {
    var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
    if (enter && (event.modifiers & Qt.ControlModifier)) { submitForm(); return true }
    if (event.key === Qt.Key_Escape) { leaveForm(); return true }
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      var order = [projectField, titleField, bodyArea, kindRow]
      var back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)
      var i = order.indexOf(field)
      order[(i + (back ? order.length - 1 : 1)) % order.length].forceActiveFocus()
      return true
    }
    return false
  }

  function stepKind(delta) {
    var kinds = Model.REMEMBER_KINDS
    var i = kinds.indexOf(formKind)
    formKind = kinds[clamp(i + delta, 0, kinds.length - 1)]
  }

  Connections {
    target: reqall
    function onSaved(result) {
      if (result.ok) {
        root.formError = false
        root.formStatus = "Remembered #" + result.id + (result.kind ? " (" + result.kind + ")" : "") + " in " + result.project
        titleField.text = ""
        bodyArea.text = ""
        if (root.opened && root.formFocused) titleField.forceActiveFocus()
      } else {
        root.formError = true
        root.formStatus = result.message || "Could not save"
      }
    }
    function onProjectsDocChanged() { root.preselectProject() }
    function onSignedInChanged() { if (reqall.signedIn && root.opened) reqall.loadProjects(false) }
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

  // Signed in, the panel opens straight into the project search.
  readonly property Item openFocusItem: signedIn ? projectField : keyCatcher

  onOpenedChanged: if (opened) {
    cursorActive = false
    focusSection = "actions"
    actionIndex = 0
    recentIndex = 0
    nowMs = Date.now()
    formStatus = ""
    formError = false
    if (panelFlick) panelFlick.contentY = 0
    if (Date.now() - reqall.fetchedAtMs > 60000) reqall.refresh()
    if (signedIn) reqall.loadProjects(false)
    Qt.callLater(function() { root.openFocusItem.forceActiveFocus() })
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
    focusTarget: root.openFocusItem
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.formFocused

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
        else if (t === "a" || t === "A" || t === "/") root.focusForm()
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

          // ---------- Remember ----------
          PanelSeparator {
            visible: rememberSection.visible
            foreground: root.foreground
          }

          Column {
            id: rememberSection
            visible: root.signedIn
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "REMEMBER"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            TextField {
              id: projectField
              width: parent.width
              placeholderText: reqall.projectsLoading && reqall.projects.length === 0 ? "Loading projects…" : "Project: type to search"
              foreground: root.foreground
              font.family: root.fontFamily

              onActiveFocusChanged: {
                if (activeFocus) {
                  root.projectQuery = ""
                  root.pickerIndex = 0
                  selectAll()
                } else {
                  // Leaving without a pick puts the chosen project back.
                  root.projectQuery = ""
                  text = root.formProject ? root.formProject.name : ""
                }
              }
              onTextEdited: {
                root.projectQuery = text
                root.pickerIndex = 0
              }

              Keys.onPressed: function(event) {
                var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                var ctrl = event.modifiers & Qt.ControlModifier
                if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N))) {
                  root.movePicker(1); event.accepted = true
                } else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P))) {
                  root.movePicker(-1); event.accepted = true
                } else if ((enter && !ctrl) || (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier) && root.projectQuery !== "")) {
                  if (root.pickerRows.length > 0) root.pickProject(root.pickerRows[root.pickerIndex])
                  else if (root.formProject && root.projectQuery === "") titleField.forceActiveFocus()
                  event.accepted = true
                } else if (root.formKey(event, projectField)) {
                  event.accepted = true
                }
              }
            }

            // Fuzzy matches while the project field has focus.
            Column {
              visible: root.pickerOpen
              width: parent.width
              spacing: 0

              Text {
                visible: root.pickerRows.length === 0
                width: parent.width
                text: reqall.projectsMessage !== "" ? reqall.projectsMessage
                  : reqall.projectsLoading ? "Loading projects…"
                  : "No project matches \u201C" + root.projectQuery + "\u201D"
                color: reqall.projectsMessage !== "" ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                leftPadding: Style.space(8)
              }

              Repeater {
                model: root.pickerRows

                Rectangle {
                  id: pickRow
                  required property var modelData
                  required property int index
                  readonly property bool current: index === root.pickerIndex
                  width: parent.width
                  height: pickColumn.implicitHeight + Style.space(8)
                  radius: Style.cornerRadius
                  color: current ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"

                  Column {
                    id: pickColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(1)

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: pickRow.modelData.name
                      color: pickRow.current ? Style.hoverStateColor(root.foreground, Color.accent) : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideMiddle
                    }
                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: Model.projectDetail(pickRow.modelData, root.nowMs)
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: root.pickerIndex = pickRow.index
                    onClicked: root.pickProject(pickRow.modelData)
                  }
                }
              }
            }

            TextField {
              id: titleField
              width: parent.width
              placeholderText: "Title"
              maximumLength: 500
              foreground: root.foreground
              font.family: root.fontFamily

              Keys.onPressed: function(event) {
                var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                if (enter && !(event.modifiers & Qt.ControlModifier)) {
                  bodyArea.forceActiveFocus(); event.accepted = true
                } else if (root.formKey(event, titleField)) {
                  event.accepted = true
                }
              }
            }

            // Multi-line body: grows with its text up to about eight lines,
            // then scrolls. Styled to match the kit's TextField.
            Item {
              id: bodyBox
              width: parent.width
              height: Math.max(Style.space(64), Math.min(bodyArea.implicitHeight, Style.space(150)))

              readonly property bool hot: bodyHover.hovered
              readonly property var borderSpec: Border.controlSpec(bodyArea.activeFocus ? "focus" : (hot ? "hover-cursor" : "normal"), root.foreground, Color.accent)

              HoverHandler { id: bodyHover }

              BorderSurface {
                anchors.fill: parent
                color: Style.controlFill(bodyArea.activeFocus, bodyBox.hot, root.foreground, Color.accent)
                borderSpec: bodyBox.borderSpec
                radius: Style.cornerRadius
              }

              ScrollView {
                id: bodyScroll
                anchors.fill: parent
                anchors.leftMargin: Border.left(bodyBox.borderSpec)
                anchors.rightMargin: Border.right(bodyBox.borderSpec)
                anchors.topMargin: Border.top(bodyBox.borderSpec)
                anchors.bottomMargin: Border.bottom(bodyBox.borderSpec)
                clip: true

                TextArea {
                  id: bodyArea
                  placeholderText: "Body (optional)"
                  wrapMode: TextEdit.Wrap
                  color: root.foreground
                  placeholderTextColor: Qt.darker(root.foreground, 1.6)
                  selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
                  selectedTextColor: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  leftPadding: Style.spacing.controlPaddingX
                  rightPadding: Style.spacing.controlPaddingX
                  topPadding: Style.spacing.inputPaddingY
                  bottomPadding: Style.spacing.inputPaddingY
                  background: null

                  Keys.onPressed: function(event) {
                    if (root.formKey(event, bodyArea)) event.accepted = true
                  }
                }
              }
            }

            // Kind: auto lets Reqall classify the record. With the row
            // focused, h/l or the arrows step through kinds and Enter saves.
            Flow {
              id: kindRow
              width: parent.width
              spacing: Style.space(3)

              Keys.onPressed: function(event) {
                var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                if (event.key === Qt.Key_Left || event.text === "h") { root.stepKind(-1); event.accepted = true }
                else if (event.key === Qt.Key_Right || event.text === "l") { root.stepKind(1); event.accepted = true }
                else if (enter || event.key === Qt.Key_Space) { root.submitForm(); event.accepted = true }
                else if (root.formKey(event, kindRow)) event.accepted = true
              }

              Repeater {
                model: Model.REMEMBER_KINDS

                Button {
                  required property string modelData
                  text: modelData
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  horizontalPadding: Style.space(5)
                  verticalPadding: Style.space(3)
                  bordered: true
                  selected: root.formKind === modelData
                  hasCursor: kindRow.activeFocus && root.formKind === modelData
                  onClicked: root.formKind = modelData
                }
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Button {
                text: reqall.saving ? "Saving…" : "Remember"
                iconText: "\u{F0193}"                                    // nf-md-content_save
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                iconSpinning: false
                opacity: root.canRemember ? 1.0 : 0.5
                onClicked: root.submitForm()
              }

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: root.formStatus
                color: root.formError ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
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
              if (root.formFocused) {
                parts.push("tab next", "ctrl+enter remember", "esc browse")
                return parts.join(" · ")
              }
              parts.push("r refresh")
              if (root.signedIn) parts.push("o open", "a remember")
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
