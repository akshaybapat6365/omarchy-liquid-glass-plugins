pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: root

  property var hostPanel: null
  property var anchorItem: null
  property var screenshots: []
  property int currentIndex: -1
  property bool open: false
  property bool justCopied: false

  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property var currentScreenshot: root.currentIndex >= 0 && root.currentIndex < root.screenshots.length
    ? root.screenshots[root.currentIndex]
    : null
  readonly property int previewWidth: root.currentScreenshot ? Number(root.currentScreenshot.width || 0) : 0
  readonly property int previewHeight: root.currentScreenshot ? Number(root.currentScreenshot.height || 0) : 0

  visible: root.open
  screen: root.anchorWindow ? root.anchorWindow.screen : null
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "omarchy-screenshot-preview"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore

  function showAt(index) {
    if (root.screenshots.length === 0) return
    root.justCopied = false
    root.currentIndex = index < 0 ? 0 : Math.min(index, root.screenshots.length - 1)
    root.open = true
    Qt.callLater(function() { if (root.open) stage.forceActiveFocus() })
  }

  function step(delta) {
    if (root.screenshots.length === 0) return
    var next = root.currentIndex + delta
    if (next < 0) next = root.screenshots.length - 1
    if (next >= root.screenshots.length) next = 0
    root.justCopied = false
    if (root.hostPanel && typeof root.hostPanel.resetTrashConfirmation === "function")
      root.hostPanel.resetTrashConfirmation()
    root.currentIndex = next
  }

  function dismiss() {
    root.justCopied = false
    if (root.hostPanel && typeof root.hostPanel.resetTrashConfirmation === "function")
      root.hostPanel.resetTrashConfirmation()
    root.open = false
  }

  Timer {
    id: copiedBadgeTimer
    interval: 1600
    onTriggered: root.justCopied = false
  }

  PreviewStage {
    id: stage
    anchors.fill: parent
    screenshots: root.screenshots
    currentIndex: root.currentIndex
    busy: !!(root.hostPanel && root.hostPanel.busy)
    canOpenFolder: !!(root.hostPanel && root.hostPanel.screenshotsDir !== "")
    justCopied: root.justCopied
    pendingTrashKey: root.hostPanel ? String(root.hostPanel.pendingTrashKey || "") : ""

    onDismissRequested: root.dismiss()
    onStepRequested: function(delta) { root.step(delta) }
    onCopyRequested: function(screenshot) {
      if (root.hostPanel && typeof root.hostPanel.copyScreenshot === "function") {
        root.hostPanel.copyScreenshot(screenshot)
        root.justCopied = true
        copiedBadgeTimer.restart()
      }
    }
    onOpenRequested: function(screenshot) {
      if (!screenshot || !screenshot.path) return
      if (root.hostPanel && typeof root.hostPanel.openScreenshot === "function") {
        root.hostPanel.openScreenshot(screenshot)
      } else {
        Quickshell.execDetached(["xdg-open", screenshot.path])
      }
    }
    onFolderRequested: {
      if (root.hostPanel && typeof root.hostPanel.openFolder === "function")
        root.hostPanel.openFolder()
    }
    onDeleteRequested: function(screenshot) {
      if (root.hostPanel && typeof root.hostPanel.requestTrash === "function")
        root.hostPanel.requestTrash(screenshot)
    }
  }
}
