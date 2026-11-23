.pragma library

function cleanText(value) {
  return String(value === undefined || value === null ? "" : value).trim()
}

function emptyState() {
  return {
    known: false,
    count: 0,
    total: 0,
    dir: "",
    dirName: "Pictures",
    screenshots: [],
    tooltip: "Manage screenshots"
  }
}

function normalizeScreenshot(value) {
  var source = value || {}
  return {
    path: cleanText(source.path),
    previewPath: cleanText(source.previewPath),
    name: cleanText(source.name),
    size: Number(source.size || 0),
    humanSize: cleanText(source.humanSize) || "",
    width: Number(source.width || 0),
    height: Number(source.height || 0),
    mtimeIso: cleanText(source.mtimeIso)
  }
}

function parseState(raw) {
  try {
    var parsed = JSON.parse(String(raw || "{}"))
    var source = Array.isArray(parsed.screenshots) ? parsed.screenshots : []
    var screenshots = []

    for (var i = 0; i < source.length; i++) {
      var screenshot = normalizeScreenshot(source[i])
      if (screenshot.path) screenshots.push(screenshot)
    }

    var dir = cleanText(parsed.dir)
    var dirName = cleanText(parsed.dirName) || "Pictures"
    var count = screenshots.length
    var total = Number(parsed.total || count)
    return {
      known: true,
      count: count,
      total: total,
      dir: dir,
      dirName: dirName,
      screenshots: screenshots,
      tooltip: count === 0
        ? "No screenshots yet"
        : count === 1 ? "1 screenshot" : count + " screenshots"
    }
  } catch (error) {
    return emptyState()
  }
}

function defaultIcon() {
  return "󰄀"
}

function barLabel(count, vertical, known, icon, showCount) {
  var glyph = cleanText(icon) || defaultIcon()
  if (!known || Number(count || 0) === 0) return glyph
  if (showCount === false) return glyph
  return vertical ? glyph + "\n" + count : glyph + " " + count
}

function screenshotKey(screenshot) {
  return cleanText((screenshot || {}).path)
}

function humanDate(iso) {
  var value = cleanText(iso)
  if (!value) return ""
  return value.replace("T", " ").slice(0, 16)
}

function friendlyDate(iso) {
  var value = cleanText(iso)
  if (!value) return ""
  var match = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})/.exec(value)
  if (!match) return humanDate(value)
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  var monthIndex = parseInt(match[2], 10) - 1
  var day = parseInt(match[3], 10)
  if (monthIndex < 0 || monthIndex > 11 || isNaN(day)) return humanDate(value)
  return months[monthIndex] + " " + day + ", " + match[4] + ":" + match[5]
}

function dimensionsText(screenshot) {
  var value = screenshot || {}
  var w = Number(value.width || 0)
  var h = Number(value.height || 0)
  return (w > 0 && h > 0) ? (w + "×" + h) : ""
}

function numericMeta(screenshot) {
  var value = screenshot || {}
  var parts = []
  var dims = dimensionsText(value)
  var size = cleanText(value.humanSize)
  if (dims) parts.push(dims)
  if (size) parts.push(size)
  return parts.join(" · ")
}

function screenshotMeta(screenshot) {
  var value = screenshot || {}
  var parts = []
  var date = humanDate(value.mtimeIso)
  if (date) parts.push(date)
  if (cleanText(value.humanSize)) parts.push(cleanText(value.humanSize))
  if (parts.length === 0) parts.push(cleanText(value.name))
  return parts.join("  ·  ")
}

function matchesQuery(screenshot, query) {
  var needle = cleanText(query).toLowerCase()
  if (!needle) return true
  var value = screenshot || {}
  var haystack = (cleanText(value.name) + " " + humanDate(value.mtimeIso)).toLowerCase()
  return haystack.indexOf(needle) !== -1
}

function filterScreenshots(screenshots, query) {
  var needle = cleanText(query).toLowerCase()
  var result = []
  for (var i = 0; i < screenshots.length; i++) {
    if (matchesQuery(screenshots[i], needle)) result.push(screenshots[i])
  }
  return result
}

function actionError(exitCode, stderrText, action) {
  var detail = cleanText(stderrText).split("\n")[0]
  if (Number(exitCode) === 126) return "Authentication was cancelled"
  if (Number(exitCode) === 127) return "A required command is unavailable"
  if (detail) return detail
  return "Could not " + action + " screenshots"
}
