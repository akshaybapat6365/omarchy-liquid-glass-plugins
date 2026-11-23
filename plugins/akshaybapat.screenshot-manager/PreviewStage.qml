pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Item {
  id: root

  property var screenshots: []
  property int currentIndex: -1
  property bool busy: false
  property bool canOpenFolder: true
  property bool justCopied: false
  property string pendingTrashKey: ""
  property bool synchronousLoad: false

  signal dismissRequested()
  signal stepRequested(int delta)
  signal copyRequested(var screenshot)
  signal openRequested(var screenshot)
  signal folderRequested()
  signal deleteRequested(var screenshot)

  readonly property var currentScreenshot: root.currentIndex >= 0 && root.currentIndex < root.screenshots.length
    ? root.screenshots[root.currentIndex]
    : null
  readonly property string currentKey: root.currentScreenshot ? Model.screenshotKey(root.currentScreenshot) : ""
  readonly property int previewWidth: root.currentScreenshot ? Number(root.currentScreenshot.width || 0) : 0
  readonly property int previewHeight: root.currentScreenshot ? Number(root.currentScreenshot.height || 0) : 0
  readonly property bool deleteArmed: root.currentKey !== "" && root.pendingTrashKey === root.currentKey

  readonly property color foreground: Commons.Color.foreground
  readonly property color background: Commons.Color.background
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property color dim: Util.alpha(root.foreground, 0.66)
  readonly property color faint: Util.alpha(root.foreground, 0.46)
  readonly property color scrim: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.84)

  readonly property string monoFont: Style.font.family
  readonly property string uiFont: (Style.font.menuFamily && Style.font.menuFamily !== Style.font.family && Style.font.menuFamily !== "monospace")
    ? Style.font.menuFamily
    : "Inter Display"

  readonly property int frameRadius: Math.max(10, Style.cornerRadius)

  focus: true

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return) {
      root.dismissRequested()
    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
      root.stepRequested(-1)
    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
      root.stepRequested(1)
    }
    event.accepted = true
  }

  component HudActionButton: Rectangle {
    id: hudBtn

    property string glyph: ""
    property string label: ""
    property string keycap: ""
    property bool activeTint: false
    property bool danger: false
    property bool armed: false
    property bool buttonEnabled: true

    signal triggered()

    readonly property bool hot: hudMouse.containsMouse && buttonEnabled

    implicitHeight: Style.space(30)
    implicitWidth: btnRow.implicitWidth + Style.space(18)
    radius: height / 2
    opacity: buttonEnabled ? 1.0 : 0.42

    color: armed
      ? Util.alpha(root.urgent, 0.24)
      : (activeTint
        ? Util.alpha(root.accent, 0.22)
        : (hot
          ? (danger ? Util.alpha(root.urgent, 0.16) : Util.alpha(root.foreground, 0.12))
          : "transparent"))
    border.width: (armed || activeTint || hot) ? Style.spacing.hairline : 0
    border.color: armed
      ? Util.alpha(root.urgent, 0.56)
      : (activeTint
        ? Util.alpha(root.accent, 0.48)
        : (hot
          ? (danger ? Util.alpha(root.urgent, 0.36) : Util.alpha(root.foreground, 0.20))
          : "transparent"))

    Behavior on color { ColorAnimation { duration: Style.duration(130) } }
    Behavior on border.color { ColorAnimation { duration: Style.duration(130) } }

    Row {
      id: btnRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {
        visible: hudBtn.glyph !== ""
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: hudBtn.glyph
        color: hudBtn.armed
          ? root.urgent
          : (hudBtn.activeTint
            ? root.accent
            : (hudBtn.hot && hudBtn.danger ? root.urgent : root.foreground))
        font.family: root.monoFont
        font.pixelSize: Style.font.icon
      }

      Text {
        visible: hudBtn.label !== ""
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: hudBtn.label
        color: hudBtn.armed
          ? root.urgent
          : (hudBtn.activeTint
            ? root.accent
            : (hudBtn.hot && hudBtn.danger ? root.urgent : root.foreground))
        font.family: root.uiFont
        font.pixelSize: Style.font.bodySmall
        font.weight: Font.Medium
      }

      Rectangle {
        visible: hudBtn.keycap !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: keycapLabel.implicitWidth + Style.space(10)
        height: Style.space(18)
        radius: Style.space(5)
        color: Util.alpha(root.foreground, 0.08)
        border.width: Style.spacing.hairline
        border.color: Util.alpha(root.foreground, 0.16)

        Text {
          id: keycapLabel
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: hudBtn.keycap
          color: root.dim
          font.family: root.monoFont
          font.pixelSize: Style.font.caption
          font.features: ({ "tnum": 1 })
        }
      }
    }

    MouseArea {
      id: hudMouse
      anchors.fill: parent
      enabled: hudBtn.buttonEnabled
      hoverEnabled: true
      cursorShape: hudBtn.buttonEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: hudBtn.triggered()
    }
  }

  component HudDivider: Rectangle {
    width: Style.spacing.hairline
    height: Style.space(16)
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    color: Util.alpha(root.foreground, 0.14)
  }

  component NavArrowButton: Rectangle {
    id: navBtn

    property string glyph: ""
    signal triggered()

    readonly property bool hot: navMouse.containsMouse

    width: Style.space(38)
    height: Style.space(38)
    radius: width / 2
    color: hot
      ? Qt.rgba(root.background.r, root.background.g, root.background.b, 0.88)
      : Qt.rgba(root.background.r, root.background.g, root.background.b, 0.68)
    border.width: Style.spacing.hairline
    border.color: hot ? Util.alpha(root.foreground, 0.28) : Util.alpha(root.foreground, 0.16)

    Behavior on color { ColorAnimation { duration: Style.duration(140) } }
    Behavior on border.color { ColorAnimation { duration: Style.duration(140) } }

    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      color: Util.alpha(root.foreground, navBtn.hot ? 0.09 : 0.04)
      Behavior on color { ColorAnimation { duration: Style.duration(140) } }
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: navBtn.glyph
      color: navBtn.hot ? root.foreground : root.dim
      font.family: root.monoFont
      font.pixelSize: Style.font.iconLarge
    }

    MouseArea {
      id: navMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: navBtn.triggered()
    }
  }

  Rectangle {
    anchors.fill: parent
    color: root.scrim

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.025) }
        GradientStop { position: 0.45; color: "transparent" }
        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.20) }
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismissRequested()
    }

    Item {
      id: stage
      anchors.fill: parent
      anchors.topMargin: Style.space(36)
      anchors.bottomMargin: Style.space(28)
      anchors.leftMargin: Style.space(48)
      anchors.rightMargin: Style.space(48)

      ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(18)

        Item {
          id: stagePicture
          Layout.fillWidth: true
          Layout.fillHeight: true

          readonly property real sideGutter: root.screenshots.length > 1 ? Style.space(56) : 0
          readonly property real maxW: Math.max(1, stagePicture.width - 2 * stagePicture.sideGutter)
          readonly property real maxH: Math.max(1, stagePicture.height)
          readonly property bool sized: root.previewWidth > 0 && root.previewHeight > 0
          readonly property real fitScale: stagePicture.sized
            ? Math.min(1, stagePicture.maxW / root.previewWidth, stagePicture.maxH / root.previewHeight)
            : 1
          readonly property real frameW: stagePicture.sized
            ? Math.round(root.previewWidth * stagePicture.fitScale)
            : stagePicture.maxW
          readonly property real frameH: stagePicture.sized
            ? Math.round(root.previewHeight * stagePicture.fitScale)
            : stagePicture.maxH

          // Soft layered ambient elevation behind the framed screenshot.
          Rectangle {
            anchors.centerIn: imageFrame
            width: imageFrame.width + Style.space(32)
            height: imageFrame.height + Style.space(32)
            anchors.verticalCenterOffset: Style.space(10)
            radius: root.frameRadius + Style.space(14)
            color: Qt.rgba(0, 0, 0, 0.26)
          }

          Rectangle {
            anchors.centerIn: imageFrame
            width: imageFrame.width + Style.space(14)
            height: imageFrame.height + Style.space(14)
            anchors.verticalCenterOffset: Style.space(5)
            radius: root.frameRadius + Style.space(6)
            color: Qt.rgba(0, 0, 0, 0.36)
          }

          Rectangle {
            id: imageFrame
            anchors.centerIn: parent
            width: stagePicture.frameW
            height: stagePicture.frameH
            radius: root.frameRadius
            color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.65)
            clip: true

            MouseArea {
              anchors.fill: parent
            }

            Item {
              id: imageMask
              anchors.fill: parent
              visible: false
              layer.enabled: root.frameRadius > 0

              Rectangle {
                anchors.fill: parent
                radius: root.frameRadius
                color: "white"
              }
            }

            Item {
              anchors.fill: parent
              layer.enabled: root.frameRadius > 0
              layer.smooth: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: imageMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
              }

              Image {
                id: previewImage
                anchors.fill: parent
                source: root.currentScreenshot && (root.currentScreenshot.path || root.currentScreenshot.previewPath)
                  ? "file://" + (root.currentScreenshot.path || root.currentScreenshot.previewPath)
                  : ""
                sourceSize.width: Math.min(3840, Math.max(1, Math.round(width)))
                sourceSize.height: Math.min(2160, Math.max(1, Math.round(height)))
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: !root.synchronousLoad
              }
            }

            // Crisp 1 px neutral hairline bezel.
            Rectangle {
              anchors.fill: parent
              radius: root.frameRadius
              color: "transparent"
              border.width: Style.spacing.hairline
              border.color: Util.alpha(root.foreground, 0.22)
            }

            // Subtle top specular sheen across the upper edge.
            Rectangle {
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.topMargin: 1
              anchors.leftMargin: Math.round(root.frameRadius * 0.7)
              anchors.rightMargin: Math.round(root.frameRadius * 0.7)
              height: 1
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, 0.16) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.28) }
                GradientStop { position: 0.75; color: Qt.rgba(1, 1, 1, 0.16) }
                GradientStop { position: 1.0; color: "transparent" }
              }
            }
          }

          NavArrowButton {
            visible: root.screenshots.length > 1
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: "󰅁"
            onTriggered: root.stepRequested(-1)
          }

          NavArrowButton {
            visible: root.screenshots.length > 1
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            glyph: "󰅂"
            onTriggered: root.stepRequested(1)
          }
        }

        ColumnLayout {
          Layout.alignment: Qt.AlignHCenter
          spacing: Style.space(10)

          Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.space(10)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.currentScreenshot ? root.currentScreenshot.name : ""
              color: root.foreground
              font.family: root.uiFont
              font.pixelSize: Style.font.subtitle
              font.weight: Font.Medium
              elide: Text.ElideMiddle
              width: Math.min(implicitWidth, Style.space(340))
            }

            Text {
              visible: root.currentScreenshot !== null && Model.friendlyDate(root.currentScreenshot.mtimeIso) !== ""
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.currentScreenshot ? "·  " + Model.friendlyDate(root.currentScreenshot.mtimeIso) : ""
              color: root.dim
              font.family: root.uiFont
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              visible: root.currentScreenshot !== null
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: {
                if (!root.currentScreenshot) return ""
                var parts = []
                var dims = Model.dimensionsText(root.currentScreenshot)
                if (dims) parts.push(dims)
                if (root.currentScreenshot.humanSize) parts.push(root.currentScreenshot.humanSize)
                parts.push((root.currentIndex + 1) + " / " + root.screenshots.length)
                return "·  " + parts.join("  ·  ")
              }
              color: root.faint
              font.family: root.monoFont
              font.pixelSize: Style.font.caption
              font.features: ({ "tnum": 1 })
            }
          }

          // Floating macOS frosted glass HUD pill.
          Rectangle {
            id: hudPill
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: hudRow.implicitWidth + Style.space(14)
            implicitHeight: Style.space(42)
            radius: implicitHeight / 2
            color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.84)
            border.width: Style.spacing.hairline
            border.color: Util.alpha(root.foreground, 0.20)

            Rectangle {
              anchors.fill: parent
              radius: parent.radius
              color: Util.alpha(root.foreground, 0.055)
            }

            Rectangle {
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.topMargin: 1
              anchors.leftMargin: Math.round(hudPill.radius * 0.85)
              anchors.rightMargin: Math.round(hudPill.radius * 0.85)
              height: 1
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, 0.16) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.28) }
                GradientStop { position: 0.75; color: Qt.rgba(1, 1, 1, 0.16) }
                GradientStop { position: 1.0; color: "transparent" }
              }
            }

            MouseArea {
              anchors.fill: parent
            }

            Row {
              id: hudRow
              anchors.centerIn: parent
              spacing: Style.space(4)

              HudActionButton {
                glyph: root.justCopied ? "󰄬" : "󰅌"
                label: root.justCopied ? "Copied" : "Copy"
                activeTint: root.justCopied
                buttonEnabled: !root.busy && root.currentScreenshot !== null
                onTriggered: root.copyRequested(root.currentScreenshot)
              }

              HudDivider {}

              HudActionButton {
                glyph: "󰏌"
                label: "Open"
                buttonEnabled: root.currentScreenshot !== null
                onTriggered: root.openRequested(root.currentScreenshot)
              }

              HudActionButton {
                glyph: "󰝰"
                label: "Folder"
                buttonEnabled: root.canOpenFolder
                onTriggered: root.folderRequested()
              }

              HudDivider {}

              HudActionButton {
                glyph: root.deleteArmed ? "󰄬" : "󰩹"
                label: root.deleteArmed ? "Confirm" : "Delete"
                danger: true
                armed: root.deleteArmed
                buttonEnabled: !root.busy && root.currentScreenshot !== null
                onTriggered: root.deleteRequested(root.currentScreenshot)
              }

              HudDivider {}

              HudActionButton {
                keycap: "Esc"
                onTriggered: root.dismissRequested()
              }
            }
          }
        }
      }
    }
  }
}
