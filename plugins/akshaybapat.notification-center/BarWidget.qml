import QtQuick
import Quickshell
import "components"
import "host" as NotificationCenter
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
    id: root

    property bool popupOpen: false
    property bool searching: false
    property string query: ""
    property string filterMode: "all"
    property int selectedIndex: -1
    property bool clearArmed: false
    property string statusMessage: ""
    property int timeRevision: 0
    property bool popoutSwitchClosing: false
    readonly property var runtime: NotificationCenter.NotificationCenterHost.runtime
    readonly property int modelRevision: runtime ? Number(runtime.modelRevision || 0) : 0
    readonly property var allDisplayGroups: {
        var rev = root.modelRevision + root.timeRevision;
        return rev >= 0 && runtime ? runtime.groupsForQuery(root.query, Date.now()) : [];
    }
    readonly property var allDisplayRows: {
        var rev = root.modelRevision + root.timeRevision;
        return rev >= 0 && runtime ? runtime.flatRowsForQuery(root.query, Date.now()) : [];
    }
    readonly property int displayUnreadCount: {
        var count = 0;
        for (var i = 0; i < root.allDisplayRows.length; i++) {
            if (root.allDisplayRows[i].visualUnread)
                count += 1;

        }
        return count;
    }
    readonly property int displayUrgentCount: {
        var count = 0;
        for (var i = 0; i < root.allDisplayRows.length; i++) {
            if (Number(root.allDisplayRows[i].urgency || 0) === 2)
                count += 1;

        }
        return count;
    }
    readonly property var displayGroups: {
        if (root.filterMode === "all")
            return root.allDisplayGroups;

        var list = root.allDisplayGroups || [];
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
    readonly property var displayRows: {
        if (root.filterMode === "all")
            return root.allDisplayRows;

        var flat = [];
        for (var g = 0; g < root.displayGroups.length; g++) {
            var rows = root.displayGroups[g].rows || [];
            for (var r = 0; r < rows.length; r++) flat.push(rows[r])
        }
        return flat;
    }
    readonly property int unreadCount: runtime ? Number(runtime.unreadCount || 0) : 0
    readonly property int urgentUnreadCount: runtime ? Number(runtime.urgentUnreadCount || 0) : 0
    readonly property int sessionNewCount: runtime ? Number(runtime.sessionNewCount || 0) : 0
    readonly property int sessionUrgentCount: runtime ? Number(runtime.sessionUrgentCount || 0) : 0
    readonly property bool sourceAvailable: !!runtime && runtime.sourceReady === true
    readonly property bool dnd: !!runtime && runtime.doNotDisturb === true
    readonly property bool popoutSwitching: popup.popoutSwitching
    readonly property var anchorWindow: button ? button.QsWindow.window : null
    readonly property string screenName: anchorWindow && anchorWindow.screen ? String(anchorWindow.screen.name || "") : ""
    readonly property bool focusPreferred: !!screenName && bar && typeof bar.focusedScreenName === "function" && String(bar.focusedScreenName() || "") === screenName
    readonly property bool opened: popupOpen
    readonly property string uiFont: {
        var f = Style.font.menuFamily;
        return (f && f.length > 0 && f !== Style.font.family && f !== "monospace") ? f : "Inter Display";
    }
    readonly property string runtimeStatus: {
        if (!runtime)
            return "";

        var value = String(runtime.lastActionStatus || "");
        if (value.indexOf("Clear") === 0 || value.indexOf("All notifications") === 0)
            return value;

        return "";
    }

    function openFromHost() {
        clearArmed = false;
        clearDisarm.stop();
        statusMessage = "";
        filterMode = "all";
        selectedIndex = -1;
        if (searching)
            endSearch();

        popupOpen = true;
    }

    function closeFromHost() {
        clearArmed = false;
        clearDisarm.stop();
        if (searching)
            endSearch();

        popupOpen = false;
    }

    function close() {
        closeFromHost();
    }

    function open() {
        return NotificationCenter.NotificationCenterHost.openView(root);
    }

    function closeForPopoutSwitch() {
        popoutSwitchClosing = true;
        closeFromHost();
        Qt.callLater(function() {
            root.popoutSwitchClosing = false;
        });
    }

    function switchPanel(direction) {
        if (bar && typeof bar.switchPanelFrom === "function")
            return bar.switchPanelFrom(root, direction);

        return false;
    }

    function toggleFromButton() {
        NotificationCenter.NotificationCenterHost.noteInteraction(root);
        if (popupOpen)
            NotificationCenter.NotificationCenterHost.closePanel();
        else
            NotificationCenter.NotificationCenterHost.openView(root);
    }

    function setFilterMode(mode) {
        var next = String(mode || "all");
        if (next !== "all" && next !== "unread" && next !== "urgent")
            next = "all";

        filterMode = next;
        selectedIndex = -1;
    }

    function beginSearch() {
        if (!sourceAvailable || allDisplayRows.length === 0)
            return ;

        searching = true;
        panelContent.focusSearch();
    }

    function endSearch() {
        searching = false;
        query = "";
        panelContent.setSearchText("");
        selectedIndex = -1;
        Qt.callLater(function() {
            if (root.popupOpen)
                keyCatcher.forceActiveFocus();

        });
    }

    function toggleSearch() {
        if (searching)
            endSearch();
        else
            beginSearch();
    }

    function setCursor(index) {
        if (displayRows.length === 0) {
            selectedIndex = -1;
            return ;
        }
        selectedIndex = Math.max(0, Math.min(displayRows.length - 1, index));
        panelContent.revealFlatIndex(selectedIndex);
    }

    function hoverCursor(index, hovered) {
        if (hovered)
            setCursor(index);
        else if (selectedIndex === index)
            selectedIndex = -1;
    }

    function moveCursor(delta) {
        if (displayRows.length === 0)
            return ;

        if (selectedIndex < 0) {
            setCursor(delta > 0 ? 0 : displayRows.length - 1);
            return ;
        }
        setCursor(selectedIndex + delta);
    }

    function selectedRow() {
        return selectedIndex >= 0 && selectedIndex < displayRows.length ? displayRows[selectedIndex] : null;
    }

    function activateSelected() {
        if (clearArmed) {
            confirmClear();
            return ;
        }
        var row = selectedRow();
        if (!row || !runtime)
            return ;

        var result = runtime.activate(String(row.key));
        statusMessage = result === "ok" ? "" : "Action no longer available";
        if (result === "ok")
            selectedIndex = -1;

    }

    function dismissSelected() {
        var row = selectedRow();
        if (!row || !runtime)
            return ;

        var nextIndex = selectedIndex;
        runtime.dismiss(String(row.key));
        statusMessage = "";
        if (displayRows.length === 0)
            selectedIndex = -1;
        else
            selectedIndex = Math.min(nextIndex, displayRows.length - 1);
    }

    function activateKey(key) {
        if (!runtime)
            return ;

        var result = runtime.activate(String(key || ""));
        statusMessage = result === "ok" ? "" : "Action no longer available";
    }

    function dismissKey(key) {
        if (!runtime)
            return ;

        runtime.dismiss(String(key || ""));
        statusMessage = "";
    }

    function toggleDnd() {
        if (!runtime)
            return ;

        runtime.setDoNotDisturb(!runtime.doNotDisturb);
    }

    function requestClear() {
        if (!runtime || allDisplayRows.length === 0)
            return ;

        if (clearArmed) {
            confirmClear();
            return ;
        }
        clearArmed = true;
        statusMessage = "Press Clear all again to confirm";
        clearDisarm.restart();
    }

    function confirmClear() {
        if (!runtime)
            return ;

        clearDisarm.stop();
        clearArmed = false;
        statusMessage = "Clearing notifications…";
        runtime.clearAll();
        selectedIndex = -1;
    }

    moduleName: "akshaybapat.notification-center"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    onPopupOpenChanged: NotificationCenter.NotificationCenterHost.viewOpenChanged(root, popupOpen)
    onDisplayRowsChanged: {
        if (displayRows.length === 0)
            selectedIndex = -1;
        else if (selectedIndex >= displayRows.length)
            selectedIndex = displayRows.length - 1;
    }
    onRuntimeStatusChanged: {
        if (runtimeStatus)
            statusMessage = runtimeStatus;

    }
    Component.onCompleted: NotificationCenter.NotificationCenterHost.registerView(root)
    Component.onDestruction: NotificationCenter.NotificationCenterHost.unregisterView(root)

    // Read state moves only once the panel has actually been painted. The
    // PanelWindow wrapper has no frameSwapped signal; the QQuickWindow behind
    // the panel content does.
    Connections {
        function onFrameSwapped() {
            if (root.popupOpen && root.runtime && typeof root.runtime.acknowledgeRendered === "function")
                root.runtime.acknowledgeRendered();

        }

        target: panelContent.Window.window
    }

    Timer {
        interval: 60000
        running: root.popupOpen
        repeat: true
        onTriggered: root.timeRevision += 1
    }

    Timer {
        id: clearDisarm

        interval: 4000
        repeat: false
        onTriggered: {
            root.clearArmed = false;
            root.statusMessage = "";
        }
    }

    Shortcut {
        sequence: "Ctrl+F"
        enabled: root.popupOpen
        onActivated: root.toggleSearch()
    }

    Shortcut {
        sequence: "Home"
        enabled: root.popupOpen && !root.searching
        onActivated: root.setCursor(0)
    }

    Shortcut {
        sequence: "End"
        enabled: root.popupOpen && !root.searching
        onActivated: root.setCursor(root.displayRows.length - 1)
    }

    NotificationBarButton {
        id: button

        anchors.fill: parent
        bar: root.bar
        unreadCount: root.unreadCount
        urgentUnreadCount: root.urgentUnreadCount
        dnd: root.dnd
        sourceAvailable: root.sourceAvailable
        // A missing notification source only spoke through the tooltip, so a
        // dead centre looked exactly like a quiet one. Borrow the same dimmed
        // affordance silenced-and-empty already uses: one language for "this
        // button has nothing to say", no new colour on the bar.
        dimmed: !root.sourceAvailable || (root.dnd && root.unreadCount === 0)
        onLeftPressed: root.toggleFromButton()
        onRightPressed: root.toggleDnd()
    }

    KeyboardPanel {
        id: popup

        anchorItem: button
        owner: root
        bar: root.bar
        open: root.popupOpen
        focusTarget: keyCatcher
        contentWidth: fittedContentWidth(Style.space(440))
        contentHeight: fittedContentHeight(panelContent.implicitHeight, Style.space(760))

        PanelKeyCatcher {
            id: keyCatcher

            anchors.fill: parent
            blocked: root.searching
            onMoveRequested: function(dx, dy) {
                if (dy !== 0)
                    root.moveCursor(dy);

            }
            onActivateRequested: root.activateSelected()
            onDeleteRequested: root.dismissSelected()
            onCloseRequested: root.closeFromHost()
            onTabRequested: function(direction) {
                root.switchPanel(direction);
            }
            onTextKey: function(value) {
                var key = String(value || "").toLowerCase();
                if (key === "/")
                    root.beginSearch();
                else if (key === "d")
                    root.toggleDnd();
                else if (key === "c")
                    root.requestClear();
            }

            NotificationPanel {
                id: panelContent

                anchors.fill: parent
                groups: root.displayGroups
                selectedIndex: root.selectedIndex
                unreadAtOpen: root.sessionNewCount
                urgentUnread: root.sessionUrgentCount
                visibleCount: root.displayRows.length
                totalCount: root.allDisplayRows.length
                unreadFilterCount: root.displayUnreadCount
                urgentFilterCount: root.displayUrgentCount
                filterMode: root.filterMode
                externallyFiltered: true
                searching: root.searching
                query: root.query
                dnd: root.dnd
                clearArmed: root.clearArmed
                sourceAvailable: root.sourceAvailable
                statusMessage: root.statusMessage
                foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                uiFont: root.uiFont
                onSearchRequested: root.toggleSearch()
                onSearchEdited: function(value) {
                    root.query = value;
                    root.selectedIndex = root.displayRows.length > 0 ? 0 : -1;
                }
                onSearchMoveRequested: function(delta) {
                    root.moveCursor(delta);
                }
                onSearchActivateRequested: root.activateSelected()
                onSearchEscapeRequested: root.endSearch()
                onDndRequested: root.toggleDnd()
                onClearRequested: root.requestClear()
                onFilterModeRequested: function(mode) {
                    root.setFilterMode(mode);
                }
                onRowHovered: function(flatIndex, isHovered) {
                    root.hoverCursor(flatIndex, isHovered);
                }
                onRowActivateRequested: function(key) {
                    root.activateKey(key);
                }
                onRowDismissRequested: function(key) {
                    root.dismissKey(key);
                }
            }

        }

    }

}
