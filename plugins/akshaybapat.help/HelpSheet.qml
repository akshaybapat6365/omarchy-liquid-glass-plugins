pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "HelpModel.js" as HelpModel

// Self-contained Liquid Glass Shortcuts, Gestures, Custom Tools & Quick Guide sheet.
// Mounted inside OverlayWindow by Help.qml (and directly renderable offscreen for visual QA).
Item {
  id: sheet

  property var helpData: ({
    counts: { shortcuts: 0, gestures: 0, tools: 0, guides: 0 },
    categories: [],
    shortcuts: [],
    gestures: [],
    tools: [],
    guides: []
  })
  property int activeTab: 0
  property string selectedCategory: "all"
  property string searchQuery: ""
  property int selectedIndex: 0
  property bool reduceMotion: false
  property string toastText: ""

  property color glassTint: Qt.rgba(16 / 255, 17 / 255, 22 / 255, 0.86)
  property color accentColor: "#7176b8"
  property color foregroundColor: "#eef4ff"
  property color mutedColor: "#94a3b8"

  signal requestAction(var actionSpec)
  signal requestDismiss()
  signal requestRefresh()

  readonly property color accentBright: Qt.rgba(
    Math.min(1.0, accentColor.r * 1.25 + 0.22),
    Math.min(1.0, accentColor.g * 1.25 + 0.24),
    Math.min(1.0, accentColor.b * 1.25 + 0.28),
    1.0
  )
  readonly property color textPrimary: "#F0F5FF"
  readonly property color textSecondary: "#A7B5C9"
  readonly property color textMuted: "#7E8DA3"

  readonly property var tabDefs: HelpModel.TAB_DEFS
  readonly property var filteredShortcuts: HelpModel.filterShortcuts(helpData ? helpData.shortcuts : [], selectedCategory, searchQuery)
  readonly property var filteredGestures: HelpModel.filterItems(helpData ? helpData.gestures : [], searchQuery)
  readonly property var filteredTools: HelpModel.filterItems(helpData ? helpData.tools : [], searchQuery)
  readonly property var filteredGuides: HelpModel.filterItems(helpData ? helpData.guides : [], searchQuery)
  readonly property var categoryCounts: HelpModel.categoryMatchCounts(helpData ? helpData.shortcuts : [], searchQuery)
  readonly property var tabCounts: HelpModel.tabMatchCounts(helpData, searchQuery)

  readonly property int currentItemCount: {
    if (activeTab === 0) return filteredShortcuts.length
    if (activeTab === 1) return filteredGestures.length
    if (activeTab === 2) return filteredTools.length
    return filteredGuides.length
  }

  // Normalized X center of the active tab within the full glass panel width,
  // driving the subtle overhead Fresnel accent caustic in glass_panel.frag.
  readonly property real targetTabPos: 0.455 + (activeTab + 0.5) * (0.515 / 4.0)
  property real animatedTabPos: targetTabPos

  Behavior on animatedTabPos {
    enabled: !sheet.reduceMotion
    NumberAnimation {
      duration: 240
      easing.type: Easing.OutQuart
    }
  }

  onTargetTabPosChanged: animatedTabPos = targetTabPos

  function focusSearch() {
    searchInput.forceActiveFocus()
  }

  function resetSelection() {
    selectedIndex = 0
  }

  function setTab(idx) {
    var clamped = Math.max(0, Math.min(3, idx))
    if (activeTab !== clamped) {
      activeTab = clamped
      selectedIndex = 0
    }
  }

  function moveSelection(delta) {
    var count = currentItemCount
    if (count <= 0) {
      selectedIndex = 0
      return
    }
    var next = Math.max(0, Math.min(count - 1, selectedIndex + delta))
    selectedIndex = next
    ensureSelectedVisible()
  }

  function ensureSelectedVisible() {
    if (activeTab === 0 && shortcutsGrid.count > 0) {
      shortcutsGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
    } else if (activeTab === 1 && gesturesGrid.count > 0) {
      gesturesGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
    } else if (activeTab === 2 && toolsGrid.count > 0) {
      toolsGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
    } else if (activeTab === 3 && guidesGrid.count > 0) {
      guidesGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
    }
  }

  function activateSelected() {
    if (activeTab === 0) {
      if (selectedIndex >= 0 && selectedIndex < filteredShortcuts.length) {
        const sc = filteredShortcuts[selectedIndex]
        if (sc && sc.runnable && sc.action) {
          sheet.requestAction({
            command: sc.action,
            closeOnRun: true,
            delayMs: sc.delayMs || 0,
            toast: ""
          })
        }
      }
    } else if (activeTab === 2) {
      if (selectedIndex >= 0 && selectedIndex < filteredTools.length) {
        const tool = filteredTools[selectedIndex]
        if (tool && tool.actions && tool.actions.length > 0) {
          const act = tool.actions[0]
          sheet.requestAction(act)
        }
      }
    }
  }

  function handleKeyEvent(event) {
    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    const shift = (event.modifiers & Qt.ShiftModifier) !== 0
    const alt = (event.modifiers & Qt.AltModifier) !== 0

    if (event.key === Qt.Key_Escape) {
      if (sheet.searchQuery.length > 0) {
        sheet.searchQuery = ""
        searchInput.text = ""
        sheet.selectedIndex = 0
      } else {
        sheet.requestDismiss()
      }
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      const step = (event.key === Qt.Key_Backtab || shift) ? -1 : 1
      sheet.setTab((sheet.activeTab + step + 4) % 4)
      event.accepted = true
      return
    }

    if (ctrl && !alt && event.key === Qt.Key_R) {
      sheet.requestRefresh()
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_F5) {
      sheet.requestRefresh()
      event.accepted = true
      return
    }

    if (ctrl && event.key === Qt.Key_U) {
      sheet.searchQuery = ""
      searchInput.text = ""
      sheet.selectedIndex = 0
      event.accepted = true
      return
    }

    if ((ctrl || (sheet.searchQuery === "" && !alt && !shift))
        && event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
      sheet.setTab(event.key - Qt.Key_1)
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Down) {
      sheet.moveSelection(2)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Up) {
      sheet.moveSelection(-2)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Right && sheet.searchQuery === "") {
      sheet.moveSelection(1)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Left && sheet.searchQuery === "") {
      sheet.moveSelection(-1)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      sheet.activateSelected()
      event.accepted = true
      return
    }
  }

  function statusDotColor(tone) {
    if (tone === "ok") return "#4ADE80"
    if (tone === "warn") return "#FBBF24"
    if (tone === "accent") return sheet.accentBright
    return "#94A3B8"
  }

  function statusTextColor(tone) {
    if (tone === "ok") return "#86EFAC"
    if (tone === "warn") return "#FDE68A"
    if (tone === "accent") return Qt.lighter(sheet.accentBright, 1.15)
    return "#CBD5E1"
  }

  function statusBgColor(tone) {
    if (tone === "ok") return Qt.rgba(74 / 255, 222 / 255, 128 / 255, 0.12)
    if (tone === "warn") return Qt.rgba(251 / 255, 191 / 255, 36 / 255, 0.13)
    if (tone === "accent") return Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, 0.22)
    return Qt.rgba(148 / 255, 163 / 255, 184 / 255, 0.12)
  }

  function statusBorderColor(tone) {
    if (tone === "ok") return Qt.rgba(74 / 255, 222 / 255, 128 / 255, 0.30)
    if (tone === "warn") return Qt.rgba(251 / 255, 191 / 255, 36 / 255, 0.32)
    if (tone === "accent") return Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, 0.44)
    return Qt.rgba(148 / 255, 163 / 255, 184 / 255, 0.26)
  }

  onSearchQueryChanged: {
    if (searchInput.text !== searchQuery) searchInput.text = searchQuery
    selectedIndex = 0
  }

  onSelectedCategoryChanged: selectedIndex = 0

  implicitWidth: 1040
  implicitHeight: 700

  // Soft two-tier physical elevation halo behind the optical glass sheet.
  Rectangle {
    anchors.fill: parent
    anchors.margins: -14
    anchors.topMargin: -6
    anchors.bottomMargin: -22
    radius: 34
    color: Qt.rgba(2 / 255, 3 / 255, 8 / 255, 0.34)
  }
  Rectangle {
    anchors.fill: parent
    anchors.margins: -5
    anchors.topMargin: -2
    anchors.bottomMargin: -9
    radius: 26
    color: Qt.rgba(2 / 255, 3 / 255, 8 / 255, 0.36)
  }

  // Compiled Qt 6.12 optical Liquid Glass sheet shader (45° Fresnel sheen + 1px bezel + active caustic).
  ShaderEffect {
    id: glassShader
    anchors.fill: parent
    property vector2d iResolution: Qt.vector2d(Math.max(4, width), Math.max(4, height))
    property color tintColor: sheet.glassTint
    property color accentColor: sheet.accentColor
    property real cornerRadius: 22.0
    property real activeTabPos: sheet.animatedTabPos
    property real causticStrength: 1.0
    fragmentShader: Qt.resolvedUrl("shaders/glass_panel.frag.qsb")
  }

  // Graceful fallback surface if shader compilation is unavailable.
  Rectangle {
    anchors.fill: parent
    visible: glassShader.status !== ShaderEffect.Compiled
    radius: 22
    color: sheet.glassTint
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.20)
  }

  // Absorb clicks inside the glass panel so outside scrim clicks dismiss cleanly.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onClicked: searchInput.forceActiveFocus()
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.leftMargin: 24
    anchors.rightMargin: 24
    anchors.topMargin: 20
    anchors.bottomMargin: 15
    spacing: 13

    // ------------------------------------------------------------------ Header
    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: false
      Layout.preferredHeight: 42
      Layout.minimumHeight: 42
      Layout.maximumHeight: 42
      spacing: 12

      // Recessed optical medallion holding the Omarchy emblem.
      Rectangle {
        Layout.preferredWidth: 38
        Layout.preferredHeight: 38
        radius: 11
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, 0.28) }
          GradientStop { position: 1.0; color: Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, 0.10) }
        }
        border.width: 1
        border.color: Qt.rgba(sheet.accentBright.r, sheet.accentBright.g, sheet.accentBright.b, 0.40)

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.leftMargin: 6
          anchors.rightMargin: 6
          anchors.topMargin: 1
          height: 1
          color: Qt.rgba(1, 1, 1, 0.30)
        }

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "\ue900"
          font.family: "omarchy"
          font.pixelSize: 19
          color: "#F3F7FF"
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: 2

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: "Shortcuts & Help"
          font.family: "Inter"
          font.weight: Font.DemiBold
          font.pixelSize: 19
          font.letterSpacing: -0.35
          color: sheet.textPrimary
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: HelpModel.formatSubtitle(sheet.helpData ? sheet.helpData.counts : null)
          font.family: "Inter"
          font.weight: Font.Normal
          font.pixelSize: 12
          font.features: ({ "tnum": 1 })
          color: sheet.textSecondary
        }
      }

      Item {
        Layout.fillWidth: true
      }

      // Transient feedback pill for in-place tool toggles (Spatial Audio, Battery Care, Nightlight).
      Rectangle {
        visible: sheet.toastText.length > 0
        Layout.preferredHeight: 30
        Layout.preferredWidth: toastRow.implicitWidth + 22
        radius: 9
        color: Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, 0.24)
        border.width: 1
        border.color: Qt.rgba(sheet.accentBright.r, sheet.accentBright.g, sheet.accentBright.b, 0.45)

        Row {
          id: toastRow
          anchors.centerIn: parent
          spacing: 7

          Rectangle {
            width: 6
            height: 6
            radius: 3
            anchors.verticalCenter: parent.verticalCenter
            color: "#4ADE80"
          }

          Text {
            textFormat: Text.PlainText
            text: sheet.toastText
            font.family: "Inter"
            font.weight: Font.Medium
            font.pixelSize: 12
            color: "#EEF4FF"
          }
        }
      }

      // Crisp Esc close glass pill.
      Rectangle {
        id: closePill
        Layout.preferredHeight: 32
        Layout.preferredWidth: closeRow.implicitWidth + 18
        radius: 10
        color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.05)
        border.width: 1
        border.color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.11)

        Row {
          id: closeRow
          anchors.centerIn: parent
          spacing: 7

          Keycap {
            anchors.verticalCenter: parent.verticalCenter
            label: "Esc"
            compact: true
            modifier: true
            accentColor: sheet.accentColor
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Close"
            font.family: "Inter"
            font.weight: Font.Medium
            font.pixelSize: 12
            color: closeMouse.containsMouse ? sheet.textPrimary : sheet.textSecondary
          }
        }

        MouseArea {
          id: closeMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: sheet.requestDismiss()
        }
      }
    }

    // ---------------------------------------- Unified Search + Segmented Tabs
    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: false
      Layout.preferredHeight: 42
      Layout.minimumHeight: 42
      Layout.maximumHeight: 42
      spacing: 12

      // Instant Search Field
      Rectangle {
        id: searchBox
        Layout.preferredWidth: 406
        Layout.fillHeight: true
        radius: 12
        color: searchInput.activeFocus ? Qt.rgba(1, 1, 1, 0.068) : Qt.rgba(1, 1, 1, 0.044)
        border.width: 1
        border.color: searchInput.activeFocus
          ? Qt.rgba(sheet.accentBright.r, sheet.accentBright.g, sheet.accentBright.b, 0.58)
          : Qt.rgba(1, 1, 1, 0.11)

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 13
          anchors.rightMargin: 10
          spacing: 9

          // Crisp pure-QML vector magnifying glass (always sharp at 264 PPI).
          Item {
            Layout.preferredWidth: 14
            Layout.preferredHeight: 14

            Rectangle {
              x: 0
              y: 0
              width: 11
              height: 11
              radius: 5.5
              color: "transparent"
              border.width: 2
              border.color: searchInput.activeFocus ? sheet.accentBright : sheet.textMuted
            }
            Rectangle {
              x: 9.4
              y: 8.6
              width: 2
              height: 5.5
              radius: 1
              rotation: -45
              color: searchInput.activeFocus ? sheet.accentBright : sheet.textMuted
            }
          }

          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: searchInput.text.length === 0
              textFormat: Text.PlainText
              text: "Search shortcuts, gestures, tools, or guide…"
              font.family: "Inter"
              font.pixelSize: 13
              color: sheet.textMuted
              elide: Text.ElideRight
            }

            TextInput {
              id: searchInput
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              focus: true
              color: sheet.textPrimary
              selectionColor: Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, 0.45)
              selectedTextColor: "#FFFFFF"
              font.family: "Inter"
              font.pixelSize: 13
              font.weight: Font.Normal
              cursorVisible: activeFocus
              onTextChanged: {
                if (sheet.searchQuery !== text) sheet.searchQuery = text
              }
              Keys.onPressed: function(event) {
                sheet.handleKeyEvent(event)
              }
            }
          }

          // Clear query pill when typing.
          Rectangle {
            visible: sheet.searchQuery.length > 0
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            radius: 10
            color: clearSearchMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "×"
              font.family: "Inter"
              font.weight: Font.DemiBold
              font.pixelSize: 13
              color: sheet.textPrimary
            }

            MouseArea {
              id: clearSearchMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                sheet.searchQuery = ""
                searchInput.text = ""
                searchInput.forceActiveFocus()
              }
            }
          }
        }
      }

      // 4 Segmented Liquid Glass Tabs
      Rectangle {
        id: tabTrack
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 12
        color: Qt.rgba(1, 1, 1, 0.040)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.095)

        readonly property real slotWidth: (width - 8) / 4.0

        // Smoothly gliding frosted glass active tab pill.
        Rectangle {
          id: tabThumb
          y: 4
          height: parent.height - 8
          width: Math.max(40, tabTrack.slotWidth)
          x: 4 + sheet.activeTab * tabTrack.slotWidth
          radius: 9

          Behavior on x {
            enabled: !sheet.reduceMotion
            NumberAnimation {
              duration: 210
              easing.type: Easing.OutQuart
            }
          }

          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, 0.34) }
            GradientStop { position: 1.0; color: Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, 0.18) }
          }
          border.width: 1
          border.color: Qt.rgba(sheet.accentBright.r, sheet.accentBright.g, sheet.accentBright.b, 0.48)

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 1
            height: 1
            color: Qt.rgba(1, 1, 1, 0.30)
          }
        }

        Row {
          anchors.fill: parent
          anchors.margins: 4

          Repeater {
            model: sheet.tabDefs
            delegate: Item {
              id: tabBtn
              required property var modelData
              required property int index

              readonly property bool isActive: sheet.activeTab === index
              readonly property bool searching: sheet.searchQuery.length > 0
              readonly property int matchCount: sheet.tabCounts[index] || 0

              width: tabTrack.slotWidth
              height: parent.height

              Rectangle {
                anchors.fill: parent
                radius: 9
                color: !tabBtn.isActive && tabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.055) : "transparent"
              }

              Row {
                anchors.centerIn: parent
                spacing: 6

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  height: 18
                  width: Math.max(18, Math.ceil(badgeTxt.implicitWidth) + 9)
                  radius: 5.5
                  color: tabBtn.isActive
                    ? Qt.rgba(1, 1, 1, 0.18)
                    : (tabBtn.searching && tabBtn.matchCount > 0
                      ? Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, 0.28)
                      : Qt.rgba(1, 1, 1, 0.065))
                  border.width: 1
                  border.color: tabBtn.isActive
                    ? Qt.rgba(1, 1, 1, 0.25)
                    : Qt.rgba(1, 1, 1, 0.10)

                  Text {
                    id: badgeTxt
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: tabBtn.searching ? String(tabBtn.matchCount) : tabBtn.modelData.number
                    font.family: "JetBrainsMono Nerd Font"
                    font.weight: Font.DemiBold
                    font.pixelSize: 10
                    font.features: ({ "tnum": 1 })
                    color: tabBtn.isActive
                      ? "#F6FAFF"
                      : (tabBtn.searching && tabBtn.matchCount === 0 ? sheet.textMuted : "#D0DCF0")
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: tabBtn.modelData.label
                  font.family: "Inter"
                  font.weight: tabBtn.isActive ? Font.DemiBold : Font.Medium
                  font.pixelSize: 13
                  color: tabBtn.isActive
                    ? "#F6FAFF"
                    : (tabMouse.containsMouse ? "#DFE9FA" : sheet.textSecondary)
                }
              }

              MouseArea {
                id: tabMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  sheet.setTab(tabBtn.index)
                  searchInput.forceActiveFocus()
                }
              }
            }
          }
        }
      }
    }

    // ----------------------------- Shortcuts Category Chips (Tab 0 only)
    Row {
      visible: sheet.activeTab === 0
      Layout.fillWidth: true
      Layout.fillHeight: false
      Layout.preferredHeight: 30
      Layout.minimumHeight: 30
      Layout.maximumHeight: 30
      spacing: 7

      Repeater {
        model: sheet.helpData && sheet.helpData.categories ? sheet.helpData.categories : []
        delegate: Rectangle {
          id: chip
          required property var modelData

          readonly property bool selected: sheet.selectedCategory === modelData.id
          readonly property int liveCount: sheet.categoryCounts[modelData.id] !== undefined
            ? sheet.categoryCounts[modelData.id]
            : (modelData.count || 0)

          height: 30
          width: chipRow.implicitWidth + 22
          radius: 9
          color: selected
            ? Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, 0.28)
            : (chipMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.085) : Qt.rgba(1, 1, 1, 0.038))
          border.width: 1
          border.color: selected
            ? Qt.rgba(sheet.accentBright.r, sheet.accentBright.g, sheet.accentBright.b, 0.52)
            : Qt.rgba(1, 1, 1, chipMouse.containsMouse ? 0.18 : 0.09)

          Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: chip.modelData.label
              font.family: "Inter"
              font.weight: chip.selected ? Font.DemiBold : Font.Medium
              font.pixelSize: 12
              color: chip.selected ? "#F6FAFF" : (chipMouse.containsMouse ? "#E3ECFA" : sheet.textSecondary)
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String(chip.liveCount)
              font.family: "Inter"
              font.weight: Font.Medium
              font.pixelSize: 11
              font.features: ({ "tnum": 1 })
              color: chip.selected ? Qt.lighter(sheet.accentBright, 1.2) : sheet.textMuted
            }
          }

          MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              sheet.selectedCategory = chip.modelData.id
              searchInput.forceActiveFocus()
            }
          }
        }
      }
    }

    // --------------------------------------------------- Main Content Viewport
    Item {
      id: contentStage
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true

      // ==================================================== TAB 0: SHORTCUTS
      GridView {
        id: shortcutsGrid
        anchors.fill: parent
        visible: sheet.activeTab === 0 && sheet.filteredShortcuts.length > 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: sheet.filteredShortcuts
        cellWidth: Math.floor((width - 10) / 2)
        cellHeight: 65

        ScrollBar.vertical: ScrollBar {
          policy: shortcutsGrid.contentHeight > shortcutsGrid.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
          width: 6
          contentItem: Rectangle {
            implicitWidth: 4
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.22)
          }
          background: Rectangle { color: "transparent" }
        }

        delegate: Item {
          id: scCell
          required property var modelData
          required property int index

          width: shortcutsGrid.cellWidth
          height: shortcutsGrid.cellHeight

          readonly property bool isSelected: sheet.selectedIndex === index
          readonly property bool isHot: isSelected || scMouse.containsMouse
          readonly property bool canRun: !!modelData.runnable

          Rectangle {
            anchors.fill: parent
            anchors.rightMargin: 10
            anchors.bottomMargin: 8
            radius: 13
            color: scCell.isSelected
              ? Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, 0.21)
              : (scMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.072) : Qt.rgba(1, 1, 1, 0.032))
            border.width: 1
            border.color: scCell.isSelected
              ? Qt.rgba(sheet.accentBright.r, sheet.accentBright.g, sheet.accentBright.b, 0.56)
              : Qt.rgba(1, 1, 1, scMouse.containsMouse ? 0.17 : 0.075)

            // Crisp top inner specular highlight when selected.
            Rectangle {
              visible: scCell.isSelected
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.leftMargin: 12
              anchors.rightMargin: 12
              anchors.topMargin: 1
              height: 1
              color: Qt.rgba(1, 1, 1, 0.28)
            }

            // Quiet luminous left focus bar on keyboard-selected card.
            Rectangle {
              visible: scCell.isSelected
              width: 3
              height: 28
              radius: 1.5
              anchors.left: parent.left
              anchors.leftMargin: 4
              anchors.verticalCenter: parent.verticalCenter
              color: sheet.accentBright
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 14
              anchors.rightMargin: 12
              spacing: 10

              ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: scCell.modelData.title || ""
                  font.family: "Inter"
                  font.weight: scCell.isHot ? Font.DemiBold : Font.Medium
                  font.pixelSize: 13
                  color: sheet.textPrimary
                  elide: Text.ElideRight
                  maximumLineCount: 1
                }

                Row {
                  spacing: 6

                  Text {
                    textFormat: Text.PlainText
                    text: scCell.modelData.categoryLabel || ""
                    font.family: "Inter"
                    font.pixelSize: 11
                    color: scCell.isSelected ? Qt.lighter(sheet.accentBright, 1.15) : sheet.textMuted
                  }

                  Text {
                    visible: scCell.canRun && scCell.isHot
                    textFormat: Text.PlainText
                    text: "·  Run ↵"
                    font.family: "Inter"
                    font.weight: Font.Medium
                    font.pixelSize: 11
                    color: "#86EFAC"
                  }

                  Text {
                    visible: !scCell.canRun && scCell.isHot
                    textFormat: Text.PlainText
                    text: "·  Reference"
                    font.family: "Inter"
                    font.pixelSize: 11
                    color: sheet.textMuted
                  }
                }
              }

              // Right-aligned sculpted 3D-beveled keycap sequence.
              Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 4

                Repeater {
                  model: scCell.modelData.keys || []
                  delegate: Keycap {
                    required property string modelData
                    label: modelData
                    modifier: HelpModel.isModifierCap(modelData)
                    highlighted: scCell.isSelected && !HelpModel.isModifierCap(modelData)
                    accentColor: sheet.accentColor
                  }
                }
              }
            }

            MouseArea {
              id: scMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: scCell.canRun ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: {
                sheet.selectedIndex = scCell.index
                if (scCell.canRun && scCell.modelData.action) {
                  sheet.requestAction({
                    command: scCell.modelData.action,
                    closeOnRun: true,
                    delayMs: scCell.modelData.delayMs || 0,
                    toast: ""
                  })
                } else {
                  searchInput.forceActiveFocus()
                }
              }
            }
          }
        }
      }

      // ===================================================== TAB 1: GESTURES
      GridView {
        id: gesturesGrid
        anchors.fill: parent
        visible: sheet.activeTab === 1 && sheet.filteredGestures.length > 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: sheet.filteredGestures
        cellWidth: Math.floor((width - 10) / 2)
        cellHeight: 98

        ScrollBar.vertical: ScrollBar {
          policy: gesturesGrid.contentHeight > gesturesGrid.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
          width: 6
          contentItem: Rectangle {
            implicitWidth: 4
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.22)
          }
          background: Rectangle { color: "transparent" }
        }

        delegate: Item {
          id: gCell
          required property var modelData
          required property int index

          width: gesturesGrid.cellWidth
          height: gesturesGrid.cellHeight

          readonly property bool isSelected: sheet.selectedIndex === index

          Rectangle {
            anchors.fill: parent
            anchors.rightMargin: 10
            anchors.bottomMargin: 10
            radius: 15
            color: gCell.isSelected
              ? Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, 0.20)
              : (gMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.072) : Qt.rgba(1, 1, 1, 0.034))
            border.width: 1
            border.color: gCell.isSelected
              ? Qt.rgba(sheet.accentBright.r, sheet.accentBright.g, sheet.accentBright.b, 0.54)
              : Qt.rgba(1, 1, 1, gMouse.containsMouse ? 0.18 : 0.085)

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.leftMargin: 14
              anchors.rightMargin: 14
              anchors.topMargin: 1
              height: 1
              color: Qt.rgba(1, 1, 1, gCell.isSelected ? 0.26 : 0.11)
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 14
              anchors.rightMargin: 14
              anchors.topMargin: 12
              anchors.bottomMargin: 12
              spacing: 14

              GestureGlyph {
                Layout.preferredWidth: 68
                Layout.preferredHeight: 58
                Layout.alignment: Qt.AlignVCenter
                gestureType: gCell.modelData.gestureType || "swipe-up"
                fingers: gCell.modelData.fingers !== undefined ? gCell.modelData.fingers : 3
                accentColor: sheet.accentColor
                active: gCell.isSelected || gMouse.containsMouse
              }

              ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 5

                RowLayout {
                  Layout.fillWidth: true
                  spacing: 8

                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: gCell.modelData.title || ""
                    font.family: "Inter"
                    font.weight: Font.DemiBold
                    font.pixelSize: 14
                    color: sheet.textPrimary
                    elide: Text.ElideRight
                  }

                  Rectangle {
                    Layout.preferredHeight: 20
                    Layout.preferredWidth: ctxText.implicitWidth + 14
                    radius: 6
                    color: Qt.rgba(1, 1, 1, 0.065)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.11)

                    Text {
                      id: ctxText
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: gCell.modelData.context || ""
                      font.family: "Inter"
                      font.weight: Font.Medium
                      font.pixelSize: 10
                      color: sheet.textSecondary
                    }
                  }
                }

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: gCell.modelData.description || ""
                  font.family: "Inter"
                  font.pixelSize: 12
                  lineHeight: 1.32
                  color: "#B4C2D6"
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }
              }
            }

            MouseArea {
              id: gMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                sheet.selectedIndex = gCell.index
                searchInput.forceActiveFocus()
              }
            }
          }
        }
      }

      // ================================================= TAB 2: CUSTOM TOOLS
      GridView {
        id: toolsGrid
        anchors.fill: parent
        visible: sheet.activeTab === 2 && sheet.filteredTools.length > 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: sheet.filteredTools
        cellWidth: Math.floor((width - 10) / 2)
        cellHeight: 126

        ScrollBar.vertical: ScrollBar {
          policy: toolsGrid.contentHeight > toolsGrid.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
          width: 6
          contentItem: Rectangle {
            implicitWidth: 4
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.22)
          }
          background: Rectangle { color: "transparent" }
        }

        delegate: Item {
          id: tCell
          required property var modelData
          required property int index

          width: toolsGrid.cellWidth
          height: toolsGrid.cellHeight

          readonly property bool isSelected: sheet.selectedIndex === index

          Rectangle {
            anchors.fill: parent
            anchors.rightMargin: 10
            anchors.bottomMargin: 10
            radius: 15
            color: tCell.isSelected
              ? Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, 0.19)
              : (toolHover.containsMouse ? Qt.rgba(1, 1, 1, 0.064) : Qt.rgba(1, 1, 1, 0.034))
            border.width: 1
            border.color: tCell.isSelected
              ? Qt.rgba(sheet.accentBright.r, sheet.accentBright.g, sheet.accentBright.b, 0.54)
              : Qt.rgba(1, 1, 1, toolHover.containsMouse ? 0.16 : 0.085)

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.leftMargin: 14
              anchors.rightMargin: 14
              anchors.topMargin: 1
              height: 1
              color: Qt.rgba(1, 1, 1, tCell.isSelected ? 0.25 : 0.11)
            }

            MouseArea {
              id: toolHover
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                sheet.selectedIndex = tCell.index
                searchInput.forceActiveFocus()
              }
            }

            ColumnLayout {
              anchors.fill: parent
              anchors.leftMargin: 15
              anchors.rightMargin: 15
              anchors.topMargin: 12
              anchors.bottomMargin: 12
              spacing: 7

              // Title + Live Status Pill
              RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: tCell.modelData.title || ""
                  font.family: "Inter"
                  font.weight: Font.DemiBold
                  font.pixelSize: 14
                  color: sheet.textPrimary
                  elide: Text.ElideRight
                }

                Rectangle {
                  Layout.preferredHeight: 22
                  Layout.preferredWidth: statusRow.implicitWidth + 16
                  radius: 11
                  color: sheet.statusBgColor(tCell.modelData.tone)
                  border.width: 1
                  border.color: sheet.statusBorderColor(tCell.modelData.tone)

                  Row {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 6

                    Rectangle {
                      width: 6.5
                      height: 6.5
                      radius: 3.25
                      anchors.verticalCenter: parent.verticalCenter
                      color: sheet.statusDotColor(tCell.modelData.tone)
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: tCell.modelData.status || ""
                      font.family: "Inter"
                      font.weight: Font.DemiBold
                      font.pixelSize: 11
                      font.features: ({ "tnum": 1 })
                      color: sheet.statusTextColor(tCell.modelData.tone)
                    }
                  }
                }
              }

              // Concise live telemetry metric
              Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                textFormat: Text.PlainText
                text: tCell.modelData.metric || ""
                font.family: "Inter"
                font.pixelSize: 12
                font.features: ({ "tnum": 1 })
                lineHeight: 1.3
                color: sheet.textSecondary
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }

              // 1-click Liquid Glass action buttons
              Row {
                Layout.fillWidth: true
                spacing: 7

                Repeater {
                  model: tCell.modelData.actions || []
                  delegate: Rectangle {
                    id: actBtn
                    required property var modelData

                    readonly property bool isActivePreset: !!modelData.active
                    height: 28
                    width: actRow.implicitWidth + 20
                    radius: 8.5

                    gradient: Gradient {
                      GradientStop {
                        position: 0.0
                        color: actBtn.isActivePreset
                          ? Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, actMouse.containsMouse ? 0.48 : 0.36)
                          : Qt.rgba(1, 1, 1, actMouse.containsMouse ? 0.16 : 0.085)
                      }
                      GradientStop {
                        position: 1.0
                        color: actBtn.isActivePreset
                          ? Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, actMouse.containsMouse ? 0.30 : 0.20)
                          : Qt.rgba(1, 1, 1, actMouse.containsMouse ? 0.09 : 0.042)
                      }
                    }

                    border.width: 1
                    border.color: actBtn.isActivePreset
                      ? Qt.rgba(sheet.accentBright.r, sheet.accentBright.g, sheet.accentBright.b, 0.65)
                      : Qt.rgba(1, 1, 1, actMouse.containsMouse ? 0.28 : 0.13)

                    Row {
                      id: actRow
                      anchors.centerIn: parent
                      spacing: 6

                      Rectangle {
                        visible: actBtn.isActivePreset
                        width: 5.5
                        height: 5.5
                        radius: 2.75
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#4ADE80"
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: actBtn.modelData.label || ""
                        font.family: "Inter"
                        font.weight: Font.Medium
                        font.pixelSize: 12
                        color: actBtn.isActivePreset || actMouse.containsMouse ? "#F6FAFF" : "#D6E2F2"
                      }
                    }

                    MouseArea {
                      id: actMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        sheet.selectedIndex = tCell.index
                        sheet.requestAction(actBtn.modelData)
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      // ================================================== TAB 3: QUICK GUIDE
      GridView {
        id: guidesGrid
        anchors.fill: parent
        visible: sheet.activeTab === 3 && sheet.filteredGuides.length > 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: sheet.filteredGuides
        cellWidth: Math.floor((width - 10) / 2)
        cellHeight: 252

        ScrollBar.vertical: ScrollBar {
          policy: guidesGrid.contentHeight > guidesGrid.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
          width: 6
          contentItem: Rectangle {
            implicitWidth: 4
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.22)
          }
          background: Rectangle { color: "transparent" }
        }

        delegate: Item {
          id: guideCell
          required property var modelData
          required property int index

          width: guidesGrid.cellWidth
          height: guidesGrid.cellHeight

          Rectangle {
            anchors.fill: parent
            anchors.rightMargin: 12
            anchors.bottomMargin: 12
            radius: 16
            clip: true
            color: Qt.rgba(1, 1, 1, 0.036)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.095)

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.leftMargin: 16
              anchors.rightMargin: 16
              anchors.topMargin: 1
              height: 1
              color: Qt.rgba(1, 1, 1, 0.14)
            }

            ColumnLayout {
              anchors.fill: parent
              anchors.leftMargin: 18
              anchors.rightMargin: 18
              anchors.topMargin: 14
              anchors.bottomMargin: 12
              spacing: 8

              ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 2

                Text {
                  textFormat: Text.PlainText
                  text: guideCell.modelData.eyebrow || ""
                  font.family: "Inter"
                  font.weight: Font.DemiBold
                  font.pixelSize: 10
                  font.letterSpacing: 1.15
                  color: sheet.accentBright
                }

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: guideCell.modelData.title || ""
                  font.family: "Inter"
                  font.weight: Font.DemiBold
                  font.pixelSize: 15
                  font.letterSpacing: -0.2
                  color: sheet.textPrimary
                  elide: Text.ElideRight
                }

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: guideCell.modelData.summary || ""
                  font.family: "Inter"
                  font.pixelSize: 11
                  color: sheet.textMuted
                  elide: Text.ElideRight
                }
              }

              Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 1
                color: Qt.rgba(1, 1, 1, 0.075)
              }

              ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6

                Repeater {
                  model: guideCell.modelData.bullets || []
                  delegate: RowLayout {
                    id: bulletRow
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 9

                    Rectangle {
                      Layout.preferredWidth: 5
                      Layout.preferredHeight: 5
                      Layout.alignment: Qt.AlignTop
                      Layout.topMargin: 6
                      radius: 2.5
                      color: sheet.accentBright
                    }

                    Text {
                      Layout.fillWidth: true
                      Layout.alignment: Qt.AlignTop
                      textFormat: Text.PlainText
                      text: bulletRow.modelData.text || ""
                      font.family: "Inter"
                      font.pixelSize: 12
                      lineHeight: 1.25
                      color: "#D3DFEE"
                      wrapMode: Text.WordWrap
                    }

                    Row {
                      visible: bulletRow.modelData.keys && bulletRow.modelData.keys.length > 0
                      Layout.alignment: Qt.AlignTop
                      spacing: 3

                      Repeater {
                        model: bulletRow.modelData.keys || []
                        delegate: Keycap {
                          required property string modelData
                          label: modelData
                          compact: true
                          modifier: HelpModel.isModifierCap(modelData)
                          accentColor: sheet.accentColor
                        }
                      }
                    }
                  }
                }

                Item { Layout.fillHeight: true }
              }
            }
          }
        }
      }

      // ================================================= Empty Search State
      Column {
        anchors.centerIn: parent
        spacing: 12
        visible: sheet.currentItemCount === 0

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: sheet.searchQuery.length > 0
            ? ("No matches in " + sheet.tabDefs[sheet.activeTab].label + " for \"" + sheet.searchQuery + "\"")
            : "Loading live system shortcuts…"
          font.family: "Inter"
          font.weight: Font.Medium
          font.pixelSize: 14
          color: sheet.textSecondary
        }

        // Cross-tab jump chips when other tabs matched the search query!
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 8
          visible: sheet.searchQuery.length > 0

          Repeater {
            model: sheet.tabDefs
            delegate: Rectangle {
              id: jumpChip
              required property var modelData
              required property int index
              readonly property int cnt: sheet.tabCounts[index] || 0
              visible: index !== sheet.activeTab && cnt > 0
              height: 30
              width: jumpLabel.implicitWidth + 22
              radius: 9
              color: jumpMouse.containsMouse
                ? Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, 0.34)
                : Qt.rgba(sheet.accentColor.r, sheet.accentColor.g, sheet.accentColor.b, 0.20)
              border.width: 1
              border.color: Qt.rgba(sheet.accentBright.r, sheet.accentBright.g, sheet.accentBright.b, 0.48)

              Text {
                id: jumpLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "View " + jumpChip.cnt + " in " + jumpChip.modelData.label + " →"
                font.family: "Inter"
                font.weight: Font.Medium
                font.pixelSize: 12
                font.features: ({ "tnum": 1 })
                color: "#EEF4FF"
              }

              MouseArea {
                id: jumpMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  sheet.selectedCategory = "all"
                  sheet.setTab(jumpChip.index)
                  searchInput.forceActiveFocus()
                }
              }
            }
          }
        }
      }
    }

    // --------------------------------------------------------- Footer Legend
    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: false
      Layout.preferredHeight: 1
      Layout.maximumHeight: 1
      color: Qt.rgba(1, 1, 1, 0.08)
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: false
      Layout.preferredHeight: 24
      Layout.minimumHeight: 24
      Layout.maximumHeight: 24
      spacing: 12

      Row {
        spacing: 8

        Keycap { anchors.verticalCenter: parent.verticalCenter; label: "1–4"; compact: true; modifier: true; accentColor: sheet.accentColor }
        Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: "Tabs"; font.family: "Inter"; font.pixelSize: 11; color: sheet.textMuted }

        Item { width: 4; height: 1 }

        Keycap { anchors.verticalCenter: parent.verticalCenter; label: "↑↓"; compact: true; modifier: true; accentColor: sheet.accentColor }
        Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: "Select"; font.family: "Inter"; font.pixelSize: 11; color: sheet.textMuted }

        Item { width: 4; height: 1 }

        Keycap { anchors.verticalCenter: parent.verticalCenter; label: "↵"; compact: true; modifier: true; accentColor: sheet.accentColor }
        Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: "Run action"; font.family: "Inter"; font.pixelSize: 11; color: sheet.textMuted }

        Item { width: 4; height: 1 }

        Keycap { anchors.verticalCenter: parent.verticalCenter; label: "Esc"; compact: true; modifier: true; accentColor: sheet.accentColor }
        Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: "Clear / Close"; font.family: "Inter"; font.pixelSize: 11; color: sheet.textMuted }
      }

      Item { Layout.fillWidth: true }

      Rectangle {
        Layout.preferredHeight: 24
        Layout.preferredWidth: refreshTxt.implicitWidth + 16
        radius: 7
        color: refreshMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent"
        border.width: refreshMouse.containsMouse ? 1 : 0
        border.color: Qt.rgba(1, 1, 1, 0.14)

        Text {
          id: refreshTxt
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "↻ Refresh"
          font.family: "Inter"
          font.weight: Font.Medium
          font.pixelSize: 11
          color: refreshMouse.containsMouse ? sheet.textPrimary : sheet.textMuted
        }

        MouseArea {
          id: refreshMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: sheet.requestRefresh()
        }
      }

      Text {
        textFormat: Text.PlainText
        text: "Omarchy 4.5 · Liquid Glass"
        font.family: "Inter"
        font.weight: Font.Medium
        font.pixelSize: 11
        color: Qt.rgba(150 / 255, 165 / 255, 186 / 255, 0.62)
      }
    }
  }
}
