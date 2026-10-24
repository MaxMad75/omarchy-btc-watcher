import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.maxmad75.btc-watcher"
  ipcTarget: "io.github.maxmad75.btc-watcher"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  // The bar identifies panels by the widget mounted in its slot, not by this
  // nested panel — same reasoning as omarchy.weather.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Pushed in by BarWidget, which owns the polling so alerts keep working
  // while this panel is closed.
  property var report: null
  property var hostWidgetRefresh: null

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refresh()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.settingsOpen = false
    root.advancedOpen = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    if (root.hostWidgetRefresh) root.hostWidgetRefresh()
  }

  readonly property string label: Model.barText(root.report, root.settings)

  readonly property string currency: root.setting("currency", "EUR")
  readonly property var price: report && report.price ? report.price : null
  readonly property var chain: report && report.chain ? report.chain : null
  readonly property var fees: chain && chain.fees ? chain.fees : null
  readonly property var difficulty: chain && chain.difficulty ? chain.difficulty : null
  readonly property var mempool: chain && chain.mempool ? chain.mempool : null
  readonly property int nowTs: report && report.ts ? report.ts : 0
  readonly property bool iconOn: Model.flag(root.setting("showIcon", true), true)

  // Everything visual comes from the active Omarchy theme, never from literals:
  // the bar's own values first, the theme singletons as the fallback.
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The palette has foreground, accent, urgent and muted — no green. Rather
  // than paint a green that fights every theme, direction is carried by the
  // arrow, and colour only marks the fall as the theme's urgent.
  readonly property color upColor: Color.accent
  readonly property color downColor: Color.urgent

  function changeColor(pct) {
    var sign = Model.changeSign(pct)
    if (sign > 0) return root.upColor
    if (sign < 0) return root.downColor
    return root.dim
  }

  // The panel always shows the full spread, so the single number the bar was
  // configured to show has something to be read against.
  readonly property var spreadWindows: ["10m", "1h", "24h"]

  // Omarchy 4.0.1 renders no settings form for bar widgets — `settingsForm` is
  // declared in two first-party manifests and consumed nowhere — so the
  // switches live here. Writing goes through the documented CLI rather than
  // editing shell.json directly, so the host stays the one owning the file.
  // Toggling a part off is refused when it is the last one: an empty pill is
  // not a state anybody chooses on purpose, and there would be no way back to
  // the settings from a bar item that shows nothing.
  function toggleDisplayPart(part) {
    var parts = Model.displayList(root.settings)
    var at = parts.indexOf(part)
    if (at >= 0) {
      if (parts.length === 1) return
      parts.splice(at, 1)
    } else {
      parts.push(part)
    }
    root.setSetting("display", parts.join(","))
  }

  function setSetting(key, value) {
    settingProc.command = ["omarchy", "bar", "set", root.moduleName, key, String(value)]
    settingProc.running = true
  }

  Process {
    id: settingProc
    command: ["true"]
  }

  // The quote currencies CoinGecko accepts. Loaded when the panel first opens
  // rather than at startup: a widget that only ever sits in the bar should not
  // pay for a list nobody looked at.
  // Transient by design: the panel opens collapsed every time, so a stray
  // click last week does not decide what today's glance looks like.
  property bool settingsOpen: false
  property bool advancedOpen: false
  onSettingsOpenChanged: if (settingsOpen) loadCurrencies()

  property var currencyOptions: []
  readonly property string fetcher: decodeURIComponent(String(Qt.resolvedUrl("bin/btc-watcher-fetch")).replace(/^file:\/\//, ""))

  function loadCurrencies() {
    if (root.currencyOptions.length > 0 || currencyProc.running) return
    currencyProc.running = true
  }

  Process {
    id: currencyProc
    command: [root.fetcher, "--currencies"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var codes = String(text || "").split("\n").filter(function(c) { return c.length > 0 })
        if (codes.length > 0) root.currencyOptions = codes
      }
    }
  }

  component Disclosure: Item {
    property string caption: ""
    property bool expanded: false
    signal toggled()

    width: parent ? parent.width : 0
    height: discRow.implicitHeight + Style.space(4)

    Row {
      id: discRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Text {
        text: parent.parent.expanded ? "▾" : "▸"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        width: Style.space(10)
      }
      Text {
        text: parent.parent.caption
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // The whole row is the target; a ten-pixel triangle is not a button.
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.toggled()
    }
  }

  component Chip: Rectangle {
    property string caption: ""
    property bool active: false
    signal picked()

    radius: Style.cornerRadius
    color: active ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"
    border.width: 1
    border.color: active ? root.foreground : Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.45)
    implicitWidth: chipLabel.implicitWidth + Style.space(16)
    implicitHeight: chipLabel.implicitHeight + Style.space(8)

    Text {
      id: chipLabel
      anchors.centerIn: parent
      text: parent.caption
      color: parent.active ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.picked()
    }
  }

  component StatRow: Row {
    property string caption: ""
    property string value: ""
    width: parent ? parent.width : 0
    spacing: Style.space(10)

    Text {
      width: Style.space(74)
      text: parent.caption
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      verticalAlignment: Text.AlignVCenter
      height: parent.height
    }
    Text {
      width: parent.width - Style.space(84)
      text: parent.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // Without this the settings section makes the column taller than the
      // popup and nothing draws at all. Tall content has to scroll, which is
      // exactly how omarchy.weather builds its panel.
      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

      Column {
        id: column
        width: scroll.width
        spacing: Style.space(12)

        // ── Price ────────────────────────────────────────────────────────
        Column {
          width: parent.width
          spacing: Style.space(2)

          Text {
            text: root.price ? Model.formatPrice(root.price.value, root.currency) : "–"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
          }

          Text {
            text: root.price ? Model.formatSatsPerUnit(root.price.value, root.currency) : ""
            visible: text !== ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(18)

          Repeater {
            model: root.spreadWindows
            delegate: Column {
              id: spreadItem
              required property string modelData
              readonly property var pct: root.price && root.price.change
                ? root.price.change[modelData] : null
              spacing: 0

              Text {
                text: Model.formatChange(spreadItem.pct)
                color: root.changeColor(spreadItem.pct)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.Medium
              }
              Text {
                text: Model.windowLabel(spreadItem.modelData)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        PanelSeparator { width: parent.width }

        // ── Chain ────────────────────────────────────────────────────────
        Column {
          width: parent.width
          spacing: Style.space(6)

          StatRow {
            caption: "Block"
            value: root.chain
              ? Model.formatHeight(root.chain.height) + "  ·  " + Model.formatAge(root.chain.tip_age_s)
              : "–"
          }

          // Three bare fee rates answered no question. What a person actually
          // wants to know is what sending costs right now and what waiting
          // saves, so the rate is converted into their own currency.
          StatRow {
            caption: "Send now"
            value: root.fees && root.price
              ? Model.formatFeeCost(root.fees.fastest, root.price.value, root.currency)
              : (root.fees ? Model.formatFee(root.fees.fastest) : "–")
          }

          StatRow {
            caption: "Or wait"
            value: root.fees && root.price
              ? Model.formatFeeCost(root.fees.economy, root.price.value, root.currency)
              : (root.fees ? Model.formatFee(root.fees.economy) : "–")
          }

          // Backlog in blocks rather than transactions: "84 000 tx" means
          // nothing without knowing what fits in a block.
          StatRow {
            caption: "Backlog"
            value: root.mempool ? Model.formatMempool(root.mempool.vsize) : "–"
          }

          StatRow {
            caption: "Difficulty"
            value: root.difficulty
              ? Model.formatChange(root.difficulty.change_pct, { digits: 2 })
                + " · " + Model.formatEta(root.difficulty.retarget_ts, root.nowTs)
              : "–"
          }

          StatRow {
            caption: "Hashrate"
            value: root.chain ? Model.formatHashrate(root.chain.hashrate) : "–"
          }

          StatRow {
            caption: "Halving"
            value: root.chain && root.chain.halving
              ? Model.formatCount(root.chain.halving.blocks_left) + " blocks · "
                + Model.formatEta(root.chain.halving.est_ts, root.nowTs)
              : "–"
          }
        }

        PanelSeparator { width: parent.width }

        // ── Switches ─────────────────────────────────────────────────────
        // Folded away by default: the panel is opened to read a number, not to
        // configure one.
        Disclosure {
          caption: "Settings"
          expanded: root.settingsOpen
          onToggled: root.settingsOpen = !root.settingsOpen
        }

        Column {
          visible: root.settingsOpen
          width: parent.width
          spacing: Style.space(6)

          // Multi-select: each part is independent, and the pill shows them in
          // the fixed order Model.DISPLAY_PARTS defines.
          Row {
            spacing: Style.space(6)
            Repeater {
              model: Model.DISPLAY_PARTS
              delegate: Chip {
                required property string modelData
                caption: Model.displayLabel(modelData)
                active: Model.displayList(root.settings).indexOf(modelData) >= 0
                onPicked: root.toggleDisplayPart(modelData)
              }
            }
          }

          Row {
            spacing: Style.space(8)
            topPadding: Style.space(6)

            Text {
              text: "Currency"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }

            SearchableDropdown {
              width: Style.space(130)
              showLabel: false
              fontFamily: root.fontFamily
              placeholderText: "Search…"
              emptyText: "No match"
              options: root.currencyOptions.length > 0 ? root.currencyOptions : [root.currency]
              value: root.currency
              onChanged: function(value) { root.setSetting("currency", value) }
            }
          }

          Row {
            spacing: Style.space(6)
            topPadding: Style.space(4)

            Chip {
              caption: root.iconOn ? "₿ on" : "₿ off"
              active: root.iconOn
              onPicked: root.setSetting("showIcon", root.iconOn ? "false" : "true")
            }

            Repeater {
              model: ["10m", "1h", "24h"]
              delegate: Chip {
                required property string modelData
                caption: modelData
                active: root.setting("changeWindow", "24h") === modelData
                onPicked: root.setSetting("changeWindow", modelData)
              }
            }
          }

          // A second fold: thresholds are set once and then never looked
          // at again, so they do not belong in the way of the things that are.
          Disclosure {
            caption: "Advanced"
            expanded: root.advancedOpen
            onToggled: root.advancedOpen = !root.advancedOpen
          }

          Column {
            visible: root.advancedOpen
            width: parent.width
            spacing: Style.space(6)

            Text {
              text: "Notify when the price moves, over the window below"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              spacing: Style.space(6)
              Text {
                text: "▲"
                color: root.upColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(12)
              }
              Repeater {
                model: [0, 1, 2, 3, 5, 10]
                delegate: Chip {
                  required property int modelData
                  caption: modelData === 0 ? "off" : modelData + " %"
                  active: Number(root.setting("notifyUpPercent", 0)) === modelData
                  onPicked: root.setSetting("notifyUpPercent", modelData)
                }
              }
            }

            Row {
              spacing: Style.space(6)
              Text {
                text: "▼"
                color: root.downColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(12)
              }
              Repeater {
                model: [0, 1, 2, 3, 5, 10]
                delegate: Chip {
                  required property int modelData
                  caption: modelData === 0 ? "off" : modelData + " %"
                  active: Number(root.setting("notifyDownPercent", 0)) === modelData
                  onPicked: root.setSetting("notifyDownPercent", modelData)
                }
              }
            }

            // Capped at an hour on purpose: a slower alert is a news article,
            // not a notification. The bar can still display longer spans.
            Row {
              spacing: Style.space(6)
              topPadding: Style.space(4)
              Text {
                text: "over"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(34)
              }
              Repeater {
                model: ["10m", "15m", "30m", "1h"]
                delegate: Chip {
                  required property string modelData
                  caption: modelData
                  active: root.setting("notifyWindow", "1h") === modelData
                  onPicked: root.setSetting("notifyWindow", modelData)
                }
              }
            }

            Row {
              spacing: Style.space(6)
              Text {
                text: "quiet"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(34)
              }
              Repeater {
                model: [15, 30, 60, 120]
                delegate: Chip {
                  required property int modelData
                  caption: modelData + " min"
                  active: Number(root.setting("notifyCooldownMinutes", 30)) === modelData
                  onPicked: root.setSetting("notifyCooldownMinutes", modelData)
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          text: root.hostWidget && root.hostWidget.lastError ? root.hostWidget.lastError : ""
          visible: text !== ""
          color: root.downColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
      }
    }
  }
}
