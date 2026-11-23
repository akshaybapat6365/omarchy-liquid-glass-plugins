import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
    id: root

    property var groups: []
    property int selectedIndex: -1
    property int unreadAtOpen: 0
    property int urgentUnread: 0
    property int visibleCount: 0
    property int totalCount: -1
    property int unreadFilterCount: -1
    property int urgentFilterCount: -1
    property string filterMode: "all"
    property bool externallyFiltered: false
    property bool searching: false
    property string query: ""
    property bool dnd: false
    property bool clearArmed: false
    property bool sourceAvailable: false
    property string statusMessage: ""
    property color foreground: Commons.Color.foreground
    property string fontFamily: Style.font.family
    property string uiFont: {
        var f = Style.font.menuFamily;
        return (f && f.length > 0 && f !== Style.font.family && f !== "monospace") ? f : "Inter Display";
    }
    readonly property int pillRadius: Math.max(8, Style.cornerRadius)
    readonly property int cardRadius: Math.max(8, Style.cornerRadius - 2)
    readonly property color secondary: Qt.darker(foreground, 1.45)
    readonly property var localCounts: {
        var allCount = 0;
        var unreadCount = 0;
        var urgentCount = 0;
        var list = root.groups || [];
        for (var i = 0; i < list.length; i++) {
            var rows = list[i] && list[i].rows ? list[i].rows : [];
            for (var r = 0; r < rows.length; r++) {
                allCount += 1;
                if (rows[r].visualUnread)
                    unreadCount += 1;

                if (Number(rows[r].urgency || 0) === 2)
                    urgentCount += 1;

            }
        }
        return {
            "all": allCount,
            "unread": unreadCount,
            "urgent": urgentCount
        };
    }
    readonly property int effectiveTotalCount: totalCount >= 0 ? totalCount : Math.max(visibleCount, localCounts.all)
    readonly property int effectiveUnreadFilterCount: unreadFilterCount >= 0 ? unreadFilterCount : localCounts.unread
    readonly property int effectiveUrgentFilterCount: urgentFilterCount >= 0 ? urgentFilterCount : localCounts.urgent
    readonly property var effectiveGroups: {
        if (root.externallyFiltered || root.filterMode === "all")
            return root.groups || [];

        var list = root.groups || [];
        var out = [];
        var flatIndex = 0;
        for (var i = 0; i < list.length; i++) {
            var group = list[i];
            var rows = group && group.rows ? group.rows : [];
            var kept = [];
            var urgentGroup = false;
            var unreadGroup = 0;
            for (var r = 0; r < rows.length; r++) {
                var row = rows[r];
                var match = root.filterMode === "unread" ? row.visualUnread === true : Number(row.urgency || 0) === 2;
                if (!match)
                    continue;

                var copy = {
                };
                for (var k in row) copy[k] = row[k]
                copy.flatIndex = flatIndex;
                flatIndex += 1;
                if (copy.visualUnread)
                    unreadGroup += 1;

                if (Number(copy.urgency || 0) === 2)
                    urgentGroup = true;

                kept.push(copy);
            }
            if (kept.length > 0) {
                var groupCopy = {
                };
                for (var gk in group) groupCopy[gk] = group[gk]
                groupCopy.rows = kept;
                groupCopy.count = kept.length;
                groupCopy.unreadCount = unreadGroup;
                groupCopy.urgent = urgentGroup;
                groupCopy.startFlatIndex = kept[0].flatIndex;
                out.push(groupCopy);
            }
        }
        return out;
    }
    readonly property int effectiveVisibleCount: {
        if (root.externallyFiltered || root.filterMode === "all")
            return root.visibleCount;

        var count = 0;
        for (var i = 0; i < root.effectiveGroups.length; i++) count += Number(root.effectiveGroups[i].count || 0)
        return count;
    }
    readonly property bool empty: sourceAvailable && effectiveVisibleCount === 0
    readonly property bool showFilterBar: sourceAvailable && (effectiveTotalCount > 0 || filterMode !== "all")
    readonly property real scrollPosition: groupsList.contentY
    readonly property real bodyHeight: {
        // A fixed box, because the empty hero centres in it — small enough so
        // clearing the last notification shrinks the popup cleanly.
        if (!sourceAvailable || empty)
            return Style.space(156);

        // Cap, never floor, so the panel shrinks naturally as rows are dismissed.
        return Math.min(groupsList.contentHeight, Style.space(580));
    }
    readonly property var filterTabs: [{
        "id": "all",
        "label": "All",
        "count": root.effectiveTotalCount,
        "urgent": false
    }, {
        "id": "unread",
        "label": "Unread",
        "count": root.effectiveUnreadFilterCount,
        "urgent": false
    }, {
        "id": "urgent",
        "label": "Urgent",
        "count": root.effectiveUrgentFilterCount,
        "urgent": true
    }]

    signal searchRequested()
    signal searchEdited(string text)
    signal searchMoveRequested(int delta)
    signal searchActivateRequested()
    signal searchEscapeRequested()
    signal dndRequested()
    signal clearRequested()
    signal filterModeRequested(string mode)
    signal rowHovered(int flatIndex, bool isHovered)
    signal rowActivateRequested(string key)
    signal rowDismissRequested(string key)

    function alpha(colorValue, opacity) {
        return Qt.rgba(colorValue.r, colorValue.g, colorValue.b, opacity);
    }

    function selectFilter(mode) {
        var next = String(mode || "all");
        if (root.externallyFiltered)
            root.filterModeRequested(next);
        else
            root.filterMode = next;
        groupsList.contentY = 0;
    }

    function focusSearch() {
        Qt.callLater(function() {
            if (root.searching)
                searchField.forceActiveFocus();

        });
    }

    function setSearchText(value) {
        searchField.text = String(value || "");
    }

    function revealFlatIndex(flatIndex) {
        if (flatIndex < 0 || !root.effectiveGroups)
            return ;

        for (var i = 0; i < root.effectiveGroups.length; i++) {
            var group = root.effectiveGroups[i];
            var first = Number(group.startFlatIndex || 0);
            var last = first + Number(group.count || 0) - 1;
            if (flatIndex >= first && flatIndex <= last) {
                groupsList.positionViewAtIndex(i, ListView.Contain);
                var groupIndex = i;
                var rowIndex = flatIndex - first;
                Qt.callLater(function() {
                    root.revealGroupRow(groupIndex, rowIndex, 0);
                });
                return ;
            }
        }
    }

    function revealGroupRow(groupIndex, rowIndex, attempt) {
        var delegate = groupsList.itemAtIndex(groupIndex);
        var boundsFn = delegate ? delegate["rowBounds"] : null;
        if (!delegate || typeof boundsFn !== "function") {
            if (attempt < 2) {
                groupsList.positionViewAtIndex(groupIndex, ListView.Beginning);
                Qt.callLater(function() {
                    root.revealGroupRow(groupIndex, rowIndex, attempt + 1);
                });
            }
            return ;
        }
        var bounds = boundsFn.call(delegate, rowIndex);
        if (!bounds)
            return ;

        var top = delegate.y + Number(bounds.top || 0);
        var bottom = delegate.y + Number(bounds.bottom || 0);
        var viewportTop = groupsList.contentY;
        var viewportBottom = viewportTop + groupsList.height;
        var maximum = Math.max(0, groupsList.contentHeight - groupsList.height);
        if (top < viewportTop)
            groupsList.contentY = Math.max(0, top);
        else if (bottom > viewportBottom)
            groupsList.contentY = Math.min(maximum, Math.max(0, bottom - groupsList.height));
    }

    implicitWidth: Style.space(412)
    implicitHeight: panelColumn.implicitHeight

    Column {
        id: panelColumn

        width: parent.width
        spacing: Style.space(12)

        Item {
            width: parent.width
            height: Style.space(42)

            RowLayout {
                anchors.fill: parent
                spacing: Style.space(10)

                Rectangle {
                    Layout.preferredWidth: Style.space(36)
                    Layout.preferredHeight: Style.space(36)
                    Layout.alignment: Qt.AlignVCenter
                    radius: root.cardRadius
                    color: root.urgentUnread > 0 ? root.alpha(Commons.Color.urgent, 0.14) : (root.dnd ? root.alpha(Commons.Color.accent, 0.12) : root.alpha(root.foreground, 0.06))
                    border.width: 1
                    border.color: root.urgentUnread > 0 ? root.alpha(Commons.Color.urgent, 0.34) : (root.dnd ? root.alpha(Commons.Color.accent, 0.3) : root.alpha(root.foreground, 0.11))

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: Math.max(4, Math.round(root.cardRadius * 0.5))
                        anchors.rightMargin: Math.max(4, Math.round(root.cardRadius * 0.5))
                        anchors.topMargin: 1
                        height: 1
                        color: root.alpha(root.foreground, 0.14)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.dnd ? "󰂛" : (root.urgentUnread > 0 ? "󰂞" : "󰂚")
                        textFormat: Text.PlainText
                        color: root.urgentUnread > 0 ? Commons.Color.urgent : (root.dnd ? Commons.Color.accent : root.foreground)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.iconLarge
                    }

                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Style.space(2)

                    Text {
                        Layout.fillWidth: true
                        text: "Notifications"
                        textFormat: Text.PlainText
                        color: root.foreground
                        font.family: root.uiFont
                        font.pixelSize: Style.font.title
                        font.bold: true
                        font.letterSpacing: Style.spaceReal(-0.2)
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: {
                            if (!root.sourceAvailable)
                                return "SOURCE UNAVAILABLE";

                            var kept = root.effectiveTotalCount + " KEPT";
                            var prefix = root.dnd ? "SILENCED · " : "";
                            return root.unreadAtOpen > 0 ? prefix + root.unreadAtOpen + " UNREAD · " + kept : prefix + kept;
                        }
                        textFormat: Text.PlainText
                        color: root.secondary
                        font.family: root.uiFont
                        font.pixelSize: Style.font.caption
                        font.weight: Font.DemiBold
                        font.letterSpacing: Style.spaceReal(0.75)
                        font.features: ({
                            "tnum": 1
                        })
                        elide: Text.ElideRight
                    }

                }

                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Style.space(6)

                    Rectangle {
                        id: searchButton

                        readonly property bool hot: searchMouse.containsMouse || activeFocus

                        visible: root.sourceAvailable && root.effectiveTotalCount > 0
                        Layout.preferredWidth: Style.space(30)
                        Layout.preferredHeight: Style.space(30)
                        Layout.alignment: Qt.AlignVCenter
                        radius: Math.max(6, root.cardRadius - 2)
                        color: root.searching ? root.alpha(Commons.Color.accent, 0.16) : (hot ? root.alpha(root.foreground, 0.11) : root.alpha(root.foreground, 0.055))
                        border.width: 1
                        border.color: root.searching ? root.alpha(Commons.Color.accent, 0.44) : (hot ? root.alpha(root.foreground, 0.22) : root.alpha(root.foreground, 0.11))
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: "Search notifications"
                        Accessible.onPressAction: root.searchRequested()
                        Keys.onReturnPressed: root.searchRequested()
                        Keys.onEnterPressed: root.searchRequested()
                        Keys.onSpacePressed: root.searchRequested()

                        Text {
                            anchors.centerIn: parent
                            text: "󰍉"
                            textFormat: Text.PlainText
                            color: root.searching ? Commons.Color.accent : (searchButton.hot ? root.foreground : root.secondary)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.icon
                        }

                        MouseArea {
                            id: searchMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.searchRequested()
                        }

                        PanelToolTip {
                            visible: searchMouse.containsMouse
                            text: "Search notifications"
                            fontFamily: root.uiFont
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

                    Rectangle {
                        id: dndButton

                        // One glyph in both states, like the first-party DND
                        // indicator: the header bell already reports whether
                        // notifications are silenced, so a second bell that
                        // flips the other way only argues with it. Accent fill
                        // marks the toggle as engaged; the tooltip says what
                        // pressing it will do.
                        readonly property bool hot: (dndMouse.containsMouse || activeFocus) && root.sourceAvailable

                        Layout.preferredWidth: Style.space(30)
                        Layout.preferredHeight: Style.space(30)
                        Layout.alignment: Qt.AlignVCenter
                        radius: Math.max(6, root.cardRadius - 2)
                        opacity: root.sourceAvailable ? 1 : 0.45
                        color: root.dnd ? root.alpha(Commons.Color.accent, 0.16) : (hot ? root.alpha(root.foreground, 0.11) : root.alpha(root.foreground, 0.055))
                        border.width: 1
                        border.color: root.dnd ? root.alpha(Commons.Color.accent, 0.44) : (hot ? root.alpha(root.foreground, 0.22) : root.alpha(root.foreground, 0.11))
                        activeFocusOnTab: root.sourceAvailable
                        Accessible.role: Accessible.Button
                        Accessible.name: root.dnd ? "Allow notifications" : "Silence notifications"
                        Accessible.onPressAction: {
                            if (root.sourceAvailable)
                                root.dndRequested();

                        }
                        Keys.onReturnPressed: {
                            if (root.sourceAvailable)
                                root.dndRequested();

                        }
                        Keys.onEnterPressed: {
                            if (root.sourceAvailable)
                                root.dndRequested();

                        }
                        Keys.onSpacePressed: {
                            if (root.sourceAvailable)
                                root.dndRequested();

                        }

                        Text {
                            anchors.centerIn: parent
                            text: "󰂛"
                            textFormat: Text.PlainText
                            color: root.dnd ? Commons.Color.accent : (dndButton.hot ? root.foreground : root.secondary)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.icon
                        }

                        MouseArea {
                            id: dndMouse

                            anchors.fill: parent
                            enabled: root.sourceAvailable
                            hoverEnabled: true
                            cursorShape: root.sourceAvailable ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.dndRequested()
                        }

                        PanelToolTip {
                            visible: dndMouse.containsMouse
                            text: root.dnd ? "Allow notifications" : "Silence notifications"
                            fontFamily: root.uiFont
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

                    Rectangle {
                        id: clearButton

                        readonly property bool hot: clearMouse.containsMouse || activeFocus

                        visible: root.sourceAvailable && root.effectiveTotalCount > 0
                        Layout.preferredWidth: clearLabel.implicitWidth + Style.space(18)
                        Layout.preferredHeight: Style.space(30)
                        Layout.alignment: Qt.AlignVCenter
                        radius: Math.max(6, root.cardRadius - 2)
                        color: root.clearArmed ? (hot ? root.alpha(Commons.Color.urgent, 0.28) : root.alpha(Commons.Color.urgent, 0.18)) : (hot ? root.alpha(root.foreground, 0.12) : root.alpha(root.foreground, 0.06))
                        border.width: 1
                        border.color: root.clearArmed ? root.alpha(Commons.Color.urgent, 0.48) : (hot ? root.alpha(root.foreground, 0.24) : root.alpha(root.foreground, 0.13))
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: root.clearArmed ? "Confirm clear all notifications" : "Clear all notifications"
                        Accessible.onPressAction: root.clearRequested()
                        Keys.onReturnPressed: root.clearRequested()
                        Keys.onEnterPressed: root.clearRequested()
                        Keys.onSpacePressed: root.clearRequested()

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: Math.max(4, Math.round(clearButton.radius * 0.5))
                            anchors.rightMargin: Math.max(4, Math.round(clearButton.radius * 0.5))
                            anchors.topMargin: 1
                            height: 1
                            color: root.alpha(root.foreground, 0.12)
                        }

                        Text {
                            id: clearLabel

                            anchors.centerIn: parent
                            text: root.clearArmed ? "Sure?" : "Clear all"
                            textFormat: Text.PlainText
                            color: root.clearArmed ? Commons.Color.urgent : root.foreground
                            font.family: root.uiFont
                            font.pixelSize: Style.font.bodySmall
                            font.weight: root.clearArmed ? Font.Bold : Font.DemiBold
                        }

                        MouseArea {
                            id: clearMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.clearRequested()
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

                }

            }

        }

        // Recessed frosted-glass segmented filter bar (All | Unread | Urgent),
        // sibling of ai-usage v1.15.0's rounded pill switcher.
        Rectangle {
            id: filterTrack

            visible: root.showFilterBar
            width: parent.width
            height: Style.space(34)
            radius: Math.max(8, root.pillRadius - 2)
            color: root.alpha(root.foreground, 0.055)
            border.width: 1
            border.color: root.alpha(root.foreground, 0.11)

            Row {
                anchors.fill: parent
                anchors.margins: Style.space(3)
                spacing: Style.space(3)

                Repeater {
                    model: root.filterTabs

                    delegate: Rectangle {
                        id: segPill

                        required property var modelData
                        required property int index
                        readonly property bool activeSeg: root.filterMode === modelData.id
                        readonly property bool hot: segMouse.containsMouse || activeFocus
                        readonly property bool showUrgentDot: modelData.urgent && Number(modelData.count || 0) > 0

                        width: (filterTrack.width - Style.space(6) - Style.space(6)) / 3
                        height: parent.height
                        radius: Math.max(6, root.pillRadius - 4)
                        color: activeSeg ? root.alpha(root.foreground, 0.14) : (hot ? root.alpha(root.foreground, 0.07) : "transparent")
                        border.width: activeSeg ? 1 : 0
                        border.color: activeSeg ? root.alpha(root.foreground, 0.18) : "transparent"
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.label + " (" + String(modelData.count) + ")"
                        Accessible.onPressAction: root.selectFilter(modelData.id)
                        Keys.onReturnPressed: root.selectFilter(modelData.id)
                        Keys.onEnterPressed: root.selectFilter(modelData.id)
                        Keys.onSpacePressed: root.selectFilter(modelData.id)

                        Rectangle {
                            visible: segPill.activeSeg
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: Math.max(4, Math.round(segPill.radius * 0.6))
                            anchors.rightMargin: Math.max(4, Math.round(segPill.radius * 0.6))
                            anchors.topMargin: 1
                            height: 1
                            color: root.alpha(root.foreground, 0.16)
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: Style.space(5)

                            Rectangle {
                                visible: segPill.showUrgentDot
                                width: Style.space(5)
                                height: width
                                radius: width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: Commons.Color.urgent
                            }

                            Text {
                                text: segPill.modelData.label
                                textFormat: Text.PlainText
                                anchors.verticalCenter: parent.verticalCenter
                                color: segPill.activeSeg ? root.foreground : root.secondary
                                font.family: root.uiFont
                                font.pixelSize: Style.font.bodySmall
                                font.weight: segPill.activeSeg ? Font.DemiBold : Font.Medium
                            }

                            Rectangle {
                                visible: Number(segPill.modelData.count || 0) > 0 || segPill.activeSeg
                                width: segCountText.implicitWidth + Style.space(9)
                                height: segCountText.implicitHeight + Style.space(2)
                                radius: height / 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: segPill.showUrgentDot ? root.alpha(Commons.Color.urgent, 0.18) : (segPill.activeSeg ? root.alpha(root.foreground, 0.12) : root.alpha(root.foreground, 0.06))

                                Text {
                                    id: segCountText

                                    anchors.centerIn: parent
                                    text: String(segPill.modelData.count)
                                    textFormat: Text.PlainText
                                    color: segPill.showUrgentDot ? Commons.Color.urgent : (segPill.activeSeg ? root.foreground : root.secondary)
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.weight: Font.DemiBold
                                    font.features: ({
                                        "tnum": 1
                                    })
                                }

                            }

                        }

                        MouseArea {
                            id: segMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectFilter(segPill.modelData.id)
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

                }

            }

        }

        PanelSeparator {
            visible: !root.showFilterBar
            width: parent.width
            foreground: root.foreground
            strength: 0.09
        }

        Rectangle {
            id: searchBar

            visible: root.searching
            width: parent.width
            height: Style.space(34)
            radius: Math.max(8, root.cardRadius)
            color: root.alpha(root.foreground, searchField.activeFocus ? 0.08 : 0.055)
            border.width: 1
            border.color: searchField.activeFocus ? root.alpha(Commons.Color.accent, 0.55) : root.alpha(root.foreground, 0.13)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Text {
                    text: "󰍉"
                    textFormat: Text.PlainText
                    color: searchField.activeFocus ? Commons.Color.accent : root.secondary
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.iconSmall
                    Layout.alignment: Qt.AlignVCenter
                }

                TextField {
                    id: searchField

                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    placeholderText: "Search app, title, or message"
                    foreground: root.foreground
                    font.family: root.uiFont
                    text: root.query
                    horizontalPadding: 0
                    verticalPadding: Style.space(4)
                    onTextEdited: root.searchEdited(text)
                    Keys.onDownPressed: root.searchMoveRequested(1)
                    Keys.onUpPressed: root.searchMoveRequested(-1)
                    Keys.onReturnPressed: root.searchActivateRequested()
                    Keys.onEnterPressed: root.searchActivateRequested()
                    Keys.onEscapePressed: root.searchEscapeRequested()

                    background: Item {
                    }

                }

                Rectangle {
                    visible: searchField.text.length > 0
                    Layout.preferredWidth: Style.space(20)
                    Layout.preferredHeight: Style.space(20)
                    Layout.alignment: Qt.AlignVCenter
                    radius: height / 2
                    color: clearSearchMouse.containsMouse ? root.alpha(root.foreground, 0.14) : root.alpha(root.foreground, 0.07)

                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        textFormat: Text.PlainText
                        color: root.secondary
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                        id: clearSearchMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            searchField.text = "";
                            root.searchEdited("");
                            searchField.forceActiveFocus();
                        }
                    }

                }

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

        Item {
            width: parent.width
            height: root.bodyHeight
            clip: true

            Column {
                visible: !root.sourceAvailable || root.empty
                anchors.centerIn: parent
                width: Math.min(parent.width - Style.space(24), Style.space(320))
                spacing: Style.space(8)

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Style.space(46)
                    height: Style.space(46)
                    radius: width / 2
                    color: root.alpha(root.foreground, 0.055)
                    border.width: 1
                    border.color: root.alpha(root.foreground, 0.11)

                    Text {
                        anchors.centerIn: parent
                        text: {
                            if (!root.sourceAvailable)
                                return "󰅚";

                            if (root.query || root.filterMode !== "all")
                                return "󰍉";

                            return "󰂚";
                        }
                        textFormat: Text.PlainText
                        color: root.secondary
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.heading
                    }

                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: {
                        if (!root.sourceAvailable)
                            return "Notification service unavailable";

                        if (root.query)
                            return "No matching notifications";

                        if (root.filterMode === "unread")
                            return "No unread notifications";

                        if (root.filterMode === "urgent")
                            return "No urgent notifications";

                        return "All caught up";
                    }
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.uiFont
                    font.pixelSize: Style.font.title
                    font.bold: true
                    font.letterSpacing: Style.spaceReal(-0.15)
                }

                Text {
                    width: parent.width
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: {
                        if (!root.sourceAvailable)
                            return "The center will reconnect without taking over delivery.";

                        if (root.query)
                            return "Try another app, title, or message.";

                        if (root.filterMode === "unread")
                            return "Everything in your history has been read.";

                        if (root.filterMode === "urgent")
                            return "No high-priority alerts right now.";

                        return "Nothing needs your attention.";
                    }
                    textFormat: Text.PlainText
                    color: root.secondary
                    font.family: root.uiFont
                    font.pixelSize: Style.font.bodySmall
                    lineHeight: 1.3
                }

                Rectangle {
                    visible: root.sourceAvailable && root.filterMode !== "all" && !root.query
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: resetFilterText.implicitWidth + Style.space(20)
                    height: resetFilterText.implicitHeight + Style.space(10)
                    radius: Math.max(6, root.cardRadius - 2)
                    color: resetFilterMouse.containsMouse ? root.alpha(root.foreground, 0.12) : root.alpha(root.foreground, 0.06)
                    border.width: 1
                    border.color: resetFilterMouse.containsMouse ? root.alpha(root.foreground, 0.24) : root.alpha(root.foreground, 0.14)
                    Accessible.role: Accessible.Button
                    Accessible.name: "Show all notifications"
                    Accessible.onPressAction: root.selectFilter("all")

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

                    Text {
                        id: resetFilterText

                        anchors.centerIn: parent
                        text: "Show all"
                        textFormat: Text.PlainText
                        color: root.foreground
                        font.family: root.uiFont
                        font.pixelSize: Style.font.bodySmall
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: resetFilterMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectFilter("all")
                    }

                }

            }

            ListView {
                id: groupsList

                anchors.fill: parent
                visible: root.sourceAvailable && !root.empty
                model: root.effectiveGroups
                spacing: Style.space(8)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true

                ScrollBar.horizontal: ScrollBar {
                    policy: ScrollBar.AlwaysOff
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                delegate: AppGroup {
                    id: groupDelegate

                    required property var modelData

                    width: groupsList.width
                    group: modelData
                    selectedIndex: root.selectedIndex
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    uiFont: root.uiFont
                    onRowHovered: function(flatIndex, isHovered) {
                        root.rowHovered(flatIndex, isHovered);
                    }
                    onRowActivateRequested: function(key) {
                        root.rowActivateRequested(key);
                    }
                    onRowDismissRequested: function(key) {
                        root.rowDismissRequested(key);
                    }
                }

            }

        }

        Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.sourceAvailable && (root.effectiveTotalCount > 0 || root.statusMessage !== "")

            PanelSeparator {
                width: parent.width
                foreground: root.foreground
                strength: 0.08
            }

            Item {
                width: parent.width
                height: Style.space(20)

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    Rectangle {
                        width: Style.space(6)
                        height: width
                        radius: width / 2
                        color: root.clearArmed || root.urgentUnread > 0 ? Commons.Color.urgent : (root.unreadAtOpen > 0 ? Commons.Color.accent : root.alpha(root.foreground, 0.35))
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: root.statusMessage ? root.statusMessage : (root.dnd ? "Notifications silenced" : (root.unreadAtOpen > 0 ? "New since last opened" : "Up to date"))
                        textFormat: Text.PlainText
                        color: root.clearArmed ? Commons.Color.urgent : root.secondary
                        font.family: root.uiFont
                        font.pixelSize: Style.font.caption
                        font.weight: root.clearArmed ? Font.DemiBold : Font.Normal
                    }

                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.filterMode !== "all" ? root.effectiveVisibleCount + " of " + root.effectiveTotalCount : root.effectiveVisibleCount + " visible"
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

    }

}
