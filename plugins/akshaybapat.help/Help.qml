import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "HelpModel.js" as HelpModel

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool _surfaceMapped: false
  property var helpData: ({
    counts: { shortcuts: 0, gestures: 0, tools: 0, guides: 0 },
    categories: [],
    shortcuts: [],
    gestures: [],
    tools: [],
    guides: []
  })
  property string toastText: ""
  property string _pendingCommand: ""

  // Resolve plugin directory safely across Omarchy 4.5 (sanitized manifests omit __sourceDir).
  readonly property string sourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir)
    : decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, ""))
  readonly property string dataScriptPath: sourceDir ? (sourceDir + "/HelpData.py") : ""

  // Lift pure #000000 backgrounds subtly to smoked obsidian so the Liquid Glass
  // sheet carries physical depth over dark wallpapers while tracking every theme.
  readonly property color glassTint: {
    var bg = Commons.Color.background
    var nearBlack = bg.r < 0.025 && bg.g < 0.025 && bg.b < 0.025
    if (nearBlack) return Qt.rgba(16 / 255, 17 / 255, 22 / 255, 0.86)
    return Qt.rgba(bg.r, bg.g, bg.b, 0.86)
  }

  function refreshData() {
    if (!dataScriptPath) return
    if (dataProc.running) {
      dataProc.running = false
    }
    dataProc.command = ["python3", dataScriptPath, "--json"]
    dataProc.running = true
  }

  function showToast(msg) {
    root.toastText = String(msg || "")
    if (root.toastText.length > 0) toastTimer.restart()
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    var tabIdx = HelpModel.tabIndexForName(payload.tab)
    if (tabIdx >= 0) {
      sheetView.setTab(tabIdx)
    } else if (!root.opened) {
      sheetView.setTab(0)
    }

    if (typeof payload.category === "string" && payload.category.length > 0) {
      sheetView.selectedCategory = payload.category
    } else if (!root.opened) {
      sheetView.selectedCategory = "all"
    }

    if (typeof payload.query === "string") {
      sheetView.searchQuery = payload.query
    } else if (!root.opened) {
      sheetView.searchQuery = ""
    }

    sheetView.resetSelection()
    exitTimer.stop()
    root._surfaceMapped = true
    root.opened = true
    root.refreshData()

    Qt.callLater(function() {
      if (root.opened) sheetView.focusSearch()
    })
  }

  function close() {
    if (!root.opened && !root._surfaceMapped) return
    root.opened = false
    if (Style.reduceMotion) {
      root._surfaceMapped = false
    } else {
      exitTimer.restart()
    }
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide((root.manifest && root.manifest.id) || "akshaybapat.help")
    }
  }

  function toggle(payloadJson) {
    if (root.opened) root.dismiss()
    else root.open(payloadJson || "{}")
  }

  function refresh() {
    root.refreshData()
    return "ok"
  }

  function ping() {
    return "ok"
  }

  function executeAction(spec) {
    if (!spec || !spec.command) return
    var cmd = String(spec.command)
    var closeFirst = spec.closeOnRun !== false
    var delay = Number(spec.delayMs || 0)

    if (closeFirst) {
      root.dismiss()
      if (delay > 0) {
        root._pendingCommand = cmd
        delayedRunTimer.interval = delay
        delayedRunTimer.restart()
      } else {
        Util.execDetached(cmd)
      }
      return
    }

    Util.execDetached(cmd)
    if (spec.toast) root.showToast(spec.toast)
    postActionRefreshFast.restart()
    postActionRefreshSlow.restart()
  }

  Process {
    id: dataProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          const parsed = JSON.parse(raw)
          if (parsed && typeof parsed === "object") {
            root.helpData = parsed
          }
        } catch (e) {
          console.warn("akshaybapat.help: failed to parse HelpData JSON:", e)
        }
      }
    }
  }

  Timer {
    id: exitTimer
    interval: Style.duration(165)
    repeat: false
    onTriggered: {
      if (!root.opened) root._surfaceMapped = false
    }
  }

  Timer {
    id: delayedRunTimer
    interval: 120
    repeat: false
    onTriggered: {
      if (root._pendingCommand) {
        const cmd = root._pendingCommand
        root._pendingCommand = ""
        Util.execDetached(cmd)
      }
    }
  }

  Timer {
    id: toastTimer
    interval: 2400
    repeat: false
    onTriggered: root.toastText = ""
  }

  Timer {
    id: postActionRefreshFast
    interval: 900
    repeat: false
    onTriggered: if (root.opened) root.refreshData()
  }

  Timer {
    id: postActionRefreshSlow
    interval: 2200
    repeat: false
    onTriggered: if (root.opened) root.refreshData()
  }

  // Warm the shortcut & tool cache silently on plugin load so the very first summon opens in 0ms.
  Component.onCompleted: {
    Qt.callLater(function() { root.refreshData() })
  }

  ShellIpc {
    target: "help"
    function open(payloadJson: string): string {
      root.open(payloadJson)
      return "ok"
    }
    function close(): string {
      root.dismiss()
      return "ok"
    }
    function toggle(payloadJson: string): string {
      root.toggle(payloadJson)
      return "ok"
    }
    function refresh(): string {
      return root.refresh()
    }
    function state(): string {
      return root.opened ? "open" : "closed"
    }
    function ping(): string {
      return "ok"
    }
  }

  OverlayWindow {
    id: panel
    shown: root._surfaceMapped
    shownKeyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "omarchy-help"

    readonly property bool visualActive: root.opened && panel.contentRevealed

    // Subtle smoked backdrop veil that dismisses on outside click.
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(6 / 255, 7 / 255, 11 / 255, 0.44)
      opacity: panel.visualActive ? 1.0 : 0.0

      Behavior on opacity {
        enabled: !Style.reduceMotion
        NumberAnimation {
          duration: panel.visualActive ? Style.duration(170) : Style.duration(140)
          easing.type: Easing.OutCubic
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    HelpSheet {
      id: sheetView
      width: Math.min(1040, Math.max(680, panel.width - 48))
      height: Math.min(700, Math.max(520, panel.height - 48))
      anchors.centerIn: parent

      helpData: root.helpData
      glassTint: root.glassTint
      accentColor: Commons.Color.accent
      foregroundColor: Commons.Color.popups.text
      mutedColor: Commons.Color.muted
      reduceMotion: Style.reduceMotion
      toastText: root.toastText

      opacity: panel.visualActive ? 1.0 : 0.0
      scale: panel.visualActive ? 1.0 : 0.965
      transformOrigin: Item.Center

      transform: Translate {
        y: panel.visualActive ? 0 : 10
        Behavior on y {
          enabled: !Style.reduceMotion
          NumberAnimation {
            duration: panel.visualActive ? Style.duration(210) : Style.duration(145)
            easing.type: panel.visualActive ? Easing.OutQuart : Easing.InCubic
          }
        }
      }

      Behavior on opacity {
        enabled: !Style.reduceMotion
        NumberAnimation {
          duration: panel.visualActive ? Style.duration(165) : Style.duration(140)
          easing.type: Easing.OutCubic
        }
      }

      Behavior on scale {
        enabled: !Style.reduceMotion
        NumberAnimation {
          duration: panel.visualActive ? Style.duration(210) : Style.duration(145)
          easing.type: panel.visualActive ? Easing.OutQuart : Easing.InCubic
        }
      }

      onRequestAction: function(spec) { root.executeAction(spec) }
      onRequestDismiss: root.dismiss()
      onRequestRefresh: {
        root.refreshData()
        root.showToast("Refreshed live system state")
      }
    }
  }
}
