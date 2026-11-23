pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var screenshots: []
  property var visibleScreenshots: []
  property string dirName: "Pictures"
  property string screenshotsDir: ""
  property int totalCount: 0
  property string filterText: ""
  property string statusText: ""
  property string summaryText: ""
  property string pendingTrashKey: ""
  property string copiedKey: ""
  property bool pendingClear: false
  property bool busy: false
  property int cursorIndex: -1
  property string barIcon: Model.defaultIcon()
  property color foreground: Commons.Color.foreground
  property string monoFont: Style.font.family
  property bool synchronousLoad: false

  signal filterEdited(string text)
  signal filterAccepted()
  signal closeRequested()
  signal captureRequested()
  signal openFolderRequested()
  signal refreshRequested()
  signal clearAllRequested()
  signal cancelConfirmRequested()
  signal previewRequested(int index)
  signal copyRequested(var screenshot)
  signal trashRequested(var screenshot)
  signal cursorChanged(int index)

  readonly property alias searchField: searchInput
  readonly property bool searchHasFocus: searchInput.activeFocus
  readonly property color background: Commons.Color.background
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property color dim: Util.alpha(root.foreground, 0.64)
  readonly property color faint: Util.alpha(root.foreground, 0.44)
  readonly property color armedForeground: root.busy ? root.foreground : root.urgent

  readonly property string uiFont: (Style.font.menuFamily && Style.font.menuFamily !== Style.font.family && Style.font.menuFamily !== "monospace")
    ? Style.font.menuFamily
    : "Inter Display"

  readonly property int cardRadius: Math.max(10, Style.cornerRadius)
  readonly property int thumbRadius: Math.max(8, Style.cornerRadius - 2)
  readonly property int controlRadius: Math.max(8, Style.cornerRadius - 4)
  readonly property int badgeRadius: Math.max(8, Style.cornerRadius - 2)
  readonly property int cardGutter: Style.space(12)
  readonly property int cardHeight: Style.space(202)
  readonly property bool showStatusBanner: root.statusText !== "" && root.statusText !== root.summaryText
  readonly property bool confirmActive: root.pendingTrashKey !== "" || root.pendingClear

  function focusSearch() {
    searchInput.forceActiveFocus()
  }

  function clearSearch() {
    searchInput.text = ""
  }

  implicitWidth: Style.space(544)
  implicitHeight: layoutColumn.implicitHeight

  component HeaderIconButton: Rectangle {
    id: hdrBtn

    property string glyph: ""
    property string tooltipText: ""
    property bool danger: false
    property bool armed: false
    property bool buttonEnabled: true

    signal triggered()

    readonly property bool hot: hdrMouse.containsMouse && buttonEnabled

    Layout.preferredWidth: Style.space(30)
    Layout.preferredHeight: Style.space(30)
    Layout.alignment: Qt.AlignVCenter
    radius: root.controlRadius
    opacity: buttonEnabled ? 1.0 : 0.40

    color: armed
      ? Util.alpha(root.urgent, 0.20)
      : (hot
        ? (danger ? Util.alpha(root.urgent, 0.14) : Util.alpha(root.foreground, 0.11))
        : Util.alpha(root.foreground, 0.05))
    border.width: Style.spacing.hairline
    border.color: armed
      ? Util.alpha(root.urgent, 0.52)
      : (hot
        ? (danger ? Util.alpha(root.urgent, 0.34) : Util.alpha(root.foreground, 0.22))
        : Util.alpha(root.foreground, 0.11))

    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

    Rectangle {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.topMargin: 1
      anchors.leftMargin: Style.space(5)
      anchors.rightMargin: Style.space(5)
      height: 1
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, hdrBtn.hot ? 0.20 : 0.10) }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: hdrBtn.glyph
      color: hdrBtn.armed
        ? root.armedForeground
        : (hdrBtn.hot
          ? (hdrBtn.danger ? root.urgent : root.foreground)
          : root.dim)
      font.family: root.monoFont
      font.pixelSize: Style.font.icon
    }

    MouseArea {
      id: hdrMouse
      anchors.fill: parent
      enabled: hdrBtn.buttonEnabled
      hoverEnabled: true
      cursorShape: hdrBtn.buttonEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: hdrBtn.triggered()
    }

    PanelToolTip {
      visible: hdrBtn.tooltipText !== "" && hdrMouse.containsMouse
      text: hdrBtn.tooltipText
      fontFamily: root.uiFont
    }
  }

  component CardOverlayAction: Rectangle {
    id: pillAction

    property string glyph: ""
    property string label: ""
    property bool activeTint: false
    property bool danger: false
    property bool armed: false
    property bool buttonEnabled: true

    signal triggered()

    readonly property bool hot: actionMouse.containsMouse && buttonEnabled

    implicitHeight: Style.space(26)
    implicitWidth: actionRow.implicitWidth + (label !== "" ? Style.space(14) : Style.space(12))
    radius: height / 2
    opacity: buttonEnabled ? 1.0 : 0.45

    color: armed
      ? Util.alpha(root.urgent, 0.28)
      : (activeTint
        ? Util.alpha(root.accent, 0.26)
        : (hot
          ? (danger ? Util.alpha(root.urgent, 0.20) : Util.alpha(root.foreground, 0.16))
          : "transparent"))
    border.width: (armed || activeTint || hot) ? Style.spacing.hairline : 0
    border.color: armed
      ? Util.alpha(root.urgent, 0.58)
      : (activeTint
        ? Util.alpha(root.accent, 0.52)
        : (hot
          ? (danger ? Util.alpha(root.urgent, 0.40) : Util.alpha(root.foreground, 0.22))
          : "transparent"))

    Behavior on color { ColorAnimation { duration: Style.duration(110) } }
    Behavior on border.color { ColorAnimation { duration: Style.duration(110) } }

    Row {
      id: actionRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: pillAction.glyph
        color: pillAction.armed
          ? root.urgent
          : (pillAction.activeTint
            ? root.accent
            : (pillAction.hot && pillAction.danger ? root.urgent : root.foreground))
        font.family: root.monoFont
        font.pixelSize: Style.font.iconSmall + 1
      }

      Text {
        visible: pillAction.label !== ""
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: pillAction.label
        color: pillAction.armed
          ? root.urgent
          : (pillAction.activeTint
            ? root.accent
            : (pillAction.hot && pillAction.danger ? root.urgent : root.foreground))
        font.family: root.uiFont
        font.pixelSize: Style.font.caption + 1
        font.weight: Font.Medium
      }
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      enabled: pillAction.buttonEnabled
      hoverEnabled: true
      cursorShape: pillAction.buttonEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: pillAction.triggered()
    }
  }

  Column {
    id: layoutColumn
    width: parent.width
    spacing: Style.space(12)

    // Instrument-grade header matching Vitals & Notifications.
    Item {
      width: parent.width
      height: Style.space(42)

      RowLayout {
        anchors.fill: parent
        spacing: Style.space(10)

        // Rounded frosted camera icon badge.
        Rectangle {
          Layout.preferredWidth: Style.space(36)
          Layout.preferredHeight: Style.space(36)
          Layout.alignment: Qt.AlignVCenter
          radius: root.badgeRadius
          color: Util.alpha(root.foreground, 0.06)
          border.width: Style.spacing.hairline
          border.color: Util.alpha(root.foreground, 0.14)

          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            height: 1
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: "transparent" }
              GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.22) }
              GradientStop { position: 1.0; color: "transparent" }
            }
          }

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.barIcon || Model.defaultIcon()
            color: root.foreground
            font.family: root.monoFont
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
            text: "Screenshots"
            color: root.foreground
            font.family: root.uiFont
            font.pixelSize: Style.font.heading
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }

          Row {
            spacing: Style.space(6)

            Rectangle {
              width: Style.space(6)
              height: Style.space(6)
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: root.busy
                ? root.urgent
                : (root.screenshots.length > 0 ? root.accent : root.faint)
            }

            Text {
              visible: root.screenshots.length > 0 && !root.busy
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String(root.totalCount > 0 ? root.totalCount : root.screenshots.length)
              color: root.foreground
              font.family: root.monoFont
              font.pixelSize: Style.font.caption
              font.features: ({ "tnum": 1 })
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: {
                if (root.busy) return "Scanning " + root.dirName + "…"
                var n = root.totalCount > 0 ? root.totalCount : root.screenshots.length
                if (n === 0) return "Empty · " + root.dirName
                var unit = n === 1 ? "capture" : "captures"
                var shown = root.totalCount > root.screenshots.length
                  ? " (showing " + root.screenshots.length + ")"
                  : ""
                return unit + shown + "  ·  " + root.dirName
              }
              color: root.dim
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
            }
          }
        }

        RowLayout {
          Layout.alignment: Qt.AlignVCenter
          spacing: Style.space(6)

          // Primary frosted Capture action button.
          Rectangle {
            id: captureButton
            readonly property bool hot: captureMouse.containsMouse && !root.busy
            Layout.preferredHeight: Style.space(30)
            Layout.preferredWidth: captureRow.implicitWidth + Style.space(18)
            Layout.alignment: Qt.AlignVCenter
            radius: root.controlRadius
            opacity: root.busy ? 0.45 : 1.0
            color: hot ? Util.alpha(root.accent, 0.24) : Util.alpha(root.accent, 0.14)
            border.width: Style.spacing.hairline
            border.color: hot ? Util.alpha(root.accent, 0.54) : Util.alpha(root.accent, 0.34)

            Behavior on color { ColorAnimation { duration: Style.duration(120) } }
            Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

            Rectangle {
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.topMargin: 1
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              height: 1
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.24) }
                GradientStop { position: 1.0; color: "transparent" }
              }
            }

            Row {
              id: captureRow
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "󰐕"
                color: root.foreground
                font.family: root.monoFont
                font.pixelSize: Style.font.iconSmall + 1
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Capture"
                color: root.foreground
                font.family: root.uiFont
                font.pixelSize: Style.font.bodySmall
                font.weight: Font.Medium
              }
            }

            MouseArea {
              id: captureMouse
              anchors.fill: parent
              enabled: !root.busy
              hoverEnabled: true
              cursorShape: root.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
              onClicked: root.captureRequested()
            }

            PanelToolTip {
              visible: captureMouse.containsMouse
              text: "Take a new screenshot"
              fontFamily: root.uiFont
            }
          }

          HeaderIconButton {
            glyph: "󰝰"
            tooltipText: "Open screenshots folder"
            buttonEnabled: root.screenshotsDir !== ""
            onTriggered: root.openFolderRequested()
          }

          HeaderIconButton {
            glyph: "󰑐"
            tooltipText: "Refresh"
            buttonEnabled: !root.busy
            onTriggered: root.refreshRequested()
          }

          HeaderIconButton {
            glyph: root.pendingClear ? "󰄬" : "󰩹"
            tooltipText: root.pendingClear
              ? "Confirm clearing all screenshots"
              : "Clear all screenshots"
            danger: true
            armed: root.pendingClear
            buttonEnabled: !root.busy && root.screenshots.length > 0
            onTriggered: root.clearAllRequested()
          }

          HeaderIconButton {
            glyph: "󰅖"
            tooltipText: "Close"
            onTriggered: root.closeRequested()
          }
        }
      }
    }

    // Frosted search / filter capsule.
    Rectangle {
      id: searchWell
      width: parent.width
      height: Style.space(34)
      radius: root.controlRadius
      color: searchInput.activeFocus
        ? Util.alpha(root.foreground, 0.08)
        : Util.alpha(root.foreground, 0.045)
      border.width: Style.spacing.hairline
      border.color: searchInput.activeFocus
        ? Util.alpha(root.accent, 0.56)
        : Util.alpha(root.foreground, 0.12)

      Behavior on color { ColorAnimation { duration: Style.duration(120) } }
      Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Style.space(11)
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(8)

        Text {
          Layout.alignment: Qt.AlignVCenter
          textFormat: Text.PlainText
          text: "󰍉"
          color: searchInput.activeFocus ? root.accent : root.faint
          font.family: root.monoFont
          font.pixelSize: Style.font.icon
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: searchInput.text.length === 0
            textFormat: Text.PlainText
            text: "Filter screenshots by name or date…"
            color: root.faint
            font.family: root.uiFont
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          TextInput {
            id: searchInput
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: root.foreground
            selectionColor: Util.alpha(root.accent, 0.36)
            selectedTextColor: root.foreground
            font.family: root.uiFont
            font.pixelSize: Style.font.body
            maximumLength: 100
            enabled: !root.busy
            clip: true
            selectByMouse: true
            onTextChanged: root.filterEdited(text)
            onAccepted: root.filterAccepted()
            Keys.onEscapePressed: root.closeRequested()
          }
        }

        Rectangle {
          visible: root.filterText.length > 0
          Layout.alignment: Qt.AlignVCenter
          implicitWidth: matchBadgeText.implicitWidth + Style.space(10)
          implicitHeight: Style.space(20)
          radius: implicitHeight / 2
          color: Util.alpha(root.foreground, 0.08)

          Text {
            id: matchBadgeText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.visibleScreenshots.length + " / " + root.screenshots.length
            color: root.dim
            font.family: root.monoFont
            font.pixelSize: Style.font.caption
            font.features: ({ "tnum": 1 })
          }
        }

        Rectangle {
          id: clearSearchBtn
          visible: searchInput.text.length > 0
          Layout.preferredWidth: Style.space(22)
          Layout.preferredHeight: Style.space(22)
          Layout.alignment: Qt.AlignVCenter
          radius: width / 2
          color: clearSearchMouse.containsMouse ? Util.alpha(root.foreground, 0.14) : "transparent"

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "󰅖"
            color: clearSearchMouse.containsMouse ? root.foreground : root.dim
            font.family: root.monoFont
            font.pixelSize: Style.font.iconSmall
          }

          MouseArea {
            id: clearSearchMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              searchInput.text = ""
              searchInput.forceActiveFocus()
            }
          }
        }
      }
    }

    // Transient frosted status / armed-trash confirmation banner.
    Rectangle {
      visible: root.showStatusBanner
      width: parent.width
      implicitHeight: statusRow.implicitHeight + Style.space(14)
      radius: root.controlRadius
      color: root.confirmActive
        ? Util.alpha(root.urgent, 0.14)
        : Util.alpha(root.accent, 0.12)
      border.width: Style.spacing.hairline
      border.color: root.confirmActive
        ? Util.alpha(root.urgent, 0.36)
        : Util.alpha(root.accent, 0.30)

      RowLayout {
        id: statusRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(8)

        Text {
          Layout.alignment: Qt.AlignVCenter
          textFormat: Text.PlainText
          text: root.confirmActive ? "󰀨" : "󰄬"
          color: root.confirmActive ? root.urgent : root.accent
          font.family: root.monoFont
          font.pixelSize: Style.font.icon
        }

        Text {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          textFormat: Text.PlainText
          text: root.statusText
          color: root.foreground
          font.family: root.uiFont
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Rectangle {
          visible: root.confirmActive
          Layout.alignment: Qt.AlignVCenter
          implicitWidth: cancelLabel.implicitWidth + Style.space(14)
          implicitHeight: Style.space(24)
          radius: height / 2
          color: cancelMouse.containsMouse ? Util.alpha(root.foreground, 0.14) : Util.alpha(root.foreground, 0.07)
          border.width: Style.spacing.hairline
          border.color: Util.alpha(root.foreground, 0.16)

          Text {
            id: cancelLabel
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "Cancel"
            color: root.foreground
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            font.weight: Font.Medium
          }

          MouseArea {
            id: cancelMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.cancelConfirmRequested()
          }
        }
      }
    }

    // Serene frosted empty state.
    Rectangle {
      visible: !root.busy && root.visibleScreenshots.length === 0
      width: parent.width
      height: Style.space(188)
      radius: root.cardRadius
      color: Util.alpha(root.foreground, 0.035)
      border.width: Style.spacing.hairline
      border.color: Util.alpha(root.foreground, 0.10)

      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 1
        anchors.leftMargin: Style.space(14)
        anchors.rightMargin: Style.space(14)
        height: 1
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.12) }
          GradientStop { position: 1.0; color: "transparent" }
        }
      }

      Column {
        anchors.centerIn: parent
        width: parent.width - Style.space(48)
        spacing: Style.space(10)

        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Style.space(44)
          height: Style.space(44)
          radius: root.badgeRadius + 2
          color: Util.alpha(root.foreground, 0.055)
          border.width: Style.spacing.hairline
          border.color: Util.alpha(root.foreground, 0.12)

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.filterText !== "" ? "󰍉" : (root.barIcon || Model.defaultIcon())
            color: root.dim
            font.family: root.monoFont
            font.pixelSize: Style.font.iconLarge + 2
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.filterText !== "" ? "No matching screenshots" : "No screenshots yet"
          color: root.foreground
          font.family: root.uiFont
          font.pixelSize: Style.font.title
          font.weight: Font.DemiBold
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.filterText !== ""
            ? "Try a shorter filename or date, or clear the search filter."
            : "Click Capture above or right-click the bar camera icon to take your first screenshot."
          color: root.dim
          font.family: root.uiFont
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }

    // 2-column frosted-glass screenshot gallery grid.
    GridView {
      id: galleryGrid
      visible: root.visibleScreenshots.length > 0
      width: parent.width
      readonly property int columns: 2
      readonly property int halfGutter: Math.floor(root.cardGutter / 2)
      cellWidth: Math.max(Style.space(180), Math.floor(width / columns))
      cellHeight: root.cardHeight + root.cardGutter
      height: Math.min(Math.max(0, contentHeight - root.cardGutter), root.cardHeight * 2 + root.cardGutter)
      model: root.visibleScreenshots
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      delegate: Item {
        id: cellItem
        required property int index
        required property var modelData

        width: galleryGrid.cellWidth
        height: galleryGrid.cellHeight

        readonly property bool isRightCol: (cellItem.index % galleryGrid.columns) === 1
        readonly property string itemKey: Model.screenshotKey(modelData)
        readonly property bool hasCursor: root.cursorIndex === cellItem.index
        readonly property bool armed: root.pendingTrashKey !== "" && root.pendingTrashKey === itemKey
        readonly property bool justCopied: root.copiedKey !== "" && root.copiedKey === itemKey

        Rectangle {
          id: cardSurface
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: cellItem.isRightCol ? galleryGrid.halfGutter : 0
          anchors.rightMargin: cellItem.isRightCol ? 0 : galleryGrid.halfGutter
          height: root.cardHeight
          radius: root.cardRadius
          color: cellItem.hasCursor
            ? Util.alpha(root.foreground, 0.085)
            : Util.alpha(root.foreground, 0.045)
          border.width: Style.spacing.hairline
          border.color: cellItem.armed
            ? Util.alpha(root.urgent, 0.56)
            : (cellItem.hasCursor
              ? Util.alpha(root.foreground, 0.24)
              : Util.alpha(root.foreground, 0.11))

          Behavior on color { ColorAnimation { duration: Style.duration(140) } }
          Behavior on border.color { ColorAnimation { duration: Style.duration(140) } }

          // Subtle top specular sheen on the frosted glass card.
          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: Math.round(cardSurface.radius * 0.8)
            anchors.rightMargin: Math.round(cardSurface.radius * 0.8)
            height: 1
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: "transparent" }
              GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, cellItem.hasCursor ? 0.18 : 0.10) }
              GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, cellItem.hasCursor ? 0.28 : 0.16) }
              GradientStop { position: 0.75; color: Qt.rgba(1, 1, 1, cellItem.hasCursor ? 0.18 : 0.10) }
              GradientStop { position: 1.0; color: "transparent" }
            }
          }

          HoverHandler {
            id: cardHover
            onHoveredChanged: {
              if (cardHover.hovered) root.cursorChanged(cellItem.index)
              else if (root.cursorIndex === cellItem.index) root.cursorChanged(-1)
            }
          }

          // Concentric rounded 16:9 thumbnail viewport.
          Rectangle {
            id: thumbFrame
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Style.space(6)
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            height: Style.space(143)
            radius: root.thumbRadius
            color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.52)
            clip: true

            Item {
              id: thumbMask
              anchors.fill: parent
              visible: false
              layer.enabled: root.thumbRadius > 0

              Rectangle {
                anchors.fill: parent
                radius: root.thumbRadius
                color: "white"
              }
            }

            Item {
              anchors.fill: parent
              layer.enabled: root.thumbRadius > 0
              layer.smooth: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: thumbMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
              }

              Image {
                anchors.fill: parent
                source: cellItem.modelData.previewPath ? "file://" + cellItem.modelData.previewPath : ""
                sourceSize.width: Math.round(Style.space(480))
                sourceSize.height: Math.round(Style.space(270))
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: !root.synchronousLoad
              }
            }

            // Click thumbnail to open fullscreen lightbox.
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.previewRequested(cellItem.index)
              onDoubleClicked: root.previewRequested(cellItem.index)
            }

            // Crisp 1 px inner hairline rim over thumbnail edges.
            Rectangle {
              anchors.fill: parent
              radius: root.thumbRadius
              color: "transparent"
              border.width: Style.spacing.hairline
              border.color: Util.alpha(root.foreground, cellItem.hasCursor ? 0.22 : 0.13)
              Behavior on border.color { ColorAnimation { duration: Style.duration(140) } }
            }

            // Subtle top specular sheen inside thumbnail rim.
            Rectangle {
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.topMargin: 1
              anchors.leftMargin: Math.round(root.thumbRadius * 0.7)
              anchors.rightMargin: Math.round(root.thumbRadius * 0.7)
              height: 1
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.20) }
                GradientStop { position: 1.0; color: "transparent" }
              }
            }

            // Floating frosted-glass hover overlay action pill.
            Rectangle {
              id: overlayPill
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(8)
              implicitWidth: Math.min(parent.width - Style.space(12), overlayRow.implicitWidth + Style.space(10))
              implicitHeight: Style.space(32)
              radius: implicitHeight / 2
              color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.86)
              border.width: Style.spacing.hairline
              border.color: cellItem.armed
                ? Util.alpha(root.urgent, 0.46)
                : Util.alpha(root.foreground, 0.22)
              opacity: (cellItem.hasCursor || cellItem.armed || cellItem.justCopied) ? 1.0 : 0.0
              visible: opacity > 0.01

              Behavior on opacity {
                NumberAnimation { duration: Style.duration(150); easing.type: Easing.OutCubic }
              }

              Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Util.alpha(root.foreground, 0.06)
              }

              Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 1
                anchors.leftMargin: Math.round(overlayPill.radius * 0.75)
                anchors.rightMargin: Math.round(overlayPill.radius * 0.75)
                height: 1
                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: 0.0; color: "transparent" }
                  GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.24) }
                  GradientStop { position: 1.0; color: "transparent" }
                }
              }

              Row {
                id: overlayRow
                anchors.centerIn: parent
                spacing: Style.space(2)

                CardOverlayAction {
                  glyph: cellItem.justCopied ? "󰄬" : "󰅌"
                  label: cellItem.justCopied ? "Copied" : "Copy"
                  activeTint: cellItem.justCopied
                  buttonEnabled: !root.busy
                  onTriggered: root.copyRequested(cellItem.modelData)
                }

                CardOverlayAction {
                  glyph: "󰈈"
                  label: "Open"
                  buttonEnabled: !root.busy
                  onTriggered: root.previewRequested(cellItem.index)
                }

                CardOverlayAction {
                  glyph: cellItem.armed ? "󰄬" : "󰩹"
                  label: cellItem.armed ? "Confirm" : ""
                  danger: true
                  armed: cellItem.armed
                  buttonEnabled: !root.busy
                  onTriggered: root.trashRequested(cellItem.modelData)
                }
              }
            }
          }

          // Refined Inter Display filename + date and tabular mono dimensions footer.
          ColumnLayout {
            anchors.top: thumbFrame.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.topMargin: Style.space(7)
            anchors.leftMargin: Style.space(9)
            anchors.rightMargin: Style.space(9)
            anchors.bottomMargin: Style.space(7)
            spacing: Style.space(2)

            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: cellItem.modelData.name
              color: root.foreground
              font.family: root.uiFont
              font.pixelSize: Style.font.bodySmall
              font.weight: Font.Medium
              elide: Text.ElideMiddle
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(6)

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: Model.friendlyDate(cellItem.modelData.mtimeIso)
                color: root.dim
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Text {
                visible: text !== ""
                textFormat: Text.PlainText
                text: Model.numericMeta(cellItem.modelData)
                color: root.faint
                font.family: root.monoFont
                font.pixelSize: Style.font.caption
                font.features: ({ "tnum": 1 })
              }
            }
          }
        }
      }
    }

    // Quiet footer strip matching Notifications & System Updates.
    Rectangle {
      width: parent.width
      height: Style.spacing.hairline
      color: Util.alpha(root.foreground, 0.08)
    }

    RowLayout {
      width: parent.width
      spacing: Style.space(8)

      Row {
        Layout.fillWidth: true
        spacing: Style.space(6)

        Rectangle {
          width: Style.space(5)
          height: Style.space(5)
          radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          color: root.accent
          opacity: 0.85
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Copies as PNG · Trashed items stay in desktop trash"
          color: root.faint
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        textFormat: Text.PlainText
        text: "Click preview · Esc close"
        color: root.faint
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
      }
    }
  }
}
