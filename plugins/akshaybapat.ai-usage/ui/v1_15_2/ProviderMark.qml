import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// One vendor identity across the bar, popup, navigation and spend rows.
// Published brand colors and existing artwork come from Model.js; brands
// without a color use the caller's foreground. Color artwork keeps the same
// identity on both light and dark surfaces. Status is shown beside the mark.
Item {
  id: root
  objectName: "providerMark"
  property string role: ""

  // Asset base name under assets/, or "" for the typographic fallback.
  property string mark: ""
  // Two letters shown when there is no mark.
  property string initials: "··"
  property color color: Commons.Color.foreground
  property color surfaceColor: Commons.Color.background
  // Drawn as the plain silhouette in `color`, with no brand ink. The bar
  // sets it for a provider with no reading (Model.stripCell plainMark), so a
  // mark only wears its vendor's colour while it has a live number beside it.
  property bool plain: false
  // Identity belongs to the mark, so every caller gets the same vendor ink.
  // Status remains on values, meters and messages rather than recoloring logos;
  // the one exception is `plain`, which takes colour away and adds none.
  readonly property color brandInk: plain ? color : (Model.brandColor(mark) || color)
  // A plain mark trades a picture for its silhouette only where the silhouette
  // is the same identity (Model.silhouetteFile); otherwise the picture stays.
  readonly property bool usingColorArt: Model.hasColorArt(mark)
    && !(plain && Model.silhouetteFile(mark) !== "")
  property string fontFamily: Style.font.family
  property int fontSize: Style.font.caption

  readonly property bool usingMark: usingColorArt
    ? colorImage.status === Image.Ready : image.status === Image.Ready

  // Some vendors' current marks are pictures, not silhouettes — Antigravity's
  // blue-to-orange arch, Codex's blue-violet gradient cloud, Cursor's
  // multicolour cube, OpenRouter's lime glyph, Kimi's K with its blue dot. Those
  // ship as assets/<mark>-color.png (keyed out of the vendors' current artwork,
  // 2026-09-06: tile and checkerboard backgrounds removed, never a solid plate)
  // and are drawn as-is instead of through the ink mask. Which marks have one is
  // the COLOR_ART list in Model.js, so nothing is probed for on disk. They are
  // never exchange these for a different vendor's monochrome logo on a light
  // surface: the Antigravity arch and Gemini star are different identities.
  readonly property bool darkSurface: (0.2126 * surfaceColor.r + 0.7152 * surfaceColor.g
    + 0.0722 * surfaceColor.b) < 0.5
  readonly property bool usingColor: colorImage.status === Image.Ready
  readonly property bool kimiLightMode: !darkSurface && mark === "kimi" && usingColor
  readonly property string artwork: usingColor ? String(colorImage.source) : String(image.source)

  // Square by default; a wordmark (Model.MARK_ASPECT) asks for its own width.
  implicitWidth: Math.round(Style.bar.iconCanvas * Model.markAspect(mark))
  implicitHeight: Style.bar.iconCanvas

  Image {
    id: image
    anchors.fill: parent
    visible: false
    layer.enabled: true
    fillMode: Image.PreserveAspectFit
    // Decode well above the painted size: these are 16px marks on a HiDPI
    // screen, and a 1:1 decode is visibly soft.
    sourceSize.width: Math.round(Math.max(16, root.width) * 3)
    sourceSize.height: Math.round(Math.max(16, root.height) * 3)
    source: root.usingColorArt || Model.silhouetteFile(root.mark) === ""
      ? "" : Qt.resolvedUrl("assets/" + Model.silhouetteFile(root.mark))
  }

  Image {
    id: colorImage
    anchors.fill: parent
    visible: root.usingColor
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
    // Kimi's artwork is a white K with a blue top-right dot. On light surfaces,
    // tint the K cleanly into the bar's dark ink so it reads as solid, crisp
    // typography inside a small dial rather than a hollow outlined ghost; the
    // un-tinted blue dot is painted back on top in its disjoint quadrant below.
    layer.enabled: root.kimiLightMode
    layer.effect: MultiEffect {
      colorization: 1.0
      colorizationColor: root.color
    }
    sourceSize.width: Math.round(Math.max(16, root.width) * 3)
    sourceSize.height: Math.round(Math.max(16, root.height) * 3)
    source: root.usingColorArt ? Qt.resolvedUrl("assets/" + Model.colorArtFile(root.mark)) : ""
  }

  // Preserves Kimi's official blue dot on light surfaces without hardcoding any
  // colour literal or clipping the dark-ink K (in kimi-color.png the K stays in
  // x<=0.75, y>=0.19 while the blue dot sits cleanly in x>=0.81, y<=0.19).
  Item {
    visible: root.kimiLightMode
    x: Math.floor(parent.width * 0.77)
    y: 0
    width: parent.width - x
    height: Math.ceil(parent.height * 0.25)
    clip: true

    Image {
      x: -parent.x
      y: -parent.y
      width: root.width
      height: root.height
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
      sourceSize.width: colorImage.sourceSize.width
      sourceSize.height: colorImage.sourceSize.height
      source: root.kimiLightMode ? colorImage.source : ""
    }
  }

  Rectangle {
    id: ink
    anchors.fill: parent
    visible: false
    layer.enabled: true
    color: root.brandInk
  }

  MultiEffect {
    anchors.fill: parent
    visible: root.usingMark && !root.usingColor
    source: ink
    maskEnabled: true
    maskSource: image
  }

  Item {
    anchors.fill: parent
    visible: !root.usingMark

    Rectangle {
      anchors.fill: parent
      radius: Math.min(5, Math.max(2, Style.cornerRadius))
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.55)
    }

    Text {
      anchors.centerIn: parent
      text: root.initials
      textFormat: Text.PlainText
      color: root.color
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      renderType: Text.NativeRendering
    }
  }
}
