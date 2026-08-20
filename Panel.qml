import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "components"

// CodexBar widget: one bar icon and one panel that mirrors the native Model
// Usage widget's look. Usage, limits, credits, and resets are read straight
// from `codexbar serve`; nothing here is recomputed or guessed.
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
  // Selection follows the provider id, not the slot: a scan that lands while
  // the panel is open swaps data under a stable selection.
  property string selectedProviderId: ""
  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) return i
    return 0
  }
  readonly property var provider: providers.length > 0 ? providers[providerIndex] : null

  // The hero dropdown owns the keys while its popup is open; the panel's
  // keyCatcher stands down so j/k and Enter drive the option list, not the
  // panel cursor.
  property bool providerDropdownOpen: false

  readonly property var providerOptions: {
    var out = []
    for (var i = 0; i < providers.length; i++)
      out.push({ value: providers[i].providerId, label: providers[i].providerName })
    return out
  }
  readonly property var limits: limitWindows(provider)
  readonly property var days: provider && provider.recentDays ? provider.recentDays : []
  readonly property bool hasDays: days.length > 0
  readonly property bool alarming: !!provider && provider.headlinePercent >= 0.9

  // The provider picker shrinks to the widest option label so the hero's meta
  // subtext stays visible; the chevron and paddings add a fixed allowance.
  readonly property real providerDropdownWidth: {
    var w = 0
    for (var i = 0; i < providerOptions.length; i++) {
      providerLabelMetrics.text = providerOptions[i].label
      if (providerLabelMetrics.width > w) w = providerLabelMetrics.width
    }
    return Math.max(Style.space(96), Math.min(Style.space(180), w + Style.space(40)))
  }

  TextMetrics {
    id: providerLabelMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    text: ""
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  onProvidersChanged: {
    var found = false
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) { found = true; break }
    if (!found && providers.length > 0) selectedProviderId = providers[0].providerId
    else if (providers.length === 0) selectedProviderId = ""
  }

  function selectProviderId(id) {
    selectedProviderId = id
    if (panelFlick) panelFlick.contentY = 0
    nowMs = Date.now()
  }

  function refreshNow() { usage.refresh(true) }

  // ---------------------------------------------------------------- limits

  function limitWindow(window) {
    if (!window) return null
    return {
      title: window.title,
      percent: Number(window.percent),
      resetAt: String(window.resetAt || "")
    }
  }

  function limitWindows(p) {
    if (!p || !p.windows) return []
    var out = []
    for (var i = 0; i < p.windows.length; i++) {
      var w = limitWindow(p.windows[i])
      if (w) out.push(w)
    }
    return out
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  // ---------------------------------------------------------------- content

  function providerMeta(p) {
    if (!p) return ""
    var parts = []
    if (String(p.source || "") !== "") parts.push(String(p.source).toUpperCase())
    if (String(p.plan || "") !== "") parts.push(String(p.plan))
    if (String(p.account || "") !== "") parts.push(String(p.account))
    return parts.join(" · ")
  }

  function creditsLine(p) {
    if (!p) return ""
    if (p.creditsRemaining === null && p.creditsTotal === null) return ""
    if (p.creditsRemaining !== null && p.creditsTotal !== null)
      return "Credits " + root.formatNumber(p.creditsRemaining) + " of " + root.formatNumber(p.creditsTotal)
    if (p.creditsRemaining !== null) return "Credits " + root.formatNumber(p.creditsRemaining)
    return "Credits " + root.formatNumber(p.creditsTotal) + " total"
  }

  function formatNumber(n) {
    if (n === undefined || n === null) return "—"
    if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
    if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
    if (Math.round(n) === n) return String(n)
    return n.toFixed(2)
  }

  // ---------------------------------------------------------------- icons

  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * root.colorChannelLuminance(color.r)
      + 0.7152 * root.colorChannelLuminance(color.g)
      + 0.0722 * root.colorChannelLuminance(color.b)
  }

  // Vendored brand marks come in a dark variant (<id>.svg, black) for light
  // surfaces and a light variant (<id>-light.svg, white) for dark ones,
  // mirroring how the native widget swaps the Codex mark.
  function iconSourceForProvider(p) {
    if (!p || String(p.iconBase || "") === "") return ""
    var onLight = root.colorLuminance(root.surface) >= 0.5
    return Qt.resolvedUrl("assets/icons/" + p.iconBase + (onLight ? ".svg" : "-light.svg"))
  }

  function providerInitials(p) {
    if (!p) return "?"
    var words = String(p.providerName || "").split(/\s+/).filter(function(w) { return w !== "" })
    var out = ""
    for (var i = 0; i < words.length && out.length < 2; i++) out += words[i].charAt(0)
    return out === "" ? "?" : out.toUpperCase()
  }

  function hasIcon(p) { return root.iconSourceForProvider(p) !== "" }

  // ---------------------------------------------------------------- days

  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getFullYear()
      + "-" + String(now.getMonth() + 1).padStart(2, "0")
      + "-" + String(now.getDate()).padStart(2, "0")
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  function dayLabel(date, today) {
    if (today) return "Today"
    return root.dayName(date)
  }

  function dayTooltip(day) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : root.dayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    return label + " · " + usage.formatTokenCount(Number(day.messageCount || 0)) + " tokens"
  }

  function weekPeak(p) {
    var days = p ? (p.recentDays || []) : []
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].messageCount || 0))
    return peak
  }

  // ---------------------------------------------------------------- misc

  function updatedText() {
    var when = "updated " + root.timeAgo(usage.lastRefreshedAtMs)
    if (usage.isStalled()) when += " · stalled"
    if (usage.codexbarVersion !== "") return "CodexBar " + usage.codexbarVersion + " · " + when
    return when
  }

  function timeAgo(ms) {
    if (!(ms > 0)) return "—"
    var elapsed = Math.floor((root.nowMs - ms) / 1000)
    if (elapsed < 60) return "now"
    return root.formatDuration(elapsed * 1000) + " ago"
  }

  function emptyText() {
    if (usage.usageStatusText !== "") return usage.usageStatusText + "\n\nStart it with `codexbar serve` and enable providers in CodexBar settings."
    return "No provider usage from CodexBar yet.\nEnable a provider in CodexBar and wait for the next refresh."
  }

  function barTooltip() {
    if (!root.provider) return "CodexBar — no provider usage"
    var label = root.provider.providerName
    if (root.provider.headlinePercent >= 0) label += " · " + Math.round(root.provider.headlinePercent * 100) + "%"
    return label
  }

  // The slot is the user's choice: once placed, the icon stays put and the
  // panel explains any failure (binary missing, no provider data) when opened,
  // instead of the widget silently vanishing.
  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    // Fetch usage now (restarting the background countdown) and pull the
    // heavier cost history for the daily token chart.
    usage.pollNow()
    usage.refreshCost()
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
    function status(): string {
      var snap = usage.statusSnapshot()
      snap.widget = { visible: root.visible, opened: root.opened, providerCount: root.providers.length, provider: root.provider ? root.provider.providerId : "" }
      return JSON.stringify(snap)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱚣"
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(800))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (root.providerDropdownOpen) return
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: { if (!root.providerDropdownOpen) root.refreshNow() }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (root.providerDropdownOpen) return
        if (t === "r" || t === "R") root.refreshNow()
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

          // ---------- Hero: provider mark · name · plan + provider picker ----------
          PanelHero {
            visible: !!root.provider
            width: parent.width
            title: root.provider ? root.provider.providerName : ""
            meta: root.providerMeta(root.provider)
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Item {
                width: Style.font.display
                height: Style.font.display

                // Brand mark when we vendored one, initials tile otherwise.
                Image {
                  visible: root.hasIcon(root.provider)
                  anchors.fill: parent
                  source: root.iconSourceForProvider(root.provider)
                  sourceSize.width: Style.font.display * 2
                  sourceSize.height: Style.font.display * 2
                  fillMode: Image.PreserveAspectFit
                }

                Rectangle {
                  visible: !root.hasIcon(root.provider)
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: root.alpha(root.foreground, 0.12)

                  Text {
                    anchors.centerIn: parent
                    text: root.providerInitials(root.provider)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }
            }

            trailingControl: Component {
              ProviderDropdown {
                width: root.providerDropdownWidth
                showLabel: false
                fontFamily: root.fontFamily
                options: root.providerOptions
                value: root.selectedProviderId
                onChanged: function(v) { root.selectProviderId(v) }
                onPopupOpenChanged: root.providerDropdownOpen = popupOpen
                Component.onCompleted: root.providerDropdownOpen = popupOpen
                Component.onDestruction: root.providerDropdownOpen = false
              }
            }
          }

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

          // ---------- Status ----------
          BorderSurface {
            visible: !!root.provider && String(root.provider.error || "") !== "" && String(root.provider.statusText || "") !== ""
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: statusText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: root.provider && root.provider.error !== "" ? root.provider.error : (root.provider ? root.provider.statusText : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Limits ----------
          PanelSeparator {
            visible: limitsSection.visible
            foreground: root.foreground
          }

          Column {
            id: limitsSection
            visible: root.limits.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "LIMITS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.limits
              LimitRow {
                required property var modelData
                width: limitsSection.width
                window: modelData
              }
            }
          }

          // ---------- Credits ----------
          PanelSeparator {
            visible: creditsSection.visible
            foreground: root.foreground
          }

          Column {
            id: creditsSection
            visible: root.creditsLine(root.provider) !== ""
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "CREDITS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              text: root.creditsLine(root.provider)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          // ---------- Tokens by day (only when CodexBar reports history) ----------
          PanelSeparator {
            visible: daySection.visible
            foreground: root.foreground
          }

          Column {
            id: daySection
            visible: root.hasDays
            width: parent.width
            spacing: Style.space(10)

            readonly property real peak: Math.max(1, root.weekPeak(root.provider))

            PanelSectionHeader {
              text: "TOKENS BY DAY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.days
              DayRow {
                required property var modelData
                required property int index

                width: daySection.width
                day: modelData
                ratio: Number(modelData.messageCount || 0) / daySection.peak
                today: String(modelData.date || "") === root.todayDate()
              }
            }
          }

          Text {
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.updatedText()
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

  // A limit window: label and percentage, meter, and reset countdown.
  component LimitRow: Column {
    id: limitRow
    property var window: null

    readonly property bool alarming: window && window.percent >= 0.9

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

      Text {
        id: limitLabel
        text: limitRow.window ? limitRow.window.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: limitValue
        text: limitRow.window && limitRow.window.percent >= 0
          ? Math.round(limitRow.window.percent * 100) + "%"
          : "—"
        color: limitRow.alarming ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: limitRow.window ? limitRow.window.percent : -1
      alarming: limitRow.alarming
    }

    Text {
      width: parent.width
      text: {
        var remainingMs = root.resetMsFor(limitRow.window)
        return remainingMs > 0 ? "Resets in " + root.formatDuration(remainingMs) : ""
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    // CodexBar's pace forecast: how far the window is expected to be used at
    // the current burn rate, and whether it lasts to the reset.
    Text {
      visible: Boolean(limitRow.window && limitRow.window.pace)
      width: parent.width
      text: {
        var pc = limitRow.window.pace
        if (!pc) return ""
        var parts = ["At this pace"]
        if (pc.expectedPercent >= 0)
          parts.push("~" + Math.round(pc.expectedPercent * 100) + "% used")
        parts.push(pc.willLastToReset ? "lasts until reset" : "runs out before reset")
        return parts.join(" · ")
      }
      color: Boolean(limitRow.window && limitRow.window.pace && !limitRow.window.pace.willLastToReset) ? root.urgent : root.dim
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

  // One row per day: label, bar, tokens. Today is picked out in full
  // foreground so the history reads as a run-up to right now.
  component DayRow: Item {
    id: dayRow
    property var day: null
    property real ratio: 0
    property bool today: false

    implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight) + Style.spacing.sm

    Text {
      id: dayLabel
      text: root.dayLabel(dayRow.day ? dayRow.day.date : "", dayRow.today)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: dayRow.today
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    Rectangle {
      id: dayTrack
      anchors.left: dayLabel.right
      anchors.right: dayValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * root.clamp(dayRow.ratio, 0, 1)
        color: dayRow.today ? root.foreground : root.alpha(root.foreground, 0.55)

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      id: dayValue
      text: usage.formatTokenCount(dayRow.day ? Number(dayRow.day.messageCount || 0) : 0)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    MouseArea {
      id: dayHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: dayHover.containsMouse
      text: root.dayTooltip(dayRow.day)
      fontFamily: root.fontFamily
    }
  }
}
