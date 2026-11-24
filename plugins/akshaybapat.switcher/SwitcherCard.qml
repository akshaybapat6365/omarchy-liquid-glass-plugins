pragma ComponentBehavior: Bound
import QtQuick

// Sculpted 146x146 VisionOS / Liquid Glass window tile card.
Item {
  id: card

  property var windowData: ({})
  property bool selected: false
  property bool hovered: false
  property bool reduceMotion: false
  property color accentColor: "#7176b8"
  property color accentBright: "#9ea5f0"

  signal clicked()
  signal pointerEntered()

  readonly property string appName: String(windowData && windowData.appName ? windowData.appName : "Window")
  readonly property string titleText: String(windowData && windowData.title ? windowData.title : appName)
  readonly property string workspaceLabel: String(windowData && windowData.workspaceLabel ? windowData.workspaceLabel : "Desk 1")
  readonly property bool isMinimized: !!(windowData && windowData.minimized)
  readonly property bool isFocused: !!(windowData && windowData.focused)
  readonly property bool isFloating: !!(windowData && windowData.floating)
  readonly property string iconPath: String(windowData && windowData.iconPath ? windowData.iconPath : "")
  readonly property string monogram: String(windowData && windowData.monogram ? windowData.monogram : "W")
  readonly property real accentHue: Number(windowData && windowData.accentHue !== undefined ? windowData.accentHue : 225)

  readonly property url iconUrl: {
    if (!iconPath) return ""
    if (iconPath.indexOf("file://") === 0 || iconPath.indexOf("image://") === 0) return iconPath
    var encoded = iconPath.replace(/%/g, "%25").replace(/#/g, "%23").replace(/\?/g, "%3F").replace(/ /g, "%20")
    return "file://" + encoded
  }

  readonly property bool iconReady: iconUrl.toString().length > 0 && appIcon.status === Image.Ready

  implicitWidth: 146
  implicitHeight: 146
  width: 146
  height: 146
  z: selected ? 3 : (hovered ? 2 : 1)

  scale: selected ? 1.04 : (hovered ? 1.012 : 1.0)
  transformOrigin: Item.Center

  Behavior on scale {
    enabled: !card.reduceMotion
    NumberAnimation {
      duration: 155
      easing.type: Easing.OutCubic
    }
  }

  // Soft borderless diffused optical bloom halo around the active card (zero double-border artifact).
  Rectangle {
    anchors.fill: parent
    anchors.margins: -5
    radius: 23
    color: Qt.rgba(card.accentColor.r, card.accentColor.g, card.accentColor.b, 0.14)
    opacity: card.selected ? 1.0 : 0.0

    Behavior on opacity {
      enabled: !card.reduceMotion
      NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }
  }

  // Main sculpted Liquid Glass tile body.
  Rectangle {
    id: tileBody
    anchors.fill: parent
    radius: 18
    border.width: 1
    border.color: card.selected
      ? Qt.rgba(card.accentBright.r, card.accentBright.g, card.accentBright.b, 0.88)
      : (card.hovered ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.095))

    gradient: Gradient {
      GradientStop {
        position: 0.0
        color: card.selected
          ? Qt.rgba(card.accentColor.r * 0.85 + 0.12, card.accentColor.g * 0.85 + 0.12, card.accentColor.b * 0.85 + 0.14, 0.30)
          : (card.hovered ? Qt.rgba(1, 1, 1, 0.088) : Qt.rgba(1, 1, 1, 0.052))
      }
      GradientStop {
        position: 1.0
        color: card.selected
          ? Qt.rgba(card.accentColor.r * 0.60 + 0.05, card.accentColor.g * 0.60 + 0.05, card.accentColor.b * 0.60 + 0.08, 0.15)
          : (card.hovered ? Qt.rgba(1, 1, 1, 0.036) : Qt.rgba(1, 1, 1, 0.018))
      }
    }

    // Crisp 1px overhead specular catchlight along the upper glass edge.
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: 15
      anchors.rightMargin: 15
      anchors.topMargin: 1
      height: 1
      radius: 0.5
      color: card.selected
        ? Qt.rgba(1, 1, 1, 0.54)
        : Qt.rgba(1, 1, 1, card.hovered ? 0.22 : 0.12)
    }

    // Subtle currently-focused window indicator dot (top-left).
    Item {
      visible: card.isFocused
      width: 12
      height: 12
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.leftMargin: 11
      anchors.topMargin: 11

      Rectangle {
        anchors.centerIn: parent
        width: 12
        height: 12
        radius: 6
        color: Qt.rgba(125 / 255, 211 / 255, 252 / 255, 0.22)
      }
      Rectangle {
        anchors.centerIn: parent
        width: 6
        height: 6
        radius: 3
        color: "#7DD3FC"
      }
    }

    // Corner workspace pill (Desk N, or warm luminous amber Shelf badge for minimized windows).
    Rectangle {
      id: wsPill
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: 9
      anchors.rightMargin: 9
      height: 19
      width: Math.min(78, wsRow.implicitWidth + 12)
      radius: 9.5

      color: card.isMinimized
        ? Qt.rgba(245 / 255, 158 / 255, 11 / 255, card.selected ? 0.27 : 0.19)
        : Qt.rgba(10 / 255, 12 / 255, 19 / 255, card.selected ? 0.78 : 0.62)
      border.width: 1
      border.color: card.isMinimized
        ? Qt.rgba(251 / 255, 191 / 255, 36 / 255, card.selected ? 0.74 : 0.50)
        : Qt.rgba(1, 1, 1, card.selected ? 0.22 : 0.12)

      Row {
        id: wsRow
        anchors.centerIn: parent
        spacing: 4

        Rectangle {
          visible: card.isMinimized
          width: 5
          height: 5
          radius: 2.5
          anchors.verticalCenter: parent.verticalCenter
          color: "#FBBF24"
        }

        Text {
          textFormat: Text.PlainText
          text: card.workspaceLabel
          font.family: "Inter"
          font.weight: Font.DemiBold
          font.pixelSize: 10
          font.features: ({ "tnum": 1 })
          color: card.isMinimized
            ? "#FDE68A"
            : (card.selected ? "#EEF5FF" : "#B8C7DC")
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    // Recessed optical glass icon stage holding the crisp 48x48 application icon.
    Rectangle {
      id: iconStage
      width: 58
      height: 58
      radius: 15
      anchors.horizontalCenter: parent.horizontalCenter
      y: 31

      border.width: 1
      border.color: card.selected
        ? Qt.rgba(1, 1, 1, 0.20)
        : Qt.rgba(1, 1, 1, 0.08)

      gradient: Gradient {
        GradientStop {
          position: 0.0
          color: card.selected
            ? Qt.rgba(1, 1, 1, 0.11)
            : Qt.rgba(1, 1, 1, 0.05)
        }
        GradientStop {
          position: 1.0
          color: Qt.rgba(4 / 255, 6 / 255, 12 / 255, 0.28)
        }
      }

      // Crisp native SVG / high-DPI PNG application icon (2x supersampled for 264 PPI).
      Image {
        id: appIcon
        anchors.centerIn: parent
        width: 46
        height: 46
        source: card.iconUrl
        sourceSize: Qt.size(96, 96)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: false
        visible: card.iconReady
        opacity: (card.isMinimized && !card.selected) ? 0.80 : 1.0
      }

      // Sculpted monogram glass badge fallback if no desktop icon is available.
      Rectangle {
        anchors.centerIn: parent
        width: 46
        height: 46
        radius: 12
        visible: !card.iconReady
        opacity: (card.isMinimized && !card.selected) ? 0.82 : 1.0

        gradient: Gradient {
          GradientStop {
            position: 0.0
            color: Qt.hsla(((card.accentHue % 360) + 360) % 360 / 360.0, 0.52, 0.52, 0.46)
          }
          GradientStop {
            position: 1.0
            color: Qt.hsla(((card.accentHue % 360) + 360) % 360 / 360.0, 0.56, 0.34, 0.34)
          }
        }
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.24)

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.leftMargin: 6
          anchors.rightMargin: 6
          anchors.topMargin: 1
          height: 1
          color: Qt.rgba(1, 1, 1, 0.34)
        }

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: card.monogram
          font.family: "Inter"
          font.weight: Font.Bold
          font.pixelSize: card.monogram.length > 1 ? 17 : 20
          color: "#F5F9FF"
        }
      }
    }

    // Crisp bold application display name.
    Text {
      id: appNameText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      y: 96
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: card.appName
      font.family: "Inter"
      font.weight: Font.DemiBold
      font.pixelSize: 13
      color: card.selected ? "#F6F9FF" : "#E6EEF9"
      elide: Text.ElideRight
      maximumLineCount: 1
    }

    // Elided window title subtitle.
    Text {
      id: titleSubText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      y: 115
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: card.titleText
      font.family: "Inter"
      font.weight: Font.Normal
      font.pixelSize: 11
      color: card.selected ? "#C9D7EA" : "#8D9DB5"
      elide: Text.ElideRight
      maximumLineCount: 1
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: card.pointerEntered()
    onClicked: card.clicked()
  }
}
