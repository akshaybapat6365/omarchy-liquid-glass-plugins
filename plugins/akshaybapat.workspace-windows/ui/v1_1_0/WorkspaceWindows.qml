pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "WindowIcons.js" as WindowIcons

Ui.BarWidget {
  id: root
  moduleName: "akshaybapat.workspace-windows"
  readonly property string uiRevision: "1.1.0"

  IpcHandler {
    target: root.moduleName + "." + (root.QsWindow.window && root.QsWindow.window.screen ? root.QsWindow.window.screen.name : "unmounted")
    enabled: root.QsWindow.window !== null
    function appearance(): string { return JSON.stringify(root.appearance()) }
  }

  function appearance() {
    var entries = []
    for (var i = 0; i < root.allToplevels.length; i++) {
      var t = root.allToplevels[i], e = root.desktopEntry(t)
      entries.push({
        appClass: String(t && t.lastIpcObject ? t.lastIpcObject.class : ""),
        entryId: e ? e.id : "",
        artwork: root.windowIcon(t)
      })
    }
    var painted = []
    for (var j = 0; j < windowRepeater.count; j++) {
      var slot = windowRepeater.itemAt(j)
      if (slot) painted.push({ artwork: slot.paintSource, ready: slot.imageReady })
    }
    return { revision: root.uiRevision, applications: entries, painted: painted }
  }

  readonly property var desktopApplications: DesktopEntries.applications.values
  readonly property var iconLibrary: root.bar && root.bar.shell ? root.bar.shell.appLibrary : null

  property var focusedWorkspace: Hyprland.focusedWorkspace
  property var allToplevels: Hyprland.toplevels.values
  property string hoveredAddressOverride: ""
  property real wheelRemainder: 0

  readonly property int maxItems: Math.max(1, Number(root.setting("maxItems", 10)))
  readonly property bool showActiveLabel: root.setting("showActiveLabel", true) !== false
  readonly property int maxLabelWidth: Math.max(Style.space(64), Number(root.setting("maxLabelWidth", Style.space(124))))
  readonly property int cell: Math.max(Style.bar.iconSlot, Style.space(28))
  readonly property int iconExtent: Style.bar.iconCanvas
  readonly property color foreground: root.bar ? root.bar.barForeground : Commons.Color.foreground
  readonly property color accentColor: Commons.Color.accent
  readonly property string uiFont: (Style.font.menuFamily && Style.font.menuFamily !== Style.font.family && Style.font.menuFamily !== "monospace")
    ? Style.font.menuFamily
    : "Inter Display"

  // Windows of the focused workspace, in the compositor's own order. Special
  // workspaces (the minimize shelf, scratchpads) are never listed.
  readonly property var windows: {
    var ws = root.focusedWorkspace
    if (!ws) return []
    var all = root.allToplevels || []
    var out = []
    for (var i = 0; i < all.length; i++) {
      var t = all[i]
      if (!t || !t.workspace || t.workspace.id !== ws.id) continue
      if (String(t.workspace.name || "").indexOf("special:") === 0) continue
      out.push(t)
      if (out.length >= root.maxItems) break
    }
    return out
  }

  visible: root.windows.length > 0 && !root.vertical
  implicitWidth: visible ? stripRow.implicitWidth : 0
  implicitHeight: root.barSize

  Behavior on implicitWidth {
    NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
  }

  function normalizedAddress(toplevel) {
    if (!toplevel || !toplevel.address) return ""
    var address = String(toplevel.address)
    return address.indexOf("0x") === 0 ? address : "0x" + address
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

  function appDisplayName(toplevel) {
    if (toplevel && toplevel.appNameOverride) return String(toplevel.appNameOverride)
    var entry = root.desktopEntry(toplevel)
    if (entry && entry.name) return String(entry.name)
    var ipc = toplevel && toplevel.lastIpcObject ? toplevel.lastIpcObject : null
    if (ipc && ipc.class) {
      var cls = String(ipc.class).trim()
      if (cls.length > 0) return cls.charAt(0).toUpperCase() + cls.slice(1)
    }
    return ""
  }

  function windowLabel(toplevel) {
    var name = root.appDisplayName(toplevel)
    var title = String(toplevel && toplevel.title ? toplevel.title : "").trim()
    if (!name) return title || "Window"
    if (!title || title.toLowerCase() === name.toLowerCase()) return name
    return name + " · " + title
  }

  // Calm label for the active pill: shows the app name when unique on the
  // workspace so dynamic tab/CWD titles never cause width jitter, and switches
  // to the concise window title when multiple windows of the same app are open.
  function chipLabel(toplevel) {
    var name = root.appDisplayName(toplevel)
    var title = String(toplevel && toplevel.title ? toplevel.title : "").trim()
    if (!name) return title || "Window"
    var sameApp = 0
    for (var i = 0; i < root.windows.length; i++) {
      if (root.appDisplayName(root.windows[i]).toLowerCase() === name.toLowerCase()) sameApp += 1
    }
    if (sameApp > 1 && title) return title
    return name
  }

  function fallbackLetter(toplevel) {
    var label = root.appDisplayName(toplevel) || String(toplevel && toplevel.title ? toplevel.title : "W").trim()
    return label.length > 0 ? label.charAt(0).toUpperCase() : "W"
  }

  function focusWindow(toplevel) {
    var address = root.normalizedAddress(toplevel)
    if (!address) return
    // Hyprland 0.56 evaluates dispatch strings as Lua; the classic syntax is rejected.
    Hyprland.dispatch("hl.dsp.focus({ window = " + JSON.stringify("address:" + address) + " })")
  }

  function closeWindow(toplevel) {
    var address = root.normalizedAddress(toplevel)
    if (!address) return
    Hyprland.dispatch("hl.dsp.window.close({ window = " + JSON.stringify("address:" + address) + " })")
  }

  function cycleFocus(delta) {
    var list = root.windows
    if (list.length < 2) return
    var activeIdx = -1
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].activated === true) {
        activeIdx = i
        break
      }
    }
    var nextIdx = activeIdx < 0
      ? (delta > 0 ? 0 : list.length - 1)
      : (((activeIdx + delta) % list.length) + list.length) % list.length
    root.focusWindow(list[nextIdx])
  }

  Row {
    id: stripRow
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    spacing: Style.space(4)

    Repeater {
      id: windowRepeater
      model: root.windows

      delegate: Item {
        id: slot
        required property var modelData
        readonly property var toplevel: modelData
        readonly property string paintSource: appIcon.source
        readonly property bool imageReady: appIcon.status === Image.Ready
        readonly property bool focused: !!(slot.toplevel && slot.toplevel.activated === true)
        readonly property bool hot: pointer.containsMouse
          || (root.hoveredAddressOverride !== "" && root.hoveredAddressOverride === root.normalizedAddress(slot.toplevel))
        readonly property string labelText: root.chipLabel(slot.toplevel)
        readonly property bool showLabel: slot.focused && root.showActiveLabel && slot.labelText !== ""
        readonly property real measuredLabelWidth: Math.min(root.maxLabelWidth, Math.ceil(chipMetrics.advanceWidth))
        readonly property real targetWidth: slot.showLabel
          ? Math.max(root.cell, Style.space(8) + Style.space(5) + Style.space(6) + root.iconExtent + Style.space(6) + slot.measuredLabelWidth + Style.space(10))
          : (slot.focused ? root.cell + Style.space(8) : root.cell)

        TextMetrics {
          id: chipMetrics
          font.family: root.uiFont
          font.pixelSize: Style.font.bodySmall
          font.weight: Font.Medium
          text: slot.labelText
        }

        width: targetWidth
        height: root.barSize

        Behavior on width {
          NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
        }

        // Sleek macOS-calm frosted glass chip vertically centered in the 26 px bar.
        Rectangle {
          id: pillSurface
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.right: parent.right
          height: Math.min(root.barSize - Style.space(4), Style.space(22))
          radius: Math.max(6, Math.min(Math.round(height / 2), Style.cornerRadius > 0 ? Style.cornerRadius - 3 : 0))
          color: slot.focused
            ? Util.alpha(root.foreground, slot.hot ? 0.145 : 0.105)
            : (slot.hot ? Util.alpha(root.foreground, 0.09) : Util.alpha(root.foreground, 0.035))
          border.width: Style.spacing.hairline
          border.color: slot.focused
            ? Util.alpha(root.foreground, slot.hot ? 0.30 : 0.22)
            : (slot.hot ? Util.alpha(root.foreground, 0.20) : Util.alpha(root.foreground, 0.08))

          Behavior on color { ColorAnimation { duration: Style.duration(140) } }
          Behavior on border.color { ColorAnimation { duration: Style.duration(140) } }

          // Subtle top specular sheen for the active or hovered glass pill.
          Rectangle {
            visible: pillSurface.radius > 0
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: Math.round(pillSurface.radius * 0.65)
            anchors.rightMargin: Math.round(pillSurface.radius * 0.65)
            height: 1
            opacity: slot.focused ? 1.0 : (slot.hot ? 0.75 : 0.0)
            Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: "transparent" }
              GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.26) }
              GradientStop { position: 1.0; color: "transparent" }
            }
          }

          Row {
            anchors.centerIn: parent
            spacing: Style.space(6)

            // Quiet luminous accent dot cue for the focused window.
            Rectangle {
              visible: slot.focused
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(5)
              height: Style.space(5)
              radius: width / 2
              color: root.accentColor
            }

            Item {
              anchors.verticalCenter: parent.verticalCenter
              width: root.iconExtent
              height: root.iconExtent

              Image {
                id: appIcon
                property bool failed: false
                readonly property string resolvedIcon: root.windowIcon(slot.toplevel)
                onResolvedIconChanged: failed = false
                onStatusChanged: if (status === Image.Error) failed = true
                anchors.fill: parent
                source: failed ? Quickshell.iconPath("application-x-executable") : resolvedIcon
                sourceSize.width: Math.round(width * Screen.devicePixelRatio)
                sourceSize.height: Math.round(height * Screen.devicePixelRatio)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                opacity: slot.focused ? 1.0 : (slot.hot ? 0.94 : 0.56)
                Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }
              }

              Text {
                anchors.centerIn: parent
                visible: appIcon.status === Image.Error || appIcon.source.toString() === ""
                textFormat: Text.PlainText
                text: root.fallbackLetter(slot.toplevel)
                color: root.foreground
                opacity: slot.focused ? 1.0 : (slot.hot ? 0.92 : 0.60)
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                font.weight: Font.DemiBold
              }
            }

            Text {
              visible: slot.showLabel
              anchors.verticalCenter: parent.verticalCenter
              width: slot.measuredLabelWidth
              textFormat: Text.PlainText
              text: slot.labelText
              color: root.foreground
              font.family: root.uiFont
              font.pixelSize: Style.font.bodySmall
              font.weight: Font.Medium
              elide: Text.ElideRight
              verticalAlignment: Text.AlignVCenter
            }
          }
        }

        MouseArea {
          id: pointer
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            if (mouse.button === Qt.MiddleButton) root.closeWindow(slot.toplevel)
            else root.focusWindow(slot.toplevel)
          }
          onWheel: function(wheel) {
            var res = Util.wheelSteps(root.wheelRemainder, wheel.angleDelta.y)
            root.wheelRemainder = res.remainder
            if (res.steps !== 0) root.cycleFocus(res.steps > 0 ? -1 : 1)
          }
          onEntered: if (root.bar) root.bar.showTooltip(slot, root.windowLabel(slot.toplevel))
          onExited: if (root.bar) root.bar.hideTooltip(slot)
        }
      }
    }
  }
}
