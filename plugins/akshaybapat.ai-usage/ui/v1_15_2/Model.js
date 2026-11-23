// Pure data shaping for the Omarchy Quattro widget. Keep this file free of
// QML globals so the exact report contract and selection behavior can also be
// exercised by Node in CI.

function cleanText(value, maxLength) {
  var text = value === undefined || value === null ? "" : String(value)
  // The Rust projection already strips terminal controls. This second, cheap
  // boundary keeps hand-authored/older JSON from putting controls in a
  // long-lived shell process.
  text = text.replace(/[\t\r]/g, " ")
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]/g, "")
    .replace(/[\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "")
  var limit = Number(maxLength) || 2048
  if (text.length <= limit) return text
  var end = limit - 1
  var finalCodeUnit = text.charCodeAt(end - 1)
  if (finalCodeUnit >= 0xd800 && finalCodeUnit <= 0xdbff) end--
  return text.slice(0, end) + "…"
}

// Shared Omarchy components use Text.AutoText. Replace angle brackets before
// passing provider-controlled labels into those components so they can never
// be reclassified as rich text (including an image tag with a remote URL).
function autoTextSafe(value) {
  return cleanText(value, 1000)
    .replace(/[\n\u2028\u2029]/g, " ")
    .replace(/</g, "‹")
    .replace(/>/g, "›")
}

function finitePercent(value) {
  if (value === null || value === undefined || value === "" || typeof value === "boolean") return null
  var number = Number(value)
  if (!isFinite(number)) return null
  return Math.max(0, Math.min(100, Math.round(number)))
}

function normalizeSection(raw) {
  if (!raw || typeof raw !== "object") return null
  var type = String(raw.type || "")
  if (type === "spacer") return { type: "spacer" }
  if (type === "metric") {
    var percent = finitePercent(raw.percent)
    if (percent === null) return null
    var severity = String(raw.severity || "")
    if (["low", "mid", "high", "critical"].indexOf(severity) < 0)
      severity = percent >= 90 ? "critical" : percent >= 75 ? "high" : percent >= 50 ? "mid" : "low"
    return {
      type: "metric",
      label: cleanText(raw.label, 160),
      percent: percent,
      value: cleanText(raw.value, 240),
      detail: cleanText(raw.detail, 1000),
      severity: severity,
      reset_at: cleanText(raw.reset_at, 80),
      window_start_at: cleanText(raw.window_start_at, 80)
    }
  }
  if (type === "text") {
    return {
      type: "text",
      label: cleanText(raw.label, 160),
      value: cleanText(raw.value, 1000)
    }
  }
  if (type === "block") {
    var body = Array.isArray(raw.body) ? raw.body : []
    var lines = []
    for (var i = 0; i < body.length && i < 24; i++) lines.push(cleanText(body[i], 1000))
    return { type: "block", label: cleanText(raw.label, 160), body: lines }
  }
  return null
}

function normalizeEntry(raw) {
  if (!raw || typeof raw !== "object") return null
  var id = cleanText(raw.id, 180).trim()
  if (id === "") return null
  var sourceSections = Array.isArray(raw.sections) ? raw.sections : []
  var sections = []
  for (var i = 0; i < sourceSections.length && i < 96; i++) {
    var section = normalizeSection(sourceSections[i])
    if (section) sections.push(section)
  }
  var error = raw.error === undefined || raw.error === null ? "" : cleanText(raw.error, 1200)
  // The engine keeps its own cache. When a provider stops answering it re-sends
  // the last good reading with `stale: true`, `error: null`, and the failure
  // demoted to a text row labelled "Warning" — prefixed "credentials error:"
  // whatever the cause. For a provider that sleeps by design (Antigravity: no
  // app or agy session, no local server) that row is neither a warning nor a
  // login problem, so it is lifted out here into `offline_notice` and the panel
  // says "not running · last seen …" instead. The gate is deliberately narrow —
  // the engine's cached shape, its Warning row, an is-not-running message, and
  // a vendor listed in OFFLINE_HINTS — so a cloud provider's refused connection
  // or any other warning stays in the sections, red, where it belongs.
  var offlineNotice = ""
  var refusal = null
  var authNote = ""
  var displayName = cleanText(raw.display_name, 240) || id
  var kept = []
  var liftable = raw.stale === true && sleepsByDesign({ id: id })
  var heading = ""
  for (var s = 0; s < sections.length; s++) {
    var row = sections[s]
    // A text row with a label and no value is a heading ("Session", "Weekly");
    // the metric rows under it inherit it, which is how a 0 % reading later
    // learns how long its window is.
    if (row.type === "text" && row.value === "" && row.label !== "") heading = row.label
    if (row.type === "metric") row.window_hint = heading
    if (liftable && row.type === "text" && /^warning$/i.test(row.label) && isOfflineError(row.value)) {
      if (offlineNotice === "") offlineNotice = row.value.replace(/^\s*credentials error:\s*/i, "")
      // The spacer that introduced the row would otherwise trail the list.
      if (kept.length > 0 && kept[kept.length - 1].type === "spacer") kept.pop()
      continue
    }
    // The engine demotes an HTTP failure of a cached provider into a text row
    // labelled with the status ("HTTP 403" · "Cursor authentication failed").
    // A 403, 429 or 5xx on a cached reading is the dashboard refusing or
    // failing the check — Cursor's edge refused the engine's client while the
    // login still worked (2026-09-07) — so it is lifted into `refusal` and
    // the panel words it as what it is. A 401 is the opposite: the credentials
    // were rejected. That row becomes a login problem (`auth_note`): the cell
    // shows the urgent dot and no number, never a calm cached percentage.
    if (raw.stale === true && row.type === "text" && /^HTTP (401|403|429|5\d\d)$/i.test(row.label)) {
      var httpStatus = parseInt(row.label.slice(5), 10)
      if (httpStatus === 401) {
        if (authNote === "") authNote = displayName + " needs a new sign-in (HTTP 401)"
      } else if (!refusal) {
        refusal = { status: httpStatus, text: cleanText(row.value, 200) }
      }
      if (kept.length > 0 && kept[kept.length - 1].type === "spacer") kept.pop()
      continue
    }
    kept.push(row)
  }
  sections = kept
  // Fork addition: the 1.12 engine also ships a flat `metrics` list. Upstream
  // reads quota out of `sections`; the provider strip wants the flat list, so
  // carry it through the same sanitizing boundary rather than reaching past it.
  var sourceMetrics = Array.isArray(raw.metrics) ? raw.metrics : []
  var metrics = []
  for (var m = 0; m < sourceMetrics.length && m < 32; m++) {
    var metric = sourceMetrics[m]
    if (!metric || typeof metric !== "object") continue
    metrics.push({
      label: cleanText(metric.label, 160),
      percent: finitePercent(metric.percent),
      value: cleanText(metric.value, 240),
      detail: cleanText(metric.detail, 1000),
      severity: cleanText(metric.severity, 24),
      reset_at: cleanText(metric.reset_at, 80),
      window_start_at: cleanText(metric.window_start_at, 80),
      window_hint: ""
    })
  }
  // The flat list has no headings; borrow each metric's from its twin section
  // row (same label and reset time) so both views agree on the window.
  for (var k = 0; k < metrics.length; k++) {
    for (var q = 0; q < sections.length; q++) {
      var twin = sections[q]
      if (twin.type === "metric" && twin.label === metrics[k].label && twin.reset_at === metrics[k].reset_at) {
        metrics[k].window_hint = twin.window_hint || ""
        break
      }
    }
  }
  return {
    id: id,
    name: cleanText(raw.name, 240),
    display_name: cleanText(raw.display_name, 240),
    short_name: cleanText(raw.short_name, 24),
    plan: cleanText(raw.plan, 240),
    status: error !== "" || raw.status === "error" ? "error" : "ready",
    error: error,
    stale: raw.stale === true,
    offline_notice: offlineNotice,
    refusal: refusal,
    auth_note: authNote,
    source: raw.source === "native" ? "native" : "",
    fetched_at: cleanText(raw.fetched_at, 80),
    metrics: metrics,
    sections: sections
  }
}

function parseReport(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    if (!parsed || !Array.isArray(parsed.entries))
      return { ok: false, error: "The usage command returned an unsupported report.", primary: "", entries: [] }
    var entries = []
    for (var i = 0; i < parsed.entries.length && i < 64; i++) {
      var entry = normalizeEntry(parsed.entries[i])
      if (entry) entries.push(entry)
    }
    if (parsed.entries.length > 0 && entries.length === 0)
      return { ok: false, error: "The usage report did not contain a valid provider entry.", primary: "", entries: [] }
    return { ok: true, error: "", primary: cleanText(parsed.primary, 180).trim(), entries: entries }
  } catch (error) {
    return { ok: false, error: "The usage command returned invalid JSON.", primary: "", entries: [] }
  }
}

function baseProvider(id) {
  return String(id || "").split("@")[0]
}

function providerName(entry) {
  if (!entry) return "AI usage"
  // The Rust report owns canonical product names. `name` is the compatible
  // fallback for older binaries; the machine id is only a last resort.
  var title = cleanText(entry.display_name || entry.name, 240).trim()
  if (title === "") title = baseProvider(entry.id).replace(/_/g, " ") || "AI usage"
  return autoTextSafe(title)
}

// The Waybar-style provider tag. `VendorId::short_name` in Rust owns the codes
// and ships them as `short_name`; a binary older than that field has none, so
// the machine id's vendor half stands in rather than a table living here.
function providerShort(entry) {
  if (!entry) return ""
  var code = cleanText(entry.short_name, 24).trim()
  if (code === "") code = baseProvider(entry.id).replace(/_/g, "-")
  return autoTextSafe(code).trim()
}

