import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BorderSurface {
    id: root

    required property var group
    property int selectedIndex: -1
    property color foreground: Commons.Color.foreground
    property string fontFamily: Style.font.family
    property string uiFont: {
        var f = Style.font.menuFamily;
        return (f && f.length > 0 && f !== Style.font.family && f !== "monospace") ? f : "Inter Display";
    }
    readonly property int cardRadius: Math.max(8, Style.cornerRadius - 2)
    readonly property color secondary: Qt.darker(foreground, 1.45)
    readonly property int rowCount: group ? Number(group.count || 0) : 0
    readonly property bool urgent: group && group.urgent === true
    readonly property string iconSource: group ? String(group.iconSource || "") : ""

    signal rowHovered(int flatIndex, bool isHovered)
    signal rowActivateRequested(string key)
    signal rowDismissRequested(string key)

    function alpha(colorValue, opacity) {
        return Qt.rgba(colorValue.r, colorValue.g, colorValue.b, opacity);
    }

    function rowBounds(rowIndex) {
        var wrapper = rowsRepeater.itemAt(Number(rowIndex));
        if (!wrapper)
            return null;

        return {
            "top": groupColumn.y + wrapper.y,
            "bottom": groupColumn.y + wrapper.y + wrapper.height
        };
    }

    Accessible.role: Accessible.Grouping
    Accessible.name: group ? String(group.app || "Unknown application") + ", " + String(group.count || 0) + " notifications" : "Notification group"
    color: alpha(foreground, 0.045)
    borderSpec: Border.flat(urgent ? alpha(Commons.Color.urgent, 0.28) : alpha(foreground, 0.11), 1)
    radius: cardRadius
    implicitWidth: Style.space(400)
    implicitHeight: groupColumn.implicitHeight + borderTop + borderBottom
    clip: true

    Behavior on color {
        ColorAnimation {
            duration: Style.duration(120)
        }

    }

    Rectangle {
        x: root.borderLeft + Math.round(root.cardRadius * 0.5)
        y: root.borderTop
        width: Math.max(0, root.width - root.borderLeft - root.borderRight - root.cardRadius)
        height: 1
        z: 2

        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0
                color: "transparent"
            }

            GradientStop {
                position: 0.25
                color: root.alpha(root.foreground, 0.14)
            }

            GradientStop {
                position: 0.75
                color: root.alpha(root.foreground, 0.14)
            }

            GradientStop {
                position: 1
                color: "transparent"
            }

        }

    }

    Column {
        id: groupColumn

        x: root.borderLeft
        y: root.borderTop
        width: root.width - root.borderLeft - root.borderRight

        Item {
            width: parent.width
            height: Style.space(34)

            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(8)

                Rectangle {
                    id: groupIconSlot

                    readonly property bool showsIcon: root.iconSource !== "" && groupIconImage.status !== Image.Error

                    Layout.preferredWidth: Style.space(22)
                    Layout.preferredHeight: Style.space(22)
                    Layout.alignment: Qt.AlignVCenter
                    radius: Math.max(6, Math.round(root.cardRadius * 0.65))
                    color: showsIcon ? "transparent" : (root.urgent ? root.alpha(Commons.Color.urgent, 0.15) : root.alpha(root.foreground, 0.08))
                    border.width: showsIcon ? 0 : 1
                    border.color: root.urgent ? root.alpha(Commons.Color.urgent, 0.34) : root.alpha(root.foreground, 0.12)

                    Image {
                        id: groupIconImage

                        anchors.fill: parent
                        anchors.margins: Style.space(2)
                        visible: groupIconSlot.showsIcon
                        source: root.iconSource
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !groupIconSlot.showsIcon
                        text: {
                            if (root.group && String(root.group.glyph || ""))
                                return String(root.group.glyph);

                            var app = root.group ? String(root.group.app || "") : "";
                            return app ? app.charAt(0).toUpperCase() : "N";
                        }
                        textFormat: Text.PlainText
                        color: root.urgent ? Commons.Color.urgent : root.foreground
                        font.family: (root.group && String(root.group.glyph || "")) ? root.fontFamily : root.uiFont
                        font.pixelSize: Style.font.caption
                        font.bold: true
                    }

                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignVCenter
                    text: root.group ? String(root.group.app || "Unknown application") : ""
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.uiFont
                    font.pixelSize: Style.font.body
                    font.weight: Font.DemiBold
                    font.letterSpacing: Style.spaceReal(-0.1)
                    elide: Text.ElideRight
                }

                Rectangle {
                    // A single-notification card has nothing to summarise: the
                    // count pill and group time only appear for multi-item groups.
                    visible: root.rowCount > 1
                    Layout.preferredWidth: countBadgeText.implicitWidth + Style.space(12)
                    Layout.preferredHeight: countBadgeText.implicitHeight + Style.space(4)
                    Layout.alignment: Qt.AlignVCenter
                    radius: height / 2
                    color: root.alpha(root.foreground, 0.08)
                    border.width: 1
                    border.color: root.alpha(root.foreground, 0.11)

                    Text {
                        id: countBadgeText

                        anchors.centerIn: parent
                        text: String(root.rowCount)
                        textFormat: Text.PlainText
                        color: root.secondary
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        font.features: ({
                            "tnum": 1
                        })
                    }

                }

                Text {
                    visible: root.rowCount > 1
                    Layout.alignment: Qt.AlignVCenter
                    text: root.group ? String(root.group.latestLabel || "") : ""
                    textFormat: Text.PlainText
                    color: root.secondary
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.features: ({
                        "tnum": 1
                    })
                }

            }

        }

        Repeater {
            id: rowsRepeater

            model: root.group && root.group.rows ? root.group.rows : []

            delegate: Column {
                id: rowWrapper

                required property var modelData
                required property int index

                width: groupColumn.width

                Item {
                    width: parent.width
                    height: 1

                    PanelSeparator {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: rowWrapper.index === 0 ? 0 : Style.space(12)
                        anchors.rightMargin: rowWrapper.index === 0 ? 0 : Style.space(12)
                        foreground: root.foreground
                        strength: 0.08
                    }

                }

                Item {
                    width: parent.width
                    implicitHeight: notificationRow.implicitHeight + Style.space(8)

                    NotificationRow {
                        id: notificationRow

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Style.space(4)
                        anchors.rightMargin: Style.space(4)
                        row: rowWrapper.modelData
                        selected: root.selectedIndex === Number(rowWrapper.modelData.flatIndex)
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        uiFont: root.uiFont
                        onHovered: function(isHovered) {
                            root.rowHovered(Number(rowWrapper.modelData.flatIndex), isHovered);
                        }
                        onActivateRequested: root.rowActivateRequested(String(rowWrapper.modelData.key))
                        onDismissRequested: root.rowDismissRequested(String(rowWrapper.modelData.key))
                    }

                }

            }

        }

    }

}
