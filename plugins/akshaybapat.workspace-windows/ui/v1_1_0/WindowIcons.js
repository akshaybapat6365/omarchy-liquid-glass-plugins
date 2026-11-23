// Shared identity lookup for the workspace strip and minimized-window shelf.
// The catalog is an explicit input: late desktop-entry loading must invalidate
// callers' icon bindings. Window titles are never application identities.
function ids(toplevel) {
  var ipc = toplevel && toplevel.lastIpcObject || {}
  var wayland = toplevel && toplevel.wayland || {}
  return [wayland.appId, ipc.class, ipc.initialClass].map(function(value) {
    return String(value || "").trim().replace(/\.desktop$/, "")
  }).filter(function(value, index, all) { return value && all.indexOf(value) === index })
}

function browserIdentity(value) {
  var match = /^(?:chrome|chromium|brave)-(.+)-(?:Default|Profile_[0-9]+)$/.exec(value)
  return match ? match[1] : ""
}

function webIdentities(entry) {
  var command = entry.command || []
  var launchWebapp = command.some(function(arg) {
    return String(arg).split("/").pop() === "omarchy-launch-webapp"
  })
  var identities = []
  for (var i = 0; i < command.length; i++) {
    var arg = String(command[i])
    if (arg.indexOf("--app-id=") === 0) identities.push(arg.slice(9))
    var url = arg.indexOf("--app=") === 0 ? arg.slice(6) : (launchWebapp ? arg : "")
    var match = /^https?:\/\/([^/?#]+)([^?#]*)/.exec(url)
    if (match) identities.push(match[1].toLowerCase() + "_" + (match[2] || "/").replace(/\//g, "_"))
  }
  return identities
}

function lookup(toplevel, entries, heuristic) {
  var candidates = ids(toplevel)
  var catalog = entries || []
  var i, j, candidate, entry
  // Exact IDs take precedence over case-insensitive matching: ChatGPT (web)
  // and chatgpt (native) can legitimately coexist as separate launchers.
  for (i = 0; i < candidates.length; i++) {
    candidate = candidates[i]
    for (j = 0; j < catalog.length; j++) {
      entry = catalog[j]
      if (entry.id === candidate) return entry
    }
  }
  for (i = 0; i < candidates.length; i++) {
    candidate = candidates[i].toLowerCase()
    for (j = 0; j < catalog.length; j++) {
      entry = catalog[j]
      if (String(entry.startupClass || "").toLowerCase() === candidate) return entry
    }
    var browser = browserIdentity(candidates[i])
    if (browser) {
      for (j = 0; j < catalog.length; j++) {
        entry = catalog[j]
        if (webIdentities(entry).indexOf(browser) >= 0) return entry
      }
    }
  }
  for (i = 0; i < candidates.length; i++) {
    candidate = candidates[i].toLowerCase()
    for (j = 0; j < catalog.length; j++)
      if (String(catalog[j].id).toLowerCase() === candidate) return catalog[j]
    if (heuristic) {
      try { entry = heuristic(candidates[i]); if (entry) return entry } catch (error) {}
    }
  }
  return null
}

if (typeof module !== "undefined") module.exports = {ids: ids, browserIdentity: browserIdentity, webIdentities: webIdentities, lookup: lookup}