function filteredEntries(entries, configuredProvider) {
  var list = Array.isArray(entries) ? entries : []
  var wanted = String(configuredProvider || "").trim().toLowerCase()
  if (wanted === "") return list.slice()
  var exact = list.filter(function(entry) { return String(entry.id).toLowerCase() === wanted })
  if (exact.length > 0) return exact
  return list.filter(function(entry) { return baseProvider(entry.id).toLowerCase() === wanted })
}

function selectedIndex(entries, selectedId) {
  var list = Array.isArray(entries) ? entries : []
  for (var i = 0; i < list.length; i++) if (list[i].id === selectedId) return i
  return list.length > 0 ? 0 : -1
}

function preferredEntryId(entries, primaryProvider, rememberedEntryId) {
  var list = Array.isArray(entries) ? entries : []
  if (list.length === 0) return ""
  var remembered = cleanText(rememberedEntryId, 180).trim().toLowerCase()
  for (var r = 0; r < list.length; r++)
    if (String(list[r].id).toLowerCase() === remembered) return list[r].id
  var primary = String(primaryProvider || "").toLowerCase()
  for (var i = 0; i < list.length; i++)
    if (String(list[i].id).toLowerCase() === primary) return list[i].id
  for (var j = 0; j < list.length; j++)
    if (baseProvider(list[j].id).toLowerCase() === primary) return list[j].id
  return list[0].id
}

function settingsWithOverrides(settings, moduleName, overrides) {
  var moduleId = cleanText(moduleName, 180).trim()
  if (moduleId === "" || !overrides || typeof overrides !== "object" || Array.isArray(overrides))
    return null

  var next = { id: moduleId }
  var current = settings && typeof settings === "object" && !Array.isArray(settings)
    ? settings : {}
  for (var key in current) {
    if (key === "id" || key === "__proto__" || key === "constructor" || key === "prototype")
      continue
    next[key] = current[key]
  }
  for (var overrideKey in overrides) {
    if (overrideKey === "id" || overrideKey === "__proto__" || overrideKey === "constructor"
        || overrideKey === "prototype") continue
    next[overrideKey] = overrides[overrideKey]
  }
  return next
}

function settingsWithSelectedEntry(settings, moduleName, entryId) {
  var selected = cleanText(entryId, 180).trim()
  if (selected === "") return null
  return settingsWithOverrides(settings, moduleName, { lastSelectedEntryId: selected })
}

function booleanSetting(value, fallback) {
  if (value === true || value === false) return value
  var normalized = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  if (["true", "1", "yes", "on"].indexOf(normalized) >= 0) return true
  if (["false", "0", "no", "off"].indexOf(normalized) >= 0) return false
  return fallback === true
}

// `providerLabel` is already resolved by the caller: empty when the opt-in
// provider switch is off, so the icon-and-value label is unchanged for everyone
// who never turns it on. A vertical bar has no width for either field and
// keeps showing the icon alone.
function barLabel(alarming, vertical, showValue, loading, hasEntry, summaryText,
                  providerLabel) {
  var icon = "󰚩"
  if (vertical) return alarming ? "󰅙" : icon
  if (loading && !hasEntry) return icon + "  …"
  if (!hasEntry) return alarming ? "󰅙" : icon
  var provider = autoTextSafe(providerLabel).trim()
  var summary = showValue ? autoTextSafe(summaryText).trim() : ""
  if (provider === "") return summary === "" ? icon : icon + "  " + summary
  // One space between tag and value, matching Waybar's
  // `{vendor_short} {session_pct}%`; the wider gap stays next to the icon.
  return summary === "" ? icon + "  " + provider
    : icon + "  " + provider + " " + summary
}

function headline(entry) {
  if (!entry) return { text: "", percent: null, severity: "low", label: "" }
  var best = null
  var sections = entry.sections || []
  for (var i = 0; i < sections.length; i++) {
    var section = sections[i]
    if (section.type === "metric" && (!best || section.percent > best.percent)) best = section
  }
  if (best) {
    var bestText = /balance/i.test(best.label) && best.value !== ""
      ? best.value : best.percent + "%"
    return {
      text: bestText,
      percent: best.percent,
      severity: best.severity,
      label: best.label
    }
  }
  for (var j = 0; j < sections.length; j++) {
    var row = sections[j]
    if (row.type === "text" && /(balance|available|spend|prepaid)/i.test(row.label) && row.value !== "")
      return { text: row.value, percent: null, severity: "low", label: row.label }
  }
  // A provider that is asleep by design has nothing to headline and nothing
  // wrong: the hero's detail line stays empty rather than saying "Error" one
  // row under "Not running".
  var text = entry.status === "error" ? (isAsleep(entry) ? "" : "Error") : "Ready"
  return { text: text, percent: null, severity: "low", label: "" }
}

// The panel's urgency, and the same rule the strip uses for its urgent dot:
// a login problem, a real failure, or a critical reading. A stale number and a
// provider that is asleep by design are calm in the bar and stay calm here.
function isAlarming(entry) {
  if (!entry) return false
  var state = cellState(entry)
  return state === "auth" || state === "error" || headline(entry).severity === "critical"
}

function formatDuration(milliseconds) {
  if (!(milliseconds > 0)) return "now"
  var minutes = Math.floor(milliseconds / 60000)
  var hours = Math.floor(minutes / 60)
  var days = Math.floor(hours / 24)
  if (days > 0) return days + "d " + (hours % 24) + "h"
  if (hours > 0) return hours + "h " + (minutes % 60) + "m"
  return Math.max(1, minutes) + "m"
}

var MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function pad2(value) {
  return ("0" + value).slice(-2)
}

function isSameLocalDay(a, b) {
  return a.getFullYear() === b.getFullYear()
    && a.getMonth() === b.getMonth()
    && a.getDate() === b.getDate()
}

function formatReset(resetAt, nowMs) {
  if (!resetAt) return ""
  var resetMs = new Date(String(resetAt)).getTime()
  if (!isFinite(resetMs)) return ""
  var remaining = resetMs - Number(nowMs)
  if (remaining <= 0) return "Reset due"
  // Show the real local clock time the window reopens, so the absolute
  // reset moment is visible next to the countdown. Date it whenever it
  // lands on another day: a bare "03:00" on an 18h countdown reads as a
  // time that has already passed, which is the ambiguity this row exists
  // to remove. Keyed on the calendar day rather than on "is it 24h away",
  // because tonight's reset crosses midnight long before it crosses 24h.
  var at = new Date(resetMs)
  var clock = pad2(at.getHours()) + ":" + pad2(at.getMinutes())
  if (!isSameLocalDay(at, new Date(Number(nowMs))))
    clock = MONTH_NAMES[at.getMonth()] + " " + at.getDate() + " " + clock
  return "Resets in " + formatDuration(remaining) + " · " + clock
}

function formatUpdated(fetchedAt, nowMs) {
  if (!fetchedAt) return "Updated time unavailable"
  var fetchedMs = new Date(String(fetchedAt)).getTime()
  if (!isFinite(fetchedMs)) return "Updated time unavailable"
  var elapsed = Math.max(0, Number(nowMs) - fetchedMs)
  if (elapsed < 60000) return "Updated just now"
  return "Updated " + formatDuration(elapsed) + " ago"
}

// The same reading as formatUpdated, phrased for a provider that is not
// answering: "Antigravity is not running · last seen 2h 5m ago". formatUpdated
// leads with "Updated", which in that sentence would claim the opposite.
function lastSeenLabel(fetchedAt, nowMs) {
  if (!fetchedAt) return "last seen earlier"
  var fetchedMs = new Date(String(fetchedAt)).getTime()
  if (!isFinite(fetchedMs)) return "last seen earlier"
  var elapsed = Math.max(0, Number(nowMs) - fetchedMs)
  if (elapsed < 60000) return "last seen just now"
  return "last seen " + formatDuration(elapsed) + " ago"
}

function metricDetail(row, nowMs) {
  var detail = cleanText(row && row.detail, 1000)
  if (!row || !row.reset_at) return detail
  // Older human-readable reset text remains useful to CLI consumers. Strip
  // just that fragment in the native panel, which renders a live countdown.
  detail = detail.replace(/^Resets in [^·]+\s*(?:·\s*)?/i, "")
  detail = detail.replace(/\s*·\s*reset\s+[^·]+$/i, "")
  detail = detail.trim()
  // Only an explicit provider timestamp establishes a start.
  if (row.window_start_at && row.percent === 0 && nowMs !== undefined) {
    var began = windowStartLabel(row, nowMs)
    if (began) detail = detail ? detail + " · " + began : began
  }
  return detail
}

// "17:39", or "Sep 6 17:39" when it is not today. Takes an ISO string or a
// millisecond timestamp.
function clockLabel(iso, nowMs) {
  var ms = typeof iso === "number" ? iso : new Date(String(iso)).getTime()
  if (!isFinite(ms)) return ""
  var at = new Date(ms)
  var clock = pad2(at.getHours()) + ":" + pad2(at.getMinutes())
  if (!isSameLocalDay(at, new Date(Number(nowMs)))) clock = MONTH_NAMES[at.getMonth()] + " " + at.getDate() + " " + clock
  return clock
}

// Show only a start explicitly reported by the provider. Reset times alone are insufficient.
function windowStartLabel(metric, nowMs) {
  if (!metric || !metric.reset_at || !metric.window_start_at) return ""
  var resetMs = new Date(String(metric.reset_at)).getTime()
  if (!isFinite(resetMs)) return ""
  var startMs = metric.window_start_at ? new Date(String(metric.window_start_at)).getTime() : NaN
  if (!isFinite(startMs)) return ""
  var since = Number(nowMs) - startMs
  if (!(since >= 0) || Number(nowMs) > resetMs) return ""
  return "window began " + formatDuration(since) + " ago (" + clockLabel(startMs, nowMs) + ")"
}

