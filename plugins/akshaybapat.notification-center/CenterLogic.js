function text(value) {
  return String(value === undefined || value === null ? "" : value)
}

function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : (fallback === undefined ? 0 : fallback)
}

function arrayLike(value) {
  if (!value || typeof value === "string" || typeof value.length !== "number") return []
  var result = []
  for (var i = 0; i < value.length; i++) result.push(value[i])
  return result
}

function dictionary() {
  return Object.create(null)
}

function cleanInline(value) {
  return cleanBody(value, "", "").replace(/\s+/g, " ").trim()
}

function stableKey(row) {
  var value = row || {}
  var timestamp = Math.max(0, Math.round(finiteNumber(value.timestamp, 0)))
  var id = value.originalId
  if (id === undefined || id === null) id = value.id
  if (id === undefined || id === null) id = 0
  return String(timestamp) + ":" + text(id)
}

function cleanBody(body, app, appIcon) {
  var value = text(body)
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<img[^>]*>/gi, "")
    .replace(/<a\b[^>]*>(.*?)<\/a>/gi, "$1")
    .replace(/<[^>]*>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/[\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "")

  var sender = (text(app) + "\n" + text(appIcon)).toLowerCase()
  var chromium = sender.indexOf("chrom") >= 0 || sender.indexOf("brave") >= 0
    || sender.indexOf("vivaldi") >= 0 || sender.indexOf("microsoft-edge") >= 0
    || sender.indexOf("opera") >= 0
  if (chromium) {
    value = value
      .replace(/^\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/\S*)?\s+/i, "")
  }

  var lines = value.split(/\r?\n/)
  var kept = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/\s+/g, " ").trim()
    if (line) kept.push(line)
  }
  return kept.join("\n")
}

function normalizeRow(value, source, sourceIndex) {
  var row = value || {}
  var app = cleanInline(row.appName || row.app || "Unknown application")
  if (!app) app = "Unknown application"
  var timestamp = Math.max(0, Math.round(finiteNumber(row.timestamp, 0)))
  var originalId = row.originalId
  if (originalId === undefined || originalId === null) originalId = row.id
  if (originalId === undefined || originalId === null) originalId = 0

  var normalized = {
    key: "",
    source: source === "live" ? "live" : "history",
    live: source === "live",
    sourceIndex: source === "live" ? finiteNumber(sourceIndex, -1) : -1,
    id: row.id === undefined || row.id === null ? originalId : row.id,
    originalId: originalId,
    app: app,
    appIcon: text(row.appIcon),
    summary: cleanInline(row.summary || "Notification") || "Notification",
    body: cleanBody(row.body, app, row.appIcon),
    image: text(row.image),
    glyph: text(row.glyph),
    urgency: Math.max(0, Math.min(2, Math.round(finiteNumber(row.urgency, 1)))),
    timestamp: timestamp,
    actionable: false,
    historyBacked: source !== "live",
    unread: false,
    visualUnread: false,
    previewSource: "",
    // The daemon's own key for the card, which its IPC acts on, and whether
    // he closed it himself (a card he dismissed or clicked has been seen).
    serviceKey: text(row.serviceKey),
    handled: row.handled === true
  }
  normalized.key = stableKey(normalized)
  return normalized
}

// Omarchy 4.5's daemon keeps its state in ~/.local/state/omarchy/notifications/:
// live.json (the cards on screen, oldest first) and history.json (closed
// cards, newest first), each a JSON array of rows whose ts is in seconds. It
// stores a card that carried a code only as this placeholder, sender and all
// blanked, and shows it translated; here such cards share one group.
var REDACTED_SUMMARY = "Verification notification"
var REDACTED_BODY = "[redacted]"
var HANDLED_REASONS = { dismissed: true, activated: true }

function serviceRow(entry, source, index, labels) {
  var names = labels || {}
  var redacted = entry.summary === REDACTED_SUMMARY && entry.body === REDACTED_BODY
  return normalizeRow({
    app: redacted ? "Verification codes" : entry.app,
    appIcon: entry.appIcon,
    glyph: entry.glyph,
    summary: redacted ? text(names.redactedSummary || entry.summary) : entry.summary,
    body: redacted ? text(names.redactedBody || "Code hidden") : entry.body,
    urgency: entry.urgency,
    originalId: entry.originalId,
    timestamp: Math.round(finiteNumber(entry.ts, 0) * 1000),
    serviceKey: entry.key,
    handled: source !== "live" && HANDLED_REASONS[text(entry.closed_reason)] === true
  }, source, index)
}

