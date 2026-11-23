.pragma library

// Formatting, sorting, and semantic styling helpers for the Vitals panel.
// Pure functions only.

function pad2(n) { return (n < 10 ? "0" : "") + n }

// 1234567 -> "1.2 MiB". Binary units, one decimal under 100, none above.
function bytes(n, unitSuffix) {
  n = Number(n)
  if (!isFinite(n) || n < 0) return "—"
  var units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
  var i = 0
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  var s = i === 0 ? String(Math.round(n)) : (n < 10 ? n.toFixed(1) : (n < 100 ? n.toFixed(1) : String(Math.round(n))))
  return s + " " + units[i] + (unitSuffix || "")
}

// Compact form for tight table cells: "1.0G", "689M", "12K".
function bytesShort(n) {
  n = Number(n)
  if (!isFinite(n) || n < 0) return "—"
  var units = ["B", "K", "M", "G", "T"]
  var i = 0
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  if (i === 0) return String(Math.round(n)) + units[i]
  return (n < 10 ? n.toFixed(1) : String(Math.round(n))) + units[i]
}

function rate(bps) {
  if (bps === null || bps === undefined) return "—"
  return bytes(bps, "/s")
}

function percent(v, decimals) {
  if (v === null || v === undefined || !isFinite(v)) return "—"
  return (decimals ? Number(v).toFixed(decimals) : String(Math.round(v))) + "%"
}

function temp(c) {
  if (c === null || c === undefined || !isFinite(c)) return "—"
  return Math.round(c) + "°C"
}

function mhz(v) {
  if (v === null || v === undefined || !isFinite(v)) return "—"
  if (v <= 0) return "Idle"
  return v >= 1000 ? (v / 1000).toFixed(2) + " GHz" : Math.round(v) + " MHz"
}

function rpm(v) {
  if (v === null || v === undefined || !isFinite(v)) return "—"
  if (v <= 0) return "Idle"
  return count(Math.round(v)) + " rpm"
}

function watts(w) {
  if (w === null || w === undefined || !isFinite(w)) return "—"
  return (w < 10 ? w.toFixed(1) : (w < 100 ? w.toFixed(1) : String(Math.round(w)))) + " W"
}

function uptime(seconds) {
  seconds = Math.max(0, Math.floor(Number(seconds) || 0))
  var d = Math.floor(seconds / 86400)
  var h = Math.floor((seconds % 86400) / 3600)
  var m = Math.floor((seconds % 3600) / 60)
  if (d > 0) return d + "d " + h + "h"
  if (h > 0) return h + "h " + pad2(m) + "m"
  return m + "m"
}

function loadAvg(load) {
  if (!load || load.length < 3) return "—"
  return load.map(function(x) { return Number(x).toFixed(2) }).join("  ")
}

