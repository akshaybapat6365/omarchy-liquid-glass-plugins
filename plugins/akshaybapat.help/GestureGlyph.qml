import QtQuick

// Bespoke geometric Apple-HIG gesture icon badge rendered cleanly with
// crisp antialiased vector primitives inside a smoked glass trackpad tile.
Item {
  id: badge

  property string gestureType: "swipe-up"
  property int fingers: 3
  property color accentColor: "#7176b8"
  property bool active: false

  implicitWidth: 68
  implicitHeight: 58

  // Recessed miniature glass trackpad frame.
  Rectangle {
    anchors.fill: parent
    radius: 13
    gradient: Gradient {
      GradientStop {
        position: 0.0
        color: badge.active
          ? Qt.rgba(badge.accentColor.r, badge.accentColor.g, badge.accentColor.b, 0.24)
          : Qt.rgba(1, 1, 1, 0.068)
      }
      GradientStop {
        position: 1.0
        color: badge.active
          ? Qt.rgba(badge.accentColor.r, badge.accentColor.g, badge.accentColor.b, 0.10)
          : Qt.rgba(1, 1, 1, 0.022)
      }
    }
    border.width: 1
    border.color: badge.active
      ? Qt.rgba(badge.accentColor.r, badge.accentColor.g, badge.accentColor.b, 0.55)
      : Qt.rgba(1, 1, 1, 0.12)

    // Subtle top bevel catchlight.
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      anchors.topMargin: 1
      height: 1
      color: Qt.rgba(1, 1, 1, 0.20)
    }
  }

  // Vector gesture artwork for all trackpad, drag, and Quick Look gestures.
  Canvas {
    id: glyphCanvas
    anchors.fill: parent
    visible: badge.gestureType !== "mouse-clicks"
    antialiasing: true
    renderStrategy: Canvas.Cooperative

    onVisibleChanged: if (visible) requestPaint()
    Component.onCompleted: if (visible) requestPaint()

    function drawArrowHead(ctx, x, y, angleRad, size) {
      ctx.save()
      ctx.translate(x, y)
      ctx.rotate(angleRad)
      ctx.beginPath()
      ctx.moveTo(-size, -size * 0.72)
      ctx.lineTo(0, 0)
      ctx.lineTo(-size, size * 0.72)
      ctx.stroke()
      ctx.restore()
    }

    function drawFingerDot(ctx, x, y, r, accentStr) {
      // Soft outer touch contact halo
      ctx.beginPath()
      ctx.arc(x, y, r + 2.8, 0, Math.PI * 2)
      ctx.fillStyle = accentStr
      ctx.fill()

      // Crisp inner fingertip core
      ctx.beginPath()
      ctx.arc(x, y, r, 0, Math.PI * 2)
      ctx.fillStyle = "#F0F6FF"
      ctx.fill()
    }

    onPaint: {
      var ctx = getContext("2d")
      var w = width
      var h = height
      ctx.clearRect(0, 0, w, h)
      ctx.lineCap = "round"
      ctx.lineJoin = "round"

      var ar = Math.min(255, Math.round(badge.accentColor.r * 255 * 1.25 + 48))
      var ag = Math.min(255, Math.round(badge.accentColor.g * 255 * 1.25 + 56))
      var ab = Math.min(255, Math.round(badge.accentColor.b * 255 * 1.25 + 56))
      var halo = "rgba(" + ar + "," + ag + "," + ab + ",0.34)"
      var strokeBright = "rgba(" + ar + "," + ag + "," + ab + ",0.95)"
      var strokeSoft = "rgba(220,234,255,0.42)"

      var t = badge.gestureType
      var n = Math.max(1, badge.fingers)

      if (t === "swipe-up" || t === "swipe-down") {
        var up = (t === "swipe-up")
        var yDot = up ? 39 : 19
        var yTip = up ? 14 : 44
        var spacing = 12.5
        var startX = w / 2 - ((n - 1) * spacing) / 2

        for (var i = 0; i < n; i++) {
          var fx = startX + i * spacing
          // Motion trail stem
          ctx.beginPath()
          ctx.moveTo(fx, up ? yDot - 5 : yDot + 5)
          ctx.lineTo(fx, up ? yTip + 4 : yTip - 4)
          ctx.strokeStyle = i === Math.floor(n / 2) ? strokeBright : strokeSoft
          ctx.lineWidth = i === Math.floor(n / 2) ? 1.8 : 1.35
          ctx.stroke()
          drawFingerDot(ctx, fx, yDot, 3.3, halo)
        }
        // Crisp directional chevron on central motion axis
        ctx.strokeStyle = strokeBright
        ctx.lineWidth = 2.0
        drawArrowHead(ctx, w / 2, yTip, up ? -Math.PI / 2 : Math.PI / 2, 5.2)

      } else if (t === "swipe-lr") {
        var lrSpacing = n >= 4 ? 9.5 : (n === 3 ? 11.5 : 14)
        var lrStartX = w / 2 - ((n - 1) * lrSpacing) / 2
        var cy = 34

        // Opposing horizontal glide arrow bar above fingers
        ctx.beginPath()
        ctx.moveTo(15, 16)
        ctx.lineTo(w - 15, 16)
        ctx.strokeStyle = strokeSoft
        ctx.lineWidth = 1.5
        ctx.stroke()

        ctx.strokeStyle = strokeBright
        ctx.lineWidth = 1.9
        drawArrowHead(ctx, 14, 16, Math.PI, 4.6)
        drawArrowHead(ctx, w - 14, 16, 0, 4.6)

        for (var j = 0; j < n; j++) {
          var rx = lrStartX + j * lrSpacing
          drawFingerDot(ctx, rx, cy, n >= 4 ? 2.75 : 3.25, halo)
        }

      } else if (t === "pinch-out") {
        var cx = w / 2
        var py = h / 2 + 1
        var angles = n >= 4
          ? [-2.35, -0.78, 0.78, 2.35]
          : [-Math.PI / 2, 0.55, Math.PI - 0.55]

        // Quiet center anchor point
        ctx.beginPath()
        ctx.arc(cx, py, 2.0, 0, Math.PI * 2)
        ctx.fillStyle = "rgba(220,234,255,0.35)"
        ctx.fill()

        for (var k = 0; k < angles.length; k++) {
          var ang = angles[k]
          var rDot = n >= 4 ? 9.5 : 9.0
          var rTip = n >= 4 ? 21.5 : 21.0
          var dx = cx + Math.cos(ang) * rDot
          var dy = py + Math.sin(ang) * rDot
          var tx = cx + Math.cos(ang) * rTip
          var ty = py + Math.sin(ang) * rTip

          ctx.beginPath()
          ctx.moveTo(dx, dy)
          ctx.lineTo(tx, ty)
          ctx.strokeStyle = strokeBright
          ctx.lineWidth = 1.6
          ctx.stroke()

          drawArrowHead(ctx, tx, ty, ang, 4.1)
          drawFingerDot(ctx, dx, dy, n >= 4 ? 2.6 : 2.9, halo)
        }

      } else if (t === "drag") {
        // Two miniature desktop cards with a curved drag arc between them
        ctx.strokeStyle = "rgba(220,234,255,0.32)"
        ctx.fillStyle = "rgba(255,255,255,0.06)"
        ctx.lineWidth = 1.2

        // Left desk
        ctx.beginPath()
        ctx.roundedRect(9, 25, 20, 18, 4, 4)
        ctx.fill()
        ctx.stroke()

        // Right desk (highlighted destination)
        ctx.strokeStyle = strokeBright
        ctx.fillStyle = "rgba(" + ar + "," + ag + "," + ab + ",0.16)"
        ctx.beginPath()
        ctx.roundedRect(39, 25, 20, 18, 4, 4)
        ctx.fill()
        ctx.stroke()

        // Lifted window chip inside left desk
        ctx.fillStyle = "rgba(240,246,255,0.82)"
        ctx.beginPath()
        ctx.roundedRect(13, 30, 9, 7, 2, 2)
        ctx.fill()

        // Smooth curved drag trajectory arc overhead
        ctx.beginPath()
        ctx.moveTo(19, 23)
        ctx.quadraticCurveTo(w / 2, 7, 48, 22)
        ctx.strokeStyle = strokeBright
        ctx.lineWidth = 1.75
        ctx.stroke()
        drawArrowHead(ctx, 49, 22.5, 0.55, 4.3)

      } else if (t === "spacebar") {
        // Quick Look eye-lens emblem floating above a crisp Spacebar keycap
        var ey = 21
        ctx.beginPath()
        ctx.moveTo(19, ey)
        ctx.quadraticCurveTo(w / 2, ey - 10, w - 19, ey)
        ctx.quadraticCurveTo(w / 2, ey + 10, 19, ey)
        ctx.strokeStyle = strokeBright
        ctx.lineWidth = 1.7
        ctx.stroke()

        // Iris pupil
        ctx.beginPath()
        ctx.arc(w / 2, ey, 3.6, 0, Math.PI * 2)
        ctx.fillStyle = "#F0F6FF"
        ctx.fill()

        // Miniature elongated Spacebar keycap
        ctx.fillStyle = "rgba(255,255,255,0.12)"
        ctx.strokeStyle = "rgba(255,255,255,0.34)"
        ctx.lineWidth = 1.2
        ctx.beginPath()
        ctx.roundedRect(12, 36, w - 24, 11, 3.5, 3.5)
        ctx.fill()
        ctx.stroke()

        // Center notch indicator on spacebar
        ctx.beginPath()
        ctx.moveTo(w / 2 - 7, 41.5)
        ctx.lineTo(w / 2 + 7, 41.5)
        ctx.strokeStyle = "rgba(240,246,255,0.65)"
        ctx.lineWidth = 1.3
        ctx.stroke()
      }
    }
  }

  // Bespoke Omarchy Logo + L/M/R click pills diagram for Top-Left Logo card.
  Column {
    anchors.centerIn: parent
    spacing: 5
    visible: badge.gestureType === "mouse-clicks"

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: "\ue900"
      font.family: "omarchy"
      font.pixelSize: 20
      color: Qt.lighter(badge.accentColor, 1.45)
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 3

      Repeater {
        model: ["L", "M", "R"]
        delegate: Rectangle {
          required property string modelData
          width: 15
          height: 14
          radius: 4
          color: Qt.rgba(1, 1, 1, 0.11)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.22)
          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: parent.modelData
            font.family: "JetBrainsMono Nerd Font"
            font.weight: Font.DemiBold
            font.pixelSize: 9
            color: "#E8F0FC"
          }
        }
      }
    }
  }

  onGestureTypeChanged: if (glyphCanvas.visible) glyphCanvas.requestPaint()
  onFingersChanged: if (glyphCanvas.visible) glyphCanvas.requestPaint()
  onAccentColorChanged: if (glyphCanvas.visible) glyphCanvas.requestPaint()
  onActiveChanged: if (glyphCanvas.visible) glyphCanvas.requestPaint()
}