// What a dashboard did with the last check, by status: 403 refused it, 429
// rate-limited it, 5xx could not answer it. Never "authentication failed".
function refusalVerb(status) {
  var code = Number(status) || 0
  if (code === 429) return "rate-limited"
  if (code >= 500) return "could not answer"
  return "refused"
}

function refusalPhrase(entry) {
  if (!entry || !entry.refusal) return ""
  var status = Number(entry.refusal.status) || 0
  return "dashboard " + refusalVerb(status) + " the last check" + (status ? " (HTTP " + status + ")" : "")
}

// The panel's status line for a cached reading the provider's dashboard
// refused or failed. The login is not in question — a 401 never comes this
// way, and the native Cursor reader checks /api/auth/me before calling it a
// refusal — so this names the status and dates the numbers instead.
function refusalStatus(entry, nowMs) {
  if (!entry || !entry.refusal) return ""
  var line = providerName(entry) + "'s " + refusalPhrase(entry)
  var clock = entry.fetched_at ? clockLabel(entry.fetched_at, nowMs) : ""
  return clock !== "" ? line + " · showing the " + clock + " reading" : line
}

// The panel's status line for a reading whose login has stopped working: the
// note (the native reader's, which says what to run, or the engine's 401) and
// the age of the numbers below it.
function authStatus(entry, nowMs) {
  if (!entry || String(entry.auth_note || "") === "") return ""
  var clock = entry.fetched_at ? clockLabel(entry.fetched_at, nowMs) : ""
  return clock !== "" ? entry.auth_note + " · showing the " + clock + " reading" : entry.auth_note
}

function errorMessage(value) {
  var message = cleanText(value, 500).trim()
  return message === "" ? "The usage command failed without an error message." : message
}

// The panel launches ai-usagebar through /usr/bin/env, so a missing binary
// comes back as exit 127 instead of the process simply never starting.
// Quickshell does not emit `exited` when it cannot launch a binary directly --
// it only logs an internal warning -- which used to leave the widget stuck on
// its loading state with no way to explain that the binary was not installed.
function launchErrorMessage(exitCode, stderrText) {
  if (Number(exitCode) === 127)
    return "ai-usagebar is not installed. The plugin is only the display frontend. Install the binary with: omarchy pkg aur add ai-usagebar-bin"
  return errorMessage(stderrText)
}

function settingsId(value) {
  var id = cleanText(value, 80).trim()
  if (!/^[a-z0-9_-]+$/.test(id)
      || id === "__proto__" || id === "constructor" || id === "prototype") return ""
  return id
}

// The Rust bridge deliberately returns only key-presence booleans. Keep this
// parser strict so a compromised/older helper cannot smuggle rich text or an
// unbounded model into the long-lived shell process.
function parseSettingsSnapshot(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    if (!parsed || Number(parsed.schema_version) !== 1
        || !Array.isArray(parsed.primary_choices) || !Array.isArray(parsed.keys))
      return { ok: false, error: "The settings command returned an unsupported response.", primary: "", primary_choices: [], keys: [] }

    var choices = []
    for (var i = 0; i < parsed.primary_choices.length && i < 64; i++) {
      var choice = parsed.primary_choices[i]
      var choiceId = settingsId(choice && choice.id)
      if (choiceId === "") continue
      choices.push({ id: choiceId, value: choiceId, label: cleanText(choice.label, 120) || choiceId })
    }

    var keys = []
    for (var j = 0; j < parsed.keys.length && j < 32; j++) {
      var key = parsed.keys[j]
      var keyId = settingsId(key && key.id)
      if (keyId === "") continue
      keys.push({
        id: keyId,
        label: cleanText(key.label, 120) || keyId,
        environment: cleanText(key.environment, 160),
        secret_label: cleanText(key.secret_label, 120),
        note: cleanText(key.note, 240),
        configured: key.configured === true,
        inline_configured: key.inline_configured === true,
        environment_configured: key.environment_configured === true
      })
    }

    var primary = settingsId(parsed.primary)
    var primaryAvailable = false
    for (var k = 0; k < choices.length; k++) {
      if (choices[k].id === primary) {
        primaryAvailable = true
        break
      }
    }
    if (!primaryAvailable) primary = choices.length > 0 ? choices[0].id : ""
    return { ok: true, error: "", primary: primary, primary_choices: choices, keys: keys }
  } catch (error) {
    return { ok: false, error: "The settings command returned invalid JSON.", primary: "", primary_choices: [], keys: [] }
  }
}

function buildSettingsPatch(primary, changes) {
  var primaryId = settingsId(primary)
  var rawPrimary = String(primary || "").trim()
  if (rawPrimary !== "" && primaryId === "")
    return { ok: false, error: "Choose a valid primary provider.", payload: "" }
  var keys = {}
  var list = Array.isArray(changes) ? changes : []
  var seen = []
  for (var i = 0; i < list.length; i++) {
    var change = list[i] || {}
    var id = settingsId(change.id)
    if (id === "" || seen.indexOf(id) >= 0)
      return { ok: false, error: "A settings row has an invalid provider id.", payload: "" }
    seen.push(id)
    if (change.action === "clear") {
      keys[id] = { action: "clear" }
    } else if (change.action === "set") {
      var value = String(change.value || "")
      if (value === "") return { ok: false, error: "An edited credential is empty.", payload: "" }
      if (value.length > 16384) return { ok: false, error: "A credential is too long.", payload: "" }
      keys[id] = { action: "set", value: value }
    } else return { ok: false, error: "A settings row has an invalid action.", payload: "" }
  }
  if (primaryId === "" && seen.length === 0)
    return { ok: false, error: "There are no settings changes to save.", payload: "" }
  var patch = { schema_version: 1, keys: keys }
  if (primaryId !== "") patch.primary = primaryId
  return {
    ok: true,
    error: "",
    payload: JSON.stringify(patch)
  }
}

function parseSettingsApplyResult(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    return parsed && parsed.ok === true
  } catch (error) {
    return false
  }
}

// ---------------------------------------------------------------------------
// Provider-strip model (fork addition)
//
// Everything below is what turns one report into the bar's row of provider
// cells. Upstream's model answers "what does the selected provider read?";
// this answers "what does every provider read, at a glance?", which is the
// whole point of the fork. Kept in this file, and free of QML globals, so
// Node exercises the same code the shell runs.
// ---------------------------------------------------------------------------

// Marks are looked up by vendor, not by account: `anthropic@work` wears the
// Anthropic mark. A handful of engine ids do not match the asset name, so the
// aliases live here rather than as duplicated files.
var MARK_ALIASES = {
  "claude": "anthropic",
  "codex": "openai",
  "chatgpt": "openai",
  "gpt": "openai",
  "grok": "supergrok",
  "xai": "supergrok",
  "moonshot": "kimi",
  "gemini": "antigravity",
  "google": "antigravity",
  "agy": "antigravity",
  "fireworks-ai": "fireworks",
  "github-copilot": "copilot",
  "githubcopilot": "copilot"
}

// Every mark this plugin ships. A vendor outside the list gets the
// typographic fallback, which is a designed state rather than a hole.
var MARK_FILES = [
  "anthropic", "antigravity", "copilot", "cursor", "deepseek", "fireworks",
  "kimi", "openai", "opencode", "openrouter", "supergrok", "xiaomi", "cherryin"
]

// The one place a vendor's brand colour is written down. Values are the `hex`
// field of the matching Simple Icons entry (CC0), which is the vendor's own
// published mark colour rather than a colour picked here.
//
// Only a brand that HAS a colour appears. OpenAI, Cursor, X/Grok, Kimi,
// Copilot, opencode and Z.AI publish a black-or-white mark, so there is no
// brand colour to be faithful to and they keep the bar's foreground; Fireworks
// has no reliable published hex. Keyed on the resolved mark id, so an alias
// (`gemini`, `claude`, `anthropic@work`) inherits its vendor's colour without a
// second entry.
//
// OpenRouter's slate (#94A3B8) is measured out rather than absent: against the
// light bar surface it lands at 2.2:1, under the 3:1 floor for a graphic that
// carries meaning, and slate against a grey bar buys no recognition anyway. It
// keeps the foreground and stays legible in both themes.
var BRAND_COLORS = {
  anthropic: "#D97757",    // Claude terracotta
  antigravity: "#8E75B2",  // Google Gemini
  deepseek: "#5786FE",
  xiaomi: "#FF6900"
}

// Marks whose current artwork is a picture rather than a silhouette. Each ships
// as assets/<mark>-color.png and ProviderMark draws it as-is on a dark bar
// surface. An explicit list, like BRAND_COLORS, so the widget never asks the
// disk for a file that is not there (a missing image is a warning per render).
var COLOR_ART = ["antigravity", "cursor", "kimi", "openai", "openrouter"]

function hasColorArt(mark) {
  return COLOR_ART.indexOf(String(mark || "")) >= 0 || mark === "cherryin"
}

function colorArtFile(mark) {
  if (mark === "cherryin") return "cherryin.svg"
  return COLOR_ART.indexOf(String(mark || "")) >= 0 ? mark + "-color.png" : ""
}

// The one-colour silhouette under assets/ that is still the vendor's own mark,
// drawn through the ink mask; "" where there is none. Three vendors' only
// faithful mark is a picture: Antigravity's arch (antigravity.svg is the Gemini
// star, a different identity), OpenRouter's lime pill (its svg is a different
// glyph) and CherryIN's filled tile (as a mask, a blank square). Those
// keep their picture when a plain mark is asked for.
var PICTURE_ONLY = ["antigravity", "openrouter", "cherryin"]

function silhouetteFile(mark) {
  var vendor = String(mark || "")
  if (vendor === "" || MARK_FILES.indexOf(vendor) < 0 || PICTURE_ONLY.indexOf(vendor) >= 0) return ""
  return vendor + ".svg"
}

