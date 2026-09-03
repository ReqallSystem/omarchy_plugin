import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The data side of the Reqall widget. It runs bin/reqall-widget-fetch on a
// timer and on demand, and exposes the parsed result. Panel.qml only reads
// from here; nothing in this file draws.
Item {
  id: root
  visible: false

  property var settings: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  readonly property string scriptPath: String(Qt.resolvedUrl("bin/reqall-widget-fetch")).replace(/^file:\/\//, "")

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
    fetchProcess.environment = {
      REQALL_WIDGET_API_KEY: String(setting("apiKey", "")),
      REQALL_WIDGET_URL: String(setting("serverUrl", "")),
      REQALL_WIDGET_PROJECT: String(setting("project", "")),
      REQALL_WIDGET_RECENT: String(recentCount)
    }
    fetchProcess.running = true
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
}
