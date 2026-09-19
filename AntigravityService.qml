import QtQuick
import Quickshell.Io

// Headless collector for Antigravity usage.
//
// This plugin is deliberately not a display. It runs bin/antigravity-usage-update
// on a timer, which publishes one record to
// ~/.local/state/omarchy/agents/usage/antigravity.json; the built-in Agents
// panel discovers that file by name and draws the tab, so Antigravity appears
// next to Claude and Codex with no UI of our own. See roadmap.md §1.
//
// The first-party omarchy-agent-usage-update only runs collectors shipped in
// $OMARCHY_PATH/bin, so nothing else will ever refresh our record — that is
// this service's whole job.
Item {
  id: root
  visible: false

  // Injected by the shell's plugin loader.
  property var shell: null
  property var manifest: null
  property var settings: ({})

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")

  // Matches omarchy.agents' own default. Below 60s we would be spawning the
  // agy binary more often than its numbers can meaningfully change.
  readonly property int refreshIntervalSec: {
    var configured = settings && settings.refreshIntervalSec
    var value = Number(configured)
    return isFinite(value) && value >= 60 ? Math.floor(value) : 900
  }

  function refresh(force) {
    if (collector.running) {
      root.rerunQueued = true
      return
    }
    collector.command = force === true
      ? [root.pluginDir + "/bin/antigravity-usage-update", "--force"]
      : [root.pluginDir + "/bin/antigravity-usage-update"]
    collector.running = true
  }

  property bool rerunQueued: false

  Process {
    id: collector
    running: false

    onExited: (exitCode) => {
      if (exitCode !== 0)
        console.warn("antigravity: collector exited", exitCode)
      if (root.rerunQueued) {
        root.rerunQueued = false
        root.refresh(false)
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("antigravity:", text.trim())
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  // `omarchy-shell lasswellt.antigravity refresh` forces a fresh collection,
  // which is also the escape hatch when a limit has just reset.
  IpcHandler {
    target: "lasswellt.antigravity"

    function refresh(): void { root.refresh(true) }
    function collect(): void { root.refresh(false) }
  }
}
