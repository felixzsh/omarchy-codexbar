import QtQuick
import Quickshell
import Quickshell.Io
import "codexbar.js" as Cbx

// Talks to the codexbar CLI directly (no `codexbar serve` daemon needed) and
// turns its per-provider payloads into the normalized records the panel
// renders. Usage is polled on a background timer so the bar icon stays fresh;
// cost history (the heavier local scan) is fetched when the panel opens.
Item {
  id: root
  visible: false

  property var settings: ({})

  property string codexbarBin: {
    var v = String(setting("codexbarBin", "codexbar")).trim()
    return v === "" ? "codexbar" : v
  }
  property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 120)))

  property bool refreshing: false
  property bool costRefreshing: false
  property string codexbarVersion: ""
  property string usageStatusText: ""
  property string lastError: ""
  property double lastRefreshedAtMs: 0
  property double lastCostRefreshedAtMs: 0

  // Watchdog bookkeeping: the codexbar CLI has been observed to hang on some
  // web fetches regardless of --web-timeout, so every spawned run is killed
  // after a hard deadline instead of blocking the poll loop forever.
  property int _usageTimeoutMs: 30000
  property int _costTimeoutMs: 60000
  property double _usageSpawnedAtMs: 0
  property double _costSpawnedAtMs: 0
  property bool _usageTimedOut: false
  property bool _costTimedOut: false
  property bool _usageExitHandled: false

  // Every provider CodexBar returned (valid ones first, errors trailing) and
  // the strict subset the panel shows.
  property var allProviders: []
  property var validProviders: []
  property var _costMap: ({})
  property bool _usageHandled: false
  property bool _costHandled: false
  property int revision: 0

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  Timer {
    id: usageTimer
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Force-kills a wedged codexbar process so refresh() can never be blocked
  // forever by a run that refuses to finish.
  Timer {
    id: watchdogTimer
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.checkWatchdog()
  }

  // After a watchdog kill, retry once shortly after so the panel recovers
  // without waiting for the next poll interval.
  Timer {
    id: usageRetryTimer
    interval: 3000
    running: false
    repeat: false
    onTriggered: root.refresh()
  }

  function checkWatchdog() {
    if (usageProc.running && root._usageSpawnedAtMs > 0
        && Date.now() - root._usageSpawnedAtMs > root._usageTimeoutMs) {
      root._usageTimedOut = true
      usageProc.signal(9)
    }
    if (costProc.running && root._costSpawnedAtMs > 0
        && Date.now() - root._costSpawnedAtMs > root._costTimeoutMs) {
      root._costTimedOut = true
      costProc.signal(9)
    }
  }

  // ---------------------------------------------------------------- usage

  Process {
    id: usageProc
    running: false
    onExited: root.onUsageExited(exitCode)
    onRunningChanged: root.onUsageRunningChanged()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onUsageOutput(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: function(text) {
        var t = String(text || "").trim()
        if (t !== "") console.warn("codexbar/usage", t)
      }
    }
  }

  function usageCommand() {
    return [root.codexbarBin, "usage", "--format", "json", "--web-timeout", "15"]
  }

  function refresh(force) {
    if (usageProc.running) {
      // A wedged process would freeze the whole poll loop; kill it so the
      // exit handler can clear state and a retry can start a fresh run.
      if (root._usageSpawnedAtMs > 0 && Date.now() - root._usageSpawnedAtMs > root._usageTimeoutMs) {
        root._usageTimedOut = true
        usageProc.signal(9)
      }
      return
    }
    root._usageHandled = false
    root._usageTimedOut = false
    root.refreshing = true
    root._usageSpawnedAtMs = Date.now()
    usageProc.command = root.usageCommand()
    usageProc.running = true
  }

  function refreshAll(force) { refresh(force) }
  function refreshLimits() { refresh() }

  // Fetch usage now and restart the background countdown (used on panel open).
  function pollNow() {
    root.refresh()
    usageTimer.restart()
  }

  function onUsageOutput(text) {
    root._usageHandled = true
    root._usageTimedOut = false
    root._usageSpawnedAtMs = 0
    root.refreshing = false
    var data = root.parseJsonOutput(text)
    if (data === null) {
      root.lastError = "CodexBar returned no parseable usage. Run `" + root.codexbarBin + " usage --format json` to check."
      root.usageStatusText = root.lastError
      root.allProviders = []
      root.validProviders = []
      root.revision++
      return
    }
    root.lastError = ""
    root.usageStatusText = ""
    root.lastRefreshedAtMs = Date.now()
    root.allProviders = Cbx.normalizeProviders(data)
    root.mergeCost()
    root.revision++
  }

  // Quickshell's Process only surfaces a failed-to-start through runningChanged
  // (no error signal and no `exited`): the run stops without output or exit,
  // so onUsageRunningChanged reports it. A normal exit is handled by
  // onUsageExited first, which sets _usageExitHandled to swallow the pair.
  function onUsageRunningChanged() {
    if (usageProc.running) return
    if (root._usageHandled) return
    if (root._usageExitHandled) {
      root._usageExitHandled = false
      return
    }
    root.refreshing = false
    root._usageSpawnedAtMs = 0
    root.allProviders = []
    root.validProviders = []
    root.lastError = "CodexBar failed to start. Is `" + root.codexbarBin + "` on PATH?"
    root.usageStatusText = root.lastError
    root.revision++
  }

  function onUsageExited(exitCode) {
    if (root._usageHandled) return
    root._usageExitHandled = true
    root.refreshing = false
    root._usageSpawnedAtMs = 0
    if (root._usageTimedOut) {
      root._usageTimedOut = false
      root.usageStatusText = "CodexBar usage timed out and was killed after "
        + Math.round(root._usageTimeoutMs / 1000) + "s. Retrying in a moment."
      root.revision++
      usageRetryTimer.start()
      return
    }
    root.allProviders = []
    root.validProviders = []
    root.lastError = "CodexBar failed to run (exit " + exitCode + "). Is `" + root.codexbarBin + "` on PATH?"
    root.usageStatusText = root.lastError
    root.revision++
  }

  // ---------------------------------------------------------------- cost

  Process {
    id: costProc
    running: false
    onExited: root.onCostExited(exitCode)
    onRunningChanged: root.onCostRunningChanged()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onCostOutput(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: function(text) {
        var t = String(text || "").trim()
        if (t !== "") console.warn("codexbar/cost", t)
      }
    }
  }

  function refreshCost() {
    if (costProc.running) {
      if (root._costSpawnedAtMs > 0 && Date.now() - root._costSpawnedAtMs > root._costTimeoutMs) {
        root._costTimedOut = true
        costProc.signal(9)
      }
      return
    }
    root._costHandled = false
    root._costTimedOut = false
    root.costRefreshing = true
    root._costSpawnedAtMs = Date.now()
    costProc.command = [root.codexbarBin, "cost", "--format", "json"]
    costProc.running = true
  }

  function onCostOutput(text) {
    root._costHandled = true
    root._costTimedOut = false
    root._costSpawnedAtMs = 0
    root.costRefreshing = false
    root.lastCostRefreshedAtMs = Date.now()
    var data = root.parseJsonOutput(text)
    var map = {}
    if (Array.isArray(data)) {
      for (var i = 0; i < data.length; i++) {
        var rec = data[i]
        if (!rec || !rec.provider || rec.error) continue
        map[String(rec.provider)] = Cbx.normalizeCost(rec)
      }
    }
    root._costMap = map
    root.mergeCost()
  }

  function onCostRunningChanged() {
    if (costProc.running) return
    if (root._costHandled) return
    root.costRefreshing = false
    root._costSpawnedAtMs = 0
    root._costTimedOut = false
  }

  function onCostExited(exitCode) {
    if (root._costHandled) return
    root.costRefreshing = false
    root._costSpawnedAtMs = 0
    root._costTimedOut = false
  }

  // Re-apply the latest daily token history onto the current provider records.
  function mergeCost() {
    for (var i = 0; i < root.allProviders.length; i++) {
      var cost = root._costMap[root.allProviders[i].providerId]
      if (cost) {
        root.allProviders[i].recentDays = cost.recentDays
        root.allProviders[i].dailyUpdatedAt = cost.updatedAt
      }
    }
    root.validProviders = Cbx.filterValid(root.allProviders)
  }

  // ---------------------------------------------------------------- misc

  Process {
    id: versionProc
    command: [root.codexbarBin, "--version"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function(text) {
        var v = String(text || "").trim().split("\n")[0]
        if (v !== "") root.codexbarVersion = v
      }
    }
  }

  // Grab the version once, a beat after the component tree is settled.
  Timer {
    interval: 1000
    running: true
    repeat: false
    onTriggered: versionProc.running = true
  }

  function parseJsonOutput(text) {
    var raw = String(text || "").trim()
    if (raw === "") return null
    try { return JSON.parse(raw) } catch (e) {}
    var lines = raw.split("\n")
    for (var i = lines.length - 1; i >= 0; i--) {
      var line = lines[i].trim()
      if (line === "") continue
      try { return JSON.parse(line) } catch (e2) {}
    }
    return null
  }

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
        windows: p.windows,
        hasDailyTokens: p.recentDays && p.recentDays.length > 0
      })
    }
    return {
      module: "local.codexbar",
      codexbarBin: root.codexbarBin,
      codexbarVersion: root.codexbarVersion,
      refreshing: root.refreshing,
      costRefreshing: root.costRefreshing,
      updatedAt: new Date(root.lastRefreshedAtMs).toISOString(),
      providers: providers,
      usageStatusText: root.usageStatusText
    }
  }
}