function count(n) {
  n = Number(n) || 0
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

// A friendly label for a mount point: "/" -> "root", "/home" -> "home".
function mountLabel(mount) {
  if (mount === "/") return "root"
  var parts = String(mount).split("/").filter(function(p) { return p !== "" })
  return parts.length ? parts[parts.length - 1] : mount
}

function fsLabel(disk) {
  var s = disk.fstype || ""
  var src = String(disk.source || "")
  if (src.indexOf("/dev/mapper/") === 0) s += " · encrypted"
  else if (src.indexOf("/dev/") === 0) s += " · " + src.substring(5)
  else if (src) s += " · " + src
  return s
}

// Sort comparator for the process table. Numeric columns default to
// descending (biggest first); text columns ascending.
function sortProcesses(list, key, reverse) {
  var out = list.slice()
  var numeric = key === "cpu" || key === "mem" || key === "pid" || key === "threads"
  out.sort(function(a, b) {
    var av = a[key], bv = b[key]
    var c
    if (numeric) c = (Number(bv) || 0) - (Number(av) || 0)
    else {
      av = String(av || "").toLowerCase(); bv = String(bv || "").toLowerCase()
      c = av < bv ? -1 : (av > bv ? 1 : 0)
    }
    if (c === 0) c = (a.pid || 0) - (b.pid || 0)
    return reverse ? -c : c
  })
  return out
}

function filterProcesses(list, query) {
  query = String(query || "").trim().toLowerCase()
  if (!query) return list
  return list.filter(function(p) {
    return String(p.name || "").toLowerCase().indexOf(query) >= 0
      || String(p.cmd || "").toLowerCase().indexOf(query) >= 0
      || String(p.user || "").toLowerCase().indexOf(query) >= 0
      || String(p.pid) === query
  })
}

// Push onto a fixed-length history buffer (returns a new array so bindings fire).
function pushHistory(history, value, max) {
  var next = (history || []).slice()
  next.push(value === null || value === undefined ? 0 : Number(value))
  while (next.length > max) next.shift()
  return next
}

function maxOf(arr, floor) {
  var m = floor || 0
  for (var i = 0; i < (arr || []).length; i++) if (arr[i] > m) m = arr[i]
  return m
}

function avgOf(arr) {
  if (!arr || arr.length === 0) return 0
  var sum = 0
  for (var i = 0; i < arr.length; i++) sum += Number(arr[i]) || 0
  return sum / arr.length
}

function gpuVendorLabel(v) {
  if (v === "intel") return "Intel"
  if (v === "amd") return "AMD"
  if (v === "nvidia") return "NVIDIA"
  return ""
}

function gpuKey(gpu) { return String(gpu.id || (gpu.vendor + ":" + gpu.name)) }

// Short display names preserve the real detected model rather than guessing it.
function gpuDisplayName(gpu) {
  var name = String(gpu && gpu.name || "Graphics device")
  if (gpu && gpu.vendor === "nvidia") {
    var rtx = name.match(/(?:RTX|GTX)\s+[\w ]+/)
    if (rtx) return "NVIDIA " + rtx[0].replace(/\s+Laptop GPU.*$/, "").replace(/\s+GPU.*$/, "").trim()
  }
  if (gpu && gpu.vendor === "intel") {
    var bracket = name.match(/\[([^\]]+)\]/)
    if (bracket) return "Intel " + bracket[1].replace(/ Graphics$/, "")
  }
  return name
}

function chartClock(seconds) {
  if (!isFinite(seconds) || seconds <= 0) return ""
  var d = new Date(seconds * 1000)
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds())
}

function chartDuration(times) {
  if (!times || times.length < 2) return "Collecting history…"
  var elapsed = Math.max(0, Math.round(times[times.length - 1] - times[0]))
  return elapsed < 60 ? elapsed + "s window" : Math.floor(elapsed / 60) + "m " + pad2(elapsed % 60) + "s window"
}

function gpuTimeDomain(times, devices) {
  var start = Infinity, end = -Infinity
  for (var i = 0; i < devices.length; i++) {
    var row = times[gpuKey(devices[i])] || []
    for (var j = 0; j < row.length; j++) {
      var t = Number(row[j])
      if (isFinite(t) && t > 0) { start = Math.min(start, t); end = Math.max(end, t) }
    }
  }
  return isFinite(start) && isFinite(end) ? { start: start, end: end } : { start: 0, end: 0 }
}

function timeFraction(time, start, end) {
  return end > start ? Math.max(0, Math.min(1, (time - start) / (end - start))) : 0
}

// ------------------------------------------------ 3-tier semantic color system
// Harmonized with Omarchy's frosted-glass language and ai-usage v1.15:
//   calm     -> theme foreground / crisp accent
//   warn     -> warm amber (WCAG >= 4.5:1 on active surface)
//   critical -> urgent coral-red (WCAG >= 4.5:1 on active surface)

var WARN_AMBER_DARK = [0.95, 0.72, 0.24]
var WARN_AMBER_LIGHT = [0.68, 0.40, 0.02]
var CRIT_CORAL_DARK = [0.95, 0.42, 0.36]
var CRIT_CORAL_LIGHT = [0.75, 0.16, 0.14]

