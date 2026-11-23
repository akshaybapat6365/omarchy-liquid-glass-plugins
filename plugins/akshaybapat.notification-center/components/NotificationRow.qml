import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import qs.Commons
import qs.Commons as Commons
import qs.Ui

CursorSurface {
    id: root

    required property var row
    property bool selected: false
    property string fontFamily: Style.font.family
    property string uiFont: {
        var f = Style.font.menuFamily;
        return (f && f.length > 0 && f !== Style.font.family && f !== "monospace") ? f : "Inter Display";
    }
    readonly property bool urgent: Number(row.urgency || 0) === 2
    readonly property bool hasPreview: String(row.previewSource || "") !== ""
    readonly property int rowRadius: Math.max(6, Style.cornerRadius - 4)
    readonly property color secondary: Qt.darker(foreground, 1.45)
    readonly property color bodyColor: (row.visualUnread || urgent) ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.8) : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.56)
    readonly property color stateColor: urgent ? Commons.Color.urgent : (row.visualUnread ? Commons.Color.accent : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.24))

    signal hovered(bool isHovered)
    signal activateRequested()
    signal dismissRequested()

    function alpha(colorValue, opacity) {
        return Qt.rgba(colorValue.r, colorValue.g, colorValue.b, opacity);
    }

    Accessible.role: Accessible.ListItem
    Accessible.name: String(row.app || "Unknown application") + ": " + String(row.summary || "Notification")
    Accessible.description: String(row.body || "")
    Accessible.selected: selected
    Accessible.onPressAction: root.activateRequested()
    hasCursor: selected
    radius: rowRadius
    accent: urgent ? Commons.Color.urgent : Commons.Color.accent
    fill: urgent ? alpha(Commons.Color.urgent, 0.1) : alpha(root.foreground, 0.085)
    color: hasCursor ? fill : (urgent ? alpha(Commons.Color.urgent, 0.035) : "transparent")
    borderSpec: selected ? Border.flat(root.urgent ? alpha(Commons.Color.urgent, 0.54) : alpha(Commons.Color.accent, 0.46), 1) : Border.none()
    implicitWidth: Style.space(380)
    implicitHeight: Math.max(Style.space(58), content.implicitHeight + Style.space(16), hasPreview ? Style.space(62) : 0)

    Behavior on color {
        ColorAnimation {
            duration: Style.duration(110)
        }

    }

    MouseArea {
        id: rowMouse

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: root.row.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onContainsMouseChanged: root.hovered(containsMouse)
        onClicked: root.activateRequested()
    }

    Rectangle {
        id: stateRule

        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.top: parent.top
        anchors.topMargin: Style.space(10)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(10)
        width: Math.max(2, Style.space(3))
        radius: width / 2
        color: root.stateColor
        opacity: root.row.visualUnread || root.urgent ? 0.95 : 0.4

        Behavior on opacity {
            NumberAnimation {
                duration: Style.duration(140)
            }

        }

    }

    RowLayout {
        id: content

        anchors.left: stateRule.right
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(9)

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(4)

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(7)

                Text {
                    Layout.fillWidth: true
                    text: String(root.row.summary || "Notification")
                    textFormat: Text.PlainText
                    color: root.row.visualUnread || root.urgent ? root.foreground : root.alpha(root.foreground, 0.72)
                    font.family: root.uiFont
                    font.pixelSize: Style.font.subtitle
                    font.weight: root.row.visualUnread || root.urgent ? Font.DemiBold : Font.Medium
                    font.letterSpacing: Style.spaceReal(-0.1)
                    elide: Text.ElideRight
                }

                Rectangle {
                    visible: root.urgent
                    Layout.preferredWidth: urgentText.implicitWidth + Style.space(12)
                    Layout.preferredHeight: urgentText.implicitHeight + Style.space(4)
                    Layout.alignment: Qt.AlignVCenter
                    radius: height / 2
                    color: root.alpha(Commons.Color.urgent, 0.16)
                    border.width: 1
                    border.color: root.alpha(Commons.Color.urgent, 0.38)

                    Text {
                        id: urgentText

                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: Math.round(Style.spaceReal(0.25))
                        text: "URGENT"
                        textFormat: Text.PlainText
                        color: Commons.Color.urgent
                        font.family: root.uiFont
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        font.letterSpacing: Style.spaceReal(0.45)
                    }

                }

                Text {
                    text: String(root.row.timeLabel || "")
                    textFormat: Text.PlainText
                    color: root.secondary
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.features: ({
                        "tnum": 1
                    })
                }

            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: String(root.row.body || "")
                textFormat: Text.PlainText
                color: root.bodyColor
                font.family: root.uiFont
                font.pixelSize: Style.font.body
                lineHeight: 1.28
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                // Three lines, matching the packaged toast, which also gives
                // the body one more line than the summary.
                maximumLineCount: 3
            }

        }

        Rectangle {
            visible: root.hasPreview && preview.status !== Image.Error
            Layout.preferredWidth: Style.space(52)
            Layout.preferredHeight: Style.space(44)
            Layout.alignment: Qt.AlignVCenter
            radius: Math.max(6, root.rowRadius)
            color: root.alpha(root.foreground, 0.06)
            border.width: 1
            border.color: root.alpha(root.foreground, 0.14)
            clip: true

            Image {
                id: preview

                anchors.fill: parent
                anchors.margins: 1
                source: String(root.row.previewSource || "")
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
            }

        }

        Rectangle {
            id: actionPill

            readonly property color tint: root.urgent ? Commons.Color.urgent : Commons.Color.accent
            readonly property bool hot: actionMouse.containsMouse || activeFocus

            visible: root.row.actionable === true
            Layout.preferredWidth: actionLabel.implicitWidth + Style.space(18)
            Layout.preferredHeight: actionLabel.implicitHeight + Style.space(10)
            Layout.alignment: Qt.AlignVCenter
            radius: Math.max(6, root.rowRadius)
            color: actionMouse.pressed ? root.alpha(tint, 0.32) : (hot ? root.alpha(tint, 0.24) : root.alpha(tint, 0.14))
            border.width: 1
            border.color: hot ? root.alpha(tint, 0.56) : root.alpha(tint, 0.34)
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: (root.urgent ? "Review" : "Open") + " " + String(root.row.summary || "notification")
            Accessible.onPressAction: root.activateRequested()
            Keys.onReturnPressed: root.activateRequested()
            Keys.onEnterPressed: root.activateRequested()
            Keys.onSpacePressed: root.activateRequested()

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Math.max(4, Math.round(actionPill.radius * 0.6))
                anchors.rightMargin: Math.max(4, Math.round(actionPill.radius * 0.6))
                anchors.topMargin: 1
                height: 1
                color: root.alpha(root.foreground, 0.16)
            }

            Text {
                id: actionLabel

                anchors.centerIn: parent
                text: root.urgent ? "Review" : "Open"
                textFormat: Text.PlainText
                color: root.urgent ? Commons.Color.urgent : root.foreground
                font.family: root.uiFont
                font.pixelSize: Style.font.bodySmall
                font.weight: Font.DemiBold
            }

            MouseArea {
                id: actionMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activateRequested()
            }

            Behavior on color {
                ColorAnimation {
                    duration: Style.duration(120)
                }

            }

            Behavior on border.color {
                ColorAnimation {
                    duration: Style.duration(120)
                }

            }

        }

        PanelActionButton {
            // Outline close-circle, not the filled one. The packaged panels
            // only ever show their filled disc on the row under the pointer;
            // here every row carries a dismiss, so a filled mark would stack
            // into a column of discs heavier than the notifications themselves.
            iconText: "󰅚"
            tooltipText: "Dismiss"
            foreground: root.selected ? root.foreground : root.secondary
            hoverColor: root.foreground
            fontFamily: root.fontFamily
            radius: size / 2
            focusable: true
            Accessible.role: Accessible.Button
            Accessible.name: "Dismiss " + String(root.row.summary || "notification")
            Accessible.onPressAction: root.dismissRequested()
            onClicked: root.dismissRequested()
        }

    }

}
