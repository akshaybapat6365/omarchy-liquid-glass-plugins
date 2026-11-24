pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Native Omarchy 4.5 Liquid Glass Visual Window & App Switcher HUD overlay.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool _surfaceMapped: false
  property bool _dataReady: false
  property bool _loading: false
  property string currentMode: "all"
  property string activeAppName: ""
  property int _initialStep: 1
  property int _pendingSteps: 0
  property bool _openedViaStep: false
  property bool _silentWarmup: false
  property var windowItems: []

  // Resolve plugin directory safely across Omarchy 4.5 (sanitized manifests omit __sourceDir).
  readonly property string sourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir)
    : decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, ""))
  readonly property string dataScriptPath: sourceDir ? (sourceDir + "/SwitcherData.py") : ""

  // Smoked obsidian optical glass base (#101219 @ 0.86 alpha) on dark themes,
  // tracking lighter Omarchy themes gracefully.
  readonly property color glassTint: {
    var bg = Commons.Color.background
    var nearBlack = bg.r < 0.035 && bg.g < 0.035 && bg.b < 0.035
    if (nearBlack) return Qt.rgba(16 / 255, 18 / 255, 25 / 255, 0.86)
    return Qt.rgba(bg.r, bg.g, bg.b, 0.86)
  }

  function _parsePayload(payloadJson) {
    if (!payloadJson) return ({})
    if (typeof payloadJson === "object") return payloadJson
    try {
      const parsed = JSON.parse(String(payloadJson))
      return (parsed && typeof parsed === "object") ? parsed : ({})
    } catch (e) {
      return ({})
    }
  }

  function _fetchLiveWindows(sameAppMode, silentWarmup) {
    if (!dataScriptPath) return
    if (dataProc.running) {
      dataProc.running = false
    }
    root._loading = true
    root._silentWarmup = !!silentWarmup
    var cmd = ["python3", "-S", dataScriptPath, "--json"]
    if (sameAppMode) cmd.push("--same-app")
    dataProc.command = cmd
    dataProc.running = true
  }

  function open(payloadJson) {
    var payload = _parsePayload(payloadJson)
    var requestedMode = payload.mode === "same-app" ? "same-app" : "all"
    var stepDelta = payload.step === undefined || payload.step === null ? 1 : Number(payload.step)
    if (isNaN(stepDelta)) stepDelta = 1
    var isToggleOpen = payload.source === "toggle"

    // Already open in the same mode: glide selection cleanly without reloading.
    if (root.opened && root.currentMode === requestedMode) {
      const delta = stepDelta !== 0 ? stepDelta : 1
      if (root._loading && !root._dataReady) {
        root._pendingSteps += delta
      } else {
        hudView.stepSelection(delta)
      }
      if (!isToggleOpen && stepDelta !== 0) {
        hudView.openedViaStep = true
      }
      hudView.forceActiveFocus()
      return
    }

    // Fresh open or mode switch (All <-> Same App).
    exitTimer.stop()
    postActionRefreshTimer.stop()
    root.currentMode = requestedMode
    root._initialStep = stepDelta
    root._pendingSteps = 0
    root._openedViaStep = !isToggleOpen && stepDelta !== 0
    root._dataReady = false
    root._surfaceMapped = true
    root.opened = true
    readyFailsafeTimer.restart()

    hudView.resetSession(stepDelta, root._openedViaStep)
    _fetchLiveWindows(requestedMode === "same-app", false)

    Qt.callLater(function() {
      if (root.opened) hudView.forceActiveFocus()
    })
  }

  function step(payloadJson) {
    open(payloadJson)
  }

  function close() {
    readyFailsafeTimer.stop()
    postActionRefreshTimer.stop()
    if (!root.opened && !root._surfaceMapped) return
    root.opened = false
    root._dataReady = false
    root._pendingSteps = 0
    if (Style.reduceMotion) {
      root._surfaceMapped = false
    } else {
      exitTimer.restart()
    }
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide((root.manifest && root.manifest.id) || "akshaybapat.switcher")
    }
  }

  function toggle(payloadJson) {
    if (root.opened) {
      root.dismiss()
    } else {
      const payload = _parsePayload(payloadJson)
      payload.source = "toggle"
      if (payload.step === undefined) payload.step = 1
      root.open(JSON.stringify(payload))
    }
  }

  function ping() {
    return "ok"
  }

  function _focusAddress(address) {
    var addr = String(address || "").trim()
    root.dismiss()
    if (!addr || !root.dataScriptPath) return
    Quickshell.execDetached(["python3", "-S", root.dataScriptPath, "--focus", addr])
  }

  function _closeAddress(address) {
    var addr = String(address || "").trim()
    if (!addr || !root.dataScriptPath) return
    Quickshell.execDetached(["python3", "-S", root.dataScriptPath, "--close", addr])
    postActionRefreshTimer.restart()
  }

  function _hideAddress(address) {
    var addr = String(address || "").trim()
    if (!addr || !root.dataScriptPath) return
    Quickshell.execDetached(["python3", "-S", root.dataScriptPath, "--hide", addr])
    postActionRefreshTimer.restart()
  }

  Process {
    id: dataProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root._loading = false
        readyFailsafeTimer.stop()
        var raw = String(text || "").trim()
        if (!raw) {
          if (!root._silentWarmup) root._dataReady = true
          return
        }
        try {
          const parsed = JSON.parse(raw)
          if (root._silentWarmup) {
            root._silentWarmup = false
            return
          }
          if (parsed && typeof parsed === "object") {
            const wins = Array.isArray(parsed.windows) ? parsed.windows : []
            root.activeAppName = String(parsed.activeAppName || "")
            root.windowItems = wins
            if (!root._dataReady) {
              root._dataReady = true
              hudView.selectInitial(root._initialStep)
              if (root._pendingSteps !== 0) {
                hudView.stepSelection(root._pendingSteps)
                root._pendingSteps = 0
              }
            } else {
              // Post-action refresh while open: clamp selection cleanly.
              if (hudView.selectedIndex >= wins.length) {
                hudView.selectedIndex = Math.max(0, wins.length - 1)
              }
            }
            if (root.opened) {
              Qt.callLater(function() {
                if (root.opened) hudView.forceActiveFocus()
              })
            }
          }
        } catch (e) {
          console.warn("akshaybapat.switcher: failed to parse SwitcherData JSON:", e)
          root._dataReady = true
        }
      }
    }
  }

  Timer {
    id: readyFailsafeTimer
    interval: 220
    repeat: false
    onTriggered: {
      if (root.opened && !root._dataReady) {
        root._dataReady = true
      }
    }
  }

  Timer {
    id: postActionRefreshTimer
    interval: 240
    repeat: false
    onTriggered: {
      if (root.opened) {
        root._fetchLiveWindows(root.currentMode === "same-app", false)
      }
    }
  }

  Timer {
    id: exitTimer
    interval: Style.duration(150)
    repeat: false
    onTriggered: {
      if (!root.opened) root._surfaceMapped = false
    }
  }

  // Silently warm the icon & desktop cache on plugin load so the very first Alt+Tab opens in ~15ms.
  Component.onCompleted: {
    Qt.callLater(function() {
      root._fetchLiveWindows(false, true)
    })
  }

  ShellIpc {
    target: "switcher"
    function open(payloadJson: string): string {
      root.open(payloadJson)
      return "ok"
    }
    function step(payloadJson: string): string {
      root.step(payloadJson)
      return "ok"
    }
    function close(): string {
      root.dismiss()
      return "ok"
    }
    function toggle(): string {
      root.toggle("{}")
      return "ok"
    }
    function state(): string {
      return root.opened ? "open" : "closed"
    }
    function ping(): string {
      return root.ping()
    }
  }

  OverlayWindow {
    id: panel
    shown: root._surfaceMapped
    shownKeyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "omarchy-switcher"

    readonly property bool visualActive: root.opened && panel.contentRevealed && root._dataReady

    onVisualActiveChanged: {
      if (visualActive) {
        Qt.callLater(function() {
          if (root.opened) hudView.forceActiveFocus()
        })
      }
    }

    // Subtle smoked optical backdrop veil; clicking outside cancels cleanly.
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(6 / 255, 7 / 255, 11 / 255, 0.36)
      opacity: panel.visualActive ? 1.0 : 0.0

      Behavior on opacity {
        enabled: !Style.reduceMotion
        NumberAnimation {
          duration: panel.visualActive ? Style.duration(155) : Style.duration(125)
          easing.type: Easing.OutCubic
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    SwitcherHud {
      id: hudView
      anchors.centerIn: parent
      maxAvailableWidth: panel.width > 0 ? panel.width : 1600

      windows: root.windowItems
      sameApp: root.currentMode === "same-app"
      activeAppName: root.activeAppName
      reduceMotion: Style.reduceMotion
      glassTint: root.glassTint
      accentColor: Commons.Color.accent
      foregroundColor: Commons.Color.popups.text
      mutedColor: Commons.Color.muted

      opacity: panel.visualActive ? 1.0 : 0.0
      scale: panel.visualActive ? 1.0 : 0.955
      transformOrigin: Item.Center

      transform: Translate {
        y: panel.visualActive ? 0 : 8
        Behavior on y {
          enabled: !Style.reduceMotion
          NumberAnimation {
            duration: panel.visualActive ? Style.duration(160) : Style.duration(125)
            easing.type: panel.visualActive ? Easing.OutQuart : Easing.InCubic
          }
        }
      }

      Behavior on opacity {
        enabled: !Style.reduceMotion
        NumberAnimation {
          duration: panel.visualActive ? Style.duration(155) : Style.duration(125)
          easing.type: Easing.OutCubic
        }
      }

      Behavior on scale {
        enabled: !Style.reduceMotion
        NumberAnimation {
          duration: panel.visualActive ? Style.duration(160) : Style.duration(125)
          easing.type: panel.visualActive ? Easing.OutQuart : Easing.InCubic
        }
      }

      onRequestFocus: function(address) { root._focusAddress(address) }
      onRequestCloseWindow: function(address) { root._closeAddress(address) }
      onRequestHideWindow: function(address) { root._hideAddress(address) }
      onRequestDismiss: root.dismiss()
    }
  }
}