// Read-only diagnostics from the instantiated scene, not reconstructed source.
// Includes no account data, usage values, credentials, or titles.
function renderedMarks(item) {
  var out = []
  if (!item) return out
  if (item.objectName === "providerMark") {
    out.push({ role: item.role, mark: item.mark, ready: item.usingMark,
      colorArt: item.usingColor, ink: String(item.brandInk),
      artwork: item.artwork, width: item.width, height: item.height })
  }
  var children = item.children || []
  for (var i = 0; i < children.length; i++)
    out = out.concat(renderedMarks(children[i]))
  return out
}

// Marks that are wordmarks rather than glyphs, and the width each needs as a
// multiple of the square icon canvas. SpaceXAI's swoosh-X-A-I is twice as wide
// as it is tall; squeezed into a square at bar size it read as a lone X, which
// the owner rightly called wrong. Everything else is 1 (square).
// Severity may change an ink's hue and weight, never its legibility. The
// theme's alarm colour is a palette red, and a generated palette can make it
// far darker than the text beside it (Aether, 2026-11: #58241c next to
// #dbcca5). Contrast depends on luminance alone, so the rule works on that:
//
//   - On a surface whose colour is known (a panel), a red that already clears
//     WCAG AA (4.5:1) there, and is as bright as the floor below, is a
//     designed ink and is kept as it is.
//   - Otherwise the alarm follows the ink it escalates from, because that ink
//     is the one colour known to read on whatever is behind it. The bar can be
//     see-through, and a plugin is not told what shows through it. Light ink
//     means a dark backdrop, so the alarm is lifted to a floor: the ink's own
//     luminance, but never more than 0.3 (7:1 on black). Dark ink means a light
//     backdrop, so it is never lighter than a red that reads on white. A red
//     already on the right side is left alone.
//
// The 0.3 cap is what keeps an alarm red. Lifted all the way to cream text's
// luminance (0.61) the palette red turned pastel pink (Aether 2026-11-11:
// #a1665b became #fbbfb4) and a designed red such as #ff5555 nearly white; at
// 0.3 the first is a saturated coral (#f6684e, 5:1 or better on the dark bar)
// and the second is all but unchanged.
//
// What changes is lightness; the hue stays the theme's, with enough saturation
// to still read as red. Channels 0..1; [r, g, b]. surface may be null.
function legibleAlarmRgb(alarm, ink, surface) {
  function linear(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) }
  function luminance(c) { return 0.2126 * linear(c[0]) + 0.7152 * linear(c[1]) + 0.0722 * linear(c[2]) }
  function channel(p, q, t) {
    if (t < 0) t += 1
    if (t > 1) t -= 1
    if (t < 1 / 6) return p + (q - p) * 6 * t
    if (t < 1 / 2) return q
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
    return p
  }
  function fromHsl(h, s, l) {
    var q = l < 0.5 ? l * (1 + s) : l + s - l * s
    var p = 2 * l - q
    return [channel(p, q, h + 1 / 3), channel(p, q, h), channel(p, q, h - 1 / 3)]
  }
  var la = luminance(alarm), li = luminance(ink)
  // 0.18 is where an ink stops reading on white (4.5:1) and, near enough,
  // where text switches from dark-on-light to light-on-dark.
  var lightInk = li >= 0.18
  var floor = Math.min(li, 0.3)
  if (surface && (!lightInk || la >= floor)) {
    var ls = luminance(surface)
    if ((Math.max(la, ls) + 0.05) / (Math.min(la, ls) + 0.05) >= 4.5) return alarm.slice(0, 3)
  }
  var target = lightInk ? Math.max(la, floor) : Math.min(la, 0.18)
  if (Math.abs(target - la) < 0.004) return alarm.slice(0, 3)
  var r = alarm[0], g = alarm[1], b = alarm[2]
  var max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min
  var hue = 0
  if (d > 0) {
    if (max === r) hue = ((g - b) / d + (g < b ? 6 : 0)) / 6
    else if (max === g) hue = ((b - r) / d + 2) / 6
    else hue = ((r - g) / d + 4) / 6
  }
  var lightness = (max + min) / 2
  var saturation = d === 0 ? 0 : d / (1 - Math.abs(2 * lightness - 1))
  saturation = Math.max(saturation, 0.9)
  var lo = 0, hi = 1
  for (var i = 0; i < 24; i++) {
    var mid = (lo + hi) / 2
    if (luminance(fromHsl(hue, saturation, mid)) < target) lo = mid
    else hi = mid
  }
  return fromHsl(hue, saturation, (lo + hi) / 2)
}

var MARK_ASPECT = { supergrok: 2 }

function markAspect(mark) {
  var aspect = MARK_ASPECT[String(mark || "")]
  return aspect ? aspect : 1
}

function markId(id) {
  var vendor = baseProvider(id).toLowerCase().replace(/[^a-z0-9-]/g, "")
  if (MARK_ALIASES[vendor]) vendor = MARK_ALIASES[vendor]
  return MARK_FILES.indexOf(vendor) >= 0 ? vendor : ""
}

// "" means "no brand colour": the caller keeps the bar's foreground, which is
// what every monochrome brand and every unknown vendor gets.
function brandColor(mark) {
  var vendor = String(mark || "")
  return BRAND_COLORS[vendor] ? BRAND_COLORS[vendor] : ""
}

// Two letters, upper case, for a vendor with no mark. Prefers the engine's own
// short code so the fallback matches what Waybar prints.
function markInitials(entry) {
  var source = entry ? (cleanText(entry.short_name, 24).trim() || baseProvider(entry.id)) : ""
  var letters = String(source).replace(/[^A-Za-z0-9]/g, "")
  if (letters === "") return "··"
  return letters.slice(0, 2).toUpperCase()
}

// `metrics` is the flat quota list the 1.12 engine ships. Older reports only
// carry `sections`, so the metric rows in there stand in. Either way the strip
// sees one shape.
function entryMetrics(entry) {
  if (!entry) return []
  var out = []
  var raw = Array.isArray(entry.metrics) ? entry.metrics : []
  for (var i = 0; i < raw.length && i < 32; i++) {
    var m = raw[i]
    if (!m || typeof m !== "object") continue
    var percent = finitePercent(m.percent)
    out.push({
      label: cleanText(m.label, 160),
      percent: percent,
      value: cleanText(m.value, 240),
      detail: cleanText(m.detail, 1000),
      severity: cleanText(m.severity, 24),
      reset_at: cleanText(m.reset_at, 80),
      window_start_at: cleanText(m.window_start_at, 80),
      window_hint: cleanText(m.window_hint, 40)
    })
  }
  if (out.length > 0) return out
  var sections = entry.sections || []
  for (var j = 0; j < sections.length; j++) {
    var section = sections[j]
    if (section.type !== "metric") continue
    // Projected, not passed through: a section row carries `type`, and the one
    // shape this function promises is the flat metric. It is also what makes a
    // remembered reading serialize identically to the one it came from.
    out.push({
      label: section.label,
      percent: section.percent,
      value: section.value,
      detail: section.detail,
      severity: section.severity,
      reset_at: section.reset_at,
      window_start_at: section.window_start_at || "",
      window_hint: section.window_hint || ""
    })
  }
  return out
}

// A percent is only worth a meter when the engine actually reported one.
// DeepSeek reports a balance and no quota at all; painting it a 0%-wide meter
// would read as "empty", which is the opposite of the truth.
function severityForPercent(percent) {
  if (percent === null) return "none"
  if (percent >= 90) return "critical"
  if (percent >= 70) return "warn"
  return "normal"
}

// A side pool the owner has switched off: Cursor's "Other Models" (named and
// API models) says "on-demand off" in its detail. Full there does not stop the
// plan he uses (the included "Cursor Models" pool), so it never outranks a
// metric that is not a side pool; the tooltip and the panel still show it.
// (Fix round 2026-11-20: otherwise a full side pool is a permanent crimson
// "100" on the bar for a month, the same false alarm the old balance was.)
function sidePool(metric) {
  return /on-demand off/i.test(String(metric && metric.detail || ""))
}

// A value that is money: "$6.39", "-$0.01", "\u2212$2.00" (a typographic minus).
var MONEY_VALUE = /^\s*[-+\u2212]?\s*[$€£¥]/

// The one number the cell shows: the provider's most-constrained metric. A
// metric whose value is a bare amount of money (OpenRouter's credit balance)
// is a prepaid balance and shows the money. Money with a cap written beside it
// ("$12.00 / $20.00") is a plan being used up, so it keeps its percent and its
// column.
function cellHeadline(entry) {
  var empty = { text: "", percent: null, severity: "none", label: "", isMoney: false }
  if (!entry) return empty
  var metrics = entryMetrics(entry)
  var best = null
  for (var i = 0; i < metrics.length; i++) {
    var m = metrics[i]
    if (m.percent === null || m.percent === undefined) continue
    if (!best) { best = m; continue }
    var side = sidePool(m), bestSide = sidePool(best)
    if (side !== bestSide) { if (bestSide) best = m; continue }
    if (m.percent > best.percent) best = m
  }
  if (best) {
    var money = MONEY_VALUE.test(String(best.value || "")) && String(best.value).indexOf("/") < 0
    if (money) return balanceHeadline(best.value, best.label)
    return {
      // Bare digits, no per-cent sign. Every cell in the strip is a
      // percentage and each one is underlined by its own meter, so nine `%`
      // signs in a row are nine characters of noise — and dropping them is
      // what lets the number sit in a three-character tabular slot instead of
      // four. A money value keeps its currency mark: that is the one thing in
      // the strip that is not a percentage, and it has to say so.
      text: money ? best.value : String(best.percent),
      percent: best.percent,
      severity: severityForPercent(best.percent),
      label: best.label,
      isMoney: false,
      // The reading's own time is the clock: clock-free, and true as of the numbers.
      pace: pacePercent(best, Date.parse(entry.fetched_at || ""))
    }
  }
  // No quota anywhere. Fall back to the first section that carries a value at
  // all, so a balance-only provider still says something in the strip.
  var sections = (entry.sections || [])
  for (var j = 0; j < sections.length; j++) {
    var row = sections[j]
    if ((row.type === "text" || row.type === "metric") && cleanText(row.value, 240) !== "") {
      if (MONEY_VALUE.test(String(row.value))) return balanceHeadline(row.value, row.label)
      return {
        text: cleanText(row.value, 240),
        percent: null,
        severity: "none",
        label: cleanText(row.label, 160),
        isMoney: false,
        pace: null
      }
    }
  }
  return empty
}

