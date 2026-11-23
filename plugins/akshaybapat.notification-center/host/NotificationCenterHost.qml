import QtQuick
import Quickshell.Io
pragma Singleton

Item {
    id: host

    property var runtime: null
    property string runtimeRevision: ""
    property int attachmentCount: 0
    property bool ipcReady: false
    property Component runtimeComponentOverride: null
    property var loadedRuntimeComponent: null
    property string loadedComponentRevision: ""
    property var retiringRuntime: null
    property var pendingShell: null
    property string pendingOmarchyPath: ""
    property string pendingRevision: ""
    property string attachedPluginId: ""
    property var views: []
    property var lastView: null
    readonly property var pluginRegistry: pendingShell && pendingShell.pluginRegistry ? pendingShell.pluginRegistry : null
    readonly property url runtimeUrl: Qt.resolvedUrl("../Runtime.qml")
    readonly property var ipcHandlerObject: centerIpc

    function componentForRevision(revision) {
        if (runtimeComponentOverride)
            return runtimeComponentOverride;

        if (!loadedRuntimeComponent || loadedComponentRevision !== revision) {
            var url = String(runtimeUrl) + "?laneNC=" + encodeURIComponent(revision);
            loadedRuntimeComponent = Qt.createComponent(url, Component.PreferSynchronous);
            loadedComponentRevision = revision;
        }
        if (!loadedRuntimeComponent || loadedRuntimeComponent.status !== Component.Ready) {
            var detail = loadedRuntimeComponent ? loadedRuntimeComponent.errorString() : "no component";
            throw new Error("Could not load notification-center runtime: " + detail);
        }
        return loadedRuntimeComponent;
    }

    function attach(shell, omarchyPath, revision, pluginId) {
        attachmentCount += 1;
        releaseTimer.stop();
        pendingShell = shell;
        pendingOmarchyPath = String(omarchyPath || "");
        pendingRevision = String(revision || "");
        attachedPluginId = String(pluginId || "");
        if (!pendingRevision || !attachedPluginId) {
            attachmentCount = Math.max(0, attachmentCount - 1);
            throw new Error("Notification center has no runtime revision or plugin identity");
        }
        if (runtime && runtimeRevision === pendingRevision) {
            updateContext(shell, omarchyPath);
            ipcReady = true;
            return runtime;
        }
        if (runtime)
            beginRuntimeReplacement();
        else if (retiringRuntime)
            replacementTimer.restart();
        else
            createPendingRuntime();
        return runtime;
    }

    function beginRuntimeReplacement() {
        var oldRuntime = runtime;
        runtime = null;
        runtimeRevision = "";
        if (oldRuntime) {
            oldRuntime.active = false;
            retiringRuntime = oldRuntime;
            oldRuntime.destroy();
        }
        replacementTimer.restart();
    }

    function finishRuntimeReplacement() {
        if (retiringRuntime) {
            replacementTimer.restart();
            return ;
        }
        if (attachmentCount <= 0 || !pendingRevision)
            return ;

        createPendingRuntime();
    }

    function createPendingRuntime() {
        var component = componentForRevision(pendingRevision);
        var created = component.createObject(host, {
            "shell": pendingShell,
            "omarchyPath": pendingOmarchyPath,
            "active": true
        });
        if (!created)
            throw new Error("Could not create notification-center runtime");

        runtime = created;
        runtimeRevision = pendingRevision;
        ipcReady = true;
        syncRuntimePanelState();
    }

    function updateContext(shell, omarchyPath) {
        pendingShell = shell;
        pendingOmarchyPath = String(omarchyPath || "");
        if (!runtime)
            return ;

        runtime.shell = shell;
        runtime.omarchyPath = pendingOmarchyPath;
    }

    function detach(reloadExpected) {
        attachmentCount = Math.max(0, attachmentCount - 1);
        if (attachmentCount > 0)
            return ;

        if (reloadExpected === false)
            retireRuntime();
        else
            releaseTimer.restart();
    }

    function retireRuntime() {
        ipcReady = false;
        releaseTimer.stop();
        replacementTimer.stop();
        pendingShell = null;
        pendingOmarchyPath = "";
        pendingRevision = "";
        var retiring = runtime;
        runtime = null;
        runtimeRevision = "";
        if (retiring) {
            retiring.active = false;
            retiring.destroy();
        }
        if (!runtimeComponentOverride) {
            loadedRuntimeComponent = null;
            loadedComponentRevision = "";
        }
    }

    function releaseIfIdle() {
        if (attachmentCount > 0)
            return ;

        retireRuntime();
    }

    function reconcileRegistryOwnership() {
        if (!pluginRegistry || !attachedPluginId)
            return ;

        var installed = pluginRegistry.installedPlugins || null;
        var stillInstalled = installed && installed[attachedPluginId];
        if (!stillInstalled || !pluginRegistry.isEnabled(attachedPluginId))
            retireRuntime();

    }

    function registered(view) {
        for (var i = 0; i < views.length; i++) if (views[i] === view) {
            return true;
        }
        return false;
    }

    function registerView(view) {
        if (!view || registered(view))
            return ;

        views = views.concat([view]);
        if (!lastView)
            lastView = view;

    }

    function unregisterView(view) {
        var next = [];
        for (var i = 0; i < views.length; i++) if (views[i] && views[i] !== view) {
            next.push(views[i]);
        }
        views = next;
        if (lastView === view)
            lastView = next.length > 0 ? next[0] : null;

        syncRuntimePanelState();
    }

    function noteInteraction(view) {
        if (view && registered(view))
            lastView = view;

    }

    function firstOpenView() {
        for (var i = 0; i < views.length; i++) {
            var view = views[i];
            if (view && view.popupOpen === true)
                return view;

        }
        return null;
    }

    function focusedView() {
        for (var i = 0; i < views.length; i++) {
            var view = views[i];
            if (view && view.focusPreferred === true)
                return view;

        }
        return null;
    }

    function preferredView() {
        var opened = firstOpenView();
        if (opened)
            return opened;

        var focused = focusedView();
        if (focused)
            return focused;

        if (lastView && registered(lastView))
            return lastView;

        return views.length > 0 ? views[0] : null;
    }

    function closeOtherViews(keep) {
        for (var i = 0; i < views.length; i++) {
            var view = views[i];
            if (view && view !== keep && view.popupOpen === true && typeof view.closeFromHost === "function")
                view.closeFromHost();

        }
    }

    function viewOpenChanged(view, open) {
        if (!view)
            return ;

        if (open) {
            noteInteraction(view);
            closeOtherViews(view);
        }
        syncRuntimePanelState();
    }

    function syncRuntimePanelState() {
        if (!runtime || typeof runtime.setPanelOpen !== "function")
            return ;

        runtime.setPanelOpen(firstOpenView() !== null);
    }

    function openPanel() {
        var view = preferredView();
        return openView(view);
    }

    function openView(view) {
        if (!view || typeof view.openFromHost !== "function")
            return "unavailable";

        if (!registered(view))
            return "unavailable";

        closeOtherViews(view);
        noteInteraction(view);
        view.openFromHost();
        return "ok";
    }

    function closePanel() {
        var changed = false;
        for (var i = 0; i < views.length; i++) {
            var view = views[i];
            if (!view || view.popupOpen !== true || typeof view.closeFromHost !== "function")
                continue;

            view.closeFromHost();
            changed = true;
        }
        return changed ? "ok" : "none";
    }

    function togglePanel() {
        var opened = firstOpenView();
        if (opened)
            return closePanel();

        return openPanel();
    }

    visible: false

    Timer {
        id: releaseTimer

        interval: 1500
        repeat: false
        onTriggered: host.releaseIfIdle()
    }

    Timer {
        id: replacementTimer

        interval: 25
        repeat: false
        onTriggered: host.finishRuntimeReplacement()
    }

    Connections {
        function onRegistryRevisionChanged() {
            host.reconcileRegistryOwnership();
        }

        target: host.pluginRegistry
    }

    IpcHandler {
        id: centerIpc

        function open() : string {
            return host.openPanel();
        }

        function close() : string {
            return host.closePanel();
        }

        function toggle() : string {
            return host.togglePanel();
        }

        function unread() : string {
            return host.runtime ? String(host.runtime.unreadCount) : "unavailable";
        }

        function markAllRead() : string {
            return host.runtime ? host.runtime.markAllRead() : "unavailable";
        }

        function clear() : string {
            return host.runtime ? host.runtime.clearAll() : "unavailable";
        }

        function toggleDnd() : string {
            if (!host.runtime)
                return "unavailable";

            return host.runtime.setDoNotDisturb(!host.runtime.doNotDisturb);
        }

        function ping() : string {
            return host.runtime && host.attachmentCount > 0 ? "ok" : "unavailable";
        }

        // Read-only state dump for diagnosing the runtime from the shell.
        function diag() : string {
            var component = host.loadedRuntimeComponent;
            return JSON.stringify({
                "attachmentCount": host.attachmentCount,
                "ipcReady": host.ipcReady,
                "runtime": host.runtime !== null,
                "runtimeRevision": host.runtimeRevision,
                "pendingRevision": host.pendingRevision,
                "attachedPluginId": host.attachedPluginId,
                "componentRevision": host.loadedComponentRevision,
                "componentStatus": component ? component.status : -1,
                "componentError": component ? component.errorString() : "",
                "state": host.runtime ? host.runtime.diagnostics() : null
            });
        }

        enabled: host.ipcReady
        target: "akshaybapat.notification-center"
    }

}
