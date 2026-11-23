import QtQuick
import "host" as NotificationCenter

Item {
  id: service

  visible: false

  property var shell: null
  property string omarchyPath: ""
  property var manifest: null
  property bool hostAttached: false
  property bool ready: false

  readonly property var runtime: NotificationCenter.NotificationCenterHost.runtime
  readonly property string desiredRevision: manifest
    ? String(manifest.version || "") : ""
  readonly property int registryRevision: shell && shell.pluginRegistry
    ? Number(shell.pluginRegistry.registryRevision || 0) : 0
  readonly property bool enabledInRegistry: {
    if (registryRevision < 0) return true
    if (!shell || !shell.pluginRegistry || !manifest) return true
    return shell.pluginRegistry.isEnabled(String(manifest.id || ""))
  }

  function prepareHost() {
    if (ready || hostAttached || !shell || !manifest || !desiredRevision) return
    attachTimer.restart()
  }

  function attachHost() {
    if (ready || hostAttached || !shell || !manifest || !desiredRevision) return
    NotificationCenter.NotificationCenterHost.attach(
      shell, omarchyPath, desiredRevision, String(manifest.id || ""))
    hostAttached = true
    finishAttach()
  }

  function finishAttach() {
    if (!hostAttached) return
    if (!NotificationCenter.NotificationCenterHost.runtime
        || NotificationCenter.NotificationCenterHost.runtimeRevision !== desiredRevision) {
      readyTimer.restart()
      return
    }
    ready = true
  }

  function reloadExpected() {
    if (!shell || !shell.pluginRegistry || !manifest) return true
    return shell.pluginRegistry.isEnabled(String(manifest.id || ""))
  }

  function retire() {
    if (!hostAttached) return
    attachTimer.stop()
    readyTimer.stop()
    ready = false
    NotificationCenter.NotificationCenterHost.detach(false)
    hostAttached = false
  }

  Timer {
    id: attachTimer

    interval: 25
    repeat: false
    onTriggered: service.attachHost()
  }

  Timer {
    id: readyTimer

    interval: 25
    repeat: false
    onTriggered: service.finishAttach()
  }

  onShellChanged: prepareHost()
  onManifestChanged: prepareHost()
  // onManifestChanged fires before desiredRevision's binding has re-evaluated, so
  // the guard still sees the previous (empty) revision there; this is the handler
  // that runs once the revision is real.
  onDesiredRevisionChanged: prepareHost()
  onEnabledInRegistryChanged: if (!enabledInRegistry) retire()
  onOmarchyPathChanged: {
    if (hostAttached)
      NotificationCenter.NotificationCenterHost.updateContext(shell, omarchyPath)
    else
      prepareHost()
  }

  Component.onCompleted: prepareHost()
  Component.onDestruction: if (hostAttached)
    NotificationCenter.NotificationCenterHost.detach(reloadExpected())
}
