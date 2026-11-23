import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Native Omarchy Quattro popup. BarWidget.qml owns the bar slot and injects
// its button as this panel's anchor; collection stays in the Rust binary.
Panel {
  id: root
  moduleName: "akshaybapat.ai-usage"
  manageIpc: false
  readonly property string uiRevision: "1.15.2"

  function appearance() {
    return { revision: uiRevision, opened: opened,
      selected: entry ? entry.id : "",
      navigatorCount: providerList.count,
      navigatorWidth: providerList.width,
      navigatorContentWidth: providerList.contentWidth,
      activityOpen: activityOpen, contentHeight: panelFlick.contentHeight, viewportHeight: panelFlick.height,
      marks: Model.renderedMarks(keyCatcher) }
  }

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  // The panel's alarm ink comes from the strip, so the same alarm wears the
  // same colour in both places and is never fainter than the text around it.
  readonly property color urgent: hostWidget && hostWidget.legibleAlarm
    ? hostWidget.legibleAlarm(bar ? bar.urgent : Commons.Color.urgent, foreground,
        Commons.Color.popups.background)
    : (bar ? bar.urgent : Commons.Color.urgent)
  readonly property color warnColor: {
    var v = Model.barWarnRgb([foreground.r, foreground.g, foreground.b], [surface.r, surface.g, surface.b])
    return Qt.rgba(v[0], v[1], v[2], 1)
  }
  readonly property int pillRadius: Math.max(8, Style.cornerRadius)
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color track: Style.selectedFillFor(foreground, Commons.Color.accent)
  // 1.14: the panel's meters speak the strip's language: the same dark well
  // in a rim that stands 3:1 on the popup surface, the same flat-topped fill,
  // the same pace mark. Solved once per theme.
  readonly property color surface: Commons.Color.popups.background
  readonly property var meterInks: Model.stripInks([surface.r, surface.g, surface.b],
    [foreground.r, foreground.g, foreground.b], [urgent.r, urgent.g, urgent.b],
    [Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b])
  function inkOf(v) { return Qt.rgba(v[0], v[1], v[2], 1) }
  readonly property var dormantList: hostWidget && hostWidget.dormant ? hostWidget.dormant : []
  readonly property double readingMs: entry ? Date.parse(entry.fetched_at || "") : NaN
  readonly property string monoFont: bar ? bar.fontFamily : Style.font.family
  readonly property string uiFont: (Style.font.menuFamily && Style.font.menuFamily.length > 0 && Style.font.menuFamily !== "monospace")
    ? Style.font.menuFamily
    : "Inter Display"
  readonly property string fontFamily: monoFont
  readonly property bool isDark: (0.2126 * surface.r + 0.7152 * surface.g + 0.0722 * surface.b) < 0.5
  readonly property color specularTop: Qt.rgba(1, 1, 1, isDark ? 0.08 : 0.35)
  readonly property bool vertical: bar ? bar.vertical : false

  // Injected by BarWidget.qml. Collection lives in UsageSource so the strip
  // in the bar does not depend on this popup existing, and so this panel is a
  // view of the report rather than its owner.
  property var source: null

  property string selectedEntryId: ""
  property bool cursorActive: false
  property bool settingsOpen: false
  property bool activityOpen: false
  property string expandedActivityProvider: ""
  readonly property var activitySummary: Model.activityTotals(spend)
  readonly property var recentActivity: spendRows.filter(function(row) { return row.d30.replies > 0 })
  readonly property string accountBalance: Model.creditBalance(entry)
  readonly property var localActivity: Model.activityFor(spend, entry ? entry.id : "")

  readonly property var entries: source ? source.entries : []
  readonly property string primaryProvider: source ? source.primary : ""
  readonly property string loadError: source ? source.loadError : ""
  readonly property bool loading: source ? source.loading : true
  readonly property bool busy: source ? source.busy : false
  readonly property double nowMs: source ? source.nowMs : 0
  readonly property double lastSuccessfulMs: source ? source.lastSuccessfulMs : 0
  readonly property var spend: source ? source.spend : ({ ok: false, note: "", rows: [], total: 0 })
  readonly property var spendRows: spend && spend.rows ? spend.rows : []

  readonly property int refreshIntervalSec: Math.max(30, Math.min(3600,
    Number(setting("refreshIntervalSec", 300)) || 300))
  readonly property string configuredProvider: String(setting("provider", "") || "").trim()
  readonly property string rememberedEntryId: String(setting("lastSelectedEntryId", "") || "").trim()
  readonly property bool showPercent: Model.booleanSetting(setting("showPercent", true), true)
  readonly property bool showMeter: Model.booleanSetting(setting("showMeter", true), true)
  readonly property bool compact: Model.booleanSetting(setting("compact", false), false)
  readonly property var visibleEntries: Model.filteredEntries(entries, configuredProvider)
  readonly property int entryIndex: Model.selectedIndex(visibleEntries, selectedEntryId)
  readonly property var entry: entryIndex >= 0 ? visibleEntries[entryIndex] : null
  readonly property string entryFetchedAt: {
    if (!entry) return ""
    return String(entry.fetched_at || "")
  }
  readonly property var summary: Model.headline(entry)
  readonly property var entrySections: Model.presentationSections(entry)
  readonly property bool filterMiss: configuredProvider !== "" && entries.length > 0 && visibleEntries.length === 0
  readonly property bool alarming: Model.isAlarming(entry) || loadError !== "" || filterMiss

  function alpha(color, opacity) {
    return Qt.rgba(color.r, color.g, color.b, opacity)
  }

  function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
  }

  function syncSelection() {
    if (visibleEntries.length === 0) {
      selectedEntryId = ""
      return
    }
    for (var i = 0; i < visibleEntries.length; i++)
      if (visibleEntries[i].id === selectedEntryId) return
    selectedEntryId = Model.preferredEntryId(visibleEntries, primaryProvider, rememberedEntryId)
  }

  function restoreRememberedSelection() {
    if (visibleEntries.length === 0) return
    selectedEntryId = Model.preferredEntryId(visibleEntries, primaryProvider, rememberedEntryId)
  }

  function persistWidgetSettings(values) {
    // Quattro persists inline widget settings in shell.json and pushes them
    // live to every monitor. Keep every existing setting, including settings
    // introduced by future versions, and apply only the requested overrides.
    var entry = Model.settingsWithOverrides(root.settings, root.moduleName, values)
    if (!entry) return false

    // Apply locally first so controls remain responsive. Older compatible hosts
    // without updateEntryInline still retain the choice for this session.
    root.settings = entry
    if (hostWidget && "settings" in hostWidget) hostWidget.settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, entry)
    return true
  }

  function persistSelection(entryId) {
    if (String(entryId || "").trim() === rememberedEntryId) return
    persistWidgetSettings({ lastSelectedEntryId: entryId })
  }

  function setShowPercent(enabled) {
    var next = enabled === true
    if (next === showPercent) return
    persistWidgetSettings({ showPercent: next })
  }

  function setShowMeter(enabled) {
    var next = enabled === true
    if (next === showMeter) return
    persistWidgetSettings({ showMeter: next })
  }

  function setCompact(enabled) {
    var next = enabled === true
    if (next === compact) return
    persistWidgetSettings({ compact: next })
  }

  function selectEntry(index) {
    if (visibleEntries.length === 0) return
    var wrapped = ((index % visibleEntries.length) + visibleEntries.length) % visibleEntries.length
    selectedEntryId = visibleEntries[wrapped].id
    activityOpen = false
    persistSelection(selectedEntryId)
    if (providerList.visible) providerList.positionViewAtIndex(wrapped, ListView.Contain)
    if (panelFlick) panelFlick.contentY = 0
  }

  // Fork addition: the bar strip's click target. Clicking a provider's cell
  // opens this panel already showing that provider, so the strip and the panel
  // are one navigation instead of two — and clicking the cell that is already
  // showing closes the panel, the way every other bar item toggles.
  function showEntry(entryId) {
    var id = String(entryId || "").trim()
    if (id === "") {
      toggle()
      return
    }
    var index = Model.selectedIndex(visibleEntries, id)
    if (index >= 0) {
      if (opened && id === selectedEntryId) {
        close()
        return
      }
      selectEntry(index)
    }
    if (!opened) open()
  }

  function startRefresh() { if (source) source.refresh() }

  function refresh() { startRefresh() }

  function openSettings() {
    settingsOpen = true
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { settingsView.forceActiveFocus() })
  }

  function closeSettings() {
    settingsOpen = false
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openTerminalSettings() {
    if (hostWidget && typeof hostWidget.launchDashboard === "function")
      hostWidget.launchDashboard()
    else if (bar)
      bar.run("omarchy-launch-floating-terminal-with-presentation ai-usagebar-tui")
  }

  function openNousLogin() {
    if (bar && typeof bar.run === "function")
      bar.run("omarchy-launch-floating-terminal-with-presentation ai-usagebar auth nous login")
  }

  function openCopilotLogin() {
    if (bar && typeof bar.run === "function")
      bar.run("omarchy-launch-floating-terminal-with-presentation gh auth login --web")
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  // A provider that is closed rather than broken. Antigravity only answers
  // while its app or an agy session runs, and the engine reports that as
  // "credentials error: … no local server found" — words the owner read as a
  // login problem. Asleep is not urgent and is never a warning. Model.isAsleep
  // is true only for vendors that sleep by design, so a cloud provider's
  // failure keeps its own text and its red frame.
  readonly property bool entryNotRunning: Model.isAsleep(entry)

  // 1.14: a provider the strip leaves off as dormant (no reading for 14 days,
  // or no plan) is still listed here, with one calm line: why, and what
  // brings it back.
  function dormantReason() {
    var list = hostWidget && hostWidget.dormant ? hostWidget.dormant : []
    for (var i = 0; entry && i < list.length; i++) if (list[i].id === entry.id) return list[i].reason
    return ""
  }

  function statusMessage() {
    if (filterMiss) return "No configured entry matches ‘" + configuredProvider + "’. Clear the provider setting or use an id from ai-usagebar usage --json."
    if (dormantReason() !== "") return "Not on the bar · " + Model.friendlyDormantText(dormantReason())
    if (entry && entry.error !== "" && !entryNotRunning) return entry.error
    // A failed refresh outranks the calm sentence: it is the one place the
    // failure is shown, and it is what the red frame below means.
    if (loadError !== "") return entries.length > 0
      ? "Refresh failed; showing the previous report. " + loadError
      : loadError
    if (entryNotRunning) return Model.offlineStatus(entry, nowMs)
    // A cached reading whose login stopped working says so, with what to do
    // and the age of the numbers; it is urgent, like any login problem.
    if (entry && Model.authStatus(entry, nowMs) !== "") return Model.authStatus(entry, nowMs)
    // A dashboard that refused the check is named as such, with the age of
    // the numbers — never "authentication failed" for a login that works.
    if (entry && entry.refusal) return Model.refusalStatus(entry, nowMs)
    if (entry && entry.stale) return "Cached data · the provider could not supply a fresh response."
    return ""
  }

  function statusIsUrgent() {
    if (!filterMiss && dormantReason() !== "") return false
    return filterMiss || (entry && entry.error !== "" && !entryNotRunning) || loadError !== ""
      || (entry && Model.authStatus(entry, nowMs) !== "")
  }

  function heroMeta() {
    if (!entry) return loading ? "Loading providers" : "Usage report"
    if (entry.error !== "") return entryNotRunning ? "Not running" : "Provider unavailable"
    // planLabel, not the raw plan: OpenRouter's plan string embeds a key prefix.
    var text = Model.planLabel(entry) || "Usage and limits"
    if (Model.authStatus(entry, nowMs) !== "") text += " · needs sign-in"
    else if (entry.stale) text += entryNotRunning ? " · not running" : (entry.refusal ? " · last check refused" : " · cached")
    return Model.autoTextSafe(text)
  }

  function tooltipText() {
    if (!entry) return Model.autoTextSafe(statusMessage() || "AI usage")
    var text = Model.providerName(entry)
    if (summary.text !== "") text += " · " + Model.autoTextSafe(summary.text)
    if (entry.stale) text += entryNotRunning ? " · not running" : " · cached"
    return text
  }

  onEntriesChanged: Qt.callLater(syncSelection)
  onSourceChanged: Qt.callLater(syncSelection)
  onConfiguredProviderChanged: Qt.callLater(syncSelection)
  onRememberedEntryIdChanged: Qt.callLater(restoreRememberedSelection)
  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      // The clock lives on the source now, so opening the panel asks it for a
      // fresh tick rather than setting one behind its back.
      if (source) source.nowMs = Date.now()
      if (panelFlick) panelFlick.contentY = 0
      if (lastSuccessfulMs === 0 || Date.now() - lastSuccessfulMs >= refreshIntervalSec * 1000)
        startRefresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      settingsOpen = false
    }
  }




  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(column.implicitHeight + (updatedFooter.visible ? updatedFooter.implicitHeight + Style.space(10) : 0), Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Native form controls own Tab/Enter/Esc while settings are open.
      blocked: root.settingsOpen

      onMoveRequested: function(dx, dy) {
        if (!root.settingsOpen && dx !== 0) {
          root.cursorActive = true
          root.selectEntry(root.entryIndex + dx)
        }
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
            Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: if (!root.settingsOpen) root.refresh()
      onCloseRequested: root.settingsOpen ? root.closeSettings() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (!root.settingsOpen && (text === "r" || text === "R")) root.refresh()
        else if (!root.settingsOpen && (text === "s" || text === "S")) root.openSettings()
      }

      Flickable {
        id: panelFlick
        objectName: "usageViewport"
        anchors.fill: parent
        anchors.bottomMargin: updatedFooter.visible ? updatedFooter.implicitHeight + Style.space(10) : 0
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar {
          id: panelScrollBar
          policy: panelFlick.contentHeight > panelFlick.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
          active: true
          width: Style.space(4)
          padding: 0
          background: Item {}
          contentItem: Rectangle {
            implicitWidth: Style.space(4)
            radius: implicitWidth / 2
            color: root.alpha(root.foreground, panelScrollBar.pressed ? 0.42 : (panelScrollBar.hovered ? 0.30 : 0.20))
          }
        }

        Column {
          id: column
          width: panelFlick.width - (panelFlick.contentHeight > panelFlick.height ? Style.space(10) : 0)
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: root.settingsOpen ? "Settings"
              : (root.activityOpen ? "API activity" : (root.entry ? Model.providerName(root.entry) : "AI usage"))
            meta: root.settingsOpen ? "Display, provider & API keys"
              : root.activityOpen ? "Recorded on this laptop"
              : (root.entry && root.heroMeta().toLowerCase() === Model.providerName(root.entry).toLowerCase()
                ? "" : root.heroMeta())
            detail: ""
            foreground: root.foreground
            fontFamily: root.uiFont

            // The hero wears the same mark as the provider's cell in the bar,
            // so clicking a cell and landing here is visibly the same object
            // rather than a generic panel that happens to be about it.
            iconComponent: Component {
              Item {
                // A wordmark is twice as wide as it is tall (SpaceXAI), and a
                // square slot made it fit by halving its height — half the
                // optical weight of every other hero mark. So the slot is a
                // fixed gutter, as wide as the widest mark the set contains,
                // and every mark hangs on its left edge. Sizing the slot to
                // each mark instead cost both alignments the panel has: the
                // title slid sideways as the selection moved between a
                // wordmark and a square one, and the mark stepped off the left
                // rail the banners, section captions and meters all sit on.
                implicitWidth: Style.space(40)
                implicitHeight: Style.space(20)

                ProviderMark {
                  id: heroMark
                  role: "hero"
                  height: parent.height
                  width: Math.round(height * Model.markAspect(mark))
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !root.settingsOpen && !root.activityOpen && root.entry !== null
                  mark: root.entry ? Model.markId(root.entry.id) : ""
                  initials: Model.markInitials(root.entry)
                  color: root.foreground
                  surfaceColor: root.surface
                  fontFamily: root.monoFont
                  fontSize: Style.font.bodySmall
                }

                Text {
                  // Square glyphs, so they keep the mark's own box at the head
                  // of the gutter rather than centring in the whole slot.
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.font.display
                  horizontalAlignment: Text.AlignHCenter
                  visible: root.settingsOpen || root.activityOpen || root.entry === null
                  text: root.settingsOpen ? "󰒓" : root.activityOpen ? "󰄨" : "󰚩"
                  color: (!root.settingsOpen && !root.activityOpen && root.alarming) ? root.urgent : root.foreground
                  font.family: root.monoFont
                  font.pixelSize: Style.font.display
                }
              }
            }

            trailingControl: Component {
              Row {
                spacing: Style.space(4)

                PanelActionButton {
                  visible: !root.settingsOpen
                  radius: Math.max(7, root.pillRadius - 2)
                  iconText: "󰑐"
                  tooltipText: "Refresh usage"
                  foreground: root.foreground
                  fontFamily: root.monoFont
                  enabled: !root.busy
                  onClicked: root.refresh()
                }

                PanelActionButton {
                  radius: Math.max(7, root.pillRadius - 2)
                  iconText: root.settingsOpen ? "󰁍" : "󰒓"
                  tooltipText: root.settingsOpen ? "Back to usage" : "Settings"
                  foreground: root.foreground
                  fontFamily: root.monoFont
                  onClicked: root.settingsOpen ? root.closeSettings() : root.openSettings()
                }
              }
            }
          }

          SettingsView {
            id: settingsView
            visible: root.settingsOpen
            width: parent.width
            foreground: root.foreground
            urgent: root.urgent
            surface: root.surface
            fontFamily: root.monoFont
            monoFont: root.monoFont
            uiFont: root.uiFont
            showPercent: root.showPercent
            showMeter: root.showMeter
            compact: root.compact
            onSaved: root.startRefresh()
            onShowPercentRequested: function(enabled) { root.setShowPercent(enabled) }
            onShowMeterRequested: function(enabled) { root.setShowMeter(enabled) }
            onCompactRequested: function(enabled) { root.setCompact(enabled) }
            onFallbackRequested: root.openTerminalSettings()
            onNousLoginRequested: root.openNousLogin()
            onCopilotLoginRequested: root.openCopilotLogin()
            onCloseRequested: root.closeSettings()
          }

          ListView {
            id: providerList
            objectName: "providerNavigator"
            visible: !root.settingsOpen && !root.activityOpen && root.visibleEntries.length > 1
            width: parent.width
            height: visible ? Style.space(32) : 0
            orientation: ListView.Horizontal
            spacing: Style.space(4)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.visibleEntries
            currentIndex: root.entryIndex

            delegate: Button {
              id: providerButton
              required property var modelData
              required property int index

              height: providerList.height
              tooltipText: Model.providerName(modelData)
              implicitWidth: providerIdentity.implicitWidth + Style.space(18)
              selected: false
              hasCursor: root.cursorActive && index === root.entryIndex
              bordered: false
              background: "transparent"
              foreground: root.foreground
              fontFamily: root.uiFont
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: {
                root.cursorActive = true
                root.selectEntry(index)
              }
              onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
              Accessible.role: Accessible.Button
              Accessible.name: Model.providerName(modelData)

              readonly property bool isCurrent: index === root.entryIndex

              Rectangle {
                anchors.fill: parent
                radius: Math.max(7, root.pillRadius - 2)
                color: providerButton.isCurrent
                  ? root.alpha(root.foreground, 0.13)
                  : (providerButton.hasCursor ? root.alpha(root.foreground, 0.06) : "transparent")
                border.width: providerButton.isCurrent ? 1 : 0
                border.color: providerButton.isCurrent
                  ? root.alpha(root.foreground, 0.16)
                  : "transparent"
                Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

                GlassHighlight {
                  visible: providerButton.isCurrent
                  inset: Style.space(5)
                }
              }

              // Clean centered accent underline indicator on the active provider
              Rectangle {
                opacity: providerButton.isCurrent ? 1 : 0
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(2)
                width: Style.space(14)
                height: 2
                radius: 1
                color: Commons.Color.accent
                Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }
              }

              Row {
                id: providerIdentity
                anchors.centerIn: parent
                spacing: Style.space(6)

                ProviderMark {
                  role: "navigation"
                  width: Math.round(Style.bar.iconCanvas * Model.markAspect(mark))
                  height: Style.bar.iconCanvas
                  anchors.verticalCenter: parent.verticalCenter
                  mark: Model.markId(providerButton.modelData.id)
                  initials: Model.markInitials(providerButton.modelData)
                  color: root.foreground
                  surfaceColor: root.surface
                }
              }
            }
          }

          // Refined rounded segmented pill switcher (Account | This laptop)
          Rectangle {
            visible: !root.settingsOpen
            width: parent.width
            height: Style.space(32)
            radius: Math.max(8, root.pillRadius - 2)
            color: root.alpha(root.foreground, 0.06)
            border.width: 1
            border.color: root.alpha(root.foreground, 0.11)

            GlassHighlight { inset: Style.space(6) }

            Row {
              anchors.fill: parent
              anchors.margins: Style.space(3)
              spacing: Style.space(3)
              Repeater {
                model: ["Account", "This laptop"]
                delegate: Button {
                  id: segBtn
                  required property string modelData
                  required property int index
                  readonly property bool activeSeg: root.activityOpen === (index === 1)
                  width: (parent.width - Style.space(3)) / 2
                  height: parent.height
                  text: ""
                  objectName: index === 0 ? "accountTab" : "activityTab"
                  selected: false
                  bordered: false
                  background: "transparent"
                  foreground: root.foreground
                  fontFamily: root.uiFont
                  onClicked: { root.activityOpen = index === 1; panelFlick.contentY = 0 }

                  Rectangle {
                    anchors.fill: parent
                    radius: Math.max(6, root.pillRadius - 4)
                    color: segBtn.activeSeg
                      ? root.alpha(root.foreground, 0.14)
                      : (segBtn.hot ? root.alpha(root.foreground, 0.055) : "transparent")
                    border.width: segBtn.activeSeg ? 1 : 0
                    border.color: segBtn.activeSeg ? root.alpha(root.foreground, 0.16) : "transparent"
                    Behavior on color { ColorAnimation { duration: Style.duration(140) } }
                    Behavior on border.color { ColorAnimation { duration: Style.duration(140) } }

                    GlassHighlight {
                      visible: segBtn.activeSeg
                      inset: Style.space(5)
                    }
                  }

                  Text {
                    anchors.centerIn: parent
                    text: segBtn.modelData
                    textFormat: Text.PlainText
                    color: segBtn.activeSeg
                      ? root.foreground
                      : (segBtn.hot ? root.alpha(root.foreground, 0.85) : root.dim)
                    font.family: root.uiFont
                    font.pixelSize: Style.font.bodySmall
                    font.weight: segBtn.activeSeg ? Font.DemiBold : Font.Medium
                    font.letterSpacing: 0.1
                    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                  }
                }
              }
            }
          }

          Rectangle {
            visible: !root.settingsOpen && !root.activityOpen && root.accountBalance !== ""
            width: parent.width
            implicitHeight: balanceCol.implicitHeight + Style.space(20)
            radius: Math.max(8, root.pillRadius - 2)
            color: root.alpha(root.foreground, 0.045)
            border.width: 1
            border.color: root.alpha(root.foreground, 0.11)

            GlassHighlight { inset: Style.space(7) }

            Column {
              id: balanceCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(4)

              Text {
                text: "CREDIT REMAINING"
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                font.weight: Font.DemiBold
                font.letterSpacing: 0.85
              }
              Text {
                text: root.accountBalance
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.monoFont
                font.pixelSize: Style.font.display
                font.bold: true
                font.features: { "tnum": 1 }
              }
              Text {
                width: parent.width
                text: "Available account balance reported by " + (root.entry ? Model.providerName(root.entry) : "the provider")
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          // A neutral rounded glass surface in every case (a tinted orange plate
          // read as the brown/orange plate he rejected on the bar); a problem is
          // said by an inset pill rule in the alarm ink on the left edge and by
          // bold text.
          BorderSurface {
            readonly property string message: root.statusMessage()
            visible: !root.settingsOpen && message !== ""
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.space(20)
            color: root.alpha(root.foreground, 0.045)
            borderSpec: Border.flat(root.alpha(root.foreground, 0.14), 1)
            radius: Math.max(8, root.pillRadius - 2)

            GlassHighlight { inset: Style.space(7) }

            // Inset rounded accent pill clear of the card corners.
            Rectangle {
              visible: root.statusIsUrgent()
              anchors.left: parent.left
              anchors.leftMargin: Style.space(5)
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.topMargin: Style.space(7)
              anchors.bottomMargin: Style.space(7)
              width: Math.max(3, Style.space(3))
              radius: width / 2
              color: root.urgent
            }

            Text {
              id: statusText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: root.statusIsUrgent() ? Style.space(15) : Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: parent.message
              textFormat: Text.PlainText
              // A problem speaks in the text ink, bold, one step up in size,
              // beside the alarm rule; a merely cached reading keeps the quiet
              // caption.
              color: root.statusIsUrgent() ? root.foreground : root.dim
              font.family: root.uiFont
              font.pixelSize: root.statusIsUrgent() ? Style.font.bodySmall : Style.font.caption
              font.weight: root.statusIsUrgent() ? Font.DemiBold : Font.Normal
              wrapMode: Text.WordWrap
            }
          }

          Column {
            visible: !root.settingsOpen && root.loading && root.entries.length === 0
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "USAGE"
              foreground: root.foreground
              fontFamily: root.uiFont
              font.letterSpacing: 0.85
            }

            Text {
              width: parent.width
              text: "Collecting configured providers…"
              color: root.dim
              font.family: root.uiFont
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }
          }

          Column {
            id: usageSection
            visible: !root.settingsOpen && !root.activityOpen && root.entrySections.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator {
              width: parent.width
              foreground: root.foreground
            }

            Repeater {
              model: root.entrySections

              Column {
                required property var modelData
                width: usageSection.width

                // `visible` alone is not enough: QML evaluates the bindings of
                // hidden items too, so every row used to be handed to all three
                // components and the two that did not match read fields the row
                // does not carry. A "spacer" row has no label or value, which is
                // what produced the TypeError below on every report.
                MetricRow {
                  visible: modelData.type === "metric"
                  width: parent.width
                  row: modelData.type === "metric" ? modelData : null
                }

                DetailRow {
                  visible: modelData.type === "text"
                  width: parent.width
                  row: modelData.type === "text" ? modelData : null
                }

                BlockRow {
                  visible: modelData.type === "block"
                  width: parent.width
                  row: modelData.type === "block" ? modelData : null
                }

                Item {
                  visible: modelData.type === "spacer"
                  width: 1
                  height: Style.space(4)
                }
              }
            }
          }

          Column {
            id: spendSection
            visible: !root.settingsOpen && root.activityOpen
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "LAST 30 DAYS · ALL RECORDED PROVIDERS"
              foreground: root.foreground
              fontFamily: root.uiFont
              font.letterSpacing: 0.85
            }

            Row {
              visible: root.recentActivity.length > 0
              width: parent.width
              spacing: Style.space(8)

              Rectangle {
                width: (parent.width - parent.spacing) / 2
                implicitHeight: subtotalCol.implicitHeight + Style.space(16)
                radius: Math.max(8, root.pillRadius - 2)
                color: root.alpha(root.foreground, 0.045)
                border.width: 1
                border.color: root.alpha(root.foreground, 0.11)

                GlassHighlight { inset: Style.space(7) }

                Column {
                  id: subtotalCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(11)
                  anchors.rightMargin: Style.space(11)
                  spacing: Style.space(3)

                  Text {
                    width: parent.width
                    text: "RECORDED SUBTOTAL"
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.75
                    elide: Text.ElideRight
                  }
                  Text {
                    text: Model.recordedCost(root.activitySummary)
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.monoFont
                    font.pixelSize: Style.font.title
                    font.bold: true
                    font.features: { "tnum": 1 }
                  }
                }
              }

              Rectangle {
                width: (parent.width - parent.spacing) / 2
                implicitHeight: repliesCol.implicitHeight + Style.space(16)
                radius: Math.max(8, root.pillRadius - 2)
                color: root.alpha(root.foreground, 0.045)
                border.width: 1
                border.color: root.alpha(root.foreground, 0.11)

                GlassHighlight { inset: Style.space(7) }

                Column {
                  id: repliesCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(11)
                  anchors.rightMargin: Style.space(11)
                  spacing: Style.space(3)

                  Text {
                    width: parent.width
                    text: "RECORDED REPLIES"
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.75
                    elide: Text.ElideRight
                  }
                  Text {
                    text: String(root.activitySummary.replies)
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.monoFont
                    font.pixelSize: Style.font.title
                    font.bold: true
                    font.features: { "tnum": 1 }
                  }
                }
              }
            }

            Text {
              visible: root.activitySummary.unpriced_replies > 0
              width: parent.width
              text: root.activitySummary.unpriced_replies + (root.activitySummary.unpriced_replies === 1 ? " reply has" : " replies have") + " no recorded price. The subtotal excludes those costs."
              textFormat: Text.PlainText
              color: root.dim; font.family: root.uiFont; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap
            }
            Text {
              visible: root.activitySummary.missing_usage_replies > 0
              width: parent.width
              text: "Token totals are incomplete for " + root.activitySummary.missing_usage_replies + (root.activitySummary.missing_usage_replies === 1 ? " reply." : " replies.")
              textFormat: Text.PlainText
              color: root.dim; font.family: root.uiFont; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap
            }

            PanelSeparator { width: parent.width; foreground: root.foreground }

            Column {
              id: activityList
              visible: root.recentActivity.length > 0
              width: parent.width
              spacing: Style.space(5)

              Repeater {
                model: root.recentActivity
                delegate: Column {
                  required property var modelData
                  width: activityList.width
                  spacing: Style.space(4)
                  ProviderActivityRow { width: parent.width; row: parent.modelData }
                  Repeater {
                    model: root.expandedActivityProvider === parent.modelData.id ? parent.modelData.apps : []
                    delegate: AppActivityRow { required property var modelData; width: activityList.width - Style.space(14); x: Style.space(14); row: modelData }
                  }
                }
              }
            }

            Text {
              visible: root.recentActivity.length === 0
              width: parent.width
              text: root.busy ? "Reading app records…" : !root.spend.ok ? (root.spend.note || "Local records are unavailable.") : "The available app records contain no replies from the last 30 days."
              textFormat: Text.PlainText
              color: root.spend.ok || root.busy ? root.foreground : root.urgent
              font.family: root.uiFont; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap
            }
            Text {
              width: parent.width
              text: "OpenCode + DeepSeek Harness records. DSH prices and activity from other apps are not included. Select a provider for its app breakdown."
              textFormat: Text.PlainText
              color: root.dim; font.family: root.uiFont; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap
            }
            Repeater {
              model: root.spend.coverage || []
              delegate: Text {
                required property var modelData
                visible: modelData.status === "unavailable" || modelData.status === "partial"
                width: spendSection.width
                text: modelData.app + ": " + (modelData.status === "unavailable" ? "records unavailable" : "some records are incomplete")
                textFormat: Text.PlainText
                color: root.urgent; font.family: root.uiFont; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap
              }
            }
          }
          // 1.14 (C5): providers the strip leaves off, each with one plain
          // sentence: why it is off, and what brings it back. A click shows
          // its own page.
          Column {
            id: dormantSection
            objectName: "dormantSection"
            visible: !root.settingsOpen && !root.activityOpen && root.dormantList.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator { width: parent.width; foreground: root.foreground }

            PanelSectionHeader {
              text: "NOT ON THE BAR"
              foreground: root.foreground
              fontFamily: root.uiFont
              font.letterSpacing: 0.85
            }

            Repeater {
              model: root.dormantList
              delegate: Rectangle {
                id: dormantRow
                required property var modelData
                width: dormantSection.width
                implicitHeight: Math.max(Style.bar.iconCanvas, dormantText.implicitHeight) + Style.space(14)
                radius: Math.max(8, root.pillRadius - 2)
                color: dormantMouse.containsMouse
                  ? root.alpha(root.foreground, 0.075)
                  : root.alpha(root.foreground, 0.04)
                border.width: 1
                border.color: dormantMouse.containsMouse
                  ? root.alpha(root.foreground, 0.18)
                  : root.alpha(root.foreground, 0.10)
                Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

                GlassHighlight { inset: Style.space(7) }

                ProviderMark {
                  role: "dormant"
                  x: Style.space(10)
                  y: Style.space(8)
                  width: Math.round(Style.bar.iconCanvas * Model.markAspect(mark))
                  height: Style.bar.iconCanvas
                  mark: Model.markId(dormantRow.modelData.id)
                  initials: dormantRow.modelData.name.slice(0, 2)
                  color: root.foreground
                  surfaceColor: root.surface
                  fontFamily: root.monoFont
                }

                Column {
                  id: dormantText
                  x: Style.space(38)
                  y: Style.space(7)
                  width: parent.width - x - Style.space(10)
                  spacing: Style.space(3)
                  Text {
                    text: dormantRow.modelData.name
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.uiFont
                    font.pixelSize: Style.font.bodySmall
                    font.weight: Font.DemiBold
                  }
                  Text {
                    width: parent.width
                    text: Model.friendlyDormantText(dormantRow.modelData.reason)
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                }

                MouseArea {
                  id: dormantMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    for (var i = 0; i < root.visibleEntries.length; i++)
                      if (root.visibleEntries[i].id === dormantRow.modelData.id) root.selectEntry(i)
                    panelFlick.contentY = 0
                  }
                }
              }
            }
          }

          Text {
            visible: !root.settingsOpen && !root.activityOpen && root.entry && root.entrySections.length === 0 && root.accountBalance === "" && !root.loading && root.statusMessage() === ""
            width: parent.width
            text: root.entry && Model.baseProvider(root.entry.id) === "deepseek" ? "Balance not reported by DeepSeek." : "Quota not reported by this provider."
            color: root.dim; font.family: root.uiFont; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap
          }

          Text {
            visible: !root.settingsOpen && !root.loading && !root.entry && root.statusMessage() === ""
            width: parent.width
            topPadding: Style.space(20)
            text: "No configured provider reported usage."
            color: root.dim
            font.family: root.uiFont
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }


        }
      }
      Text {
        id: updatedFooter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: !root.settingsOpen && (root.activityOpen ? root.spend.generatedAt > 0 : root.entryFetchedAt !== "")
        text: (root.activityOpen && root.spend.generatedAt > 0
          ? Model.formatUpdated(new Date(root.spend.generatedAt).toISOString(), root.nowMs)
          : root.entryNotRunning ? Model.lastSeenLabel(root.entryFetchedAt, root.nowMs).replace(/^last/, "Last")
          : Model.formatUpdated(root.entryFetchedAt, root.nowMs)) + (root.busy ? " · refreshing…" : "")
        color: root.dim
        font.family: root.monoFont
        font.pixelSize: Style.font.caption
        font.features: { "tnum": 1 }
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }
  }

  // Whisper-quiet 1px top-edge inner specular catchlight for architectural glass surfaces.
  component GlassHighlight: Rectangle {
    property real inset: Style.space(7)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: inset
    anchors.rightMargin: inset
    anchors.topMargin: 1
    height: 1
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: "transparent" }
      GradientStop { position: 0.14; color: root.specularTop }
      GradientStop { position: 0.86; color: root.specularTop }
      GradientStop { position: 1.0; color: "transparent" }
    }
  }

  component MetricRow: Column {
    id: metricRow
    property var row: null
    // One ramp for both surfaces. The engine labels a row low/mid/high/critical
    // and steps at 75; the strip judges the same number at 70 and calls it warn.
    // Two vocabularies meant a cell could be lit in the bar while the row it
    // opens looked perfectly calm in here. Ask the strip's own helper instead,
    // so the panel confirms what the cell said rather than second-guessing it.
    readonly property string severity: row ? Model.severityForPercent(row.percent) : "none"
    readonly property bool critical: severity === "critical"
    readonly property bool attention: severity === "warn" || critical
    readonly property string detailText: Model.metricDetail(row, root.nowMs)
    readonly property string resetText: row ? Model.formatReset(row.reset_at, root.nowMs) : ""

    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: Math.max(metricLabel.implicitHeight, metricValue.implicitHeight)

      Text {
        id: metricLabel
        text: metricRow.row ? metricRow.row.label : ""
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.uiFont
        // Every other row type in this list sets its label at bodySmall, and the
        // number this label describes used to be two pixels smaller than the
        // label itself. One scale down the whole section, with the label keeping
        // its presence through weight instead of size.
        font.pixelSize: Style.font.bodySmall
        font.weight: Font.DemiBold
        font.letterSpacing: -0.1
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: metricValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Row {
        id: metricValue
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)
        readonly property string leftText: Model.percentRemaining(metricRow.row)
        readonly property color tierColor: metricRow.critical ? root.urgent
          : (metricRow.severity === "warn" ? root.warnColor : root.foreground)

        Text {
          text: Model.percentUsed(metricRow.row)
          textFormat: Text.PlainText
          color: metricValue.tierColor
          font.family: root.monoFont
          font.pixelSize: Style.font.bodySmall
          font.bold: metricRow.attention
          font.features: { "tnum": 1 }
        }

        Text {
          visible: metricValue.leftText !== ""
          text: "· " + metricValue.leftText
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.monoFont
          font.pixelSize: Style.font.caption
          font.features: { "tnum": 1 }
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    // Sleek pill-rounded progress track matching the strip's 3-tier semantic color ladder.
    Item {
      id: meterBox
      readonly property int barHeight: Math.max(Style.space(7), Math.round(Style.spacing.controlHeight * 0.24))
      readonly property real corner: barHeight / 2
      readonly property var pace: Model.pacePercent(metricRow.row, root.readingMs)
      readonly property bool hasPace: metricRow.row !== null && pace !== null && metricRow.row.percent !== null
      width: parent.width
      readonly property int rim: Math.max(1, Style.space(1))
      readonly property int length: metricRow.row ? Model.fillHeight(metricRow.row.percent, width) : 0
      readonly property int paceWidth: Math.max(2, Style.space(2))
      readonly property int paceX: width - paceWidth - Model.paceOffset(pace, width, paceWidth)
      readonly property bool paceInFill: paceX + paceWidth / 2 <= length
      readonly property color fillTint: metricRow.critical ? root.urgent
        : (metricRow.severity === "warn" ? root.warnColor : root.foreground)
      implicitHeight: barHeight

      Rectangle {
        id: meterTrack
        width: parent.width
        height: meterBox.barHeight
        radius: meterBox.corner
        color: root.alpha(root.foreground, 0.09)
        border.width: meterBox.rim
        border.color: metricRow.critical ? root.alpha(root.urgent, 0.65) : root.alpha(root.foreground, 0.16)
      }

      Rectangle {
        visible: meterBox.length > 0
        height: meterTrack.height
        width: meterBox.length
        radius: meterBox.corner
        color: meterBox.fillTint
      }

      Rectangle {
        visible: meterBox.hasPace
        x: meterBox.paceX
        y: meterBox.paceInFill ? 0 : meterBox.rim
        width: meterBox.paceWidth
        height: meterBox.paceInFill ? meterTrack.height : meterTrack.height - meterBox.rim * 2
        radius: 1
        color: meterBox.paceInFill ? root.surface : root.inkOf(root.meterInks.paceLine)
      }
    }

    Text {
      visible: text !== ""
      width: parent.width
      text: metricRow.detailText
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
      font.features: { "tnum": 1 }
      wrapMode: Text.WordWrap
    }

    Text {
      visible: text !== ""
      width: parent.width
      text: metricRow.resetText
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.monoFont
      font.pixelSize: Style.font.caption
      font.features: { "tnum": 1 }
      // The row now carries a date and clock as well as the countdown, so it
      // can outgrow a narrow panel. Wrap like the detail line above it rather
      // than painting past the panel edge.
      wrapMode: Text.WordWrap
    }
  }

  component DetailRow: Item {
    id: detailRow
    property var row: null
    readonly property bool heading: row && row.label !== "" && row.value === ""

    implicitHeight: heading ? headingLabel.implicitHeight : Math.max(detailLabel.implicitHeight, detailValue.implicitHeight)

    PanelSectionHeader {
      id: headingLabel
      visible: detailRow.heading
      width: parent.width
      text: detailRow.row ? Model.autoTextSafe(String(detailRow.row.label || "").toUpperCase()) : ""
      foreground: root.foreground
      fontFamily: root.uiFont
      font.letterSpacing: 0.85
    }

    Text {
      id: detailLabel
      visible: !detailRow.heading && text !== ""
      text: detailRow.row ? detailRow.row.label : ""
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.uiFont
      font.pixelSize: Style.font.bodySmall
      font.weight: Font.DemiBold
      anchors.left: parent.left
      anchors.top: parent.top
      width: Math.min(implicitWidth, parent.width * 0.42)
      elide: Text.ElideRight
    }

    Text {
      id: detailValue
      visible: !detailRow.heading
      text: detailRow.row ? detailRow.row.value : ""
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.monoFont
      font.pixelSize: Style.font.bodySmall
      font.features: { "tnum": 1 }
      horizontalAlignment: detailLabel.visible ? Text.AlignRight : Text.AlignLeft
      wrapMode: Text.WordWrap
      anchors.left: detailLabel.visible ? detailLabel.right : parent.left
      anchors.leftMargin: detailLabel.visible ? Style.spacing.md : 0
      anchors.right: parent.right
      anchors.top: parent.top
    }
  }

  component ProviderActivityRow: Button {
    id: providerRow
    property var row: null
    readonly property bool isExpanded: row !== null && root.expandedActivityProvider === row.id
    readonly property bool hasApps: !!(row && row.apps && row.apps.length > 0)
    objectName: row ? "providerActivity-" + row.id : "providerActivity-empty"
    height: Style.space(42)
    radius: Math.max(8, root.pillRadius - 2)
    selected: false
    bordered: false
    background: "transparent"
    foreground: root.foreground
    fontFamily: root.uiFont
    onClicked: if (row) root.expandedActivityProvider = isExpanded ? "" : row.id

    Rectangle {
      anchors.fill: parent
      radius: Math.max(8, root.pillRadius - 2)
      color: providerRow.isExpanded
        ? root.alpha(root.foreground, 0.10)
        : (providerRow.hot ? root.alpha(root.foreground, 0.075) : root.alpha(root.foreground, 0.038))
      border.width: 1
      border.color: providerRow.isExpanded
        ? root.alpha(root.foreground, 0.22)
        : (providerRow.hot ? root.alpha(root.foreground, 0.16) : root.alpha(root.foreground, 0.09))
      Behavior on color { ColorAnimation { duration: Style.duration(120) } }
      Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

      GlassHighlight { inset: Style.space(7) }
    }

    Item {
      id: rowIconGutter
      width: Style.space(32)
      height: Style.bar.iconCanvas
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter

      ProviderMark {
        id: rowMark
        role: "spend"
        mark: providerRow.row ? providerRow.row.mark : ""
        initials: providerRow.row ? providerRow.row.name.slice(0, 2) : ""
        color: root.foreground
        surfaceColor: root.surface
        fontFamily: root.monoFont
        width: Math.round(Style.bar.iconCanvas * Model.markAspect(mark))
        height: Style.bar.iconCanvas
        anchors.centerIn: parent
      }
    }

    Column {
      anchors.left: rowIconGutter.right
      anchors.leftMargin: Style.space(8)
      anchors.right: rowTrailing.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        width: parent.width
        text: providerRow.row ? providerRow.row.name : ""
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.uiFont
        font.pixelSize: Style.font.bodySmall
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: providerRow.row ? providerRow.row.d30.replies + (providerRow.row.d30.replies === 1 ? " reply · " : " replies · ") + Model.formatTokens(providerRow.row.d30.tokens) + " tokens" : ""
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.features: { "tnum": 1 }
        elide: Text.ElideRight
      }
    }

    Row {
      id: rowTrailing
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Text {
        id: rowCost
        readonly property string costLabel: Model.recordedCost(providerRow.row ? providerRow.row.d30 : null)
        readonly property bool isFigure: /\d/.test(costLabel)
        text: costLabel
        textFormat: Text.PlainText
        color: isFigure ? root.foreground : root.dim
        font.family: isFigure ? root.monoFont : root.uiFont
        font.pixelSize: isFigure ? Style.font.bodySmall : Style.font.caption
        font.weight: isFigure ? Font.Bold : Font.Medium
        font.features: { "tnum": 1 }
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        visible: providerRow.hasApps
        text: providerRow.isExpanded ? "󰅃" : "󰅀"
        textFormat: Text.PlainText
        color: providerRow.isExpanded ? root.foreground : root.dim
        font.family: root.monoFont
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  component AppActivityRow: Rectangle {
    id: appRow
    property var row: null
    implicitHeight: Style.space(38)
    radius: Math.max(7, root.pillRadius - 3)
    color: root.alpha(root.foreground, 0.025)
    border.width: 1
    border.color: root.alpha(root.foreground, 0.08)

    GlassHighlight { inset: Style.space(6) }

    Rectangle {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.topMargin: Style.space(7)
      anchors.bottomMargin: Style.space(7)
      width: 2
      radius: 1
      color: root.alpha(Commons.Color.accent, 0.55)
    }

    ProviderMark {
      id: appMark
      role: "spend"
      mark: appRow.row && appRow.row.id === "opencode" ? "opencode" : "deepseek"
      color: root.foreground
      surfaceColor: root.surface
      fontFamily: root.monoFont
      width: Style.bar.iconCanvas
      height: Style.bar.iconCanvas
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
    }
    Column {
      anchors.left: appMark.right
      anchors.leftMargin: Style.space(10)
      anchors.right: appCost.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        width: parent.width
        text: appRow.row ? appRow.row.name : ""
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.uiFont
        font.pixelSize: Style.font.bodySmall
        font.weight: Font.Medium
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: appRow.row ? appRow.row.d30.replies + (appRow.row.d30.replies === 1 ? " reply · " : " replies · ") + Model.formatTokens(appRow.row.d30.tokens) + " tokens" : ""
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.features: { "tnum": 1 }
        elide: Text.ElideRight
      }
    }
    Text {
      id: appCost
      readonly property string costLabel: Model.recordedCost(appRow.row ? appRow.row.d30 : null)
      readonly property bool isFigure: /\d/.test(costLabel)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: costLabel
      textFormat: Text.PlainText
      color: isFigure ? root.foreground : root.dim
      font.family: isFigure ? root.monoFont : root.uiFont
      font.pixelSize: isFigure ? Style.font.bodySmall : Style.font.caption
      font.weight: isFigure ? Font.Bold : Font.Medium
      font.features: { "tnum": 1 }
    }
  }

  component BlockRow: Column {
    id: blockRow
    property var row: null

    spacing: Style.space(4)

    Text {
      width: parent.width
      text: blockRow.row ? blockRow.row.label : ""
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.uiFont
      font.pixelSize: Style.font.bodySmall
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: blockRow.row && blockRow.row.body ? blockRow.row.body.join("\n") : ""
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