// 1.14: a prepaid balance is money in a wallet, not a plan being used up, so
// "98 % of lifetime top-ups spent" is never an alarm. The amount reads in
// normal ink; below $5 it is "low" (bold), below $1 "critical" (urgent).
// percent stays null: there is no plan for a gauge to fill.
var BALANCE_LOW = 5
var BALANCE_CRITICAL = 1

function balanceHeadline(value, label) {
  var text = cleanText(value, 240).trim()
  var amount = parseFloat(text.replace(/\u2212/g, "-").replace(/[^0-9.\-]/g, ""))
  var severity = !isFinite(amount) ? "normal"
    : amount < BALANCE_CRITICAL ? "critical"
    : amount < BALANCE_LOW ? "warn" : "normal"
  return { text: text, percent: null, severity: severity, label: cleanText(label, 160),
    isMoney: true, pace: null }
}

// 1.14: how much of the metric's window has gone, 0..100, or null where the
// window is unknown. The engine states it in the detail ("· 42% elapsed ·");
// a window with both ends known is the fallback, given a clock.
function pacePercent(metric, nowMs) {
  if (!metric) return null
  var said = /(\d+(?:\.\d+)?)\s*%\s*elapsed/i.exec(String(metric.detail || ""))
  if (said) return Math.max(0, Math.min(100, parseFloat(said[1])))
  var start = Date.parse(metric.window_start_at || "")
  var end = Date.parse(metric.reset_at || "")
  var now = Number(nowMs)
  if (!isFinite(start) || !isFinite(end) || !isFinite(now) || end <= start) return null
  return Math.max(0, Math.min(100, Math.round((now - start) / (end - start) * 100)))
}

// Antigravity only serves quota while its app or an `agy` session is running,
// so its usual error is "not running", not "logged out". Dimming it like an
// idle provider and saving the urgent dot for a real credentials failure keeps
// the dot meaningful: if one is lit, something needs the owner.
function isOfflineError(message) {
  var text = String(message || "").toLowerCase()
  if (text === "") return false
  return text.indexOf("no local server") >= 0
    || text.indexOf("is only served while") >= 0
    || text.indexOf("not running") >= 0
    || text.indexOf("connection refused") >= 0
}

// A provider that has a reading to show but is not answering right now: either
// the engine re-sent its own cached reading (offline_notice) or this widget
// substituted its last-seen one (offline_cached). Both mean the same thing to
// the owner and get the same words.
function notRunning(entry) {
  if (!entry) return false
  return entry.offline_cached === true || String(entry.offline_notice || "") !== ""
}

// Vendors that sleep by design — their quota is served by a local process
// that exists only while their app or CLI is open — and what brings each one
// back. Only Antigravity today. This list is the gate for every calm
// "not running" presentation: a cloud provider that refuses a connection is
// a failure and keeps its own error text and its red styling.
var OFFLINE_HINTS = {
  antigravity: "Quota is only reported while the Antigravity app or an agy session is open."
}

function sleepsByDesign(entry) {
  return !!entry && Object.prototype.hasOwnProperty.call(OFFLINE_HINTS, baseProvider(entry.id).toLowerCase())
}

// Asleep: a by-design sleeper that is not answering — with a reading to show
// (notRunning) or without one (cellState offline). The panel keys its calm
// path on this and nothing else.
function isAsleep(entry) {
  return sleepsByDesign(entry) && (cellState(entry) === "offline" || notRunning(entry))
}

// The panel's status line for a provider that is asleep. Says which provider,
// how old the numbers below are (when there are any), and what brings it back.
// Never "Warning", never "credentials": closing an app is neither. "" for
// anything that is not asleep, so the caller falls through to the real error.
function offlineStatus(entry, nowMs) {
  if (!isAsleep(entry)) return ""
  var hint = OFFLINE_HINTS[baseProvider(entry.id).toLowerCase()]
  if (!notRunning(entry)) return providerName(entry) + " is not running. " + hint
  return providerName(entry) + " is not running · " + lastSeenLabel(entry.fetched_at, nowMs) + ". " + hint
}

function isAuthError(message) {
  var text = String(message || "").toLowerCase()
  if (text === "" || isOfflineError(text)) return false
  return /\b(401|403)\b/.test(text)
    || text.indexOf("credentials error") >= 0
    || text.indexOf("authentication") >= 0
    || text.indexOf("unauthorized") >= 0
    || text.indexOf("not logged in") >= 0
    || text.indexOf("login") >= 0
}

// One word per cell, and the only thing the view branches on.
//   ok       full strength
//   stale    last known values, dimmed
//   offline  provider asleep — dimmed mark, no number, no alarm
//   auth     needs the owner — dimmed mark plus the urgent dot
//   error    anything else that failed
function cellState(entry) {
  if (!entry) return "loading"
  var message = String(entry.error || "")
  if (entry.status === "error" || message !== "") {
    if (isOfflineError(message)) return "offline"
    if (isAuthError(message)) return "auth"
    return "error"
  }
  // A cached reading whose credentials were rejected (the engine's 401 row,
  // or the native reader's verdict) needs the owner, whatever the numbers say.
  if (String(entry.auth_note || "") !== "") return "auth"
  if (entry.stale === true) return "stale"
  return "ok"
}

// The plan string is the only report field that can carry a key prefix
// (OpenRouter ships "OpenRouter — <key-prefix>"). Everything after the em dash
// is dropped before it can reach a tooltip, let alone the bar.
function planLabel(entry) {
  if (!entry) return ""
  var plan = cleanText(entry.plan, 240)
  var cut = plan.indexOf(" — ")
  if (cut >= 0) plan = plan.slice(0, cut)
  cut = plan.indexOf(" - ")
  if (cut >= 0 && /[A-Za-z0-9_-]{12,}/.test(plan.slice(cut))) plan = plan.slice(0, cut)
  return autoTextSafe(plan).trim()
}

// "Claude · Max 20x · Session 12% · Weekly 45% · Fable 61% · resets in 1d 7h"
function cellTooltip(entry, nowMs) {
  if (!entry) return "AI usage"
  var parts = [providerName(entry)]
  var state = cellState(entry)
  // An asleep provider we have never seen has nothing to report and no problem
  // to report either. One line is the whole truth.
  if (state === "offline") return providerName(entry) + " is not running"
  // An asleep provider we have seen leads with both facts in order: it is not
  // answering now, and this is when the numbers below were last true. The
  // engine's own cached reading and this widget's read the same way.
  if (notRunning(entry))
    parts[0] = providerName(entry) + " is not running · "
      + lastSeenLabel(entry.fetched_at, nowMs)
  var plan = planLabel(entry)
  if (plan !== "") parts.push(plan)
  if (state === "auth") parts.push("needs login")
  else if (state === "error") parts.push("unavailable")
  var metrics = entryMetrics(entry)
  var reset = ""
  var began = ""
  for (var i = 0; i < metrics.length && i < 6; i++) {
    var m = metrics[i]
    var value = cleanText(m.value, 240) || (m.percent === null ? "" : m.percent + "%")
    if (value === "") continue
    parts.push(autoTextSafe(cleanText(m.label, 160) + " " + value).trim())
    if (reset === "" && m.reset_at) reset = m.reset_at
    if (began === "" && m.percent === 0) began = windowStartLabel(m, nowMs)
  }
  if (began !== "") parts.push(began)
  if (metrics.length === 0 && state === "ok") {
    var headline = cellHeadline(entry)
    if (headline.text !== "")
      parts.push(autoTextSafe((headline.label ? headline.label + " " : "") + headline.text).trim())
  }
  // "cached" is what the engine's own stale flag means. A not-running
  // provider's reading already said so, with a date, in its first line.
  if (state === "stale" && !notRunning(entry)) {
    if (entry.graced) parts.push("last check failed · numbers from " + clockLabel(entry.fetched_at, nowMs))
    else if (entry.refusal) parts.push(refusalPhrase(entry))
    else parts.push("cached")
  }
  if (reset !== "") {
    var countdown = formatReset(reset, nowMs)
    if (countdown !== "") parts.push(autoTextSafe(countdown.replace(/^Resets in/, "resets in")))
  }
  return parts.join(" · ")
}

// The strip's order is the engine's order, which is the order the owner wrote
// their config in. `providers` overrides it — a comma list both filters and
// reorders, so "anthropic,openai" is a two-cell strip in that order.
function stripEntries(entries, providersSetting) {
  var list = Array.isArray(entries) ? entries : []
  var wanted = String(providersSetting || "").trim()
  if (wanted === "") return list.slice()
  var ids = wanted.split(",")
  var out = []
  for (var i = 0; i < ids.length; i++) {
    var id = ids[i].trim().toLowerCase()
    if (id === "") continue
    for (var j = 0; j < list.length; j++) {
      var entry = list[j]
      if (out.indexOf(entry) >= 0) continue
      if (String(entry.id).toLowerCase() === id || baseProvider(entry.id).toLowerCase() === id)
        out.push(entry)
    }
  }
  return out
}

// --------------------------------------------------- last seen, per provider
//
// Antigravity only answers while its app or an interactive `agy` session is
// running, which for most of the day is not the case — so its cell spent most
// of the day empty. An empty cell is not what the owner knows: the quota was
// 0% at 20:28 and nothing since then has spent any of it.
//
// So the widget remembers the last successful reading per provider and shows
// it, dimmed and dated, whenever that provider goes offline. Only what a cell
// and its tooltip need is kept, and an error string is never one of those
// things: this cache exists to remember successes.

