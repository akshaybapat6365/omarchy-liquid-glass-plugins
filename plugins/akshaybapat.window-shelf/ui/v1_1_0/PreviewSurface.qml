pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  property var toplevel: null
  property string titleText: ""
  property string iconSource: ""
  property string fallbackLetter: "W"
  property string previewImageSource: ""
  property bool live: false
  property bool open: false
  property bool peeked: false
  property bool synchronousLoad: false

  readonly property color foreground: Commons.Color.popups.text
  readonly property color background: Commons.Color.background
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Util.alpha(root.foreground, 0.62)
  readonly property color faint: Util.alpha(root.foreground, 0.44)

  readonly property string uiFont: (Style.font.menuFamily && Style.font.menuFamily !== Style.font.family && Style.font.menuFamily !== "monospace")
    ? Style.font.menuFamily
    : "Inter Display"

  // Concentric inner thumbnail rounding matching Overview and the desktop's 12 px rounding.
  readonly property int thumbRadius: Math.max(8, Style.cornerRadius - 2)
  readonly property bool rounded: root.thumbRadius > 0 && (root.open || root.previewImageSource !== "")
  readonly property bool hasPreview: previewView.hasContent || (root.previewImageSource !== "" && previewFallbackImage.status === Image.Ready)

  // Subtle top specular highlight along the popup card interior.
  Rectangle {
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: -Style.space(7)
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(12)
    height: 1
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: "transparent" }
      GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, 0.14) }
      GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.24) }
      GradientStop { position: 0.75; color: Qt.rgba(1, 1, 1, 0.14) }
      GradientStop { position: 1.0; color: "transparent" }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(8)

    // Smooth concentric rounded thumbnail frame with 1 px neutral hairline rim.
    Rectangle {
      id: previewFrame
      Layout.fillWidth: true
      Layout.fillHeight: true
      radius: root.thumbRadius
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.58)
      clip: true

      Item {
        id: previewMask
        anchors.fill: parent
        visible: false
        layer.enabled: root.rounded

        Rectangle {
          anchors.fill: parent
          radius: root.thumbRadius
          color: "white"
        }
      }

      Item {
        anchors.fill: parent
        layer.enabled: root.rounded
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: previewMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 1.0
        }

        // App icon placeholder while the live ScreencopyView frame arrives.
        Image {
          width: Style.space(44)
          height: width
          anchors.centerIn: parent
          source: root.iconSource
          sourceSize.width: Math.round(width * Screen.devicePixelRatio)
          sourceSize.height: Math.round(height * Screen.devicePixelRatio)
          fillMode: Image.PreserveAspectFit
          opacity: root.hasPreview ? 0 : 0.55
          Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }
        }

        // Static image source only used when explicitly supplied (e.g. offscreen QA).
        Image {
          id: previewFallbackImage
          anchors.fill: parent
          visible: root.previewImageSource !== "" && !previewView.hasContent
          source: root.previewImageSource
          fillMode: Image.PreserveAspectCrop
          smooth: true
          asynchronous: !root.synchronousLoad
        }

        ScreencopyView {
          id: previewView
          anchors.fill: parent
          captureSource: root.toplevel && root.toplevel.wayland ? root.toplevel.wayland : null
          live: root.live
          paintCursor: false
          opacity: hasContent ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: Style.duration(150) } }
        }
      }

      // Crisp 1 px neutral hairline rim over thumbnail corners.
      Rectangle {
        anchors.fill: parent
        radius: root.thumbRadius
        color: "transparent"
        border.width: Style.spacing.hairline
        border.color: root.peeked ? Util.alpha(root.accent, 0.44) : Util.alpha(root.foreground, 0.16)
      }

      // Subtle top specular highlight on the thumbnail glass edge.
      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 1
        anchors.leftMargin: Math.round(root.thumbRadius * 0.7)
        anchors.rightMargin: Math.round(root.thumbRadius * 0.7)
        height: 1
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.22) }
          GradientStop { position: 1.0; color: "transparent" }
        }
      }
    }

    // Refined Inter Display title + action hint footer.
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(2)
      Layout.rightMargin: Style.space(2)
      spacing: Style.space(8)

      Rectangle {
        Layout.preferredWidth: Style.space(24)
        Layout.preferredHeight: Style.space(24)
        Layout.alignment: Qt.AlignVCenter
        radius: Style.space(6)
        color: Util.alpha(root.foreground, 0.06)
        border.width: Style.spacing.hairline
        border.color: Util.alpha(root.foreground, 0.12)

        Image {
          id: footerIcon
          anchors.centerIn: parent
          width: Style.space(16)
          height: Style.space(16)
          source: root.iconSource
          sourceSize.width: Math.round(width * Screen.devicePixelRatio)
          sourceSize.height: Math.round(height * Screen.devicePixelRatio)
          fillMode: Image.PreserveAspectFit
          smooth: true
          asynchronous: !root.synchronousLoad
        }

        Text {
          anchors.centerIn: parent
          visible: footerIcon.status === Image.Error || footerIcon.source.toString() === ""
          textFormat: Text.PlainText
          text: root.fallbackLetter
          color: root.foreground
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.titleText || "Window"
          color: root.foreground
          font.family: root.uiFont
          font.pixelSize: Style.font.bodySmall
          font.weight: Font.Medium
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.peeked
            ? "Click to restore · Right-click to close Peek"
            : "Click to restore · Right-click to Peek"
          color: root.faint
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Rectangle {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: badgeLabel.implicitWidth + Style.space(12)
        implicitHeight: Style.space(20)
        radius: implicitHeight / 2
        color: root.peeked ? Util.alpha(root.accent, 0.18) : Util.alpha(root.foreground, 0.06)
        border.width: Style.spacing.hairline
        border.color: root.peeked ? Util.alpha(root.accent, 0.44) : Util.alpha(root.foreground, 0.12)

        Text {
          id: badgeLabel
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.peeked ? "Peek" : "Shelved"
          color: root.peeked ? root.accent : root.dim
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          font.weight: Font.Medium
        }
      }
    }
  }
}
