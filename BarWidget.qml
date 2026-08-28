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
  readonly property string fetcher: String(Qt.resolvedUrl("bin/btc-watcher-fetch")).replace(/^file:\/\//, "")

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

  // When each direction last fired, so a threshold that stays crossed does not
  // notify on every poll.
  property double lastAlertUp: 0
  property double lastAlertDown: 0

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
    if (!fetchProc.running) fetchProc.running = true
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

    var now = Date.now()
    var last = alert.direction === "up" ? root.lastAlertUp : root.lastAlertDown
    if (now - last < root.cooldownMs) return

    if (alert.direction === "up") root.lastAlertUp = now
    else root.lastAlertDown = now

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

  visible: label !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string label: Model.barText(root.report, root.settings)

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    // Currency or window changed: the cached answer is for the old question.
    refresh()
  }
  onReportChanged: injectPanel()

  Process {
    id: fetchProc
    command: [root.fetcher, "--currency", root.currency]
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

      if (parsed && parsed.ok) {
        root.lastError = ""
        root.report = parsed
        if (root.primed) root.maybeNotify()
        else root.primed = true
      } else {
        // Keep the last good reading on screen. A failed poll is a network
        // blip, not news, and blanking the bar over it is worse than stale.
        root.lastError = "No answer from mempool.space / CoinGecko"
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
    hasVisualContent: text !== ""
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: Model.tooltipText(root.report, root.settings)

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