// One record, from a live entry. Null when there is nothing worth remembering,
// which keeps a failed or empty reading from overwriting a good one.
function lastSeenRecord(entry) {
  if (!entry || entry.status === "error" || String(entry.error || "") !== "") return null
  var metrics = entryMetrics(entry)
  var sections = Array.isArray(entry.sections) ? entry.sections : []
  if (metrics.length === 0 && sections.length === 0) return null
  return {
    id: entry.id,
    display_name: cleanText(entry.display_name || entry.name, 240),
    // The label, not the raw field: OpenRouter's `plan` embeds a key prefix,
    // and the cell only ever shows what planLabel() leaves. Writing the raw
    // string would put that prefix in a file on disk to no purpose.
    plan: planLabel(entry),
    fetched_at: cleanText(entry.fetched_at, 80),
    metrics: metrics,
    sections: sections
  }
}

// The file is written by this widget, but it is still a file on disk that a
// text editor or a stale schema can reach, so it comes back in through
// `normalizeEntry` — the same sanitizing boundary the engine's own report
// crosses — rather than being trusted for having our name on it.
function parseLastSeen(raw) {
  var out = {}
  try {
    var parsed = JSON.parse(String(raw || ""))
    if (!parsed || !Array.isArray(parsed.providers)) return out
    for (var i = 0; i < parsed.providers.length && i < 64; i++) {
      var record = lastSeenRecord(normalizeEntry(parsed.providers[i]))
      if (record) out[record.id] = record
    }
  } catch (error) {
    // A corrupt cache is a cache we do not have. Never a broken strip.
  }
  return out
}

// Sorted by id so an unchanged cache serializes to a byte-identical string and
// the caller can skip the write entirely.
function serializeLastSeen(cache) {
  var ids = []
  for (var id in cache) if (cache[id]) ids.push(id)
  ids.sort()
  var providers = []
  for (var i = 0; i < ids.length; i++) providers.push(cache[ids[i]])
  return JSON.stringify({ schema_version: 1, providers: providers })
}

// A new map with every successful entry in this report folded in. Nothing is
// ever expired: a reading from last week is still the last thing that was
// true, and the tooltip says how old it is.
function rememberEntries(cache, entries) {
  var next = {}
  var current = cache && typeof cache === "object" ? cache : {}
  for (var id in current) if (current[id]) next[id] = current[id]
  var list = Array.isArray(entries) ? entries : []
  for (var i = 0; i < list.length; i++) {
    var record = lastSeenRecord(list[i])
    if (record) next[record.id] = record
  }
  return next
}

// The remembered reading, wearing the shape of a live entry so that every rule
// above — headline, severity, meter, tooltip — applies to it unchanged.
//
// Only an offline provider is ever substituted. An auth failure keeps its
// urgent dot and its empty cell: "your login expired" is not something a cached
// percentage is allowed to paper over, and a number that cannot be refreshed
// until the owner acts is exactly the number not to show.
function cachedEntry(entry, remembered) {
  if (!entry || !remembered || cellState(entry) !== "offline") return null
  return {
    id: entry.id,
    name: entry.name,
    display_name: remembered.display_name || entry.display_name,
    short_name: entry.short_name,
    plan: remembered.plan,
    status: "ready",
    error: "",
    stale: true,
    offline_cached: true,
    offline_notice: "",
    fetched_at: remembered.fetched_at,
    metrics: remembered.metrics,
    sections: remembered.sections
  }
}

// One cell's complete view model. The QML side reads these fields and nothing
// else, so every rule above is testable without a running shell.
//
// Deliberately clock-free: the countdown in a tooltip is built on demand by
// cellTooltip(). Folding the clock in here would rebuild this array every
// minute and churn every delegate in the strip for a string nobody is looking
// at unless they are hovering.
function stripCell(entry, remembered, missCount) {
  var source = cachedEntry(entry, remembered) || entry
  var state = cellState(source)
  // One missed refresh right after a fresh one is noise, not news: the last
  // reading stays at full strength and only the tooltip mentions the miss.
  // From the second miss in a row the cell dims as stale — and so does a
  // reading whose history is unknown (first refresh after a shell start).
  // Never for a login problem, a failure, or a vendor that is asleep by
  // design — those already have their own words.
  var graced = state === "stale" && !notRunning(source) && Number(missCount) === 1
  if (graced) {
    source = Object.assign({}, source, { graced: true })
    state = "ok"
  }
  var headline = state === "offline" || state === "auth" || state === "error"
    ? { text: "", percent: null, severity: "none", label: "", isMoney: false, pace: null }
    : cellHeadline(source)
  var mark = markId(source ? source.id : "")
  var cell = {
    id: source ? source.id : "",
    name: source ? providerName(source) : "",
    mark: mark,
    initials: markInitials(source),
    // The vendor's own colour where it has one, "" where the brand is
    // monochrome by design and the bar's foreground is the faithful answer.
    brand: brandColor(mark),
    state: state,
    // A cell with no reading to show drops its brand colour and is drawn as
    // the plain silhouette in the bar's ink, so colour on the strip always
    // means "this is a live number". Brand art at the down cell's 0.45 kept
    // its saturation (Kimi's blue dot, DeepSeek's blue whale) and read as a
    // working provider, or, for Kimi, as a second alarm dot.
    //
    // 1.14: never. Every mark is drawn as it is, in its own colours, in every
    // state; the column and the words beside it say what is wrong. (A plain
    // white Claude for "sign in" read as a different company.)
    plainMark: false,
    text: headline.text,
    percent: headline.percent,
    severity: headline.severity,
    isMoney: headline.isMoney,
    pace: headline.pace === undefined ? null : headline.pace,
    asleep: sleepsByDesign(source),
    refused: state === "stale" && !!(source && source.refusal),
    // A free-level login with nothing to measure: it says so in words rather
    // than a dangling dash (seen only when the providers option names it).
    noPlan: freeLevel(source) && entryMetrics(source).length === 0 && headline.text === "",
    graced: graced,
    alarming: state === "auth" || state === "error" || headline.severity === "critical",
    entry: source
  }
  cell.look = cellLook(cell)
  return cell
}

// `misses` counts consecutive refreshes in which a provider was not fresh
// (kept by UsageSource); it decides whether a stale reading is graced.
//
// 1.14: dormant providers take no room. With no explicit `providers` setting,
// a provider whose last usable reading is 14 days older than the freshest one
// in the same report, or that has no plan or balance at all, is left off the
// strip and listed by dormantProviders() for the panel instead. Measured
// against the report itself, not the wall clock, so the rule needs no timer
// and an engine that is wholly behind never empties the strip. A by-design
// sleeper (Antigravity) is never dormant: "not running" is its normal state.
var DORMANT_AFTER_MS = 14 * 24 * 3600 * 1000

function newestReading(entries) {
  var newest = NaN
  var list = Array.isArray(entries) ? entries : []
  for (var i = 0; i < list.length; i++) {
    var at = Date.parse(list[i] && list[i].fetched_at || "")
    if (isFinite(at) && !(newest >= at)) newest = at
  }
  return newest
}

function shortDate(ms) {
  var when = new Date(ms)
  return MONTH_NAMES[when.getMonth()] + " " + when.getDate()
}

// The report's own words for "the provider refused the saved key": an engine
// error, the reader's login note, or a "HTTP 401" row the engine kept.
function refusedKey(entry) {
  if (!entry) return false
  if (/\b401\b/.test(String(entry.error || "") + " " + String(entry.auth_note || ""))) return true
  var rows = entry.sections || []
  for (var i = 0; i < rows.length; i++)
    if (rows[i] && /\b401\b/.test(String(rows[i].label || "") + " " + String(rows[i].value || ""))) return true
  return false
}

function freeLevel(entry) {
  return !!entry && /^\s*free\s*$/i.test(String(entry.plan || ""))
}

// One plain sentence for the panel: why the provider is off the bar, and what
// brings it back. Derived from the report alone (no clock, no guessing).
function dormantReason(entry, remembered, newestMs) {
  if (!entry || sleepsByDesign(entry)) return ""
  var seen = Date.parse(entry.fetched_at || "")
  var kept = Date.parse(remembered && remembered.fetched_at || "")
  if (isFinite(kept) && !(seen >= kept)) seen = kept
  var name = providerName(entry)
  var state = cellState(entry)
  var empty = entryMetrics(entry).length === 0 && cellHeadline(entry).text === ""
  var old = isFinite(seen) && isFinite(newestMs) && newestMs - seen >= DORMANT_AFTER_MS
  if (old && refusedKey(entry))
    return name + " has refused the saved API key since " + shortDate(seen)
      + " (HTTP 401). A new API key brings it back."
  var failure = cleanText(entry.error, 160).trim()
  if (old && failure !== "" && state === "error")
    return name + " has had no reading since " + shortDate(seen) + ": its usage check fails (the engine reports \u201c"
      + failure.replace(new RegExp("^" + name + "\\s+", "i"), "")
      + "\u201d). It comes back when the engine reads " + name + " again."
  if ((old || state === "ok" || state === "stale") && freeLevel(entry) && entryMetrics(entry).length === 0)
    return "This " + name + " login is on the free level and its usage answer is empty, so there is no plan to show"
      + (old ? " (last reading " + shortDate(seen) + ")" : "") + ". A login with a paid plan brings it back."
  if (old)
    return name + " has had no reading since " + shortDate(seen) + ". "
      + (state === "auth" ? "A new sign-in brings it back." : "It comes back by itself with its next good reading.")
  if ((state === "ok" || state === "stale") && empty)
    return name + " reports no plan or balance. It comes back once it has one."
  return ""
}

