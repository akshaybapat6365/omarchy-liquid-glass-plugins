import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "OsdModel.js" as OsdModel

Item {
  id: root

  property bool opened: false
  property bool _surfaceMapped: false
  property string icon: ""
  property string message: ""
  property string iconKey: ""
  property int value: 0
  property int maxValue: 100
  property bool hasProgress: true
  property int duration: 1200

  readonly property bool mediaOsd: iconKey.indexOf("media") === 0 || iconKey.indexOf("player") === 0
  property real displayRatio: 0.0

  Behavior on displayRatio {
    enabled: root.opened && !Style.reduceMotion
    NumberAnimation {
      duration: Style.duration(150)
      easing.type: Easing.BezierSpline
      easing.bezierCurve: [0.18, 0.96, 0.30, 1.0, 1.0, 1.0]
    }
  }

  // Lift pure #000000 backgrounds subtly to smoked obsidian so the glass pill
  // carries depth over dark wallpapers while tracking every other theme's tint.
  readonly property color glassTint: {
    var bg = Commons.Color.background
    var nearBlack = bg.r < 0.025 && bg.g < 0.025 && bg.b < 0.025
    if (nearBlack) return Qt.rgba(16 / 255, 17 / 255, 22 / 255, 0.78)
    return Qt.rgba(bg.r, bg.g, bg.b, 0.78)
  }

  // Balanced capsule pill geometry: horizontal padding slightly wider than
  // vertical so the semicircular ends frame the icon and tabular digits cleanly.
  readonly property int padX: Style.space(20)
  readonly property int padY: Style.space(12)
  readonly property int gap: Style.space(14)
  readonly property int messageGap: Style.space(11)
  readonly property int barWidth: Style.space(148)
  readonly property int maxMessageWidth: root.mediaOsd ? Style.space(325) : Style.space(210)
  readonly property int pillHeight: Math.max(Style.space(48), Style.font.displayLarge + root.padY * 2)

  // Nerd Font glyphs draw outside their monospace advance; pin progress OSD
  // icon column to the widest glyph so the pill bar never shifts on thresholds.
  readonly property int iconInkWidth: Math.ceil(iconMetrics.tightBoundingRect.width)
  readonly property int iconWidth: root.hasProgress
    ? Math.max(root.iconInkWidth, Math.ceil(widestIconMetrics.tightBoundingRect.width))
    : root.iconInkWidth
  readonly property int valueWidth: Math.ceil(Math.max(valueMetrics.advanceWidth, messageMetrics.advanceWidth))
  readonly property int messageWidth: Math.min(Math.ceil(messageMetrics.advanceWidth), root.maxMessageWidth)
  readonly property int contentWidth: root.hasProgress
    ? root.iconWidth + root.gap + root.barWidth + root.gap + root.valueWidth
    : (root.message === "" ? root.iconWidth : root.iconWidth + root.messageGap + root.messageWidth)

  function iconFor(name, percent) {
    return OsdModel.iconFor(name, percent)
  }

  function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
    var next = OsdModel.stateForShow(
      iconName,
      rawMessage,
      rawValue,
      rawMax,
      rawProgressText,
      rawDuration,
      Commons.I18n.formatNumber
    )
    exitTimer.stop()
    iconKey = next.iconKey
    maxValue = next.maxValue
    hasProgress = next.hasProgress
    value = next.value
    message = next.message
    icon = next.icon
    duration = next.duration
    // Update displayRatio before flipping opened=true so a fresh open starts
    // immediately at the new value, while subsequent updates while already
    // open animate smoothly through Behavior on displayRatio.
    displayRatio = next.hasProgress
      ? Math.max(0.0, Math.min(1.0, next.value / Math.max(1, next.maxValue)))
      : 0.0
    _surfaceMapped = true
    opened = true
    if (duration > 0) hideTimer.restart()
    else hideTimer.stop()
  }

  function open(payloadJson) {
    try {
      const p = JSON.parse(payloadJson || "{}")
      show(
        p.icon || "",
        p.message || "",
        p.value === undefined ? "" : String(p.value),
        p.max === undefined ? "100" : String(p.max),
        p.progressText || "",
        p.duration === undefined ? "1200" : String(p.duration)
      )
    } catch (e) {}
  }

  function close() {
    hideTimer.stop()
    if (!opened) {
      if (!_surfaceMapped) return
    }
    opened = false
    if (Style.reduceMotion) {
      _surfaceMapped = false
    } else {
      exitTimer.restart()
    }
  }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.close()
  }

  Timer {
    id: exitTimer
    interval: Style.duration(175)
    onTriggered: {
      if (!root.opened) root._surfaceMapped = false
    }
  }

  TextMetrics {
    id: messageMetrics
    font.family: "Inter"
    font.weight: Font.DemiBold
    font.pixelSize: Style.font.title
    font.features: ({ "tnum": 1 })
    text: root.message
  }

  TextMetrics {
    id: valueMetrics
    font: messageMetrics.font
    text: Commons.I18n.formatNumber(100) + "%"
  }

  TextMetrics {
    id: iconMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.display
    text: root.icon
  }

  TextMetrics {
    id: widestIconMetrics
    font: iconMetrics.font
    text: OsdModel.widestIcon
  }

  ShellIpc {
    target: "osd"
    function show(payloadJson: string): string {
      root.open(payloadJson)
      return "ok"
    }
    function close(): string {
      root.close()
      return "ok"
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
    shownKeyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "omarchy-osd"
    // Visual-only surface: empty input mask so clicks pass straight through.
    mask: Region {}

    readonly property bool visualActive: root.opened && panel.contentRevealed

    Item {
      id: card
      width: root.padX + root.contentWidth + root.padX
      height: root.pillHeight
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(64)

      opacity: panel.visualActive ? 1.0 : 0.0
      scale: panel.visualActive ? 1.0 : 0.94
      transformOrigin: Item.Bottom

      transform: Translate {
        y: panel.visualActive ? 0 : Style.space(6)
        Behavior on y {
          enabled: !Style.reduceMotion
          NumberAnimation {
            duration: panel.visualActive ? Style.duration(220) : Style.duration(150)
            easing.type: panel.visualActive ? Easing.OutQuart : Easing.InCubic
          }
        }
      }

      Behavior on opacity {
        enabled: !Style.reduceMotion
        NumberAnimation {
          duration: panel.visualActive ? Style.duration(170) : Style.duration(150)
          easing.type: Easing.OutCubic
        }
      }

      Behavior on scale {
        enabled: !Style.reduceMotion
        NumberAnimation {
          duration: panel.visualActive ? Style.duration(220) : Style.duration(150)
          easing.type: panel.visualActive ? Easing.OutQuart : Easing.InCubic
        }
      }

      // Compiled Qt 6.12 optical Liquid Glass capsule shader with top-edge
      // Fresnel sheen and crisp 1px specular glass bezel.
      ShaderEffect {
        id: glassShader
        anchors.fill: parent
        property vector2d iResolution: Qt.vector2d(Math.max(2, width), Math.max(2, height))
        property color tintColor: root.glassTint
        property color accentColor: Commons.Color.accent
        property real progress: root.displayRatio
        property real hasProgress: root.hasProgress ? 1.0 : 0.0
        fragmentShader: Qt.resolvedUrl("shaders/glass_pill.frag.qsb")
      }

      // Graceful software fallback if the shader has not compiled.
      Rectangle {
        anchors.fill: parent
        visible: glassShader.status !== ShaderEffect.Compiled
        radius: height / 2
        color: root.glassTint
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.24)
      }

      Row {
        anchors.fill: parent
        anchors.leftMargin: root.padX
        anchors.rightMargin: root.padX
        anchors.topMargin: root.padY
        anchors.bottomMargin: root.padY
        spacing: root.hasProgress ? root.gap : root.messageGap

        Item {
          width: root.iconWidth
          height: parent.height
          Text {
            textFormat: Text.PlainText
            x: Math.round((root.iconWidth - root.iconInkWidth) / 2 - iconMetrics.tightBoundingRect.x)
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font: iconMetrics.font
            color: Commons.Color.popups.text
          }
        }

        // Sculpted pill track + critically-damped luminous progress bar.
        Rectangle {
          id: track
          visible: root.hasProgress
          width: root.barWidth
          height: Style.space(6)
          radius: height / 2
          anchors.verticalCenter: parent.verticalCenter
          color: Util.alpha(Commons.Color.popups.text, 0.16)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.08)
          clip: true

          Rectangle {
            id: fill
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            radius: height / 2
            readonly property real rawWidth: parent.width * root.displayRatio
            width: root.displayRatio <= 0.001 ? 0 : Math.max(height, rawWidth)
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: Qt.darker(Commons.Color.accent, 1.12) }
              GradientStop { position: 0.75; color: Commons.Color.accent }
              GradientStop { position: 1.0; color: Qt.lighter(Commons.Color.accent, 1.16) }
            }

            // Crisp 1px overhead catchlight along the active pill fill.
            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.leftMargin: 2
              anchors.rightMargin: 2
              height: 1
              radius: 0.5
              color: Qt.rgba(1, 1, 1, 0.36)
              visible: parent.width > 6
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.message !== ""
          width: root.hasProgress ? root.valueWidth : root.messageWidth
          horizontalAlignment: root.hasProgress ? Text.AlignRight : Text.AlignLeft
          anchors.verticalCenter: parent.verticalCenter
          text: root.message
          font: messageMetrics.font
          color: Commons.Color.popups.text
          elide: Text.ElideRight
          maximumLineCount: 1
        }
      }
    }
  }
}
