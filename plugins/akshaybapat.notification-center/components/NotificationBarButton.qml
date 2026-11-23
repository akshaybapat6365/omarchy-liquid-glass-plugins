import "AlarmInk.js" as AlarmInk
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The bar's own button contract (WidgetButton: clicks, tooltip, hover, press
// feedback) with the same optical glyph BarIconButton draws, laid out mark
// first and count second. BarIconButton always prints its label before the
// glyph; every other counted mark on this bar (the camera, the usage strip)
// reads icon then number, so the bell composes the two stock parts in that
// order instead of borrowing a component that cannot.
WidgetButton {
    id: root

    property int unreadCount: 0
    property int urgentUnreadCount: 0
    property bool dnd: false
    property bool sourceAvailable: true
    // The count reads as part of the mark rather than a badge stuck on top of
    // it — the same move the battery widget makes when it prints a percentage
    // beside its glyph. Clamped so a notification storm cannot keep widening
    // the bar.
    readonly property string countText: unreadCount > 99 ? "99+" : String(unreadCount)
    // A vertical bar is only one icon wide, so digits would spill out of the
    // slot; there the tooltip carries the count, as the power widget does.
    readonly property bool countVisible: unreadCount > 0 && !vertical
    // A ringing bell means "one of these is urgent". On a vertical bar, where
    // there is no room for digits, it also has to carry plain unread — without
    // it a bar with seven waiting notifications would look exactly like an idle
    // one, which is the one thing this module must never do.
    readonly property bool ringing: urgentUnreadCount > 0 || (vertical && unreadCount > 0)
    // Omarchy 4.5 draws `text` as an optical glyph scaled into the icon canvas,
    // so digits there shrink to fit; the count is its own text beside it, at
    // the bar's icon type size.
    readonly property string labelText: countVisible ? countText : ""
    // The gap between mark and count is the one BarIconButton leaves.
    readonly property real labelGap: Style.space(4)
    // Widen the slot by exactly what the count adds (its advance plus the
    // gap), so the air either side of the mark stays what every other bar icon
    // has, and the open-panel dot (sized from the slot) keeps tracking it.
    readonly property real slotSize: Style.bar.iconSlot + (countVisible ? Math.ceil(countMetrics.advanceWidth) + labelGap : 0)
    readonly property real canvasSize: Math.max(Style.bar.iconSize, Style.bar.iconCanvas)
    readonly property color ink: active && useActiveColor ? activeColor : foreground

    signal leftPressed()
    signal rightPressed()

    labelVisible: false
    hasVisualContent: true
    fontSize: Style.bar.iconFont
    fixedWidth: vertical ? -1 : slotSize
    fixedHeight: vertical ? slotSize : -1
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: tooltipText
    Accessible.description: "Open the notification center. Use the context action to toggle Do Not Disturb."
    Accessible.onPressAction: root.leftPressed()
    Keys.onReturnPressed: root.leftPressed()
    Keys.onEnterPressed: root.leftPressed()
    Keys.onSpacePressed: root.leftPressed()
    // Silenced wins the silhouette over ringing: a muted bell is the more
    // important thing to say.
    text: dnd ? "󰂛" : (ringing ? "󰂞" : "󰂚")
    // Colour escalates for urgent only. Ordinary unread is already announced by
    // digits appearing, and on a theme whose accent is dimmer than the plain
    // foreground, tinting the bell for routine unread made a busy bell recede.
    active: urgentUnreadCount > 0
    // Urgent is a real alarm, and the bar has one alarm colour: the theme's
    // urgent ink made legible beside the bar's own text by the same rule the AI
    // usage strip applies (AlarmInk.js), so the ringing bell and a quota about
    // to run out are the same coral. The bar can be see-through, so, as in the
    // strip, no surface is assumed.
    activeColor: {
        // `bar` is null until the bar hands itself over; the stock button
        // falls back to the theme's urgent ink the same way.
        var alarm = bar ? bar.urgent : Commons.Color.urgent;
        var rgb = AlarmInk.legibleAlarmRgb([alarm.r, alarm.g, alarm.b], [foreground.r, foreground.g, foreground.b], null);
        return Qt.rgba(rgb[0], rgb[1], rgb[2], 1);
    }
    dimmed: dnd && unreadCount === 0
    tooltipText: {
        if (!sourceAvailable)
            return "Notification center unavailable";

        if (dnd && unreadCount > 0)
            return "Silenced · " + unreadCount + " new";

        if (dnd)
            return "Notifications silenced";

        if (unreadCount === 1)
            return "1 unread notification";

        if (unreadCount > 1)
            return unreadCount + " unread notifications";

        return "No unread notifications";
    }
    onPressed: function(mouseButton) {
        if (mouseButton === Qt.RightButton)
            root.rightPressed();
        else if (mouseButton === Qt.LeftButton)
            root.leftPressed();
    }

    // Mark, then count, centred together in the slot the way BarIconButton
    // centres its group; exact coordinates keep odd-width slots centred.
    Item {
        id: content

        x: (root.width - width) / 2
        y: (root.height - height) / 2
        scale: root.pressScale
        width: root.canvasSize + (count.visible ? root.labelGap + count.implicitWidth : 0)
        height: root.canvasSize

        OpticalGlyph {
            width: root.canvasSize
            height: root.canvasSize
            text: root.text
            fontFamily: root.fontFamily
            fontSize: root.fontSize
            paintedSize: Style.bar.iconSize
            color: root.ink
        }

        Text {
            id: count

            visible: root.labelText !== ""
            x: root.canvasSize + root.labelGap
            // Centre the figure height, not the line box, so the digits sit
            // level with the mark (BarIconButton's own label rule).
            y: (parent.height - height) / 2 + (countFont.descent - countFont.ascent + countFont.tightBoundingRect("0").height) / 2
            textFormat: Text.PlainText
            text: root.labelText
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            font.features: ({
                "tnum": 1
            })
            color: root.ink
            renderType: Text.NativeRendering
        }

        FontMetrics {
            id: countFont

            font: count.font
        }

    }

    // Measured in the glyph's own font and size, so the slot grows by the width
    // the digits actually take rather than a guessed multiple of the icon slot.
    TextMetrics {
        id: countMetrics

        font.family: root.fontFamily
        font.pixelSize: Math.max(1, Math.round(root.fontSize))
        text: root.labelText
    }

    // The slot changes width when the count appears or gains a digit. Easing it
    // keeps the modules beside it from jumping sideways mid-glance.
    Behavior on implicitWidth {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }

    }

}