function dormantProviders(entries, providersSetting, lastSeen) {
  if (String(providersSetting || "").trim() !== "") return []
  var list = Array.isArray(entries) ? entries : []
  var cache = lastSeen && typeof lastSeen === "object" ? lastSeen : {}
  var newest = newestReading(list)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var why = dormantReason(list[i], cache[list[i].id], newest)
    if (why !== "") out.push({ id: list[i].id, name: providerName(list[i]), reason: why })
  }
  return out
}

function stripCells(entries, providersSetting, lastSeen, misses) {
  var list = stripEntries(entries, providersSetting)
  var cache = lastSeen && typeof lastSeen === "object" ? lastSeen : {}
  var missed = misses && typeof misses === "object" ? misses : {}
  var explicit = String(providersSetting || "").trim() !== ""
  var newest = newestReading(list)
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (!explicit && dormantReason(list[i], cache[list[i].id], newest) !== "") continue
    out.push(stripCell(list[i], cache[list[i].id], missed[list[i].id]))
  }
  return out
}

// Consecutive-miss counters after a report: fresh resets to 0, anything else
// counts up. A provider with no history that is not fresh starts at 2 — the
// grace is for "fresh a moment ago, missed once", never for "unknown". Kept
// out of the entries so a tick never rebuilds them.
function countMisses(previous, entries) {
  var next = {}
  var before = previous && typeof previous === "object" ? previous : {}
  var list = Array.isArray(entries) ? entries : []
  for (var i = 0; i < list.length; i++) {
    var id = list[i].id
    if (cellState(list[i]) === "ok") next[id] = 0
    else next[id] = Object.prototype.hasOwnProperty.call(before, id) ? (Number(before[id]) || 0) + 1 : 2
  }
  return next
}

// ----------------------------------------------------- native Cursor reading
//
// omarchy-ai-cursor-usage reads Cursor's dashboard with the standard library,
// because Cursor's edge refuses the engine's HTTP client while accepting the
// same request from anything else (2026-09-07). Its output is one engine-shaped
// entry, or a refusal, or a login problem — parsed through the same boundary
// as the engine's report.
function parseNative(raw) {
  var empty = { ok: false, entry: null, refused: null, auth: null, note: "" }
  try {
    var parsed = JSON.parse(String(raw || ""))
    if (!parsed || typeof parsed !== "object") return empty
    var entry = parsed.entry && typeof parsed.entry === "object" ? normalizeEntry(parsed.entry) : null
    if (entry && baseProvider(entry.id) !== "cursor") entry = null
    if (entry) entry.source = "native"
    return {
      ok: true,
      entry: entry,
      refused: parsed.refused && typeof parsed.refused === "object" ? { status: Number(parsed.refused.status) || 0 } : null,
      auth: parsed.auth && typeof parsed.auth === "object" ? { status: Number(parsed.auth.status) || 0 } : null,
      note: cleanText(parsed.note, 300)
    }
  } catch (error) {
    return empty
  }
}

// The native reading outranks the engine's whenever it is fresh. When it is a
// refusal or a login problem, that fact is attached to the engine's own entry
// (which is by then cached or failed) so the panel can word it. Engine order
// is kept; a machine where the engine has no Cursor at all still gets a cell.
function mergeNative(entries, native) {
  var list = Array.isArray(entries) ? entries.slice() : []
  if (!native || !native.ok) return list
  var index = -1
  for (var i = 0; i < list.length; i++) if (baseProvider(list[i].id) === "cursor") { index = i; break }
  if (native.entry) {
    if (index >= 0) list[index] = native.entry
    else list.push(native.entry)
    return list
  }
  if (index < 0) return list
  var entry = Object.assign({}, list[index])
  if (cellState(entry) !== "ok") {
    // The reader asked /api/auth/me. Its answer outranks whatever status row
    // the engine demoted: a working login is a refusal even if the engine
    // saw a 401, and a rejected login is a login problem even if the engine
    // saw a 403.
    if (native.refused) {
      if (!entry.refusal) entry.refusal = { status: native.refused.status, text: native.note }
      entry.auth_note = ""
    } else if (native.auth) {
      entry.auth_note = native.note || (providerName(entry) + " needs a new sign-in")
      entry.refusal = null
    }
  }
  list[index] = entry
  return list
}

// ------------------------------------------------------- local API spend
//
// Second data source, read from opencode's own database by the collector
// script. The panel never trusts it to be there: a machine without opencode,
// or with a database the collector could not open, gets an empty list and a
// one-line note instead of a broken section.

function formatMoney(amount) {
  var value = Number(amount)
  if (!isFinite(value) || value <= 0) return "$0"
  if (value < 0.01) return "<$0.01"
  if (value < 100) return "$" + value.toFixed(2)
  return "$" + Math.round(value)
}

function formatTokens(count) {
  var value = Number(count)
  if (!isFinite(value) || value <= 0) return "0"
  if (value >= 1e9) return (value / 1e9).toFixed(1) + "B"
  if (value >= 1e6) return (value / 1e6).toFixed(1) + "M"
  if (value >= 1e3) return Math.round(value / 1e3) + "K"
  return String(Math.round(value))
}

function spendWindow(row, key) {
  var window = row && row[key]
  if (!window || typeof window !== "object") return { sessions: 0, cost: 0, tokens: 0 }
  return {
    sessions: Math.max(0, Math.round(Number(window.sessions) || 0)),
    cost: Math.max(0, Number(window.cost) || 0),
    tokens: Math.max(0, Math.round(Number(window.tokens) || 0)),
    replies: Math.max(0, Math.round(Number(window.replies) || 0)),
    unpriced_replies: Math.max(0, Math.round(Number(window.unpriced_replies) || 0)),
    missing_usage_replies: Math.max(0, Math.round(Number(window.missing_usage_replies) || 0))
  }
}

function parseSpend(raw) {
  var failed = { ok: false, note: "Local API spend is unavailable.", rows: [], total: 0 }
  try {
    var parsed = JSON.parse(String(raw || ""))
    if (!parsed || !Array.isArray(parsed.providers)) return failed
    var rows = []
    var total = 0
    for (var i = 0; i < parsed.providers.length && i < 32; i++) {
      var provider = parsed.providers[i]
      if (!provider || typeof provider !== "object") continue
      var id = cleanText(provider.id, 80).trim()
      if (id === "") continue
      var d30 = spendWindow(provider, "d30")
      rows.push({
        id: id,
        name: autoTextSafe(cleanText(provider.name, 120) || id),
        mark: markId(id),
        today: spendWindow(provider, "today"),
        d7: spendWindow(provider, "d7"),
        d30: d30,
        d90: spendWindow(provider, "d90"),
        apps: Array.isArray(provider.apps) ? provider.apps.map(function(app) { return {id: cleanText(app.id,80), name:cleanText(app.name,80), d30:spendWindow(app,"d30")} }) : []
      })
      total += d30.cost
    }
    rows.sort(function(a, b) { return b.d30.cost - a.d30.cost })
    return {
      ok: true,
      note: cleanText(parsed.note, 500),
      generatedAt: Number(parsed.generated_at) || 0,
      coverage: Array.isArray(parsed.coverage) ? parsed.coverage : [],
      rows: rows,
      total: total
    }
  } catch (error) {
    return failed
  }
}

// Meaning and layout for the native account/activity views.
function creditBalance(entry) {
  if (!entry || ["deepseek", "openrouter"].indexOf(baseProvider(entry.id)) < 0) return ""
  var value=headline(entry).text
  return /^[\$¥]/.test(value) ? value : ""
}

function presentationSections(entry) {
  if (!entry) return []
  var rows = entry.sections.filter(function(r) { return r.type !== "spacer" })
  var vendor = baseProvider(entry.id)
  if (vendor === "deepseek") return [] // the balance summary is complete; omit duplicate API/breakdown boilerplate
  if (vendor === "openrouter")
    return rows.filter(function(r) { return r.label !== "Credit balance" && r.label !== "Tier" })
  if (vendor === "antigravity") {
    var weekly = [], session = [], dest = session
    for (var i=0; i<rows.length; i++) {
      var row=rows[i]
      if (row.type === "text" && row.value === "" && row.label === "Weekly") { dest=weekly; dest.push({type:"text",label:"Weekly allowance",value:""}); continue }
      if (row.type === "text" && row.value === "" && row.label === "Session") { dest=session; dest.push({type:"text",label:"Five-hour allowance",value:""}); continue }
      dest.push(row)
    }
    return weekly.concat(session)
  }
  return rows
}

function percentUsed(row) {
  if (!row || row.percent === null) return "Not reported"
  if (/^[\d.,]+%$/.test(row.value || "")) return row.value + " used"
  return row.value || row.percent + "% used"
}

function activityFor(spend, entryId) {
  var id=baseProvider(entryId), rows=spend && spend.rows ? spend.rows : []
  if (id === "supergrok") id = "xai"
  for (var i=0;i<rows.length;i++) if (baseProvider(rows[i].id)===id) return rows[i]
  return null
}

function recordedCost(window) {
  if (!window || !window.replies) return "Not recorded"
  if (window.unpriced_replies >= window.replies) return "Not recorded"
  return formatMoney(window.cost)
}

function activityTotals(spend) {
  var out={replies:0,cost:0,tokens:0,unpriced_replies:0,missing_usage_replies:0}
  var rows=spend && spend.rows ? spend.rows : []
  for(var i=0;i<rows.length;i++) for(var key in out) out[key] += Number(rows[i].d30[key]) || 0
  return out
}


