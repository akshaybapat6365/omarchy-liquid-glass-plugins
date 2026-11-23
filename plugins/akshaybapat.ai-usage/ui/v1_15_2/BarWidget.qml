import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The provider strip (v1.15.2 — precision circular dials, dual typography & glass craft).
//
// Each metered provider wears one compact circular tachometer ring wrapping
// its centered vendor mark, paired with its tabular figure right beside it.
// Moving from vertical pill columns to circular dials removes the "battery
// charge remaining" visual confusion next to the laptop battery, normalizes
// wide marks (Grok) to the exact same visual footprint, and uses a clear
// 3-tier semantic color progression (calm ink -> warm amber >=70% -> urgent
// coral-red >=90%) with generous inter-provider spacing so numbers never bleed
// into the next logo.
BarWidget {
  id: root
  moduleName: "akshaybapat.ai-usage"
  readonly property string uiRevision: "1.15.2"

  IpcHandler {
    enabled: root.bar !== null && root.bar.shell !== null && root.QsWindow.window !== null
    target: root.moduleName + "." + (root.QsWindow.window ? root.QsWindow.window.screen.name : "unmounted")
    function appearance(): string {
      return JSON.stringify(root.appearance())
    }
  }

  function appearance() {
    return { revision: uiRevision, bar: Model.renderedMarks(strip),
      dormant: root.dormant, stripWidth: strip.implicitWidth, stripHeight: strip.implicitHeight,
      cells: root.cells.map(function(c) { return { id: c.id, state: c.state, look: c.look, pace: c.pace } }),
      inks: root.inks.contrast,
      theme: { foreground: String(Commons.Color.foreground), background: String(Commons.Color.background),
        accent: String(Commons.Color.accent), urgent: String(Commons.Color.urgent), muted: String(Commons.Color.muted),
        shellValues: Commons.Color.shellValues, cornerRadius: Style.cornerRadius,
        barForeground: String(root.foreground) },
      panel: panelItem ? panelItem.appearance() : null }
  }

  readonly property var panelItem: panelLoader.item
  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem
    ? panelItem.popoutSwitchClosing === true
    : false

  // ------------------------------------------------------------- tokens
  readonly property color foreground: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color surfaceColor: root.bar && "barBackground" in root.bar
    ? root.bar.barBackground : Commons.Color.bar.background
  readonly property color urgentColor: color3(Model.barAlarmRgb(rgb(bar ? bar.urgent : Commons.Color.urgent),
    rgb(foreground), surfaceColor.a >= 1 ? rgb(surfaceColor) : null))
  readonly property color warnColor: color3(Model.barWarnRgb(rgb(foreground),
    surfaceColor.a >= 1 ? rgb(surfaceColor) : null))

  function legibleAlarm(alarm, ink, surface) {
    var rgbVal = Model.legibleAlarmRgb([alarm.r, alarm.g, alarm.b], [ink.r, ink.g, ink.b],
      surface ? [surface.r, surface.g, surface.b] : null)
    return Qt.rgba(rgbVal[0], rgbVal[1], rgbVal[2], 1)
  }
  readonly property string monoFont: bar ? bar.fontFamily : Style.font.family
  readonly property string uiFont: (Style.font.menuFamily && Style.font.menuFamily.length > 0 && Style.font.menuFamily !== "monospace")
    ? Style.font.menuFamily
    : "Inter Display"
  readonly property string fontFamily: monoFont

  // ------------------------------------------------------------ settings
  readonly property bool showPercent: Model.booleanSetting(setting("showPercent", true), true)
  readonly property bool showMeter: Model.booleanSetting(setting("showMeter", true), true)
  readonly property bool compact: Model.booleanSetting(setting("compact", false), false)
  readonly property string providersSetting: String(setting("providers", "") || "").trim()

  readonly property int refreshIntervalSec: Math.max(30, Math.min(3600,
    Number(setting("refreshIntervalSec", 300)) || 300))

  // ---------------------------------------------------------------- data
  UsageSource {
    id: usage
    refreshIntervalSec: root.refreshIntervalSec
  }

  readonly property var entries: usage.entries
  readonly property bool loading: usage.loading
  readonly property double nowMs: usage.nowMs
  readonly property var cells: Model.stripCells(entries, providersSetting, usage.lastSeen, usage.misses)
  readonly property var dormant: Model.dormantProviders(entries, providersSetting, usage.lastSeen)

  function tooltipFor(index) {
    var cell = cells[index]
    return cell ? Model.cellTooltip(cell.entry, nowMs) : ""
  }

  // --------------------------------------------------------------- metrics
  // Precision circular instrument geometry at 12 px base font on the 26 px bar:
  //   dialSize    22 px circle (2 px clear top and bottom on 26 px bar)
  //   arcWidth    2.0 px stroke, antialiased CurveRenderer
  //   innerMark   11 px square centered inside the 18 px inner cavity (wide
  //               wordmark 14 x 7), keeping >1.1 px clean breathing room all
  //               the way around every logo so no swoosh touches the ring
  //   bareMark    16 px (Style.bar.iconCanvas) when meter is off or balance-only
  //   labelGap    4 px between dial/mark and its own figure
  //   cellGap     10 px between providers (2.5x wider than internal gap)
  readonly property int markSize: Style.bar.iconCanvas
  readonly property int dialSize: Math.min(root.barSize - 4, Math.max(16, Style.space(22)))
  readonly property real arcWidth: Math.max(1.8, Style.space(2))
  readonly property int labelGap: Math.max(3, Style.space(4))
  readonly property int cellGap: Math.max(8, Style.space(10))
  readonly property int stripPadding: Style.space(3)

  readonly property var inks: Model.stripInks(rgb(surfaceColor), rgb(foreground), rgb(urgentColor),
    rgb(Commons.Color.muted))
  readonly property color wellColor: color3(inks.well)
  readonly property color urgentWellColor: color3(inks.urgentWell)
  readonly property color rimColor: color3(inks.rim)
  readonly property color quietTextColor: color3(inks.quietText)
  readonly property color paceLineColor: color3(inks.paceLine)
  // Quiet translucent circular track: legible on both dark and light bars without
  // ever reading as a solid grey slab on zero/calm items.
  readonly property color dialTrackColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.24)

  function rgb(c) { return [c.r, c.g, c.b] }
  function color3(v) { return Qt.rgba(v[0], v[1], v[2], 1) }

  function open() { if (panelItem) panelItem.open() }
  function close() { if (panelItem) panelItem.close() }
  function toggle() { if (panelItem) panelItem.toggle() }
  function closeForPopoutSwitch() { if (panelItem) panelItem.closeForPopoutSwitch() }
  function refresh() { usage.refresh() }

  function nextEntry() {
    if (panelItem) panelItem.selectEntry(panelItem.entryIndex + 1)
  }

  function openAt(entryId) {
    if (!panelItem) return
    panelItem.showEntry(entryId)
  }

  function launchDashboard() {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation ai-usagebar-tui")
    root.close()
  }

  function injectPanel() {
    var target = panelItem
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = strip
    if ("hostWidget" in target) target.hostWidget = root
    if ("source" in target) target.source = usage
  }

  visible: cells.length > 0 || loading || dormant.length > 0 || providersSetting !== ""
  implicitWidth: strip.implicitWidth
  implicitHeight: strip.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

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

  Item {
    id: strip
    anchors.fill: parent
    implicitWidth: root.vertical ? root.barSize : cellRow.implicitWidth + root.stripPadding * 2
    implicitHeight: root.vertical ? cellColumn.implicitHeight + root.stripPadding * 2 : root.barSize

    Row {
      id: cellRow
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: root.cellGap

      Repeater {
        model: root.vertical ? [] : root.cells
        delegate: ProviderCell {}
      }
    }

    Column {
      id: cellColumn
      visible: root.vertical
      anchors.centerIn: parent
      spacing: Style.space(6)

      Repeater {
        model: root.vertical ? root.cells : []
        delegate: ProviderCell {}
      }
    }

    WidgetButton {
      id: placeholder
      anchors.centerIn: parent
      visible: root.cells.length === 0
      bar: root.bar
      text: "󰚩"
      fontSize: Style.bar.iconFont
      dimmed: false
      tooltipText: root.loading ? "Collecting AI usage…"
        : root.dormant.length > 0 ? "No AI provider has a reading to show: click for why"
        : root.providersSetting !== "" ? "No provider named in the providers option reported usage"
        : "No configured AI provider reported usage"
      onPressed: function(buttonCode) {
        if (buttonCode === Qt.RightButton) root.launchDashboard()
        else root.toggle()
      }
    }
  }

  // ------------------------------------------------------------------ cell
  component ProviderCell: WidgetButton {
    id: cell

    required property var modelData
    required property int index
    readonly property var view: modelData
    readonly property var look: view.look || Model.cellLook(view)

    readonly property bool hasGauge: root.showMeter && look.gauge !== "none"
    readonly property bool levelled: look.gauge === "fill" || look.gauge === "hollow"
    readonly property bool wantsValue: !root.vertical && look.figure !== ""
      && (look.gauge === "signin" || look.gauge === "sleep" || look.figure === "no plan"
        || (look.gauge === "none" && (root.compact || !root.showPercent))
        || (root.showPercent && !root.compact))
    readonly property bool hasPace: look.gauge === "fill" && view.pace !== null && view.pace !== undefined

    // 3-tier semantic color ladder: calm ink -> warm amber (70–89% / <$5) -> urgent red-orange (>=90% / <$1 / signin).
    readonly property bool isWarn: !look.urgent && look.bold && look.gauge !== "signin"
    readonly property color ink: look.urgent || look.gauge === "signin"
      ? root.urgentColor
      : (isWarn ? root.warnColor : root.foreground)

    readonly property real pctClamped: levelled && isFinite(Number(view.percent))
      ? Math.max(0, Math.min(100, Number(view.percent))) : 0
    readonly property real sweepDeg: pctClamped > 0 ? Math.max(22, pctClamped * 3.6) : 0
    readonly property real paceRad: hasPace
      ? ((-90 + Math.max(0, Math.min(100, Number(view.pace) || 0)) * 3.6) * Math.PI / 180) : 0

    readonly property real aspect: Model.markAspect(view.mark)
    readonly property int bareMarkWidth: Math.round(root.markSize * aspect)
    // Inside the 22 px dial ring (18 px inner diameter), compute height first
    // and multiply by exact markAspect so every logo (square 11 x 11, 2:1
    // SpaceXAI 14 x 7) preserves exact proportions with >1.1 px clearance.
    readonly property int innerMarkH: aspect > 1.3 ? Math.max(6, Math.round(root.dialSize * 0.31)) : Math.round(root.dialSize * 0.50)
    readonly property int innerMarkW: Math.round(innerMarkH * aspect)
    readonly property int visualWidth: hasGauge ? root.dialSize : bareMarkWidth
    readonly property real figureWidth: wantsValue ? valueMetrics.advanceWidth : 0

    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    interactive: true
    pressable: true
    tooltipText: root.tooltipFor(index)
    // Uniform cell width in vertical bars so dials (22 px) and bare balance
    // marks (16 px) share one centered vertical axis instead of drifting left.
    fixedWidth: root.vertical
      ? Math.max(16, root.barSize - Style.space(2))
      : visualWidth + (wantsValue ? root.labelGap + Math.ceil(figureWidth) : 0)
    fixedHeight: root.vertical ? root.dialSize : root.barSize
    opacity: concealed ? 0 : 1

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchDashboard()
      else if (buttonCode === Qt.MiddleButton) root.refresh()
      else root.openAt(view.id)
    }

    onWheelMoved: function(delta) {
      if (delta !== 0 && root.panelItem)
        root.panelItem.selectEntry(root.panelItem.entryIndex + (delta < 0 ? 1 : -1))
    }

    TextMetrics {
      id: valueMetrics
      font: value.font
      text: cell.look.figure
    }

    // --------------------------------------------------- circular dial host
    // Keeps objectName "usageColumn" so existing layout/bounds QA checks verify
    // the dial stays cleanly inside the 26 px bar.
    Item {
      id: dial
      objectName: "usageColumn"
      visible: cell.hasGauge
      x: root.vertical ? Math.round((parent.width - width) / 2) : 0
      y: Math.round((parent.height - height) / 2)
      width: root.dialSize
      height: root.dialSize

      readonly property real cx: width / 2
      readonly property real cy: height / 2
      readonly property real r: (width - root.arcWidth) / 2

      // Track ring + active usage arc
      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // Quiet circular base track (or full urgent ring for sign-in required)
        ShapePath {
          fillColor: "transparent"
          strokeWidth: cell.look.gauge === "signin" ? root.arcWidth : Math.max(1.4, root.arcWidth * 0.72)
          strokeColor: cell.look.gauge === "signin" ? root.urgentColor : root.dialTrackColor
          PathAngleArc {
            centerX: dial.cx
            centerY: dial.cy
            radiusX: dial.r
            radiusY: dial.r
            startAngle: 0
            sweepAngle: 360
          }
        }

        // Active usage sweep clockwise from 12 o'clock
        ShapePath {
          fillColor: "transparent"
          strokeWidth: cell.sweepDeg > 0 ? root.arcWidth : 0
          strokeColor: cell.sweepDeg > 0 ? cell.ink : "transparent"
          strokeStyle: cell.look.gauge === "hollow" ? ShapePath.DashLine : ShapePath.SolidLine
          dashPattern: [2, 2]
          capStyle: ShapePath.RoundCap
          PathAngleArc {
            centerX: dial.cx
            centerY: dial.cy
            radiusX: dial.r
            radiusY: dial.r
            startAngle: -90
            sweepAngle: cell.sweepDeg
          }
        }
      }

      // Pace graduation pip on the dial perimeter (shows time elapsed in window).
      // High-contrast ink center + 1 px surface knockout halo so it stays crisp
      // across dark/light themes and over calm, amber, or urgent arcs alike.
      Rectangle {
        visible: cell.hasPace
        readonly property real pipSize: Math.max(3.6, root.arcWidth * 1.8)
        width: pipSize
        height: pipSize
        radius: pipSize / 2
        antialiasing: true
        color: root.foreground
        border.width: 1
        border.color: root.surfaceColor.a > 0.5 ? root.surfaceColor : Qt.rgba(0, 0, 0, 0.85)
        x: dial.cx + Math.cos(cell.paceRad) * dial.r - width / 2
        y: dial.cy + Math.sin(cell.paceRad) * dial.r - height / 2
      }

      // Centered vendor mark inside the circular dial
      ProviderMark {
        id: dialMark
        role: "bar"
        width: cell.innerMarkW
        height: cell.innerMarkH
        anchors.centerIn: parent
        mark: view.mark
        plain: view.plainMark === true
        initials: view.initials
        color: root.foreground
        surfaceColor: root.surfaceColor
        fontFamily: root.fontFamily
        fontSize: Math.max(8, Style.font.caption - 1)
      }
    }

    // Bare mark when meter is turned off or provider is balance-only ($6.39)
    ProviderMark {
      id: bareMark
      role: "bar"
      visible: !cell.hasGauge
      width: root.vertical ? Math.min(cell.bareMarkWidth, root.barSize - Style.space(4)) : cell.bareMarkWidth
      height: root.vertical ? Math.max(8, Math.round(width / cell.aspect)) : root.markSize
      x: root.vertical ? Math.round((parent.width - width) / 2) : 0
      y: Math.round((parent.height - height) / 2)
      mark: view.mark
      plain: view.plainMark === true
      initials: view.initials
      color: root.foreground
      surfaceColor: root.surfaceColor
      fontFamily: root.fontFamily
    }

    // ---------------------------------------------------------- the figure
    Text {
      id: value
      visible: cell.wantsValue
      text: cell.look.figure
      textFormat: Text.PlainText
      color: cell.look.gauge === "sleep" ? root.quietTextColor
        : (cell.look.gauge === "signin" ? root.urgentColor : cell.ink)
      font.family: root.monoFont
      font.pixelSize: Style.font.bodySmall
      font.weight: cell.look.bold ? Font.Bold : Font.Medium
      font.features: { "tnum": 1 }
      renderType: Text.NativeRendering
      x: cell.visualWidth + root.labelGap
      anchors.verticalCenter: parent.verticalCenter
      Behavior on color { ColorAnimation { duration: Style.duration(140) } }
    }
  }
}
