// ~/.config/quickshell/services/Network.qml
// Singleton iwd provider. Queries iwd over its system-bus DBus API (via the
// always-present `busctl`) and exposes reactive state for the SideBar's network
// button + the NetworkFlyout manager.
//
// This box runs **iwd standalone** (NetworkManager is disabled — it fought iwd),
// so there is no nmcli to talk to. iwd is the source of truth for wifi: scan
// results, saved ("known") networks, the active connection and radio power all
// come from `net.connman.iwd` on the system bus. The local IPv4 / default-route
// (and any ethernet uplink) still come from plain `ip`, which is backend-neutral.
//
// One bundled `sh -c` poll per tick:
//   * busctl GetManagedObjects (JSON) — whole iwd object tree in one call:
//     Device (radio power), Station (state + connected network), Network
//     (scan results) and KnownNetwork (saved) objects.
//   * ip route / ip addr — default uplink + local address.
// iwd exposes per-AP signal only via Station.GetOrderedNetworks (not as an
// object property), so a tiny follow-up busctl call merges RSSI once the poll
// has discovered the station path. Actions (connect / disconnect / forget /
// power / scan) shell out to `iwctl` and re-poll on exit.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: net

    // ---- primary link state -------------------------------------------------
    property string primaryType: "none"   // "wifi" | "ethernet" | "none"
    property bool   connected:   false
    property string primaryName: ""        // SSID or wired device name
    property int    wifiSignal:  0          // 0..100, current AP
    property bool   wifiEnabled: true
    property bool   ethernetUp:  false      // wired link is the active uplink
    property string localIp:     ""         // local IPv4 of the active uplink

    // ---- wired link (manual-override toggle) --------------------------------
    // networkd manages the wired NIC; iwd only does wifi. A plugged-in cable
    // auto-wins on route metric, but the flyout can also force it off/on.
    property bool   ethernetPresent: false  // an en* device exists
    property bool   ethernetEnabled: true   // admin-up (the override target)
    property bool   ethernetPlugged: false  // carrier present (cable in)

    // ---- wifi scan results --------------------------------------------------
    // [{ ssid, signal (0..100), secured (bool), enterprise (bool),
    //    active (bool), saved (bool) }]
    property var    networks:  []
    property var    savedNames: []
    property bool   scanning:  false
    property string lastError: ""

    signal actionFinished(bool ok, string message)

    // ---- iwd topology (discovered each poll) --------------------------------
    property string _wifiDev:     "wlan0"  // station device name, for iwctl
    property string _stationPath: ""        // DBus path of the station device
    property var    _rssiByPath:  ({})      // network object path -> rssi (dBm*100)
    property string _ethDev:      ""        // wired device name, for networkctl

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

    // iwd RSSI is reported in dBm×100. Map to a 0..100 bar the UI can show:
    // ~-100 dBm (unusable) → 0, ~-50 dBm (excellent) → 100, clamped.
    function _rssiToPercent(rssi) {
        const dbm = rssi / 100.0
        return Math.max(0, Math.min(100, Math.round(2 * (dbm + 100))))
    }

    // ---- single bundled status poll -----------------------------------------
    readonly property Process _poll: Process {
        command: ["sh", "-c",
            "echo @@OBJ@@;" +
            "busctl --system --json=short call net.connman.iwd / " +
            "org.freedesktop.DBus.ObjectManager GetManagedObjects 2>/dev/null;" +
            "echo; echo @@ROUTE@@; ip -4 route show default 2>/dev/null; ip -6 route show default 2>/dev/null;" +
            "echo @@ADDR@@;   ip -4 -o addr show scope global 2>/dev/null;" +
            "echo @@LINK@@;   ip -o link show 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: net._ingest(this.text) }
    }

    // Follow-up: per-AP signal. Station.GetOrderedNetworks returns the visible
    // networks in signal order as (object-path, rssi) pairs — the only place
    // iwd surfaces RSSI. Merged into `networks` / `wifiSignal` once it returns.
    readonly property Process _signalPoll: Process {
        stdout: StdioCollector { onStreamFinished: net._ingestSignals(this.text) }
    }

    // Backup poll. The busctl monitor below makes switches reflect near-instantly;
    // this slow tick just catches anything the event stream might miss.
    readonly property Timer _tick: Timer {
        interval: 6000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: net._poll.running = true
    }

    // Event-driven refresh: `busctl monitor` emits a message on every iwd signal
    // (PropertiesChanged on connect/disconnect/scan, InterfacesAdded/Removed for
    // appearing networks). Debounce a burst of those into a single re-poll so the
    // icon follows the active uplink quickly.
    readonly property Process _monitor: Process {
        running: true
        command: ["busctl", "--system", "monitor", "net.connman.iwd"]
        stdout: SplitParser { onRead: net._debounce.restart() }
    }
    readonly property Timer _debounce: Timer {
        interval: 350
        onTriggered: net._poll.running = true
    }

    function refresh() { _poll.running = true }

    function _ingest(raw) {
        try {
            const text = raw || ""
            // Split the busctl JSON blob from the ip route/addr sections.
            const objStart = text.indexOf("@@OBJ@@")
            const routeStart = text.indexOf("@@ROUTE@@")
            const addrStart = text.indexOf("@@ADDR@@")
            const linkStart = text.indexOf("@@LINK@@")
            const objJson = text.substring(objStart + 7, routeStart).trim()
            const routeBlock = text.substring(routeStart + 9, addrStart)
            const addrBlock = text.substring(addrStart + 8, linkStart)
            const linkBlock = text.substring(linkStart + 8)

            // ---- iwd object tree -------------------------------------------
            let stationPath = "", wifiDev = "", stationState = "",
                connectedNetPath = "", radioOn = true, scanningNow = false
            const netByPath = {}       // path -> { ssid, type, connected, known }
            const savedSet = {}

            if (objJson.length) {
                const parsed = JSON.parse(objJson)
                const tree = (parsed.data && parsed.data[0]) || {}
                for (const path in tree) {
                    const ifaces = tree[path]
                    const dev = ifaces["net.connman.iwd.Device"]
                    const sta = ifaces["net.connman.iwd.Station"]
                    const nw  = ifaces["net.connman.iwd.Network"]
                    const kn  = ifaces["net.connman.iwd.KnownNetwork"]

                    if (dev) {
                        // The station device (Mode station) owns the radio power
                        // flag and is the path we issue iwctl actions against.
                        if (!sta && dev.Mode && dev.Mode.data !== "station") {
                            // non-station device — ignore
                        }
                        if (sta || (dev.Mode && dev.Mode.data === "station")) {
                            wifiDev = dev.Name ? dev.Name.data : wifiDev
                            if (dev.Powered) radioOn = dev.Powered.data
                        }
                    }
                    if (sta) {
                        stationPath = path
                        stationState = sta.State ? sta.State.data : ""
                        scanningNow = sta.Scanning ? sta.Scanning.data : false
                        connectedNetPath = sta.ConnectedNetwork ? sta.ConnectedNetwork.data : ""
                    }
                    if (nw) {
                        netByPath[path] = {
                            ssid: nw.Name ? nw.Name.data : "",
                            type: nw.Type ? nw.Type.data : "open",
                            connected: nw.Connected ? nw.Connected.data : false,
                            known: !!(nw.KnownNetwork && nw.KnownNetwork.data &&
                                      nw.KnownNetwork.data !== "/")
                        }
                    }
                    if (kn && kn.Name) savedSet[kn.Name.data] = true
                }
            }

            if (wifiDev.length) _wifiDev = wifiDev
            _stationPath = stationPath
            wifiEnabled = radioOn
            scanning = scanningNow

            // saved ("known") network names
            const savedList = []
            for (const nm in savedSet) savedList.push(nm)
            savedNames = savedList

            // wifi list from Network objects. Signal merged later by GetOrderedNetworks;
            // seed each entry's signal from the last RSSI map so the bars don't blank.
            const list = []
            const connectedSsid = (connectedNetPath && netByPath[connectedNetPath])
                ? netByPath[connectedNetPath].ssid : ""
            for (const p in netByPath) {
                const n = netByPath[p]
                if (!n.ssid.length) continue
                const rssi = _rssiByPath[p]
                list.push({
                    _path:   p,
                    ssid:    n.ssid,
                    signal:  rssi !== undefined ? _rssiToPercent(rssi) : 0,
                    secured: n.type !== "open",
                    enterprise: n.type === "8021x",
                    active:  n.connected,
                    saved:   n.known || savedList.indexOf(n.ssid) !== -1
                })
            }
            list.sort(function(a, b) {
                if (a.active !== b.active) return a.active ? -1 : 1
                return b.signal - a.signal
            })
            networks = list

            const wifiConnected = (stationState === "connected" && connectedSsid.length)

            // ---- default route + local address (backend-neutral) -----------
            const routes = routeBlock.split("\n")
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

            const addrs = addrBlock.split("\n")
            const devIp = {}
            for (let a = 0; a < addrs.length; a++) {
                const t = addrs[a].trim().split(/\s+/)
                if (t.length < 4 || t[2] !== "inet") continue
                const dev = t[1]
                const ip  = t[3].split("/")[0]
                if (devIp[dev] === undefined) devIp[dev] = ip
            }

            // wired NIC discovery from `ip -o link show`. Lines look like:
            //   3: enp197s0f4u1u1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ...
            // The flags carry admin state (UP) and carrier (LOWER_UP). Track the
            // first en* device so the override toggle has a target even when the
            // link is down (no IP / no route to infer it from).
            const links = linkBlock.split("\n")
            let ethDev = "", ethAdminUp = false, ethCarrier = false
            for (let l = 0; l < links.length; l++) {
                const m = links[l].trim().match(/^\d+:\s+([^:@\s]+)(?:@\S+)?:\s+<([^>]*)>/)
                if (!m) continue
                const name = m[1]
                if (!/^en/.test(name)) continue   // physical ethernet only
                const flags = m[2].split(",")
                ethDev = name
                ethAdminUp = flags.indexOf("UP") !== -1
                ethCarrier = flags.indexOf("LOWER_UP") !== -1
                break
            }
            _ethDev = ethDev
            ethernetPresent = ethDev.length > 0
            ethernetEnabled = ethAdminUp
            ethernetPlugged = ethCarrier

            // An ethernet uplink = a default-route device that isn't the wifi
            // station and isn't a virtual link (wl*, tailscale, lo). networkd
            // gives the wired NIC a lower route metric, so a plugged cable wins.
            const isWired = routeDev && routeDev !== _wifiDev
                && !/^(wl|lo|tailscale|docker|veth|virbr|tun)/.test(routeDev)
            ethernetUp = !!isWired

            // ---- fold into the primary-link summary ------------------------
            if (isWired) {
                primaryType = "ethernet"; connected = true
                primaryName = routeDev
                localIp = devIp[routeDev] || ""
            } else if (wifiConnected) {
                primaryType = "wifi"; connected = true
                primaryName = connectedSsid
                localIp = devIp[_wifiDev] || (routeDev ? (devIp[routeDev] || "") : "")
                // wifiSignal is set from the connected entry; GetOrderedNetworks refines it.
                for (let i = 0; i < list.length; i++)
                    if (list[i].active) { wifiSignal = list[i].signal; break }
            } else {
                primaryType = "none"; connected = false
                primaryName = ""; localIp = ""; wifiSignal = 0
            }

            // refine RSSI for the network list + connected AP
            if (_stationPath.length && !_signalPoll.running) {
                _signalPoll.command = ["busctl", "--system", "call",
                    "net.connman.iwd", _stationPath,
                    "net.connman.iwd.Station", "GetOrderedNetworks"]
                _signalPoll.running = true
            }
        } catch (e) {
            // malformed read — leave prior state, next tick recovers
        }
    }

    // Merge Station.GetOrderedNetworks output:  a(on) <count> "<path>" <rssi> ...
    function _ingestSignals(raw) {
        try {
            const text = raw || ""
            const re = /"(\/net\/connman\/iwd\/[^"]+)"\s+(-?\d+)/g
            const map = {}
            let m
            while ((m = re.exec(text)) !== null) map[m[1]] = parseInt(m[2])
            _rssiByPath = map

            // re-apply onto the current list without re-polling iwd
            const list = networks.slice()
            let changed = false
            for (let i = 0; i < list.length; i++) {
                const rssi = map[list[i]._path]
                if (rssi === undefined) continue
                const pct = _rssiToPercent(rssi)
                if (list[i].signal !== pct) { list[i].signal = pct; changed = true }
                if (list[i].active) wifiSignal = pct
            }
            if (changed) networks = list
        } catch (e) {
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

    // Connect to a wifi network via iwctl. Open or already-saved (known)
    // networks need no passphrase; secured + unknown ones take one inline.
    // 802.1X (enterprise) connects use the provisioning file in /var/lib/iwd —
    // the flyout routes brand-new enterprise setups to a terminal instead.
    function connectWifi(ssid, secured, password) {
        if (!secured || isSaved(ssid) || !password || !password.length)
            _run(["iwctl", "station", _wifiDev, "connect", ssid])
        else
            _run(["iwctl", "--passphrase", password, "station", _wifiDev, "connect", ssid])
    }
    function disconnectWifi() {
        _run(["iwctl", "station", _wifiDev, "disconnect"])
    }
    function forget(ssid) { _run(["iwctl", "known-networks", ssid, "forget"]) }

    function setWifiEnabled(on) {
        Quickshell.execDetached(["iwctl", "device", _wifiDev, "set-property",
                                 "Powered", on ? "on" : "off"])
        wifiEnabled = on
        rescanTimer.restart()
    }
    function toggleWifi() { setWifiEnabled(!wifiEnabled) }

    // Manual wired override: bring the networkd-managed link admin up/down. A
    // polkit rule (org.freedesktop.network1.manage-links) lets the active
    // session do this without a password. Downing the cable hands the default
    // route back to wifi; upping it re-runs DHCP and the low metric wins again.
    function setEthernetEnabled(on) {
        if (!_ethDev.length) return
        Quickshell.execDetached(["networkctl", on ? "up" : "down", _ethDev])
        ethernetEnabled = on
        _ethTimer.restart()
    }
    function toggleEthernet() { setEthernetEnabled(!ethernetEnabled) }
    readonly property Timer _ethTimer: Timer {
        interval: 1500    // give networkd time to (de)configure, then re-poll
        onTriggered: net.refresh()
    }

    function rescan() {
        scanning = true
        Quickshell.execDetached(["iwctl", "station", _wifiDev, "scan"])
        rescanTimer.restart()
    }
    readonly property Timer _rescanTimer: Timer {
        id: rescanTimer
        interval: 2500
        onTriggered: { net.scanning = false; net.refresh() }
    }
}