// ---------------------------------------------------------------- 1.14 look
//
// How one cell is drawn, decided here so every state is a rule a test can hold
// rather than a picture to squint at. gauge is the column's form:
//   fill    the used part of the plan, filled from the base
//   hollow  the last known level, outlined only: the provider refused the
//           check, so the level is remembered, not read
//   signin  an empty column ringed in the alarm ink, with the words "sign in"
//   sleep   an empty column and the word "off": asleep by design, not broken
//   empty   an empty column and a dash: no reading this time
//   none    a prepaid balance: money has no plan to fill
// figure is the text beside it; bold and urgent follow the one ladder
// (text ink, then bold from 70 or under $5, then the alarm from 90 or under $1).
function cellLook(cell) {
  if (!cell) return { gauge: "empty", figure: "", bold: false, urgent: false, stale: false }
  var critical = cell.severity === "critical"
  var warn = cell.severity === "warn" || critical
  if (cell.state === "auth") return { gauge: "signin", figure: "sign in", bold: true, urgent: false, stale: false }
  if (cell.state === "offline") return { gauge: "sleep", figure: "off", bold: false, urgent: false, stale: false }
  if (cell.noPlan) return { gauge: "empty", figure: "no plan", bold: false, urgent: false, stale: false }
  if (cell.state === "error") return { gauge: "empty", figure: "\u2013", bold: false, urgent: false, stale: false }
  if (cell.isMoney) return { gauge: "none", figure: cell.text, bold: warn, urgent: critical, stale: false }
  if (cell.percent === null || cell.percent === undefined) {
    if (cell.text !== "") return { gauge: "none", figure: cell.text, bold: false, urgent: false, stale: cell.state === "stale" }
    return { gauge: "empty", figure: "\u2026", bold: false, urgent: false, stale: false }
  }
  // A remembered number keeps its ink and its alarm, at normal weight, behind
  // a "~": approximately this, as of the last good reading.
  if (cell.state === "stale")
    return { gauge: cell.refused ? "hollow" : "fill", figure: "~" + cell.text, bold: false, urgent: critical, stale: true }
  return { gauge: "fill", figure: cell.text, bold: warn, urgent: critical, stale: false }
}

// Column geometry, in logical pixels. Any reading above zero is at least
// MIN_FILL tall (a short flat-topped bar, never a round blob); zero is an
// empty track.
var MIN_FILL = 4

function fillHeight(percent, height) {
  var p = Number(percent)
  if (!isFinite(p) || p <= 0) return 0
  return Math.min(height, Math.max(MIN_FILL, Math.round(height * Math.min(100, p) / 100)))
}

// Top of the pace cut: centred on "this much of the window has gone",
// measured from the base, kept inside the column.
function paceOffset(pace, height, cut) {
  var p = Math.max(0, Math.min(100, Number(pace) || 0))
  return Math.max(0, Math.min(height - cut, Math.round(height * (1 - p / 100) - cut / 2)))
}

// ------------------------------------------------------------- 1.14 inks
//
// Grafted from the capsule study: every ink is derived from the bar's own
// tokens (surface = bar background, ink = bar text, alarm = urgent, quiet =
// muted) with the contrast floors written down.
//
// The column is a vessel: a dark well (the bar's surface with about 13 % of
// its ink, a step off the bar and no more) inside a 1 px rim of the bar's ink
// let down just far enough to stand 3:1 on the bar. The 3:1 floor is met by
// the column's edge, not by its body, so an empty or nearly empty column reads
// as an empty vessel and a calm day is a row of outlines with small bright
// fills, never a row of grey slabs (fix round, 2026-11-20).
//   figures       4.5:1 against the bar
//   rim           3:1 against the bar
//   fill          3:1 against the well (the fill runs out to the rim)
//   urgent fill   3:1 against the well and against the bar
//   pace          a cut in the bar's colour inside the fill; inside the well
//                 a quiet line, the faintest ink that reads 4.5:1 on the well,
//                 so the mark is a graduation on the vessel and the fill is
//                 the only bright thing in it (in the bar's full ink the line
//                 read as a second level: "Cursor 10" looked 40 % full)
// The strip's alarm ink: the theme's urgent colour repaired when it is fainter
// than the text (legibleAlarmRgb), given a red hue when the theme's urgent is
// all but the text colour (so critical never looks like warning), then stepped
// toward the ink until it reads at 4.5:1 on the bar's surface (a light theme's
// red lands just under).
var ALARM_RED = [0.86, 0.2, 0.16]
var WELL_MIX = 0.13

function barAlarmRgb(alarm, ink, surface) {
  var out = legibleAlarmRgb(alarm, ink, null)
  if (contrastRgb(out, ink) < 1.5) out = legibleAlarmRgb(ALARM_RED, ink, null)
  if (!surface) return out
  var base = out.slice(0, 3)
  for (var step = 1; step <= 10 && contrastRgb(out, surface) < 4.5; step++)
    out = mixRgb(base, ink, step * 0.08)
  return out
}

function contrastRgb(a, b) {
  function linear(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) }
  function luminance(c) { return 0.2126 * linear(c[0]) + 0.7152 * linear(c[1]) + 0.0722 * linear(c[2]) }
  var la = luminance(a), lb = luminance(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

function mixRgb(a, b, t) {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
}

function stripInks(surface, ink, alarm, quiet) {
  function solve(from, to, ok) {
    for (var step = from; from <= to ? step <= to : step >= to; step += from <= to ? 1 : -1) {
      var c = mixRgb(surface, ink, step / 100)
      if (ok(c)) return c
    }
    return null
  }
  // The well: a step off the bar; let back toward the bar only if the fill
  // would not stand 3:1 on it (a theme whose ink is barely off its surface).
  var well = solve(Math.round(WELL_MIX * 100), 0, function(c) { return contrastRgb(ink, c) >= 3 })
    || surface.slice(0, 3)
  // The rim: the faintest ink that stands 3:1 on the bar.
  var rim = solve(5, 100, function(c) { return contrastRgb(c, surface) >= 3 }) || ink.slice(0, 3)
  // The alarm's well, only if the ordinary one would not hold the alarm fill
  // at 3:1 (it shows on at most a tenth of a column, since the fill starts at 90).
  var urgentWell = contrastRgb(alarm, well) >= 3 ? well
    : (solve(Math.round(WELL_MIX * 100), 0, function(c) { return contrastRgb(alarm, c) >= 3 }) || surface.slice(0, 3))
  // The pace line inside a well: the faintest ink that reads 4.5:1 on the well
  // (and on the alarm's well); the bar's ink itself where nothing fainter does.
  var paceLine = ink.slice(0, 3)
  for (var p = 1; p <= 100; p++) {
    var candidate = mixRgb(well, ink, p / 100)
    if (contrastRgb(candidate, well) >= 4.5 && contrastRgb(candidate, urgentWell) >= 4.5) { paceLine = candidate; break }
  }
  // The word "off" uses the muted ink only at 4.5:1, else the text ink.
  var quietText = quiet && contrastRgb(quiet, surface) >= 4.5 ? quiet.slice(0, 3) : ink.slice(0, 3)
  return {
    well: well, rim: rim, urgentWell: urgentWell, quietText: quietText, paceLine: paceLine,
    // The panel's older names for the same inks.
    track: well, urgentTrack: urgentWell,
    contrast: {
      figure: contrastRgb(ink, surface),
      urgentFigure: contrastRgb(alarm, surface),
      quietFigure: contrastRgb(quietText, surface),
      wellOnBar: contrastRgb(well, surface),
      rimOnBar: contrastRgb(rim, surface),
      urgentRimOnBar: contrastRgb(alarm, surface),
      fillOnWell: contrastRgb(ink, well),
      urgentOnWell: contrastRgb(alarm, urgentWell),
      urgentOnBar: contrastRgb(alarm, surface),
      paceCutInFill: contrastRgb(surface, ink),
      paceLineInWell: contrastRgb(paceLine, well),
      alarmOnInk: contrastRgb(alarm, ink)
    }
  }
}

// ------------------------------------------------------------- 1.15 helpers
// Warm amber warning tier (70–89% used, or balance under $5), distinct from
// calm text ink and from critical coral-red, solved for >= 4.5:1 on the bar.
var WARN_AMBER_DARK = [0.95, 0.72, 0.24]
var WARN_AMBER_LIGHT = [0.68, 0.40, 0.02]

function barWarnRgb(ink, surface) {
  function linear(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) }
  function lum(c) { return 0.2126 * linear(c[0]) + 0.7152 * linear(c[1]) + 0.0722 * linear(c[2]) }
  var isLight = surface ? lum(surface) > 0.45 : (ink ? lum(ink) < 0.45 : false)
  var base = (isLight ? WARN_AMBER_LIGHT : WARN_AMBER_DARK).slice(0, 3)
  if (!surface) return base
  var out = base.slice(0, 3)
  var target = ink || (isLight ? [0.08, 0.08, 0.08] : [0.95, 0.95, 0.92])
  for (var step = 1; step <= 12 && contrastRgb(out, surface) < 4.5; step++)
    out = mixRgb(base, target, step * 0.07)
  return out
}

function percentRemaining(row) {
  if (!row || row.percent === null || row.percent === undefined) return ""
  var p = Number(row.percent)
  if (!isFinite(p)) return ""
  var left = Math.max(0, Math.round(100 - Math.min(100, Math.max(0, p))))
  return left + "% left"
}

function friendlyDormantText(reason) {
  var text = String(reason || "")
  if (text === "") return ""
  text = text.replace(/\s*\(HTTP 401\)/g, "")
  text = text.replace(/its usage check fails \(the engine reports [“"]API schema drift[”"]\)/i,
    "the provider changed its status format and the reader needs an update")
  text = text.replace(/\(the engine reports [“"]([^”"]+)[”"]\)/i, "($1)")
  text = text.replace(/has refused the saved API key since ([^.]+)\.\s*A new API key brings it back\./i,
    "rejected your saved API key (since $1) — open Settings to enter a fresh key.")
  text = text.replace(/has refused the saved API key since ([^.]+)\./i,
    "rejected your saved API key (since $1) — open Settings to enter a fresh key.")
  return text
}
