import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.maxmad75.btc-watcher"

  // The fetch lives here rather than in the panel: alerts have to keep working
  // while the panel is closed, and the panel is only a view onto this data.
  property var report: null
  property string lastError: ""

  // The host does not hand a bar widget its manifest, so the plugin directory
  // is derived from this file's own URL instead of being guessed or injected.
  readonly property string fetcher: decodeURIComponent(String(Qt.resolvedUrl("bin/btc-watcher-fetch")).replace(/^file:\/\//, ""))

  readonly property string currency: root.setting("currency", "EUR")
  // Settings are hand-editable in shell.json, so a value that is not a number
  // has to land on the default rather than on NaN — a NaN Timer interval never
  // fires again, and the widget would go quietly stale.
  function number(key, fallback) {
    var value = Number(root.setting(key, fallback))
    return isFinite(value) ? value : fallback
  }

  readonly property int pollSeconds: Math.max(15, root.number("pollSeconds", 60))
  readonly property int cooldownMs: Math.max(0, root.number("notifyCooldownMinutes", 30)) * 60000

  // The shell builds one widget per monitor and every one of them polls, so
  // the cooldown is not kept here: the fetcher claims an alert under a file
  // lock, and only the instance that wins the claim notifies.
  property var pendingNotice: null
  property bool refreshQueued: false

  // The first reading after a start establishes the baseline and never alerts.
  // Two reasons: the notification service is not up yet a second into the
  // shell's life, so the message would be posted into the void — and a
  // threshold that was crossed while the machine slept is history, not news.
  property bool primed: false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("report" in target) target.report = root.report
    if ("hostWidgetRefresh" in target) target.hostWidgetRefresh = root.refresh
  }

  function refresh() {
    if (fetchProc.running) {
      // The running fetch may be asking the old question (currency changed).
      root.refreshQueued = true
      return
    }
    fetchProc.running = true
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function maybeNotify() {
    var alert = Model.pendingAlert(root.report, root.settings)
    if (!alert) return
    // A price the fetcher could not refresh is not news.
    if (root.report.price && root.report.price.stale) return
    if (claimProc.running) return

    root.pendingNotice = alert
    claimProc.command = [
      "timeout", "5", root.fetcher,
      "--claim-alert", alert.direction,
      "--cooldown", String(root.cooldownMs / 1000)
    ]
    claimProc.running = true
  }

  function sendNotice() {
    var alert = root.pendingNotice
    root.pendingNotice = null
    if (!alert || !root.report || !root.report.price) return

    var arrow = alert.direction === "up" ? "▲" : "▼"
    var headline = "Bitcoin " + arrow + " " + Math.abs(alert.percent).toFixed(1) + " %"
    var body = Model.windowLabel(alert.window) + " · now "
      + Model.formatPrice(root.report.price.value, root.currency)

    notifyProc.command = [
      "omarchy-notification-send",
      "-g", "₿",
      "-u", alert.direction === "down" ? "normal" : "low",
      headline, body
    ]
    notifyProc.running = true
  }

  // Without data the pill stays as a bare ₿ (error in the tooltip) rather
  // than vanishing with nothing to click.
  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string label: {
    var text = Model.barText(root.report, root.settings)
    return text !== "" ? text : "₿"
  }

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    // Currency or window changed: the cached answer is for the old question.
    refresh()
  }
  onReportChanged: injectPanel()

  Process {
    id: fetchProc
    // `timeout`: DNS resolution is outside the fetcher's own request budget,
    // and a hung Process would otherwise block every later poll.
    command: ["timeout", "25", root.fetcher, "--currency", root.currency]
    // Parsed here rather than in onExited: the collector is only guaranteed to
    // have the whole stream at this point, and exit can land first.
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: fetchProc.apply(String(text || ""))
    }

    // The fetcher bounds its own output, but this process is long-lived and
    // the one holding the string, so the ceiling is enforced on this side too.
    readonly property int maxBytes: 262144

    function apply(raw) {
      if (raw.length > fetchProc.maxBytes) {
        console.warn("btc-watcher: fetcher returned " + raw.length
          + " bytes, over the " + fetchProc.maxBytes + " byte ceiling — ignoring it")
        root.lastError = "Unexpected answer from the data helper"
        return
      }

      var parsed = null
      try {
        parsed = JSON.parse(raw)
      } catch (e) {
        parsed = null
      }

      // A report for another currency than the one now configured is the
      // answer to an old question; drop it and ask again.
      if (parsed && parsed.ok && parsed.currency !== String(root.currency).toUpperCase()) {
        root.refreshQueued = true
        return
      }

      if (parsed && parsed.ok) {
        root.lastError = ""
        root.report = parsed
        if (root.primed) root.maybeNotify()
        else root.primed = true
      } else {
        // Keep the last good reading on screen. A failed poll is a network
        // blip, not news, and blanking the bar over it is worse than stale.
        root.lastError = parsed && parsed.error
          ? String(parsed.error).slice(0, 120)
          : "No answer from mempool.space / CoinGecko"
      }
    }

    onRunningChanged: {
      if (!running && root.refreshQueued) {
        root.refreshQueued = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: claimProc
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (String(text || "").trim() === "yes") root.sendNotice()
        else root.pendingNotice = null
      }
    }
  }

  Process {
    id: notifyProc
    command: ["true"]
  }

  Timer {
    interval: root.pollSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // WidgetButton rather than BarIconButton: this pill is text of varying
  // width, and BarIconButton is a fixed slot sized for one glyph.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    labelVisible: true
    hasVisualContent: true
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.lastError !== "" && !root.report
      ? root.lastError
      : Model.tooltipText(root.report, root.settings)

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
