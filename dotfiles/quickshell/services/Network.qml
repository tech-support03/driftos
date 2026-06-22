// ~/.config/quickshell/services/Network.qml
// Singleton NetworkManager provider. Polls `nmcli` and exposes reactive
// state for the SideBar's network button + the NetworkFlyout manager.
//
// One bundled `sh -c` poll per tick (radio + device status + wifi list +
// saved connections, split by markers) — mirrors SysStats' single-process
// philosophy. Actions (connect / disconnect / toggle / rescan) run as their
// own short-lived Process and refresh the state on exit.
//
// nmcli lives in /usr/bin on Arch (the /usr/sbin entry is a symlink), so it
// resolves on the quickshell process PATH without a wrapper script.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: net

    // ---- primary link state -------------------------------------------------
    property string primaryType: "none"   // "wifi" | "ethernet" | "none"
    property bool   connected:   false
    property string primaryName: ""        // SSID or wired connection name
    property int    wifiSignal:  0          // 0..100, current AP
    property bool   wifiEnabled: true
    property bool   ethernetUp:  false
    property string localIp:     ""         // local IPv4 of the active uplink

    // ---- wifi scan results --------------------------------------------------
    // [{ ssid, signal (0..100), secured (bool), active (bool), saved (bool) }]
    property var    networks:  []
    property var    savedNames: []
    property bool   scanning:  false
    property string lastError: ""

    signal actionFinished(bool ok, string message)

    // ---- glyphs (nerd font, Material Design wifi-strength set) ---------------
    function signalGlyph(s) {
        if (s >= 80) return "󰤨"  // wifi-strength-4
        if (s >= 60) return "󰤥"  // wifi-strength-3
        if (s >= 40) return "󰤢"  // wifi-strength-2
        if (s >= 20) return "󰤟"  // wifi-strength-1
        return "󰤯"               // wifi-strength-outline (faint)
    }
    // Glyph for the sidebar status button.
    readonly property string glyph: {
        if (primaryType === "ethernet") return "󰈀"   // ethernet
        if (!wifiEnabled)               return "󰤮"    // wifi-strength-off-outline
        if (primaryType === "wifi" && connected) return signalGlyph(wifiSignal)
        return "󰤯"                                    // disconnected
    }

    // ---- single bundled status poll -----------------------------------------
    readonly property Process _poll: Process {
        command: ["sh", "-c",
            "echo @@RADIO@@;  nmcli -t radio wifi 2>/dev/null;" +
            "echo @@DEV@@;    nmcli -t -f TYPE,STATE,CONNECTION,DEVICE device status 2>/dev/null;" +
            "echo @@WIFI@@;   nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list 2>/dev/null;" +
            "echo @@SAVED@@;  nmcli -t -f NAME connection show 2>/dev/null;" +
            "echo @@ROUTE@@;  ip -4 route show default 2>/dev/null; ip -6 route show default 2>/dev/null;" +
            "echo @@ADDR@@;   ip -4 -o addr show scope global 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: net._ingest(this.text) }
    }

    // Backup poll. The nmcli monitor below makes switches reflect near-instantly;
    // this slow tick just catches anything the event stream might miss.
    readonly property Timer _tick: Timer {
        interval: 6000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: net._poll.running = true
    }

    // Event-driven refresh: nmcli monitor emits a line on every NM state change
    // (link up/down, default-route change, manual switch). Debounce a burst of
    // those into a single re-poll so the icon follows the active uplink quickly.
    readonly property Process _monitor: Process {
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: net._debounce.restart() }
    }
    readonly property Timer _debounce: Timer {
        interval: 350
        onTriggered: net._poll.running = true
    }

    function refresh() { _poll.running = true }

    function _ingest(raw) {
        try {
            const lines = (raw || "").split("\n")
            let section = ""
            let radio = "enabled", devs = [], wifis = [], saved = [], routes = [], addrs = []
            for (let i = 0; i < lines.length; i++) {
                const ln = lines[i]
                if (ln.indexOf("@@") === 0) { section = ln; continue }
                if (ln.length === 0) continue
                if (section === "@@RADIO@@")  radio = ln.trim()
                else if (section === "@@DEV@@")   devs.push(ln)
                else if (section === "@@WIFI@@")  wifis.push(ln)
                else if (section === "@@SAVED@@") saved.push(ln)
                else if (section === "@@ROUTE@@") routes.push(ln)
                else if (section === "@@ADDR@@")  addrs.push(ln)
            }

            wifiEnabled = (radio === "enabled")

            // device status: TYPE:STATE:CONNECTION:DEVICE (CONNECTION may have
            // colons, DEVICE is last). Build dev→{type,conn} and remember which
            // ethernet/wifi devices are link-connected (fallback if no default).
            const devType = {}, devConn = {}
            let ethDev = null, ethConn = null, wifiDev = null, wifiConn = null
            for (let d = 0; d < devs.length; d++) {
                const f = devs[d].split(":")
                if (f.length < 4) continue
                const type = f[0]
                const state = f[1]
                const dev  = f[f.length - 1]
                const conn = f.slice(2, f.length - 1).join(":")
                devType[dev] = type
                devConn[dev] = conn
                if (state !== "connected") continue
                if (type === "ethernet") { ethDev = dev; ethConn = conn }
                else if (type === "wifi") { wifiDev = dev; wifiConn = conn }
            }
            ethernetUp = (ethDev !== null)

            // default routes: pick the active uplink as the dev with the lowest
            // route metric. NetworkManager gives ethernet a lower metric than
            // wifi, so ethernet is preferred automatically; if the user drops
            // ethernet or reprioritizes, the default route — and this pick —
            // follow. Lines look like:
            //   default via 192.168.1.1 dev enp8s0 proto dhcp ... metric 100
            let routeDev = null, bestMetric = Infinity
            for (let r = 0; r < routes.length; r++) {
                const t = routes[r].trim().split(/\s+/)
                if (t[0] !== "default") continue
                let dev = "", metric = 0
                for (let k = 0; k < t.length - 1; k++) {
                    if (t[k] === "dev")    dev = t[k + 1]
                    if (t[k] === "metric") metric = parseInt(t[k + 1]) || 0
                }
                if (!dev) continue
                if (metric < bestMetric) { bestMetric = metric; routeDev = dev }
            }

            // local IPv4 per device. `ip -4 -o addr show scope global` prints
            //   2: enp8s0    inet 192.168.1.42/24 brd ... scope global ...
            // so the device is field[1] and the dotted addr is field[3] before
            // its /prefix. Pick the address on the active uplink (route dev),
            // falling back to ethernet then wifi when there's no default route.
            const devIp = {}
            for (let a = 0; a < addrs.length; a++) {
                const t = addrs[a].trim().split(/\s+/)
                if (t.length < 4 || t[2] !== "inet") continue
                const dev = t[1]
                const ip  = t[3].split("/")[0]
                if (devIp[dev] === undefined) devIp[dev] = ip
            }
            const ipDev = routeDev || ethDev || wifiDev
            const ipNow = ipDev ? (devIp[ipDev] || "") : ""

            // saved connection names
            const savedList = []
            for (let s = 0; s < saved.length; s++)
                if (saved[s].length) savedList.push(saved[s])
            savedNames = savedList

            // wifi list: IN-USE:SIGNAL:SECURITY:SSID (SSID last, may hold colons)
            const seen = {}
            const list = []
            let activeSsid = "", activeSig = 0
            for (let w = 0; w < wifis.length; w++) {
                const f = wifis[w].split(":")
                if (f.length < 4) continue
                const inUse = f[0] === "*"
                const sig = parseInt(f[1]) || 0
                const sec = f[2]
                const ssid = f.slice(3).join(":")
                if (!ssid.length) continue
                const secured = sec.length > 0 && sec !== "--"
                // 802.1X = WPA2/WPA3-Enterprise: needs a username + EAP method,
                // not a single PSK. The flyout hands these to nmtui instead of
                // showing a (useless) password box.
                const enterprise = sec.indexOf("802.1X") !== -1
                if (inUse) { activeSsid = ssid; activeSig = sig }
                // dedupe by SSID, keep strongest signal
                if (seen[ssid] !== undefined) {
                    if (sig > list[seen[ssid]].signal) {
                        list[seen[ssid]].signal = sig
                        list[seen[ssid]].active = list[seen[ssid]].active || inUse
                    }
                    continue
                }
                seen[ssid] = list.length
                list.push({
                    ssid: ssid, signal: sig, secured: secured, enterprise: enterprise,
                    active: inUse, saved: savedList.indexOf(ssid) !== -1
                })
            }
            list.sort(function(a, b) {
                if (a.active !== b.active) return a.active ? -1 : 1
                return b.signal - a.signal
            })
            networks = list

            // fold everything into the primary-link summary. Prefer the device
            // that owns the default route (the connection actually carrying
            // traffic); fall back to a link-connected device — ethernet first —
            // when there's no default route (e.g. captive/no-gateway link).
            wifiSignal = activeSig
            const routeType = routeDev ? devType[routeDev] : ""
            if (routeType === "ethernet" || routeType === "wifi") {
                primaryType = routeType
                connected = true
                primaryName = routeType === "wifi"
                    ? (activeSsid || devConn[routeDev] || wifiConn)
                    : devConn[routeDev]
                localIp = ipNow
            } else if (ethDev !== null) {
                primaryType = "ethernet"; connected = true; primaryName = ethConn
                localIp = ipNow
            } else if (wifiDev !== null) {
                primaryType = "wifi"; connected = true
                primaryName = activeSsid || wifiConn
                localIp = ipNow
            } else {
                primaryType = "none"; connected = false; primaryName = ""; localIp = ""
            }
        } catch (e) {
            // malformed read — leave prior state, next tick recovers
        }
    }

    function isSaved(ssid) { return savedNames.indexOf(ssid) !== -1 }

    // ---- actions ------------------------------------------------------------
    readonly property Process _action: Process {
        stdout: StdioCollector { id: actOut }
        stderr: StdioCollector { id: actErr }
        onExited: (code, status) => {
            const ok = code === 0
            net.lastError = ok ? "" : (actErr.text || actOut.text || "failed").trim()
            net.actionFinished(ok, net.lastError)
            net.refresh()
        }
    }
    function _run(cmd) {
        if (_action.running) return
        _action.command = cmd
        _action.running = true
    }

    // Connect to a wifi network. Open or already-saved networks need no
    // password; secured + unknown ones require one.
    function connectWifi(ssid, secured, password) {
        if (!secured || isSaved(ssid))
            _run(["nmcli", "dev", "wifi", "connect", ssid])
        else
            _run(["nmcli", "dev", "wifi", "connect", ssid, "password", password])
    }
    function disconnectWifi() {
        // Bring the active wifi connection down by name.
        if (primaryType === "wifi" && primaryName.length)
            _run(["nmcli", "connection", "down", "id", primaryName])
    }
    function forget(ssid) { _run(["nmcli", "connection", "delete", "id", ssid]) }

    function setWifiEnabled(on) {
        Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"])
        wifiEnabled = on
        rescanTimer.restart()
    }
    function toggleWifi() { setWifiEnabled(!wifiEnabled) }

    function rescan() {
        scanning = true
        Quickshell.execDetached(["nmcli", "dev", "wifi", "rescan"])
        rescanTimer.restart()
    }
    readonly property Timer _rescanTimer: Timer {
        id: rescanTimer
        interval: 2500
        onTriggered: { net.scanning = false; net.refresh() }
    }
}
