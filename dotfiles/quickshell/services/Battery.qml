// ~/.config/quickshell/services/Battery.qml
// Singleton battery provider. Reads /sys/class/power_supply/BAT* via a single
// bundled `sh -c` poll (mirrors SysStats/Network's one-process philosophy) and
// exposes reactive level + charge state for the SideBar's battery pill.
//
// Per CLAUDE.md the desktop has NO battery indicator. This service self-gates:
// `present` stays false when no BAT* node exists, so the laptop install shows
// the pill and the desktop install hides it automatically — no profile flag.
//
// Battery state moves slowly, so a 10s poll is plenty (and stays cheap in the
// light profile). cat on sysfs is effectively free.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: bat

    property bool   present:  false
    property int    percent:  0
    property string status:   "Unknown"   // Charging | Discharging | Full | ...
    readonly property bool charging: status === "Charging" || status === "Full"
    readonly property bool low:      present && !charging && percent <= 15

    // Nerd-font Material battery glyphs, tiered by level (charging set has the
    // bolt baked in). Mirrors Network.signalGlyph's shape.
    readonly property string glyph: {
        if (!present) return ""
        if (charging) {
            if (percent >= 90) return "󰂅"
            if (percent >= 70) return "󰂊"
            if (percent >= 50) return "󰂈"
            if (percent >= 30) return "󰂆"
            return "󰢜"
        }
        if (percent >= 95) return "󰁹"
        if (percent >= 85) return "󰂂"
        if (percent >= 75) return "󰂁"
        if (percent >= 65) return "󰂀"
        if (percent >= 55) return "󰁿"
        if (percent >= 45) return "󰁾"
        if (percent >= 35) return "󰁽"
        if (percent >= 25) return "󰁼"
        if (percent >= 15) return "󰁻"
        if (percent >= 5)  return "󰁺"
        return "󰂎"
    }

    readonly property Process _poll: Process {
        command: ["sh", "-c",
            "B=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1);" +
            "if [ -z \"$B\" ]; then echo PRESENT=0; else" +
            "  echo PRESENT=1;" +
            "  echo CAP=$(cat \"$B/capacity\" 2>/dev/null);" +
            "  echo STATUS=$(cat \"$B/status\" 2>/dev/null);" +
            "fi"]
        stdout: StdioCollector { onStreamFinished: bat._ingest(this.text) }
    }

    readonly property Timer _tick: Timer {
        interval: 10000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: bat._poll.running = true
    }

    function refresh() { _poll.running = true }

    function _ingest(raw) {
        try {
            const lines = (raw || "").split("\n")
            let pres = false, cap = bat.percent, st = bat.status
            for (let i = 0; i < lines.length; i++) {
                const ln = lines[i].trim()
                if (ln === "PRESENT=0") { pres = false }
                else if (ln === "PRESENT=1") { pres = true }
                else if (ln.indexOf("CAP=") === 0) {
                    const v = parseInt(ln.slice(4))
                    if (!isNaN(v)) cap = Math.max(0, Math.min(100, v))
                }
                else if (ln.indexOf("STATUS=") === 0) {
                    const s = ln.slice(7)
                    if (s.length) st = s
                }
            }
            present = pres
            percent = cap
            status = st
        } catch (e) {
            // malformed read — keep prior state, next tick recovers
        }
    }
}
