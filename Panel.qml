import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Optional bar widget: one icon and one panel for Antigravity's limits and
// local activity.
//
// This reads the same record AntigravityService.qml publishes — it never
// collects anything itself, so the numbers here and the ones in the built-in
// Agents panel cannot disagree. The widget is not in the default layout; the
// Agents panel already shows this data. Add it with
// `omarchy bar put lasswellt.antigravity` when you want a dedicated icon, and
// see the README for hiding the duplicate Agents tab.
Panel {
  id: root

  moduleName: "lasswellt.antigravity"
  // The service owns the plain `lasswellt.antigravity` IPC target (refresh,
  // collect). Two IpcHandlers cannot share a target, so the panel takes its
  // own rather than fighting the service for it.
  ipcTarget: "lasswellt.antigravity.panel"

  readonly property color foreground: Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color urgent: Color.urgent
  readonly property color track: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.16)
  readonly property string fontFamily: Style.font.family

  readonly property string usageDir:
    (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") || "") + "/.local/state")
    + "/omarchy/agents/usage"

  property var record: null

  readonly property var limits: record && Array.isArray(record.limits) ? record.limits : []
  readonly property var recentDays: record && Array.isArray(record.recentDays) ? record.recentDays : []
  readonly property bool ready: !!record && record.ready === true
  readonly property string statusText: record ? String(record.usageStatusText || "") : ""
  readonly property string helpText: record ? String(record.authHelpText || "") : ""
  readonly property string tierLabel: record ? String(record.tierLabel || "") : ""

  function num(v) {
    var n = Number(v)
    return isFinite(n) ? n : 0
  }

  // `visible: false` on an enclosing item does not stop its children's
  // bindings from evaluating, so every read of `record` has to survive the
  // null it holds before the first file load.
  readonly property real todaySessions: record ? num(record.todaySessions) : 0
  readonly property real totalSessions: record ? num(record.totalSessions) : 0
  readonly property real activeDays: record ? num(record.activeDays) : 0

  // Same gate the Agents panel applies: a machine that has Antigravity but has
  // never used it draws nothing rather than sitting in the bar saying zero.
  readonly property bool hasData: !!record && (
    num(record.totalSessions) > 0 || num(record.todaySessions) > 0
    || num(record.activeDays) > 0 || limits.length > 0)

  // The limit closest to exhausted drives the bar label and the alarm state.
  readonly property var tightestLimit: {
    var worst = null
    for (var i = 0; i < limits.length; i++) {
      var pct = num(limits[i].percent)
      if (!worst || pct > num(worst.percent)) worst = limits[i]
    }
    return worst
  }
  readonly property bool alarming: !!tightestLimit && num(tightestLimit.percent) >= 0.9

  visible: hasData

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Reset countdowns are only worth recomputing while someone is looking.
  property double nowMs: Date.now()
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  FileView {
    path: root.usageDir + "/antigravity.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(String(text() || ""))
        root.record = parsed && typeof parsed === "object" ? parsed : null
      } catch (e) {
        console.warn("antigravity: ignoring bad usage record", e)
        root.record = null
      }
    }
    onLoadFailed: root.record = null
  }

  Process {
    id: refreshProcess
    running: false
    command: [Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
              + "/bin/antigravity-usage-update", "--force"]
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("antigravity:", text.trim())
    }
  }

  function refreshNow() {
    if (!refreshProcess.running) refreshProcess.running = true
  }

  function percentText(value) {
    var pct = root.num(value) * 100
    if (pct > 0 && pct < 1) return "<1%"
    return Math.round(pct) + "%"
  }

  // "resets in 4h 19m" / "resets in 6d" — the same shape the CLI prints.
  function resetText(iso) {
    if (!iso) return ""
    var at = Date.parse(String(iso))
    if (!isFinite(at)) return ""
    var secs = Math.floor((at - root.nowMs) / 1000)
    if (secs <= 0) return "resetting"
    var days = Math.floor(secs / 86400)
    var hours = Math.floor((secs % 86400) / 3600)
    var mins = Math.floor((secs % 3600) / 60)
    if (days > 0) return "resets in " + days + "d " + hours + "h"
    if (hours > 0) return "resets in " + hours + "h " + mins + "m"
    return "resets in " + mins + "m"
  }

  function shortDay(iso) {
    var d = new Date(String(iso) + "T00:00:00")
    if (isNaN(d.getTime())) return String(iso)
    return Qt.formatDate(d, "ddd")
  }

  readonly property int busiestDay: {
    var max = 0
    for (var i = 0; i < recentDays.length; i++)
      max = Math.max(max, num(recentDays[i].messageCount))
    return max
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  function markCandidates(surfaceColor) {
    var c = surfaceColor || Color.background
    var luminance = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    var out = []
    if (luminance >= 0.5) out.push(Qt.resolvedUrl("assets/antigravity-light.svg"))
    out.push(Qt.resolvedUrl("assets/antigravity.svg"))
    return out
  }

  // ------------------------------------------------------------- bar button

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.alarming
    // No `text`: BarIconButton hides its own glyph whenever iconComponent is
    // set, so the fallback for a missing SVG lives inside the icon instead.

    iconComponent: Component {
      Item {
        id: mark
        property var candidates: root.markCandidates(root.barForeground)
        property string candidatesKey: candidates.join("\n")
        property int index: 0
        onCandidatesKeyChanged: index = 0

        width: Style.font.icon
        height: Style.font.icon

        Image {
          id: markImage
          anchors.fill: parent
          source: mark.index < mark.candidates.length ? mark.candidates[mark.index] : ""
          sourceSize.width: Style.font.icon * 2
          sourceSize.height: Style.font.icon * 2
          fillMode: Image.PreserveAspectFit
          // Stepping source from inside its own status handler trips the
          // binding-loop detector; defer one tick, same as the Agents panel.
          onStatusChanged: if (status === Image.Error && mark.index < mark.candidates.length)
            Qt.callLater(function() { mark.index++ })
        }

        // If neither SVG loads, the button's own glyph shows through.
        Text {
          anchors.centerIn: parent
          visible: markImage.status !== Image.Ready
          textFormat: Text.PlainText
          text: "󰑫"
          color: root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refreshNow()
      else root.toggle()
    }
  }

  // ----------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    // Four limit rows, three stats and a seven-day chart do not fit in the
    // height a control panel wants. Capped at 560 the newest day — today, the
    // one row anyone actually looks for — fell below the fold.
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          flick.contentY = root.clamp(flick.contentY + dy * Style.space(56), 0,
                                      Math.max(0, flick.contentHeight - flick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refreshNow() }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          PanelHero {
            title: "Antigravity"
            meta: root.tierLabel !== "" ? root.tierLabel
                  : (root.statusText !== "" ? root.statusText : "Local activity and limits")
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Item {
                id: heroMark
                property var candidates: root.markCandidates(Color.background)
                property string candidatesKey: candidates.join("\n")
                property int index: 0
                onCandidatesKeyChanged: index = 0

                width: Style.font.display
                height: Style.font.display

                Image {
                  id: heroImage
                  anchors.fill: parent
                  source: heroMark.index < heroMark.candidates.length ? heroMark.candidates[heroMark.index] : ""
                  sourceSize.width: Style.font.display * 2
                  sourceSize.height: Style.font.display * 2
                  fillMode: Image.PreserveAspectFit
                  onStatusChanged: if (status === Image.Error && heroMark.index < heroMark.candidates.length)
                    Qt.callLater(function() { heroMark.index++ })
                }
              }
            }
          }

          // ---------- Not signed in / collector trouble ----------
          Column {
            visible: root.statusText !== "" || (!root.ready && !!root.record)
            width: parent.width
            spacing: Style.space(4)

            PanelSeparator { width: parent.width }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.statusText !== "" ? root.statusText : "No Antigravity data yet"
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.helpText !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: root.helpText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Limits ----------
          Column {
            visible: root.limits.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator { width: parent.width }

            PanelSectionHeader {
              width: parent.width
              text: "LIMITS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.limits

              LimitRow {
                required property var modelData
                width: column.width
                label: String(modelData.label || "")
                percent: root.num(modelData.percent)
                resetsAt: String(modelData.resetsAt || "")
              }
            }
          }

          // ---------- Activity ----------
          Column {
            visible: !!root.record
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { width: parent.width }

            PanelSectionHeader {
              width: parent.width
              text: "ACTIVITY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            StatRow { label: "Conversations today"; value: root.todaySessions }
            StatRow { label: "All time"; value: root.totalSessions }
            StatRow { label: "Active days"; value: root.activeDays }
          }

          // ---------- Last 7 days ----------
          Column {
            visible: root.recentDays.length > 0 && root.busiestDay > 0
            width: parent.width
            spacing: Style.space(4)

            PanelSeparator { width: parent.width }

            PanelSectionHeader {
              width: parent.width
              text: "LAST 7 DAYS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.recentDays

              DayRow {
                required property var modelData
                required property int index
                width: column.width
                day: root.shortDay(modelData.date)
                steps: root.num(modelData.messageCount)
                isToday: index === root.recentDays.length - 1
              }
            }
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: "r refresh · Esc close"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // ------------------------------------------------------- inline components

  component Meter: Item {
    property real value: -1
    property bool alarming: false

    implicitHeight: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(parent.value, 0, 1)
      color: parent.alarming ? root.urgent : root.foreground
    }
  }

  component LimitRow: Column {
    property string label: ""
    property real percent: 0
    property string resetsAt: ""

    readonly property bool rowAlarming: percent >= 0.9

    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

      Text {
        id: limitLabel
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width - limitValue.implicitWidth - Style.space(8))
        textFormat: Text.PlainText
        text: parent.parent.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      // Percentage and reset share one line. On their own rows the four
      // limits pushed the seven-day chart past the bottom of the panel.
      Text {
        id: limitValue
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: {
          var used = root.percentText(parent.parent.percent) + " used"
          var reset = root.resetText(parent.parent.resetsAt)
          return reset === "" ? used : used + " · " + reset
        }
        color: parent.parent.rowAlarming ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Meter {
      width: parent.width
      value: parent.percent
      alarming: parent.rowAlarming
    }
  }

  component StatRow: Item {
    property string label: ""
    property real value: 0

    width: parent ? parent.width : 0
    implicitHeight: Math.max(statLabel.implicitHeight, statValue.implicitHeight)

    Text {
      id: statLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: parent.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      id: statValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: String(Math.round(parent.value))
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  component DayRow: Item {
    property string day: ""
    property real steps: 0
    property bool isToday: false

    implicitHeight: Math.max(dayLabel.implicitHeight, Style.space(14))

    Text {
      id: dayLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(34)
      textFormat: Text.PlainText
      text: parent.day
      color: parent.isToday ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: parent.isToday
    }

    Rectangle {
      id: dayTrack
      anchors.left: dayLabel.right
      anchors.leftMargin: Style.space(6)
      anchors.right: dayValue.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.12))
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        // Scaled against the busiest day, the way the Agents panel scales its
        // weekly chart, so a quiet week still reads as a shape.
        width: root.busiestDay > 0
               ? parent.width * root.clamp(dayRowSteps / root.busiestDay, 0, 1)
               : 0
        color: root.foreground
        opacity: dayRowIsToday ? 1.0 : 0.65

        readonly property real dayRowSteps: parent.parent.steps
        readonly property bool dayRowIsToday: parent.parent.isToday
      }
    }

    Text {
      id: dayValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: String(Math.round(parent.steps))
      color: parent.isToday ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: parent.isToday
    }
  }
}
