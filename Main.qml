import QtQuick
import Quickshell
import Quickshell.Io
import "providers/codexbar-model.js" as Cbx

// Talks to `codexbar serve` and turns its per-provider payloads into the
// normalized records the panel renders. All usage computation is delegated to
// CodexBar; this file only polls, parses, and filters.
Item {
  id: root
  visible: false

  property var settings: ({})

  property string serverUrl: String(setting("codexbarUrl", "http://127.0.0.1:8080")).trim()
  property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 120)))

  property bool refreshing: false
  property bool serverOnline: false
  property string serverVersion: ""
  property string usageStatusText: ""
  property string lastError: ""
  property double lastRefreshedAtMs: 0

  // Every provider CodexBar returned (valid ones first, errors trailing) and
  // the strict subset the panel shows.
  property var allProviders: []
  property var validProviders: []
  property int revision: 0

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  function fetchJson(url, onDone) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", url, true)
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      var ok = xhr.status >= 200 && xhr.status < 300
      var data = null
      var raw = xhr.responseText || ""
      if (ok && raw !== "") {
        try { data = JSON.parse(raw) } catch (e) { data = null }
      }
      onDone(ok, data, xhr.status, raw)
    }
    xhr.send()
  }

  function refresh(force) {
    if (root.refreshing) return
    root.refreshing = true
    var base = []
    var costMap = {}
    var usageLoaded = false
    var costLoaded = false

    function finish() {
      if (!usageLoaded || !costLoaded) return
      // Attach the per-day token history CodexBar reports (codex/claude local
      // logs) to the matching provider; everyone else keeps an empty chart.
      for (var i = 0; i < base.length; i++) {
        var cost = costMap[base[i].providerId]
        if (cost) {
          base[i].recentDays = cost.recentDays
          base[i].dailyUpdatedAt = cost.updatedAt
        }
      }
      root.refreshing = false
      root.lastRefreshedAtMs = Date.now()
      root.allProviders = base
      root.validProviders = Cbx.filterValid(base)
      root.revision++
    }

    root.fetchJson(root.serverUrl + "/usage?provider=all", function(ok, data, status) {
      usageLoaded = true
      if (!ok) {
        root.serverOnline = false
        root.serverVersion = ""
        root.lastError = status === 0
          ? "CodexBar server not reachable at " + root.serverUrl + ". Run `codexbar serve`."
          : "CodexBar server returned HTTP " + status + "."
        root.usageStatusText = root.lastError
      } else {
        root.serverOnline = true
        root.lastError = ""
        root.usageStatusText = ""
        base = Cbx.normalizeProviders(data || [])
      }
      finish()
    })

    root.fetchJson(root.serverUrl + "/cost?provider=all", function(ok, data) {
      costLoaded = true
      if (ok && Array.isArray(data)) {
        for (var i = 0; i < data.length; i++) {
          var rec = data[i]
          if (!rec || !rec.provider || rec.error) continue
          costMap[String(rec.provider)] = Cbx.normalizeCost(rec)
        }
      }
      finish()
    })

    // Best-effort version badge; a failure here never masks a good usage read.
    root.fetchJson(root.serverUrl + "/health", function(ok, health) {
      if (ok && health && health.version) root.serverVersion = String(health.version)
    })
  }

  function refreshAll(force) { refresh(force) }
  function refreshLimits() { refresh() }

  function formatTokenCount(n) {
    if (n === undefined || n === null) return "0"
    if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
    if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
    return String(n)
  }

  // JSON snapshot for `omarchy-shell local.codexbar status`.
  function statusSnapshot() {
    var providers = []
    for (var i = 0; i < root.validProviders.length; i++) {
      var p = root.validProviders[i]
      providers.push({
        provider: p.providerId,
        name: p.providerName,
        source: p.source,
        headlinePercent: p.headlinePercent,
        creditsRemaining: p.creditsRemaining,
        windows: p.windows
      })
    }
    return {
      module: "local.codexbar",
      serverUrl: root.serverUrl,
      serverOnline: root.serverOnline,
      serverVersion: root.serverVersion,
      refreshing: root.refreshing,
      updatedAt: new Date(root.lastRefreshedAtMs).toISOString(),
      providers: providers,
      usageStatusText: root.usageStatusText
    }
  }
}
