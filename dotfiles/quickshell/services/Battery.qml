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

    // Remaining run-time (discharging) / time-to-full (charging), derived from
    // the same poll. `timeRemaining` is a human string ("3h 24m" / "42m"); it's
    // "" whenever we can't compute it (rate unknown / zero, or Full). The raw
    // minute count is also exposed for any consumer that wants to format it.
    property string timeRemaining: ""
    property int    minutesRemaining: 0

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
            // Energy-based gauges (µWh / µW). Some batteries report charge
            // instead (µAh / µA) — emit both, _ingest prefers energy_* then
            // falls back to charge_*. Missing files just print blank.
            "  echo ENOW=$(cat \"$B/energy_now\" 2>/dev/null);" +
            "  echo EFULL=$(cat \"$B/energy_full\" 2>/dev/null);" +
            "  echo PNOW=$(cat \"$B/power_now\" 2>/dev/null);" +
            "  echo CNOW=$(cat \"$B/charge_now\" 2>/dev/null);" +
            "  echo CFULL=$(cat \"$B/charge_full\" 2>/dev/null);" +
            "  echo INOW=$(cat \"$B/current_now\" 2>/dev/null);" +
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

    // Pretty-print a minute count → "Xh Ym" (or "Ym" under an hour).
    function _fmt(mins) {
        const m = Math.round(mins)
        if (m <= 0) return ""
        const h = Math.floor(m / 60)
        const r = m % 60
        return h > 0 ? (h + "h " + r + "m") : (r + "m")
    }

    function _ingest(raw) {
        try {
            const lines = (raw || "").split("\n")
            let pres = false, cap = bat.percent, st = bat.status
            // Raw gauges, NaN until a valid line sets them.
            let enow = NaN, efull = NaN, pnow = NaN
            let cnow = NaN, cfull = NaN, inow = NaN
            const num = function (s) { const v = parseFloat(s); return isNaN(v) ? NaN : v }
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
                else if (ln.indexOf("ENOW=")  === 0) enow  = num(ln.slice(5))
                else if (ln.indexOf("EFULL=") === 0) efull = num(ln.slice(6))
                else if (ln.indexOf("PNOW=")  === 0) pnow  = num(ln.slice(5))
                else if (ln.indexOf("CNOW=")  === 0) cnow  = num(ln.slice(5))
                else if (ln.indexOf("CFULL=") === 0) cfull = num(ln.slice(6))
                else if (ln.indexOf("INOW=")  === 0) inow  = num(ln.slice(5))
            }
            present = pres
            percent = cap
            status = st

            // Time estimate. Prefer energy_* (Wh/W); fall back to charge_*
            // (Ah/A). The Wh/W and Ah/A ratios both come out in hours, so the
            // arithmetic is identical — pick whichever gauge set is populated.
            let now = NaN, full = NaN, rate = NaN
            if (!isNaN(enow) && !isNaN(pnow)) { now = enow; full = efull; rate = pnow }
            else if (!isNaN(cnow) && !isNaN(inow)) { now = cnow; full = cfull; rate = inow }

            let mins = 0
            const chg = (st === "Charging")
            if (!isNaN(now) && !isNaN(rate) && rate > 0) {
                if (chg) {
                    if (!isNaN(full) && full > now) mins = ((full - now) / rate) * 60
                } else if (st === "Discharging") {
                    mins = (now / rate) * 60
                }
            }
            minutesRemaining = Math.max(0, Math.round(mins))
            timeRemaining = _fmt(mins)
        } catch (e) {
            // malformed read — keep prior state, next tick recovers
        }
    }
}
