pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "Model.js" as Model

Ui.Panel {
  id: root
  moduleName: "akshaybapat.screenshot-manager"
  ipcTarget: "akshaybapat.screenshot-manager"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var screenshots: []
  property var visibleScreenshots: []
  property string filterText: ""
  property string statusText: ""
  property string summaryText: ""
  property string pendingTrashKey: ""
  property var pendingTrashScreenshot: null
  property string copiedKey: ""
  property string listError: ""
  property string trashError: ""
  property string copyError: ""
  property string clearError: ""
  property bool pendingClear: false
  property bool loaded: false
  property string lastSignature: ""
  property int cursorIndex: -1
  property string screenshotsDir: ""
  property string dirName: "Pictures"
  property int totalCount: 0

  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property string contentFontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property bool busy: listProcess.running || trashProcess.running || copyProcess.running || clearProcess.running
  readonly property bool previewOpen: preview ? preview.open : false
  readonly property string helperPath: {
    var url = decodeURIComponent(String(Qt.resolvedUrl("screenshotctl.py")))
    return url.indexOf("file://") === 0 ? url.substring(7) : url
  }

  // Prefer the native Rust screenshotd (<5 ms cached 480x270 thumbnails, zero
  // full-4K tmpfs bloat) with automatic fallback to screenshotctl.py.
  function helperCommand(args) {
    return [
      "sh", "-c",
      "helper=\"$1\"; shift; if [ -x \"$HOME/.local/bin/screenshotd\" ]; then exec \"$HOME/.local/bin/screenshotd\" \"$@\"; else exec python3 \"$helper\" \"$@\"; fi",
      "--", root.helperPath
    ].concat(args || [])
  }

  function launch(process, args) {
    process.settled = false
    process.command = helperCommand(args)
    process.running = true
  }

  // A helper that never starts produces no exit code: Quickshell only drops
  // `running` back to false. Route that through the same error text the exit
  // handlers use instead of leaving the hopeful "…" status on screen forever.
  function helperDidNotStart(process, action) {
    if (process.settled) return
    process.settled = true
    if (action === "trash" || action === "clear") resetTrashConfirmation()
    root.statusText = Model.actionError(127, "", action)
  }

  function updateVisible() {
    root.visibleScreenshots = Model.filterScreenshots(root.screenshots, root.filterText)
    if (preview && preview.open) {
      preview.screenshots = root.visibleScreenshots
      if (root.visibleScreenshots.length === 0) {
        preview.dismiss()
      } else if (preview.currentIndex >= root.visibleScreenshots.length) {
        preview.currentIndex = root.visibleScreenshots.length - 1
      }
    }
  }

  function open() {
    root.controller.show()
    refresh()
    preview.anchorItem = root.anchorItem
    preview.hostPanel = root
    Qt.callLater(function() {
      if (root.opened && !root.previewOpen) galleryView.focusSearch()
    })
  }

  function close() {
    resetTrashConfirmation()
    if (preview) preview.dismiss()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() {
    if (root.busy) return
    if (!root.loaded) root.statusText = "Scanning screenshots…"
    root.listError = ""
    launch(listProcess, ["list"])
  }

  function applyState(raw) {
    var state = Model.parseState(raw)
    var first = state.screenshots.length > 0 ? state.screenshots[0].path : ""
    var last = state.screenshots.length > 0 ? state.screenshots[state.screenshots.length - 1].path : ""
    var signature = state.dir + "|" + state.count + "|" + first + "|" + last
    if (signature !== root.lastSignature) {
      root.lastSignature = signature
      root.screenshots = state.screenshots
      root.updateVisible()
    }
    root.screenshotsDir = state.dir
    root.dirName = state.dirName || "Pictures"
    root.totalCount = state.total
    root.loaded = state.known
    root.summaryText = state.count === 0
      ? "No screenshots yet"
      : state.total === state.count
        ? state.dirName + " · " + state.count + " screenshots"
        : state.dirName + " · " + state.total + " screenshots (showing " + state.count + ")"
    root.statusText = root.summaryText
    if (root.hostWidget && root.hostWidget.applyState) root.hostWidget.applyState(state)
  }

  function copyScreenshot(screenshot) {
    if (root.busy || !screenshot) return
    resetTrashConfirmation()
    root.copiedKey = Model.screenshotKey(screenshot)
    copiedResetTimer.restart()
    root.statusText = "Copying " + screenshot.name + "…"
    root.copyError = ""
    launch(copyProcess, ["copy", screenshot.path])
  }

  function copyLatest() {
    if (root.busy) return
    if (root.screenshots.length === 0) {
      root.statusText = "No screenshots to copy yet"
      return
    }
    root.copyScreenshot(root.screenshots[0])
  }

  function requestTrash(screenshot) {
    if (root.busy || !screenshot) return
    var key = Model.screenshotKey(screenshot)
    if (root.pendingTrashKey !== key) {
      root.pendingTrashKey = key
      root.pendingTrashScreenshot = screenshot
      root.statusText = "Press Confirm to trash " + screenshot.name
      confirmTimer.restart()
      return
    }

    confirmTimer.stop()
    root.statusText = "Trashing " + screenshot.name + "…"
    root.trashError = ""
    launch(trashProcess, ["trash", screenshot.path])
  }

  function resetTrashConfirmation() {
    confirmTimer.stop()
    root.pendingTrashKey = ""
    root.pendingTrashScreenshot = null
    root.pendingClear = false
  }

  function requestClearAll() {
    if (root.busy || root.screenshots.length === 0) return
    if (root.pendingTrashKey) resetTrashConfirmation()
    if (!root.pendingClear) {
      root.pendingClear = true
      root.statusText = "Press Clear all again to trash " + root.screenshots.length + " screenshots"
      confirmTimer.restart()
      return
    }

    confirmTimer.stop()
    root.pendingClear = false
    root.statusText = "Trashing " + root.screenshots.length + " screenshots…"
    root.clearError = ""
    launch(clearProcess, ["clear"])
  }

  function takeScreenshot() {
    if (root.busy) return
    resetTrashConfirmation()
    root.statusText = "Launching screenshot flow…"
    Quickshell.execDetached(["omarchy", "capture", "screenshot"])
    takeRefreshTimer.restart()
  }

  function openFolder() {
    if (!root.screenshotsDir) return
    Quickshell.execDetached(["xdg-open", root.screenshotsDir])
  }

  function openScreenshot(screenshot) {
    if (!screenshot || !screenshot.path) return
    Quickshell.execDetached(["xdg-open", screenshot.path])
  }

  function openPreviewAt(index) {
    if (root.busy || root.visibleScreenshots.length === 0) return
    resetTrashConfirmation()
    preview.screenshots = root.visibleScreenshots
    preview.showAt(index < 0 ? 0 : index)
  }

  function openPreview(screenshot) {
    if (root.busy || !screenshot) return
    var index = -1
    for (var i = 0; i < root.visibleScreenshots.length; i++) {
      if (root.visibleScreenshots[i].path === screenshot.path) {
        index = i
        break
      }
    }
    root.openPreviewAt(index)
  }

  function previewLatest() {
    if (root.visibleScreenshots.length === 0) {
      root.statusText = "No screenshots to preview yet"
      return
    }
    root.openPreviewAt(0)
  }

  onAnchorItemChanged: if (preview) preview.anchorItem = root.anchorItem
  onFilterTextChanged: root.updateVisible()
  onVisibleScreenshotsChanged: root.cursorIndex = -1

  Timer {
    id: confirmTimer
    interval: 8000
    onTriggered: {
      root.resetTrashConfirmation()
      if (!root.busy) root.statusText = "Trash cancelled"
    }
  }

  Timer {
    id: copiedResetTimer
    interval: 1600
    onTriggered: root.copiedKey = ""
  }

  Timer {
    id: takeRefreshTimer
    interval: 10000
    onTriggered: root.refresh()
  }

  Timer {
    id: autoRefreshTimer
    interval: 5000
    repeat: true
    running: root.opened && !root.busy && !root.previewOpen
    onTriggered: root.refresh()
  }

  Process {
    id: listProcess
    property bool settled: false
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text) root.applyState(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.listError = text
    }
    onRunningChanged: if (!running) Qt.callLater(function() { root.helperDidNotStart(listProcess, "load") })
    onExited: function(exitCode) {
      settled = true
      if (exitCode !== 0) root.statusText = Model.actionError(exitCode, root.listError, "load")
    }
  }

  Process {
    id: trashProcess
    property bool settled: false
    command: ["true"]
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.trashError = text
    }
    onRunningChanged: if (!running) Qt.callLater(function() { root.helperDidNotStart(trashProcess, "trash") })
    onExited: function(exitCode) {
      settled = true
      var trashed = root.pendingTrashScreenshot
      root.resetTrashConfirmation()
      if (exitCode !== 0) {
        root.statusText = Model.actionError(exitCode, root.trashError, "trash")
        return
      }
      root.statusText = "Trashed " + (trashed ? trashed.name : "screenshot")
      Qt.callLater(root.refresh)
    }
  }

  Process {
    id: copyProcess
    property bool settled: false
    command: ["true"]
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.copyError = text
    }
    onRunningChanged: if (!running) Qt.callLater(function() { root.helperDidNotStart(copyProcess, "copy") })
    onExited: function(exitCode) {
      settled = true
      if (exitCode !== 0) {
        root.copiedKey = ""
        root.statusText = Model.actionError(exitCode, root.copyError, "copy")
        return
      }
      root.statusText = "Copied to clipboard as PNG"
    }
  }

  Process {
    id: clearProcess
    property bool settled: false
    command: ["true"]
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.clearError = text
    }
    onRunningChanged: if (!running) Qt.callLater(function() { root.helperDidNotStart(clearProcess, "clear") })
    onExited: function(exitCode) {
      settled = true
      if (exitCode !== 0) {
        root.statusText = Model.actionError(exitCode, root.clearError, "clear")
        return
      }
      root.statusText = "Trashed all screenshots"
      Qt.callLater(root.refresh)
    }
  }

  PreviewOverlay {
    id: preview
    hostPanel: root
    anchorItem: root.anchorItem
  }

  Ui.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: galleryView.searchField
    contentWidth: panel.fittedContentWidth(Style.space(576))
    contentHeight: panel.fittedContentHeight(galleryView.implicitHeight)

    Ui.PanelKeyCatcher {
      anchors.fill: parent
      blocked: galleryView.searchHasFocus || root.previewOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      GalleryView {
        id: galleryView
        width: parent.width
        screenshots: root.screenshots
        visibleScreenshots: root.visibleScreenshots
        dirName: root.dirName
        screenshotsDir: root.screenshotsDir
        totalCount: root.totalCount
        filterText: root.filterText
        statusText: root.statusText
        summaryText: root.summaryText
        pendingTrashKey: root.pendingTrashKey
        copiedKey: root.copiedKey
        pendingClear: root.pendingClear
        busy: root.busy
        cursorIndex: root.cursorIndex
        barIcon: root.hostWidget && root.hostWidget.barIcon
          ? root.hostWidget.barIcon
          : Model.defaultIcon()
        foreground: root.contentForeground
        monoFont: root.contentFontFamily

        onFilterEdited: function(text) { root.filterText = text }
        onFilterAccepted: if (root.visibleScreenshots.length > 0) root.openPreviewAt(0)
        onCloseRequested: root.close()
        onCaptureRequested: root.takeScreenshot()
        onOpenFolderRequested: root.openFolder()
        onRefreshRequested: root.refresh()
        onClearAllRequested: root.requestClearAll()
        onCancelConfirmRequested: {
          root.resetTrashConfirmation()
          root.statusText = root.summaryText
        }
        onPreviewRequested: function(index) { root.openPreviewAt(index) }
        onCopyRequested: function(screenshot) { root.copyScreenshot(screenshot) }
        onTrashRequested: function(screenshot) { root.requestTrash(screenshot) }
        onCursorChanged: function(index) { root.cursorIndex = index }
      }
    }
  }
}
