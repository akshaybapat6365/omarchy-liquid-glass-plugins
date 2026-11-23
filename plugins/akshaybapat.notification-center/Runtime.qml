import "CenterLogic.js" as CenterLogic
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// The notification center reads Omarchy 4.5's notification daemon the way any
// add-on may. What to show comes from the daemon's own state files, which it
// rewrites whole a moment after every change; what to do goes through its
// public "notifications" IPC target, exactly as a keybinding would. Omarchy
// 4.5 gives an add-on no handle on another plugin's service object, and this
// needs none.
Item {
    id: runtime

    property var shell: null
    property string omarchyPath: Quickshell.env("OMARCHY_PATH")
    property bool active: true
    // The daemon keeps these under $HOME whatever XDG_STATE_HOME says.
    readonly property string sourceDir: Quickshell.env("HOME") + "/.local/state/omarchy/notifications"
    readonly property string serviceTarget: "notifications"
    readonly property var labels: ({
        "redactedSummary": I18n.t("notifications.redactedSummary"),
        "redactedBody": I18n.t("notifications.redactedBody")
    })
    property var liveRows: []
    property var historyRows: []
    property bool liveRead: false
    property bool historyRead: false
    property bool serviceDnd: false
    // Available once the daemon's files exist; until then the bell says so.
    readonly property bool sourceReady: liveRead || historyRead
    readonly property bool doNotDisturb: serviceDnd
    readonly property string home: Quickshell.env("HOME")
    readonly property string configuredStateHome: Quickshell.env("XDG_STATE_HOME")
    readonly property string stateHome: configuredStateHome ? configuredStateHome : home + "/.local/state"
    readonly property string stateDir: stateHome + "/akshaybapat.notification-center"
    readonly property string statePath: stateDir + "/state.json"
    property bool stateLoaded: false
    property real seenThrough: 0
    property var dismissed: []
    property var rows: []
    property int unreadCount: 0
    property int urgentUnreadCount: 0
    property real maxTimestamp: 0
    property int modelRevision: 0
    property bool panelOpen: false
    property var visualUnreadKeys: ({
    })
    property int sessionNewCount: 0
    property int sessionUrgentCount: 0
    property real pendingSeenThrough: 0
    property bool clearing: false
    property int clearChecks: 0
    property int clearRetries: 0
    property string lastActionStatus: ""
    property var serviceCalls: []
    property var serviceCallDone: null
    // The exit and the end of its output arrive in either order.
    property int serviceExit: -1
    property bool serviceOutputDone: false

    // A file the daemon has not written yet keeps what was last read; one
    // that is gone (or never was) is no rows.
    function acceptRows(which, raw, present) {
        var parsed = present ? CenterLogic.parseServiceRows(raw, which, runtime.labels) : [];
        if (parsed === null)
            return ;

        if (which === "live") {
            runtime.liveRows = parsed;
            runtime.liveRead = present;
        } else {
            runtime.historyRows = parsed;
            runtime.historyRead = present;
        }
        modelDebounce.restart();
    }

    function acceptQuiet(raw) {
        var dnd = CenterLogic.parseQuiet(raw);
        if (dnd !== null)
            runtime.serviceDnd = dnd;

    }

    function countKeys(map) {
        var count = 0;
        var values = map || {
        };
        for (var key in values) if (values[key] === true) {
            count += 1;
        }
        return count;
    }

    function cloneKeys(map) {
        var result = {
        };
        var values = map || {
        };
        for (var key in values) if (values[key] === true) {
            result[key] = true;
        }
        return result;
    }

    // The icon the card asked for, else the app's own name in the theme; the
    // group falls back to its initial.
    function iconSource(row) {
        var named = String(row.appIcon || "");
        var found = named ? Quickshell.iconPath(named, true) : "";
        if (found)
            return found;

        var slug = String(row.app || "").toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^[-.]+|[-.]+$/g, "");
        return slug ? Quickshell.iconPath(slug, true) : "";
    }

    function decorateRows(values) {
        var source = values || [];
        for (var i = 0; i < source.length; i++) {
            // 4.5 never stores a card's picture, only its icon name.
            source[i].previewSource = "";
            source[i].iconSource = runtime.iconSource(source[i]);
            source[i].actionable = source[i].live && !!source[i].serviceKey;
        }
        return source;
    }

    function rebuild() {
        if (!runtime.stateLoaded || runtime.clearing) {
            runtime.rows = [];
            runtime.unreadCount = 0;
            runtime.urgentUnreadCount = 0;
            runtime.maxTimestamp = 0;
            runtime.modelRevision += 1;
            return ;
        }
        var built = CenterLogic.buildRows(runtime.historyRows, runtime.liveRows, runtime.dismissed, runtime.seenThrough, runtime.visualUnreadKeys, runtime.panelOpen);
        if (runtime.panelOpen) {
            // While the panel is open, whatever arrives stays marked new until
            // it closes; it counts as seen once a frame has shown it.
            var nextVisual = runtime.cloneKeys(runtime.visualUnreadKeys);
            var changed = false;
            var newest = runtime.pendingSeenThrough;
            for (var i = 0; i < built.rows.length; i++) {
                var row = built.rows[i];
                if (!row.unread || nextVisual[row.key] === true)
                    continue;

                nextVisual[row.key] = true;
                newest = Math.max(newest, row.timestamp);
                changed = true;
            }
            if (changed) {
                runtime.visualUnreadKeys = nextVisual;
                runtime.sessionNewCount = runtime.countKeys(nextVisual);
                runtime.pendingSeenThrough = newest;
                built = CenterLogic.buildRows(runtime.historyRows, runtime.liveRows, runtime.dismissed, runtime.seenThrough, runtime.visualUnreadKeys, true);
            }
        }
        var decorated = runtime.decorateRows(built.rows);
        var visualUrgent = 0;
        for (var urgentIndex = 0; urgentIndex < decorated.length; urgentIndex++) {
            if (decorated[urgentIndex].visualUnread && decorated[urgentIndex].urgency === 2)
                visualUrgent += 1;

        }
        runtime.rows = decorated;
        runtime.unreadCount = built.unreadCount;
        runtime.urgentUnreadCount = built.urgentUnreadCount;
        runtime.sessionUrgentCount = runtime.panelOpen ? visualUrgent : 0;
        runtime.maxTimestamp = built.maxTimestamp;
        runtime.modelRevision += 1;
        runtime.pruneDismissed();
    }

    function groupsForQuery(query, now) {
        runtime.modelRevision;
        return CenterLogic.groupRows(runtime.rows, query, now === undefined ? Date.now() : now);
    }

    function flatRowsForQuery(query, now) {
        return CenterLogic.flattenGroups(runtime.groupsForQuery(query, now));
    }

    function pruneDismissed() {
        var next = CenterLogic.pruneDismissed(runtime.dismissed, CenterLogic.keyMap(runtime.liveRows), CenterLogic.keyMap(runtime.historyRows), Date.now(), 600000);
        if (CenterLogic.sameRecords(next, runtime.dismissed))
            return ;

        runtime.dismissed = next;
        runtime.scheduleStateSave();
    }

    function loadState(raw) {
        if (runtime.stateLoaded)
            return ;

        var parsed = CenterLogic.parseState(raw);
        runtime.seenThrough = parsed.seenThrough;
        runtime.dismissed = parsed.dismissed;
        runtime.stateLoaded = true;
        runtime.rebuild();
    }

    function scheduleStateSave() {
        if (runtime.stateLoaded)
            stateSaveTimer.restart();

    }

    function flushState() {
        var payload = {
            "version": 1,
            "seenThrough": Math.max(0, runtime.seenThrough),
            "dismissed": runtime.dismissed
        };
        stateFile.setText(JSON.stringify(payload, null, 2) + "\n");
    }

    function setPanelOpen(open) {
        var wanted = !!open;
        if (wanted === runtime.panelOpen)
            return ;

        runtime.panelOpen = wanted;
        runtime.visualUnreadKeys = ({
        });
        runtime.sessionNewCount = 0;
        runtime.sessionUrgentCount = 0;
        runtime.pendingSeenThrough = 0;
        runtime.rebuild();
    }

    function acknowledgeRendered() {
        if (!runtime.panelOpen || runtime.pendingSeenThrough <= runtime.seenThrough)
            return ;

        runtime.seenThrough = runtime.pendingSeenThrough;
        runtime.pendingSeenThrough = 0;
        runtime.scheduleStateSave();
        runtime.rebuild();
    }

    function removeVisualKey(key) {
        if (!runtime.visualUnreadKeys[key])
            return ;

        var next = runtime.cloneKeys(runtime.visualUnreadKeys);
        delete next[key];
        runtime.visualUnreadKeys = next;
        runtime.sessionNewCount = runtime.countKeys(next);
    }

    function rowForKey(key) {
        var wanted = String(key || "");
        for (var i = 0; i < runtime.rows.length; i++) if (runtime.rows[i].key === wanted) {
            return runtime.rows[i];
        }
        return null;
    }

    function rememberDismissed(key) {
        runtime.dismissed = CenterLogic.addDismissed(runtime.dismissed, key, Date.now());
        runtime.removeVisualKey(key);
        runtime.scheduleStateSave();
    }

    // One omarchy-shell call at a time, in the order asked; done(ok, output)
    // hears how it went.
    function callService(args, done) {
        runtime.serviceCalls = runtime.serviceCalls.concat([{
            "args": args,
            "done": done || null
        }]);
        Qt.callLater(runtime.nextServiceCall);
    }

    function nextServiceCall() {
        if (!runtime.active || serviceCall.running || runtime.serviceCalls.length === 0)
            return ;

        var next = runtime.serviceCalls[0];
        runtime.serviceCalls = runtime.serviceCalls.slice(1);
        runtime.serviceCallDone = next.done;
        runtime.serviceExit = -1;
        runtime.serviceOutputDone = false;
        serviceCall.command = ["omarchy-shell", runtime.serviceTarget].concat(next.args);
        serviceCall.running = true;
    }

    function finishServiceCall() {
        if (runtime.serviceExit < 0 || !runtime.serviceOutputDone)
            return ;

        var code = runtime.serviceExit;
        var done = runtime.serviceCallDone;
        runtime.serviceCallDone = null;
        runtime.serviceExit = -1;
        if (code !== 0)
            runtime.lastActionStatus = "Notifications are not responding";

        if (done)
            done(code === 0, String(serviceReply.text || "").trim());

        Qt.callLater(runtime.nextServiceCall);
    }

    // A history row is only hidden here; a card on screen is closed by the
    // daemon, and goes on to its history, still hidden.
    function dismiss(key) {
        var row = runtime.rowForKey(key);
        if (!row)
            return "none";

        runtime.rememberDismissed(row.key);
        runtime.rebuild();
        if (row.live && row.serviceKey)
            runtime.callService(["dismissKey", row.serviceKey]);

        runtime.lastActionStatus = "dismissed";
        return "ok";
    }

    // The card's own click: its command, the sender's default action, or its
    // window, as 4.5 decides.
    function activate(key) {
        var row = runtime.rowForKey(key);
        if (!row || row.actionable !== true) {
            runtime.lastActionStatus = "Action no longer available";
            return "unavailable";
        }
        runtime.rememberDismissed(row.key);
        runtime.rebuild();
        runtime.callService(["activateKey", row.serviceKey], function(ok, output) {
            if (ok && output !== "ok")
                runtime.lastActionStatus = "Action no longer available";

        });
        runtime.lastActionStatus = "opened";
        return "ok";
    }

    function markAllRead() {
        runtime.seenThrough = Math.max(runtime.seenThrough, runtime.maxTimestamp);
        runtime.visualUnreadKeys = ({
        });
        runtime.sessionNewCount = 0;
        runtime.sessionUrgentCount = 0;
        runtime.pendingSeenThrough = 0;
        runtime.scheduleStateSave();
        runtime.rebuild();
        return "ok";
    }

    function clearAll() {
        if (!runtime.sourceReady)
            return "unavailable";

        if (runtime.clearing)
            return "pending";

        runtime.clearing = true;
        runtime.clearChecks = 0;
        runtime.clearRetries = 0;
        runtime.lastActionStatus = "Clearing notifications…";
        runtime.seenThrough = Math.max(Date.now(), runtime.maxTimestamp);
        runtime.dismissed = [];
        runtime.visualUnreadKeys = ({
        });
        runtime.sessionNewCount = 0;
        runtime.sessionUrgentCount = 0;
        runtime.rebuild();
        runtime.scheduleStateSave();
        runtime.requestSourceClear();
        clearSettleTimer.start();
        return "pending";
    }

    // The cards close first, which files them in history; then history goes.
    function requestSourceClear() {
        runtime.callService(["dismissAll"]);
        runtime.callService(["clearHistory"]);
    }

    function finishClearIfSettled() {
        runtime.clearChecks += 1;
        if (runtime.liveRows.length > 0 || runtime.historyRows.length > 0) {
            if (runtime.clearChecks < 50)
                return ;

            if (runtime.clearRetries < 2) {
                runtime.clearRetries += 1;
                runtime.clearChecks = 0;
                runtime.lastActionStatus = "Clear retry " + runtime.clearRetries + " of 2…";
                runtime.requestSourceClear();
                return ;
            }
            runtime.lastActionStatus = "Clear could not finish";
        } else {
            runtime.lastActionStatus = "All notifications cleared";
        }
        runtime.clearing = false;
        clearSettleTimer.stop();
        runtime.rebuild();
    }

    // Shown at once; quiet.json, rewritten by the daemon a moment later, has
    // the last word.
    function setDoNotDisturb(value) {
        if (!runtime.sourceReady)
            return "unavailable";

        var on = !!value;
        runtime.serviceDnd = on;
        runtime.callService(["setDnd", on ? "on" : "off"], function(ok, output) {
            if (output === "on" || output === "off")
                runtime.serviceDnd = output === "on";
            else
                quietFile.reload();
        });
        return on ? "on" : "off";
    }

    // For `omarchy-shell akshaybapat.notification-center diag`.
    function diagnostics() {
        var live = 0;
        for (var i = 0; i < runtime.rows.length; i++) if (runtime.rows[i].live) {
            live += 1;
        }
        return {
            "sourceReady": runtime.sourceReady,
            "doNotDisturb": runtime.doNotDisturb,
            "unread": runtime.unreadCount,
            "urgentUnread": runtime.urgentUnreadCount,
            "rows": runtime.rows.length,
            "live": live,
            "clearing": runtime.clearing,
            "status": runtime.lastActionStatus
        };
    }

    visible: false
    onActiveChanged: {
        if (!active) {
            stateSaveTimer.stop();
            clearSettleTimer.stop();
            sourceRetry.stop();
            runtime.serviceCalls = [];
        }
    }
    Component.onCompleted: ensureStateDir.running = true
    Component.onDestruction: {
        if (runtime.stateLoaded)
            runtime.flushState();

    }

    // Watched by path, so the daemon's atomic rewrites and a file that comes
    // and goes are both seen. A directory that does not exist yet cannot be
    // watched; sourceRetry looks again until it does.
    FileView {
        id: liveFile

        path: runtime.sourceDir + "/live.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: runtime.acceptRows("live", text(), true)
        onLoadFailed: {
            runtime.acceptRows("live", "", false);
            sourceRetry.start();
        }
    }

    FileView {
        id: historyFile

        path: runtime.sourceDir + "/history.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: runtime.acceptRows("history", text(), true)
        onLoadFailed: {
            runtime.acceptRows("history", "", false);
            sourceRetry.start();
        }
    }

    FileView {
        id: quietFile

        path: runtime.sourceDir + "/quiet.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: runtime.acceptQuiet(text())
        onLoadFailed: sourceRetry.start()
    }

    Timer {
        id: sourceRetry

        interval: 3000
        repeat: false
        onTriggered: {
            if (!runtime.active)
                return ;

            if (!runtime.liveRead)
                liveFile.reload();

            if (!runtime.historyRead)
                historyFile.reload();

            quietFile.reload();
        }
    }

    Process {
        id: serviceCall

        onExited: function(exitCode) {
            runtime.serviceExit = exitCode;
            runtime.finishServiceCall();
        }

        stdout: StdioCollector {
            id: serviceReply

            waitForEnd: true
            onStreamFinished: {
                runtime.serviceOutputDone = true;
                runtime.finishServiceCall();
            }
        }

    }

    Process {
        id: ensureStateDir

        command: ["mkdir", "-p", runtime.stateDir]
        onExited: stateFile.reload()
    }

    FileView {
        id: stateFile

        path: runtime.statePath
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: runtime.loadState(text())
        onLoadFailed: runtime.loadState("")
    }

    Timer {
        id: stateSaveTimer

        interval: 120
        repeat: false
        onTriggered: runtime.flushState()
    }

    Timer {
        id: modelDebounce

        interval: 30
        repeat: false
        onTriggered: runtime.rebuild()
    }

    Timer {
        id: clearSettleTimer

        interval: 100
        repeat: true
        onTriggered: runtime.finishClearIfSettled()
    }

}
