import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Bar entry for Vitals: a chip icon (plus passive temperature while awake)
// that opens the monitor panel. Panel.qml is loaded once so tab selection,
// sort order, and session peaks survive between opens while collector.py
// runs strictly on-open-only.
BarWidget {
  id: root
  moduleName: "akshaybapat.vitals"
  readonly property var panelItem: panelLoader.item

  property string passiveText: "󰢮"
  property string passiveTooltip: ""
  // waybar-gpu reads only sysfs, so polling it never wakes the card. Its
  // "sleep" class means the NVIDIA GPU is powered off: the chip rests dimmed
  // with no text beside it; "warm" (>=70°C) and "hot" (>=85°C) surface
  // thermal attention on the bar without waking the GPU.
  property bool gpuAsleep: false
  property string gpuClass: "cool"

  readonly property color barInk: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color barSurface: bar ? bar.barBackground : Commons.Color.background
  readonly property color warnInk: {
    var rgb = Model.warnRgb([barInk.r, barInk.g, barInk.b], [barSurface.r, barSurface.g, barSurface.b])
    return Qt.rgba(rgb[0], rgb[1], rgb[2], 1)
  }

  Process {
    id: passiveStatus
    command: ["waybar-gpu"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const status = JSON.parse(text)
          root.passiveText = status.text || "󰢮"
          root.passiveTooltip = String(status.tooltip || "")
          root.gpuClass = String(status["class"] || "cool")
          root.gpuAsleep = root.gpuClass === "sleep"
        } catch (e) {
          root.passiveText = "󰢮"
          root.passiveTooltip = ""
          root.gpuClass = "cool"
          root.gpuAsleep = false
        }
      }
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: if (!passiveStatus.running) passiveStatus.running = true
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (!panelLoader.item) return
    if (panelLoader.item.opened) panelLoader.item.close()
    else { panelLoader.item.showTab("gpu"); panelLoader.item.open() }
  }

  // Shape contract for shell.summon/hide/toggle routing — the bar identifies
  // this widget, not the nested panel.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) { panelLoader.item.showTab("gpu"); panelLoader.item.openFromHotkey() }
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.gpuAsleep ? "󰢮" : root.passiveText
    fontSize: root.gpuAsleep ? Style.font.body : Style.font.bodySmall
    dimmed: root.gpuAsleep
    active: !root.gpuAsleep && root.gpuClass === "hot"
    foreground: !root.gpuAsleep && root.gpuClass === "warm" ? root.warnInk : root.barInk
    tooltipText: root.gpuAsleep
      ? "Graphics card asleep, saving battery\nClick for GPU & system vitals"
      : (root.passiveTooltip || "GPU & system vitals")
    onPressed: function(b) { root.togglePanel() }
  }
}
