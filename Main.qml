import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The data side of the Reqall widget. It runs bin/reqall-widget-fetch on a
// timer and on demand, and exposes the parsed result. The Remember form's
// project list (bin/reqall-widget-projects) and saves
// (bin/reqall-widget-remember) run through here too. Panel.qml only reads
// from here and calls in; nothing in this file draws.
Item {
  id: root
  visible: false

  property var settings: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  function binPath(name) {
    return String(Qt.resolvedUrl("bin/" + name)).replace(/^file:\/\//, "")
  }

  readonly property string scriptPath: binPath("reqall-widget-fetch")

  // Parsed fetch document. `auth` is one of ok, none, invalid, paused, error;
  // `loading` covers the moment before the first run completes.
  property var data: null
  property bool loading: false
  property double fetchedAtMs: 0
  property int revision: 0

  readonly property string auth: data ? String(data.auth || "error") : "loading"
  readonly property bool signedIn: auth === "ok"
  readonly property var recent: data && Array.isArray(data.recent) ? data.recent : []
  readonly property var counts: data && data.counts ? data.counts : null
  readonly property string url: data && data.url ? String(data.url) : "https://www.reqall.net"
  readonly property string message: data ? String(data.message || "") : ""
  readonly property string source: data ? String(data.source || "") : ""
  readonly property bool hasCli: !!(data && data.cli === true)

  readonly property int refreshIntervalSec: Math.max(60, Number(setting("refreshIntervalSec", 300)) || 300)
  readonly property int recentCount: Math.max(1, Math.min(30, Number(setting("recentCount", 6)) || 6))

  // A settings change (new key, new project filter) should show up without
  // waiting out the interval.
  onSettingsChanged: Qt.callLater(refresh)

  function refresh() {
    if (fetchProcess.running) {
      refreshQueued = true
      return
    }
    loading = true
    fetchProcess.environment = Object.assign(credentialEnv(), {
      REQALL_WIDGET_PROJECT: String(setting("project", "")),
      REQALL_WIDGET_RECENT: String(recentCount)
    })
    fetchProcess.running = true
  }

  function credentialEnv() {
    return {
      REQALL_WIDGET_API_KEY: String(setting("apiKey", "")),
      REQALL_WIDGET_URL: String(setting("serverUrl", ""))
    }
  }

  property bool refreshQueued: false

  Process {
    id: fetchProcess
    running: false
    command: ["bash", root.scriptPath]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyFetch(text)
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg) console.warn("reqall.memory: " + msg)
      }
    }

    onExited: {
      root.loading = false
      if (root.refreshQueued) {
        root.refreshQueued = false
        Qt.callLater(root.refresh)
      }
    }
  }

  function applyFetch(text) {
    data = Model.parseFetch(text)
    fetchedAtMs = Date.now()
    revision++
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // ------------------------------------------------------------- Remember

  // The project picker's list. Loaded when the panel opens rather than on the
  // refresh timer: it is a few hundred rows and changes rarely.
  property var projectsDoc: null
  property bool projectsLoading: false
  property double projectsFetchedAtMs: 0
  readonly property var projects: projectsDoc && projectsDoc.auth === "ok" ? projectsDoc.projects : []
  readonly property var usedProjects: projectsDoc ? projectsDoc.used : []
  readonly property string projectsMessage: projectsDoc && projectsDoc.auth !== "ok" ? String(projectsDoc.message || "Could not load projects") : ""

  // A project list belongs to the credentials that fetched it. Another key,
  // server, or key source can be another account, so a change drops the
  // cached list (and with it the form's selection) instead of letting it
  // live out its ten minutes.
  readonly property string credentialKey: JSON.stringify([
    String(setting("apiKey", "")), String(setting("serverUrl", "")), url, source])
  property string projectsCredentialKey: ""
  property string loadingCredentialKey: ""

  onCredentialKeyChanged: if (projectsDoc && projectsCredentialKey !== credentialKey) projectsDoc = null

  function loadProjects(force) {
    if (projectsProcess.running) return
    var fresh = projectsDoc && projectsDoc.auth === "ok" && projectsCredentialKey === credentialKey
      && Date.now() - projectsFetchedAtMs < 10 * 60 * 1000
    if (fresh && !force) return
    projectsLoading = true
    loadingCredentialKey = credentialKey
    projectsProcess.environment = credentialEnv()
    projectsProcess.running = true
  }

  Process {
    id: projectsProcess
    running: false
    command: ["bash", root.binPath("reqall-widget-projects")]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.projectsCredentialKey = root.loadingCredentialKey
        root.projectsFetchedAtMs = Date.now()
        root.projectsDoc = Model.parseProjects(text)
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg) console.warn("reqall.memory: " + msg)
      }
    }

    onExited: root.projectsLoading = false
  }

  // One save at a time. `saved` carries the parsed result of
  // bin/reqall-widget-remember: { ok, id, kind, title, project } or
  // { ok: false, auth, message }.
  property bool saving: false
  signal saved(var result)

  function remember(project, title, body, kind) {
    if (saving || !project) return false
    saving = true
    rememberProcess.environment = Object.assign(credentialEnv(), {
      REQALL_WIDGET_REMEMBER_PROJECT_ID: String(project.id),
      REQALL_WIDGET_REMEMBER_PROJECT: String(project.name),
      REQALL_WIDGET_REMEMBER_TITLE: String(title || ""),
      REQALL_WIDGET_REMEMBER_BODY: String(body || ""),
      REQALL_WIDGET_REMEMBER_KIND: kind === "auto" ? "" : String(kind || "")
    })
    rememberProcess.running = true
    return true
  }

  function noteUsed(name) {
    if (!projectsDoc) return
    var used = [name].concat(usedProjects.filter(function(n) { return n !== name })).slice(0, 10)
    projectsDoc = Object.assign({}, projectsDoc, { used: used })
  }

  Process {
    id: rememberProcess
    running: false
    command: ["bash", root.binPath("reqall-widget-remember")]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = Model.parseRemember(text)
        root.saving = false
        if (result.ok) {
          root.noteUsed(result.project)
          root.refresh()
        }
        root.saved(result)
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg) console.warn("reqall.memory: " + msg)
      }
    }

    onExited: root.saving = false
  }
}
