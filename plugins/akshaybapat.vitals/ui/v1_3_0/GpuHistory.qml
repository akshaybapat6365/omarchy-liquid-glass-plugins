import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// Smooth antialiased GPU utilization chart framed in a recessed frosted-glass well.
Item {
  id: root

  property var values: []
  property var sampleTimes: []
  property real domainStart: 0
  property real domainEnd: 0
  property color ink: Commons.Color.foreground
  property color lineColor: Commons.Color.accent
  property color mutedInk: Qt.rgba(ink.r, ink.g, ink.b, 0.56)
  property string fontFamily: Style.font.family
  property string monoFont: fontFamily
  property string uiFont: (Style.font.menuFamily && Style.font.menuFamily.length > 0 && Style.font.menuFamily !== "monospace")
    ? Style.font.menuFamily
    : "Inter Display"
  property int captionSize: Math.max(10, Style.font.caption)
  property string emptyText: "Collecting history…"

  readonly property bool hasCurve: (values || []).length >= 2
  readonly property real peakValue: hasCurve ? Model.maxOf(values, 0) : -1

  implicitHeight: Style.space(138)
  Accessible.name: "Graphics activity history"

  Rectangle {
    id: well
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: parent.height - axisRow.implicitHeight - Style.space(6)
    radius: Math.max(8, Style.cornerRadius)
    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.032)
    border.width: 1
    border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10)

    // Quiet chart meta header — sits above the plot so high-load curves never collide with labels.
    Item {
      id: chartHeader
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      anchors.topMargin: Style.space(7)
      implicitHeight: headerLeft.implicitHeight

      Text {
        id: headerLeft
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "HISTORY"
        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.48)
        font.family: root.uiFont
        font.pixelSize: Math.max(9, root.captionSize - 1)
        font.weight: Font.DemiBold
        font.letterSpacing: 1.0
      }

      Text {
        textFormat: Text.PlainText
        visible: root.hasCurve
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Peak " + Model.percent(root.peakValue)
        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.62)
        font.family: root.monoFont
        font.pixelSize: Math.max(9, root.captionSize - 1)
        font.weight: Font.Medium
        font.features: { "tnum": 1 }
      }
    }

    // Y-axis ticks cleanly aligned to 100%, 50%, 0% guide lines.
    Repeater {
      model: [100, 50, 0]
      delegate: Text {
        required property int modelData
        textFormat: Text.PlainText
        x: Style.space(8)
        y: plot.y + plot.padTop + (1 - modelData / 100) * plot.innerH - height / 2
        width: Style.space(26)
        text: modelData + "%"
        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.42)
        font.family: root.monoFont
        font.pixelSize: Math.max(9, root.captionSize - 1)
        font.features: { "tnum": 1 }
        horizontalAlignment: Text.AlignRight
      }
    }

    Canvas {
      id: plot
      readonly property real padTop: 6
      readonly property real padBottom: 6
      readonly property real innerH: Math.max(1, height - padTop - padBottom)

      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: chartHeader.bottom
      anchors.bottom: parent.bottom
      anchors.leftMargin: Style.space(38)
      anchors.rightMargin: Style.space(10)
      anchors.topMargin: Style.space(4)
      anchors.bottomMargin: Style.space(7)
      antialiasing: true

      Connections {
        target: root
        function onValuesChanged() { plot.requestPaint() }
        function onSampleTimesChanged() { plot.requestPaint() }
        function onDomainStartChanged() { plot.requestPaint() }
        function onDomainEndChanged() { plot.requestPaint() }
        function onLineColorChanged() { plot.requestPaint() }
        function onInkChanged() { plot.requestPaint() }
      }
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()

      onPaint: {
        var ctx = getContext("2d")
        var w = width
        var h = height
        if (w <= 2 || h <= 2) return
        ctx.reset()

        var padT = plot.padTop
        var padB = plot.padBottom
        var inner = Math.max(1, h - padT - padB)
        var baseY = padT + inner

        // Subtle dashed horizontal guide lines at 100%, 50%, and 0%.
        ctx.save()
        ctx.strokeStyle = Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.13)
        ctx.lineWidth = 1
        if (ctx.setLineDash) ctx.setLineDash([2, 3])
        for (let row = 0; row < 3; row++) {
          const gy = Math.round(padT + row * inner / 2) + 0.5
          ctx.beginPath()
          ctx.moveTo(0, gy)
          ctx.lineTo(w, gy)
          ctx.stroke()
        }
        ctx.restore()

        const points = root.values || []
        const times = root.sampleTimes || []
        const n = points.length
        if (n < 2) return

        const start = root.domainStart > 0 ? root.domainStart : times[0]
        const end = root.domainEnd > 0 ? root.domainEnd : times[n - 1]
        const elapsed = times.length === n ? end - start : 0
        const usableW = Math.max(1, w - 4)

        const xs = []
        const ys = []
        for (let i = 0; i < n; i++) {
          const xv = elapsed > 0
            ? Model.timeFraction(times[i], start, end) * usableW
            : (i * usableW / (n - 1))
          const clamped = Math.max(0, Math.min(100, Number(points[i]) || 0))
          const yv = padT + (1 - clamped / 100) * inner
          xs.push(xv)
          ys.push(yv)
        }

        function traceSmoothPath() {
          ctx.moveTo(xs[0], ys[0])
          if (n === 2) {
            ctx.lineTo(xs[1], ys[1])
            return
          }
          for (let j = 1; j < n - 1; j++) {
            const midX = (xs[j] + xs[j + 1]) * 0.5
            const midY = (ys[j] + ys[j + 1]) * 0.5
            ctx.quadraticCurveTo(xs[j], ys[j], midX, midY)
          }
          ctx.lineTo(xs[n - 1], ys[n - 1])
        }

        // Soft vertical gradient fill under the curve.
        var c = root.lineColor
        var fill = ctx.createLinearGradient(0, padT, 0, baseY)
        fill.addColorStop(0.0, Qt.rgba(c.r, c.g, c.b, 0.28))
        fill.addColorStop(0.65, Qt.rgba(c.r, c.g, c.b, 0.08))
        fill.addColorStop(1.0, Qt.rgba(c.r, c.g, c.b, 0.005))

        ctx.beginPath()
        traceSmoothPath()
        ctx.lineTo(xs[n - 1], baseY)
        ctx.lineTo(xs[0], baseY)
        ctx.closePath()
        ctx.fillStyle = fill
        ctx.fill()

        // Smooth antialiased signal line.
        ctx.beginPath()
        traceSmoothPath()
        ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.96)
        ctx.lineWidth = 2.0
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.stroke()

        // Glowing live endpoint indicator.
        const ex = Math.max(3, Math.min(w - 3, xs[n - 1]))
        const ey = ys[n - 1]
        ctx.beginPath()
        ctx.arc(ex, ey, 6.0, 0, Math.PI * 2)
        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.22)
        ctx.fill()

        ctx.beginPath()
        ctx.arc(ex, ey, 3.0, 0, Math.PI * 2)
        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 1.0)
        ctx.fill()

        ctx.beginPath()
        ctx.arc(ex, ey, 1.2, 0, Math.PI * 2)
        ctx.fillStyle = Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.92)
        ctx.fill()
      }
    }

    Text {
      textFormat: Text.PlainText
      anchors.centerIn: plot
      visible: !root.hasCurve
      text: root.emptyText
      color: root.mutedInk
      font.family: root.uiFont
      font.pixelSize: root.captionSize
    }
  }

  Item {
    id: axisRow
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    implicitHeight: Math.max(startTime.implicitHeight, endTime.implicitHeight)

    Text {
      id: startTime
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(2)
      text: root.domainStart > 0 ? Model.chartClock(root.domainStart) : ""
      color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.48)
      font.family: root.monoFont
      font.pixelSize: Math.max(9, root.captionSize - 1)
      font.features: { "tnum": 1 }
    }

    Text {
      id: endTime
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.rightMargin: Style.space(2)
      text: root.domainEnd > 0 ? Model.chartClock(root.domainEnd) : ""
      color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.48)
      font.family: root.monoFont
      font.pixelSize: Math.max(9, root.captionSize - 1)
      font.features: { "tnum": 1 }
    }
  }
}
