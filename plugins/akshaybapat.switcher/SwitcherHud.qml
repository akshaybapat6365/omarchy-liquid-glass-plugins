pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Self-contained Apple-grade Liquid Glass Window & App Switcher HUD.
// Mounted inside OverlayWindow by Switcher.qml and directly renderable offscreen for visual QA.
Item {
  id: hud

  property var windows: []
  property bool sameApp: false
  property string activeAppName: ""
  property string searchQuery: ""
  property bool searchArmed: false
  property int selectedIndex: 0
  property bool reduceMotion: false
  property real maxAvailableWidth: 1440

  property color glassTint: Qt.rgba(16 / 255, 18 / 255, 25 / 255, 0.86)
  property color accentColor: "#7176b8"
  property color foregroundColor: "#F0F5FF"
  property color mutedColor: "#94A3B8"

  // Hold-Alt-Release-to-Switch state tracked on keyboard focus.
  property bool altSeenHeld: false
  property bool openedViaStep: false

  // Prevent stationary mouse cursor under the newly mapped HUD from stealing selection.
  property int hoveredIndex: -1
  property bool pointerMovedSinceOpen: false

  signal requestFocus(string address)
  signal requestCloseWindow(string address)
  signal requestHideWindow(string address)
  signal requestDismiss()

  readonly property color accentBright: Qt.rgba(
    Math.min(1.0, accentColor.r * 1.28 + 0.22),
    Math.min(1.0, accentColor.g * 1.28 + 0.24),
    Math.min(1.0, accentColor.b * 1.28 + 0.28),
    1.0
  )

  readonly property int cardSize: 146
  readonly property int cardSpacing: 12
  readonly property int hudPadX: 22
  readonly property int railPadX: 10
  readonly property int railPadY: 12

  readonly property var filteredWindows: {
    var list = hud.windows || []
    var q = String(hud.searchQuery || "").trim().toLowerCase()
    if (!q) return list
    var out = []
    for (var i = 0; i < list.length; i++) {
      var w = list[i]
      if (!w) continue
      var hay = (
        String(w.appName || "") + " " +
        String(w.title || "") + " " +
        String(w["class"] || "") + " " +
        String(w.workspaceLabel || "")
      ).toLowerCase()
      if (hay.indexOf(q) >= 0) out.push(w)
    }
    return out
  }

  readonly property int itemCount: filteredWindows.length
  readonly property int safeSelectedIndex: itemCount > 0
    ? Math.max(0, Math.min(itemCount - 1, selectedIndex))
    : -1
  readonly property var selectedWindow: safeSelectedIndex >= 0
    ? filteredWindows[safeSelectedIndex]
    : null

  readonly property int maxHudWidth: Math.max(620, Math.floor(maxAvailableWidth * 0.88))
  readonly property int minHudWidth: 620
  readonly property int maxVisibleCards: Math.max(
    1,
    Math.min(7, Math.floor((maxHudWidth - hudPadX * 2 - railPadX * 2 + cardSpacing) / (cardSize + cardSpacing)))
  )
  readonly property int visibleCardCount: Math.max(1, Math.min(maxVisibleCards, Math.max(1, itemCount)))
  readonly property int contentRailWidth: itemCount > 0
    ? (itemCount * cardSize + Math.max(0, itemCount - 1) * cardSpacing)
    : 0
  readonly property int idealRailViewportWidth: visibleCardCount * cardSize
    + Math.max(0, visibleCardCount - 1) * cardSpacing
    + railPadX * 2

  readonly property bool expandedLegend: width >= 760
  readonly property bool needsScroll: itemCount > maxVisibleCards

  implicitWidth: Math.min(maxHudWidth, Math.max(minHudWidth, idealRailViewportWidth + hudPadX * 2))
  implicitHeight: 298
  width: implicitWidth
  height: implicitHeight
  focus: true

  // Normalized X center (0..1) of the active card within the full glass capsule,
  // smoothly steering the overhead Fresnel accent caustic in glass_switcher.frag.
  readonly property real targetFocusX: {
    if (itemCount <= 0 || safeSelectedIndex < 0 || width <= 0) return 0.5
    var listLeft = railViewport.x + cardList.x
    // Note: Qt ListView starts contentX at -leftMargin, so subtracting contentX
    // already includes leftMargin cleanly without double-counting.
    var cardCenter = listLeft
      + safeSelectedIndex * (cardSize + cardSpacing)
      + cardSize * 0.5
      - cardList.contentX
    return Math.max(0.08, Math.min(0.92, cardCenter / width))
  }
  property real animatedFocusX: targetFocusX

  Behavior on animatedFocusX {
    enabled: !hud.reduceMotion
    NumberAnimation {
      duration: 185
      easing.type: Easing.OutQuart
    }
  }
  onTargetFocusXChanged: animatedFocusX = targetFocusX

  function resetSession(stepDelta, isStepOpen) {
    searchQuery = ""
    searchArmed = false
    hoveredIndex = -1
    pointerMovedSinceOpen = false
    altSeenHeld = false
    openedViaStep = !!isStepOpen
    selectInitial(stepDelta)
  }

  function selectInitial(stepDelta) {
    var count = filteredWindows.length
    if (count <= 0) {
      selectedIndex = 0
      return
    }
    if (stepDelta < 0) {
      selectedIndex = count - 1
    } else if (stepDelta > 0) {
      selectedIndex = count > 1 ? 1 : 0
    } else {
      selectedIndex = 0
    }
    ensureSelectedVisible()
  }

  function stepSelection(delta) {
    var count = filteredWindows.length
    if (count <= 0) {
      selectedIndex = 0
      return
    }
    var cur = Math.max(0, Math.min(count - 1, selectedIndex))
    var next = (cur + delta) % count
    if (next < 0) next += count
    selectedIndex = next
    ensureSelectedVisible()
  }

  function ensureSelectedVisible() {
    if (safeSelectedIndex >= 0 && cardList.count > safeSelectedIndex) {
      cardList.positionViewAtIndex(safeSelectedIndex, ListView.Contain)
    }
  }

  function confirmSelected() {
    var win = selectedWindow
    if (!win || !win.address) {
      requestDismiss()
      return
    }
    requestFocus(String(win.address))
  }

  function closeHighlighted() {
    var win = selectedWindow
    if (!win || !win.address) return
    var addr = String(win.address)
    var updated = []
    var list = hud.windows || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && String(list[i].address) !== addr) updated.push(list[i])
    }
    hud.windows = updated
    if (hud.filteredWindows.length === 0) {
      selectedIndex = 0
    } else if (selectedIndex >= hud.filteredWindows.length) {
      selectedIndex = hud.filteredWindows.length - 1
    }
    requestCloseWindow(addr)
  }

  function hideHighlighted() {
    var win = selectedWindow
    if (!win || !win.address) return
    var addr = String(win.address)
    var updated = []
    var list = hud.windows || []
    for (var i = 0; i < list.length; i++) {
      var item = list[i]
      if (!item) continue
      if (String(item.address) === addr) {
        var copy = Object.assign({}, item, {
          minimized: true,
          focused: false,
          workspaceLabel: "Shelf"
        })
        updated.push(copy)
      } else {
        updated.push(item)
      }
    }
    hud.windows = updated
    requestHideWindow(addr)
  }

  function clearFilter() {
    searchQuery = ""
    searchArmed = false
    selectedIndex = Math.min(selectedIndex, Math.max(0, filteredWindows.length - 1))
  }

  function formatIconUrl(rawPath) {
    var p = String(rawPath || "")
    if (!p) return ""
    if (p.indexOf("file://") === 0 || p.indexOf("image://") === 0) return p
    return "file://" + p.replace(/%/g, "%25").replace(/#/g, "%23").replace(/\?/g, "%3F").replace(/ /g, "%20")
  }

  Keys.onPressed: function(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0

    if (event.key === Qt.Key_Alt || alt) {
      hud.altSeenHeld = true
    }

    if (event.key === Qt.Key_Escape) {
      if (hud.searchQuery.length > 0 || hud.searchArmed) {
        hud.clearFilter()
      } else {
        hud.openedViaStep = false
        hud.altSeenHeld = false
        hud.requestDismiss()
      }
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Tab) {
      hud.stepSelection(shift ? -1 : 1)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Backtab) {
      hud.stepSelection(-1)
      event.accepted = true
      return
    }

    if ((event.key === Qt.Key_QuoteLeft || event.key === Qt.Key_AsciiTilde) && alt) {
      hud.stepSelection(shift ? -1 : 1)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
      hud.stepSelection(1)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
      hud.stepSelection(-1)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Home) {
      hud.selectedIndex = 0
      hud.ensureSelectedVisible()
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_End) {
      hud.selectedIndex = Math.max(0, hud.itemCount - 1)
      hud.ensureSelectedVisible()
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      hud.confirmSelected()
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Space) {
      if (hud.searchQuery.length === 0 && !hud.searchArmed) {
        hud.confirmSelected()
      } else {
        hud.searchQuery = hud.searchQuery + " "
        hud.selectedIndex = 0
      }
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Backspace) {
      if (hud.searchQuery.length > 0) {
        hud.searchQuery = hud.searchQuery.slice(0, -1)
        if (hud.searchQuery.length === 0) hud.searchArmed = false
        hud.selectedIndex = 0
      } else if (hud.searchArmed) {
        hud.searchArmed = false
      }
      event.accepted = true
      return
    }

    // Power actions on highlighted card when search query is empty.
    if (hud.searchQuery.length === 0 && !hud.searchArmed && !ctrl) {
      if (event.key === Qt.Key_Delete || event.key === Qt.Key_Q) {
        hud.closeHighlighted()
        event.accepted = true
        return
      }
      if (event.key === Qt.Key_H) {
        hud.hideHighlighted()
        event.accepted = true
        return
      }
      if (event.text === "/") {
        hud.searchArmed = true
        event.accepted = true
        return
      }
    }

    // Live type-to-filter for printable characters.
    if (!ctrl && !alt && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32) {
      hud.searchQuery = hud.searchQuery + event.text
      hud.selectedIndex = 0
      event.accepted = true
      return
    }
  }

  Keys.onReleased: function(event) {
    if (event.key === Qt.Key_Alt) {
      var shouldCommit = (hud.openedViaStep || hud.altSeenHeld)
        && hud.searchQuery.length === 0
        && !hud.searchArmed
      hud.altSeenHeld = false
      hud.openedViaStep = false
      if (shouldCommit) {
        hud.confirmSelected()
        event.accepted = true
      }
    }
  }

  // Soft ambient drop shadow beneath the floating Liquid Glass capsule.
  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: -6
    anchors.rightMargin: -6
    anchors.topMargin: 6
    anchors.bottomMargin: -14
    radius: 32
    color: Qt.rgba(0, 0, 0, 0.34)
    z: -2
  }

  // Compiled Qt 6.12 optical Liquid Glass capsule shader.
  ShaderEffect {
    id: glassShader
    anchors.fill: parent
    property vector2d iResolution: Qt.vector2d(Math.max(4, width), Math.max(4, height))
    property color tintColor: hud.glassTint
    property color accentColor: hud.accentColor
    property real cornerRadius: 26.0
    property real focusX: hud.animatedFocusX
    property real causticStrength: hud.itemCount > 0 ? 1.0 : 0.35
    fragmentShader: Qt.resolvedUrl("shaders/glass_switcher.frag.qsb")
  }

  // Graceful fallback frame if shader fails to compile on software GL.
  Rectangle {
    anchors.fill: parent
    visible: glassShader.status !== ShaderEffect.Compiled
    radius: 26
    color: hud.glassTint
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.22)
  }

  // Swallow clicks inside the HUD so they never trigger backdrop dismissal.
  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onPositionChanged: hud.pointerMovedSinceOpen = true
    onClicked: {}
  }

  // =========================================================================
  // 1. TOP HEADER STRIP: mode badge, live count, optional filter chip, legend
  // =========================================================================
  Item {
    id: headerBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: hud.hudPadX
    anchors.rightMargin: hud.hudPadX
    anchors.topMargin: 15
    height: 30

    // Left cluster: mode pill + window count + optional active filter chip.
    Row {
      id: leftCluster
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8

      // Mode badge pill.
      Rectangle {
        height: 26
        width: modeRow.implicitWidth + 18
        radius: 13
        anchors.verticalCenter: parent.verticalCenter
        color: hud.sameApp
          ? Qt.rgba(hud.accentColor.r, hud.accentColor.g, hud.accentColor.b, 0.24)
          : Qt.rgba(1, 1, 1, 0.068)
        border.width: 1
        border.color: hud.sameApp
          ? Qt.rgba(hud.accentBright.r, hud.accentBright.g, hud.accentBright.b, 0.56)
          : Qt.rgba(1, 1, 1, 0.13)

        Row {
          id: modeRow
          anchors.centerIn: parent
          spacing: 6

          Rectangle {
            width: 6
            height: 6
            radius: 3
            anchors.verticalCenter: parent.verticalCenter
            color: hud.sameApp ? hud.accentBright : Qt.rgba(hud.accentBright.r, hud.accentBright.g, hud.accentBright.b, 0.85)
          }

          Text {
            textFormat: Text.PlainText
            text: hud.sameApp
              ? ("Same App" + (hud.activeAppName ? (" · " + hud.activeAppName) : ""))
              : "All Windows"
            font.family: "Inter"
            font.weight: Font.DemiBold
            font.pixelSize: 12
            color: "#F3F7FF"
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }

      // Live window count pill.
      Rectangle {
        height: 24
        width: countText.implicitWidth + 16
        radius: 12
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(1, 1, 1, 0.045)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.09)

        Text {
          id: countText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: {
            var total = (hud.windows || []).length
            if (hud.searchQuery.length > 0) {
              return hud.itemCount + " of " + total
            }
            return total === 1 ? "1 window" : (total + " windows")
          }
          font.family: "Inter"
          font.weight: Font.Medium
          font.pixelSize: 11
          font.features: ({ "tnum": 1 })
          color: "#A4B3C8"
        }
      }

      // Optional active filter chip when user types letters.
      Rectangle {
        visible: hud.searchQuery.length > 0 || hud.searchArmed
        height: 26
        width: Math.min(200, filterRow.implicitWidth + 16)
        radius: 13
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(hud.accentColor.r, hud.accentColor.g, hud.accentColor.b, 0.22)
        border.width: 1
        border.color: Qt.rgba(hud.accentBright.r, hud.accentBright.g, hud.accentBright.b, 0.62)

        Row {
          id: filterRow
          anchors.centerIn: parent
          spacing: 5

          Text {
            textFormat: Text.PlainText
            text: "Filter:"
            font.family: "Inter"
            font.weight: Font.Medium
            font.pixelSize: 11
            color: "#B9C8DE"
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            textFormat: Text.PlainText
            text: hud.searchQuery.length > 0 ? hud.searchQuery : "type…"
            font.family: "Inter"
            font.weight: Font.DemiBold
            font.pixelSize: 12
            color: hud.searchQuery.length > 0 ? "#F6FAFF" : "#8FA0B8"
            elide: Text.ElideRight
            maximumLineCount: 1
            width: Math.min(implicitWidth, 110)
            anchors.verticalCenter: parent.verticalCenter
          }

          Rectangle {
            width: 15
            height: 15
            radius: 7.5
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(1, 1, 1, 0.14)

            Text {
              anchors.centerIn: parent
              anchors.verticalCenterOffset: -0.5
              textFormat: Text.PlainText
              text: "×"
              font.family: "Inter"
              font.weight: Font.DemiBold
              font.pixelSize: 11
              color: "#E8F0FF"
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: hud.clearFilter()
            }
          }
        }
      }
    }

    // Right cluster: minimal sculpted keycap legend (Tab ↵ Q H Esc).
    Row {
      id: legendRow
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: hud.expandedLegend ? 10 : 7

      Row {
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter
        Keycap { label: "Tab"; compact: true; accentColor: hud.accentColor }
        Text {
          visible: hud.expandedLegend
          textFormat: Text.PlainText
          text: "Cycle"
          font.family: "Inter"
          font.pixelSize: 11
          color: "#8E9EB6"
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Row {
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter
        Keycap { label: "↵"; compact: true; accentColor: hud.accentColor }
        Text {
          visible: hud.expandedLegend
          textFormat: Text.PlainText
          text: "Focus"
          font.family: "Inter"
          font.pixelSize: 11
          color: "#8E9EB6"
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Row {
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter
        Keycap { label: "Q"; compact: true; accentColor: hud.accentColor }
        Text {
          textFormat: Text.PlainText
          text: "Close"
          font.family: "Inter"
          font.pixelSize: 11
          color: "#8E9EB6"
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Row {
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter
        Keycap { label: "H"; compact: true; accentColor: hud.accentColor }
        Text {
          textFormat: Text.PlainText
          text: "Shelf"
          font.family: "Inter"
          font.pixelSize: 11
          color: "#8E9EB6"
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Keycap {
        label: "Esc"
        compact: true
        accentColor: hud.accentColor
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  // =========================================================================
  // 2. CENTER HORIZONTAL LIQUID GLASS CARD CAROUSEL
  // =========================================================================
  Item {
    id: railViewport
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: headerBar.bottom
    anchors.leftMargin: hud.hudPadX - hud.railPadX
    anchors.rightMargin: hud.hudPadX - hud.railPadX
    anchors.topMargin: 12
    height: hud.cardSize + hud.railPadY * 2

    // Empty state when no windows are open or filter matches nothing.
    Column {
      visible: hud.itemCount === 0
      anchors.centerIn: parent
      spacing: 6

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: hud.searchQuery.length > 0
          ? ("No windows match \"" + hud.searchQuery + "\"")
          : "No open windows"
        font.family: "Inter"
        font.weight: Font.DemiBold
        font.pixelSize: 14
        color: "#DCE6F6"
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: hud.searchQuery.length > 0
          ? "Press Esc to clear filter"
          : "Open an application or restore from Top-Bar Shelf"
        font.family: "Inter"
        font.pixelSize: 12
        color: "#8494AC"
      }
    }

    ListView {
      id: cardList
      visible: hud.itemCount > 0
      orientation: ListView.Horizontal
      spacing: hud.cardSpacing
      boundsBehavior: Flickable.StopAtBounds
      clip: hud.needsScroll
      interactive: hud.needsScroll

      height: parent.height
      width: hud.needsScroll
        ? parent.width
        : Math.min(parent.width, hud.contentRailWidth + hud.railPadX * 2)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter

      leftMargin: hud.railPadX
      rightMargin: hud.railPadX
      topMargin: hud.railPadY
      bottomMargin: hud.railPadY

      model: hud.filteredWindows
      currentIndex: hud.safeSelectedIndex
      highlightFollowsCurrentItem: true
      highlightRangeMode: hud.needsScroll ? ListView.ApplyRange : ListView.NoHighlightRange
      preferredHighlightBegin: Math.max(0, (width - hud.cardSize) * 0.35)
      preferredHighlightEnd: Math.min(width, (width + hud.cardSize) * 0.65)
      highlightMoveDuration: hud.reduceMotion ? 0 : 165

      // Gliding liquid-glass highlight cradle softly tracking the active card.
      highlight: Item {
        id: glidingHalo
        z: 0
        width: hud.cardSize
        height: hud.cardSize

        Rectangle {
          anchors.fill: parent
          anchors.margins: -9
          radius: 26
          color: Qt.rgba(hud.accentColor.r, hud.accentColor.g, hud.accentColor.b, 0.10)
        }
      }

      delegate: Item {
        id: slot
        required property var modelData
        required property int index

        width: hud.cardSize
        height: hud.cardSize
        z: hud.safeSelectedIndex === index ? 3 : (hud.hoveredIndex === index ? 2 : 1)

        SwitcherCard {
          anchors.centerIn: parent
          windowData: slot.modelData
          selected: hud.safeSelectedIndex === slot.index
          hovered: hud.hoveredIndex === slot.index && hud.safeSelectedIndex !== slot.index
          reduceMotion: hud.reduceMotion
          accentColor: hud.accentColor
          accentBright: hud.accentBright

          onPointerEntered: {
            if (hud.pointerMovedSinceOpen) {
              hud.hoveredIndex = slot.index
            }
          }
          onClicked: {
            hud.selectedIndex = slot.index
            hud.confirmSelected()
          }
        }
      }
    }

    // Subtle scroll edge indicators when >7 windows overflow horizontally.
    Rectangle {
      visible: hud.needsScroll && !cardList.atXBeginning
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 34
      z: 6
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Qt.rgba(16 / 255, 18 / 255, 25 / 255, 0.85) }
        GradientStop { position: 1.0; color: Qt.rgba(16 / 255, 18 / 255, 25 / 255, 0.0) }
      }
      Text {
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "‹"
        font.family: "Inter"
        font.weight: Font.DemiBold
        font.pixelSize: 20
        color: "#C4D3E8"
      }
    }

    Rectangle {
      visible: hud.needsScroll && !cardList.atXEnd
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 34
      z: 6
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Qt.rgba(16 / 255, 18 / 255, 25 / 255, 0.0) }
        GradientStop { position: 1.0; color: Qt.rgba(16 / 255, 18 / 255, 25 / 255, 0.85) }
      }
      Text {
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "›"
        font.family: "Inter"
        font.weight: Font.DemiBold
        font.pixelSize: 20
        color: "#C4D3E8"
      }
    }
  }

  // Subtle horizontal optical hairline separator above the spotlight bar.
  Rectangle {
    id: footerDivider
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: railViewport.bottom
    anchors.leftMargin: hud.hudPadX
    anchors.rightMargin: hud.hudPadX
    anchors.topMargin: 10
    height: 1
    color: Qt.rgba(1, 1, 1, 0.09)
  }

  // =========================================================================
  // 3. BOTTOM FULL-TITLE SPOTLIGHT BAR
  // =========================================================================
  RowLayout {
    id: spotlightBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: footerDivider.bottom
    anchors.bottom: parent.bottom
    anchors.leftMargin: hud.hudPadX
    anchors.rightMargin: hud.hudPadX
    anchors.topMargin: 2
    anchors.bottomMargin: 6
    spacing: 10

    // Mini crisp app icon (or colored dot fallback) of the selected window.
    Item {
      visible: hud.selectedWindow !== null
      Layout.preferredWidth: 20
      Layout.preferredHeight: 20
      Layout.alignment: Qt.AlignVCenter

      Image {
        id: miniIcon
        anchors.fill: parent
        source: hud.selectedWindow ? hud.formatIconUrl(hud.selectedWindow.iconPath) : ""
        sourceSize: Qt.size(40, 40)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: false
        visible: status === Image.Ready
      }

      Rectangle {
        anchors.fill: parent
        radius: 5.5
        visible: miniIcon.status !== Image.Ready
        color: hud.selectedWindow
          ? Qt.hsla(((Number(hud.selectedWindow.accentHue || 225) % 360) + 360) % 360 / 360.0, 0.52, 0.48, 0.55)
          : Qt.rgba(1, 1, 1, 0.15)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.22)

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: hud.selectedWindow ? String(hud.selectedWindow.monogram || "W") : ""
          font.family: "Inter"
          font.weight: Font.Bold
          font.pixelSize: 10
          color: "#F5F9FF"
        }
      }
    }

    // Complete untruncated title + app name spotlight.
    RowLayout {
      visible: hud.selectedWindow !== null
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: 7

      Text {
        textFormat: Text.PlainText
        text: hud.selectedWindow ? String(hud.selectedWindow.appName || "Window") : ""
        font.family: "Inter"
        font.weight: Font.DemiBold
        font.pixelSize: 13
        color: "#F3F7FF"
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        visible: hud.selectedWindow !== null
          && String(hud.selectedWindow.title || "").trim().toLowerCase() !== String(hud.selectedWindow.appName || "").trim().toLowerCase()
        textFormat: Text.PlainText
        text: "·"
        font.family: "Inter"
        font.weight: Font.DemiBold
        font.pixelSize: 13
        color: "#6B7C96"
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        visible: hud.selectedWindow !== null
          && String(hud.selectedWindow.title || "").trim().toLowerCase() !== String(hud.selectedWindow.appName || "").trim().toLowerCase()
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: hud.selectedWindow ? String(hud.selectedWindow.title || "") : ""
        font.family: "Inter"
        font.weight: Font.Normal
        font.pixelSize: 13
        color: "#C4D3E8"
        elide: Text.ElideRight
        maximumLineCount: 1
        Layout.alignment: Qt.AlignVCenter
      }
    }

    Item {
      visible: hud.selectedWindow === null
      Layout.fillWidth: true
    }

    // Right-side metadata: Floating / Current / Shelf restore pill + tabular index counter.
    Row {
      visible: hud.selectedWindow !== null
      Layout.alignment: Qt.AlignVCenter
      spacing: 8

      Rectangle {
        visible: !!(hud.selectedWindow && hud.selectedWindow.focused)
        height: 21
        width: currentBadgeText.implicitWidth + 14
        radius: 10.5
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(125 / 255, 211 / 255, 252 / 255, 0.14)
        border.width: 1
        border.color: Qt.rgba(125 / 255, 211 / 255, 252 / 255, 0.36)

        Text {
          id: currentBadgeText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "Current"
          font.family: "Inter"
          font.weight: Font.DemiBold
          font.pixelSize: 11
          color: "#BAE6FD"
        }
      }

      Rectangle {
        visible: !!(hud.selectedWindow && hud.selectedWindow.floating)
        height: 21
        width: floatBadgeText.implicitWidth + 14
        radius: 10.5
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(1, 1, 1, 0.065)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        Text {
          id: floatBadgeText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "Floating"
          font.family: "Inter"
          font.weight: Font.Medium
          font.pixelSize: 11
          color: "#B9C7DC"
        }
      }

      Rectangle {
        height: 21
        width: spotWsRow.implicitWidth + 14
        radius: 10.5
        anchors.verticalCenter: parent.verticalCenter
        color: (hud.selectedWindow && hud.selectedWindow.minimized)
          ? Qt.rgba(245 / 255, 158 / 255, 11 / 255, 0.20)
          : Qt.rgba(1, 1, 1, 0.065)
        border.width: 1
        border.color: (hud.selectedWindow && hud.selectedWindow.minimized)
          ? Qt.rgba(251 / 255, 191 / 255, 36 / 255, 0.54)
          : Qt.rgba(1, 1, 1, 0.14)

        Row {
          id: spotWsRow
          anchors.centerIn: parent
          spacing: 5

          Rectangle {
            visible: !!(hud.selectedWindow && hud.selectedWindow.minimized)
            width: 5
            height: 5
            radius: 2.5
            anchors.verticalCenter: parent.verticalCenter
            color: "#FBBF24"
          }

          Text {
            textFormat: Text.PlainText
            text: hud.selectedWindow
              ? (hud.selectedWindow.minimized ? "Shelf · Restore" : String(hud.selectedWindow.workspaceLabel || "Desk 1"))
              : ""
            font.family: "Inter"
            font.weight: Font.DemiBold
            font.pixelSize: 11
            font.features: ({ "tnum": 1 })
            color: (hud.selectedWindow && hud.selectedWindow.minimized) ? "#FDE68A" : "#D6E2F2"
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        text: (hud.safeSelectedIndex + 1) + " / " + hud.itemCount
        font.family: "Inter"
        font.weight: Font.Medium
        font.pixelSize: 11
        font.features: ({ "tnum": 1 })
        color: "#8696AE"
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