// One of those files. Empty is no rows; anything that is not a JSON array yet
// (a write caught halfway, say) is null, so the caller keeps what it last read
// rather than blanking the bell.
function parseServiceRows(raw, source, labels) {
  var value = text(raw)
  if (!value.trim()) return []
  var parsed
  try {
    parsed = JSON.parse(value)
  } catch (error) {
    return null
  }
  if (!Array.isArray(parsed)) return null
  var rows = []
  for (var i = 0; i < parsed.length; i++) {
    var entry = parsed[i]
    if (!entry || typeof entry !== "object" || typeof entry.key !== "string" || !entry.key) continue
    rows.push(serviceRow(entry, source, i, labels))
  }
  return rows
}

// quiet.json: whether Do Not Disturb is on; null when it says nothing usable.
function parseQuiet(raw) {
  var value = text(raw)
  if (!value.trim()) return null
  try {
    var parsed = JSON.parse(value)
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed.dnd === true : null
  } catch (error) {
    return null
  }
}

function recordMap(records) {
  var map = dictionary()
  var values = arrayLike(records)
  for (var i = 0; i < values.length; i++) {
    var record = values[i]
    if (!record || !record.key) continue
    map[text(record.key)] = true
  }
  return map
}

function buildRows(historyRows, liveRows, dismissedRecords, seenThrough,
                   visualUnreadKeys, panelOpen) {
  var byKey = dictionary()
  var historyKeys = dictionary()
  var dismissed = recordMap(dismissedRecords)
  var history = arrayLike(historyRows)
  var live = arrayLike(liveRows)
  var seen = Math.max(0, finiteNumber(seenThrough, 0))
  var visual = visualUnreadKeys || {}

  for (var h = 0; h < history.length; h++) {
    var historical = normalizeRow(history[h], "history", -1)
    historyKeys[historical.key] = true
    if (!dismissed[historical.key]) byKey[historical.key] = historical
  }
  for (var l = 0; l < live.length; l++) {
    var current = normalizeRow(live[l], "live", l)
    current.historyBacked = historyKeys[current.key] === true
    if (!dismissed[current.key]) byKey[current.key] = current
  }

  var rows = []
  var unreadCount = 0
  var urgentUnreadCount = 0
  var maxTimestamp = 0
  for (var key in byKey) {
    var row = byKey[key]
    row.unread = row.timestamp > seen && !row.handled
    row.visualUnread = panelOpen ? visual[key] === true : row.unread
    if (row.unread) {
      unreadCount += 1
      if (row.urgency === 2) urgentUnreadCount += 1
    }
    maxTimestamp = Math.max(maxTimestamp, row.timestamp)
    rows.push(row)
  }
  rows.sort(function(a, b) {
    if (a.timestamp !== b.timestamp) return b.timestamp - a.timestamp
    return a.key < b.key ? -1 : (a.key > b.key ? 1 : 0)
  })

  return {
    rows: rows,
    unreadCount: unreadCount,
    urgentUnreadCount: urgentUnreadCount,
    maxTimestamp: maxTimestamp
  }
}

function matches(row, query) {
  var needle = text(query).trim().toLowerCase()
  if (!needle) return true
  var haystack = [row.app, row.summary, row.body].join("\n").toLowerCase()
  return haystack.indexOf(needle) >= 0
}

function relativeTime(timestamp, now) {
  var value = Math.max(0, finiteNumber(timestamp, 0))
  var current = Math.max(value, finiteNumber(now, Date.now()))
  if (!value) return ""
  var seconds = Math.max(0, Math.floor((current - value) / 1000))
  if (seconds < 60) return "now"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return String(minutes) + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return String(hours) + "h"
  var days = Math.floor(hours / 24)
  if (days < 7) return String(days) + "d"
  var date = new Date(value)
  return date.toLocaleDateString(undefined, { month: "short", day: "numeric" })
}

