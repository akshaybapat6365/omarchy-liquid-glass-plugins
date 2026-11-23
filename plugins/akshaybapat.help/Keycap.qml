import QtQuick

// Sculpted 3D-beveled tactile keycap pill (JetBrainsMono Nerd Font SemiBold).
Item {
  id: cap

  property string label: ""
  property bool compact: false
  property bool modifier: false
  property bool highlighted: false
  property color accentColor: "#7176b8"

  readonly property int padX: compact ? 6 : 8
  readonly property int minCapWidth: compact ? 20 : 25
  readonly property int capHeight: compact ? 20 : 25

  implicitWidth: Math.max(minCapWidth, Math.ceil(labelText.implicitWidth) + padX * 2)
  implicitHeight: capHeight

  // Outer physical keycap socket & lower beveled skirt shadow.
  Rectangle {
    anchors.fill: parent
    radius: cap.compact ? 5.5 : 6.5
    color: Qt.rgba(4 / 255, 5 / 255, 10 / 255, 0.78)
    border.width: 1
    border.color: cap.highlighted
      ? Qt.rgba(cap.accentColor.r, cap.accentColor.g, cap.accentColor.b, 0.55)
      : Qt.rgba(1, 1, 1, cap.modifier ? 0.10 : 0.15)
  }

  // Sculpted upper keycap face raised 2px above the bottom lip.
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
          : (cap.modifier ? Qt.rgba(1, 1, 1, 0.115) : Qt.rgba(1, 1, 1, 0.17))
      }
      GradientStop {
        position: 1.0
        color: cap.highlighted
          ? Qt.rgba(cap.accentColor.r, cap.accentColor.g, cap.accentColor.b, 0.16)
          : (cap.modifier ? Qt.rgba(1, 1, 1, 0.048) : Qt.rgba(1, 1, 1, 0.075))
      }
    }

    // Crisp 1px top beveled inner catchlight.
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: 3
      anchors.rightMargin: 3
      height: 1
      radius: 0.5
      color: cap.highlighted
        ? Qt.rgba(1, 1, 1, 0.42)
        : Qt.rgba(1, 1, 1, cap.modifier ? 0.20 : 0.32)
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
    color: cap.highlighted
      ? "#F6FAFF"
      : (cap.modifier ? "#CAD7E8" : "#F1F6FF")
  }
}
