pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "Model.js" as Model

Ui.BarWidget {
  id: root
  moduleName: "akshaybapat.screenshot-manager"

  property var screenshotState: Model.emptyState()

  readonly property string barIcon: root.setting("icon", Model.defaultIcon())
  readonly property bool showCount: root.setting("showCount", true) !== false
  readonly property color fg: root.bar ? root.bar.barForeground : Commons.Color.foreground
  readonly property string monoFont: root.bar ? root.bar.fontFamily : Style.font.family

  readonly property var panelItem: panelLoader.item
  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false

  function open() {
    if (panelItem && typeof panelItem.open === "function") panelItem.open()
  }

  function close() {
    if (panelItem && typeof panelItem.close === "function") panelItem.close()
  }

  function toggle() {
    if (panelItem && typeof panelItem.toggle === "function") panelItem.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelItem && typeof panelItem.closeForPopoutSwitch === "function") panelItem.closeForPopoutSwitch()
  }

  function applyState(state) {
    screenshotState = state || Model.emptyState()
  }

  function refresh() {
    if (panelItem && typeof panelItem.refresh === "function") panelItem.refresh()
  }

  function takeScreenshot() {
    if (panelItem && typeof panelItem.takeScreenshot === "function") panelItem.takeScreenshot()
  }

  function copyLatest() {
    if (panelItem && typeof panelItem.copyLatest === "function") panelItem.copyLatest()
  }

  function previewLatest() {
    if (panelItem && typeof panelItem.previewLatest === "function") panelItem.previewLatest()
  }

  function injectPanel() {
    if (!panelItem) return
    panelItem.bar = root.bar
    panelItem.anchorItem = button
    panelItem.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // The count does not exist until the first scan lands, so the label grows
  // from glyph to "glyph 54" in one frame and every module to the left of it
  // jumps sideways. Ease the slot instead, exactly as the bar's own
  // variable-width active-window label does.
  Behavior on implicitWidth {
    NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
  }

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      // Scan once at start: without it the bar shows no count until the panel
      // is first opened, so every bar restart blanks the number.
      Qt.callLater(function() {
        root.injectPanel()
        root.refresh()
      })
    }
  }

  IpcHandler {
    target: "akshaybapat.screenshot-manager"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function preview(): void { root.previewLatest() }
  }

  // Quiet macOS-calm frosted glass pill on hover or while the gallery is open,
  // centered inside the exact 26 px bar slot without adding a pixel of height.
  Rectangle {
    id: glassPill
    readonly property bool hot: root.opened || button.tooltipHovered
    anchors.centerIn: parent
    width: root.vertical
      ? Math.max(Style.space(20), parent.width - Style.space(4))
      : Math.max(Style.space(22), parent.width - Style.space(2))
    height: root.vertical
      ? Math.max(Style.space(22), parent.height - Style.space(2))
      : Math.min(parent.height - Style.space(4), Style.space(22))
    radius: Math.max(6, Math.min(Math.round(height / 2), Style.cornerRadius > 0 ? Style.cornerRadius - 3 : 0))
    color: root.opened
      ? Util.alpha(root.fg, 0.12)
      : (button.tooltipHovered ? Util.alpha(root.fg, 0.08) : "transparent")
    border.width: hot ? Style.spacing.hairline : 0
    border.color: root.opened
      ? Util.alpha(root.fg, 0.24)
      : (button.tooltipHovered ? Util.alpha(root.fg, 0.16) : "transparent")

    Behavior on color { ColorAnimation { duration: Style.duration(140) } }
    Behavior on border.color { ColorAnimation { duration: Style.duration(140) } }

    Rectangle {
      visible: glassPill.hot && glassPill.radius > 0
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.topMargin: 1
      anchors.leftMargin: Math.round(glassPill.radius * 0.65)
      anchors.rightMargin: Math.round(glassPill.radius * 0.65)
      height: 1
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, root.opened ? 0.22 : 0.14) }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }
  }

  Ui.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontFamily: root.monoFont
    text: Model.barLabel(root.screenshotState.count, root.vertical, root.screenshotState.known, root.barIcon, root.showCount)
    tooltipText: "Screenshots · left: manage · right: new · middle: copy latest"
    // WidgetButton paints at body size, which left the camera glyph visibly
    // smaller than the optically sized icons on either side of it. The bar's
    // own icon token puts it back on the same rhythm as its neighbours.
    fontSize: Style.bar.iconFont
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.RightButton) root.takeScreenshot()
      else if (buttonCode === Qt.MiddleButton) root.copyLatest()
    }
  }
}
