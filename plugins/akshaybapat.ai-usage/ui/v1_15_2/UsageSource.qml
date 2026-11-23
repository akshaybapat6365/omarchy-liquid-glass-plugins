import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The report, and nothing else.
//
// Upstream keeps collection inside Panel.qml and has the bar button read its
// numbers back out of the popup. That works when the bar shows one value, but
// it makes the thing you always see depend on the thing you rarely open — and
// the popup is a Wayland layer surface, so the bar's data is unreachable
// wherever that surface cannot exist.
//
// So collection lives here instead: a plain non-visual object that owns the
// two commands, the refresh timer, and the parsed result. The strip binds to
// it directly and the panel is handed the same instance, which makes the panel
// a view of the report rather than its owner.
//
// The commands themselves are upstream's: fixed argv, no shell string, and
// the Rust binary remains the only thing that reads config or talks to a
// provider. Each one starts through background.sh, which runs it unchanged on
// the efficiency cores at idle priority.
QtObject {
  id: root

  property int refreshIntervalSec: 300

  // ---------------------------------------------------------------- report
  property var entries: []
  property string primary: ""
  property bool loading: true
  property string loadError: ""
  property int lastExitCode: 0
  property double lastSuccessfulMs: 0

  // The engine's own entries, before the native Cursor reading is merged in.
  property var engineEntries: []
  property bool engineDone: false

  // ---------------------------------------------------------- native Cursor
  //
  // Cursor's edge refuses the engine's HTTP client while accepting the same
  // request from the standard library (2026-09-07), so Cursor is also read by
  // omarchy-ai-cursor-usage and that reading, when fresh, replaces the
  // engine's. Its refusal / login verdicts ride along for the panel's wording.
  property var nativeCursor: ({ ok: false, entry: null, refused: null, auth: null, note: "" })
  property string nativeStdout: ""

  // Consecutive refreshes in which a provider was not fresh, by id. One miss
  // is graced in the strip; the second dims the cell. `missesBase` is the
  // count at the start of the current refresh, so re-applying the same cycle
  // (engine first, native reading a moment later) never counts a miss twice.
  property var misses: ({})
  property var missesBase: ({})

  // A clock for the countdowns. Deliberately separate from `entries` so a tick
  // re-evaluates the text bindings that use it without rebuilding the model
  // and churning every delegate in the strip.
  property double nowMs: Date.now()

  // ------------------------------------------------------------- last seen
  //
  // The last successful reading per provider, so a provider that is only up
  // while its app is (Antigravity) shows its real numbers, dated, instead of
  // an empty cell. It outlives the shell because the thing it remembers does:
  // restarting the bar should not lose what was true an hour ago.
  property var lastSeen: ({})
  property string lastSeenText: ""

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/ai-usage"

  function rememberReport() {
    var next = Model.rememberEntries(lastSeen, entries)
    var text = Model.serializeLastSeen(next)
    // Sorted output means an unchanged cache is a byte-identical string, so the
    // steady state — every provider up, nothing new learned — writes nothing.
    if (text === lastSeenText) return
    lastSeen = next
    lastSeenText = text
    lastSeenFile.setText(text)
  }

  // FileView creates the parent directories on write and, with atomicWrites,
  // replaces the file rather than truncating it, so a shell killed mid-write
  // leaves the previous cache intact. The initial read blocks: it is one small
  // file, read once at construction, and doing it asynchronously would show an
  // empty offline cell for a frame before filling it in.
  property FileView lastSeenFile: FileView {
    id: lastSeenFile
    path: root.stateDir + "/last-seen.json"
    blockLoading: true
    blockWrites: false
    atomicWrites: true
    // A missing cache on first run is the normal case, not a fault to report.
    printErrors: false
    onLoaded: {
      root.lastSeenText = text()
      root.lastSeen = Model.parseLastSeen(root.lastSeenText)
    }
  }

  // ----------------------------------------------------------- local spend
  property var spend: ({ ok: false, note: "", rows: [], total: 0 })

  readonly property bool busy: usageProcess.running

  property string commandStdout: ""
  property string commandStderr: ""
  property string spendStdout: ""
  property bool refreshQueued: false

  signal reportChanged()

  readonly property string launcher: pathFromUrl(Qt.resolvedUrl("background.sh"))

  function pathFromUrl(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0)
      return decodeURIComponent(value.substring(7))
    return value
  }

  function refresh() {
    if (usageProcess.running) {
      refreshQueued = true
      return
    }
    refreshQueued = false
    commandStdout = ""
    commandStderr = ""
    engineDone = false
    missesBase = misses
    if (entries.length === 0) loading = true
    usageProcess.running = true
    refreshNative()
    refreshSpend()
  }

  function refreshNative() {
    if (cursorProcess.running) return
    nativeStdout = ""
    cursorProcess.running = true
  }

  // Publish the merged report. Called when the engine finishes and again if
  // the native Cursor reading lands afterwards; both are the same cycle.
  function applyReport() {
    entries = Model.mergeNative(engineEntries, nativeCursor)
    misses = Model.countMisses(missesBase, entries)
    loadError = ""
    lastSuccessfulMs = Date.now()
    rememberReport()
    loading = false
    nowMs = Date.now()
    reportChanged()
  }

  function refreshSpend() {
    if (spendProcess.running) return
    spendStdout = ""
    spendProcess.running = true
  }

  function finishRefresh() {
    var parsed = Model.parseReport(commandStdout)
    if (parsed.ok) {
      primary = parsed.primary
      engineEntries = parsed.entries
      engineDone = true
      applyReport()
    } else {
      var detail = commandStderr.trim()
      loadError = lastExitCode === 127
        ? Model.launchErrorMessage(lastExitCode, detail)
        : (detail !== "" ? Model.errorMessage(detail) : parsed.error)
      loading = false
      nowMs = Date.now()
      reportChanged()
    }
    if (refreshQueued) Qt.callLater(refresh)
  }

  property Process usageProcess: Process {
    id: usageProcess
    running: false
    // /usr/bin/env always starts on Omarchy, and a missing ai-usagebar still
    // comes back as exit 127 through the launcher. Keep the command as
    // structured argv: the launcher passes it on untouched.
    command: ["/usr/bin/env", "sh", root.launcher, "ai-usagebar", "usage", "--json"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.commandStdout = text
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.commandStderr = text
    }

    onExited: function(exitCode) {
      root.lastExitCode = exitCode
      // Let both waitForEnd collectors publish their buffers first.
      Qt.callLater(function() { root.finishRefresh() })
    }
  }

  // The native Cursor reader. Its absence or failure is not the engine's
  // problem: the engine's own Cursor entry simply stands.
  property Process cursorProcess: Process {
    id: cursorProcess
    running: false
    command: ["/usr/bin/env", "sh", root.launcher, "omarchy-ai-cursor-usage"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.nativeStdout = text
    }

    stderr: StdioCollector { waitForEnd: true }

    onExited: function(exitCode) {
      Qt.callLater(function() {
        root.nativeCursor = exitCode === 0
          ? Model.parseNative(root.nativeStdout)
          : { ok: false, entry: null, refused: null, auth: null, note: "" }
        if (root.engineDone) root.applyReport()
      })
    }
  }

  // The spend collector is a side channel and behaves like one: it shares the
  // refresh timer, it can never block the quota report, and any failure at all
  // becomes an empty list plus one line of explanation.
  property Process spendProcess: Process {
    id: spendProcess
    running: false
    command: ["/usr/bin/env", "sh", root.launcher, "omarchy-ai-api-spend"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.spendStdout = text
    }

    stderr: StdioCollector { waitForEnd: true }

    onExited: function(exitCode) {
      Qt.callLater(function() {
        root.spend = exitCode === 0
          ? Model.parseSpend(root.spendStdout)
          : { ok: false, note: "The local spend collector is not installed.", rows: [], total: 0 }
      })
    }
  }

  property Timer refreshTimer: Timer {
    interval: Math.max(30, Math.min(3600, root.refreshIntervalSec)) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // A minute is fine for "resets in 1d 7h" and costs nothing; the countdown is
  // never shown to the second.
  property Timer clockTimer: Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }
}
