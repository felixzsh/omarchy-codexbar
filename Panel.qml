import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "local.codexbar"
  ipcTarget: "local.codexbar"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Countdowns and "updated" read this instead of Date.now() so the panel
  // keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  readonly property var providers: usage.validProviders
  readonly property bool alarming: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].headlinePercent >= 0.9) return true
    return false
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function refreshNow() { usage.refresh(true) }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatNumber(n) {
    if (n === undefined || n === null) return "—"
    if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
    if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
    if (Math.round(n) === n) return String(n)
    return n.toFixed(2)
  }

  function providerInitials(name) {
    var words = String(name || "").split(/\s+/).filter(function(w) { return w !== "" })
    var out = ""
    for (var i = 0; i < words.length && out.length < 2; i++) out += words[i].charAt(0)
    return out === "" ? "?" : out.toUpperCase()
  }

  function providerMeta(p) {
    var parts = []
    if (String(p.source || "") !== "") parts.push(String(p.source).toUpperCase())
    if (String(p.plan || "") !== "") parts.push(String(p.plan))
    if (String(p.account || "") !== "") parts.push(String(p.account))
    return parts.join(" · ")
  }

  function creditsLine(p) {
    if (p.creditsRemaining === null && p.creditsTotal === null) return ""
    if (p.creditsRemaining !== null && p.creditsTotal !== null)
      return "Credits " + root.formatNumber(p.creditsRemaining) + " of " + root.formatNumber(p.creditsTotal)
    if (p.creditsRemaining !== null) return "Credits " + root.formatNumber(p.creditsRemaining)
    return "Credits " + root.formatNumber(p.creditsTotal) + " total"
  }

  function updatedText() {
    if (usage.serverVersion !== "" && usage.serverOnline)
      return "CodexBar " + usage.serverVersion + " · updated " + root.timeAgo(usage.lastRefreshedAtMs)
    return "updated " + root.timeAgo(usage.lastRefreshedAtMs)
  }

  function timeAgo(ms) {
    if (!(ms > 0)) return "—"
    var elapsed = Math.floor((root.nowMs - ms) / 1000)
    if (elapsed < 60) return "now"
    return root.formatDuration(elapsed * 1000) + " ago"
  }

  function barTooltip() {
    var lines = []
    for (var i = 0; i < providers.length; i++) {
      var p = providers[i]
      var label = p.providerName
      if (p.headlinePercent >= 0) label += " · " + Math.round(p.headlinePercent * 100) + "%"
      lines.push(label)
    }
    if (lines.length === 0) return "CodexBar — no provider usage"
    return lines.join("\n")
  }

  // An icon that reports even when the server is up but nothing has data yet:
  // opening the panel explains why instead of leaving the slot empty.
  visible: usage.serverOnline || providers.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    usage.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Main {
    id: usage
    settings: root.settings
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
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
    function refresh(): string { root.refreshNow(); return "ok" }
    function status(): string { return JSON.stringify(usage.statusSnapshot()) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf0e4"
    active: root.alarming
    tooltipText: root.barTooltip()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refreshNow()
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refreshNow() }

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

          PanelHero {
            visible: root.providers.length > 0
            width: parent.width
            title: root.providers.length + " provider" + (root.providers.length === 1 ? "" : "s")
            meta: root.updatedText()
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Item {
                width: Style.font.display
                height: Style.font.display
              }
            }
          }

          // ---------- Provider cards ----------
          Repeater {
            model: root.providers
            ProviderCard {
              required property var modelData
              width: parent.width
              provider: modelData
            }
          }

          // ---------- Empty / offline state ----------
          Text {
            visible: root.providers.length === 0
            width: parent.width
            topPadding: Style.space(24)
            text: root.emptyText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  function emptyText() {
    if (usage.usageStatusText !== "") return usage.usageStatusText + "\n\nStart it with `codexbar serve` and enable providers in CodexBar settings."
    return "No provider usage from CodexBar yet.\nEnable a provider in CodexBar and wait for the next refresh."
  }

  // A provider card: hero, usage windows, credits, and any status note.
  component ProviderCard: Column {
    id: card
    property var provider: null

    readonly property bool alarming: provider && provider.headlinePercent >= 0.9
    readonly property var windows: provider ? (provider.windows || []) : []

    spacing: Style.space(12)

    BorderSurface {
      width: parent.width
      implicitHeight: inner.implicitHeight + Style.space(14) * 2
      color: root.alpha(root.foreground, card.alarming ? 0.10 : 0.04)
      borderSpec: card.alarming
        ? Border.flat(root.alpha(root.urgent, 0.45), 1)
        : Border.flat(root.alpha(root.foreground, 0.12), 1)
      radius: Style.cornerRadius

      Column {
        id: inner
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(14)
        spacing: Style.space(10)
        width: parent.width

        PanelHero {
          width: parent.width
          title: card.provider ? card.provider.providerName : ""
          meta: card.provider ? root.providerMeta(card.provider) : ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconSize: Style.font.display

          iconComponent: Component {
            Rectangle {
              width: Style.font.display
              height: Style.font.display
              radius: Style.cornerRadius
              color: root.alpha(root.foreground, 0.12)
              border.width: 0

              Text {
                anchors.centerIn: parent
                text: root.providerInitials(card.provider ? card.provider.providerName : "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }
        }

        Repeater {
          model: card.windows
          UsageRow {
            required property var modelData
            width: parent.width
            window: modelData
          }
        }

        Text {
          visible: root.creditsLine(card.provider) !== ""
          width: parent.width
          text: root.creditsLine(card.provider)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        BorderSurface {
          visible: card.provider && (String(card.provider.statusText || "") !== "" || String(card.provider.error || "") !== "")
          width: parent.width
          implicitHeight: noteText.implicitHeight + Style.space(10) * 2
          color: root.alpha(root.urgent, 0.10)
          borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
          radius: Style.cornerRadius

          Text {
            id: noteText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            text: card.provider && card.provider.error !== "" ? card.provider.error : (card.provider ? card.provider.statusText : "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  // One limit window: label and percentage, meter, and reset countdown.
  component UsageRow: Column {
    id: usageRow
    property var window: null

    readonly property bool alarming: window && window.percent >= 0.9

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

      Text {
        id: labelText
        text: usageRow.window ? usageRow.window.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: valueText
        text: usageRow.window && usageRow.window.percent >= 0
          ? Math.round(usageRow.window.percent * 100) + "%"
          : "—"
        color: usageRow.alarming ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: usageRow.window ? usageRow.window.percent : -1
      alarming: usageRow.alarming
    }

    Text {
      width: parent.width
      text: {
        var remainingMs = root.resetMsFor(usageRow.window)
        return remainingMs > 0 ? "Resets in " + root.formatDuration(remainingMs) : ""
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Rounded track showing the percentage of the allowance used.
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }
  }
}
