pragma ComponentBehavior: Bound
import QtQuick

// Sculpted 3D-beveled tactile keycap pill (JetBrainsMono Nerd Font SemiBold),
// harmonized with Omarchy 4.5 Liquid Glass overlays.
Item {
  id: cap

  property string label: ""
  property bool compact: true
  property bool highlighted: false
  property color accentColor: "#7176b8"

  readonly property int padX: compact ? 6 : 8
  readonly property int minCapWidth: compact ? 20 : 24
  readonly property int capHeight: compact ? 19 : 23

  implicitWidth: Math.max(minCapWidth, Math.ceil(labelText.implicitWidth) + padX * 2)
  implicitHeight: capHeight

  Rectangle {
    anchors.fill: parent
    radius: cap.compact ? 5.5 : 6.5
    color: Qt.rgba(4 / 255, 5 / 255, 10 / 255, 0.78)
    border.width: 1
    border.color: cap.highlighted
      ? Qt.rgba(cap.accentColor.r, cap.accentColor.g, cap.accentColor.b, 0.58)
      : Qt.rgba(1, 1, 1, 0.15)
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: 1
    anchors.rightMargin: 1
    anchors.topMargin: 1
    height: Math.max(10, parent.height - 3)
    radius: cap.compact ? 4.5 : 5.5

    gradient: Gradient {
      GradientStop {
        position: 0.0
        color: cap.highlighted
          ? Qt.rgba(cap.accentColor.r, cap.accentColor.g, cap.accentColor.b, 0.34)
          : Qt.rgba(1, 1, 1, 0.165)
      }
      GradientStop {
        position: 1.0
        color: cap.highlighted
          ? Qt.rgba(cap.accentColor.r, cap.accentColor.g, cap.accentColor.b, 0.15)
          : Qt.rgba(1, 1, 1, 0.068)
      }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: 3
      anchors.rightMargin: 3
      height: 1
      radius: 0.5
      color: cap.highlighted
        ? Qt.rgba(1, 1, 1, 0.44)
        : Qt.rgba(1, 1, 1, 0.30)
    }
  }

  Text {
    id: labelText
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -0.5
    textFormat: Text.PlainText
    text: cap.label
    font.family: "JetBrainsMono Nerd Font"
    font.weight: Font.DemiBold
    font.pixelSize: cap.compact ? 10 : 11
    color: cap.highlighted ? "#F6FAFF" : "#EAF1FF"
  }
}
