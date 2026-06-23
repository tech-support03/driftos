// ~/.config/quickshell/services/Bluetooth.qml
// Singleton BlueZ provider. Polls `bluetoothctl` and exposes reactive state
// for the SideBar's bluetooth button + the BluetoothFlyout manager. Mirrors
// services/Network.qml beat-for-beat (single bundled poll, short-lived action
// processes that re-poll on exit).
//
// One bundled `sh -c` poll per tick (adapter show + full/paired/connected
// device lists, split by markers) — same single-process philosophy as
// Network.qml / SysStats. Actions (connect / disconnect / pair / remove /
// power toggle / scan) run as their own short-lived Process and refresh on exit.
//
// bluetoothctl ships with bluez-utils and lives in /usr/bin on Arch, so it
// resolves on the quickshell PATH without a wrapper. There's no clean
// event-stream wired up here (cf. Network.qml's `busctl monitor`), so this
// leans on the timer poll
// (sped up during a scan) plus refresh-after-action.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: bt

    // ---- adapter state ------------------------------------------------------
    property bool   available: false   // a controller exists (false ⇒ no BT hw)
    property bool   powered:   false
    property bool   discovering: false
    property bool   scanning:  false   // a `scan on` window we launched is live
    property string lastError: ""

    // ---- device list --------------------------------------------------------
    // [{ mac, name, paired (bool), connected (bool), named (bool), glyph }]
    // Unnamed scan noise (devices BlueZ only knows by MAC) is filtered out in
    // _ingest unless the device is already paired/connected — see add().
    property var    devices: []
    // convenience: the first connected device's name (for the sidebar tooltip /
    // flyout header), and a count of connected devices.
    readonly property int connectedCount: {
        let n = 0
        const d = devices || []
        for (let i = 0; i < d.length; i++) if (d[i].connected) n++
        return n
    }
    readonly property string connectedName: {
        const d = devices || []
        for (let i = 0; i < d.length; i++) if (d[i].connected) return d[i].name
        return ""
    }

    signal actionFinished(bool ok, string message)

    // ---- glyphs (nerd font, Material Design bluetooth set) ------------------
    // Sidebar status glyph: off / on-idle / connected.
    readonly property string glyph: {
        if (!powered)            return "󰂲"   // bluetooth-off
        if (connectedCount > 0)  return "󰂱"   // bluetooth-connect
        return "󰂯"                            // bluetooth (on, nothing connected)
    }

    // Per-device glyph, guessed from the BlueZ Icon hint with a name fallback.
    // Keeps the list readable without an extra `info` call per device.
    function deviceGlyph(icon, name) {
        const i = (icon || "").toLowerCase()
        const n = (name || "").toLowerCase()
        if (i.indexOf("headset") !== -1 || i.indexOf("headphone") !== -1
            || n.indexOf("headphone") !== -1 || n.indexOf("buds") !== -1
            || n.indexOf("airpod") !== -1)                       return "󰋋"  // headphones
        if (i.indexOf("audio") !== -1 || n.indexOf("speaker") !== -1) return "󰓃"  // speaker
        if (i.indexOf("mouse") !== -1)                           return "󰍽"  // mouse
        if (i.indexOf("keyboard") !== -1)                        return "󰌌"  // keyboard
        if (i.indexOf("phone") !== -1)                           return "󰄜"  // cellphone
        if (i.indexOf("input-gaming") !== -1 || n.indexOf("controller") !== -1) return "󰊴"  // gamepad
        if (i.indexOf("computer") !== -1)                        return "󰟀"  // monitor
        return "󰂯"                                                            // generic bluetooth
    }

    // ---- single bundled status poll -----------------------------------------
    // `devices Paired` / `devices Connected` filters need bluez ≥ 5.65 (current
    // on Arch). Each emits `Device <MAC> <Name>` lines.
    readonly property Process _poll: Process {
        command: ["sh", "-c",
            "echo @@SHOW@@; bluetoothctl show 2>/dev/null;" +
            "echo @@ALL@@; bluetoothctl devices 2>/dev/null;" +
            "echo @@PAIRED@@; bluetoothctl devices Paired 2>/dev/null;" +
            "echo @@CONN@@; bluetoothctl devices Connected 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: bt._ingest(this.text) }
    }

    // Poll tick. Faster while a scan window is live so newly-seen devices show
    // up promptly; slow steady tick otherwise.
    readonly property Timer _tick: Timer {
        interval: bt.scanning ? 1500 : 6000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: bt._poll.running = true
    }

    function refresh() { _poll.running = true }

    function _ingest(raw) {
        try {
            const lines = (raw || "").split("\n")
            let section = ""
            let show = [], all = [], paired = [], conn = []
            for (let i = 0; i < lines.length; i++) {
                const ln = lines[i]
                if (ln.indexOf("@@") === 0) { section = ln; continue }
                if (ln.length === 0) continue
                if (section === "@@SHOW@@")        show.push(ln)
                else if (section === "@@ALL@@")    all.push(ln)
                else if (section === "@@PAIRED@@") paired.push(ln)
                else if (section === "@@CONN@@")   conn.push(ln)
            }

            // adapter: presence of a "Controller" line means hardware exists;
            // Powered/Discovering are indented "Key: value" lines.
            let haveCtrl = false, isPowered = false, isDiscovering = false
            for (let s = 0; s < show.length; s++) {
                const t = show[s].trim()
                if (t.indexOf("Controller ") === 0) haveCtrl = true
                else if (t.indexOf("Powered:") === 0)     isPowered = t.indexOf("yes") !== -1
                else if (t.indexOf("Discovering:") === 0) isDiscovering = t.indexOf("yes") !== -1
            }
            available = haveCtrl
            powered = isPowered
            discovering = isDiscovering

            // helper: parse "Device <MAC> <Name>" → { mac, name }
            function parseDev(ln) {
                const t = ln.trim()
                if (t.indexOf("Device ") !== 0) return null
                const rest = t.slice(7)            // drop "Device "
                const sp = rest.indexOf(" ")
                if (sp === -1) return { mac: rest, name: rest }
                return { mac: rest.slice(0, sp), name: rest.slice(sp + 1) }
            }

            const pairedSet = {}, connSet = {}
            for (let p = 0; p < paired.length; p++) {
                const d = parseDev(paired[p]); if (d) pairedSet[d.mac] = true
            }
            for (let c = 0; c < conn.length; c++) {
                const d = parseDev(conn[c]); if (d) connSet[d.mac] = true
            }

            const seen = {}, list = []
            // `devices` (all) carries the canonical name; connected devices that
            // somehow aren't in the all-list still get folded in below.
            function add(d) {
                if (!d || seen[d.mac] !== undefined) return
                const isConn   = connSet[d.mac] === true
                const isPaired = pairedSet[d.mac] === true
                // BlueZ falls back to the dashed MAC as a placeholder name when
                // it has no friendly name for a device (privacy-address phones,
                // BLE beacons, neighbours). Those are unidentifiable, so keep
                // them only if already paired/connected; otherwise they're just
                // scan noise that buries the real devices, and we drop them.
                const placeholder = d.mac.replace(/:/g, "-").toUpperCase()
                const named = !!(d.name && d.name.length
                                 && d.name.toUpperCase() !== placeholder
                                 && d.name !== d.mac)
                if (!named && !isPaired && !isConn) return
                seen[d.mac] = true
                list.push({
                    mac: d.mac,
                    name: named ? d.name : d.mac,
                    paired: isPaired,
                    connected: isConn,
                    named: named,
                    glyph: bt.deviceGlyph("", d.name)
                })
            }
            for (let a = 0; a < all.length; a++) add(parseDev(all[a]))
            for (let c2 = 0; c2 < conn.length; c2++) add(parseDev(conn[c2]))

            // sort: connected first, then paired, then by name.
            list.sort(function(a, b) {
                if (a.connected !== b.connected) return a.connected ? -1 : 1
                if (a.paired !== b.paired)       return a.paired ? -1 : 1
                return a.name.localeCompare(b.name)
            })
            devices = list
        } catch (e) {
            // malformed read — leave prior state, next tick recovers
        }
    }

    // ---- actions ------------------------------------------------------------
    readonly property Process _action: Process {
        stdout: StdioCollector { id: actOut }
        stderr: StdioCollector { id: actErr }
        onExited: (code, status) => {
            const ok = code === 0
            bt.lastError = ok ? "" : (actErr.text || actOut.text || "failed").trim()
            bt.actionFinished(ok, bt.lastError)
            bt.refresh()
        }
    }
    function _run(cmd) {
        if (_action.running) return
        _action.command = cmd
        _action.running = true
    }

    function setPowered(on) {
        Quickshell.execDetached(["bluetoothctl", "power", on ? "on" : "off"])
        powered = on
        rescanTimer.restart()
    }
    function togglePower() { setPowered(!powered) }

    // Connect a known/paired device. Unpaired devices need pair+trust first;
    // bundle the three so a fresh device "just connects" from one tap. Anything
    // that needs a PIN/passkey agent falls to blueman-manager (the flyout's
    // Advanced button), same as wifi-enterprise → iwctl in a terminal.
    function connect(mac, paired) {
        if (paired)
            _run(["bluetoothctl", "connect", mac])
        else
            _run(["sh", "-c",
                  "bluetoothctl pair '" + mac + "' && " +
                  "bluetoothctl trust '" + mac + "' && " +
                  "bluetoothctl connect '" + mac + "'"])
    }
    function disconnect(mac) { _run(["bluetoothctl", "disconnect", mac]) }
    function forget(mac)     { _run(["bluetoothctl", "remove", mac]) }

    // Discovery window: `--timeout` makes bluetoothctl scan for N seconds then
    // exit on its own (scanning only runs while a bluetoothctl session is live,
    // so a plain `scan on` one-shot would stop the instant it returned).
    readonly property Process _scan: Process {
        command: ["bluetoothctl", "--timeout", "8", "scan", "on"]
        onExited: (code, status) => { bt.scanning = false; bt.refresh() }
    }
    function rescan() {
        if (!powered || _scan.running) return
        scanning = true
        _scan.running = true
        rescanTimer.restart()
    }
    // Safety net: clears the scanning flag even if the scan process is killed
    // without an exit signal reaching us.
    readonly property Timer _rescanTimer: Timer {
        id: rescanTimer
        interval: 9000
        onTriggered: { bt.scanning = false; bt.refresh() }
    }
}
