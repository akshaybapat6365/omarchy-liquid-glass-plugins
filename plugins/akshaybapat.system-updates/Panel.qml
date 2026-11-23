import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Networking
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "akshaybapat.system-updates"
  ipcTarget: "akshaybapat.system-updates"
  property var repos: []
  property int total: 0
  property string filterMode: "all"
  readonly property var installedRepos: {
    var filtered = []
    for (var i = 0; i < repos.length; i++) {
      if (repos[i].installed === true) filtered.push(repos[i])
    }
    return filtered
  }
  readonly property var visibleRepos: {
    if (filterMode !== "available") return installedRepos
    var filtered = []
    for (var i = 0; i < installedRepos.length; i++) {
      var r = installedRepos[i]
      if (Number(r.count || 0) > 0 || r.error === true) filtered.push(r)
    }
    return filtered
  }
  readonly property bool hasCheckError: {
    for (var i = 0; i < installedRepos.length; i++) {
      if (installedRepos[i].error === true) return true
    }
    return false
  }
  readonly property string failedSourceNames: {
    var names = []
    for (var i = 0; i < installedRepos.length; i++) {
      if (installedRepos[i].error === true) names.push(installedRepos[i].name)
    }
    return names.join(", ")
  }
  property var repoStatus: ({ "pacman": "idle", "aur": "idle", "flatpak": "idle", "omarchy": "idle" })
  property double lastPingAt: 0
  property string lastCheckedText: ""
  property bool settingsMode: false
  property var draftSettings: ({})
  property string settingsStatusText: ""
  property string pendingRepo: ""
  property bool fastPollActive: false
  property int fastPollCount: 0
  readonly property int maxFastPolls: 30
  // Hyprland event-socket tracking of the updater terminal window. When it
  // closes, updates are done and one immediate rescan replaces blind polling.
  property string watchedWindowAddress: ""
  property bool awaitingUpdateWindow: false

  readonly property string barIcon: root.total > 0 ? "󰚰" : "󰏗"
  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: root.bar ? root.bar.urgent : Commons.Color.urgent
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property string uiFont: {
    var f = Style.font.menuFamily
    return (f && f.length > 0 && f !== Style.font.family && f !== "monospace") ? f : "Inter Display"
  }
  readonly property int pillRadius: Math.max(8, Style.cornerRadius)
  readonly property int cardRadius: Math.max(8, Style.cornerRadius - 2)
  readonly property var filterTabs: [
    {
      "id": "all",
      "label": strings.t("updates.allSources"),
      "count": root.installedRepos.length,
      "accented": false
    },
    {
      "id": "available",
      "label": strings.t("updates.available"),
      "count": root.total,
      "accented": root.total > 0
    }
  ]

  function alpha(colorValue, opacity) {
    return Qt.rgba(colorValue.r, colorValue.g, colorValue.b, opacity)
  }

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  function fmtInt(value) {
    return Commons.I18n.formatNumber(Math.floor(Number(value) || 0))
  }
  // Only skip curl probes when NetworkManager definitively reports no
  // connectivity. Unknown/Portal/Limited must still attempt curl (ground
  // truth) — requiring Full here marked all repos offline when NM checks
  // are disabled, unconfigured, or return a captive-portal/limited state.
  readonly property bool networkOnline: !Networking.canCheckConnectivity || Networking.connectivity !== NetworkConnectivity.None
  readonly property var repoUrls: ({
    "pacman": "https://archlinux.org/packages/",
    "aur": "https://aur.archlinux.org/",
    "flatpak": "https://flathub.org/",
    "omarchy": "https://omarchy.org/"
  })

  // Update commands are owned by this panel, not by the scan cache. The cache
  // is user-writable, so a command read back from it must never reach a shell.
  // AUR is the only repo whose command depends on the installed helper; the
  // scanner reports that helper as a fixed enum and it is validated below.
  readonly property var repoUpdateCommands: ({
    // Arch goes through Omarchy's own updater, which snapshots first and
    // keeps its pacnew and keyring steps; a bare pacman -Syu skips them.
    "pacman": "omarchy update; echo; read -n 1 -s -r -p 'Done. Press any key to close'",
    "flatpak": "flatpak update; echo; read -n 1 -s -r -p 'Done. Press any key to close'",
    "omarchy": "omarchy update; echo; read -n 1 -s -r -p 'Done. Press any key to close'"
    // No "plugins" command on purpose: user plugins may be managed by a
    // package manager or dotfiles repo, so an in-place pull can conflict. The
    // row lists what is new, with links; updating stays a deliberate step.
  })
  readonly property var aurHelpers: ["checkupdates-aur", "yay", "paru"]

  // Rows the user has expanded to reveal their pending packages, keyed by
  // repo id. A plain object keeps multiple rows open at once.
  property var expandedRepos: ({})

  function isRepoExpanded(id) {
    return expandedRepos[id] === true
  }

  function toggleRepo(id) {
    var next = {}
    for (var key in expandedRepos) next[key] = expandedRepos[key]
    next[id] = !next[id]
    expandedRepos = next
  }

  function selectFilter(mode) {
    var next = String(mode || "all")
    filterMode = next === "available" ? "available" : "all"
    if (sourcesFlick) sourcesFlick.contentY = 0
  }

  function openUrl(url) {
    if (Model.isWebUrl(url)) Qt.openUrlExternally(url)
  }

  function refresh() {
    if (!scannerProc.running) scannerProc.running = true
  }

  property string lastCacheText: ""

  // Last-good scan result on disk: the bar renders it instantly at shell
  // start with zero spawns, and the first live scan waits for bootTimer.
  // The file lives in ~/.cache/omarchy, which already exists.
  readonly property string cachePath: {
    var base = Quickshell.env("XDG_CACHE_HOME")
    if (!base) base = Quickshell.env("HOME") + "/.cache"
    return base + "/omarchy/akshaybapat.system-updates.json"
  }

  function updateRepos(raw) {
    var text = String(raw || "")
    var parsed = Model.parseRepoList(text)
    repos = parsed.repos
    total = parsed.total
    // One small disk write per changed result, not per poll; the
    // text !== lastCacheText guard also makes a write->load echo a no-op.
    if (text !== "" && text !== lastCacheText) {
      lastCacheText = text
      try { cacheFile.setText(text) } catch (e) {}
    }
    // Opened before the first scan landed: nothing was probed yet, so probe
    // now rather than leave every row without its Online marker.
    if (root.opened && root.repoStatus.pacman === "idle") root.pingRepos()
  }

  function iconSource(id) {
    if (id === "pacman") return Qt.resolvedUrl("assets/arch-logo.svg")
    if (id === "aur") return Qt.resolvedUrl("assets/arch-logo.svg")
    if (id === "flatpak") return Qt.resolvedUrl("assets/flatpak.svg")
    if (id === "omarchy") return Qt.resolvedUrl("assets/omarchy.svg")
    if (id === "plugins") return Qt.resolvedUrl("assets/plugins.svg")
    return ""
  }

  // Counts come from the scan cache, so coerce them before placing them in
  // any rendered label.
  function nonNegativeCount(value) {
    var count = Number(value)
    return isFinite(count) && count > 0 ? Math.floor(count) : 0
  }

  function repoBadgeText(repo) {
    if (repo.error === true) return strings.t("updates.checkFailed")
    var count = root.nonNegativeCount(repo.count)
    if (count > 0) {
      return (count === 1 ? strings.t("updates.shortOneUpdate") : strings.t("updates.shortManyUpdates")).arg(root.fmtInt(count))
    }
    return strings.t("updates.upToDateShort")
  }

  // Kept for backwards compatibility with any external inspection.
  function statusHtml(repo) {
    var fgHex = root.fg.toString()
    var dimHex = root.dim.toString()
    var urgentHex = root.urgent.toString()
    var count = root.nonNegativeCount(repo.count)
    var pkgCount = root.nonNegativeCount(repo.pkgCount)
    var parts = []
    if (repo.error === true) {
      parts.push("<font color=\"" + urgentHex + "\">" + strings.t("updates.checkFailed") + "</font>")
    } else if (count > 0) {
      var countText = count === 1 ? strings.t("updates.oneUpdate").arg(root.fmtInt(count)) : strings.t("updates.manyUpdates").arg(root.fmtInt(count))
      parts.push("<font color=\"" + fgHex + "\">" + countText + "</font>")
    } else {
      parts.push("<font color=\"" + dimHex + "\">" + strings.t("updates.upToDateShort") + "</font>")
    }
    var status = root.repoStatus[repo.id]
    if (pkgCount > 0)
      parts.push("<font color=\"" + dimHex + "\">· " + strings.t("updates.pkgs").arg(root.fmtInt(pkgCount)) + "</font>")
    if (status === "checking")
      parts.push("<i><font color=\"" + dimHex + "\">· " + strings.t("updates.checking") + "</font></i>")
    else if (status === "online")
      parts.push("<font color=\"" + dimHex + "\">· " + strings.t("updates.online") + "</font>")
    else if (status === "offline")
      parts.push("<font color=\"" + (repo.error === true ? dimHex : urgentHex) + "\">✗ " + strings.t("updates.offline") + "</font>")
    return parts.join(" ")
  }

  // Hero status line, in the kit's caps meta voice: the overall answer first,
  // then the one panel-wide "checked" time. A failed check outranks a count,
  // so the header can never read "up to date" while a source is unknown.
  readonly property string heroMeta: {
    if (root.settingsMode) return strings.t("updates.settingsMeta")
    var head = root.hasCheckError ? strings.t("updates.checkFailed")
      : root.total > 0 ? (root.total === 1 ? strings.t("updates.oneUpdate") : strings.t("updates.manyUpdates")).arg(root.fmtInt(root.total))
      : root.installedRepos.length > 0 ? strings.t("updates.upToDateShort")
      : strings.t("updates.checking")
    return root.lastCheckedText !== "" ? head + " · " + root.lastCheckedText : head
  }

  function updateCommandFor(repo) {
    var id = String(repo && repo.id || "")
    if (id === "aur") {
      var helper = String(repo.updater || "")
      if (root.aurHelpers.indexOf(helper) === -1) return ""
      return helper + (helper === "checkupdates-aur" ? "" : " -Sua")
        + "; echo; read -n 1 -s -r -p 'Done. Press any key to close'"
    }
    return Object.prototype.hasOwnProperty.call(root.repoUpdateCommands, id)
      ? root.repoUpdateCommands[id] : ""
  }

  function updateRepo(id) {
    var repo = null
    for (var i = 0; i < repos.length; i++) {
      if (repos[i].id === id) {
        repo = repos[i]
        break
      }
    }
    var cmd = root.updateCommandFor(repo)
    if (!cmd) return

    pendingRepo = id
    fastPollCount = 0
    // Primary completion signal: Hyprland closewindow of the updater terminal.
    if (watchedWindowAddress === "" && !awaitingUpdateWindow) {
      awaitingUpdateWindow = true
      watchCaptureTimeout.restart()
    }
    // Fallback while the terminal stays open (or if event capture fails).
    fastPollActive = true
    fastPollTimer.interval = 10000
    fastPollTimer.restart()

    var launcher = "omarchy-launch-terminal"
    root.bar.run(launcher + " bash -c " + Util.shellQuote(cmd))
  }

  function stopFastPoll() {
    pendingRepo = ""
    watchedWindowAddress = ""
    awaitingUpdateWindow = false
    fastPollActive = false
    fastPollTimer.stop()
    fastPollTimer.interval = 10000
    refresh()
  }

  function setRepoStatus(id, status) {
    var next = {}
    for (var k in root.repoStatus) next[k] = root.repoStatus[k]
    if (next[id] !== undefined) next[id] = status
    root.repoStatus = next
  }

  function buildPingCommand() {
    var script = ""
    for (var i = 0; i < repos.length; i++) {
      var r = repos[i]
      var id = String(r.id || "")
      // The cache is user-writable: only an id this panel knows may be
      // spliced into the shell command below.
      if (!Object.prototype.hasOwnProperty.call(repoUrls, id)) continue
      var url = repoUrls[id]
      // Every installed repo is probed — the Online/Offline badge is useful
      // on up-to-date repos too, not just ones with updates waiting.
      if (r.installed !== true) continue
      script += "(curl -sI --connect-timeout 6 --max-time 9 " + url +
        " >/dev/null 2>&1 && echo '" + id + " online' || echo '" + id + " offline') & "
    }
    return script + "wait"
  }

  function pingRepos() {
    if (Date.now() - lastPingAt < 600000 && repoStatus.pacman !== "idle") return
    lastPingAt = Date.now()
    updateLastChecked()
    var next = {}
    for (var k in repoStatus) next[k] = repoStatus[k]
    var pinged = 0
    for (var i = 0; i < repos.length; i++) {
      var r = repos[i]
      var id = String(r.id || "")
      if (r.installed === true && Object.prototype.hasOwnProperty.call(repoUrls, id)) {
        next[id] = "checking"
        pinged++
      }
    }
    repoStatus = next
    if (pinged === 0) return

    if (!networkOnline) {
      var off = {}
      for (var k2 in repoStatus) off[k2] = repoStatus[k2] === "checking" ? "offline" : repoStatus[k2]
      repoStatus = off
      return
    }
    pingProc.command = ["bash", "-c", buildPingCommand()]
    if (!pingProc.running) pingProc.running = true
  }

  function updateLastChecked() {
    if (lastPingAt === 0) { lastCheckedText = ""; return }
    var elapsed = Math.floor((Date.now() - lastPingAt) / 1000)
    if (elapsed < 60) lastCheckedText = strings.t("updates.checkedAgoSec").arg(root.fmtInt(elapsed))
    else if (elapsed < 3600) lastCheckedText = strings.t("updates.checkedAgoMin").arg(root.fmtInt(Math.floor(elapsed / 60)))
    else lastCheckedText = strings.t("updates.checkedAgoHour").arg(root.fmtInt(Math.floor(elapsed / 3600)))
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // `omarchy bar set` stores a bare value as a JSON string unless --json is
  // used, so a boolean read back from shell.json can be "false". Coerce it
  // instead of treating every non-false value as true.
  function boolValue(value, fallback) {
    if (value === undefined || value === null) return fallback
    if (typeof value === "string") return value !== "false" && value !== "0" && value !== ""
    return value !== false
  }

  function boolSetting(name, fallback) {
    return root.boolValue(root.setting(name, fallback), fallback)
  }

  readonly property bool autoRefresh: root.boolSetting("autoRefresh", true)
  readonly property bool alwaysShow: root.boolSetting("alwaysShow", true)
  readonly property int refreshIntervalSec: {
    var value = Number(root.setting("refreshIntervalSec", 1800))
    if (!isFinite(value)) value = 1800
    return Math.round(root.clamp(value, 300, 7200))
  }

  function cloneObject(value, fallback) {
    if (value === undefined || value === null) return fallback
    try { return JSON.parse(JSON.stringify(value)) }
    catch (e) { return fallback }
  }

  function normalizedSettings(source) {
    var next = cloneObject(source, {}) || {}
    var refresh = Number(next.refreshIntervalSec === undefined || next.refreshIntervalSec === null ? 1800 : next.refreshIntervalSec)
    next.refreshIntervalSec = Math.round(root.clamp(isFinite(refresh) ? refresh : 1800, 300, 7200))
    next.alwaysShow = root.boolValue(next.alwaysShow, true)
    next.autoRefresh = root.boolValue(next.autoRefresh, true)
    return next
  }

  function canPersistSettings() {
    return !!(bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
  }

  function openSettings() {
    draftSettings = normalizedSettings(settings)
    settingsStatusText = ""
    settingsMode = true
    open()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function showMain() {
    settingsMode = false
    settingsStatusText = ""
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function saveSettings() {
    var next = normalizedSettings(draftSettings)
    draftSettings = next
    root.settings = next
    if (canPersistSettings()) {
      bar.shell.updateEntryInline(root.moduleName, next)
      settingsStatusText = strings.t("updates.savedToShell")
    } else {
      settingsStatusText = strings.t("updates.savedForSession")
    }
  }

  function draftValue(name, fallback) {
    var value = draftSettings ? draftSettings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function setDraftValue(name, value) {
    var next = normalizedSettings(draftSettings)
    next[name] = value
    draftSettings = next
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  function triggerPress(button) {
    if (button === Qt.RightButton) {
      openSettings()
      return
    }
    if (button === Qt.MiddleButton) {
      refresh()
      return
    }
    if (opened) close()
    else { open(); refresh() }
  }

  onOpenedChanged: {
    if (opened) {
      filterMode = "all"
      refresh()
      pingRepos()
    } else {
      settingsMode = false
    }
  }

  // The Panel base auto-wires open/close/show/hide/toggle IPC, but has no
  // headless refresh — and a second IpcHandler on the same target conflicts
  // with it. So take over IPC wholesale (unifi-panel pattern) and re-expose
  // the full set plus refresh, which runs a scan without opening the panel.
  manageIpc: false

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  // A failed check must stay reachable even when the icon is set to hide.
  visible: total > 0 || hasCheckError || root.alwaysShow
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  Process {
    id: scannerProc
    command: ["python3", root.pathFromUrl(Qt.resolvedUrl("scripts/check_updates.py"))]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateRepos(text)
    }
    stderr: StdioCollector {
      id: scannerErr
      waitForEnd: true
    }
    // A failed scan used to be completely silent (empty output parses to an
    // empty list, and nothing was logged). Surface it so the log — and the
    // missing cache file — actually says what broke.
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var detail = String(scannerErr.text || "").replace(/\s+/g, " ").trim()
        console.warn("system-updates: scanner exited with code " + exitCode
          + (detail !== "" ? ": " + detail : ""))
      }
    }
  }

  function pathFromUrl(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0)
      return decodeURIComponent(value.substring(7))
    return value
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: root.autoRefresh
    repeat: true
    onTriggered: root.refresh()
  }

  // First live scan waits until after boot: the disk cache renders
  // instantly, so shell startup pays no scanner cost. Opening the panel
  // (middle-click, R key, or left-click) still scans immediately.
  Timer {
    id: bootTimer
    interval: 90000
    running: root.autoRefresh
    repeat: false
    onTriggered: root.refresh()
  }

  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.lastCacheText = String(text() || "")
      root.updateRepos(text())
    }
  }

  Timer {
    id: fastPollTimer
    interval: 10000
    running: false
    repeat: true
    onTriggered: {
      root.refresh()
      root.fastPollCount++
      // Back off while the updater terminal stays open: early polls catch a
      // quick update, later ones just keep the numbers from going stale.
      if (root.fastPollCount >= 5) fastPollTimer.interval = 30000
      if (root.fastPollCount >= root.maxFastPolls) root.stopFastPoll()
    }
  }

  Timer {
    id: lastCheckedTimer
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.updateLastChecked()
  }

  Process {
    id: pingProc
    stdout: SplitParser {
      onRead: function(line) {
        var parts = line.trim().split(" ")
        if (parts.length === 2 && (parts[1] === "online" || parts[1] === "offline"))
          root.setRepoStatus(parts[0], parts[1])
      }
    }
  }

  // Watch the Hyprland event socket: capture the address of the first window
  // opened right after an update is launched, then rescan once when it closes.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "openwindow") {
        if (root.awaitingUpdateWindow) {
          root.watchedWindowAddress = String(event.data || "").split(",")[0]
          root.awaitingUpdateWindow = false
          watchCaptureTimeout.stop()
        }
      } else if (event.name === "closewindow") {
        if (root.watchedWindowAddress !== "" && String(event.data || "") === root.watchedWindowAddress)
          root.stopFastPoll()
      }
    }
  }

  Timer {
    id: watchCaptureTimeout
    interval: 15000
    onTriggered: root.awaitingUpdateWindow = false
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barIcon
    // WidgetButton paints at body size, which left the package glyph a hair
    // smaller than the optically sized icons on either side of it. The bar's
    // own icon tokens put it back on its neighbours' rhythm.
    fontSize: Style.bar.iconFont
    fixedWidth: root.bar && root.bar.vertical ? -1 : Style.bar.iconSlot
    fixedHeight: root.bar && root.bar.vertical ? Style.bar.iconSlot : -1
    tooltipText: {
      var parts = []
      for (var i = 0; i < root.installedRepos.length; i++) {
        var r = root.installedRepos[i]
        if (r.error === true) parts.push(strings.t("updates.checkFailedFor").arg(Model.text(r.name, 80)))
        else if (r.count > 0) parts.push(root.fmtInt(r.count) + " " + Model.text(r.name, 80))
      }
      if (parts.length === 0) return ""
      return parts.join(", ")
    }
    onPressed: function(b) { root.triggerPress(b) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.settingsMode && settingsContentLayout.editorActive
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "s" || t === "S") root.settingsMode ? root.saveSettings() : root.openSettings()
        if (t === "r" || t === "R") root.refresh()
      }

      ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // Unified frosted-glass panel header (sibling of ai-usage v1.15.0 and
        // notification-center): glass icon tile, crisp title + tabular caps
        // metadata, and soft glass action controls.
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(42)

          RowLayout {
            anchors.fill: parent
            spacing: Style.space(10)

            Rectangle {
              Layout.preferredWidth: Style.space(36)
              Layout.preferredHeight: Style.space(36)
              Layout.alignment: Qt.AlignVCenter
              radius: root.cardRadius
              color: root.hasCheckError && !root.settingsMode
                ? root.alpha(root.urgent, 0.14)
                : (root.total > 0 && !root.settingsMode ? root.alpha(root.accent, 0.14) : root.alpha(root.fg, 0.06))
              border.width: 1
              border.color: root.hasCheckError && !root.settingsMode
                ? root.alpha(root.urgent, 0.34)
                : (root.total > 0 && !root.settingsMode ? root.alpha(root.accent, 0.32) : root.alpha(root.fg, 0.11))

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Math.max(4, Math.round(root.cardRadius * 0.5))
                anchors.rightMargin: Math.max(4, Math.round(root.cardRadius * 0.5))
                anchors.topMargin: 1
                height: 1
                color: root.alpha(root.fg, 0.14)
              }

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: root.settingsMode ? "󰒓" : root.barIcon
                color: root.hasCheckError && !root.settingsMode
                  ? root.urgent
                  : (root.total > 0 && !root.settingsMode ? root.accent : root.fg)
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
                textFormat: Text.PlainText
                text: root.settingsMode ? strings.t("updates.settingsTitle") : strings.t("updates.title")
                color: root.fg
                font.family: root.uiFont
                font.pixelSize: Style.font.title
                font.bold: true
                font.letterSpacing: Style.spaceReal(-0.2)
                elide: Text.ElideRight
              }

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: root.heroMeta.toUpperCase()
                color: root.dim
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                font.weight: Font.DemiBold
                font.letterSpacing: Style.spaceReal(0.75)
                font.features: ({ "tnum": 1 })
                elide: Text.ElideRight
              }
            }

            RowLayout {
              Layout.alignment: Qt.AlignVCenter
              spacing: Style.space(6)

              Rectangle {
                id: savePill

                readonly property bool hot: saveMouse.containsMouse || activeFocus

                visible: root.settingsMode
                Layout.preferredWidth: saveLabel.implicitWidth + Style.space(20)
                Layout.preferredHeight: Style.space(30)
                Layout.alignment: Qt.AlignVCenter
                radius: Math.max(6, root.cardRadius - 2)
                color: saveMouse.pressed ? root.alpha(root.accent, 0.34) : (hot ? root.alpha(root.accent, 0.24) : root.alpha(root.accent, 0.15))
                border.width: 1
                border.color: hot ? root.alpha(root.accent, 0.56) : root.alpha(root.accent, 0.36)
                activeFocusOnTab: true
                Keys.onReturnPressed: root.saveSettings()
                Keys.onEnterPressed: root.saveSettings()
                Keys.onSpacePressed: root.saveSettings()

                Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.leftMargin: Math.max(4, Math.round(savePill.radius * 0.5))
                  anchors.rightMargin: Math.max(4, Math.round(savePill.radius * 0.5))
                  anchors.topMargin: 1
                  height: 1
                  color: root.alpha(root.fg, 0.16)
                }

                Text {
                  id: saveLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: strings.t("updates.save")
                  color: root.fg
                  font.family: root.uiFont
                  font.pixelSize: Style.font.bodySmall
                  font.weight: Font.DemiBold
                }

                MouseArea {
                  id: saveMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.saveSettings()
                }

                PanelToolTip {
                  visible: saveMouse.containsMouse
                  text: strings.t("updates.saveSettings")
                  fontFamily: root.uiFont
                }
              }

              Rectangle {
                id: refreshButton

                readonly property bool hot: (refreshMouse.containsMouse || activeFocus) && !scannerProc.running

                visible: !root.settingsMode
                Layout.preferredWidth: Style.space(30)
                Layout.preferredHeight: Style.space(30)
                Layout.alignment: Qt.AlignVCenter
                radius: Math.max(6, root.cardRadius - 2)
                opacity: scannerProc.running ? 0.65 : 1.0
                color: hot ? root.alpha(root.fg, 0.11) : root.alpha(root.fg, 0.055)
                border.width: 1
                border.color: hot ? root.alpha(root.fg, 0.22) : root.alpha(root.fg, 0.11)
                activeFocusOnTab: true
                Keys.onReturnPressed: root.refresh()
                Keys.onEnterPressed: root.refresh()
                Keys.onSpacePressed: root.refresh()

                Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "󰑐"
                  color: refreshButton.hot ? root.fg : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                  transformOrigin: Item.Center

                  RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: Style.duration(900)
                    loops: Animation.Infinite
                    running: scannerProc.running && !Style.reduceMotion
                  }
                }

                MouseArea {
                  id: refreshMouse
                  anchors.fill: parent
                  enabled: !scannerProc.running
                  hoverEnabled: true
                  cursorShape: scannerProc.running ? Qt.ArrowCursor : Qt.PointingHandCursor
                  onClicked: root.refresh()
                }

                PanelToolTip {
                  visible: refreshMouse.containsMouse
                  text: strings.t("updates.refreshStats")
                  fontFamily: root.uiFont
                }
              }

              Rectangle {
                id: settingsButton

                readonly property bool hot: settingsMouse.containsMouse || activeFocus

                Layout.preferredWidth: Style.space(30)
                Layout.preferredHeight: Style.space(30)
                Layout.alignment: Qt.AlignVCenter
                radius: Math.max(6, root.cardRadius - 2)
                color: root.settingsMode ? root.alpha(root.accent, 0.16) : (hot ? root.alpha(root.fg, 0.11) : root.alpha(root.fg, 0.055))
                border.width: 1
                border.color: root.settingsMode ? root.alpha(root.accent, 0.42) : (hot ? root.alpha(root.fg, 0.22) : root.alpha(root.fg, 0.11))
                activeFocusOnTab: true
                Keys.onReturnPressed: root.settingsMode ? root.showMain() : root.openSettings()
                Keys.onEnterPressed: root.settingsMode ? root.showMain() : root.openSettings()
                Keys.onSpacePressed: root.settingsMode ? root.showMain() : root.openSettings()

                Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: root.settingsMode ? "󰁍" : "󰒓"
                  color: root.settingsMode ? root.accent : (settingsButton.hot ? root.fg : root.dim)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                }

                MouseArea {
                  id: settingsMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.settingsMode ? root.showMain() : root.openSettings()
                }

                PanelToolTip {
                  visible: settingsMouse.containsMouse
                  text: root.settingsMode ? strings.t("updates.backToUpdates") : strings.t("updates.settingsTitle")
                  fontFamily: root.uiFont
                }
              }
            }
          }
        }

        // Recessed frosted-glass segmented filter bar (All sources | Available),
        // matching ai-usage v1.15.0 and notification-center.
        Rectangle {
          id: filterTrack

          visible: !root.settingsMode && root.installedRepos.length > 0
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(34)
          radius: Math.max(8, root.pillRadius - 2)
          color: root.alpha(root.fg, 0.055)
          border.width: 1
          border.color: root.alpha(root.fg, 0.11)

          Row {
            anchors.fill: parent
            anchors.margins: Style.space(3)
            spacing: Style.space(3)

            Repeater {
              model: root.filterTabs

              delegate: Rectangle {
                id: filterSeg

                required property var modelData
                required property int index

                readonly property bool activeSeg: root.filterMode === filterSeg.modelData.id
                readonly property bool hot: filterSegMouse.containsMouse || activeFocus

                width: (filterTrack.width - Style.space(9)) / 2
                height: parent.height
                radius: Math.max(6, root.pillRadius - 4)
                color: activeSeg ? root.alpha(root.fg, 0.14) : (hot ? root.alpha(root.fg, 0.07) : "transparent")
                border.width: activeSeg ? 1 : 0
                border.color: activeSeg ? root.alpha(root.fg, 0.18) : "transparent"
                activeFocusOnTab: true
                Keys.onReturnPressed: root.selectFilter(filterSeg.modelData.id)
                Keys.onEnterPressed: root.selectFilter(filterSeg.modelData.id)
                Keys.onSpacePressed: root.selectFilter(filterSeg.modelData.id)

                Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

                Rectangle {
                  visible: filterSeg.activeSeg
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.leftMargin: Math.max(4, Math.round(filterSeg.radius * 0.6))
                  anchors.rightMargin: Math.max(4, Math.round(filterSeg.radius * 0.6))
                  anchors.topMargin: 1
                  height: 1
                  color: root.alpha(root.fg, 0.16)
                }

                Row {
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  Rectangle {
                    visible: filterSeg.modelData.accented
                    width: Style.space(5)
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.accent
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: filterSeg.modelData.label
                    anchors.verticalCenter: parent.verticalCenter
                    color: filterSeg.activeSeg ? root.fg : root.dim
                    font.family: root.uiFont
                    font.pixelSize: Style.font.bodySmall
                    font.weight: filterSeg.activeSeg ? Font.DemiBold : Font.Medium
                  }

                  Rectangle {
                    width: filterCountText.implicitWidth + Style.space(10)
                    height: filterCountText.implicitHeight + Style.space(2)
                    radius: height / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: filterSeg.modelData.accented
                      ? root.alpha(root.accent, 0.20)
                      : (filterSeg.activeSeg ? root.alpha(root.fg, 0.12) : root.alpha(root.fg, 0.06))

                    Text {
                      id: filterCountText
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: root.fmtInt(filterSeg.modelData.count)
                      color: filterSeg.modelData.accented ? root.fg : (filterSeg.activeSeg ? root.fg : root.dim)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.weight: Font.DemiBold
                      font.features: ({ "tnum": 1 })
                    }
                  }
                }

                MouseArea {
                  id: filterSegMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectFilter(filterSeg.modelData.id)
                }
              }
            }
          }
        }

        PanelSeparator {
          visible: root.settingsMode || root.installedRepos.length === 0
          Layout.fillWidth: true
          foreground: root.fg
          strength: 0.09
        }

        // Neutral frosted-glass error notice with a 2px left alarm rail
        // (matching ai-usage v1.15.0's status banner).
        Rectangle {
          visible: !root.settingsMode && root.hasCheckError
          Layout.fillWidth: true
          Layout.preferredHeight: errorBannerText.implicitHeight + Style.space(18)
          radius: root.cardRadius
          color: root.alpha(root.fg, 0.05)
          border.width: 1
          border.color: root.alpha(root.urgent, 0.30)

          Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: Math.min(root.cardRadius, Style.space(8))
            anchors.bottomMargin: Math.min(root.cardRadius, Style.space(8))
            width: Math.max(2, Style.space(2))
            radius: width / 2
            color: root.urgent
          }

          Text {
            id: errorBannerText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            textFormat: Text.PlainText
            text: strings.t("updates.checkFailedBanner").arg(root.failedSourceNames)
            color: root.fg
            font.family: root.uiFont
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
          }
        }

        // Empty / loading / all-current state.
        Item {
          visible: !root.settingsMode && root.visibleRepos.length === 0
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(156)

          Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - Style.space(24), Style.space(320))
            spacing: Style.space(8)

            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(46)
              height: Style.space(46)
              radius: width / 2
              color: root.alpha(root.fg, 0.055)
              border.width: 1
              border.color: root.alpha(root.fg, 0.11)

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: root.installedRepos.length === 0 ? "󰑐" : "󰄬"
                color: root.installedRepos.length === 0 ? root.dim : root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: root.installedRepos.length === 0 ? strings.t("updates.checkingSources") : strings.t("updates.allUpToDateTitle")
              color: root.fg
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
              textFormat: Text.PlainText
              text: root.installedRepos.length === 0 ? strings.t("updates.checking") : strings.t("updates.allUpToDateBody")
              color: root.dim
              font.family: root.uiFont
              font.pixelSize: Style.font.bodySmall
              lineHeight: 1.3
            }

            Rectangle {
              visible: root.filterMode === "available" && root.installedRepos.length > 0
              anchors.horizontalCenter: parent.horizontalCenter
              width: showAllLabel.implicitWidth + Style.space(20)
              height: showAllLabel.implicitHeight + Style.space(10)
              radius: Math.max(6, root.cardRadius - 2)
              color: showAllMouse.containsMouse ? root.alpha(root.fg, 0.12) : root.alpha(root.fg, 0.06)
              border.width: 1
              border.color: showAllMouse.containsMouse ? root.alpha(root.fg, 0.24) : root.alpha(root.fg, 0.14)

              Behavior on color { ColorAnimation { duration: Style.duration(120) } }
              Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

              Text {
                id: showAllLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: strings.t("updates.showAllSources")
                color: root.fg
                font.family: root.uiFont
                font.pixelSize: Style.font.bodySmall
                font.weight: Font.DemiBold
              }

              MouseArea {
                id: showAllMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectFilter("all")
              }
            }
          }
        }

        // Scrollable stack of frosted-glass source cards.
        Flickable {
          id: sourcesFlick

          visible: !root.settingsMode && root.visibleRepos.length > 0
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(sourcesColumn.implicitHeight, Style.space(490))
          contentWidth: width
          contentHeight: sourcesColumn.implicitHeight
          clip: true
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar {
            policy: sourcesFlick.contentHeight > sourcesFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
          }

          ColumnLayout {
            id: sourcesColumn
            width: sourcesFlick.width
            spacing: Style.space(8)

            Repeater {
              model: root.opened ? root.visibleRepos : []

              delegate: Rectangle {
                id: repoCard

                required property var modelData

                readonly property var packages: repoCard.modelData.packages || []
                readonly property bool expandable: packages.length > 0
                readonly property bool expanded: root.isRepoExpanded(repoCard.modelData.id)
                readonly property int updateCount: root.nonNegativeCount(repoCard.modelData.count)
                readonly property int pkgCount: root.nonNegativeCount(repoCard.modelData.pkgCount)
                readonly property bool hasUpdates: updateCount > 0 && repoCard.modelData.error !== true
                readonly property bool isError: repoCard.modelData.error === true
                readonly property string netStatus: String(root.repoStatus[repoCard.modelData.id] || "")
                readonly property bool canUpdate: hasUpdates && root.updateCommandFor(repoCard.modelData) !== ""
                readonly property bool headerHot: headerMouse.containsMouse && expandable

                Layout.fillWidth: true
                Layout.preferredHeight: repoColumn.implicitHeight + Style.space(16)
                radius: root.cardRadius
                color: headerHot ? root.alpha(root.fg, 0.085) : (expanded ? root.alpha(root.fg, 0.06) : root.alpha(root.fg, 0.045))
                border.width: 1
                border.color: isError
                  ? root.alpha(root.urgent, 0.34)
                  : (headerHot ? root.alpha(root.fg, 0.20) : (expanded ? root.alpha(root.fg, 0.16) : root.alpha(root.fg, 0.10)))
                clip: true

                Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

                // Whisper-quiet 1px top specular rim on frosted source cards.
                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.leftMargin: Math.max(4, Math.round(root.cardRadius * 0.5))
                  anchors.rightMargin: Math.max(4, Math.round(root.cardRadius * 0.5))
                  anchors.topMargin: 1
                  height: 1
                  z: 2
                  gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.25; color: root.alpha(root.fg, repoCard.headerHot ? 0.18 : 0.13) }
                    GradientStop { position: 0.75; color: root.alpha(root.fg, repoCard.headerHot ? 0.18 : 0.13) }
                    GradientStop { position: 1.0; color: "transparent" }
                  }
                }

                // Subtle vertical left edge accent rail inset inside the card
                // border on sources with pending updates or check failures.
                Rectangle {
                  visible: repoCard.isError || repoCard.hasUpdates
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(5)
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.topMargin: Style.space(10)
                  anchors.bottomMargin: Style.space(10)
                  width: Math.max(2, Style.space(3))
                  radius: width / 2
                  color: repoCard.isError ? root.urgent : root.accent
                  opacity: repoCard.isError ? 0.95 : 0.85
                }

                ColumnLayout {
                  id: repoColumn
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(8)
                  anchors.leftMargin: Style.space(14)
                  anchors.rightMargin: Style.space(12)
                  spacing: Style.space(6)

                  Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(Style.space(36), repoRow.implicitHeight)

                    MouseArea {
                      id: headerMouse
                      anchors.fill: parent
                      enabled: repoCard.expandable
                      hoverEnabled: true
                      cursorShape: repoCard.expandable ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: root.toggleRepo(repoCard.modelData.id)
                    }

                    RowLayout {
                      id: repoRow
                      anchors.fill: parent
                      spacing: Style.space(10)

                      Rectangle {
                        Layout.preferredWidth: Style.space(32)
                        Layout.preferredHeight: Style.space(32)
                        Layout.alignment: Qt.AlignVCenter
                        radius: Math.max(6, root.cardRadius - 2)
                        color: root.alpha(root.fg, 0.06)
                        border.width: 1
                        border.color: root.alpha(root.fg, 0.10)

                        Image {
                          anchors.centerIn: parent
                          width: Style.space(18)
                          height: Style.space(18)
                          source: root.iconSource(repoCard.modelData.id)
                          sourceSize.width: Style.space(18)
                          sourceSize.height: Style.space(18)
                          fillMode: Image.PreserveAspectFit
                          smooth: true
                        }
                      }

                      ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Style.space(3)

                        RowLayout {
                          Layout.fillWidth: true
                          spacing: Style.space(8)

                          Text {
                            textFormat: Text.PlainText
                            text: repoCard.modelData.name
                            color: root.fg
                            font.family: root.uiFont
                            font.pixelSize: Style.font.subtitle
                            font.weight: Font.DemiBold
                            font.letterSpacing: Style.spaceReal(-0.1)
                            elide: Text.ElideRight
                            Layout.maximumWidth: Style.space(160)
                          }

                          Rectangle {
                            Layout.preferredWidth: badgeText.implicitWidth + Style.space(14)
                            Layout.preferredHeight: badgeText.implicitHeight + Style.space(4)
                            Layout.alignment: Qt.AlignVCenter
                            radius: height / 2
                            color: repoCard.isError
                              ? root.alpha(root.urgent, 0.16)
                              : (repoCard.hasUpdates ? root.alpha(root.accent, 0.16) : root.alpha(root.fg, 0.045))
                            border.width: 1
                            border.color: repoCard.isError
                              ? root.alpha(root.urgent, 0.38)
                              : (repoCard.hasUpdates ? root.alpha(root.accent, 0.36) : root.alpha(root.fg, 0.08))

                            Text {
                              id: badgeText
                              anchors.centerIn: parent
                              textFormat: Text.PlainText
                              text: root.repoBadgeText(repoCard.modelData)
                              color: repoCard.isError ? root.urgent : (repoCard.hasUpdates ? root.fg : root.dim)
                              font.family: root.uiFont
                              font.pixelSize: Style.font.caption
                              font.weight: repoCard.isError || repoCard.hasUpdates ? Font.DemiBold : Font.Medium
                              font.features: ({ "tnum": 1 })
                            }
                          }

                          Item { Layout.fillWidth: true }
                        }

                        Row {
                          spacing: Style.space(6)

                          Text {
                            visible: repoCard.pkgCount > 0
                            textFormat: Text.PlainText
                            text: strings.t("updates.pkgs").arg(root.fmtInt(repoCard.pkgCount))
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.features: ({ "tnum": 1 })
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          Text {
                            visible: repoCard.pkgCount > 0 && (repoCard.netStatus === "online" || repoCard.netStatus === "offline" || repoCard.netStatus === "checking")
                            textFormat: Text.PlainText
                            text: "·"
                            color: root.alpha(root.fg, 0.32)
                            font.family: root.uiFont
                            font.pixelSize: Style.font.caption
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          Row {
                            visible: repoCard.netStatus === "online" || repoCard.netStatus === "offline" || repoCard.netStatus === "checking"
                            spacing: Style.space(4)
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                              visible: repoCard.netStatus === "online" || repoCard.netStatus === "offline"
                              width: Style.space(5)
                              height: width
                              radius: width / 2
                              anchors.verticalCenter: parent.verticalCenter
                              color: repoCard.netStatus === "offline"
                                ? (repoCard.isError ? root.dim : root.urgent)
                                : root.alpha(root.fg, 0.45)
                            }

                            Text {
                              textFormat: Text.PlainText
                              text: repoCard.netStatus === "checking"
                                ? strings.t("updates.checking")
                                : (repoCard.netStatus === "online" ? strings.t("updates.online") : strings.t("updates.offline"))
                              color: repoCard.netStatus === "offline" && !repoCard.isError ? root.urgent : root.dim
                              font.family: root.uiFont
                              font.pixelSize: Style.font.caption
                              font.italic: repoCard.netStatus === "checking"
                              anchors.verticalCenter: parent.verticalCenter
                            }
                          }
                        }
                      }

                      Text {
                        textFormat: Text.PlainText
                        visible: root.pendingRepo === repoCard.modelData.id && root.fastPollActive
                        text: "\u2026"
                        color: root.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                      }

                      Rectangle {
                        id: updatePill

                        readonly property bool hot: updateMouse.containsMouse || activeFocus

                        visible: repoCard.canUpdate
                        Layout.preferredWidth: updateLabel.implicitWidth + Style.space(20)
                        Layout.preferredHeight: Style.space(26)
                        Layout.alignment: Qt.AlignVCenter
                        radius: Math.max(6, root.cardRadius - 2)
                        color: updateMouse.pressed ? root.alpha(root.accent, 0.36) : (hot ? root.alpha(root.accent, 0.26) : root.alpha(root.accent, 0.16))
                        border.width: 1
                        border.color: hot ? root.alpha(root.accent, 0.58) : root.alpha(root.accent, 0.38)
                        activeFocusOnTab: true
                        Keys.onReturnPressed: { root.updateRepo(repoCard.modelData.id); root.close() }
                        Keys.onEnterPressed: { root.updateRepo(repoCard.modelData.id); root.close() }
                        Keys.onSpacePressed: { root.updateRepo(repoCard.modelData.id); root.close() }

                        Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                        Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

                        Rectangle {
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.leftMargin: Math.max(4, Math.round(updatePill.radius * 0.5))
                          anchors.rightMargin: Math.max(4, Math.round(updatePill.radius * 0.5))
                          anchors.topMargin: 1
                          height: 1
                          color: root.alpha(root.fg, 0.16)
                        }

                        Text {
                          id: updateLabel
                          anchors.centerIn: parent
                          textFormat: Text.PlainText
                          text: strings.t("updates.update")
                          color: root.fg
                          font.family: root.uiFont
                          font.pixelSize: Style.font.bodySmall
                          font.weight: Font.DemiBold
                        }

                        MouseArea {
                          id: updateMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: { root.updateRepo(repoCard.modelData.id); root.close() }
                        }
                      }

                      Item {
                        visible: repoCard.expandable
                        Layout.preferredWidth: Style.space(20)
                        Layout.preferredHeight: Style.space(20)
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                          anchors.centerIn: parent
                          textFormat: Text.PlainText
                          text: "\uF054"
                          color: repoCard.headerHot ? root.fg : root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          rotation: repoCard.expanded ? 90 : 0

                          Behavior on rotation {
                            NumberAnimation {
                              duration: Style.duration(140)
                              easing.type: Easing.OutCubic
                            }
                          }
                        }
                      }
                    }
                  }

                  PanelSeparator {
                    visible: repoCard.expanded
                    Layout.fillWidth: true
                    foreground: root.fg
                    strength: 0.08
                  }

                  Flickable {
                    id: packageList

                    visible: repoCard.expanded
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(packagesColumn.implicitHeight, Style.space(220))
                    contentWidth: width
                    contentHeight: packagesColumn.implicitHeight
                    clip: true
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                      policy: packageList.contentHeight > packageList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    }

                    ColumnLayout {
                      id: packagesColumn
                      width: packageList.width
                      spacing: Style.space(2)

                      Repeater {
                        model: repoCard.packages

                        delegate: Rectangle {
                          id: pkgRow

                          required property var modelData
                          readonly property string title: pkgRow.modelData.title || ""

                          Layout.fillWidth: true
                          Layout.preferredHeight: pkgRowLayout.implicitHeight + Style.space(8)
                          radius: Math.max(5, root.cardRadius - 4)
                          color: pkgHover.hovered ? root.alpha(root.fg, 0.06) : "transparent"

                          Behavior on color { ColorAnimation { duration: Style.duration(90) } }

                          HoverHandler {
                            id: pkgHover
                          }

                          RowLayout {
                            id: pkgRowLayout
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Style.space(6)
                            anchors.rightMargin: Style.space(6)
                            spacing: Style.space(8)

                            Text {
                              Layout.fillWidth: true
                              Layout.maximumWidth: pkgRow.title !== "" ? Math.ceil(implicitWidth) : Infinity
                              textFormat: Text.PlainText
                              text: pkgRow.title !== "" ? pkgRow.title : pkgRow.modelData.name
                              color: root.fg
                              font.family: pkgRow.title !== "" ? root.uiFont : root.fontFamily
                              font.pixelSize: Style.font.bodySmall
                              font.weight: Font.Medium
                              elide: Text.ElideRight
                              Layout.alignment: Qt.AlignVCenter
                            }

                            Text {
                              visible: pkgRow.title !== ""
                              Layout.fillWidth: true
                              Layout.preferredWidth: 0
                              textFormat: Text.PlainText
                              text: pkgRow.modelData.name
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              elide: Text.ElideRight
                              Layout.alignment: Qt.AlignVCenter
                            }

                            Row {
                              visible: (pkgRow.modelData.from || "") !== "" || (pkgRow.modelData.to || "") !== ""
                              spacing: Style.space(4)
                              Layout.alignment: Qt.AlignVCenter

                              Text {
                                visible: (pkgRow.modelData.from || "") !== ""
                                textFormat: Text.PlainText
                                text: pkgRow.modelData.from || ""
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.features: ({ "tnum": 1 })
                              }

                              Text {
                                visible: (pkgRow.modelData.from || "") !== "" && (pkgRow.modelData.to || "") !== ""
                                textFormat: Text.PlainText
                                text: "\u2192"
                                color: root.alpha(root.fg, 0.36)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                              }

                              Text {
                                visible: (pkgRow.modelData.to || "") !== ""
                                textFormat: Text.PlainText
                                text: pkgRow.modelData.to || ""
                                color: root.alpha(root.fg, 0.88)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.features: ({ "tnum": 1 })
                              }
                            }

                            Rectangle {
                              visible: (pkgRow.modelData.url || "") !== ""
                              Layout.preferredWidth: linkText.implicitWidth + Style.space(12)
                              Layout.preferredHeight: linkText.implicitHeight + Style.space(4)
                              Layout.alignment: Qt.AlignVCenter
                              radius: height / 2
                              color: linkMouse.containsMouse ? root.alpha(root.fg, 0.12) : root.alpha(root.fg, 0.05)
                              border.width: 1
                              border.color: linkMouse.containsMouse ? root.alpha(root.fg, 0.24) : root.alpha(root.fg, 0.11)

                              Behavior on color { ColorAnimation { duration: Style.duration(100) } }
                              Behavior on border.color { ColorAnimation { duration: Style.duration(100) } }

                              Text {
                                id: linkText
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: pkgRow.modelData.label || strings.t("updates.repo")
                                color: linkMouse.containsMouse ? root.fg : root.dim
                                font.family: root.uiFont
                                font.pixelSize: Style.font.caption
                                font.weight: Font.Medium
                              }

                              MouseArea {
                                id: linkMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openUrl(pkgRow.modelData.url)
                              }

                              PanelToolTip {
                                visible: linkMouse.containsMouse
                                text: pkgRow.modelData.url || ""
                                fontFamily: root.fontFamily
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        ColumnLayout {
          id: settingsContentLayout
          visible: root.settingsMode
          Layout.fillWidth: true
          spacing: Style.space(10)

          readonly property bool editorActive: refreshIntervalField.field.activeFocus

          SectionCard {
            title: strings.t("updates.refreshSection")

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(10)

              NumberField {
                id: refreshIntervalField
                label: strings.t("updates.refreshInterval")
                value: Number(root.draftValue("refreshIntervalSec", 1800))
                from: 300
                to: 7200
                stepSize: 300
                fieldWidth: parent.width
                foreground: root.fg
                accent: Commons.Color.accent
                fontFamily: root.uiFont
                onModified: function(value) { root.setDraftValue("refreshIntervalSec", value) }
              }

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: strings.t("updates.refreshHelp")
                color: root.dim
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                lineHeight: 1.3
                wrapMode: Text.WordWrap
              }

              Toggle {
                Layout.fillWidth: true
                label: strings.t("updates.autoChecks")
                description: checked ? strings.t("updates.autoChecksOn") : strings.t("updates.autoChecksOff")
                checked: root.draftValue("autoRefresh", true) === true
                foreground: root.fg
                accent: Commons.Color.accent
                fontFamily: root.uiFont
                onClicked: root.setDraftValue("autoRefresh", !checked)
              }
            }
          }

          SectionCard {
            title: strings.t("updates.visibility")

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)

              Toggle {
                Layout.fillWidth: true
                label: strings.t("updates.alwaysShow")
                description: checked ? strings.t("updates.alwaysShowOn") : strings.t("updates.alwaysShowOff")
                checked: root.draftValue("alwaysShow", true) === true
                foreground: root.fg
                accent: Commons.Color.accent
                fontFamily: root.uiFont
                onClicked: root.setDraftValue("alwaysShow", !checked)
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.settingsStatusText !== ""
            Layout.fillWidth: true
            text: root.settingsStatusText
            color: root.accent
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: strings.t("updates.keysHint")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }

        ColumnLayout {
          visible: !root.settingsMode && root.installedRepos.length > 0
          Layout.fillWidth: true
          spacing: Style.space(8)

          PanelSeparator {
            Layout.fillWidth: true
            foreground: root.fg
            strength: 0.08
          }

          Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(18)

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Rectangle {
                width: Style.space(6)
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.hasCheckError ? root.urgent : (root.total > 0 ? root.accent : root.alpha(root.fg, 0.35))
              }

              Text {
                textFormat: Text.PlainText
                text: root.lastCheckedText !== "" ? root.lastCheckedText : (root.total > 0 ? root.heroMeta : strings.t("updates.upToDateShort"))
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.features: ({ "tnum": 1 })
              }
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: strings.t("updates.footerHint")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }

  component SectionCard: BorderSurface {
    id: section
    property string title: ""
    default property alias content: body.data

    Layout.fillWidth: true
    color: root.alpha(root.fg, 0.045)
    borderSpec: Border.flat(root.alpha(root.fg, 0.11), 1)
    radius: root.cardRadius
    padding: Style.space(14)
    implicitHeight: body.implicitHeight + contentTopInset + contentBottomInset

    Rectangle {
      x: section.borderLeft + Math.round(root.cardRadius * 0.5)
      y: section.borderTop
      width: Math.max(0, section.width - section.borderLeft - section.borderRight - root.cardRadius)
      height: 1
      z: 2
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.25; color: root.alpha(root.fg, 0.13) }
        GradientStop { position: 0.75; color: root.alpha(root.fg, 0.13) }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: section.contentTopInset
      anchors.rightMargin: section.contentRightInset
      anchors.bottomMargin: section.contentBottomInset
      anchors.leftMargin: section.contentLeftInset
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        visible: section.title !== ""
        Layout.fillWidth: true
        text: section.title.toUpperCase()
        color: root.dim
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.weight: Font.DemiBold
        font.letterSpacing: Style.spaceReal(0.85)
      }
    }
  }
}
