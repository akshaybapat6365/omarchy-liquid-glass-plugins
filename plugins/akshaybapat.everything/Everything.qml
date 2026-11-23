pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "EverythingModel.js" as Model

Panel {
  id: root
  moduleName: "akshaybapat.everything"
  ipcTarget: "akshaybapat.everything"
  manageIpc: false

  readonly property var everythingService: root.bar && root.bar.shell
    && typeof root.bar.shell.serviceFor === "function"
    ? root.bar.shell.serviceFor("akshaybapat.everything") : null
  readonly property var appLibrary: root.bar && root.bar.shell
    && root.bar.shell.appLibrary !== undefined ? root.bar.shell.appLibrary : null
  readonly property var desktopEntries: DesktopEntries.applications.values || []
  readonly property var itemRelations: Model.relationIndex(
    everythingService ? everythingService.items : [])
  readonly property var supportedGroups: Model.supportedGroupCatalog()
  readonly property var disabledKinds: Model.normalizeDisabledKinds(
    root.setting("disabledKinds", []))

  // Typography tokens: Inter Display (via Style.font.menuFamily) for all UI prose,
  // monospace Nerd Font strictly for glyphs and keycap badges.
  readonly property var styleFont: Style.font
  readonly property string uiFont: String(styleFont.menuFamily || styleFont.family)
  readonly property string monoFont: String(styleFont.family)

  // Adaptive frosted-glass palette derived strictly from Omarchy theme tokens.
  readonly property var popupsColors: Commons.Color.popups
  readonly property color surfaceBg: popupsColors.background
  readonly property real surfaceLuminance: 0.2126 * surfaceBg.r
    + 0.7152 * surfaceBg.g + 0.0722 * surfaceBg.b
  readonly property bool isDarkSurface: surfaceLuminance < 0.5
  readonly property color foreground: root.bar ? root.bar.foreground : popupsColors.text
  readonly property color accentColor: Commons.Color.accent
  readonly property color urgentColor: Commons.Color.urgent
  readonly property color secondaryForeground: Util.alpha(foreground, isDarkSurface ? 0.62 : 0.66)
  readonly property color tertiaryForeground: Util.alpha(foreground, isDarkSurface ? 0.44 : 0.50)
  readonly property color dimForeground: secondaryForeground
  readonly property color hairlineColor: Util.alpha(foreground, isDarkSurface ? 0.10 : 0.11)
  readonly property color specularHighlight: isDarkSurface
    ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.88)
  readonly property color subtleSurface: isDarkSurface
    ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04)
  readonly property color subtleSurfaceHover: isDarkSurface
    ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.07)
  readonly property color subtleSurfaceBorder: isDarkSurface
    ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.085)
  readonly property color selectedRowFill: isDarkSurface
    ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.065)
  readonly property color selectedRowSubtleFill: isDarkSurface
    ? Qt.rgba(1, 1, 1, 0.058) : Qt.rgba(0, 0, 0, 0.042)
  readonly property color selectedRowBorder: isDarkSurface
    ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.095)
  readonly property color selectedIconTileFill: Util.alpha(accentColor, isDarkSurface ? 0.20 : 0.14)
  readonly property color selectedIconTileBorder: Util.alpha(accentColor, isDarkSurface ? 0.38 : 0.30)
  readonly property color footerFill: isDarkSurface
    ? Qt.rgba(0, 0, 0, 0.24) : Qt.rgba(0, 0, 0, 0.032)
  readonly property color keycapFill: isDarkSurface
    ? Qt.rgba(1, 1, 1, 0.075) : Qt.rgba(1, 1, 1, 0.78)
  readonly property color keycapBorder: isDarkSurface
    ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.14)

  // Concentric geometry matching the floating glass capsule.
  readonly property int outerRadius: Math.max(14, Style.cornerRadius + 2)
  readonly property int cardInnerRadius: Math.max(0, Style.cornerRadius - 1)
  readonly property int innerRadius: Math.max(9, Style.cornerRadius - 2)
  readonly property int tileRadius: Math.max(7, innerRadius - 2)
  readonly property int pillRadius: Math.max(5, tileRadius - 2)

  readonly property int searchHeaderHeight: Style.space(56)
  readonly property int groupsHeaderHeight: Style.space(56)
  readonly property int footerHeight: Style.space(38)
  readonly property int emptyStateHeight: Style.space(188)
  readonly property int listTopPadding: Style.space(6)
  readonly property int listBottomPadding: Style.space(8)
  readonly property real rowHeight: Style.space(48)
  readonly property int sectionHeight: Style.space(30)
  readonly property int groupChecklistRowHeight: Style.space(38)
  // How much of the row past the fold stays showing when the list outgrows the
  // card — the same 55% of a row the shell's own menu peeks by.
  readonly property int rowPeek: Math.round(rowHeight * 0.55)

  readonly property bool isScanning: !!(everythingService && everythingService.scanning === true)
  readonly property int enabledGroupCount: Math.max(0, supportedGroups.length - disabledKinds.length)
  readonly property var activeItem: resultList.currentIndex >= 0
    && resultList.currentIndex < rankedItems.length
    ? rankedItems[resultList.currentIndex] : null

  readonly property var sectionCounts: {
    var counts = {}
    for (var i = 0; i < rankedItems.length; i++) {
      var kind = String(rankedItems[i] && rankedItems[i].kind || "")
      counts[kind] = (counts[kind] || 0) + 1
    }
    return counts
  }

  // The bottom edge of everything the result list draws: collapsed groups stop
  // at their heading; expanded groups pair their heading with their first row
  // so folding never leaves an orphaned category header at the bottom edge.
  readonly property var resultsEdges: {
    var edges = []
    var bottom = 0
    var previous = ""
    for (var i = 0; i < rankedItems.length; i++) {
      var kind = String(rankedItems[i] && rankedItems[i].kind || "")
      var collapsed = groupCollapsed(kind)
      var startsSection = (i === 0 || kind !== previous)
      if (startsSection) {
        bottom += sectionHeight
        if (collapsed) edges.push({ bottom: bottom, startsSection: true })
      }
      if (!collapsed) {
        bottom += rowHeight
        edges.push({ bottom: bottom, startsSection: startsSection })
      }
      previous = kind
    }
    return edges
  }

  readonly property real resultsContentHeight: resultsEdges.length > 0
    ? resultsEdges[resultsEdges.length - 1].bottom : 0

  function foldedResultsHeight(available) {
    if (available <= 0 || resultsContentHeight <= available) return resultsContentHeight
    var limit = available - rowPeek
    var fold = 0
    var foldIndex = -1
    for (var i = 0; i < resultsEdges.length && resultsEdges[i].bottom <= limit; i++) {
      fold = resultsEdges[i].bottom
      foldIndex = i
    }
    if (fold <= 0) return available
    var nextEdge = foldIndex + 1 < resultsEdges.length ? resultsEdges[foldIndex + 1] : null
    if (nextEdge && nextEdge.startsSection) {
      var peekWithSection = fold + sectionHeight + rowPeek
      return peekWithSection <= available ? peekWithSection : fold
    }
    return fold + rowPeek
  }

  readonly property string resultsMode: "results"
  readonly property string groupsMode: "groups"
  readonly property bool resultsModeOpen: root.opened && popupMode === resultsMode
  property var rankedItems: []
  property var collapsedKinds: ({})
  property string popupMode: resultsMode
  property string selectedItemUuid: ""
  property real savedSelectedOffset: 0
  property bool savedListFocus: false
  property bool savedKeyCatcherFocus: false
  property bool savedSearchFocus: false
  property bool pendingSelectionSurvived: false
  property bool resultUpdateInProgress: false
  property bool rankUpdateScheduled: false
  property int resultUpdateSerial: 0
  property bool pointerCursorActive: false
  // A widget may acquire its service lease before its QsWindow/screen exists.
  // Keep the owner key stable and instance-local so an early "unknown" screen
  // can never collide with another monitor or leak a lease after reparenting.
  readonly property string instanceKey: "everything:" + Date.now() + ":"
    + Math.random().toString(36).slice(2)

  function shortKindBadge(kind) {
    switch (String(kind || "")) {
      case "window": return "Window"
      case "browser-tab": return "Browser Tab"
      case "app-tab": return "App Tab"
      case "terminal-tab": return "Terminal Tab"
      case "terminal-pane": return "Pane"
      case "herdr-agent": return "Agent"
      case "herdr-workspace": return "Workspace"
      case "herdr-tab": return "Herdr Tab"
      case "herdr-pane": return "Herdr Pane"
      case "herdr-session": return "Session"
      case "tmux-session": return "tmux"
      case "tmux-window": return "tmux Window"
      case "tmux-pane": return "tmux Pane"
      case "neovim-buffer": return "Buffer"
      default: return Model.kindLabel(kind)
    }
  }

  function rowSubtitle(item, crumb, metadata) {
    if (!item) return ""
    var kind = String(item.kind || "")
    var titleNorm = Model.normalized(item.title)
    var meta = String(metadata || "").trim()
    var rawCrumb = String(crumb || "").replace(/\s*›\s*/g, " › ").trim()
    var context = String(item.context || "").trim()
    var provider = String(item.provider || "").trim()

    if (kind === "window") {
      var parts = []
      if (meta) parts.push(meta)
      if (context && Model.normalized(context) !== Model.normalized(meta)
          && Model.normalized(context) !== titleNorm) {
        parts.push(context)
      }
      return parts.join(" · ") || provider
    }

    if (kind === "neovim-buffer") {
      var bufParts = []
      if (context) bufParts.push(context)
      else if (meta) bufParts.push(meta)
      var badges = Model.badgeList(item.badges)
      for (var i = 0; i < badges.length; i++) {
        var bNorm = Model.normalized(badges[i])
        if (bNorm === "modified" || bNorm === "unloaded") {
          bufParts.push(badges[i].charAt(0).toUpperCase() + badges[i].slice(1))
          break
        }
      }
      return bufParts.join(" · ") || provider
    }

    if (kind === "herdr-agent") {
      var agentParts = []
      if (rawCrumb && Model.normalized(rawCrumb) !== titleNorm
          && Model.normalized(rawCrumb) !== Model.normalized(meta)) {
        agentParts.push(rawCrumb)
      }
      if (meta) agentParts.push(meta)
      return agentParts.join(" · ") || provider
    }

    var primary = ""
    if (rawCrumb && Model.normalized(rawCrumb) !== titleNorm) primary = rawCrumb
    else if (meta && Model.normalized(meta) !== titleNorm) primary = meta
    else primary = provider

    if (meta && primary && Model.normalized(primary).indexOf(Model.normalized(meta)) < 0
        && Model.normalized(meta) !== Model.normalized(provider)) {
      return primary + " · " + meta
    }
    return primary
  }

  function statusTone(item, metadata) {
    if (!item) return "neutral"
    var metaNorm = Model.normalized(metadata)
    if (metaNorm === "error" || metaNorm === "blocked") return "urgent"
    if (metaNorm === "working" || metaNorm === "modified") return "accent"
    var badges = Model.badgeList(item.badges)
    for (var i = 0; i < badges.length; i++) {
      var bNorm = Model.normalized(badges[i])
      if (bNorm === "error" || bNorm === "blocked") return "urgent"
      if (bNorm === "working" || bNorm === "modified") return "accent"
    }
    return "neutral"
  }

  function activeFooterContext() {
    if (popupMode === groupsMode) {
      return enabledGroupCount + " of " + supportedGroups.length + " groups visible"
    }
    if (!activeItem) {
      if (isScanning) return "Discovering windows, tabs, agents, and buffers"
      if (searchField.text.length > 0) return "No matching items"
      return "Everything"
    }
    var sectionLabel = Model.kindSectionLabel(activeItem.kind)
    var meta = Model.metadataForItem(activeItem, itemRelations)
    if (meta && Model.normalized(meta) !== Model.normalized(sectionLabel))
      return sectionLabel + " · " + meta
    return sectionLabel
  }

  function statusBadgeText() {
    var count = rankedItems.length
    if (isScanning && count === 0) return "Scanning"
    if (count === 0) return searchField.text.length > 0 ? "No matches" : ""
    return count === 1 ? "1 result" : (count + " results")
  }

  function disarmPointer() {
    pointerCursorActive = false
    pointerMoveGate.reset()
  }

  function kindDisabled(kind) {
    return disabledKinds.indexOf(String(kind || "")) >= 0
  }

  function persistDisabledKinds(value) {
    var nextKinds = Model.normalizeDisabledKinds(value)
    if (Model.sameStringList(disabledKinds, nextKinds)) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.disabledKinds = nextKinds

    // Update this monitor immediately. The shell write then injects the same
    // settings object into every live monitor instance without rebuilding it.
    root.settings = entry
    if (root.bar && root.bar.shell
        && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setKindEnabled(kind, enabled) {
    var value = String(kind || "")
    var shouldDisable = enabled !== true
    var catalogKind = false
    for (var index = 0; index < supportedGroups.length; index++) {
      if (supportedGroups[index].kind === value) {
        catalogKind = true
        break
      }
    }
    if (!catalogKind || kindDisabled(value) === shouldDisable) return

    var nextKinds = disabledKinds.slice()
    var disabledIndex = nextKinds.indexOf(value)
    if (!shouldDisable && disabledIndex >= 0) nextKinds.splice(disabledIndex, 1)
    else if (shouldDisable && disabledIndex < 0) nextKinds.push(value)
    persistDisabledKinds(nextKinds)
  }

  function toggleKindVisibility(kind) {
    setKindEnabled(kind, kindDisabled(kind))
  }

  function resetGroupChecklist() {
    groupList.currentIndex = supportedGroups.length > 0 ? 0 : -1
    groupList.contentY = groupList.originY
    Qt.callLater(function() {
      if (root.opened && root.popupMode === root.groupsMode)
        groupList.forceActiveFocus()
    })
  }

  function enterPopupMode(mode) {
    var wanted = mode === groupsMode ? groupsMode : resultsMode
    if (popupMode === wanted) return
    popupMode = wanted
    if (!root.opened) return

    if (wanted === groupsMode) {
      resetGroupChecklist()
    } else {
      searchField.text = ""
      if (appLibrary && typeof appLibrary.refreshIcons === "function")
        appLibrary.refreshIcons()
      rebuildRankedItems()
      resetResultsForOpen()
    }
  }

  function togglePopupMode(mode) {
    var wanted = mode === groupsMode ? groupsMode : resultsMode
    if (root.opened && popupMode === wanted) {
      root.close()
      return
    }
    if (root.opened) {
      enterPopupMode(wanted)
      return
    }
    popupMode = wanted
    root.open()
  }

  function setGroupChecklistIndex(index) {
    if (supportedGroups.length <= 0) {
      groupList.currentIndex = -1
      return
    }
    var bounded = Math.max(0, Math.min(supportedGroups.length - 1,
      Math.floor(Number(index || 0))))
    groupList.currentIndex = bounded
    groupList.positionViewAtIndex(bounded, ListView.Contain)
  }

  function moveGroupChecklist(delta) {
    if (supportedGroups.length <= 0 || Number(delta || 0) === 0) return
    var current = groupList.currentIndex < 0 ? 0 : groupList.currentIndex
    setGroupChecklistIndex(current + (delta < 0 ? -1 : 1))
    groupList.forceActiveFocus()
  }

  function toggleCurrentGroupVisibility() {
    var index = groupList.currentIndex
    if (index < 0 || index >= supportedGroups.length) return
    toggleKindVisibility(supportedGroups[index].kind)
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerMoveGate.moved(item, mouse)) return
    setCurrentIndex(index, false)
    pointerCursorActive = true
  }

  function focusSearch() {
    disarmPointer()
    searchField.forceActiveFocus()
  }

  function groupCollapsed(kind) {
    return collapsedKinds && collapsedKinds[String(kind || "")] === true
  }

  function currentGroupKind() {
    var index = resultList.currentIndex
    if (index < 0 || index >= rankedItems.length) return ""
    return String(rankedItems[index] && rankedItems[index].kind || "")
  }

  function selectionIsVisibleRow(index) {
    return index >= 0 && index < rankedItems.length
      && !groupCollapsed(rankedItems[index].kind)
  }

  function focusList(index) {
    if (resultList.count <= 0) return
    disarmPointer()
    setCurrentIndex(index === undefined ? 0 : index, true)
    if (resultList.currentIndex === 0)
      resultList.contentY = resultList.originY
    resultList.forceActiveFocus()
  }

  function setCurrentIndex(index, reveal) {
    if (resultList.count <= 0 || rankedItems.length <= 0) {
      resultList.currentIndex = -1
      selectedItemUuid = ""
      return
    }
    var bounded = Math.max(0, Math.min(Number(index || 0), resultList.count - 1))
    resultList.currentIndex = bounded
    selectedItemUuid = Model.itemUuid(rankedItems[bounded])
    if (reveal === true) revealSelection(bounded, false)
  }

  function moveSelection(delta) {
    if (resultList.count <= 0 || Number(delta || 0) === 0) return
    var direction = delta < 0 ? -1 : 1
    var steps = Math.max(1, Math.floor(Math.abs(Number(delta))))
    var candidate = resultList.currentIndex
    if (candidate < 0)
      candidate = Model.boundaryNavigableIndex(rankedItems, direction, collapsedKinds)
    for (var step = 0; step < steps; step++) {
      var next = Model.adjacentNavigableIndex(
        rankedItems, candidate, direction, collapsedKinds)
      if (next === candidate) break
      candidate = next
    }
    focusList(candidate)
  }

  function focusBoundary(direction) {
    focusList(Model.boundaryNavigableIndex(rankedItems, direction, collapsedKinds))
  }

  function setGroupCollapsed(kind, collapsed) {
    var value = String(kind || "")
    var wanted = collapsed === true
    if (!value || groupCollapsed(value) === wanted) return

    var nextKinds = {}
    for (var key in collapsedKinds) {
      if (collapsedKinds[key] === true) nextKinds[key] = true
    }
    if (wanted) nextKinds[value] = true
    else delete nextKinds[value]
    collapsedKinds = nextKinds
    disarmPointer()
    var index = resultList.currentIndex
    if (typeof resultList.forceLayout === "function") resultList.forceLayout()
    revealSelection(index, wanted)
  }

  function collapseCurrentGroup() {
    var kind = currentGroupKind()
    if (kind) setGroupCollapsed(kind, true)
  }

  function expandCurrentGroup() {
    var kind = currentGroupKind()
    if (kind) setGroupCollapsed(kind, false)
  }

  function toggleGroupFromHeading(kind) {
    var index = -1
    for (var itemIndex = 0; itemIndex < rankedItems.length; itemIndex++) {
      if (String(rankedItems[itemIndex].kind || "") === String(kind || "")) {
        index = itemIndex
        break
      }
    }
    if (index < 0) return
    setCurrentIndex(index, false)
    resultList.forceActiveFocus()
    setGroupCollapsed(kind, !groupCollapsed(kind))
  }

  function activateAt(index) {
    if (index < 0 || index >= rankedItems.length || !everythingService
        || !selectionIsVisibleRow(index)) return
    var target = rankedItems[index]
    // Release the layer-shell keyboard grab before asking another surface to
    // accept focus. Service.qml keeps the helper alive for the pending action.
    root.close()
    Qt.callLater(function() { everythingService.activate(target) })
  }

  function activateCurrent() {
    if (groupCollapsed(currentGroupKind())) {
      expandCurrentGroup()
      return
    }
    activateAt(resultList.currentIndex)
  }

  function hideAt(index) {
    if (index < 0 || index >= rankedItems.length || !everythingService
        || !selectionIsVisibleRow(index)) return
    everythingService.hideItem(rankedItems[index].id)
  }

  function handleEscape() {
    if (searchField.text.length > 0) {
      searchField.text = ""
      focusSearch()
    } else {
      root.close()
    }
  }

  function rowTopAt(index) {
    return Model.sectionedRowTop(
      rankedItems, index, rowHeight, sectionHeight, collapsedKinds)
  }

  function rowVisualTop(index) {
    if (index >= 0 && typeof resultList.itemAtIndex === "function") {
      var delegateItem = resultList.itemAtIndex(index)
      if (delegateItem) return Number(delegateItem.y)
    }
    return resultList.originY + rowTopAt(index)
  }

  function selectionVisualTop(index) {
    var top = rowVisualTop(index)
    if (index >= 0 && index < rankedItems.length
        && groupCollapsed(rankedItems[index].kind)) top -= sectionHeight
    return top
  }

  function revealSelection(index, alignTop) {
    if (index < 0 || index >= rankedItems.length) return
    if (typeof resultList.forceLayout === "function") resultList.forceLayout()
    var top = selectionVisualTop(index)
    var extent = groupCollapsed(rankedItems[index].kind) ? sectionHeight : rowHeight
    var wanted = resultList.contentY
    if (alignTop === true || top < wanted) wanted = top
    else if (top + extent > wanted + resultList.height)
      wanted = top + extent - resultList.height
    resultList.contentY = Model.clampContentY(
      wanted, resultList.originY, resultList.contentHeight, resultList.height)
  }

  function pageDelta(direction) {
    if (resultList.count <= 0 || direction === 0) return 0
    var current = Math.max(0, Math.min(resultList.count - 1, resultList.currentIndex))
    var target = selectionVisualTop(current)
      + (direction > 0 ? resultList.height : -resultList.height)
    var candidate = current
    var steps = 0
    while (true) {
      var next = Model.adjacentNavigableIndex(
        rankedItems, candidate, direction, collapsedKinds)
      if (next === candidate) break
      var nextTop = selectionVisualTop(next)
      if ((direction > 0 && nextTop > target)
          || (direction < 0 && nextTop < target)) break
      candidate = next
      steps++
    }
    if (steps === 0 && Model.adjacentNavigableIndex(
        rankedItems, candidate, direction, collapsedKinds) !== candidate) steps = 1
    return direction > 0 ? steps : -steps
  }

  function rememberFocusState() {
    savedKeyCatcherFocus = keyCatcher.activeFocus
    savedListFocus = resultList.activeFocus || savedKeyCatcherFocus
    savedSearchFocus = searchField.activeFocus
  }

  function rememberResultState() {
    rememberFocusState()
    var current = resultList.currentIndex
    if (current >= 0 && current < rankedItems.length) {
      selectedItemUuid = Model.itemUuid(rankedItems[current])
    }
    savedSelectedOffset = current >= 0
      ? resultList.contentY - selectionVisualTop(current) : 0
  }

  function applyOpenResultReset() {
    var index = rankedItems.length > 0 ? 0 : -1
    resultList.currentIndex = index
    selectedItemUuid = index >= 0 ? Model.itemUuid(rankedItems[index]) : ""
    savedSelectedOffset = 0
    resultList.contentY = resultList.originY
  }

  function resetResultsForOpen() {
    // A restore queued during the previous opening must never override the
    // fresh-open state after the panel becomes visible again.
    disarmPointer()
    resultUpdateSerial += 1
    collapsedKinds = ({})
    resultUpdateInProgress = false
    pendingSelectionSurvived = false
    applyOpenResultReset()
    Qt.callLater(function() {
      if (!root.opened) return
      if (typeof resultList.forceLayout === "function") resultList.forceLayout()
      root.applyOpenResultReset()
      searchField.forceActiveFocus()
    })
  }

  function scheduleRankedItems() {
    if (rankUpdateScheduled) return
    rankUpdateScheduled = true
    Qt.callLater(function() {
      // A pending rank can outlive the widget: the delayed call still runs, on
      // an object whose methods are already gone.
      if (typeof root.rebuildRankedItems !== "function") return
      root.rankUpdateScheduled = false
      root.rebuildRankedItems()
    })
  }

  function rebuildRankedItems() {
    var nextItems = Model.rank(
      everythingService ? everythingService.items : [],
      searchField.text,
      everythingService ? everythingService.hiddenIds : {},
      disabledKinds)
    if (Model.sameRankedItems(rankedItems, nextItems)) return
    if (!resultUpdateInProgress) rememberResultState()
    disarmPointer()
    resultUpdateInProgress = true
    rankedItems = nextItems
    resultUpdateSerial += 1
    var serial = resultUpdateSerial
    Qt.callLater(function() {
      if (serial === root.resultUpdateSerial) root.restoreResultSelection(serial)
    })
  }

  function restoreResultSelection(serial) {
    if (serial !== resultUpdateSerial) return
    if (typeof resultList.forceLayout === "function") resultList.forceLayout()
    pendingSelectionSurvived = Model.indexOfUuid(rankedItems, selectedItemUuid) >= 0
    var index = Model.indexAfterRefresh(rankedItems, selectedItemUuid)
    resultList.currentIndex = index
    selectedItemUuid = index >= 0 ? Model.itemUuid(rankedItems[index]) : ""
    if (!pendingSelectionSurvived) resultList.contentY = resultList.originY
    Qt.callLater(function() {
      if (serial === root.resultUpdateSerial) root.finishResultRestore(serial)
    })
  }

  function finishResultRestore(serial) {
    if (serial !== resultUpdateSerial) return
    if (typeof resultList.forceLayout === "function") resultList.forceLayout()
    var index = Model.indexOfUuid(rankedItems, selectedItemUuid)
    if (index < 0) index = rankedItems.length > 0 ? 0 : -1
    resultList.currentIndex = index
    selectedItemUuid = index >= 0 ? Model.itemUuid(rankedItems[index]) : ""

    if (pendingSelectionSurvived && index >= 0
        && resultList.contentHeight > resultList.height + 0.5) {
      resultList.contentY = Model.clampContentY(selectionVisualTop(index) + savedSelectedOffset,
        resultList.originY, resultList.contentHeight, resultList.height)
    } else if (!pendingSelectionSurvived) {
      resultList.contentY = resultList.originY
    }

    if (savedKeyCatcherFocus) keyCatcher.forceActiveFocus()
    else if (savedListFocus && index >= 0) resultList.forceActiveFocus()
    else if (savedSearchFocus) searchField.forceActiveFocus()
    resultUpdateInProgress = false
  }

  function breadcrumb(item) {
    return Model.breadcrumbFromIndex(item, itemRelations)
  }

  function usableIconSource(value) {
    var source = String(value || "")
    var generic = String(Quickshell.iconPath("application-x-executable", true) || "")
    return source && source !== generic ? source : ""
  }

  function resolveWindowDesktopEntry(item) {
    if (!item || String(item.kind || "") !== "window") return null
    var hints = Model.iconHintList(item)
    if (hints.length === 0) return null

    var entry = Model.matchDesktopEntry(hints, desktopEntries)
    if (!entry) {
      for (var lookup = 0; lookup < hints.length && !entry; lookup++) {
        try { entry = DesktopEntries.heuristicLookup(hints[lookup]) } catch (_error) { }
      }
    }
    return entry || null
  }

  function windowIconSource(item, resolvedEntry) {
    if (!item || String(item.kind || "") !== "window") return ""
    var hints = Model.iconHintList(item)
    if (hints.length === 0) return ""

    var entry = resolvedEntry || resolveWindowDesktopEntry(item)
    if (entry && entry.icon) {
      if (appLibrary && typeof appLibrary.iconSource === "function") {
        var librarySource = usableIconSource(appLibrary.iconSource(entry.icon))
        if (librarySource) return librarySource
      }
      var entrySource = usableIconSource(Quickshell.iconPath(String(entry.icon), true))
      if (entrySource) return entrySource
    }

    // A direct icon name from Hyprland can be useful even when it has no
    // corresponding desktop entry. Unknown names remain a local glyph
    // fallback; they are never treated as arbitrary URLs.
    for (var hint = 0; hint < hints.length; hint++) {
      var directSource = usableIconSource(Quickshell.iconPath(hints[hint], true))
      if (directSource) return directSource
    }
    return ""
  }

  function handleSupplementalListKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var action = ""
    if (ctrl && event.key === Qt.Key_N) action = "next"
    else if (ctrl && event.key === Qt.Key_P) action = "previous"
    else if (event.key === Qt.Key_Home) action = "first"
    else if (event.key === Qt.Key_End) action = "last"
    else if (event.key === Qt.Key_PageDown || (ctrl && event.key === Qt.Key_D)) action = "page-next"
    else if (event.key === Qt.Key_PageUp || (ctrl && event.key === Qt.Key_U)) action = "page-previous"
    else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) action = "hide"

    if (!action) return
    event.accepted = true
    if (action === "next") moveSelection(1)
    else if (action === "previous") moveSelection(-1)
    else if (action === "first") focusBoundary(-1)
    else if (action === "last") focusBoundary(1)
    else if (action === "page-next") moveSelection(pageDelta(1))
    else if (action === "page-previous") moveSelection(pageDelta(-1))
    else if (action === "hide") hideAt(resultList.currentIndex)
  }

  onOpenedChanged: {
    if (root.opened) {
      if (popupMode === groupsMode) {
        resetGroupChecklist()
      } else {
        searchField.text = ""
        if (appLibrary && typeof appLibrary.refreshIcons === "function")
          appLibrary.refreshIcons()
        rebuildRankedItems()
        resetResultsForOpen()
      }
    } else {
      popupMode = resultsMode
    }
  }

  onResultsModeOpenChanged: {
    if (!everythingService) return
    if (resultsModeOpen) everythingService.acquire(instanceKey)
    else everythingService.release(instanceKey)
  }

  onEverythingServiceChanged: {
    if (resultsModeOpen && everythingService) everythingService.acquire(instanceKey)
    scheduleRankedItems()
  }
  onDisabledKindsChanged: scheduleRankedItems()
  Component.onCompleted: scheduleRankedItems()
  Component.onDestruction: if (everythingService) everythingService.release(instanceKey)

  Connections {
    target: root.everythingService
    ignoreUnknownSignals: true
    function onItemsChanged() { root.scheduleRankedItems() }
    function onHiddenIdsChanged() { root.scheduleRankedItems() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  component KeycapHint: Row {
    id: hintRow
    property string keyLabel: ""
    property string actionLabel: ""
    property bool emphasized: false
    spacing: Style.space(5)

    Rectangle {
      id: keyBadge
      height: Style.space(20)
      width: Math.max(Style.space(22), keyGlyph.implicitWidth + Style.space(10))
      radius: root.pillRadius
      anchors.verticalCenter: hintRow.verticalCenter
      color: hintRow.emphasized
        ? Util.alpha(root.accentColor, root.isDarkSurface ? 0.22 : 0.14)
        : root.keycapFill
      border.width: 1
      border.color: hintRow.emphasized
        ? Util.alpha(root.accentColor, root.isDarkSurface ? 0.42 : 0.34)
        : root.keycapBorder

      Text {
        id: keyGlyph
        anchors.centerIn: keyBadge
        textFormat: Text.PlainText
        text: hintRow.keyLabel
        color: hintRow.emphasized ? root.foreground : root.secondaryForeground
        font.family: root.monoFont
        font.pixelSize: Math.max(10, Math.round(root.styleFont.caption))
        font.weight: Font.Medium
      }
    }

    Text {
      anchors.verticalCenter: hintRow.verticalCenter
      textFormat: Text.PlainText
      text: hintRow.actionLabel
      color: hintRow.emphasized ? root.foreground : root.tertiaryForeground
      font.family: root.uiFont
      font.pixelSize: Math.max(11, Math.round(root.styleFont.bodySmall))
      font.weight: hintRow.emphasized ? Font.Medium : Font.Normal
    }
  }

  PointerMoveGate {
    id: pointerMoveGate
    referenceItem: resultList
  }

  BarIconButton {
    id: button
    objectName: "everything-bar-button"
    anchors.fill: root
    bar: root.bar
    // A magnifier, not a chevron: the button opens a search over everything,
    // and a bare down-arrow on a bar of icons said "more" without saying what.
    text: "\u{F0349}"
    useActiveColor: false
    iconComponent: Component {
      Item {
        id: chevronFrame
        objectName: "everything-bar-chevron"
        // QML pixel-aligns the even optical canvas inside the odd bar slot.
        // Counter that half-pixel shift without moving the slot or hit target.
        readonly property real buttonCenterX: button.width / 2
          - Math.round((button.width - chevronFrame.width) / 2)
        readonly property real centerErrorX: chevron.x
          + chevron.paintedCenterX - buttonCenterX

        OpticalGlyph {
          id: chevron
          width: chevronFrame.width
          height: chevronFrame.height
          x: chevronFrame.buttonCenterX - chevron.paintedCenterX
          text: button.text
          fontFamily: button.fontFamily
          fontSize: button.fontSize
          color: button.active && button.useActiveColor
            ? button.activeColor : button.foreground
        }
      }
    }
    active: root.opened
    tooltipText: "Everything"
    activeFocusOnTab: true
    Keys.onReturnPressed: root.togglePopupMode(root.resultsMode)
    Keys.onEnterPressed: root.togglePopupMode(root.resultsMode)
    Keys.onSpacePressed: root.togglePopupMode(root.resultsMode)
    onPressed: function(buttonCode) {
      root.togglePopupMode(buttonCode === Qt.RightButton
        ? root.groupsMode : root.resultsMode)
    }

    Accessible.role: Accessible.Button
    Accessible.name: "Open Everything"
    Accessible.description: "Search things with the primary action; choose visible groups with right-click"
    Accessible.focusable: true
    Accessible.focused: button.activeFocus
    Accessible.onPressAction: root.togglePopupMode(root.resultsMode)

    Rectangle {
      anchors.fill: button
      anchors.margins: Style.space(2)
      visible: button.activeFocus
      color: "transparent"
      radius: Math.min(Style.cornerRadius, Style.space(6))
      border.width: Math.max(1, Style.normalBorderWidth)
      border.color: Style.focusBorderFor(button.foreground, Commons.Color.accent)
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    padding: 0
    borderSpec: Border.surfaceSpec("popups", "border", root.popupsColors.border, 1)
    focusTarget: root.popupMode === root.groupsMode ? groupList : searchField
    contentWidth: popup.fittedContentWidth(Style.space(660))
    readonly property real maxPanelHeight: Style.space(650)
    readonly property real resultsBudget: popup.cappedContentHeight(maxPanelHeight)
      - popup.verticalContentInset - root.searchHeaderHeight - 1
      - root.listTopPadding - root.listBottomPadding - 1 - root.footerHeight
    contentHeight: popup.fittedContentHeight(
      root.popupMode === root.groupsMode
        ? root.groupsHeaderHeight + 1 + root.listTopPadding
          + root.supportedGroups.length * root.groupChecklistRowHeight
          + root.listBottomPadding + 1 + root.footerHeight
        : root.searchHeaderHeight + 1
          + (root.resultsContentHeight > 0
            ? root.listTopPadding + root.foldedResultsHeight(popup.resultsBudget)
              + root.listBottomPadding
            : root.emptyStateHeight)
          + 1 + root.footerHeight,
      maxPanelHeight)

    PanelKeyCatcher {
      id: keyCatcher
      objectName: "everything-key-catcher"
      anchors.fill: parent
      blocked: root.popupMode === root.resultsMode && searchField.activeFocus

      onMoveRequested: function(dx, dy) {
        if (root.popupMode === root.groupsMode) {
          if (dy !== 0) root.moveGroupChecklist(dy)
        } else if (dy !== 0) root.moveSelection(dy)
        else if (dx < 0) root.collapseCurrentGroup()
        else if (dx > 0) root.expandCurrentGroup()
      }
      onActivateRequested: {
        if (root.popupMode === root.groupsMode) root.toggleCurrentGroupVisibility()
        else root.activateCurrent()
      }
      onCloseRequested: {
        if (root.popupMode === root.groupsMode) root.close()
        else root.handleEscape()
      }
      onDeleteRequested: if (root.popupMode === root.resultsMode)
        root.hideAt(resultList.currentIndex)
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (root.popupMode !== root.resultsMode) return
        if (text === "/") root.focusSearch()
        else if (text === "g") root.focusBoundary(-1)
        else if (text === "G") root.focusBoundary(1)
      }

      Item {
        id: content
        anchors.fill: keyCatcher
        Accessible.role: Accessible.Pane
        Accessible.name: root.popupMode === root.groupsMode
          ? "Everything group visibility panel" : "Everything search and switch panel"

        // Subtle optical glass wash inside the frosted card.
        Rectangle {
          anchors.fill: content
          radius: root.cardInnerRadius
          gradient: Gradient {
            GradientStop {
              position: 0.0
              color: root.isDarkSurface ? Qt.rgba(1, 1, 1, 0.036) : Qt.rgba(1, 1, 1, 0.42)
            }
            GradientStop {
              position: 0.45
              color: root.isDarkSurface ? Qt.rgba(1, 1, 1, 0.006) : Qt.rgba(1, 1, 1, 0.14)
            }
            GradientStop {
              position: 1.0
              color: root.isDarkSurface ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(0, 0, 0, 0.025)
            }
          }
        }

        // Crisp 1px top-edge inner specular highlight (fades cleanly before corner arcs).
        Rectangle {
          anchors.top: content.top
          anchors.left: content.left
          anchors.right: content.right
          anchors.leftMargin: Math.max(Style.space(12), root.cardInnerRadius)
          anchors.rightMargin: Math.max(Style.space(12), root.cardInnerRadius)
          height: 1
          z: 10
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.14; color: root.specularHighlight }
            GradientStop { position: 0.86; color: root.specularHighlight }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }

        // ------------------------------------------------ Hero Search Header
        Item {
          id: searchHeader
          anchors.top: content.top
          anchors.left: content.left
          anchors.right: content.right
          height: root.searchHeaderHeight
          visible: root.popupMode === root.resultsMode

          Text {
            id: searchGlyph
            anchors.left: searchHeader.left
            anchors.leftMargin: Style.space(18)
            anchors.verticalCenter: searchHeader.verticalCenter
            textFormat: Text.PlainText
            text: "\u{F0349}"
            color: searchField.activeFocus || searchField.text.length > 0
              ? root.accentColor : root.tertiaryForeground
            font.family: root.monoFont
            font.pixelSize: Style.space(17)
            verticalAlignment: Text.AlignVCenter
            Behavior on color { ColorAnimation { duration: Style.duration(120) } }
          }

          TextField {
            id: searchField
            objectName: "everything-search"
            anchors.left: searchGlyph.right
            anchors.leftMargin: Style.space(12)
            anchors.right: searchTrailing.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: searchHeader.verticalCenter
            height: Style.space(38)
            visible: root.popupMode === root.resultsMode
            enabled: visible
            placeholderText: "Search windows, tabs, agents, buffers…"
            color: root.foreground
            placeholderTextColor: root.tertiaryForeground
            selectionColor: Util.alpha(root.accentColor, 0.30)
            selectedTextColor: root.foreground
            font.family: root.uiFont
            font.pixelSize: Style.space(17)
            font.weight: Font.Normal
            leftPadding: 0
            rightPadding: 0
            topPadding: 0
            bottomPadding: 0
            verticalAlignment: TextInput.AlignVCenter
            background: Item {}
            activeFocusOnTab: true
            Accessible.role: Accessible.EditableText
            Accessible.name: "Search things"
            Accessible.description: "Type a contiguous title or group-name substring"
            Accessible.editable: true
            Accessible.focusable: true
            Accessible.focused: searchField.activeFocus
            onActiveFocusChanged: if (searchField.activeFocus) root.disarmPointer()
            onTextChanged: root.scheduleRankedItems()

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
              if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab
                  && (event.modifiers & Qt.ShiftModifier) === 0)) {
                event.accepted = true
                root.focusBoundary(-1)
              } else if (ctrl && event.key === Qt.Key_N) {
                event.accepted = true
                root.moveSelection(1)
              } else if (ctrl && event.key === Qt.Key_P) {
                event.accepted = true
                root.moveSelection(-1)
              } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                  && resultList.count > 0) {
                event.accepted = true
                root.activateCurrent()
              } else if (event.key === Qt.Key_Escape) {
                event.accepted = true
                root.handleEscape()
              }
            }
          }

          Row {
            id: searchTrailing
            anchors.right: searchHeader.right
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: searchHeader.verticalCenter
            spacing: Style.space(8)

            // Clear query button (appears when query has text).
            Rectangle {
              id: clearButton
              visible: searchField.text.length > 0
              width: Style.space(22)
              height: Style.space(22)
              radius: width / 2
              anchors.verticalCenter: searchTrailing.verticalCenter
              color: clearMouse.containsMouse ? root.subtleSurfaceHover : root.subtleSurface
              border.width: 1
              border.color: root.subtleSurfaceBorder
              Behavior on color { ColorAnimation { duration: Style.duration(80) } }

              Text {
                anchors.centerIn: clearButton
                textFormat: Text.PlainText
                text: "\uf00d"
                color: clearMouse.containsMouse ? root.foreground : root.secondaryForeground
                font.family: root.monoFont
                font.pixelSize: Style.space(10)
              }

              MouseArea {
                id: clearMouse
                anchors.fill: clearButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  searchField.text = ""
                  root.focusSearch()
                }
              }
            }

            // Live result counter / scanning status pill.
            Rectangle {
              id: statusPill
              readonly property string badgeText: root.statusBadgeText()
              visible: badgeText.length > 0 || root.isScanning
              height: Style.space(24)
              width: statusPillRow.implicitWidth + Style.space(16)
              radius: root.pillRadius
              anchors.verticalCenter: searchTrailing.verticalCenter
              color: root.subtleSurface
              border.width: 1
              border.color: root.subtleSurfaceBorder

              Row {
                id: statusPillRow
                anchors.centerIn: statusPill
                spacing: Style.space(6)

                Rectangle {
                  id: scanPulse
                  visible: root.isScanning
                  width: Style.space(6)
                  height: Style.space(6)
                  radius: width / 2
                  anchors.verticalCenter: statusPillRow.verticalCenter
                  color: root.accentColor

                  SequentialAnimation on opacity {
                    running: root.isScanning && !Style.reduceMotion
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.3; duration: 550; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: 0.3; to: 1.0; duration: 550; easing.type: Easing.InOutQuad }
                  }
                }

                Text {
                  anchors.verticalCenter: statusPillRow.verticalCenter
                  textFormat: Text.PlainText
                  text: statusPill.badgeText
                  color: root.secondaryForeground
                  font.family: root.uiFont
                  font.pixelSize: Math.max(11, Math.round(root.styleFont.bodySmall))
                  font.weight: Font.Medium
                }
              }
            }

            // Quiet filter trigger to open Visible Groups checklist.
            Rectangle {
              id: groupsToggleButton
              width: Style.space(26)
              height: Style.space(24)
              radius: root.pillRadius
              anchors.verticalCenter: searchTrailing.verticalCenter
              color: groupsToggleMouse.containsMouse ? root.subtleSurfaceHover : root.subtleSurface
              border.width: 1
              border.color: root.disabledKinds.length > 0
                ? Util.alpha(root.accentColor, 0.38) : root.subtleSurfaceBorder
              Behavior on color { ColorAnimation { duration: Style.duration(90) } }

              Text {
                anchors.centerIn: groupsToggleButton
                textFormat: Text.PlainText
                text: "\uf1de"
                color: groupsToggleMouse.containsMouse || root.disabledKinds.length > 0
                  ? root.foreground : root.tertiaryForeground
                font.family: root.monoFont
                font.pixelSize: Style.space(11)
              }

              Rectangle {
                visible: root.disabledKinds.length > 0
                width: Style.space(5)
                height: Style.space(5)
                radius: width / 2
                color: root.accentColor
                anchors.top: groupsToggleButton.top
                anchors.right: groupsToggleButton.right
                anchors.topMargin: Style.space(3)
                anchors.rightMargin: Style.space(3)
              }

              MouseArea {
                id: groupsToggleMouse
                anchors.fill: groupsToggleButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.enterPopupMode(root.groupsMode)
              }
            }
          }
        }

        // Full-bleed 1px hairline divider beneath search header.
        Rectangle {
          id: searchDivider
          anchors.top: searchHeader.bottom
          anchors.left: content.left
          anchors.right: content.right
          height: 1
          visible: root.popupMode === root.resultsMode
          color: root.hairlineColor
        }

        // ------------------------------------------------ Empty / Idle State
        Item {
          id: emptyState
          anchors.top: searchDivider.bottom
          anchors.left: content.left
          anchors.right: content.right
          anchors.bottom: footerDivider.top
          visible: root.popupMode === root.resultsMode && root.rankedItems.length === 0

          Column {
            anchors.centerIn: emptyState
            width: Math.min(emptyState.width - Style.space(48), Style.space(380))
            spacing: Style.space(10)

            Rectangle {
              id: emptyMedallion
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(44)
              height: Style.space(44)
              radius: root.innerRadius + Style.space(2)
              color: root.subtleSurface
              border.width: 1
              border.color: root.subtleSurfaceBorder

              Text {
                anchors.centerIn: emptyMedallion
                textFormat: Text.PlainText
                text: root.disabledKinds.length >= root.supportedGroups.length
                  ? "\uf070"
                  : (searchField.text.length > 0 ? "\u{F0349}" : "\uf002")
                color: root.isScanning ? root.accentColor : root.tertiaryForeground
                font.family: root.monoFont
                font.pixelSize: Style.space(18)
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: root.isScanning
                  ? "Scanning workspace…"
                  : (root.disabledKinds.length >= root.supportedGroups.length
                    ? "All groups are hidden"
                    : (searchField.text.length > 0
                      ? ("No results for \u201c" + searchField.text.trim() + "\u201d")
                      : "Nothing open to jump to"))
                color: root.foreground
                font.family: root.uiFont
                font.pixelSize: Style.space(14)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: root.isScanning
                  ? "Discovering windows, browser tabs, terminal sessions, agents, and buffers"
                  : (root.disabledKinds.length >= root.supportedGroups.length
                    ? "Enable one or more source groups to include them in search results"
                    : (searchField.text.length > 0
                      ? "Try matching a window title, workspace, app name, or press Esc to clear"
                      : "Open windows, browser tabs, Ghostty terminals, or Neovim buffers will appear here"))
                color: root.secondaryForeground
                font.family: root.uiFont
                font.pixelSize: Math.max(11, Math.round(root.styleFont.body))
              }
            }

            Rectangle {
              id: emptyActionPill
              visible: root.disabledKinds.length >= root.supportedGroups.length
              anchors.horizontalCenter: parent.horizontalCenter
              height: Style.space(28)
              width: emptyActionLabel.implicitWidth + Style.space(22)
              radius: root.pillRadius
              color: emptyActionMouse.containsMouse
                ? Util.alpha(root.accentColor, 0.24)
                : Util.alpha(root.accentColor, 0.16)
              border.width: 1
              border.color: Util.alpha(root.accentColor, 0.36)
              Behavior on color { ColorAnimation { duration: Style.duration(90) } }

              Text {
                id: emptyActionLabel
                anchors.centerIn: emptyActionPill
                textFormat: Text.PlainText
                text: "Choose Visible Groups"
                color: root.foreground
                font.family: root.uiFont
                font.pixelSize: Math.max(11, Math.round(root.styleFont.body))
                font.weight: Font.Medium
              }

              MouseArea {
                id: emptyActionMouse
                anchors.fill: emptyActionPill
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.enterPopupMode(root.groupsMode)
              }
            }
          }
        }

        // ------------------------------------------------ Scannable Result List
        ListView {
          id: resultList
          objectName: "everything-results"
          anchors.top: searchDivider.bottom
          anchors.topMargin: root.listTopPadding
          anchors.left: content.left
          anchors.right: content.right
          anchors.bottom: footerDivider.top
          anchors.bottomMargin: root.listBottomPadding
          visible: root.popupMode === root.resultsMode && root.rankedItems.length > 0
          enabled: visible
          clip: true
          model: root.rankedItems
          currentIndex: -1
          activeFocusOnTab: count > 0
          boundsBehavior: Flickable.StopAtBounds
          keyNavigationEnabled: false
          highlightMoveDuration: Style.duration(80)
          Accessible.role: Accessible.List
          Accessible.name: "Ranked thing list"
          Accessible.description: "Use Up and Down to select; Left and Right collapse or expand the current group"
          Accessible.focusable: count > 0
          Accessible.focused: resultList.activeFocus

          section.property: "kind"
          section.criteria: ViewSection.FullString
          section.delegate: Item {
            id: sectionHeading
            required property string section
            objectName: "everything-section-" + section
            width: ListView.view ? ListView.view.width : resultList.width
            height: root.sectionHeight
            readonly property bool collapsed: root.groupCollapsed(section)
            readonly property bool highlighted: collapsed
              && (resultList.activeFocus || keyCatcher.activeFocus)
              && root.currentGroupKind() === section
            readonly property int groupCount: Number(root.sectionCounts[section] || 0)

            Accessible.role: Accessible.Heading
            Accessible.name: Model.kindSectionLabel(sectionHeading.section)
              + (sectionHeading.collapsed ? ", collapsed" : ", expanded")
            Accessible.focusable: sectionHeading.collapsed
            Accessible.focused: sectionHeading.highlighted
            Accessible.onPressAction: root.toggleGroupFromHeading(sectionHeading.section)

            Rectangle {
              id: sectionSurface
              anchors.fill: sectionHeading
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(14)
              anchors.topMargin: Style.space(5)
              anchors.bottomMargin: Style.space(1)
              radius: root.tileRadius
              color: sectionHeading.highlighted ? root.selectedRowFill : "transparent"
              border.width: sectionHeading.highlighted ? 1 : 0
              border.color: sectionHeading.highlighted ? root.selectedRowBorder : "transparent"
              Behavior on color { ColorAnimation { duration: Style.duration(90) } }

              Rectangle {
                anchors.left: sectionSurface.left
                anchors.leftMargin: Style.space(3)
                anchors.verticalCenter: sectionSurface.verticalCenter
                width: 2.5
                height: Style.space(12)
                radius: 1.5
                color: root.accentColor
                opacity: sectionHeading.highlighted ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: Style.duration(100) } }
              }

              Text {
                id: sectionDisclosure
                anchors.left: sectionSurface.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: sectionSurface.verticalCenter
                textFormat: Text.PlainText
                text: sectionHeading.collapsed ? "\uf054" : "\uf078"
                color: sectionHeading.highlighted
                  ? root.secondaryForeground : root.tertiaryForeground
                font.family: root.monoFont
                font.pixelSize: Style.space(9)
                Behavior on color { ColorAnimation { duration: Style.duration(90) } }
              }

              Text {
                anchors.left: sectionDisclosure.right
                anchors.leftMargin: Style.space(7)
                anchors.right: sectionCountLabel.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: sectionSurface.verticalCenter
                textFormat: Text.PlainText
                text: Model.kindSectionLabel(sectionHeading.section).toUpperCase()
                color: sectionHeading.highlighted
                  ? root.foreground : root.tertiaryForeground
                font.family: root.uiFont
                font.pixelSize: Math.max(10, Math.round(root.styleFont.caption))
                font.weight: Font.DemiBold
                font.letterSpacing: 0.9
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: Style.duration(90) } }
              }

              Text {
                id: sectionCountLabel
                anchors.right: sectionSurface.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: sectionSurface.verticalCenter
                textFormat: Text.PlainText
                text: sectionHeading.collapsed
                  ? (sectionHeading.groupCount + " hidden")
                  : String(sectionHeading.groupCount)
                color: Util.alpha(root.foreground, root.isDarkSurface ? 0.34 : 0.42)
                font.family: root.uiFont
                font.pixelSize: Math.max(10, Math.round(root.styleFont.caption))
                font.weight: Font.Medium
              }
            }

            MouseArea {
              id: sectionMouse
              anchors.fill: sectionHeading
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleGroupFromHeading(sectionHeading.section)
            }
          }

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) { root.handleSupplementalListKey(event) }
          onCountChanged: {
            if (!root.resultUpdateInProgress) {
              if (count <= 0) root.setCurrentIndex(-1, false)
              else if (currentIndex < 0) root.setCurrentIndex(0, false)
              else if (currentIndex >= count) root.setCurrentIndex(count - 1, false)
            }
          }

          ScrollBar.vertical: ScrollBar {
            id: resultsScrollBar
            objectName: "everything-scrollbar"
            policy: ScrollBar.AsNeeded
            width: Style.space(8)
            rightPadding: Style.space(3)
            background: Item {}
            contentItem: Rectangle {
              visible: resultsScrollBar.size < 0.999
              implicitWidth: Style.space(3)
              radius: Style.space(2)
              color: Util.alpha(root.foreground, resultsScrollBar.pressed
                ? 0.46 : (resultsScrollBar.hovered ? 0.30 : 0.16))
              Behavior on color { ColorAnimation { duration: Style.duration(120) } }
            }
          }

          delegate: Item {
            id: row
            required property var modelData
            required property int index
            width: resultList.width
            height: groupCollapsed ? 0 : root.rowHeight
            visible: !groupCollapsed
            enabled: !groupCollapsed
            readonly property bool groupCollapsed: root.groupCollapsed(modelData.kind)
            readonly property bool highlighted: !groupCollapsed && (root.pointerCursorActive
                || resultList.activeFocus || keyCatcher.activeFocus)
              && resultList.currentIndex === index
            readonly property bool isDefaultSelection: !groupCollapsed
              && !highlighted && searchField.activeFocus
              && resultList.currentIndex === index
            readonly property bool selectedVisual: highlighted || isDefaultSelection
            readonly property string crumb: root.breadcrumb(modelData)
            readonly property string metadata: Model.metadataForItem(
              modelData, root.itemRelations)
            readonly property string subtitleText: root.rowSubtitle(
              modelData, crumb, metadata)
            readonly property string kindPillText: root.shortKindBadge(modelData.kind)
            readonly property string tone: root.statusTone(modelData, metadata)
            readonly property var windowEntry: root.resolveWindowDesktopEntry(modelData)
            readonly property string windowAppGlyph: Model.windowAppGlyph(modelData, windowEntry)
            readonly property string windowIconSource: windowAppGlyph.length === 0
              ? root.windowIconSource(modelData, windowEntry) : ""

            Accessible.role: Accessible.ListItem
            Accessible.name: String(modelData.title || "Untitled")
            Accessible.description: [String(modelData.provider || ""), Model.kindLabel(modelData.kind)]
              .concat(Array.isArray(modelData.badges) ? modelData.badges : [])
              .concat(modelData.active === true ? ["Current thing"] : [])
              .concat(crumb ? [crumb] : [])
              .filter(function(value) { return value.length > 0 }).join(", ")
            Accessible.selectable: true
            Accessible.selected: row.highlighted
            Accessible.focusable: true
            Accessible.focused: row.highlighted
            Accessible.onPressAction: root.activateAt(row.index)

            // Frosted floating row highlight capsule + refined 2.5px left accent rail.
            Rectangle {
              id: rowSurface
              anchors.fill: row
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(14)
              anchors.topMargin: Style.space(2)
              anchors.bottomMargin: Style.space(2)
              radius: root.innerRadius
              color: row.highlighted
                ? root.selectedRowFill
                : (row.isDefaultSelection ? root.selectedRowSubtleFill : "transparent")
              border.width: row.selectedVisual ? 1 : 0
              border.color: row.selectedVisual ? root.selectedRowBorder : "transparent"

              Behavior on color { ColorAnimation { duration: Style.duration(90) } }
              Behavior on border.color { ColorAnimation { duration: Style.duration(90) } }

              Rectangle {
                id: accentRail
                anchors.left: rowSurface.left
                anchors.leftMargin: Style.space(3)
                anchors.verticalCenter: rowSurface.verticalCenter
                width: 2.5
                height: Style.space(20)
                radius: 1.5
                color: root.accentColor
                opacity: row.highlighted ? 1.0 : (row.isDefaultSelection ? 0.65 : 0.0)
                Behavior on opacity { NumberAnimation { duration: Style.duration(110) } }
              }

              // Pure rounded frosted icon tile (32x32).
              Rectangle {
                id: thingIcon
                anchors.left: rowSurface.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: rowSurface.verticalCenter
                width: Style.space(32)
                height: Style.space(32)
                radius: root.tileRadius
                color: row.selectedVisual ? root.selectedIconTileFill : root.subtleSurface
                border.width: 1
                border.color: row.selectedVisual
                  ? root.selectedIconTileBorder : root.subtleSurfaceBorder
                Accessible.role: Accessible.Graphic
                Accessible.name: Model.kindLabel(row.modelData.kind) + " icon"

                Behavior on color { ColorAnimation { duration: Style.duration(100) } }
                Behavior on border.color { ColorAnimation { duration: Style.duration(100) } }

                Image {
                  id: applicationIcon
                  objectName: "everything-window-icon-" + row.index
                  anchors.centerIn: thingIcon
                  width: Style.space(18)
                  height: width
                  visible: row.windowAppGlyph.length === 0
                    && row.windowIconSource.length > 0 && status !== Image.Error
                  source: row.windowIconSource
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  smooth: true
                  sourceSize.width: width
                  sourceSize.height: height
                  layer.enabled: visible
                  layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: row.selectedVisual
                      ? root.foreground : root.secondaryForeground
                  }
                }

                OpticalGlyph {
                  id: mappedWindowGlyph
                  objectName: "everything-window-glyph-" + row.index
                  anchors.fill: thingIcon
                  anchors.margins: Style.space(5)
                  visible: row.windowAppGlyph.length > 0
                  text: row.windowAppGlyph
                  color: row.selectedVisual ? root.foreground : root.secondaryForeground
                  fontFamily: root.monoFont
                  fontSize: Style.space(16)
                }

                Text {
                  id: fallbackThingIcon
                  anchors.fill: thingIcon
                  visible: row.windowAppGlyph.length === 0 && !applicationIcon.visible
                  textFormat: Text.PlainText
                  text: Model.kindIcon(row.modelData.kind)
                  color: row.selectedVisual ? root.foreground : root.secondaryForeground
                  font.family: root.monoFont
                  font.pixelSize: Style.space(15)
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                }
              }

              // Two-line typography hierarchy: bold Inter Display title + quiet subtitle.
              Column {
                id: textColumn
                anchors.left: thingIcon.right
                anchors.leftMargin: Style.space(12)
                anchors.right: trailingCluster.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: rowSurface.verticalCenter
                spacing: Style.space(2)

                Text {
                  id: titleLabel
                  width: textColumn.width
                  textFormat: Text.PlainText
                  text: String(row.modelData.title || "Untitled")
                  color: root.foreground
                  font.family: root.uiFont
                  font.pixelSize: Math.max(13, Math.round(root.styleFont.title))
                  font.weight: row.selectedVisual ? Font.DemiBold : Font.Medium
                  elide: Text.ElideRight
                }

                Row {
                  id: subtitleRow
                  width: textColumn.width
                  visible: row.subtitleText.length > 0
                  spacing: Style.space(6)

                  Rectangle {
                    visible: row.tone !== "neutral" || row.modelData.active === true
                    width: Style.space(5)
                    height: Style.space(5)
                    radius: width / 2
                    anchors.verticalCenter: subtitleRow.verticalCenter
                    color: row.tone === "urgent" ? root.urgentColor : root.accentColor
                  }

                  Text {
                    id: subtitleLabel
                    objectName: "everything-metadata-" + row.index
                    width: Math.max(0, subtitleRow.width
                      - ((row.tone !== "neutral" || row.modelData.active === true) ? Style.space(11) : 0))
                    textFormat: Text.PlainText
                    text: row.subtitleText
                    color: row.selectedVisual
                      ? Util.alpha(root.foreground, root.isDarkSurface ? 0.72 : 0.74)
                      : root.secondaryForeground
                    font.family: root.uiFont
                    font.pixelSize: Math.max(11, Math.round(root.styleFont.bodySmall))
                    font.weight: Font.Normal
                    elide: Text.ElideMiddle
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                  }
                }
              }

              // Right-aligned subtle source pill badge + return cue on selection.
              Row {
                id: trailingCluster
                anchors.right: rowSurface.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: rowSurface.verticalCenter
                spacing: Style.space(6)

                Rectangle {
                  id: sourcePill
                  height: Style.space(22)
                  width: sourcePillLabel.implicitWidth + Style.space(14)
                  radius: root.pillRadius
                  anchors.verticalCenter: trailingCluster.verticalCenter
                  color: row.selectedVisual
                    ? Util.alpha(root.foreground, root.isDarkSurface ? 0.10 : 0.075)
                    : root.subtleSurface
                  border.width: 1
                  border.color: row.selectedVisual
                    ? Util.alpha(root.foreground, root.isDarkSurface ? 0.16 : 0.13)
                    : root.subtleSurfaceBorder
                  Behavior on color { ColorAnimation { duration: Style.duration(90) } }

                  Text {
                    id: sourcePillLabel
                    anchors.centerIn: sourcePill
                    textFormat: Text.PlainText
                    text: row.kindPillText
                    color: row.selectedVisual ? root.foreground : root.tertiaryForeground
                    font.family: root.uiFont
                    font.pixelSize: Math.max(10, Math.round(root.styleFont.caption))
                    font.weight: Font.Medium
                  }
                }

                Rectangle {
                  id: returnCue
                  visible: row.selectedVisual
                  width: Style.space(22)
                  height: Style.space(22)
                  radius: root.pillRadius
                  anchors.verticalCenter: trailingCluster.verticalCenter
                  color: Util.alpha(root.accentColor, root.isDarkSurface ? 0.22 : 0.14)
                  border.width: 1
                  border.color: Util.alpha(root.accentColor, root.isDarkSurface ? 0.42 : 0.34)

                  Text {
                    anchors.centerIn: returnCue
                    textFormat: Text.PlainText
                    text: "\u21B5"
                    color: root.foreground
                    font.family: root.monoFont
                    font.pixelSize: Math.max(10, Math.round(root.styleFont.caption))
                    font.weight: Font.DemiBold
                  }
                }
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: row
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectFromPointer(row.index, row, {
                x: rowMouse.mouseX,
                y: rowMouse.mouseY
              })
              onPositionChanged: function(mouse) {
                root.selectFromPointer(row.index, row, mouse)
              }
              onClicked: {
                root.setCurrentIndex(row.index, false)
                root.pointerCursorActive = true
                root.activateAt(row.index)
              }
            }
          }
        }

        // ------------------------------------------------ Visible Groups Mode
        Item {
          id: groupsHeader
          anchors.top: content.top
          anchors.left: content.left
          anchors.right: content.right
          height: root.groupsHeaderHeight
          visible: root.popupMode === root.groupsMode

          Column {
            anchors.left: groupsHeader.left
            anchors.leftMargin: Style.space(18)
            anchors.right: backToResultsPill.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: groupsHeader.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Visible Groups"
              color: root.foreground
              font.family: root.uiFont
              font.pixelSize: Style.space(15)
              font.weight: Font.DemiBold
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Choose which sources appear in Everything search"
              color: root.secondaryForeground
              font.family: root.uiFont
              font.pixelSize: Math.max(11, Math.round(root.styleFont.bodySmall))
              elide: Text.ElideRight
            }
          }

          Rectangle {
            id: backToResultsPill
            anchors.right: groupsHeader.right
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: groupsHeader.verticalCenter
            height: Style.space(26)
            width: backToResultsLabel.implicitWidth + Style.space(18)
            radius: root.pillRadius
            color: backToResultsMouse.containsMouse ? root.subtleSurfaceHover : root.subtleSurface
            border.width: 1
            border.color: root.subtleSurfaceBorder
            Behavior on color { ColorAnimation { duration: Style.duration(90) } }

            Text {
              id: backToResultsLabel
              anchors.centerIn: backToResultsPill
              textFormat: Text.PlainText
              text: "\u2190 Results"
              color: backToResultsMouse.containsMouse ? root.foreground : root.secondaryForeground
              font.family: root.uiFont
              font.pixelSize: Math.max(11, Math.round(root.styleFont.bodySmall))
              font.weight: Font.Medium
            }

            MouseArea {
              id: backToResultsMouse
              anchors.fill: backToResultsPill
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.enterPopupMode(root.resultsMode)
            }
          }
        }

        Rectangle {
          id: groupsRule
          anchors.top: groupsHeader.bottom
          anchors.left: content.left
          anchors.right: content.right
          height: 1
          visible: groupsHeader.visible
          color: root.hairlineColor
        }

        ListView {
          id: groupList
          objectName: "everything-groups"
          anchors.top: groupsRule.bottom
          anchors.topMargin: root.listTopPadding
          anchors.left: content.left
          anchors.right: content.right
          anchors.bottom: footerDivider.top
          anchors.bottomMargin: root.listBottomPadding
          visible: root.popupMode === root.groupsMode
          enabled: visible
          clip: true
          model: root.supportedGroups
          currentIndex: 0
          activeFocusOnTab: true
          boundsBehavior: Flickable.StopAtBounds
          keyNavigationEnabled: false
          highlightMoveDuration: Style.duration(80)
          Accessible.role: Accessible.List
          Accessible.name: "Visible thing groups"
          Accessible.description: "Checked groups appear in Everything search results"
          Accessible.focusable: true
          Accessible.focused: groupList.activeFocus

          ScrollBar.vertical: ScrollBar {
            id: groupsScrollBar
            policy: ScrollBar.AsNeeded
            width: Style.space(8)
            rightPadding: Style.space(3)
            background: Item {}
            contentItem: Rectangle {
              visible: groupsScrollBar.size < 0.999
              implicitWidth: Style.space(3)
              radius: Style.space(2)
              color: Util.alpha(root.foreground, groupsScrollBar.pressed
                ? 0.46 : (groupsScrollBar.hovered ? 0.30 : 0.16))
              Behavior on color { ColorAnimation { duration: Style.duration(120) } }
            }
          }

          delegate: Item {
            id: groupRow
            required property var modelData
            required property int index
            objectName: "everything-group-" + modelData.kind
            width: groupList.width
            height: root.groupChecklistRowHeight
            readonly property bool checked: !root.kindDisabled(modelData.kind)
            readonly property bool highlighted: groupList.currentIndex === index
              && (groupList.activeFocus || keyCatcher.activeFocus)

            function activate() {
              root.setGroupChecklistIndex(index)
              groupList.forceActiveFocus()
              root.toggleKindVisibility(modelData.kind)
            }

            Accessible.role: Accessible.CheckBox
            Accessible.name: modelData.sectionLabel
            Accessible.description: checked
              ? "Shown in Everything search results" : "Hidden from Everything search results"
            Accessible.checkable: true
            Accessible.checked: groupRow.checked
            Accessible.focusable: true
            Accessible.focused: groupRow.highlighted
            Accessible.onPressAction: groupRow.activate()
            Accessible.onToggleAction: groupRow.activate()

            Rectangle {
              id: groupRowSurface
              anchors.fill: groupRow
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(14)
              anchors.topMargin: Style.space(2)
              anchors.bottomMargin: Style.space(2)
              radius: root.innerRadius
              color: groupRow.highlighted ? root.selectedRowFill : "transparent"
              border.width: groupRow.highlighted ? 1 : 0
              border.color: groupRow.highlighted ? root.selectedRowBorder : "transparent"
              Behavior on color { ColorAnimation { duration: Style.duration(90) } }

              Rectangle {
                anchors.left: groupRowSurface.left
                anchors.leftMargin: Style.space(3)
                anchors.verticalCenter: groupRowSurface.verticalCenter
                width: 2.5
                height: Style.space(16)
                radius: 1.5
                color: root.accentColor
                opacity: groupRow.highlighted ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: Style.duration(100) } }
              }

              Rectangle {
                id: groupIconTile
                anchors.left: groupRowSurface.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: groupRowSurface.verticalCenter
                width: Style.space(26)
                height: Style.space(26)
                radius: root.tileRadius
                color: groupRow.checked
                  ? (groupRow.highlighted ? root.selectedIconTileFill : root.subtleSurface)
                  : "transparent"
                border.width: 1
                border.color: groupRow.checked
                  ? (groupRow.highlighted ? root.selectedIconTileBorder : root.subtleSurfaceBorder)
                  : Util.alpha(root.foreground, 0.06)

                Text {
                  anchors.centerIn: groupIconTile
                  textFormat: Text.PlainText
                  text: groupRow.modelData.icon
                  color: groupRow.checked ? root.foreground : root.tertiaryForeground
                  font.family: root.monoFont
                  font.pixelSize: Style.space(13)
                }
              }

              Text {
                anchors.left: groupIconTile.right
                anchors.leftMargin: Style.space(12)
                anchors.right: toggleTrack.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: groupRowSurface.verticalCenter
                textFormat: Text.PlainText
                text: groupRow.modelData.sectionLabel
                color: groupRow.checked ? root.foreground : root.tertiaryForeground
                font.family: root.uiFont
                font.pixelSize: Math.max(13, Math.round(root.styleFont.subtitle))
                font.weight: groupRow.checked ? Font.Medium : Font.Normal
                elide: Text.ElideRight
              }

              // Tactile macOS-style pill toggle switch.
              Rectangle {
                id: toggleTrack
                anchors.right: groupRowSurface.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: groupRowSurface.verticalCenter
                width: Style.space(34)
                height: Style.space(20)
                radius: height / 2
                color: groupRow.checked
                  ? root.accentColor
                  : (root.isDarkSurface ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.14))
                Behavior on color { ColorAnimation { duration: Style.duration(130) } }

                Rectangle {
                  width: Style.space(16)
                  height: Style.space(16)
                  radius: width / 2
                  anchors.verticalCenter: toggleTrack.verticalCenter
                  x: groupRow.checked
                    ? toggleTrack.width - width - Style.space(2) : Style.space(2)
                  color: "#ffffff"
                  Behavior on x {
                    NumberAnimation {
                      duration: Style.duration(130)
                      easing.type: Easing.Bezier
                      easing.bezierCurve: Style.easeOut
                    }
                  }
                }
              }
            }

            MouseArea {
              id: groupMouse
              objectName: "everything-group-pointer-" + groupRow.modelData.kind
              anchors.fill: groupRow
              cursorShape: Qt.PointingHandCursor
              onClicked: groupRow.activate()
            }
          }
        }

        // ------------------------------------------------ Refined Action Footer
        Rectangle {
          id: footerDivider
          anchors.bottom: footerBar.top
          anchors.left: content.left
          anchors.right: content.right
          height: 1
          color: root.hairlineColor
        }

        Item {
          id: footerBar
          anchors.bottom: content.bottom
          anchors.left: content.left
          anchors.right: content.right
          height: root.footerHeight
          clip: true

          // Bottom-only concentric rounded backdrop inside the glass capsule.
          Rectangle {
            anchors.left: footerBar.left
            anchors.right: footerBar.right
            anchors.bottom: footerBar.bottom
            height: footerBar.height + root.cardInnerRadius
            radius: root.cardInnerRadius
            color: root.footerFill
          }

          Row {
            id: footerContextRow
            anchors.left: footerBar.left
            anchors.leftMargin: Style.space(18)
            anchors.right: footerHints.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: footerBar.verticalCenter
            spacing: Style.space(7)

            Rectangle {
              width: Style.space(6)
              height: Style.space(6)
              radius: width / 2
              anchors.verticalCenter: footerContextRow.verticalCenter
              color: root.accentColor
              opacity: root.activeItem || root.popupMode === root.groupsMode ? 0.9 : 0.45
            }

            Text {
              width: Math.max(0, footerContextRow.width - Style.space(13))
              anchors.verticalCenter: footerContextRow.verticalCenter
              textFormat: Text.PlainText
              text: root.activeFooterContext()
              color: root.secondaryForeground
              font.family: root.uiFont
              font.pixelSize: Math.max(11, Math.round(root.styleFont.bodySmall))
              font.weight: Font.Medium
              elide: Text.ElideRight
            }
          }

          Row {
            id: footerHints
            anchors.right: footerBar.right
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: footerBar.verticalCenter
            spacing: Style.space(12)

            KeycapHint {
              visible: root.popupMode === root.resultsMode && root.rankedItems.length > 0
              keyLabel: "\u21B5"
              actionLabel: root.groupCollapsed(root.currentGroupKind()) ? "Expand" : "Open"
              emphasized: true
            }

            KeycapHint {
              visible: root.popupMode === root.groupsMode
              keyLabel: "\u21B5"
              actionLabel: "Toggle"
              emphasized: true
            }

            KeycapHint {
              visible: root.popupMode === root.resultsMode && root.rankedItems.length > 0
              keyLabel: "\u2191\u2009\u2193"
              actionLabel: "Move"
            }

            KeycapHint {
              visible: root.popupMode === root.groupsMode
              keyLabel: "\u2191\u2009\u2193"
              actionLabel: "Move"
            }

            KeycapHint {
              visible: root.popupMode === root.resultsMode && root.rankedItems.length > 0
                && !searchField.activeFocus
              keyLabel: "\u2190\u2009\u2192"
              actionLabel: "Fold"
            }

            KeycapHint {
              visible: root.popupMode === root.resultsMode && root.rankedItems.length > 0
                && searchField.activeFocus
              keyLabel: "\u21E5"
              actionLabel: "Browse"
            }

            KeycapHint {
              keyLabel: "Esc"
              actionLabel: root.popupMode === root.resultsMode && searchField.text.length > 0
                ? "Clear" : "Close"
            }
          }
        }
      }
    }
  }
}
