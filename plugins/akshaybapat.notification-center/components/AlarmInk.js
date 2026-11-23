// The bar's one alarm colour, shared with the AI usage strip.
//
// This function is a verbatim copy of legibleAlarmRgb in
// akshaybapat.ai-usage/ui/v1_15_2/Model.js, where its rule is explained in
// full: on light ink the theme's alarm red is lifted to a luminance floor of
// min(ink luminance, 0.3), which keeps it a saturated coral that reads on the
// bar, instead of the dull palette red or a pastel pink. Omarchy 4.5 gives
// every add-on its own import scope, so the bell cannot import the strip's
// model; tests/test.sh fails if the two copies ever differ.
//
// Channels 0..1; [r, g, b]. surface may be null.
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