function groupRows(rows, query, now) {
  var groupsByKey = dictionary()
  var order = []
  var values = arrayLike(rows)
  var clock = finiteNumber(now, Date.now())

  for (var i = 0; i < values.length; i++) {
    var value = values[i]
    if (!value || !matches(value, query)) continue
    var row = {}
    for (var field in value) row[field] = value[field]
    row.timeLabel = relativeTime(row.timestamp, clock)

    var groupKey = text(row.app).trim().toLowerCase() || "unknown application"
    var group = groupsByKey[groupKey]
    if (!group) {
      group = {
        key: groupKey,
        app: row.app,
        appIcon: row.appIcon,
        iconSource: row.iconSource,
        glyph: row.glyph,
        latestTimestamp: row.timestamp,
        latestLabel: row.timeLabel,
        unreadCount: 0,
        urgent: false,
        rows: []
      }
      groupsByKey[groupKey] = group
      order.push(group)
    }
    if (!group.appIcon && row.appIcon) group.appIcon = row.appIcon
    if (!group.iconSource && row.iconSource) group.iconSource = row.iconSource
    if (!group.glyph && row.glyph) group.glyph = row.glyph
    group.latestTimestamp = Math.max(group.latestTimestamp, row.timestamp)
    if (row.visualUnread) group.unreadCount += 1
    if (row.urgency === 2) group.urgent = true
    group.rows.push(row)
  }

  order.sort(function(a, b) { return b.latestTimestamp - a.latestTimestamp })
  var flatIndex = 0
  for (var g = 0; g < order.length; g++) {
    var currentGroup = order[g]
    currentGroup.latestLabel = relativeTime(currentGroup.latestTimestamp, clock)
    currentGroup.count = currentGroup.rows.length
    currentGroup.startFlatIndex = flatIndex
    for (var r = 0; r < currentGroup.rows.length; r++) {
      currentGroup.rows[r].flatIndex = flatIndex
      currentGroup.rows[r].groupIndex = g
      flatIndex += 1
    }
  }
  return order
}

function flattenGroups(groups) {
  var flat = []
  var values = arrayLike(groups)
  for (var g = 0; g < values.length; g++) {
    var rows = arrayLike(values[g] && values[g].rows)
    for (var r = 0; r < rows.length; r++) flat.push(rows[r])
  }
  return flat
}

function parseState(raw) {
  var result = { version: 1, seenThrough: 0, dismissed: [] }
  var source = text(raw).trim()
  if (!source) return result
  try {
    var parsed = JSON.parse(source)
    result.seenThrough = Math.max(0, finiteNumber(parsed && parsed.seenThrough, 0))
    var records = arrayLike(parsed && parsed.dismissed)
    for (var i = 0; i < records.length; i++) {
      var record = records[i]
      if (!record || !record.key) continue
      result.dismissed.push({
        key: text(record.key),
        dismissedAt: Math.max(0, finiteNumber(record.dismissedAt, 0)),
        archiveSeen: record.archiveSeen === true
      })
    }
  } catch (error) {
    result.error = text(error)
  }
  return result
}

function addDismissed(records, key, now) {
  var result = []
  var values = arrayLike(records)
  var wanted = text(key)
  for (var i = 0; i < values.length; i++) {
    var record = values[i]
    if (!record || !record.key || text(record.key) === wanted) continue
    result.push(record)
  }
  if (wanted) {
    result.push({
      key: wanted,
      dismissedAt: Math.max(0, finiteNumber(now, Date.now())),
      archiveSeen: false
    })
  }
  return result.slice(Math.max(0, result.length - 128))
}

function pruneDismissed(records, liveKeys, historyKeys, now, graceMs) {
  var values = arrayLike(records)
  var live = liveKeys || {}
  var history = historyKeys || {}
  var current = finiteNumber(now, Date.now())
  var grace = Math.max(0, finiteNumber(graceMs, 600000))
  var result = []

  for (var i = 0; i < values.length; i++) {
    var record = values[i]
    if (!record || !record.key) continue
    var key = text(record.key)
    var inLive = live[key] === true
    var inHistory = history[key] === true
    var archiveSeen = record.archiveSeen === true || inHistory
    var age = current - Math.max(0, finiteNumber(record.dismissedAt, current))
    if (!inLive && !inHistory && (archiveSeen || age >= grace)) continue
    result.push({
      key: key,
      dismissedAt: Math.max(0, finiteNumber(record.dismissedAt, current)),
      archiveSeen: archiveSeen
    })
  }
  return result.slice(Math.max(0, result.length - 128))
}

function keyMap(rows) {
  var result = dictionary()
  var values = arrayLike(rows)
  for (var i = 0; i < values.length; i++) {
    if (values[i] && values[i].key) result[text(values[i].key)] = true
  }
  return result
}

function sameRecords(left, right) {
  return JSON.stringify(arrayLike(left)) === JSON.stringify(arrayLike(right))
}

if (typeof module !== "undefined") {
  module.exports = {
    stableKey: stableKey,
    cleanBody: cleanBody,
    normalizeRow: normalizeRow,
    serviceRow: serviceRow,
    parseServiceRows: parseServiceRows,
    parseQuiet: parseQuiet,
    buildRows: buildRows,
    groupRows: groupRows,
    flattenGroups: flattenGroups,
    relativeTime: relativeTime,
    parseState: parseState,
    addDismissed: addDismissed,
    pruneDismissed: pruneDismissed,
    keyMap: keyMap,
    sameRecords: sameRecords
  }
}
