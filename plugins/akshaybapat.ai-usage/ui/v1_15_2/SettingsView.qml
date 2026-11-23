import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Native Quattro settings form (v1.15.2 — dual typography & luminous frosted glass).
// Rust remains the sole config owner: this view receives only non-secret
// key-presence metadata and sends changed keys over stdin, never argv or the
// environment.
Column {
  id: root

  property color foreground: Commons.Color.foreground
  property color urgent: Commons.Color.urgent
  property color surface: Commons.Color.popups.background
  property string fontFamily: Style.font.family
  property string monoFont: fontFamily
  property string uiFont: (Style.font.menuFamily && Style.font.menuFamily.length > 0 && Style.font.menuFamily !== "monospace")
    ? Style.font.menuFamily
    : "Inter Display"
  property bool showPercent: true
  property bool showMeter: true
  property bool compact: false
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property bool isDark: (0.2126 * surface.r + 0.7152 * surface.g + 0.0722 * surface.b) < 0.5
  readonly property color specularTop: Qt.rgba(1, 1, 1, isDark ? 0.08 : 0.35)
  readonly property int pillRadius: Math.max(8, Style.cornerRadius)
  readonly property int cardRadius: Math.max(8, pillRadius)
  readonly property int fieldRadius: Math.max(7, pillRadius - 1)

  property var snapshot: ({ primary_choices: [], keys: [] })
  property string selectedPrimary: ""
  property string stateStdout: ""
  property string stateStderr: ""
  property string applyStdout: ""
  property string applyStderr: ""
  property string errorText: ""
  property string statusText: ""
  property string pendingPayload: ""
  property int stateExitCode: -1
  property int applyExitCode: -1
  property bool loading: false
  property bool saving: false
  readonly property bool canSave: !loading && !saving
    && (selectedPrimary !== "" || snapshot.primary_choices.length === 0)

  signal saved()
  signal fallbackRequested()
  signal nousLoginRequested()
  signal copilotLoginRequested()
  signal showPercentRequested(bool enabled)
  signal showMeterRequested(bool enabled)
  signal compactRequested(bool enabled)
  signal closeRequested()

  spacing: Style.space(12)
  focus: visible
  Keys.onEscapePressed: closeRequested()

  function safe(value) { return Model.autoTextSafe(value) }
  function alpha(color, opacity) { return Qt.rgba(color.r, color.g, color.b, opacity) }

  function load() {
    if (stateProcess.running || applyProcess.running) return
    loading = true
    errorText = ""
    statusText = ""
    stateStdout = ""
    stateStderr = ""
    stateExitCode = -1
    stateProcess.running = true
  }

  function finishLoad() {
    loading = false
    if (stateExitCode !== 0) {
      var detail = Model.errorMessage(stateStderr)
      errorText = detail.indexOf("unrecognized subcommand") >= 0
        ? "This installed ai-usagebar binary predates native settings. Update the package, or use the terminal settings fallback."
        : detail
      snapshot = ({ primary_choices: [], keys: [] })
      selectedPrimary = ""
      return
    }
    var parsed = Model.parseSettingsSnapshot(stateStdout)
    if (!parsed.ok) {
      errorText = parsed.error
      snapshot = ({ primary_choices: [], keys: [] })
      selectedPrimary = ""
      return
    }
    snapshot = parsed
    selectedPrimary = parsed.primary
  }

  function collectChanges() {
    var changes = []
    for (var i = 0; i < keyRepeater.count; i++) {
      var row = keyRepeater.itemAt(i)
      if (!row || row.pendingAction === "unchanged") continue
      changes.push({
        id: row.vendorId,
        action: row.pendingAction,
        value: row.pendingAction === "set" ? row.secretText : ""
      })
    }
    return changes
  }

  function save() {
    if (!canSave) return
    var built = Model.buildSettingsPatch(selectedPrimary, collectChanges())
    if (!built.ok) {
      errorText = built.error
      return
    }
    saving = true
    errorText = ""
    statusText = ""
    applyStdout = ""
    applyStderr = ""
    applyExitCode = -1
    pendingPayload = built.payload
    applyProcess.running = true
  }

  function scrubSecrets() {
    pendingPayload = ""
    for (var i = 0; i < keyRepeater.count; i++) {
      var row = keyRepeater.itemAt(i)
      if (row) row.scrub()
    }
  }

  function finishApply() {
    saving = false
    // The Rust process has consumed the stdin patch. Do not retain credentials
    // in this long-lived shell, even if the save failed.
    scrubSecrets()
    if (applyExitCode !== 0 || !Model.parseSettingsApplyResult(applyStdout)) {
      errorText = Model.errorMessage(applyStderr || "The settings command did not confirm the save.")
      return
    }
    saved()
    load()
    // load() clears stale status before refreshing the snapshot, so set the
    // confirmation afterwards and keep it visible while the refresh runs.
    statusText = "Settings saved. Usage is refreshing."
  }

  onVisibleChanged: {
    if (visible) {
      load()
      Qt.callLater(function() { root.forceActiveFocus() })
    }
    else scrubSecrets()
  }

  Process {
    id: stateProcess
    running: false
    command: ["ai-usagebar", "settings", "show"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.stateStdout = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.stateStderr = text
    }
    onExited: function(exitCode, exitStatus) {
      root.stateExitCode = exitCode
      Qt.callLater(root.finishLoad)
    }
  }

  Process {
    id: applyProcess
    running: false
    command: ["ai-usagebar", "settings", "apply"]
    stdinEnabled: true

    onStarted: {
      write(root.pendingPayload + "\n")
      root.pendingPayload = ""
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStdout = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStderr = text
    }
    onExited: function(exitCode, exitStatus) {
      root.applyExitCode = exitCode
      Qt.callLater(root.finishApply)
    }
  }

  // --------------------------------------------------- rounded glass controls
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

  component SettingToggleCard: Rectangle {
    id: toggleCard
    property string label: ""
    property string description: ""
    property bool checked: false
    signal clicked()

    readonly property bool hot: toggleMouse.containsMouse
    width: parent ? parent.width : Style.space(240)
    implicitHeight: Math.max(Style.space(52), toggleContent.implicitHeight + Style.space(20))
    radius: root.cardRadius
    color: activeFocus
      ? root.alpha(root.foreground, 0.09)
      : (hot ? root.alpha(root.foreground, 0.07) : root.alpha(root.foreground, 0.04))
    border.width: 1
    border.color: activeFocus
      ? root.alpha(Commons.Color.accent, 0.65)
      : (hot ? root.alpha(root.foreground, 0.22) : root.alpha(root.foreground, 0.11))
    opacity: enabled ? 1 : 0.45

    activeFocusOnTab: enabled
    Keys.onReturnPressed: if (enabled) toggleCard.clicked()
    Keys.onEnterPressed: if (enabled) toggleCard.clicked()
    Keys.onSpacePressed: if (enabled) toggleCard.clicked()

    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

    GlassHighlight { inset: Style.space(7) }

    Row {
      id: toggleContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(12)

      Column {
        width: parent.width - toggleSwitch.width - parent.spacing
        spacing: Style.space(3)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          width: parent.width
          text: toggleCard.label
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.uiFont
          font.pixelSize: Style.font.bodySmall
          font.weight: Font.DemiBold
          wrapMode: Text.WordWrap
        }

        Text {
          visible: toggleCard.description !== ""
          width: parent.width
          text: toggleCard.description
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      ToggleSwitch {
        id: toggleSwitch
        checked: toggleCard.checked
        rounded: true
        interactive: false
        foreground: root.foreground
        accent: Commons.Color.accent
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: toggleMouse
      anchors.fill: parent
      enabled: toggleCard.enabled
      hoverEnabled: true
      cursorShape: toggleCard.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: {
        toggleCard.forceActiveFocus()
        toggleCard.clicked()
      }
    }
  }

  component GlassButton: Rectangle {
    id: glassBtn
    property string text: ""
    property string iconText: ""
    property string trailingIcon: ""
    property bool iconSpinning: false
    property bool primary: false
    property bool leftAlign: false
    signal clicked()

    readonly property bool hot: btnMouse.containsMouse
    readonly property bool pressed: btnMouse.pressed

    implicitWidth: btnRow.implicitWidth + Style.space(26)
    implicitHeight: Math.max(Style.space(36), btnRow.implicitHeight + Style.space(16))
    radius: root.cardRadius
    opacity: enabled ? 1 : 0.45
    scale: pressed && enabled ? 0.985 : 1

    color: primary
      ? (pressed ? root.alpha(Commons.Color.accent, 0.30)
        : (activeFocus || hot ? root.alpha(Commons.Color.accent, 0.24) : root.alpha(Commons.Color.accent, 0.16)))
      : (pressed ? root.alpha(root.foreground, 0.14)
        : (activeFocus ? root.alpha(root.foreground, 0.10)
          : (hot ? root.alpha(root.foreground, 0.08) : root.alpha(root.foreground, 0.045))))
    border.width: 1
    border.color: primary
      ? (activeFocus || hot ? root.alpha(Commons.Color.accent, 0.72) : root.alpha(Commons.Color.accent, 0.45))
      : (activeFocus ? root.alpha(Commons.Color.accent, 0.65)
        : (hot ? root.alpha(root.foreground, 0.24) : root.alpha(root.foreground, 0.13)))

    activeFocusOnTab: enabled
    Keys.onReturnPressed: if (enabled) glassBtn.clicked()
    Keys.onEnterPressed: if (enabled) glassBtn.clicked()
    Keys.onSpacePressed: if (enabled) glassBtn.clicked()

    Behavior on color { ColorAnimation { duration: Style.duration(110) } }
    Behavior on border.color { ColorAnimation { duration: Style.duration(110) } }
    Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

    GlassHighlight { inset: Style.space(7) }

    Row {
      id: btnRow
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: glassBtn.leftAlign ? parent.left : undefined
      anchors.leftMargin: glassBtn.leftAlign ? Style.space(12) : 0
      anchors.horizontalCenter: glassBtn.leftAlign ? undefined : parent.horizontalCenter
      spacing: Style.space(8)

      Text {
        visible: glassBtn.iconText !== ""
        text: glassBtn.iconText
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.monoFont
        font.pixelSize: Style.font.icon
        transformOrigin: Item.Center
        anchors.verticalCenter: parent.verticalCenter

        RotationAnimation on rotation {
          from: 0
          to: 360
          duration: Style.duration(900)
          loops: Animation.Infinite
          running: glassBtn.iconSpinning && !Style.reduceMotion
        }
      }

      Text {
        visible: glassBtn.text !== ""
        text: glassBtn.text
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.uiFont
        font.pixelSize: Style.font.bodySmall
        font.weight: glassBtn.primary ? Font.DemiBold : Font.Medium
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Text {
      visible: glassBtn.trailingIcon !== ""
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: glassBtn.trailingIcon
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.monoFont
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: btnMouse
      anchors.fill: parent
      enabled: glassBtn.enabled
      hoverEnabled: true
      cursorShape: glassBtn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: {
        glassBtn.forceActiveFocus()
        glassBtn.clicked()
      }
    }
  }

  component GlassDropdown: Rectangle {
    id: dropdown
    property string value: ""
    property var options: []
    signal changed(string nextValue)

    function optionValue(o) { return (o && typeof o === "object") ? String(o.value) : String(o) }
    function optionLabel(o) { return (o && typeof o === "object") ? String(o.label) : String(o) }
    function currentLabel() {
      for (var i = 0; i < options.length; i++)
        if (optionValue(options[i]) === value) return optionLabel(options[i])
      return value
    }

    readonly property bool hot: triggerMouse.containsMouse
    implicitHeight: Style.space(36)
    radius: root.cardRadius
    color: activeFocus || menuPopup.opened
      ? root.alpha(root.foreground, 0.09)
      : (hot ? root.alpha(root.foreground, 0.075) : root.alpha(root.foreground, 0.045))
    border.width: 1
    border.color: activeFocus || menuPopup.opened
      ? root.alpha(Commons.Color.accent, 0.65)
      : (hot ? root.alpha(root.foreground, 0.24) : root.alpha(root.foreground, 0.13))
    opacity: enabled ? 1 : 0.45

    activeFocusOnTab: enabled
    Keys.onPressed: function(event) {
      if (!enabled) return
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
          || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
        menuPopup.opened ? menuPopup.close() : menuPopup.open()
        event.accepted = true
      } else if (event.key === Qt.Key_Escape && menuPopup.opened) {
        menuPopup.close()
        event.accepted = true
      }
    }

    Behavior on color { ColorAnimation { duration: Style.duration(110) } }
    Behavior on border.color { ColorAnimation { duration: Style.duration(110) } }

    GlassHighlight { inset: Style.space(7) }

    Text {
      anchors.left: parent.left
      anchors.right: chevronIcon.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(8)
      text: dropdown.currentLabel()
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.uiFont
      font.pixelSize: Style.font.bodySmall
      font.weight: Font.Medium
      elide: Text.ElideRight
    }

    Text {
      id: chevronIcon
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: menuPopup.opened ? "󰅃" : "󰅀"
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.monoFont
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      id: triggerMouse
      anchors.fill: parent
      enabled: dropdown.enabled
      hoverEnabled: true
      cursorShape: dropdown.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: {
        dropdown.forceActiveFocus()
        menuPopup.opened ? menuPopup.close() : menuPopup.open()
      }
    }

    Popup {
      id: menuPopup
      x: 0
      y: dropdown.height + Style.space(4)
      width: dropdown.width
      closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape
      padding: Style.space(4)
      focus: true

      background: Rectangle {
        radius: root.cardRadius
        color: Commons.Color.popups.background
        border.width: 1
        border.color: root.alpha(root.foreground, 0.18)

        GlassHighlight { inset: Style.space(7) }
      }

      onOpened: {
        menuList.currentIndex = Math.max(0, menuList.indexOfValue(dropdown.value))
        menuList.forceActiveFocus()
      }

      contentItem: ListView {
        id: menuList
        implicitHeight: Math.min(dropdown.options.length * Style.space(32) + Math.max(0, dropdown.options.length - 1) * Style.space(2),
                                 Style.space(32) * 8 + Style.space(14))
        spacing: Style.space(2)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: dropdown.options
        currentIndex: -1

        function indexOfValue(v) {
          for (var i = 0; i < dropdown.options.length; i++)
            if (dropdown.optionValue(dropdown.options[i]) === v) return i
          return -1
        }

        function selectCurrent() {
          if (currentIndex < 0 || currentIndex >= dropdown.options.length) return
          var v = dropdown.optionValue(dropdown.options[currentIndex])
          dropdown.value = v
          dropdown.changed(v)
          menuPopup.close()
        }

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { menuPopup.close(); event.accepted = true }
          else if (event.key === Qt.Key_Down || event.text === "j") {
            menuList.currentIndex = Math.min(dropdown.options.length - 1, menuList.currentIndex + 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up || event.text === "k") {
            menuList.currentIndex = Math.max(0, menuList.currentIndex - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            menuList.selectCurrent()
            event.accepted = true
          }
        }

        delegate: Rectangle {
          id: optRow
          required property var modelData
          required property int index
          readonly property bool isSelected: dropdown.optionValue(modelData) === dropdown.value
          readonly property bool isCurrent: index === menuList.currentIndex
          width: menuList.width
          height: Style.space(32)
          radius: Math.max(6, root.cardRadius - 3)
          color: isCurrent
            ? root.alpha(root.foreground, 0.13)
            : (isSelected ? root.alpha(root.foreground, 0.06) : "transparent")
          Behavior on color { ColorAnimation { duration: Style.duration(100) } }

          Text {
            anchors.left: parent.left
            anchors.right: checkMark.left
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: dropdown.optionLabel(optRow.modelData)
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.uiFont
            font.pixelSize: Style.font.bodySmall
            font.weight: optRow.isSelected ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
          }

          Text {
            id: checkMark
            visible: optRow.isSelected
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: "󰄬"
            textFormat: Text.PlainText
            color: Commons.Color.accent
            font.family: root.monoFont
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: menuList.currentIndex = optRow.index
            onClicked: menuList.selectCurrent()
          }
        }
      }
    }
  }

  // ----------------------------------------------------------------- loading
  Column {
    visible: root.loading
    width: parent.width
    spacing: Style.space(8)

    PanelSectionHeader {
      text: "SETTINGS"
      foreground: root.foreground
      fontFamily: root.uiFont
      font.letterSpacing: 0.85
    }
    Text {
      width: parent.width
      text: "Loading configuration…"
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.uiFont
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignHCenter
    }
  }

  // ----------------------------------------------------------------- display
  Column {
    visible: !root.loading
    width: parent.width
    spacing: Style.space(8)

    PanelSectionHeader {
      text: "DISPLAY"
      foreground: root.foreground
      fontFamily: root.uiFont
      font.letterSpacing: 0.85
    }

    SettingToggleCard {
      width: parent.width
      label: "Show the percentage next to each mark"
      description: "Turn this off for a strip of marks and dials. The ring still carries the reading, \"sign in\" stays, and the tooltip still has the numbers. Applies immediately."
      checked: root.showPercent
      enabled: !root.saving && !root.compact
      onClicked: root.showPercentRequested(!root.showPercent)
    }

    SettingToggleCard {
      width: parent.width
      label: "Show the quota ring around each provider"
      description: "The circular ring fills clockwise as the plan is used, with a pace pip where the plan's window is known. Applies immediately."
      checked: root.showMeter
      enabled: !root.saving
      onClicked: root.showMeterRequested(!root.showMeter)
    }

    SettingToggleCard {
      width: parent.width
      label: "Compact strip"
      description: "Dials and marks only (a prepaid balance keeps its amount), for a crowded bar. Applies immediately."
      checked: root.compact
      enabled: !root.saving
      onClicked: root.compactRequested(!root.compact)
    }
  }

  // ------------------------------------------------------------------- error
  Rectangle {
    visible: root.errorText !== ""
    width: parent.width
    implicitHeight: errorColumn.implicitHeight + Style.space(20)
    radius: root.cardRadius
    color: root.alpha(root.urgent, 0.08)
    border.width: 1
    border.color: root.alpha(root.urgent, 0.35)

    GlassHighlight { inset: Style.space(7) }

    Rectangle {
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

    Column {
      id: errorColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(15)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(8)

      Text {
        width: parent.width
        text: root.safe(root.errorText)
        textFormat: Text.PlainText
        color: root.urgent
        font.family: root.uiFont
        font.pixelSize: Style.font.bodySmall
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
      }
      Row {
        spacing: Style.space(8)
        GlassButton {
          text: "Retry"
          onClicked: root.load()
        }
        GlassButton {
          text: "Open terminal settings"
          onClicked: root.fallbackRequested()
        }
      }
    }
  }

  // -------------------------------------------------------- primary provider
  Column {
    visible: !root.loading && root.snapshot.primary_choices.length > 0
    width: parent.width
    spacing: Style.space(8)

    PanelSeparator {
      width: parent.width
      foreground: root.foreground
    }
    PanelSectionHeader {
      text: "PRIMARY PROVIDER"
      foreground: root.foreground
      fontFamily: root.uiFont
      font.letterSpacing: 0.85
    }
    Text {
      width: parent.width
      text: "Used by the CLI, Waybar, TUI, and as this panel's preferred provider."
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
    GlassDropdown {
      id: primaryDropdown
      width: parent.width
      value: root.selectedPrimary
      options: root.snapshot.primary_choices
      enabled: !root.saving
      onChanged: function(nextValue) { root.selectedPrimary = nextValue }
    }
  }

  // ---------------------------------------------------------- authentication
  Column {
    visible: !root.loading
    width: parent.width
    spacing: Style.space(8)

    PanelSeparator {
      width: parent.width
      foreground: root.foreground
    }
    PanelSectionHeader {
      text: "AUTHENTICATION"
      foreground: root.foreground
      fontFamily: root.uiFont
      font.letterSpacing: 0.85
    }
    Text {
      width: parent.width
      text: "OAuth login opens in a terminal. Complete it, then return here, choose the provider as primary, save, and press Refresh."
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
    GlassButton {
      width: parent.width
      leftAlign: true
      text: "Log in with Nous Research"
      iconText: "󰍂"
      trailingIcon: "󰏌"
      enabled: !root.saving
      onClicked: {
        root.statusText = "Nous Research login is opening in a terminal."
        root.nousLoginRequested()
      }
    }
    GlassButton {
      width: parent.width
      leftAlign: true
      text: "Log in with GitHub Copilot"
      iconText: "󰊤"
      trailingIcon: "󰏌"
      enabled: !root.saving
      onClicked: {
        root.statusText = "GitHub sign-in is opening in a terminal. Complete it, then choose GitHub Copilot as primary and save."
        root.copilotLoginRequested()
      }
    }
  }

  // ------------------------------------------------------------- credentials
  Column {
    visible: !root.loading && root.snapshot.keys.length > 0
    width: parent.width
    spacing: Style.space(8)

    PanelSeparator {
      width: parent.width
      foreground: root.foreground
    }
    PanelSectionHeader {
      text: "CREDENTIALS"
      foreground: root.foreground
      fontFamily: root.uiFont
      font.letterSpacing: 0.85
    }
    Text {
      width: parent.width
      text: "Stored values are never loaded into the shell. Leave a field blank to keep its current value, or use the clear button to remove an inline credential. Environment variables take precedence."
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Repeater {
      id: keyRepeater
      model: root.snapshot.keys

      Rectangle {
        id: keyCard
        required property var modelData
        readonly property string vendorId: String(modelData.id || "")
        property string pendingAction: "unchanged"
        property alias secretText: keyField.text

        readonly property bool isStored: pendingAction === "unchanged"
          && (modelData.environment_configured || modelData.inline_configured)
        readonly property string badgeText: pendingAction === "clear" ? "will clear"
          : pendingAction === "set" ? "new key"
          : modelData.environment_configured ? "env override"
          : modelData.inline_configured ? "stored"
          : "not set"

        function scrub() {
          keyField.text = ""
          pendingAction = "unchanged"
        }

        width: keyRepeater.parent.width
        implicitHeight: keyColumn.implicitHeight + Style.space(20)
        radius: root.cardRadius
        color: root.alpha(root.foreground, 0.04)
        border.width: 1
        border.color: pendingAction === "clear"
          ? root.alpha(root.urgent, 0.45)
          : (pendingAction === "set" ? root.alpha(Commons.Color.accent, 0.50) : root.alpha(root.foreground, 0.11))
        Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

        GlassHighlight { inset: Style.space(7) }

        Column {
          id: keyColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: Math.max(keyLabel.implicitHeight, statusPill.implicitHeight)

            Text {
              id: keyLabel
              anchors.left: parent.left
              anchors.right: statusPill.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.safe(keyCard.modelData.label)
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.uiFont
              font.pixelSize: Style.font.bodySmall
              font.weight: Font.DemiBold
              elide: Text.ElideRight
            }

            Rectangle {
              id: statusPill
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              implicitWidth: keyStatus.implicitWidth + Style.space(14)
              implicitHeight: keyStatus.implicitHeight + Style.space(6)
              radius: implicitHeight / 2
              color: keyCard.pendingAction === "clear"
                ? root.alpha(root.urgent, 0.16)
                : (keyCard.pendingAction === "set"
                  ? root.alpha(Commons.Color.accent, 0.20)
                  : (keyCard.isStored ? root.alpha(root.foreground, 0.10) : root.alpha(root.foreground, 0.05)))
              border.width: 1
              border.color: keyCard.pendingAction === "clear"
                ? root.alpha(root.urgent, 0.40)
                : (keyCard.pendingAction === "set"
                  ? root.alpha(Commons.Color.accent, 0.45)
                  : root.alpha(root.foreground, keyCard.isStored ? 0.18 : 0.10))
              Behavior on color { ColorAnimation { duration: Style.duration(120) } }
              Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

              Text {
                id: keyStatus
                anchors.centerIn: parent
                text: keyCard.badgeText
                textFormat: Text.PlainText
                color: keyCard.pendingAction === "clear"
                  ? root.urgent
                  : (keyCard.pendingAction === "set" || keyCard.isStored ? root.foreground : root.dim)
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                font.weight: keyCard.isStored || keyCard.pendingAction !== "unchanged" ? Font.DemiBold : Font.Medium
                font.letterSpacing: 0.15
              }
            }
          }

          Text {
            visible: text !== ""
            width: parent.width
            text: {
              var parts = []
              if (keyCard.modelData.environment) parts.push(root.safe(keyCard.modelData.environment))
              if (keyCard.modelData.secret_label) parts.push(root.safe(keyCard.modelData.secret_label))
              if (keyCard.modelData.note) parts.push(root.safe(keyCard.modelData.note))
              return parts.join(" · ")
            }
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: keyField
              width: parent.width - clearButton.width - parent.spacing
              password: true
              enabled: !root.saving && keyCard.pendingAction !== "clear"
              opacity: enabled ? 1 : 0.45
              font.family: text.length > 0 ? root.monoFont : root.uiFont
              font.pixelSize: Style.font.bodySmall
              placeholderText: keyCard.modelData.configured
                ? "Leave blank to keep current credential"
                : "Paste " + (keyCard.modelData.secret_label || "credential")
              foreground: root.foreground
              onTextEdited: keyCard.pendingAction = text.length > 0 ? "set" : "unchanged"
              Keys.onEscapePressed: focus = false
              onAccepted: root.save()

              background: Rectangle {
                radius: root.fieldRadius
                color: keyField.activeFocus
                  ? root.alpha(root.foreground, 0.09)
                  : (keyField.hovered ? root.alpha(root.foreground, 0.07) : root.alpha(root.foreground, 0.045))
                border.width: 1
                border.color: keyField.activeFocus
                  ? root.alpha(Commons.Color.accent, 0.65)
                  : (keyField.hovered ? root.alpha(root.foreground, 0.22) : root.alpha(root.foreground, 0.13))
                Behavior on color { ColorAnimation { duration: Style.duration(110) } }
                Behavior on border.color { ColorAnimation { duration: Style.duration(110) } }
              }
            }

            PanelActionButton {
              id: clearButton
              anchors.verticalCenter: keyField.verticalCenter
              radius: root.fieldRadius
              size: Math.max(Style.space(28), Math.round(keyField.height))
              iconText: keyCard.pendingAction === "clear" ? "󰕌" : "󰆴"
              tooltipText: keyCard.pendingAction === "clear"
                ? "Keep the stored key" : "Clear the stored inline key"
              foreground: root.foreground
              hoverColor: keyCard.pendingAction === "clear" ? root.foreground : root.urgent
              fontFamily: root.monoFont
              focusable: true
              enabled: !root.saving && (keyCard.modelData.inline_configured || keyCard.pendingAction === "clear")
              onClicked: {
                if (keyCard.pendingAction === "clear") {
                  keyCard.pendingAction = "unchanged"
                } else {
                  keyField.text = ""
                  keyCard.pendingAction = "clear"
                }
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------------ status
  Rectangle {
    visible: root.statusText !== ""
    width: parent.width
    implicitHeight: savedText.implicitHeight + Style.space(16)
    radius: root.cardRadius
    color: root.alpha(root.foreground, 0.055)
    border.width: 1
    border.color: root.alpha(root.foreground, 0.15)

    GlassHighlight { inset: Style.space(7) }

    Text {
      id: savedText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      text: root.safe(root.statusText)
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }
  }

  // -------------------------------------------------------------------- save
  GlassButton {
    visible: !root.loading
      && (root.snapshot.primary_choices.length > 0 || root.snapshot.keys.length > 0)
    width: parent.width
    primary: true
    text: root.saving ? "Saving…" : "Save settings"
    iconText: root.saving ? "󰑐" : "󰄬"
    iconSpinning: root.saving
    enabled: root.canSave
    onClicked: root.save()
  }
}
