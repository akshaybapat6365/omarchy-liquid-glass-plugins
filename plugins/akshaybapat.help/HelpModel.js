.pragma library

var TAB_DEFS = [
  { id: "shortcuts", number: "1", label: "Shortcuts" },
  { id: "gestures",  number: "2", label: "Gestures" },
  { id: "tools",     number: "3", label: "Custom Tools" },
  { id: "guide",     number: "4", label: "Quick Guide" }
];

function tabIndexForName(name) {
  var key = String(name || "").toLowerCase().trim();
  if (key === "shortcuts" || key === "keys" || key === "keybindings" || key === "1") return 0;
  if (key === "gestures" || key === "trackpad" || key === "touchpad" || key === "2") return 1;
  if (key === "tools" || key === "custom" || key === "features" || key === "3") return 2;
  if (key === "guide" || key === "quick-guide" || key === "quickguide" || key === "help" || key === "4") return 3;
  return -1;
}

function tokenizeQuery(query) {
  var clean = String(query || "").toLowerCase().replace(/^\s+|\s+$/g, "");
  if (!clean) return [];
  return clean.split(/\s+/).filter(function(t) { return t.length > 0; });
}

function scoreTokenInText(text, token) {
  if (!text || !token) return 0;
  var idx = text.indexOf(token);
  if (idx === 0) return 120;
  if (idx > 0) {
    var prev = text.charAt(idx - 1);
    if (prev === " " || prev === "+" || prev === "/" || prev === "-" || prev === "·" || prev === "(") {
      return 92 - Math.min(20, idx * 0.4);
    }
    return 68 - Math.min(24, idx * 0.3);
  }

  // Ordered subsequence fuzzy match
  var ti = 0;
  var score = 0;
  var consecutive = 0;
  for (var i = 0; i < text.length && ti < token.length; i++) {
    if (text.charAt(i) === token.charAt(ti)) {
      consecutive += 1;
      score += 4 + consecutive * 3;
      if (i === 0 || text.charAt(i - 1) === " ") score += 5;
      ti += 1;
    } else {
      consecutive = 0;
    }
  }
  return ti === token.length ? Math.min(54, score) : 0;
}

function scoreItem(item, tokens) {
  if (!tokens || tokens.length === 0) return 1;
  var title = String(item.title || "").toLowerCase();
  var keysText = String(item.keysText || "").toLowerCase();
  var blob = String(item.searchBlob || title).toLowerCase();
  var total = 0;

  for (var i = 0; i < tokens.length; i++) {
    var tok = tokens[i];
    var sTitle = scoreTokenInText(title, tok);
    var sKeys = keysText ? scoreTokenInText(keysText, tok) : 0;
    var sBlob = scoreTokenInText(blob, tok);
    var best = Math.max(sTitle * 2.0, sKeys * 1.6, sBlob);
    if (best <= 0) return 0;
    total += best;
  }
  return total;
}

function toList(val) {
  if (!val) return [];
  if (Array.isArray(val)) return val;
  if (typeof val.length === "number") {
    var out = [];
    for (var i = 0; i < val.length; i++) out.push(val[i]);
    return out;
  }
  return [];
}

function filterShortcuts(shortcuts, categoryId, query) {
  var list = toList(shortcuts);
  var cat = String(categoryId || "all");
  var tokens = tokenizeQuery(query);
  var out = [];

  for (var i = 0; i < list.length; i++) {
    var item = list[i];
    if (cat !== "all" && item.category !== cat) continue;
    var sc = scoreItem(item, tokens);
    if (sc > 0) {
      out.push({ item: item, score: sc, order: i });
    }
  }

  if (tokens.length > 0) {
    out.sort(function(a, b) {
      if (b.score !== a.score) return b.score - a.score;
      return a.order - b.order;
    });
  }

  var result = [];
  for (var j = 0; j < out.length; j++) result.push(out[j].item);
  return result;
}

function filterItems(items, query) {
  var list = toList(items);
  var tokens = tokenizeQuery(query);
  if (tokens.length === 0) return list;

  var out = [];
  for (var i = 0; i < list.length; i++) {
    var sc = scoreItem(list[i], tokens);
    if (sc > 0) out.push({ item: list[i], score: sc, order: i });
  }
  out.sort(function(a, b) {
    if (b.score !== a.score) return b.score - a.score;
    return a.order - b.order;
  });

  var result = [];
  for (var j = 0; j < out.length; j++) result.push(out[j].item);
  return result;
}

function categoryMatchCounts(shortcuts, query) {
  var list = toList(shortcuts);
  var tokens = tokenizeQuery(query);
  var counts = { all: 0, apps: 0, windows: 0, workspaces: 0, ai: 0, capture: 0, system: 0 };

  for (var i = 0; i < list.length; i++) {
    var item = list[i];
    if (tokens.length > 0 && scoreItem(item, tokens) <= 0) continue;
    counts.all += 1;
    var c = item.category || "system";
    counts[c] = (counts[c] || 0) + 1;
  }
  return counts;
}

function tabMatchCounts(data, query) {
  if (!data) return [0, 0, 0, 0];
  return [
    filterShortcuts(data.shortcuts, "all", query).length,
    filterItems(data.gestures, query).length,
    filterItems(data.tools, query).length,
    filterItems(data.guides, query).length
  ];
}

function formatSubtitle(counts) {
  if (!counts) return "Loading live system shortcuts…";
  return String(counts.shortcuts || 0) + " Shortcuts · "
    + String(counts.gestures || 0) + " Gestures · "
    + String(counts.tools || 0) + " Custom Tools";
}

function isModifierCap(label) {
  var k = String(label || "").toLowerCase();
  return k === "super" || k === "ctrl" || k === "alt" || k === "shift" || k === "right alt";
}
