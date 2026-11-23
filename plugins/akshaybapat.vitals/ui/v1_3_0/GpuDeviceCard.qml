import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// Frosted-glass GPU telemetry instrument card.
Rectangle {
  id: root

  property var device: ({})
  property var history: []
  property var sampleTimes: []
  property real domainStart: 0
  property real domainEnd: 0
  property real peak: 0
  property color ink: Commons.Color.foreground
  property color mutedInk: Qt.rgba(ink.r, ink.g, ink.b, 0.58)
  property color chartColor: Commons.Color.accent
  property color warnColor: "#f2b83d"
  property color criticalColor: Commons.Color.urgent
  property color specularTop: Qt.rgba(1, 1, 1, 0.08)
  property string fontFamily: Style.font.family
  property string monoFont: fontFamily
  property string uiFont: (Style.font.menuFamily && Style.font.menuFamily.length > 0 && Style.font.menuFamily !== "monospace")
    ? Style.font.menuFamily
    : "Inter Display"
  property int bodySize: Math.max(12, Style.font.body)
  property int captionSize: Math.max(10, Style.font.caption)

  readonly property bool integrated: device && device.vendor === "intel"
  readonly property var statusInfo: Model.gpuStatus(device)
  readonly property string loadSeverity: Model.loadTier(device ? device.busy : null)
  readonly property string tempSeverity: Model.tempTier(device ? device.temp : null, 0)
  readonly property bool hasVram: device && device.mem_total > 0 && device.mem_used !== null && device.mem_used !== undefined
  readonly property real vramRatio: hasVram ? Math.max(0, Math.min(1, device.mem_used / device.mem_total)) : 0
  readonly property string vramSeverity: hasVram ? Model.memTier(vramRatio) : "calm"
  readonly property bool hasClockRange: device && device.freq_mhz > 0 && device.max_freq_mhz > 0
  readonly property real clockRatio: hasClockRange ? Math.max(0, Math.min(1, device.freq_mhz / device.max_freq_mhz)) : 0
  readonly property bool isCritical: statusInfo.tier === "critical"

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function tierColor(tier, calmColor) {
    if (tier === "critical") return root.criticalColor
    if (tier === "warn") return root.warnColor
    return calmColor
  }

  readonly property color badgeInk: {
    if (statusInfo.tier === "critical") return root.criticalColor
    if (statusInfo.tier === "warn") return root.warnColor
    if (statusInfo.tier === "accent") return root.chartColor
    if (statusInfo.tier === "muted") return root.alpha(root.ink, 0.45)
    return root.alpha(root.ink, 0.72)
  }
  readonly property color activeChartColor: tierColor(loadSeverity, root.chartColor)
  readonly property color heroNumberColor: tierColor(loadSeverity, root.ink)

  objectName: "gpuCard-" + Model.gpuKey(device || {})
  color: root.alpha(root.ink, 0.05)
  border.width: 1
  border.color: root.isCritical ? root.alpha(root.criticalColor, 0.48) : root.alpha(root.ink, 0.14)
  radius: Math.max(12, Style.cornerRadius + 2)
  implicitHeight: content.implicitHeight + Style.space(32)
  Behavior on border.color { ColorAnimation { duration: Style.duration(140) } }

  // Whisper-quiet 1px top-edge inner specular catchlight.
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: Math.max(6, Math.round(parent.radius * 0.7))
    anchors.rightMargin: Math.max(6, Math.round(parent.radius * 0.7))
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

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(16)
    spacing: Style.space(12)

    // ---------- Band 1: Role + status pill + device title ----------
    Column {
      width: parent.width
      spacing: Style.space(4)

      Item {
        width: parent.width
        implicitHeight: Math.max(roleText.implicitHeight, statusPill.implicitHeight)

        Text {
          id: roleText
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.right: statusPill.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: root.integrated ? "INTEGRATED GPU" : "DEDICATED GPU"
          color: root.alpha(root.ink, 0.52)
          font.family: root.uiFont
          font.pixelSize: Math.max(9, root.captionSize - 1)
          font.weight: Font.DemiBold
          font.letterSpacing: 1.0
          elide: Text.ElideRight
        }

        Rectangle {
          id: statusPill
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: statusRow.implicitWidth + Style.space(14)
          implicitHeight: Math.max(Style.space(18), statusLabel.implicitHeight + Style.space(6))
          radius: height / 2
          color: root.alpha(root.badgeInk, root.statusInfo.tier === "calm" || root.statusInfo.tier === "muted" ? 0.09 : 0.16)
          border.width: 1
          border.color: root.alpha(root.badgeInk, root.statusInfo.tier === "calm" || root.statusInfo.tier === "muted" ? 0.16 : 0.36)
          Behavior on color { ColorAnimation { duration: Style.duration(140) } }
          Behavior on border.color { ColorAnimation { duration: Style.duration(140) } }

          Row {
            id: statusRow
            anchors.centerIn: parent
            spacing: Style.space(5)

            Rectangle {
              width: Style.space(5)
              height: width
              radius: width / 2
              color: root.badgeInk
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: statusLabel
              textFormat: Text.PlainText
              text: root.statusInfo.label
              color: root.badgeInk
              font.family: root.uiFont
              font.pixelSize: Math.max(9, root.captionSize - 1)
              font.weight: Font.Bold
              font.letterSpacing: 0.7
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: Model.gpuDisplayName(root.device)
        color: root.ink
        font.family: root.uiFont
        font.pixelSize: Math.max(15, root.bodySize + 3)
        font.weight: Font.DemiBold
        font.letterSpacing: -0.25
        elide: Text.ElideRight
      }
    }

    // ---------- Band 2: Hero utilization readout + pill gauge ----------
    Column {
      width: parent.width
      spacing: Style.space(8)

      Item {
        width: parent.width
        implicitHeight: Math.max(heroPct.implicitHeight, heroMeta.implicitHeight)

        Text {
          id: heroPct
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: Model.percent(root.device ? root.device.busy : null)
          color: root.heroNumberColor
          font.family: root.monoFont
          font.pixelSize: Math.max(32, Math.round(root.bodySize * 2.85))
          font.bold: true
          font.features: { "tnum": 1 }
        }

        Column {
          id: heroMeta
          anchors.left: heroPct.right
          anchors.leftMargin: Style.space(12)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.device && root.device.busy_estimated ? "Active estimate" : "Utilization"
            color: root.alpha(root.ink, 0.85)
            font.family: root.uiFont
            font.pixelSize: root.bodySize
            font.weight: Font.Medium
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.device && root.device.data_unavailable
              ? "Driver unavailable"
              : (root.device && root.device.busy !== null && root.device.busy !== undefined
                ? Model.chartDuration(root.sampleTimes)
                : "Activity not reported")
            color: root.mutedInk
            font.family: root.uiFont
            font.pixelSize: root.captionSize
            font.features: { "tnum": 1 }
            elide: Text.ElideRight
          }
        }
      }

      // Sleek pill-rounded utilization meter
      Rectangle {
        id: utilTrack
        width: parent.width
        height: Style.space(5)
        radius: height / 2
        color: root.alpha(root.ink, 0.08)
        border.width: 1
        border.color: root.alpha(root.ink, 0.11)

        Rectangle {
          readonly property real frac: root.device && root.device.busy !== null && root.device.busy !== undefined
            ? Math.max(0, Math.min(1, Number(root.device.busy) / 100))
            : 0
          visible: frac > 0
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          height: parent.height
          width: Math.max(height, parent.width * frac)
          radius: parent.radius
          color: root.activeChartColor
        }
      }
    }

    // ---------- Band 3: Smooth antialiased sparkline ----------
    GpuHistory {
      width: parent.width
      values: root.history
      sampleTimes: root.sampleTimes
      domainStart: root.domainStart
      domainEnd: root.domainEnd
      ink: root.ink
      lineColor: root.activeChartColor
      mutedInk: root.mutedInk
      fontFamily: root.monoFont
      monoFont: root.monoFont
      uiFont: root.uiFont
      captionSize: root.captionSize
      emptyText: root.device && root.device.data_unavailable
        ? "Driver readings unavailable"
        : (root.device && root.device.busy !== null && root.device.busy !== undefined
          ? "Collecting samples…"
          : "Activity not reported")
    }

    // ---------- Band 4: 2x2 Recessed Telemetry Tiles ----------
    Grid {
      id: metricGrid
      width: parent.width
      columns: 2
      columnSpacing: Style.space(8)
      rowSpacing: Style.space(8)
      readonly property real tileWidth: (width - columnSpacing) / 2

      MetricTile {
        width: metricGrid.tileWidth
        label: "TEMP"
        badge: root.peak > 0 ? "Pk " + Math.round(root.peak) + "°" : ""
        value: Model.temp(root.device ? root.device.temp : null)
        valueColor: root.tierColor(root.tempSeverity, root.ink)
        detail: !root.device || root.device.temp === null || root.device.temp === undefined
          ? "Not reported"
          : (root.device.temp_shared ? "Shared CPU die" : "GPU sensor")
        showBar: root.device && root.device.temp !== null && root.device.temp !== undefined
        barFraction: showBar ? Math.max(0, Math.min(1, Number(root.device.temp) / 100)) : 0
        barColor: root.tierColor(root.tempSeverity, root.alpha(root.ink, 0.55))
      }

      MetricTile {
        width: metricGrid.tileWidth
        label: "POWER"
        value: Model.watts(root.device ? root.device.power_w : null)
        valueColor: root.ink
        detail: !root.device || root.device.power_w === null || root.device.power_w === undefined
          ? "Not reported"
          : "Current draw"
        showBar: false
      }

      MetricTile {
        width: metricGrid.tileWidth
        label: root.integrated ? "MEMORY" : "VRAM"
        badge: root.hasVram ? Model.percent(root.vramRatio * 100) : ""
        value: root.device && root.device.mem_used !== null && root.device.mem_used !== undefined
          ? Model.bytes(root.device.mem_used)
          : (root.integrated ? "Shared" : "—")
        valueColor: root.tierColor(root.vramSeverity, root.ink)
        detail: root.device && root.device.mem_total > 0
          ? "of " + Model.bytes(root.device.mem_total)
          : (root.integrated ? "System memory" : "Not reported")
        showBar: root.hasVram
        barFraction: root.vramRatio
        barColor: root.tierColor(root.vramSeverity, root.chartColor)
      }

      MetricTile {
        width: metricGrid.tileWidth
        label: "CLOCK"
        value: Model.mhz(root.device ? root.device.freq_mhz : null)
        valueColor: root.ink
        detail: root.device && root.device.max_freq_mhz > 0
          ? "Max " + Model.mhz(root.device.max_freq_mhz)
          : (root.device && root.device.freq_mhz !== null && root.device.freq_mhz !== undefined ? "Core clock" : "Not reported")
        showBar: root.hasClockRange
        barFraction: root.clockRatio
        barColor: root.alpha(root.ink, 0.55)
      }
    }
  }

  component MetricTile: Rectangle {
    id: tile
    property string label: ""
    property string badge: ""
    property string value: "—"
    property color valueColor: root.ink
    property string detail: ""
    property bool showBar: false
    property real barFraction: 0
    property color barColor: root.chartColor

    radius: Math.max(8, Style.cornerRadius)
    color: root.alpha(root.ink, 0.036)
    border.width: 1
    border.color: root.alpha(root.ink, 0.09)
    implicitHeight: tileColumn.implicitHeight + Style.space(18)

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Math.max(5, Math.round(parent.radius * 0.7))
      anchors.rightMargin: Math.max(5, Math.round(parent.radius * 0.7))
      anchors.topMargin: 1
      height: 1
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.16; color: Qt.rgba(root.specularTop.r, root.specularTop.g, root.specularTop.b, root.specularTop.a * 0.75) }
        GradientStop { position: 0.84; color: Qt.rgba(root.specularTop.r, root.specularTop.g, root.specularTop.b, root.specularTop.a * 0.75) }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }

    Column {
      id: tileColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(9)
      spacing: Style.space(4)

      Item {
        width: parent.width
        implicitHeight: Math.max(tileLabel.implicitHeight, tileBadge.implicitHeight)

        Text {
          id: tileLabel
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.right: tileBadge.visible ? tileBadge.left : parent.right
          anchors.rightMargin: tileBadge.visible ? Style.space(4) : 0
          anchors.verticalCenter: parent.verticalCenter
          text: tile.label
          color: root.alpha(root.ink, 0.50)
          font.family: root.uiFont
          font.pixelSize: Math.max(9, root.captionSize - 1)
          font.weight: Font.DemiBold
          font.letterSpacing: 0.9
          elide: Text.ElideRight
        }

        Text {
          id: tileBadge
          textFormat: Text.PlainText
          visible: tile.badge !== ""
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: tile.badge
          color: root.alpha(root.ink, 0.56)
          font.family: root.monoFont
          font.pixelSize: Math.max(9, root.captionSize - 1)
          font.features: { "tnum": 1 }
        }
      }

      Text {
        readonly property bool isNumeric: /\d/.test(tile.value)
        textFormat: Text.PlainText
        width: parent.width
        text: tile.value
        color: tile.valueColor
        font.family: isNumeric ? root.monoFont : root.uiFont
        font.pixelSize: text.length > 9 ? Math.max(13, root.bodySize + 1) : Math.max(15, root.bodySize + 3)
        font.weight: isNumeric ? Font.Bold : Font.DemiBold
        font.letterSpacing: isNumeric ? 0 : -0.2
        font.features: { "tnum": 1 }
        elide: Text.ElideRight
      }

      // Consistent vertical rhythm: subtle 3px pill meter when a numeric scale exists.
      Rectangle {
        width: parent.width
        height: Style.space(3)
        radius: height / 2
        color: tile.showBar ? root.alpha(root.ink, 0.09) : "transparent"

        Rectangle {
          visible: tile.showBar && tile.barFraction > 0
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          height: parent.height
          width: Math.max(height, parent.width * Math.max(0, Math.min(1, tile.barFraction)))
          radius: parent.radius
          color: tile.barColor
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: tile.detail
        color: root.alpha(root.ink, 0.54)
        font.family: root.uiFont
        font.pixelSize: Math.max(9, root.captionSize - 1)
        font.features: { "tnum": 1 }
        elide: Text.ElideRight
      }
    }
  }
}