function _linear(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) }
function _lum(c) { return 0.2126 * _linear(c[0]) + 0.7152 * _linear(c[1]) + 0.0722 * _linear(c[2]) }
function _contrast(a, b) {
  var la = _lum(a), lb = _lum(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}
function _mix(a, b, t) {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
}

function isLightSurface(surface, ink) {
  if (surface) return _lum(surface) > 0.45
  if (ink) return _lum(ink) < 0.45
  return false
}

function solveContrastRgb(base, surface, targetInk, minRatio) {
  var out = base.slice(0, 3)
  if (!surface) return out
  var goal = minRatio || 4.5
  var target = targetInk || (isLightSurface(surface, null) ? [0.08, 0.08, 0.08] : [0.96, 0.96, 0.93])
  for (var step = 1; step <= 14 && _contrast(out, surface) < goal; step++)
    out = _mix(base, target, step * 0.065)
  return out
}

function warnRgb(ink, surface) {
  var light = isLightSurface(surface, ink)
  return solveContrastRgb(light ? WARN_AMBER_LIGHT : WARN_AMBER_DARK, surface, ink, 4.5)
}

function criticalRgb(urgent, ink, surface) {
  var light = isLightSurface(surface, ink)
  var base = urgent && urgent.length >= 3 ? urgent.slice(0, 3) : (light ? CRIT_CORAL_LIGHT : CRIT_CORAL_DARK)
  // Blend slightly toward crisp coral if the theme's urgent is muted brown/grey.
  var sat = Math.max(base[0], base[1], base[2]) - Math.min(base[0], base[1], base[2])
  if (sat < 0.22) base = light ? CRIT_CORAL_LIGHT : CRIT_CORAL_DARK
  return solveContrastRgb(base, surface, ink, 4.6)
}

function chartAccentRgb(accent, ink, surface) {
  var base = accent && accent.length >= 3 ? accent.slice(0, 3) : [0.38, 0.56, 0.96]
  return solveContrastRgb(base, surface, ink, 5.2)
}

function secondaryChartRgb(accent, ink, surface) {
  var light = isLightSurface(surface, ink)
  var base = light ? [0.22, 0.48, 0.56] : [0.54, 0.80, 0.88]
  if (ink && ink.length >= 3) base = _mix(base, ink, 0.24)
  return solveContrastRgb(base, surface, ink, 5.0)
}

// Severity tiers: "calm" | "warn" | "critical"
function loadTier(pct) {
  if (pct === null || pct === undefined || !isFinite(pct)) return "calm"
  if (pct >= 90) return "critical"
  if (pct >= 70) return "warn"
  return "calm"
}

function tempTier(c, critLimit) {
  if (c === null || c === undefined || !isFinite(c)) return "calm"
  var crit = critLimit > 0 ? Math.min(92, critLimit - 5) : 85
  var warn = Math.min(72, crit - 13)
  if (c >= crit) return "critical"
  if (c >= warn) return "warn"
  return "calm"
}

function memTier(ratio) {
  if (ratio === null || ratio === undefined || !isFinite(ratio)) return "calm"
  if (ratio >= 0.90) return "critical"
  if (ratio >= 0.78) return "warn"
  return "calm"
}

function gpuStatus(device) {
  if (!device || device.data_unavailable) return { label: "SLEEPING", tier: "muted" }
  var tTier = tempTier(device.temp, 0)
  var lTier = loadTier(device.busy)
  if (tTier === "critical") return { label: "HOT", tier: "critical" }
  if (lTier === "critical") return { label: "PEAK", tier: "critical" }
  if (tTier === "warn") return { label: "WARM", tier: "warn" }
  if (lTier === "warn") return { label: "BUSY", tier: "warn" }
  if (device.busy !== null && device.busy !== undefined && device.busy >= 2) return { label: "ACTIVE", tier: "accent" }
  return { label: "IDLE", tier: "calm" }
}
