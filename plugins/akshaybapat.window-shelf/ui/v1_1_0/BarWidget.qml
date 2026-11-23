pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "../../../akshaybapat.workspace-windows/ui/v1_1_0/WindowIcons.js" as WindowIcons

Ui.BarWidget {
  id: root

  moduleName: "akshaybapat.window-shelf"

  readonly property var desktopApplications: DesktopEntries.applications.values
  readonly property var iconLibrary: root.bar && root.bar.shell ? root.bar.shell.appLibrary : null

  readonly property string shelfWorkspace: "special:omarchy-minimized"
  readonly property string peekWorkspace: "special:omarchy-window-peek"
  readonly property int maxTitleLength: Math.max(4, Number(root.setting("maxTitleLength", 18)))
  // Chips are icons by default: the bar is not the place for cut-off titles.
  // The title lives in the tooltip and the peek; showTitles brings it back.
  readonly property bool showTitles: root.setting("showTitles", false) === true
  readonly property int maxChipWidth: Math.max(Style.space(80), Number(root.setting("maxChipWidth", Style.space(180))))
  readonly property int previewDelay: Math.max(0, Number(root.setting("previewDelay", 350)))
  readonly property int peekWidth: Math.max(Style.space(320), Number(root.setting("peekWidth", 960)))
  readonly property int peekHeight: Math.max(Style.space(240), Number(root.setting("peekHeight", 640)))

  property var allToplevels: Hyprland.toplevels.values
  property var activeWindow: Hyprland.activeToplevel
  readonly property var minimizedWindows: (root.allToplevels || []).filter(function(toplevel) {
    return root.isManaged(toplevel)
  })

  readonly property color barFg: root.bar ? root.bar.barForeground : Commons.Color.foreground
  readonly property color accentColor: Commons.Color.accent
  readonly property string monoFont: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property string uiFont: (Style.font.menuFamily && Style.font.menuFamily !== Style.font.family && Style.font.menuFamily !== "monospace")
    ? Style.font.menuFamily
    : "Inter Display"

  // One button, two jobs. Focus on an ordinary window means the next click parks
  // it; anything else - nothing focused, a parked window, any other special
  // workspace - means the next click brings a window back. The glyph says which.
  readonly property bool canMinimize: root.activeWindow !== null && !root.isSpecial(root.activeWindow)
  readonly property var restoreTarget: root.canMinimize ? null : root.nextRestore()
  readonly property bool canRestore: root.restoreTarget !== null
  // Addresses of the windows this widget parked, most recent first. Hyprland
  // orders toplevels by creation, not by when they were minimized, so recency
  // is ours to remember. It lives only in memory: a shell restart falls back to
  // Hyprland's own focus history below.
  property var shelfOrder: []
  property var pendingPreviewToplevel: null
  property Item pendingPreviewAnchor: null
  property var previewToplevel: null
  property Item previewAnchor: null
  property var peekToplevel: null
  property var pendingPeekToplevel: null
  property string peekOriginWorkspace: ""
  property bool peekVisible: false
  property bool peekWasFloating: false
  property int peekOriginalFullscreen: 0
  property var peekOriginalSize: null
  property var peekOriginalPosition: null
  property string hoveredAddressOverride: ""
  readonly property bool peekTransitionRunning: peekProcess.running || peekVisibilityProcess.running

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  function isMinimized(toplevel) {
    return toplevel !== null && toplevel.workspace !== null
      && toplevel.workspace.name === root.shelfWorkspace
  }

  function isPeeked(toplevel) {
    return toplevel !== null && toplevel.workspace !== null
      && toplevel.workspace.name === root.peekWorkspace
  }

  function isManaged(toplevel) {
    return root.isMinimized(toplevel) || root.isPeeked(toplevel)
  }

  function isSpecial(toplevel) {
    return toplevel !== null && toplevel.workspace !== null
      && String(toplevel.workspace.name).indexOf("special:") === 0
  }

  // Newest first, and never twice: minimizing a window that is already on the
  // stack (parked, restored from its chip, parked again) moves it back to front.
  function rememberMinimized(toplevel) {
    var address = root.normalizedAddress(toplevel)
    if (!address) return
    var next = [address]
    for (var i = 0; i < root.shelfOrder.length; i++) {
      if (root.shelfOrder[i] !== address) next.push(root.shelfOrder[i])
    }
    root.shelfOrder = next
  }

  // Drop addresses that are no longer parked - restored from a chip, or closed
  // while minimized - so the button never aims at a window that is gone.
  function forgetVanished() {
    var parked = {}
    for (var i = 0; i < root.minimizedWindows.length; i++) {
      var address = root.normalizedAddress(root.minimizedWindows[i])
      if (address) parked[address] = true
    }
    var next = []
    for (var j = 0; j < root.shelfOrder.length; j++) {
      if (parked[root.shelfOrder[j]]) next.push(root.shelfOrder[j])
    }
    if (next.length !== root.shelfOrder.length) root.shelfOrder = next
  }

  function parkedByAddress(address) {
    for (var i = 0; i < root.minimizedWindows.length; i++) {
      if (root.normalizedAddress(root.minimizedWindows[i]) === address) return root.minimizedWindows[i]
    }
    return null
  }

  // Hyprland's focus history: 0 is the most recently focused client. Parking a
  // window requires focusing it first, so among parked windows the lowest rank
  // is the one parked (or peeked into) last. This is the fallback for windows
  // this widget did not park itself, such as those parked before a shell restart.
  function focusRank(toplevel) {
    var ipc = toplevel ? toplevel.lastIpcObject : null
    var raw = ipc ? ipc.focusHistoryID : undefined
    if (raw === undefined || raw === null) return Number.MAX_VALUE
    var rank = Number(raw)
    return isNaN(rank) ? Number.MAX_VALUE : rank
  }

  function nextRestore() {
    if (root.minimizedWindows.length === 0) return null
    // Peeked and focused: bring back the window you are already looking at.
    if (root.activeWindow !== null && root.isManaged(root.activeWindow)) return root.activeWindow
    for (var i = 0; i < root.shelfOrder.length; i++) {
      var remembered = root.parkedByAddress(root.shelfOrder[i])
      if (remembered) return remembered
    }
    var best = null
    var bestRank = Number.MAX_VALUE
    for (var j = 0; j < root.minimizedWindows.length; j++) {
      var rank = root.focusRank(root.minimizedWindows[j])
      if (rank <= bestRank) {
        best = root.minimizedWindows[j]
        bestRank = rank
      }
    }
    return best
  }

  function normalizedAddress(toplevel) {
    if (!toplevel || !toplevel.address) return ""
    var address = String(toplevel.address)
    return address.indexOf("0x") === 0 ? address : "0x" + address
  }

  function moveRequest(toplevel, workspace, follow) {
    var address = root.normalizedAddress(toplevel)
    if (!address || !workspace) return ""
    return "hl.dsp.window.move({ workspace = " + JSON.stringify(workspace)
      + ", window = " + JSON.stringify("address:" + address)
      + ", follow = " + (follow ? "true" : "false") + " })"
  }

  function moveWindow(toplevel, workspace, follow) {
    var request = root.moveRequest(toplevel, workspace, follow)
    if (!request) return
    Quickshell.execDetached(["hyprctl", "dispatch", request])
  }

  function windowFloatRequest(toplevel, action) {
    var address = root.normalizedAddress(toplevel)
    if (!address) return ""
    return "hl.dsp.window.float({ action = " + JSON.stringify(action)
      + ", window = " + JSON.stringify("address:" + address) + " })"
  }

  function windowResizeRequest(toplevel, width, height) {
    var address = root.normalizedAddress(toplevel)
    if (!address) return ""
    return "hl.dsp.window.resize({ x = " + Math.round(width) + ", y = " + Math.round(height)
      + ", window = " + JSON.stringify("address:" + address) + " })"
  }

  function windowPositionRequest(toplevel, x, y) {
    var address = root.normalizedAddress(toplevel)
    if (!address) return ""
    return "hl.dsp.window.move({ x = " + Math.round(x) + ", y = " + Math.round(y)
      + ", relative = false, window = " + JSON.stringify("address:" + address) + " })"
  }

  function windowCenterRequest(toplevel) {
    var address = root.normalizedAddress(toplevel)
    if (!address) return ""
    return "hl.dsp.window.center({ window = " + JSON.stringify("address:" + address) + " })"
  }

  function windowFullscreenRequest(toplevel, fullscreenMode) {
    var address = root.normalizedAddress(toplevel)
    if (!address || fullscreenMode <= 0) return ""
    var mode = fullscreenMode === 1 ? "maximized" : "fullscreen"
    return "hl.dsp.window.fullscreen({ mode = " + JSON.stringify(mode)
      + ", window = " + JSON.stringify("address:" + address) + " })"
  }

  function minimizeActive() {
    if (!root.canMinimize) return
    root.rememberMinimized(root.activeWindow)
    root.moveWindow(root.activeWindow, root.shelfWorkspace, false)
  }

  function restoreNext() {
    var target = root.restoreTarget
    if (!target) return
    root.cancelPreview(target)
    root.restore(target)
  }

  function toggleShelf() {
    if (root.canMinimize) root.minimizeActive()
    else root.restoreNext()
  }

  function restore(toplevel) {
    var workspace = Hyprland.focusedWorkspace
    // While a special workspace is showing, the window comes back to the
    // ordinary workspace underneath it on the focused monitor.
    var monitor = Hyprland.focusedMonitor
    var underneath = monitor && monitor.activeWorkspace
      && String(monitor.activeWorkspace.name).indexOf("special:") !== 0
      ? monitor.activeWorkspace.name : ""
    var destination = workspace && String(workspace.name).indexOf("special:") !== 0
      ? workspace.name : (root.peekOriginWorkspace || underneath)
    if (!destination) return
    if (root.peekToplevel === toplevel || root.isPeeked(toplevel)) {
      if (root.peekTransitionRunning) return
      root.peekVisible = false
      root.runPeekCommand(["hyprctl", "dispatch", root.moveRequest(toplevel, destination, true)], "restore-move")
    } else {
      root.moveWindow(toplevel, destination, true)
    }
  }

  function runPeekCommand(command, action) {
    if (root.peekTransitionRunning || !command || command.length === 0) return false
    peekProcess.action = action
    peekProcess.command = command
    peekProcess.running = true
    return true
  }

  function togglePeek(toplevel) {
    if (!toplevel || root.peekTransitionRunning) return
    root.cancelPreview(toplevel)
    if (root.peekToplevel === toplevel || root.isPeeked(toplevel)) {
      root.closePeek(toplevel)
      return
    }
    if (root.peekToplevel) {
      root.pendingPeekToplevel = toplevel
      root.closePeek(root.peekToplevel)
      return
    }

    var workspace = Hyprland.focusedWorkspace
    if (!workspace || String(workspace.name).indexOf("special:") === 0) return
    root.peekToplevel = toplevel
    root.peekOriginWorkspace = workspace.name
    root.peekVisible = false
    var ipc = toplevel.lastIpcObject || null
    root.peekWasFloating = !!(ipc && ipc.floating)
    root.peekOriginalFullscreen = Number(ipc && ipc.fullscreen ? ipc.fullscreen : 0)
    root.peekOriginalSize = ipc && Array.isArray(ipc.size) ? ipc.size.slice(0, 2) : null
    root.peekOriginalPosition = ipc && Array.isArray(ipc.at) ? ipc.at.slice(0, 2) : null
    root.runPeekCommand(["hyprctl", "dispatch", root.moveRequest(toplevel, root.peekWorkspace, false)], "show-move")
  }

  function closePeek(toplevel) {
    var target = toplevel || root.peekToplevel
    if (!target || root.peekTransitionRunning) return
    root.peekVisible = false
    root.runPeekCommand(["hyprctl", "dispatch", root.moveRequest(target, root.shelfWorkspace, false)], "hide-move")
  }

  function clearPeekState() {
    root.peekToplevel = null
    root.peekOriginWorkspace = ""
    root.peekVisible = false
    root.peekWasFloating = false
    root.peekOriginalFullscreen = 0
    root.peekOriginalSize = null
    root.peekOriginalPosition = null
  }

  function runPeekToggle(action) {
    root.runPeekCommand(["hyprctl", "dispatch",
      "hl.dsp.workspace.toggle_special(\"omarchy-window-peek\")"], action)
  }

  function runPeekVisibilityCheck(kind) {
    if (root.peekTransitionRunning) return false
    peekVisibilityProcess.kind = kind
    peekVisibilityProcess.running = true
    return true
  }

  function peekWorkspaceIsVisible(raw) {
    try {
      var monitors = JSON.parse(String(raw || ""))
      for (var i = 0; i < monitors.length; i++) {
        var special = monitors[i] ? monitors[i].specialWorkspace : null
        if (special && special.name === root.peekWorkspace) return true
      }
    } catch (exception) {
      console.warn("window-shelf: could not inspect Peek workspace visibility", exception)
    }
    return false
  }

  function finishPeekVisibilityCheck(kind, exitCode, output) {
    if (exitCode === 0 && root.peekWorkspaceIsVisible(output)) {
      Qt.callLater(function() { root.runPeekToggle(kind + "-toggle") })
    } else {
      root.finalizePeek()
    }
  }

  function finalizePeek() {
    root.clearPeekState()
    if (root.pendingPeekToplevel) {
      var next = root.pendingPeekToplevel
      root.pendingPeekToplevel = null
      Qt.callLater(function() { root.togglePeek(next) })
    }
  }

  function completePeekExit(kind) {
    if (root.peekOriginalFullscreen > 0) {
      root.runPeekCommand(["hyprctl", "dispatch",
        root.windowFullscreenRequest(root.peekToplevel, root.peekOriginalFullscreen)], kind + "-fullscreen")
    } else {
      root.runPeekVisibilityCheck(kind)
    }
  }

  function finishPeekExit(kind) {
    if (!root.peekToplevel) {
      root.clearPeekState()
      return
    }
    if (!root.peekWasFloating) {
      root.runPeekCommand(["hyprctl", "dispatch", root.windowFloatRequest(root.peekToplevel, "off")], kind + "-float")
    } else if (root.peekOriginalSize && root.peekOriginalSize.length === 2) {
      root.runPeekCommand(["hyprctl", "dispatch", root.windowResizeRequest(root.peekToplevel,
        root.peekOriginalSize[0], root.peekOriginalSize[1])], kind + "-resize")
    } else {
      root.completePeekExit(kind)
    }
  }

  function finishPeekResize(kind) {
    if (root.peekOriginalPosition && root.peekOriginalPosition.length === 2) {
      root.runPeekCommand(["hyprctl", "dispatch", root.windowPositionRequest(root.peekToplevel,
        root.peekOriginalPosition[0], root.peekOriginalPosition[1])], kind + "-position")
    } else {
      root.completePeekExit(kind)
    }
  }

  function finishPeekCommand(action, exitCode) {
    if (exitCode !== 0) {
      var failedTarget = root.peekToplevel
      root.clearPeekState()
      if (failedTarget && action.indexOf("show-") === 0) root.moveWindow(failedTarget, root.shelfWorkspace, false)
      return
    }

    if (action === "show-move") {
      Qt.callLater(function() {
        if (root.peekOriginalFullscreen > 0) {
          root.runPeekCommand(["hyprctl", "dispatch",
            root.windowFullscreenRequest(root.peekToplevel, root.peekOriginalFullscreen)], "show-fullscreen")
        } else {
          root.runPeekCommand(["hyprctl", "dispatch",
            root.windowFloatRequest(root.peekToplevel, "on")], "show-float")
        }
      })
    } else if (action === "show-fullscreen") {
      Qt.callLater(function() {
        root.runPeekCommand(["hyprctl", "dispatch",
          root.windowFloatRequest(root.peekToplevel, "on")], "show-float")
      })
    } else if (action === "show-float") {
      Qt.callLater(function() {
        root.runPeekCommand(["hyprctl", "dispatch",
          root.windowResizeRequest(root.peekToplevel, root.peekWidth, root.peekHeight)], "show-resize")
      })
    } else if (action === "show-resize") {
      Qt.callLater(function() {
        root.runPeekCommand(["hyprctl", "dispatch",
          root.windowCenterRequest(root.peekToplevel)], "show-center")
      })
    } else if (action === "show-center") {
      Qt.callLater(function() { root.runPeekToggle("show-toggle") })
    } else if (action === "show-toggle") {
      root.peekVisible = true
    } else if (action === "hide-move" || action === "restore-move") {
      var exitKind = action === "hide-move" ? "hide" : "restore"
      Qt.callLater(function() { root.finishPeekExit(exitKind) })
    } else if (action === "hide-resize" || action === "restore-resize") {
      var resizeKind = action === "hide-resize" ? "hide" : "restore"
      Qt.callLater(function() { root.finishPeekResize(resizeKind) })
    } else if (action === "hide-position" || action === "restore-position"
        || action === "hide-float" || action === "restore-float") {
      var stateKind = action.indexOf("hide-") === 0 ? "hide" : "restore"
      Qt.callLater(function() { root.completePeekExit(stateKind) })
    } else if (action === "hide-fullscreen" || action === "restore-fullscreen") {
      var fullscreenKind = action.indexOf("hide-") === 0 ? "hide" : "restore"
      Qt.callLater(function() { root.runPeekVisibilityCheck(fullscreenKind) })
    } else if (action === "hide-toggle" || action === "restore-toggle") {
      root.finalizePeek()
    } else if (action === "external-toggle") {
      root.finalizePeek()
    }
  }

  function handleFocusedWorkspaceChanged() {
    if (!root.peekToplevel || !root.peekVisible || root.peekTransitionRunning) return
    var workspace = Hyprland.focusedWorkspace
    if (workspace && workspace.name !== root.peekWorkspace) root.closePeek(root.peekToplevel)
  }

  function windowTitle(toplevel) {
    var title = String(toplevel && toplevel.title ? toplevel.title : "Window").trim()
    if (title.length <= root.maxTitleLength) return title
    return title.substring(0, root.maxTitleLength - 3) + "…"
  }

  function verticalLabel(toplevel) {
    var ipc = toplevel ? toplevel.lastIpcObject : null
    var app = String(ipc && ipc.class ? ipc.class : root.windowTitle(toplevel)).trim()
    return app.length > 0 ? app.charAt(0).toUpperCase() : "W"
  }

  function desktopEntry(toplevel) {
    return WindowIcons.lookup(toplevel, root.desktopApplications, function(candidate) {
      return DesktopEntries.heuristicLookup(candidate)
    })
  }

  function windowIcon(toplevel) {
    if (toplevel && toplevel.iconOverride) return String(toplevel.iconOverride)
    var entry = root.desktopEntry(toplevel)
    var icon = String(entry ? (entry.icon || entry.id || "") : "")
    if (root.iconLibrary && typeof root.iconLibrary.iconSource === "function")
      return root.iconLibrary.iconSource(icon)
    if (icon.indexOf("file://") === 0 || icon.indexOf("image://") === 0) return icon
    if (icon.charAt(0) === "/") return Util.fileUrl(icon)
    return Quickshell.iconPath(icon || "application-x-executable", "application-x-executable")
  }

  function requestPreview(anchor, toplevel) {
    root.pendingPreviewAnchor = anchor
    root.pendingPreviewToplevel = toplevel
    previewTimer.restart()
  }

  function cancelPreview(toplevel) {
    if (root.pendingPreviewToplevel === toplevel) {
      previewTimer.stop()
      root.pendingPreviewAnchor = null
      root.pendingPreviewToplevel = null
    }
    if (root.previewToplevel === toplevel) {
      root.previewToplevel = null
      root.previewAnchor = null
    }
  }

  onMinimizedWindowsChanged: {
    root.forgetVanished()
    if (root.previewToplevel && !root.isManaged(root.previewToplevel)) root.cancelPreview(root.previewToplevel)
    if (root.peekToplevel && !root.peekTransitionRunning && root.peekVisible
        && (!root.isManaged(root.peekToplevel) || !root.isPeeked(root.peekToplevel))) {
      root.peekVisible = false
      if (root.isMinimized(root.peekToplevel)) root.finishPeekExit("hide")
      else root.runPeekVisibilityCheck("external")
    } else if (root.peekToplevel && !root.isManaged(root.peekToplevel) && !root.peekTransitionRunning) {
      root.clearPeekState()
    }
  }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { root.handleFocusedWorkspaceChanged() }
  }

  Process {
    id: peekProcess
    property string action: ""
    onExited: function(exitCode) {
      var completedAction = action
      action = ""
      root.finishPeekCommand(completedAction, exitCode)
    }
  }

  Process {
    id: peekVisibilityProcess
    property string kind: ""
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector {
      id: peekVisibilityOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var completedKind = kind
      kind = ""
      root.finishPeekVisibilityCheck(completedKind, exitCode, peekVisibilityOutput.text)
    }
  }

  Timer {
    id: previewTimer
    interval: root.previewDelay
    onTriggered: {
      root.previewAnchor = root.pendingPreviewAnchor
      root.previewToplevel = root.pendingPreviewToplevel
      root.pendingPreviewAnchor = null
      root.pendingPreviewToplevel = null
    }
  }

  GridLayout {
    id: layout

    columns: root.vertical ? 1 : root.minimizedWindows.length + 1
    columnSpacing: root.vertical ? 0 : Style.space(4)
    rowSpacing: root.vertical ? Style.space(3) : 0

    // One button, both directions: sits in the exact 26 px bar rhythm with a
    // subtle frosted glass capsule on hover/restore-ready state.
    Ui.BarIconButton {
      id: shelfButton

      bar: root.bar
      fontFamily: root.monoFont
      text: root.canRestore ? "󰖲" : "\u{F06F2}"
      dimmed: !root.canMinimize && !root.canRestore
      interactive: root.canMinimize || root.canRestore
      tooltipText: root.canMinimize ? "Minimize the focused window"
        : (root.canRestore
          ? "Restore " + String((root.restoreTarget && root.restoreTarget.title) || "window")
          : "Nothing to minimize or restore")
      onPressed: function(button) {
        if (button === Qt.LeftButton) root.toggleShelf()
      }

      Rectangle {
        id: shelfBtnGlass
        z: -1
        anchors.centerIn: parent
        width: root.vertical
          ? Math.min(parent.width - Style.space(4), Style.space(22))
          : Math.max(Style.space(22), parent.width - Style.space(2))
        height: root.vertical
          ? Math.max(Style.space(22), parent.height - Style.space(2))
          : Math.min(parent.height - Style.space(4), Style.space(22))
        radius: Math.max(6, Math.min(Math.round(Math.min(width, height) / 2), Style.cornerRadius > 0 ? Style.cornerRadius - 3 : 0))
        color: shelfButton.tooltipHovered
          ? Util.alpha(root.barFg, 0.10)
          : (root.canRestore ? Util.alpha(root.barFg, 0.05) : "transparent")
        border.width: (shelfButton.tooltipHovered || root.canRestore) ? Style.spacing.hairline : 0
        border.color: shelfButton.tooltipHovered
          ? Util.alpha(root.barFg, 0.22)
          : (root.canRestore ? Util.alpha(root.barFg, 0.12) : "transparent")

        Behavior on color { ColorAnimation { duration: Style.duration(140) } }
        Behavior on border.color { ColorAnimation { duration: Style.duration(140) } }

        Rectangle {
          visible: (shelfButton.tooltipHovered || root.canRestore) && shelfBtnGlass.radius > 0
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: 1
          anchors.leftMargin: Math.round(shelfBtnGlass.radius * 0.6)
          anchors.rightMargin: Math.round(shelfBtnGlass.radius * 0.6)
          height: 1
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, shelfButton.tooltipHovered ? 0.20 : 0.12) }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }
      }
    }

    Repeater {
      model: root.minimizedWindows

      Ui.WidgetButton {
        id: chip

        required property var modelData
        readonly property int iconExtent: Style.bar.iconCanvas
        readonly property string iconSource: root.windowIcon(chip.modelData)
        readonly property bool peeked: root.isPeeked(chip.modelData)
        readonly property bool hot: chip.tooltipHovered
          || (root.hoveredAddressOverride !== "" && root.hoveredAddressOverride === root.normalizedAddress(chip.modelData))
        readonly property int titleOverhead: Style.space(18) + chip.iconExtent + Style.space(6) + (chip.peeked ? Style.space(11) : 0)

        TextMetrics {
          id: titleMetrics
          font.family: root.uiFont
          font.pixelSize: Style.font.bodySmall
          font.weight: Font.Medium
          text: root.windowTitle(chip.modelData)
        }

        bar: root.bar
        text: ""
        keepSpace: true
        hasVisualContent: true
        labelVisible: false
        fixedWidth: root.vertical ? root.barSize
          : (root.showTitles
            ? Math.min(root.maxChipWidth, Math.ceil(titleMetrics.advanceWidth) + chip.titleOverhead)
            : (chip.peeked ? Style.bar.iconSlot + Style.space(10) : Math.max(Style.bar.iconSlot, Style.space(28))))
        fixedHeight: root.barSize
        clip: false
        tooltipText: String(chip.modelData.title || "Window")
          + (chip.peeked ? " · click to restore, right-click to close Peek"
            : " · click to restore, right-click to Peek")
        onTooltipHoveredChanged: {
          if (chip.tooltipHovered && root.isMinimized(chip.modelData)) root.requestPreview(chip, chip.modelData)
          else root.cancelPreview(chip.modelData)
        }
        onPressed: function(button) {
          if (button === Qt.LeftButton) {
            root.cancelPreview(chip.modelData)
            root.restore(chip.modelData)
          } else if (button === Qt.RightButton) {
            root.togglePeek(chip.modelData)
          }
        }

        // Frosted glass shelf pill centered cleanly inside the exact 26 px bar height.
        Rectangle {
          id: chipPill
          anchors.centerIn: parent
          width: root.vertical ? Math.min(parent.width - Style.space(4), Style.space(22)) : parent.width
          height: root.vertical ? Math.max(Style.space(22), parent.height - Style.space(2)) : Math.min(parent.height - Style.space(4), Style.space(22))
          radius: Math.max(6, Math.min(Math.round(Math.min(width, height) / 2), Style.cornerRadius > 0 ? Style.cornerRadius - 3 : 0))
          color: chip.peeked
            ? Util.alpha(root.accentColor, chip.hot ? 0.24 : 0.18)
            : (chip.hot ? Util.alpha(root.barFg, 0.11) : Util.alpha(root.barFg, 0.055))
          border.width: Style.spacing.hairline
          border.color: chip.peeked
            ? Util.alpha(root.accentColor, chip.hot ? 0.62 : 0.48)
            : (chip.hot ? Util.alpha(root.barFg, 0.24) : Util.alpha(root.barFg, 0.13))

          Behavior on color { ColorAnimation { duration: Style.duration(140) } }
          Behavior on border.color { ColorAnimation { duration: Style.duration(140) } }

          // Subtle top specular rim highlight.
          Rectangle {
            visible: chipPill.radius > 0
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: Math.round(chipPill.radius * 0.65)
            anchors.rightMargin: Math.round(chipPill.radius * 0.65)
            height: 1
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: "transparent" }
              GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, chip.peeked || chip.hot ? 0.24 : 0.14) }
              GradientStop { position: 1.0; color: "transparent" }
            }
          }

          Row {
            anchors.centerIn: parent
            spacing: root.vertical ? 0 : Style.space(6)
            scale: chip.pressScale

            // Quiet accent indicator dot when a shelved window is actively Peeked.
            Rectangle {
              visible: !root.vertical && chip.peeked
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(5)
              height: Style.space(5)
              radius: width / 2
              color: root.accentColor
            }

            Item {
              anchors.verticalCenter: parent.verticalCenter
              width: chip.iconExtent
              height: chip.iconExtent

              Image {
                id: appIcon
                anchors.fill: parent
                source: chip.iconSource
                sourceSize.width: Math.round(width * Screen.devicePixelRatio)
                sourceSize.height: Math.round(height * Screen.devicePixelRatio)
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: true
                opacity: chip.peeked || chip.hot ? 1.0 : 0.86
                Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }
              }

              Text {
                anchors.centerIn: parent
                visible: appIcon.status === Image.Error || appIcon.source.toString() === ""
                textFormat: Text.PlainText
                text: root.verticalLabel(chip.modelData)
                color: chip.peeked ? root.accentColor : root.barFg
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                font.weight: Font.DemiBold
              }
            }

            Text {
              visible: !root.vertical && root.showTitles
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(0, chipPill.width - chip.titleOverhead)
              textFormat: Text.PlainText
              text: root.windowTitle(chip.modelData)
              color: root.barFg
              font.family: root.uiFont
              font.pixelSize: Style.font.bodySmall
              font.weight: Font.Medium
              elide: Text.ElideRight
              verticalAlignment: Text.AlignVCenter
            }
          }
        }
      }
    }
  }

  Ui.PopupCard {
    id: previewCard

    anchorItem: root.previewAnchor || root
    bar: root.bar
    owner: root
    triggerMode: "hover"
    open: root.previewToplevel !== null && root.previewAnchor !== null
    contentWidth: Style.space(324)
    contentHeight: Style.space(236)
    padding: Style.space(8)

    PreviewSurface {
      anchors.fill: parent
      toplevel: root.previewToplevel
      titleText: root.previewToplevel ? String(root.previewToplevel.title || "Window") : ""
      iconSource: root.previewToplevel ? root.windowIcon(root.previewToplevel) : ""
      fallbackLetter: root.previewToplevel ? root.verticalLabel(root.previewToplevel) : "W"
      live: previewCard.open
      open: previewCard.open
      peeked: root.previewToplevel ? root.isPeeked(root.previewToplevel) : false
    }
  }
}
