import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Vitals v1.3.0: Apple-Studio-grade translucent frosted-glass GPU & system
// monitor panel for Omarchy. collector.py runs strictly while the panel is
// open (zero background polling when closed), and only the active tab is
// instantiated.
Panel {
  id: root
  moduleName: "akshaybapat.vitals"
  ipcTarget: "akshaybapat.vitals"
  // manageIpc: false so this panel owns the single IpcHandler for showTab + appearance.
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  // The bar tracks BarWidget.qml rather than this nested panel.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- palette / semantic ramp / typography ---------------------------------
  readonly property color surface: Commons.Color.popups.background
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar && bar.urgent !== undefined ? bar.urgent : Commons.Color.urgent
  readonly property color accent: Commons.Color.accent
  readonly property color dim: alpha(foreground, 0.64)
  readonly property color faint: alpha(foreground, 0.46)
  readonly property color track: alpha(foreground, 0.10)
  readonly property color glassFill: alpha(foreground, 0.05)
  readonly property color glassBorder: alpha(foreground, 0.14)
  readonly property color wellFill: alpha(foreground, 0.035)
  readonly property color wellBorder: alpha(foreground, 0.10)

  readonly property color warnColor: {
    var v = Model.warnRgb([foreground.r, foreground.g, foreground.b], [surface.r, surface.g, surface.b])
    return Qt.rgba(v[0], v[1], v[2], 1)
  }
  readonly property color criticalColor: {
    var v = Model.criticalRgb([urgent.r, urgent.g, urgent.b], [foreground.r, foreground.g, foreground.b], [surface.r, surface.g, surface.b])
    return Qt.rgba(v[0], v[1], v[2], 1)
  }
  readonly property color chartAccent: {
    var v = Model.chartAccentRgb([accent.r, accent.g, accent.b], [foreground.r, foreground.g, foreground.b], [surface.r, surface.g, surface.b])
    return Qt.rgba(v[0], v[1], v[2], 1)
  }
  readonly property color chartSecondary: {
    var v = Model.secondaryChartRgb([accent.r, accent.g, accent.b], [foreground.r, foreground.g, foreground.b], [surface.r, surface.g, surface.b])
    return Qt.rgba(v[0], v[1], v[2], 1)
  }

  readonly property int cardRadius: Math.max(12, Style.cornerRadius + 2)
  readonly property int controlRadius: Math.max(8, Style.cornerRadius)
  readonly property string monoFont: bar ? bar.fontFamily : Style.font.family
  readonly property string uiFont: (Style.font.menuFamily && Style.font.menuFamily.length > 0 && Style.font.menuFamily !== "monospace")
    ? Style.font.menuFamily
    : "Inter Display"
  readonly property string fontFamily: monoFont
  readonly property bool isDark: (0.2126 * surface.r + 0.7152 * surface.g + 0.0722 * surface.b) < 0.5
  readonly property color specularTop: Qt.rgba(1, 1, 1, isDark ? 0.08 : 0.35)
  readonly property int bodyTextSize: Math.max(12, Style.font.body)
  readonly property int captionTextSize: Math.max(10, Style.font.caption)
  readonly property int titleTextSize: Math.max(18, Style.font.heading + 2)
  readonly property string icon: "󰍛"

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function tierColor(tier, calmColor) {
    if (tier === "critical") return root.criticalColor
    if (tier === "warn") return root.warnColor
    return calmColor
  }

  // ---- settings -------------------------------------------------------------
  readonly property int refreshSeconds: clamp(Number(setting("refreshSeconds", 1)) || 1, 1, 10)
  readonly property int historyLength: 90

  // ---- open / close ---------------------------------------------------------
  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.confirmOpen) root.cancelSignal()
    if (root.filtering) root.stopFiltering()
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
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  onOpenedChanged: {
    if (opened) {
      gpuHistories = ({})
      gpuTimes = ({})
      gpuTempPeaks = ({})
      cursorActive = false
      Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    }
  }

  readonly property bool collecting: collector.running
  readonly property string uiRevision: "1.3.0"

  function appearance() {
    return {
      revision: uiRevision,
      opened: opened,
      tab: tabKey,
      collecting: collector.running,
      contentWidth: panel.contentWidth,
      contentHeight: panel.contentHeight,
      bodyTextSize: bodyTextSize,
      captionTextSize: captionTextSize,
      devices: gpus.map(function(g) {
        return {
          id: Model.gpuKey(g),
          name: g.name,
          vendor: g.vendor,
          busy: g.busy,
          estimated: g.busy_estimated === true,
          temp: g.temp,
          power: g.power_w,
          samples: (gpuHistories[Model.gpuKey(g)] || []).length,
          peak: gpuTempPeaks[Model.gpuKey(g)] || null
        }
      })
    }
  }

  // ---- data -----------------------------------------------------------------
  property var snapshot: null
  readonly property bool hasData: snapshot !== null
  readonly property var cpu: snapshot ? snapshot.cpu : null
  readonly property var mem: snapshot ? snapshot.mem : null
  readonly property var disks: snapshot ? (snapshot.disks || []) : []
  readonly property var gpus: snapshot ? (snapshot.gpus || []) : []
  readonly property var ifaces: snapshot && snapshot.net ? (snapshot.net.ifaces || []) : []
  readonly property var processes: snapshot ? (snapshot.processes || []) : []
  readonly property var sensorTemps: snapshot && snapshot.sensors ? (snapshot.sensors.temps || []) : []
  readonly property var sensorFans: snapshot && snapshot.sensors ? (snapshot.sensors.fans || []) : []

  readonly property var hottest: {
    let best = null
    for (let i = 0; i < sensorTemps.length; i++) {
      const s = sensorTemps[i]
      if (s.temp === null || s.temp === undefined) continue
      if (!best || s.temp > best.temp) best = s
    }
    return best
  }

  readonly property var hottestGpu: {
    let best = null
    for (let i = 0; i < gpus.length; i++) {
      const g = gpus[i]
      if (g.temp === null || g.temp === undefined) continue
      if (!best || g.temp > best.temp) best = g
    }
    return best
  }

  readonly property real totalGpuPowerW: {
    let sum = 0
    let found = false
    for (let i = 0; i < gpus.length; i++) {
      const p = gpus[i].power_w
      if (p !== null && p !== undefined && isFinite(p)) { sum += Number(p); found = true }
    }
    return found ? sum : -1
  }

  readonly property bool anyDiskTemp: {
    for (let i = 0; i < disks.length; i++)
      if (disks[i].temp !== null && disks[i].temp !== undefined) return true
    return false
  }

  // High-water marks covering observed time while the panel is open.
  property var sensorPeaks: ({})
  property real cpuTempPeak: 0
  property var gpuTempPeaks: ({})

  property var cpuHistory: []
  property var gpuHistories: ({})
  property var gpuTimes: ({})
  readonly property var gpuDomain: Model.gpuTimeDomain(gpuTimes, gpus)
  property var rxHistory: []
  property var txHistory: []
  property var memHistory: []

  readonly property string collectorPath: Qt.resolvedUrl("collector.py").toString().replace(/^file:\/\//, "")

  // On-open-only collector: prefer native Rust vitalsd (<10 ms, zero GPU wake)
  // with automatic fallback to collector.py if the binary is missing.
  Process {
    id: collector
    command: [
      "sh", "-c",
      "if [ -x \"$HOME/.local/bin/vitalsd\" ]; then exec \"$HOME/.local/bin/vitalsd\" --interval \"$1\"; else exec python3 \"$2\" --interval \"$1\"; fi",
      "--", String(root.refreshSeconds), root.collectorPath
    ]
    running: root.opened
    stdout: SplitParser {
      onRead: function(line) { root.ingest(line) }
    }
  }

  function ingest(line) {
    const raw = String(line || "").trim()
    if (!raw) return
    let parsed
    try { parsed = JSON.parse(raw) } catch (e) { return }
    if (!parsed || !parsed.cpu) return
    snapshot = parsed
    cpuHistory = Model.pushHistory(cpuHistory, parsed.cpu.total, historyLength)
    memHistory = Model.pushHistory(memHistory, parsed.mem && parsed.mem.total > 0 ? parsed.mem.used * 100 / parsed.mem.total : 0, historyLength)
    const histories = {}, times = {}, current = parsed.gpus || []
    for (const timeKey in gpuTimes) times[timeKey] = gpuTimes[timeKey]
    for (const oldKey in gpuHistories) histories[oldKey] = gpuHistories[oldKey]
    for (let g = 0; g < current.length; g++) {
      const gpu = current[g]
      const key = Model.gpuKey(gpu)
      if (gpu.busy !== null && gpu.busy !== undefined) {
        histories[key] = Model.pushHistory(histories[key] || [], gpu.busy, historyLength)
        const stamps = (times[key] || []).slice()
        stamps.push(Number(parsed.t) || Date.now() / 1000)
        if (stamps.length > historyLength) stamps.shift()
        times[key] = stamps
      }
    }
    gpuHistories = histories
    gpuTimes = times
    const curIf = currentIface(parsed.net ? (parsed.net.ifaces || []) : [])
    rxHistory = Model.pushHistory(rxHistory, curIf ? curIf.rx_bps : 0, historyLength)
    txHistory = Model.pushHistory(txHistory, curIf ? curIf.tx_bps : 0, historyLength)
    trackPeaks(parsed)
    if (tabKey === "proc") rebuildProcs()
  }

  function trackPeaks(parsed) {
    if (parsed.cpu && parsed.cpu.temp > cpuTempPeak) cpuTempPeak = parsed.cpu.temp
    const gpuPeaks = {}, cards = parsed.gpus || []
    for (const oldKey in gpuTempPeaks) gpuPeaks[oldKey] = gpuTempPeaks[oldKey]
    for (let g = 0; g < cards.length; g++) {
      const gpu = cards[g]
      const key = Model.gpuKey(gpu)
      if (gpu.temp !== null && gpu.temp !== undefined)
        gpuPeaks[key] = Math.max(gpuPeaks[key] || 0, gpu.temp)
    }
    gpuTempPeaks = gpuPeaks
    const list = parsed.sensors ? (parsed.sensors.temps || []) : []
    if (list.length === 0) return
    const peaks = {}
    for (const k in sensorPeaks) peaks[k] = sensorPeaks[k]
    let changed = false
    for (let i = 0; i < list.length; i++) {
      const s = list[i]
      if (s.temp === null || s.temp === undefined) continue
      if (!(s.key in peaks) || s.temp > peaks[s.key]) { peaks[s.key] = s.temp; changed = true }
    }
    if (changed) sensorPeaks = peaks
  }

  function peakFor(key) {
    return (key in sensorPeaks) ? sensorPeaks[key] : null
  }

  // ---- tabs -----------------------------------------------------------------
  readonly property var tabs: {
    var t = [
      { key: "gpu", label: "GPU", title: "Graphics", glyph: "󰢮" },
      { key: "cpu", label: "CPU", title: "Processor", glyph: "󰍛" },
      { key: "mem", label: "Memory", title: "Memory", glyph: "󰘚" },
      { key: "disk", label: "Disks", title: "Storage", glyph: "󰋊" },
      { key: "net", label: "Network", title: "Network", glyph: "󰛳" }
    ]
    if (root.sensorTemps.length > 0 || root.sensorFans.length > 0 || !root.hasData)
      t.push({ key: "sensors", label: "Sensors", title: "Thermals", glyph: "󰔏" })
    t.push({ key: "proc", label: "Processes", title: "Processes", glyph: "󰒓" })
    return t
  }
  property string tabKey: "gpu"
  readonly property int tabIndex: {
    for (let i = 0; i < tabs.length; i++) if (tabs[i].key === tabKey) return i
    return 0
  }
  readonly property var activeTab: tabs.length > 0 ? tabs[tabIndex] : ({ key: "gpu", label: "GPU", title: "Graphics", glyph: "󰢮" })
  property bool cursorActive: false
  property bool cursorFromKeys: false

  function selectTab(index) {
    if (tabs.length === 0) return
    const n = tabs.length
    const i = ((index % n) + n) % n
    if (tabs[i].key === tabKey) return
    if (filtering) stopFiltering()
    tabKey = tabs[i].key
    procIndex = 0
    cursorFromKeys = false
    if (panelFlick) panelFlick.contentY = 0
    if (tabKey === "proc") rebuildProcs()
  }

  // Jump to a tab by key: gpu · cpu · mem · disk · net · sensors · proc.
  function showTab(key) {
    for (let i = 0; i < tabs.length; i++) {
      if (tabs[i].key === String(key)) { selectTab(i); return true }
    }
    return false
  }

  IpcHandler {
    target: "akshaybapat.vitals"

    function appearance(): string { return JSON.stringify(root.appearance()) }
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function showTab(key: string): string {
      const ok = root.showTab(key)
      if (ok && !root.opened) root.openFromHotkey()
      return ok ? "ok" : "unknown"
    }
  }

  // Hero figure & semantic tint for non-GPU tabs.
  readonly property string headline: {
    const snap = snapshot
    if (!snap) return "—"
    if (tabKey === "cpu") return snap.cpu ? Model.percent(snap.cpu.total) : "—"
    if (tabKey === "mem") return snap.mem && snap.mem.total > 0 ? Model.percent(snap.mem.used * 100 / snap.mem.total) : "—"
    if (tabKey === "disk") {
      const d = snap.disks && snap.disks.length ? snap.disks[0] : null
      return d && d.total > 0 ? Model.percent(d.used * 100 / d.total) : "—"
    }
    if (tabKey === "net") {
      const i = currentIface()
      return i ? Model.rate(i.rx_bps) : "—"
    }
    if (tabKey === "gpu") {
      const g = snap.gpus && snap.gpus.length ? snap.gpus[0] : null
      return g && g.busy !== null && g.busy !== undefined ? Model.percent(g.busy) : "—"
    }
    if (tabKey === "sensors") {
      const hot = root.hottest
      return hot ? Model.temp(hot.temp) : "—"
    }
    if (tabKey === "proc") return Model.count(snap.processes ? snap.processes.length : 0)
    return "—"
  }

  readonly property string headlineCaption: {
    if (tabKey === "cpu") return "CPU LOAD"
    if (tabKey === "mem") return "MEMORY USED"
    if (tabKey === "disk") return disks.length ? Model.mountLabel(disks[0].mount).toUpperCase() + " USED" : "STORAGE"
    if (tabKey === "net") return "RECEIVING"
    if (tabKey === "gpu") return "GPU LOAD"
    if (tabKey === "sensors") {
      const hot = root.hottest
      return hot ? hot.label.toUpperCase() : "PEAK SENSOR"
    }
    if (tabKey === "proc") return "PROCESSES"
    return ""
  }

  readonly property color headlineColor: {
    if (!snapshot) return root.foreground
    if (tabKey === "cpu" && cpu) return root.tierColor(Model.loadTier(cpu.total), root.foreground)
    if (tabKey === "mem" && mem && mem.total > 0) return root.tierColor(Model.memTier(mem.used / mem.total), root.foreground)
    if (tabKey === "disk" && disks.length > 0 && disks[0].total > 0) return root.tierColor(Model.memTier(disks[0].used / disks[0].total), root.foreground)
    if (tabKey === "sensors" && hottest) return root.tierColor(Model.tempTier(hottest.temp, hottest.crit || 0), root.foreground)
    return root.foreground
  }

  // ---- network interface selection ------------------------------------------
  property string ifaceName: ""

  function currentIface(fromList) {
    const list = fromList || ifaces
    if (list.length === 0) return null
    for (let i = 0; i < list.length; i++) if (list[i].name === ifaceName) return list[i]
    return list[0]
  }

  readonly property var iface: currentIface()

  function selectIface(name) {
    if (name === (iface ? iface.name : "")) return
    ifaceName = name
    rxHistory = []
    txHistory = []
  }

  // ---- processes ------------------------------------------------------------
  property string sortKey: "cpu"
  property bool sortReverse: false
  property int procIndex: 0
  property int selectedPid: -1
  property string filterText: ""
  property bool filtering: false
  property var sortedProcs: []
  readonly property var sortColumns: ["name", "pid", "user", "mem", "cpu"]
  readonly property var procTab: procLoader.item

  function setSort(key) {
    if (sortKey === key) sortReverse = !sortReverse
    else { sortKey = key; sortReverse = false }
    rebuildProcs()
  }

  function cycleSort(delta) {
    var i = sortColumns.indexOf(sortKey)
    var n = sortColumns.length
    sortKey = sortColumns[(((i + delta) % n) + n) % n]
    sortReverse = false
    rebuildProcs()
  }

  function rebuildProcs() {
    const list = Model.sortProcesses(Model.filterProcesses(processes, filterText), sortKey, sortReverse)
    const followPid = cursorActive && cursorFromKeys && procIndex >= 0 && procIndex < sortedProcs.length ? sortedProcs[procIndex].pid : -1
    sortedProcs = list
    const n = list.length
    let selectedStillHere = false
    for (let i = 0; i < n; i++) {
      const p = list[i]
      const row = {
        pid: p.pid, ppid: p.ppid, name: p.name, user: p.user, cpu: p.cpu, mem: p.mem,
        threads: p.threads, state: p.state || "", cmd: p.cmd
      }
      if (i < procModel.count) procModel.set(i, row)
      else procModel.append(row)
      if (p.pid === selectedPid) selectedStillHere = true
    }
    while (procModel.count > n) procModel.remove(procModel.count - 1)
    if (followPid >= 0) {
      for (let j = 0; j < n; j++) {
        if (list[j].pid === followPid) {
          if (j !== procIndex) {
            procIndex = j
            procScrollTo(j)
          }
          break
        }
      }
    }
    if (procIndex >= n) procIndex = Math.max(0, n - 1)
    if (selectedPid >= 0 && !selectedStillHere && filterText === "") selectedPid = -1
  }

  ListModel { id: procModel }

  function procScrollTo(index) {
    if (procTab && procTab.scrollTo) procTab.scrollTo(index)
  }

  function moveProcCursor(delta) {
    if (sortedProcs.length === 0) return
    cursorFromKeys = true
    procIndex = clamp(procIndex + delta, 0, sortedProcs.length - 1)
    procScrollTo(procIndex)
  }

  function jumpProcCursor(toEnd) {
    if (sortedProcs.length === 0) return
    cursorActive = true
    cursorFromKeys = true
    procIndex = toEnd ? sortedProcs.length - 1 : 0
    if (procTab && procTab.scrollToEdge) procTab.scrollToEdge(toEnd)
  }

  function toggleSelected(pid) {
    selectedPid = selectedPid === pid ? -1 : pid
  }

  function activateCursor() {
    if (tabKey !== "proc") return
    if (!cursorActive) { cursorActive = true; return }
    if (procIndex >= 0 && procIndex < sortedProcs.length) toggleSelected(sortedProcs[procIndex].pid)
  }

  function startFiltering() {
    filtering = true
    if (procTab && procTab.focusFilter) procTab.focusFilter()
  }

  function stopFiltering() {
    filtering = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function clearFilter() {
    filterText = ""
    if (procTab && procTab.clearFilterField) procTab.clearFilterField()
    rebuildProcs()
    stopFiltering()
  }

  // ---- signals to processes -------------------------------------------------
  property bool confirmOpen: false
  property var confirmTarget: null
  property string confirmSignal: "TERM"

  readonly property var signalVerbs: ({ TERM: "Terminate", KILL: "Kill", STOP: "Pause", CONT: "Resume" })

  function requestSignal(proc, sig) {
    if (!proc) return
    if (sig === "STOP" || sig === "CONT") { sendSignal(proc.pid, sig); return }
    confirmTarget = proc
    confirmSignal = sig
    confirmOpen = true
    Qt.callLater(function() { confirmKeys.forceActiveFocus() })
  }

  function requestTerminateCursor() {
    if (tabKey !== "proc" || !cursorActive || procIndex < 0 || procIndex >= sortedProcs.length) return
    requestSignal(sortedProcs[procIndex], "TERM")
  }

  function cancelSignal() {
    confirmOpen = false
    confirmTarget = null
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function confirmSignalNow() {
    if (confirmTarget) sendSignal(confirmTarget.pid, confirmSignal)
    cancelSignal()
  }

  function sendSignal(pid, sig) {
    signalProc.command = ["kill", "-" + sig, String(pid)]
    signalProc.running = true
  }

  Process { id: signalProc }

  // ---- surface --------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: Style.space(20)
    contentWidth: panel.fittedContentWidth(Style.space(620))
    contentHeight: panel.fittedContentHeight(Math.max(column.implicitHeight, Style.space(520)), Style.space(820))

    // Keys while a Terminate / Kill confirmation is up.
    Item {
      id: confirmKeys
      anchors.fill: parent
      visible: root.confirmOpen
      z: 20
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (signalConfirm.handleKey(event)) event.accepted = true
      }

      ConfirmDialog {
        id: signalConfirm
        anchors.fill: parent
        opened: root.confirmOpen
        message: root.confirmTarget
          ? root.signalVerbs[root.confirmSignal] + " " + root.confirmTarget.name + " (pid " + root.confirmTarget.pid + ")?"
            + (root.confirmSignal === "KILL" ? "\nSIGKILL cannot be caught — unsaved work is lost." : "")
          : ""
        confirmText: root.signalVerbs[root.confirmSignal] || "Confirm"
        background: Commons.Color.popups.background
        foreground: root.foreground
        fontFamily: root.uiFont
        onCanceled: root.cancelSignal()
        onConfirmed: root.confirmSignalNow()
      }
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.filtering || root.confirmOpen

      onMoveRequested: function(dx, dy) {
        root.cursorActive = true
        if (dx !== 0) root.selectTab(root.tabIndex + dx)
        else if (dy !== 0) {
          if (root.tabKey === "proc") root.moveProcCursor(dy)
          else panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                                Math.max(0, panelFlick.contentHeight - panelFlick.height))
        }
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: {
        if (root.selectedPid >= 0) root.selectedPid = -1
        else if (root.filterText !== "") root.clearFilter()
        else root.close()
      }
      onDeleteRequested: root.requestTerminateCursor()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var n = parseInt(t, 10)
        if (!isNaN(n) && n >= 1 && n <= root.tabs.length) { root.selectTab(n - 1); return }
        if (root.tabKey !== "proc") return
        if (t === "s") root.cycleSort(1)
        else if (t === "S") root.cycleSort(-1)
        else if (t === "r" || t === "R") { root.sortReverse = !root.sortReverse; root.rebuildProcs() }
        else if (t === "/" || t === "f" || t === "F") root.startFiltering()
        else if (t === "g") root.jumpProcCursor(false)
        else if (t === "G") root.jumpProcCursor(true)
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
        ScrollBar.vertical: ScrollBar { policy: panelFlick.contentHeight > panelFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(14)

          // ---------- Instrument Header ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(iconBadge.height, heroLabels.implicitHeight, rightCluster.implicitHeight)

            Rectangle {
              id: iconBadge
              width: Style.space(38)
              height: Style.space(38)
              radius: Math.max(10, root.controlRadius)
              color: root.glassFill
              border.width: 1
              border.color: root.glassBorder
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter

              GlassHighlight { inset: Style.space(6) }

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: root.activeTab ? root.activeTab.glyph : root.icon
                color: root.tabKey === "gpu" ? root.chartAccent : root.foreground
                font.family: root.monoFont
                font.pixelSize: Style.space(18)
              }
            }

            Column {
              id: heroLabels
              anchors.left: iconBadge.right
              anchors.leftMargin: Style.space(12)
              anchors.right: rightCluster.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Text {
                textFormat: Text.PlainText
                text: root.activeTab ? root.activeTab.title : "System Vitals"
                color: root.foreground
                font.family: root.uiFont
                font.pixelSize: root.titleTextSize
                font.weight: Font.DemiBold
                font.letterSpacing: -0.3
                elide: Text.ElideRight
                width: parent.width
              }

              Row {
                spacing: Style.space(6)
                width: parent.width

                Rectangle {
                  width: Style.space(6)
                  height: width
                  radius: width / 2
                  color: root.hasData && root.collecting ? root.chartAccent : root.faint
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width - Style.space(12)
                  text: root.snapshot
                    ? (String(root.snapshot.host || "localhost").toUpperCase()
                       + " · UP " + Model.uptime(root.snapshot.uptime).toUpperCase()
                       + " · LIVE " + root.refreshSeconds + "S")
                    : "READING HARDWARE…"
                  color: root.faint
                  font.family: root.uiFont
                  font.pixelSize: root.captionTextSize
                  font.weight: Font.DemiBold
                  font.letterSpacing: 0.75
                  font.features: { "tnum": 1 }
                  elide: Text.ElideRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            Row {
              id: rightCluster
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              // GPU tab glance pill: shows hottest GPU temp + aggregate power right in the header.
              Rectangle {
                visible: root.tabKey === "gpu" && root.hasData && (root.hottestGpu !== null || root.totalGpuPowerW >= 0)
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: gpuGlanceRow.implicitWidth + Style.space(18)
                implicitHeight: Style.space(28)
                radius: height / 2
                color: root.glassFill
                border.width: 1
                border.color: root.glassBorder

                GlassHighlight { inset: Style.space(8) }

                Row {
                  id: gpuGlanceRow
                  anchors.centerIn: parent
                  spacing: Style.space(8)

                  Text {
                    visible: root.hottestGpu !== null
                    textFormat: Text.PlainText
                    text: root.hottestGpu ? Model.temp(root.hottestGpu.temp) : ""
                    color: root.hottestGpu
                      ? root.tierColor(Model.tempTier(root.hottestGpu.temp, 0), root.foreground)
                      : root.foreground
                    font.family: root.monoFont
                    font.pixelSize: root.bodyTextSize
                    font.bold: true
                    font.features: { "tnum": 1 }
                  }

                  Rectangle {
                    visible: root.hottestGpu !== null && root.totalGpuPowerW >= 0
                    width: 1
                    height: Style.space(12)
                    color: root.alpha(root.foreground, 0.16)
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    visible: root.totalGpuPowerW >= 0
                    textFormat: Text.PlainText
                    text: Model.watts(root.totalGpuPowerW)
                    color: root.dim
                    font.family: root.monoFont
                    font.pixelSize: root.bodyTextSize
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                  }
                }
              }

              // Headline readout on non-GPU tabs.
              Column {
                visible: root.tabKey !== "gpu"
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Text {
                  textFormat: Text.PlainText
                  anchors.right: parent.right
                  text: root.headline
                  color: root.headlineColor
                  font.family: root.monoFont
                  font.pixelSize: root.headline.length > 6 ? Style.space(17) : Style.space(22)
                  font.bold: true
                  font.features: { "tnum": 1 }
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.right: parent.right
                  text: root.headlineCaption
                  color: root.faint
                  font.family: root.uiFont
                  font.pixelSize: Math.max(9, root.captionTextSize - 1)
                  font.weight: Font.DemiBold
                  font.letterSpacing: 0.9
                }
              }

              PanelActionButton {
                anchors.verticalCenter: parent.verticalCenter
                size: Style.space(29)
                iconText: "×"
                fontSize: Style.space(16)
                tooltipText: "Close monitor"
                foreground: root.dim
                hoverColor: root.foreground
                fontFamily: root.monoFont
                bordered: true
                onClicked: root.close()
              }
            }
          }

          // ---------- Rounded Segmented Tab Rail ----------
          Rectangle {
            id: tabRail
            width: parent.width
            height: Style.space(34)
            radius: Math.max(10, root.controlRadius)
            color: root.glassFill
            border.width: 1
            border.color: root.alpha(root.foreground, 0.12)

            GlassHighlight { inset: Style.space(7) }

            Row {
              id: tabRow
              anchors.fill: parent
              anchors.margins: Style.space(3)
              spacing: Style.space(3)

              readonly property real cellWidth: root.tabs.length > 0
                ? (width - spacing * (root.tabs.length - 1)) / root.tabs.length
                : 0

              Repeater {
                model: root.tabs

                Item {
                  id: tabCell
                  required property var modelData
                  required property int index
                  readonly property bool isCurrent: root.tabIndex === index
                  readonly property bool isCursor: root.cursorActive && isCurrent

                  width: tabRow.cellWidth
                  height: parent.height

                  Rectangle {
                    anchors.fill: parent
                    radius: Math.max(7, root.controlRadius - 2)
                    color: tabCell.isCurrent
                      ? root.alpha(root.foreground, 0.14)
                      : (tabMouse.containsMouse ? root.alpha(root.foreground, 0.06) : "transparent")
                    border.width: tabCell.isCurrent || tabCell.isCursor ? 1 : 0
                    border.color: tabCell.isCursor
                      ? root.alpha(root.accent, 0.72)
                      : (tabCell.isCurrent ? root.alpha(root.foreground, 0.18) : "transparent")
                    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                    Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

                    GlassHighlight {
                      visible: tabCell.isCurrent
                      inset: Style.space(5)
                    }
                  }

                  // Centered accent indicator on active segment (matches ai-usage v1.15).
                  Rectangle {
                    opacity: tabCell.isCurrent ? 1 : 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Style.space(2)
                    width: Style.space(16)
                    height: 2
                    radius: 1
                    color: root.chartAccent
                    Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: tabCell.isCurrent ? -1 : 0
                    width: parent.width - Style.space(6)
                    horizontalAlignment: Text.AlignHCenter
                    text: tabCell.modelData.label
                    color: tabCell.isCurrent ? root.foreground : (tabMouse.containsMouse ? root.alpha(root.foreground, 0.85) : root.dim)
                    font.family: root.uiFont
                    font.pixelSize: Style.font.bodySmall
                    font.weight: tabCell.isCurrent ? Font.DemiBold : Font.Medium
                    font.letterSpacing: 0.05
                    elide: Text.ElideRight
                    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                  }

                  MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.cursorActive = false; root.selectTab(tabCell.index) }
                  }
                }
              }
            }
          }

          // ---------- Active Tab Body (lazy-instantiated) ----------
          Loader { width: parent.width; active: root.tabKey === "gpu"; visible: active; sourceComponent: gpuTab }
          Loader { width: parent.width; active: root.tabKey === "cpu"; visible: active; sourceComponent: cpuTab }
          Loader { width: parent.width; active: root.tabKey === "mem"; visible: active; sourceComponent: memTab }
          Loader { width: parent.width; active: root.tabKey === "disk"; visible: active; sourceComponent: diskTab }
          Loader { width: parent.width; active: root.tabKey === "net"; visible: active; sourceComponent: netTab }
          Loader { width: parent.width; active: root.tabKey === "sensors"; visible: active; sourceComponent: sensorsTab }
          Loader { id: procLoader; width: parent.width; active: root.tabKey === "proc"; visible: active; sourceComponent: procTabComponent }
        }
      }
    }
  }

  // ======================================================= GPU Dashboard
  Component {
    id: gpuTab

    Column {
      id: graphicsView
      spacing: Style.space(12)

      GlassCard {
        visible: !root.hasData || root.gpus.length === 0
        width: parent.width

        Text {
          textFormat: Text.PlainText
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: !root.hasData ? "Reading graphics hardware…" : "Graphics readings are unavailable."
          color: root.dim
          font.family: root.uiFont
          font.pixelSize: root.bodyTextSize
        }
      }

      // Crisp 2-column side-by-side GPU instrument cards (NVIDIA + Intel).
      GridLayout {
        visible: root.gpus.length > 0
        width: parent.width
        columns: width >= Style.space(500) && root.gpus.length > 1 ? 2 : 1
        columnSpacing: Style.space(12)
        rowSpacing: Style.space(12)

        Repeater {
          model: root.gpus
          delegate: GpuDeviceCard {
            required property var modelData
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            device: modelData
            history: root.gpuHistories[Model.gpuKey(modelData)] || []
            sampleTimes: root.gpuTimes[Model.gpuKey(modelData)] || []
            domainStart: root.gpuDomain.start
            domainEnd: root.gpuDomain.end
            peak: root.gpuTempPeaks[Model.gpuKey(modelData)] || 0
            ink: root.foreground
            mutedInk: root.dim
            chartColor: modelData.vendor === "nvidia" ? root.chartAccent : root.chartSecondary
            warnColor: root.warnColor
            criticalColor: root.criticalColor
            specularTop: root.specularTop
            fontFamily: root.monoFont
            monoFont: root.monoFont
            uiFont: root.uiFont
            bodySize: root.bodyTextSize
            captionSize: root.captionTextSize
          }
        }
      }

      // Unified frosted-glass Cooling & System Context footer card:
      // two deliberate, spacious rows so fan chips and host vitals never crowd.
      GlassCard {
        id: footerCard
        visible: root.hasData
        width: parent.width
        cardPadding: Style.space(12)

        readonly property var footerFans: root.cpu && root.cpu.fans && root.cpu.fans.length > 0
          ? root.cpu.fans
          : root.sensorFans

        Column {
          width: parent.width
          spacing: Style.space(9)

          // Row 1: Cooling fans
          Item {
            width: parent.width
            implicitHeight: Math.max(coolingTag.implicitHeight, fansFlow.implicitHeight)

            Text {
              id: coolingTag
              textFormat: Text.PlainText
              width: Style.space(64)
              height: Style.space(22)
              verticalAlignment: Text.AlignVCenter
              text: "COOLING"
              color: root.faint
              font.family: root.uiFont
              font.pixelSize: Math.max(9, root.captionTextSize - 1)
              font.weight: Font.DemiBold
              font.letterSpacing: 0.9
              anchors.left: parent.left
              anchors.top: parent.top
            }

            Flow {
              id: fansFlow
              anchors.left: coolingTag.right
              anchors.leftMargin: Style.space(8)
              anchors.right: parent.right
              anchors.top: parent.top
              spacing: Style.space(8)

              Repeater {
                model: footerCard.footerFans
                delegate: Rectangle {
                  required property var modelData
                  implicitWidth: fanRow.implicitWidth + Style.space(14)
                  implicitHeight: Style.space(22)
                  radius: height / 2
                  color: root.alpha(root.foreground, 0.045)
                  border.width: 1
                  border.color: root.alpha(root.foreground, 0.11)

                  Row {
                    id: fanRow
                    anchors.centerIn: parent
                    spacing: Style.space(5)

                    Rectangle {
                      width: Style.space(5)
                      height: width
                      radius: width / 2
                      color: modelData.rpm > 0 ? root.chartSecondary : root.faint
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.label
                      color: root.dim
                      font.family: root.uiFont
                      font.pixelSize: root.captionTextSize
                      font.weight: Font.Medium
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: Model.rpm(modelData.rpm)
                      color: root.foreground
                      font.family: root.monoFont
                      font.pixelSize: root.captionTextSize
                      font.bold: true
                      font.features: { "tnum": 1 }
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }
              }

              Text {
                visible: footerCard.footerFans.length === 0
                textFormat: Text.PlainText
                height: Style.space(22)
                verticalAlignment: Text.AlignVCenter
                text: "Passive / no fan sensors"
                color: root.faint
                font.family: root.uiFont
                font.pixelSize: root.captionTextSize
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: root.alpha(root.foreground, 0.09)
          }

          // Row 2: Host CPU, Memory & Load context
          Item {
            width: parent.width
            implicitHeight: Math.max(hostTag.implicitHeight, hostMetrics.implicitHeight)

            Text {
              id: hostTag
              textFormat: Text.PlainText
              width: Style.space(64)
              text: "SYSTEM"
              color: root.faint
              font.family: root.uiFont
              font.pixelSize: Math.max(9, root.captionTextSize - 1)
              font.weight: Font.DemiBold
              font.letterSpacing: 0.9
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Row {
              id: hostMetrics
              anchors.left: hostTag.right
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(12)

              Row {
                visible: !!root.cpu
                spacing: Style.space(5)
                Text {
                  textFormat: Text.PlainText
                  text: "CPU"
                  color: root.faint
                  font.family: root.uiFont
                  font.pixelSize: Math.max(9, root.captionTextSize - 1)
                  font.weight: Font.DemiBold
                  font.letterSpacing: 0.8
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  textFormat: Text.PlainText
                  text: root.cpu ? Model.percent(root.cpu.total) : "—"
                  color: root.cpu ? root.tierColor(Model.loadTier(root.cpu.total), root.foreground) : root.foreground
                  font.family: root.monoFont
                  font.pixelSize: root.captionTextSize
                  font.bold: true
                  font.features: { "tnum": 1 }
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  visible: root.cpu && root.cpu.temp !== null && root.cpu.temp !== undefined
                  textFormat: Text.PlainText
                  text: root.cpu ? "· " + Model.temp(root.cpu.temp) : ""
                  color: root.cpu ? root.tierColor(Model.tempTier(root.cpu.temp, 0), root.dim) : root.dim
                  font.family: root.monoFont
                  font.pixelSize: root.captionTextSize
                  font.features: { "tnum": 1 }
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Rectangle {
                visible: !!root.cpu && !!root.mem
                width: 1
                height: Style.space(11)
                color: root.alpha(root.foreground, 0.14)
                anchors.verticalCenter: parent.verticalCenter
              }

              Row {
                visible: !!root.mem && root.mem.total > 0
                spacing: Style.space(5)
                Text {
                  textFormat: Text.PlainText
                  text: "RAM"
                  color: root.faint
                  font.family: root.uiFont
                  font.pixelSize: Math.max(9, root.captionTextSize - 1)
                  font.weight: Font.DemiBold
                  font.letterSpacing: 0.8
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  textFormat: Text.PlainText
                  text: root.mem ? Model.bytes(root.mem.used) : "—"
                  color: root.mem && root.mem.total > 0 ? root.tierColor(Model.memTier(root.mem.used / root.mem.total), root.foreground) : root.foreground
                  font.family: root.monoFont
                  font.pixelSize: root.captionTextSize
                  font.bold: true
                  font.features: { "tnum": 1 }
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  textFormat: Text.PlainText
                  text: root.mem ? "/ " + Model.bytes(root.mem.total) : ""
                  color: root.dim
                  font.family: root.monoFont
                  font.pixelSize: root.captionTextSize
                  font.features: { "tnum": 1 }
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            Row {
              visible: root.snapshot && root.snapshot.load && root.snapshot.load.length > 0
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(5)

              Text {
                textFormat: Text.PlainText
                text: "LOAD"
                color: root.faint
                font.family: root.uiFont
                font.pixelSize: Math.max(9, root.captionTextSize - 1)
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                textFormat: Text.PlainText
                text: root.snapshot && root.snapshot.load && root.snapshot.load.length > 0
                  ? Number(root.snapshot.load[0]).toFixed(2)
                  : "—"
                color: root.dim
                font.family: root.monoFont
                font.pixelSize: root.captionTextSize
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }
      }
    }
  }

  // ======================================================= CPU
  Component {
    id: cpuTab

    Column {
      spacing: Style.space(12)

      GlassCard {
        width: parent.width

        Column {
          width: parent.width
          spacing: Style.space(10)

          SectionRow {
            label: root.cpu ? root.cpu.model : "CPU"
            value: root.cpu ? [Model.mhz(root.cpu.freq_mhz), Model.temp(root.cpu.temp)].filter(function(s) { return s !== "—" }).join("  ·  ") : ""
            valueDim: true
          }

          Meter {
            value: root.cpu ? root.cpu.total / 100 : 0
            fillColor: root.cpu ? root.tierColor(Model.loadTier(root.cpu.total), root.chartAccent) : root.chartAccent
          }

          Sparkline {
            width: parent.width
            height: Style.space(82)
            values: root.cpuHistory
            maxValue: 100
            lineColor: root.cpu ? root.tierColor(Model.loadTier(root.cpu.total), root.chartAccent) : root.chartAccent
          }
        }
      }

      GlassCard {
        width: parent.width

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "CORES"
            foreground: root.foreground
            fontFamily: root.uiFont
            font.letterSpacing: 0.85
          }

          Grid {
            id: coreGrid
            width: parent.width
            readonly property int coreCount: root.cpu ? root.cpu.cores.length : 0
            columns: coreCount > 24 ? 4 : (coreCount > 8 ? 2 : 1)
            columnSpacing: Style.space(18)
            rowSpacing: Style.space(5)
            readonly property real cellWidth: (width - columnSpacing * (columns - 1)) / columns

            Repeater {
              model: coreGrid.coreCount

              Item {
                required property int index
                width: coreGrid.cellWidth
                implicitHeight: coreLabel.implicitHeight + Style.space(4)

                readonly property real load: root.cpu ? root.cpu.cores[index] : 0
                readonly property bool hasTemp: root.cpu && root.cpu.core_temps && root.cpu.core_temps.length === root.cpu.cores.length
                readonly property var coreTemp: hasTemp ? root.cpu.core_temps[index] : null
                readonly property color loadFill: root.tierColor(Model.loadTier(load), root.alpha(root.foreground, 0.72))

                Text {
                  textFormat: Text.PlainText
                  id: coreLabel
                  text: "C" + index
                  color: root.faint
                  font.family: root.monoFont
                  font.pixelSize: root.captionTextSize
                  font.features: { "tnum": 1 }
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(26)
                }

                Rectangle {
                  anchors.left: coreLabel.right
                  anchors.right: coreValue.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(5)
                  radius: height / 2
                  color: root.track

                  Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    radius: parent.radius
                    width: parent.width * root.clamp(load / 100, 0, 1)
                    color: loadFill
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  id: coreValue
                  text: Model.percent(load) + (hasTemp ? "  " + (coreTemp === null ? "   " : Model.temp(coreTemp)) : "")
                  color: root.dim
                  font.family: root.monoFont
                  font.pixelSize: root.captionTextSize
                  font.features: { "tnum": 1 }
                  horizontalAlignment: Text.AlignRight
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: hasTemp ? Style.space(66) : Style.space(34)
                }
              }
            }
          }
        }
      }

      GlassCard {
        width: parent.width

        Column {
          width: parent.width
          spacing: Style.space(6)

          Row {
            width: parent.width
            spacing: Style.space(20)

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(5)
              InfoPair { label: "Load average"; value: root.snapshot ? Model.loadAvg(root.snapshot.load) : "—" }
              InfoPair { label: "Processes"; value: root.snapshot ? Model.count(root.snapshot.procs.total) : "—" }
              InfoPair { label: "Frequency"; value: root.cpu ? Model.mhz(root.cpu.freq_mhz) : "—" }
              InfoPair {
                visible: root.cpu && root.cpu.power_w !== null && root.cpu.power_w !== undefined
                label: "Package power"; value: root.cpu ? Model.watts(root.cpu.power_w) : "—"
              }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(5)
              InfoPair { label: "Uptime"; value: root.snapshot ? Model.uptime(root.snapshot.uptime) : "—" }
              InfoPair { label: "Threads"; value: root.snapshot ? Model.count(root.snapshot.procs.threads) : "—" }
              InfoPair {
                label: "Temperature"
                value: {
                  if (!root.cpu) return "—"
                  var s = Model.temp(root.cpu.temp)
                  if (s === "—") return s
                  if (root.cpuTempPeak > root.cpu.temp + 0.5) s += "  ·  pk " + Model.temp(root.cpuTempPeak)
                  return s
                }
              }
            }
          }

          InfoPair {
            visible: root.cpu && root.cpu.fans && root.cpu.fans.length > 0
            label: root.cpu && root.cpu.fans && root.cpu.fans.length > 1 ? "Fans" : "Fan"
            value: {
              if (!root.cpu || !root.cpu.fans || root.cpu.fans.length === 0) return "—"
              var many = root.cpu.fans.length > 1
              return root.cpu.fans.map(function(f) {
                return many ? f.label + " " + Model.rpm(f.rpm) : Model.rpm(f.rpm)
              }).join("   ·   ")
            }
          }
        }
      }
    }
  }

  // ======================================================= Memory
  Component {
    id: memTab

    Column {
      spacing: Style.space(12)

      GlassCard {
        width: parent.width

        Column {
          width: parent.width
          spacing: Style.space(10)

          SectionRow {
            label: "System Memory"
            value: root.mem ? Model.bytes(root.mem.used) + " of " + Model.bytes(root.mem.total) : ""
            valueDim: true
          }

          Meter {
            readonly property real ratio: root.mem && root.mem.total > 0 ? root.mem.used / root.mem.total : 0
            value: ratio
            fillColor: root.tierColor(Model.memTier(ratio), root.chartAccent)
          }

          Sparkline {
            width: parent.width
            height: Style.space(82)
            values: root.memHistory
            maxValue: 100
            lineColor: root.mem && root.mem.total > 0 ? root.tierColor(Model.memTier(root.mem.used / root.mem.total), root.chartAccent) : root.chartAccent
          }

          Column {
            width: parent.width
            spacing: Style.space(5)

            ShareRow { label: "Used"; amount: root.mem ? root.mem.used : 0; total: root.mem ? root.mem.total : 1; strong: true }
            ShareRow { label: "Available"; amount: root.mem ? root.mem.available : 0; total: root.mem ? root.mem.total : 1 }
            ShareRow { label: "Cached"; amount: root.mem ? root.mem.cached : 0; total: root.mem ? root.mem.total : 1 }
            ShareRow { label: "Buffers"; amount: root.mem ? root.mem.buffers : 0; total: root.mem ? root.mem.total : 1 }
            ShareRow { label: "Free"; amount: root.mem ? root.mem.free : 0; total: root.mem ? root.mem.total : 1 }
          }
        }
      }

      GlassCard {
        width: parent.width

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: {
              var devs = root.mem && root.mem.swap_devices ? root.mem.swap_devices : []
              var zram = devs.some(function(d) { return String(d.name).indexOf("zram") >= 0 })
              return zram ? "SWAP · ZRAM" : "SWAP"
            }
            foreground: root.foreground
            fontFamily: root.uiFont
            font.letterSpacing: 0.85
          }

          SectionRow {
            visible: root.mem && root.mem.swap_total > 0
            label: root.mem && root.mem.swap_total > 0 ? Model.percent(root.mem.swap_used * 100 / root.mem.swap_total) + " used" : ""
            value: root.mem ? Model.bytes(root.mem.swap_used) + " of " + Model.bytes(root.mem.swap_total) : ""
            valueDim: true
          }

          Meter {
            visible: root.mem && root.mem.swap_total > 0
            readonly property real ratio: root.mem && root.mem.swap_total > 0 ? root.mem.swap_used / root.mem.swap_total : 0
            value: ratio
            fillColor: root.tierColor(Model.memTier(ratio), root.chartSecondary)
          }

          Text {
            textFormat: Text.PlainText
            visible: !root.mem || root.mem.swap_total <= 0
            text: "No swap configured"
            color: root.dim
            font.family: root.uiFont
            font.pixelSize: root.bodyTextSize
          }
        }
      }
    }
  }

  // ======================================================= Disks
  Component {
    id: diskTab

    Column {
      spacing: Style.space(10)

      GlassCard {
        visible: root.hasData && root.disks.length === 0
        width: parent.width
        Text {
          textFormat: Text.PlainText
          text: "No mounted filesystems found"
          color: root.dim
          font.family: root.uiFont
          font.pixelSize: root.bodyTextSize
        }
      }

      Repeater {
        model: root.disks

        GlassCard {
          required property var modelData
          required property int index
          width: parent.width

          readonly property real fraction: modelData.total > 0 ? modelData.used / modelData.total : 0
          readonly property bool hasIo: modelData.read_bps !== null && modelData.read_bps !== undefined

          Column {
            width: parent.width
            spacing: Style.space(7)

            Item {
              width: parent.width
              implicitHeight: Math.max(diskName.implicitHeight, diskPct.implicitHeight)

              Row {
                id: diskName
                anchors.left: parent.left
                anchors.right: diskPct.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  text: Model.mountLabel(modelData.mount)
                  color: root.foreground
                  font.family: root.uiFont
                  font.pixelSize: root.bodyTextSize
                  font.weight: Font.DemiBold
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  textFormat: Text.PlainText
                  text: Model.fsLabel(modelData)
                  color: root.dim
                  font.family: root.uiFont
                  font.pixelSize: root.captionTextSize
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                }
                Text {
                  textFormat: Text.PlainText
                  readonly property bool has: modelData.temp !== null && modelData.temp !== undefined
                  visible: has
                  text: has ? "·  " + Model.temp(modelData.temp) : ""
                  color: has ? root.tierColor(Model.tempTier(modelData.temp, 0), root.dim) : root.dim
                  font.family: root.monoFont
                  font.pixelSize: root.captionTextSize
                  font.features: { "tnum": 1 }
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Text {
                textFormat: Text.PlainText
                id: diskPct
                text: Model.percent(fraction * 100)
                color: root.tierColor(Model.memTier(fraction), root.foreground)
                font.family: root.monoFont
                font.pixelSize: root.bodyTextSize
                font.bold: true
                font.features: { "tnum": 1 }
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Meter {
              value: fraction
              fillColor: root.tierColor(Model.memTier(fraction), root.chartAccent)
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(diskUsage.implicitHeight, diskIo.implicitHeight)

              Text {
                textFormat: Text.PlainText
                id: diskUsage
                text: Model.bytes(modelData.used) + " used  ·  " + Model.bytes(modelData.free) + " free of " + Model.bytes(modelData.total)
                color: root.dim
                font.family: root.monoFont
                font.pixelSize: root.captionTextSize
                font.features: { "tnum": 1 }
                anchors.left: parent.left
                anchors.right: diskIo.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                id: diskIo
                visible: hasIo
                text: hasIo ? "R " + Model.rate(modelData.read_bps) + "  ·  W " + Model.rate(modelData.write_bps) : ""
                color: root.dim
                font.family: root.monoFont
                font.pixelSize: root.captionTextSize
                font.features: { "tnum": 1 }
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: modelData.mounts && modelData.mounts.length > 0
              width: parent.width
              text: modelData.mounts && modelData.mounts.length > 0 ? "also " + modelData.mounts.join(", ") : ""
              color: root.faint
              font.family: root.uiFont
              font.pixelSize: root.captionTextSize
              elide: Text.ElideRight
            }
          }
        }
      }

      GlassCard {
        visible: root.snapshot && !root.anyDiskTemp && root.snapshot.nvme_temp !== null && root.snapshot.nvme_temp !== undefined
        width: parent.width
        InfoPair {
          label: "Drive temperature"
          value: root.snapshot ? Model.temp(root.snapshot.nvme_temp) : "—"
        }
      }
    }
  }

  // ======================================================= Network
  Component {
    id: netTab

    Column {
      spacing: Style.space(12)

      GlassCard {
        visible: root.hasData && root.ifaces.length === 0
        width: parent.width
        Text {
          textFormat: Text.PlainText
          text: "No network interfaces found"
          color: root.dim
          font.family: root.uiFont
          font.pixelSize: root.bodyTextSize
        }
      }

      // Interface pill switcher when multiple interfaces exist.
      Rectangle {
        visible: root.ifaces.length > 1
        width: parent.width
        height: Style.space(30)
        radius: root.controlRadius
        color: root.glassFill
        border.width: 1
        border.color: root.alpha(root.foreground, 0.12)

        GlassHighlight { inset: Style.space(6) }

        Row {
          id: ifaceRow
          anchors.fill: parent
          anchors.margins: Style.space(3)
          spacing: Style.space(3)

          readonly property int count: Math.min(root.ifaces.length, 5)
          readonly property real cellWidth: count > 0 ? (width - spacing * (count - 1)) / count : 0

          Repeater {
            model: root.ifaces.slice(0, 5)

            Item {
              id: ifaceCell
              required property var modelData
              readonly property bool activeIf: root.iface && root.iface.name === modelData.name
              width: ifaceRow.cellWidth
              height: parent.height

              Rectangle {
                anchors.fill: parent
                radius: Math.max(6, root.controlRadius - 2)
                color: ifaceCell.activeIf ? root.alpha(root.foreground, 0.14) : (ifaceMouse.containsMouse ? root.alpha(root.foreground, 0.06) : "transparent")
                border.width: ifaceCell.activeIf ? 1 : 0
                border.color: ifaceCell.activeIf ? root.alpha(root.foreground, 0.18) : "transparent"
                Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

                GlassHighlight {
                  visible: ifaceCell.activeIf
                  inset: Style.space(5)
                }
              }

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: ifaceCell.modelData.name
                color: ifaceCell.activeIf ? root.foreground : (ifaceCell.modelData.up ? root.dim : root.faint)
                font.family: root.uiFont
                font.pixelSize: root.captionTextSize
                font.weight: ifaceCell.activeIf ? Font.DemiBold : Font.Medium
              }

              MouseArea {
                id: ifaceMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectIface(ifaceCell.modelData.name)
              }
            }
          }
        }
      }

      GlassCard {
        visible: !!root.iface
        width: parent.width

        Column {
          width: parent.width
          spacing: Style.space(12)

          SectionRow {
            label: root.iface ? (root.iface.ssid || root.iface.name) : ""
            value: {
              if (!root.iface) return ""
              var bits = []
              if (root.iface.ssid) bits.push(root.iface.name)
              if (root.iface.ip) bits.push(root.iface.ip)
              if (!root.iface.up) bits.push("down")
              return bits.join("  ·  ")
            }
            valueDim: true
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            readonly property real cellWidth: (width - spacing * 3) / 4

            StatCell { width: parent.cellWidth; caption: "RECEIVING"; value: root.iface ? Model.rate(root.iface.rx_bps) : "—" }
            StatCell { width: parent.cellWidth; caption: "SENDING"; value: root.iface ? Model.rate(root.iface.tx_bps) : "—" }
            StatCell { width: parent.cellWidth; caption: "DOWNLOADED"; value: root.iface ? Model.bytes(root.iface.rx_total) : "—" }
            StatCell { width: parent.cellWidth; caption: "UPLOADED"; value: root.iface ? Model.bytes(root.iface.tx_total) : "—" }
          }

          Sparkline {
            width: parent.width
            height: Style.space(90)
            values: root.rxHistory
            values2: root.txHistory
            maxValue: 0
            lineColor: root.chartAccent
            lineColor2: root.chartSecondary
          }

          Item {
            width: parent.width
            implicitHeight: legendLeft.implicitHeight

            Row {
              id: legendLeft
              spacing: Style.space(14)
              anchors.left: parent.left

              Row {
                spacing: Style.space(6)
                Rectangle { width: Style.space(10); height: 2.5; radius: 1.25; color: root.chartAccent; anchors.verticalCenter: parent.verticalCenter }
                Text { textFormat: Text.PlainText; text: "Download"; color: root.dim; font.family: root.uiFont; font.pixelSize: root.captionTextSize; font.weight: Font.Medium }
              }
              Row {
                spacing: Style.space(6)
                Rectangle { width: Style.space(10); height: 2.5; radius: 1.25; color: root.chartSecondary; anchors.verticalCenter: parent.verticalCenter }
                Text { textFormat: Text.PlainText; text: "Upload"; color: root.dim; font.family: root.uiFont; font.pixelSize: root.captionTextSize; font.weight: Font.Medium }
              }
            }

            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              text: "Peak " + Model.rate(Math.max(Model.maxOf(root.rxHistory, 0), Model.maxOf(root.txHistory, 0)))
              color: root.dim
              font.family: root.monoFont
              font.pixelSize: root.captionTextSize
              font.features: { "tnum": 1 }
            }
          }
        }
      }

      GlassCard {
        visible: root.ifaces.length > 1
        width: parent.width

        Column {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.ifaces

            Item {
              required property var modelData
              visible: !root.iface || modelData.name !== root.iface.name
              width: parent.width
              implicitHeight: visible ? otherName.implicitHeight + Style.space(2) : 0

              Text {
                textFormat: Text.PlainText
                id: otherName
                text: modelData.name + (modelData.ip ? "  ·  " + modelData.ip : "")
                color: modelData.up ? root.foreground : root.dim
                opacity: modelData.up ? 0.85 : 0.65
                font.family: root.uiFont
                font.pixelSize: root.bodyTextSize
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: modelData.up ? "↓ " + Model.rate(modelData.rx_bps) + "   ↑ " + Model.rate(modelData.tx_bps) : "down"
                color: root.dim
                font.family: root.monoFont
                font.pixelSize: root.captionTextSize
                font.features: { "tnum": 1 }
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }
      }
    }
  }

  // ======================================================= Sensors
  Component {
    id: sensorsTab

    Column {
      spacing: Style.space(12)

      GlassCard {
        width: parent.width

        Column {
          width: parent.width
          spacing: Style.space(8)

          SectionRow {
            label: "Temperature Sensors"
            value: {
              var t = root.sensorTemps.length, f = root.sensorFans.length
              return t + (t === 1 ? " temp" : " temps") + "  ·  " + f + (f === 1 ? " fan" : " fans")
            }
            valueDim: true
          }

          Text {
            textFormat: Text.PlainText
            visible: root.hasData && root.sensorTemps.length === 0
            width: parent.width
            text: "No usable temperature sensors"
            color: root.dim
            font.family: root.uiFont
            font.pixelSize: root.bodyTextSize
          }

          Column {
            width: parent.width
            spacing: Style.space(3)

            Repeater {
              model: root.sensorTemps

              SensorRow {
                required property var modelData
                label: modelData.label
                value: modelData.temp
                maxScale: modelData.crit > 0 ? modelData.crit : 100
                reading: Model.temp(modelData.temp)
                fillColor: root.tierColor(Model.tempTier(modelData.temp, modelData.crit || 0), root.alpha(root.foreground, 0.58))
                readingColor: root.tierColor(Model.tempTier(modelData.temp, modelData.crit || 0), root.foreground)
                trailing: {
                  var parts = []
                  var pk = root.peakFor(modelData.key)
                  if (pk !== null && pk > modelData.temp + 0.5) parts.push("pk " + Model.temp(pk))
                  if (modelData.crit > 0) parts.push("max " + Model.temp(modelData.crit))
                  return parts.join(" · ")
                }
              }
            }
          }
        }
      }

      GlassCard {
        visible: root.sensorFans.length > 0
        width: parent.width

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "FANS"
            foreground: root.foreground
            fontFamily: root.uiFont
            font.letterSpacing: 0.85
          }

          Column {
            width: parent.width
            spacing: Style.space(3)

            Repeater {
              model: root.sensorFans

              SensorRow {
                required property var modelData
                label: modelData.label
                value: modelData.rpm
                maxScale: modelData.max_rpm > 0 ? modelData.max_rpm : 6000
                reading: Model.rpm(modelData.rpm)
                readingWidth: Style.space(76)
                fillColor: root.chartSecondary
                readingColor: root.foreground
              }
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: "Peaks cover the current open session only."
        color: root.faint
        font.family: root.uiFont
        font.pixelSize: root.captionTextSize
        wrapMode: Text.WordWrap
      }
    }
  }

  // ======================================================= Processes
  Component {
    id: procTabComponent

    GlassCard {
      id: procTabRoot
      cardPadding: Style.space(14)

      function scrollTo(index) { procList.positionViewAtIndex(index, ListView.Contain) }
      function scrollToEdge(toEnd) { if (toEnd) procList.positionViewAtEnd(); else procList.positionViewAtBeginning() }
      function focusFilter() { filterField.forceActiveFocus(); filterField.selectAll() }
      function clearFilterField() { filterField.text = "" }

      Component.onCompleted: filterField.text = root.filterText
      Component.onDestruction: if (root.filtering) root.filtering = false

      Column {
        width: parent.width
        spacing: Style.space(8)

        Item {
          width: parent.width
          implicitHeight: Math.max(procSummary.implicitHeight, filterField.implicitHeight)

          Text {
            textFormat: Text.PlainText
            id: procSummary
            text: root.snapshot
              ? (root.filterText !== ""
                  ? Model.count(root.sortedProcs.length) + " OF " + Model.count(root.processes.length) + " PROCESSES"
                  : Model.count(root.snapshot.procs.total) + " PROCESSES  ·  " + Model.count(root.snapshot.procs.threads) + " THREADS")
              : ""
            color: root.faint
            font.family: root.uiFont
            font.pixelSize: root.captionTextSize
            font.weight: Font.DemiBold
            font.letterSpacing: 0.9
            font.features: { "tnum": 1 }
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          TextField {
            id: filterField
            width: Style.space(180)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "Filter  ( / )"
            foreground: root.foreground
            font.family: root.uiFont
            onTextChanged: { if (text !== root.filterText) { root.filterText = text; root.procIndex = 0; root.rebuildProcs() } }
            onActiveFocusChanged: root.filtering = activeFocus
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (text !== "") root.clearFilter()
                else root.stopFiltering()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Down) {
                root.stopFiltering()
                root.cursorActive = true
                event.accepted = true
              }
            }
          }
        }

        // Column headers double as sort toggles.
        Item {
          width: parent.width
          implicitHeight: Style.space(22)

          ColumnHeader { key: "name"; text: "Name"; edgeLeft: true; anchors.left: parent.left; anchors.right: pidHeader.left; anchors.rightMargin: Style.space(8) }
          ColumnHeader { id: pidHeader; key: "pid"; text: "PID"; alignRight: true; width: Style.space(58); anchors.right: userHeader.left; anchors.rightMargin: Style.space(14) }
          ColumnHeader { id: userHeader; key: "user"; text: "User"; width: Style.space(76); anchors.right: memHeader.left; anchors.rightMargin: Style.space(8) }
          ColumnHeader { id: memHeader; key: "mem"; text: "Mem"; alignRight: true; width: Style.space(60); anchors.right: cpuHeader.left; anchors.rightMargin: Style.space(8) }
          ColumnHeader { id: cpuHeader; key: "cpu"; text: "CPU"; alignRight: true; edgeRight: true; width: Style.space(68); anchors.right: parent.right }
        }

        PanelSeparator { width: parent.width; foreground: root.foreground; strength: 0.10 }

        ListView {
          id: procList
          width: parent.width
          height: Style.space(28) * 14
          clip: true
          model: procModel
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          delegate: Item {
            id: procRow
            required property var model
            required property int index
            width: procList.width
            height: Style.space(28) + (expanded ? detailBlock.implicitHeight + Style.space(12) : 0)

            readonly property bool current: root.cursorActive && root.procIndex === index
            readonly property bool expanded: root.selectedPid === procRow.model.pid
            readonly property bool paused: procRow.model.state === "T" || procRow.model.state === "t"

            Behavior on height { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }

            Rectangle {
              anchors.fill: parent
              radius: Math.max(6, root.controlRadius - 2)
              color: procRow.expanded
                ? root.alpha(root.foreground, 0.11)
                : (procRow.current ? root.alpha(root.foreground, 0.06) : "transparent")
              border.width: procRow.expanded ? 1 : 0
              border.color: procRow.expanded ? root.alpha(root.foreground, 0.16) : "transparent"
              Behavior on color { ColorAnimation { duration: Style.duration(120) } }
              Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }
            }

            Item {
              id: rowLine
              width: parent.width
              height: Style.space(28)

              Text {
                textFormat: Text.PlainText
                text: procRow.model.name
                color: root.foreground
                font.family: root.uiFont
                font.pixelSize: root.bodyTextSize
                font.weight: procRow.expanded ? Font.DemiBold : Font.Medium
                elide: Text.ElideRight
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.right: cellPid.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                id: cellPid
                text: procRow.model.pid
                color: root.dim
                font.family: root.monoFont
                font.pixelSize: root.bodyTextSize
                font.features: { "tnum": 1 }
                horizontalAlignment: Text.AlignRight
                width: Style.space(58)
                anchors.right: cellUser.left
                anchors.rightMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                id: cellUser
                text: procRow.model.user
                color: root.dim
                font.family: root.uiFont
                font.pixelSize: root.bodyTextSize
                elide: Text.ElideRight
                width: Style.space(76)
                anchors.right: cellMem.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                id: cellMem
                text: Model.bytesShort(procRow.model.mem)
                color: root.sortKey === "mem" ? root.foreground : root.dim
                font.family: root.monoFont
                font.pixelSize: root.bodyTextSize
                font.features: { "tnum": 1 }
                horizontalAlignment: Text.AlignRight
                width: Style.space(60)
                anchors.right: cellCpu.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                id: cellCpu
                text: Model.percent(procRow.model.cpu, 1)
                color: procRow.model.cpu >= 90
                  ? root.criticalColor
                  : (procRow.model.cpu >= 50 ? root.warnColor : (root.sortKey === "cpu" ? root.foreground : root.dim))
                font.family: root.monoFont
                font.pixelSize: root.bodyTextSize
                font.bold: procRow.model.cpu >= 50
                font.features: { "tnum": 1 }
                horizontalAlignment: Text.AlignRight
                width: Style.space(60)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: { root.cursorActive = true; root.cursorFromKeys = false; root.procIndex = procRow.index }
                onClicked: {
                  root.cursorActive = true
                  root.cursorFromKeys = false
                  root.procIndex = procRow.index
                  root.toggleSelected(procRow.model.pid)
                }
              }

              PanelToolTip {
                visible: rowHover.containsMouse && !procRow.expanded && procRow.model.cmd !== ""
                text: procRow.model.cmd
                fontFamily: root.monoFont
              }
            }

            Column {
              id: detailBlock
              visible: procRow.expanded
              anchors.top: rowLine.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: procRow.model.cmd !== "" ? procRow.model.cmd : "(kernel thread)"
                color: root.dim
                font.family: root.monoFont
                font.pixelSize: root.captionTextSize
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 3
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: "PID " + procRow.model.pid + "  ·  parent " + procRow.model.ppid + "  ·  " + procRow.model.threads
                  + (procRow.model.threads === 1 ? " thread" : " threads") + "  ·  " + Model.bytes(procRow.model.mem)
                  + (procRow.paused ? "  ·  paused" : "")
                color: root.dim
                font.family: root.monoFont
                font.pixelSize: root.captionTextSize
                font.features: { "tnum": 1 }
                elide: Text.ElideRight
              }

              Row {
                spacing: Style.space(6)
                topPadding: Style.space(2)

                ActionPill { text: "Terminate"; tooltipText: "Send SIGTERM — ask it to quit"; onClicked: root.requestSignal(procRow.model, "TERM") }
                ActionPill { text: "Kill"; tooltipText: "Send SIGKILL — end it immediately"; onClicked: root.requestSignal(procRow.model, "KILL") }
                ActionPill {
                  text: procRow.paused ? "Resume" : "Pause"
                  tooltipText: procRow.paused ? "Send SIGCONT" : "Send SIGSTOP — freeze it, resumable"
                  onClicked: root.requestSignal(procRow.model, procRow.paused ? "CONT" : "STOP")
                }
                ActionPill { text: "Close"; tooltipText: "Collapse (Esc)"; onClicked: root.selectedPid = -1 }
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------- components

  // Whisper-quiet 1px top-edge inner specular catchlight for architectural glass surfaces.
  component GlassHighlight: Rectangle {
    property real inset: Style.space(8)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: inset
    anchors.rightMargin: inset
    anchors.topMargin: 1
    height: 1
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: "transparent" }
      GradientStop { position: 0.14; color: root.specularTop }
      GradientStop { position: 0.86; color: root.specularTop }
      GradientStop { position: 1.0; color: "transparent" }
    }
  }

  // Unified translucent dark frosted-glass card matching ~/.config/omarchy/shell.toml.
  component GlassCard: Rectangle {
    id: glassCard
    property int cardPadding: Style.space(16)
    default property alias innerChildren: innerBox.data

    radius: root.cardRadius
    color: root.glassFill
    border.width: 1
    border.color: root.glassBorder
    implicitHeight: innerBox.implicitHeight + cardPadding * 2

    GlassHighlight { inset: Math.max(6, Math.round(glassCard.radius * 0.7)) }

    Column {
      id: innerBox
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: glassCard.cardPadding
    }
  }

  component ActionPill: Button {
    fontSize: root.captionTextSize
    foreground: root.foreground
    fontFamily: root.uiFont
    horizontalPadding: Style.space(10)
    verticalPadding: Style.space(4)
    bordered: true
  }

  component SectionRow: Item {
    property string label: ""
    property string value: ""
    property bool valueDim: false

    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(sectionLabel.implicitHeight, sectionValue.implicitHeight)

    Text {
      textFormat: Text.PlainText
      id: sectionLabel
      text: label
      color: root.foreground
      font.family: root.uiFont
      font.pixelSize: Math.max(13, root.bodyTextSize + 1)
      font.weight: Font.DemiBold
      font.letterSpacing: -0.15
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.right: sectionValue.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      textFormat: Text.PlainText
      id: sectionValue
      text: value
      color: valueDim ? root.dim : root.foreground
      font.family: root.monoFont
      font.pixelSize: valueDim ? root.captionTextSize : root.bodyTextSize
      font.bold: !valueDim
      font.features: { "tnum": 1 }
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // Pill-rounded horizontal meter without per-tick animation overhead.
  component Meter: Item {
    id: meter
    property real value: 0
    property real thickness: Style.space(6)
    property color fillColor: root.chartAccent

    width: parent ? parent.width : implicitWidth
    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.alpha(root.foreground, 0.09)
      border.width: 1
      border.color: root.alpha(root.foreground, 0.12)
    }

    Rectangle {
      readonly property real clamped: root.clamp(meter.value, 0, 1)
      visible: clamped > 0
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: Math.max(height, meterTrack.width * clamped)
      color: meter.fillColor
    }
  }

  component ShareRow: Item {
    id: shareRow
    property string label: ""
    property real amount: 0
    property real total: 1
    property bool strong: false

    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(shareLabel.implicitHeight, shareValue.implicitHeight) + Style.spacing.sm

    Text {
      textFormat: Text.PlainText
      id: shareLabel
      text: shareRow.label
      color: shareRow.strong ? root.foreground : root.dim
      font.family: root.uiFont
      font.pixelSize: root.captionTextSize
      font.weight: shareRow.strong ? Font.DemiBold : Font.Normal
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(76)
    }

    Rectangle {
      anchors.left: shareLabel.right
      anchors.right: shareValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Style.space(5)
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * root.clamp(shareRow.total > 0 ? shareRow.amount / shareRow.total : 0, 0, 1)
        color: shareRow.strong ? root.chartAccent : root.alpha(root.foreground, 0.52)
      }
    }

    Text {
      textFormat: Text.PlainText
      id: shareValue
      text: Model.bytes(shareRow.amount)
      color: shareRow.strong ? root.foreground : root.dim
      font.family: root.monoFont
      font.pixelSize: root.captionTextSize
      font.bold: shareRow.strong
      font.features: { "tnum": 1 }
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(70)
    }
  }

  component SensorRow: Item {
    id: sensorRow
    property string label: ""
    property real value: 0
    property real maxScale: 100
    property string reading: ""
    property string trailing: ""
    property real readingWidth: Style.space(52)
    property color fillColor: root.alpha(root.foreground, 0.55)
    property color readingColor: root.foreground

    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(sensorLabel.implicitHeight, sensorReading.implicitHeight) + Style.spacing.sm

    Text {
      textFormat: Text.PlainText
      id: sensorLabel
      text: sensorRow.label
      color: root.dim
      font.family: root.uiFont
      font.pixelSize: root.captionTextSize
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(126)
    }

    Rectangle {
      anchors.left: sensorLabel.right
      anchors.right: sensorReading.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Style.space(5)
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * root.clamp(sensorRow.maxScale > 0 ? sensorRow.value / sensorRow.maxScale : 0, 0, 1)
        color: sensorRow.fillColor
      }
    }

    Text {
      textFormat: Text.PlainText
      id: sensorReading
      text: sensorRow.reading
      color: sensorRow.readingColor
      font.family: root.monoFont
      font.pixelSize: root.captionTextSize
      font.bold: true
      font.features: { "tnum": 1 }
      horizontalAlignment: Text.AlignRight
      anchors.right: sensorTrailing.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: sensorRow.readingWidth
    }

    Text {
      textFormat: Text.PlainText
      id: sensorTrailing
      text: sensorRow.trailing
      color: root.faint
      font.family: root.monoFont
      font.pixelSize: root.captionTextSize
      font.features: { "tnum": 1 }
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(124)
    }
  }

  component StatCell: Rectangle {
    id: statTile
    property string caption: ""
    property string value: ""

    radius: root.controlRadius
    color: root.wellFill
    border.width: 1
    border.color: root.wellBorder
    implicitHeight: statCol.implicitHeight + Style.space(16)

    GlassHighlight { inset: Style.space(5) }

    Column {
      id: statCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(8)
      spacing: Style.space(4)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: statTile.caption
        color: root.faint
        font.family: root.uiFont
        font.pixelSize: Math.max(9, root.captionTextSize - 1)
        font.weight: Font.DemiBold
        font.letterSpacing: 0.9
        elide: Text.ElideRight
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: statTile.value
        color: root.foreground
        font.family: root.monoFont
        font.pixelSize: Math.max(13, root.bodyTextSize + 1)
        font.bold: true
        font.features: { "tnum": 1 }
        elide: Text.ElideRight
      }
    }
  }

  component ColumnHeader: Item {
    id: header
    property string key: ""
    property string text: ""
    property bool alignRight: false
    property bool edgeLeft: false
    property bool edgeRight: false
    readonly property bool activeSort: root.sortKey === key

    height: parent ? parent.height : Style.space(22)

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: header.alignRight ? undefined : parent.left
      anchors.leftMargin: header.edgeLeft ? Style.space(8) : 0
      anchors.right: header.alignRight ? parent.right : undefined
      anchors.rightMargin: header.edgeRight ? Style.space(8) : 0
      text: header.text.toUpperCase() + (header.activeSort ? (root.sortReverse ? " ▲" : " ▼") : "")
      color: header.activeSort || headerHover.containsMouse ? root.foreground : root.faint
      font.family: root.uiFont
      font.pixelSize: Math.max(9, root.captionTextSize - 1)
      font.weight: Font.DemiBold
      font.letterSpacing: 0.9
      Behavior on color { ColorAnimation { duration: Style.duration(100) } }
    }

    MouseArea {
      id: headerHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.setSort(header.key)
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      id: pairLabel
      text: label
      color: root.dim
      font.family: root.uiFont
      font.pixelSize: root.bodyTextSize
    }
    Item { width: Math.max(0, parent.width - pairLabel.implicitWidth - pairValue.implicitWidth - parent.spacing * 2); height: 1 }
    Text {
      textFormat: Text.PlainText
      id: pairValue
      text: value
      color: root.foreground
      font.family: root.monoFont
      font.pixelSize: root.bodyTextSize
      font.weight: Font.Medium
      font.features: { "tnum": 1 }
    }
  }

  // Smooth antialiased sparkline framed in a recessed glass well.
  component Sparkline: Rectangle {
    id: sparkBox
    property var values: []
    property var values2: []
    property real maxValue: 100
    property color lineColor: root.chartAccent
    property color lineColor2: root.chartSecondary
    property bool fitAvailable: false

    radius: root.controlRadius
    color: root.wellFill
    border.width: 1
    border.color: root.wellBorder

    Canvas {
      id: spark
      anchors.fill: parent
      anchors.margins: Style.space(8)
      antialiasing: true

      Connections {
        target: sparkBox
        function onValuesChanged() { spark.requestPaint() }
        function onValues2Changed() { spark.requestPaint() }
        function onLineColorChanged() { spark.requestPaint() }
        function onLineColor2Changed() { spark.requestPaint() }
      }
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()

      onPaint: {
        var ctx = getContext("2d")
        var w = width, h = height
        if (w <= 2 || h <= 2) return
        ctx.reset()

        var cap = root.historyLength
        var pad = 4
        var inner = Math.max(1, h - pad * 2)
        var peak = sparkBox.maxValue > 0 ? sparkBox.maxValue : Math.max(Model.maxOf(sparkBox.values, 0), Model.maxOf(sparkBox.values2, 0))
        if (peak <= 0) peak = 1

        // Subtle dashed mid & baseline gridlines.
        ctx.save()
        ctx.strokeStyle = Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.11)
        ctx.lineWidth = 1
        if (ctx.setLineDash) ctx.setLineDash([2, 3])
        for (let r = 1; r <= 2; r++) {
          const gy = Math.round(pad + r * inner / 2) + 0.5
          ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
        }
        ctx.restore()

        function drawSeries(vals, c, alphaLine, alphaTop) {
          const n = vals.length
          if (n < 2) return
          const step = (w - 4) / Math.max(1, (sparkBox.fitAvailable ? n : cap) - 1)
          const xs = [], ys = []
          for (let i = 0; i < n; i++) {
            xs.push((w - 4) - (n - 1 - i) * step)
            ys.push(pad + (1 - root.clamp(vals[i] / peak, 0, 1)) * inner)
          }

          function traceSmooth() {
            ctx.moveTo(xs[0], ys[0])
            if (n === 2) { ctx.lineTo(xs[1], ys[1]); return }
            for (let j = 1; j < n - 1; j++) {
              ctx.quadraticCurveTo(xs[j], ys[j], (xs[j] + xs[j + 1]) * 0.5, (ys[j] + ys[j + 1]) * 0.5)
            }
            ctx.lineTo(xs[n - 1], ys[n - 1])
          }

          var fill = ctx.createLinearGradient(0, pad, 0, pad + inner)
          fill.addColorStop(0.0, Qt.rgba(c.r, c.g, c.b, alphaTop))
          fill.addColorStop(1.0, Qt.rgba(c.r, c.g, c.b, 0.005))

          ctx.beginPath()
          traceSmooth()
          ctx.lineTo(xs[n - 1], pad + inner)
          ctx.lineTo(xs[0], pad + inner)
          ctx.closePath()
          ctx.fillStyle = fill
          ctx.fill()

          ctx.beginPath()
          traceSmooth()
          ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, alphaLine)
          ctx.lineWidth = 1.9
          ctx.lineCap = "round"
          ctx.lineJoin = "round"
          ctx.stroke()
        }

        drawSeries(sparkBox.values2 || [], sparkBox.lineColor2, 0.65, 0.12)
        drawSeries(sparkBox.values || [], sparkBox.lineColor, 0.96, 0.24)
      }
    }
  }
}
