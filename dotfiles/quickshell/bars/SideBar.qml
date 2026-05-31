// ~/.config/quickshell/bars/SideBar.qml
// Left-edge vertical sidebar. One PanelWindow per output, anchored {left, top,
// bottom}. The window is wider than the visible sidebar so the SystemMonitor's
// hover popover can overflow rightward without being clipped; `exclusiveZone`
// still reserves only the 72px column. The `mask` region restricts input to
// the visible parts, expanding to include the popover area while it's open.
//
// Modules, top → bottom:
//   archlogo · workspace dots (per output) · app dock · launcher
//   SystemMonitor · clock pill · volume · power
//
// Per CLAUDE.md: no battery indicator.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../services" as Services

Scope {
    id: root

    // Pill width and the gap between the pill and each screen edge it faces.
    readonly property int sidebarW: 72
    readonly property int edgeGap:  8

    // ---- clock --------------------------------------------------------------
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
    // 12-hour clock per project convention (see CLAUDE.md §0).
    // AM/PM rides next to the time in a smaller font; the date sits alone
    // underneath so neither line crowds the 56-px pill.
    readonly property string timeStr: {
        const h12 = (clock.hours % 12) || 12
        const m   = (clock.minutes < 10 ? "0" : "") + clock.minutes
        return h12 + ":" + m
    }
    readonly property string meridiemStr: clock.hours >= 12 ? "PM" : "AM"
    readonly property string dateStr: {
        const day  = Qt.formatDate(clock.date, "ddd").toUpperCase()
        const dd   = Qt.formatDate(clock.date, "dd")
        return day + " " + dd
    }

    // ---- volume (wpctl-driven; ~4 polls/s + immediate nudge on scroll) ------
    property int volPct: 0
    property bool volMuted: false
    Process {
        id: volProbe
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo 'Volume: 0.0'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = (this.text || "").trim()
                root.volMuted = t.indexOf("[MUTED]") !== -1
                const m = t.match(/Volume: ([0-9.]+)/)
                root.volPct = m ? Math.round(parseFloat(m[1]) * 100) : 0
            }
        }
    }
    Timer {
        interval: 250
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: volProbe.running = true
    }
    // Re-fires the probe ~40ms after a wpctl change so the popover snaps to
    // the new value instead of waiting up to a full poll interval.
    Timer {
        id: volRefetch
        interval: 40
        repeat: false
        onTriggered: volProbe.running = true
    }
    // Apply a volume delta and immediately re-probe.
    function bumpVolume(arg) {
        Quickshell.execDetached(["sh", "-c",
            "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ " + arg])
        volRefetch.restart()
    }
    readonly property string volGlyph: {
        if (volMuted) return "󰸈"
        if (volPct < 34) return "󰕿"
        if (volPct < 67) return "󰖀"
        return "󰕾"
    }

    // ---- niri workspaces (poll every 500ms) ---------------------------------
    property var workspaces: []
    Process {
        id: wsProbe
        command: ["niri", "msg", "--json", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.workspaces = JSON.parse(this.text || "[]") }
                catch (e) { root.workspaces = [] }
            }
        }
    }
    Timer {
        interval: 500
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: wsProbe.running = true
    }

    // ---- launch helpers -----------------------------------------------------
    function launch(bin) {
        Quickshell.execDetached(["app-launch", bin])
    }
    function launchShell(cmd) {
        Quickshell.execDetached(["sh", "-c", cmd])
    }

    // =========================================================================
    //  One PanelWindow per screen
    // =========================================================================
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            // Per-monitor UI scale: 1.0 on 1440px-tall (and taller) screens,
            // shrinking on shorter ones (~0.8 at 1080p) so the fixed-size top /
            // dock / bottom groups don't collide on lower-resolution monitors.
            readonly property real ui: Math.max(0.66, Math.min(1.0, height / 1350))

            anchors { left: true; top: true; bottom: true }
            // Reserve the pill width plus the left-edge gap so windows don't
            // hug the screen edge underneath the floating sidebar.
            exclusiveZone: root.sidebarW + root.edgeGap
            color: "transparent"
            implicitWidth: 520
            WlrLayershell.namespace: "quickshell-sidebar"
            WlrLayershell.layer: WlrLayer.Top

            // Sidebar column (always visible). Popover region added dynamically
            // while it's open so the cursor can reach it and clicks land.
            mask: Region {
                x: root.edgeGap; y: root.edgeGap
                width: root.sidebarW
                height: win.height - 2 * root.edgeGap

                Region {
                    intersection: Intersection.Combine
                    x: root.edgeGap + root.sidebarW - 4
                    y: sysmonStack.y + sysmon.popoverLocalY - 8
                    width:  sysmon.popoverVisible
                            ? (win.width - root.edgeGap - root.sidebarW + 4) : 0
                    height: sysmon.popoverVisible ? sysmon.popoverHeight + 16 : 0
                }
            }

            // ---- the visible sidebar pill ---------------------------------
            // Floats: inset by edgeGap on the left/top/bottom so all four
            // corners can be fully rounded.
            Rectangle {
                id: sidebar
                x: root.edgeGap
                y: root.edgeGap
                width: root.sidebarW
                height: parent.height - 2 * root.edgeGap
                color: Qt.rgba(0.055, 0.058, 0.082, 0.78)
                radius: 22
                border.color: Qt.rgba(1, 1, 1, 0.05)
                border.width: 1

                // ---- top: archlogo + workspaces -----------------------------
                Column {
                    id: topCol
                    property real ui: win.ui
                    anchors.top: parent.top
                    anchors.topMargin: 10 * win.ui
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10 * win.ui
                    width: parent.width - 12

                    IconButton {
                        glyph: "\uF303"   // arch logo
                        tint: "#67e8f9"
                        onActivated: root.launchShell("fastfetch-popup")
                    }

                    // Per-output workspace dots
                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 7 * win.ui
                        Repeater {
                            model: {
                                const out = []
                                const ws = root.workspaces || []
                                for (let i = 0; i < ws.length; i++) {
                                    if (ws[i] && ws[i].output === win.modelData.name)
                                        out.push(ws[i])
                                }
                                out.sort(function(a, b) { return (a.idx || 0) - (b.idx || 0) })
                                return out
                            }
                            delegate: Item {
                                required property var modelData
                                width: 14
                                height: 18 * win.ui

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: modelData.is_focused ? 4 : 6
                                    height: (modelData.is_focused ? 16 : 6) * win.ui
                                    radius: width / 2
                                    color: modelData.is_focused ? "#c4b5fd"
                                          : modelData.is_active ? Qt.rgba(1, 1, 1, 0.55)
                                          : Qt.rgba(1, 1, 1, 0.25)
                                    Behavior on height { NumberAnimation { duration: 160 } }
                                    Behavior on width  { NumberAnimation { duration: 160 } }
                                    Behavior on color  { ColorAnimation  { duration: 160 } }
                                }
                                TapHandler {
                                    onTapped: root.launchShell(
                                        "niri msg action focus-workspace " + modelData.id)
                                }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                        }
                    }
                }

                // ---- middle: app dock + launcher -----------------------------
                Column {
                    id: dock
                    property real ui: win.ui
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4 * win.ui
                    width: parent.width - 12

                    IconButton { glyph: "\uF268";   tint: "#f87171"; onActivated: root.launch("google-chrome-stable") }
                    IconButton { glyph: "\uF1BC";   tint: "#4ade80"; onActivated: root.launch("spotify") }
                    IconButton { glyph: "\uF120";   tint: "#d8b4fe"; onActivated: root.launch("alacritty") }
                    IconButton { glyph: "󰙯";  tint: "#a5b4fc"; onActivated: root.launch("discord") }
                    IconButton { glyph: "\uF232";   tint: "#86efac"; onActivated: root.launch("whatsapp-web") }
                    IconButton { glyph: "\uF1B6";   tint: "#93c5fd"; onActivated: root.launch("steam") }
                    IconButton {
                        glyph: "\uF00A"; tint: "#facc15"
                        onActivated: root.launchShell("qs ipc call launcher toggle")
                    }
                }
            }

            // ---- bottom stack: sysmon, clock, volume, power ----------------
            // Lives at the same Z as the sidebar Rectangle (sibling), so the
            // SystemMonitor popover can overflow rightward without being
            // clipped by the sidebar pill.
            Column {
                id: sysmonStack
                property real ui: win.ui
                x: root.edgeGap + (root.sidebarW - width) / 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14 * win.ui + root.edgeGap
                width: root.sidebarW - 16
                spacing: 10 * win.ui

                SystemMonitor {
                    id: sysmon
                    ui: win.ui
                    pillWidth: root.sidebarW - 16
                    popoverWidth: 380
                    popoverGap: 12
                }

                // Clock pill
                Rectangle {
                    id: clockPill
                    width: parent.width
                    height: 56 * win.ui
                    radius: 14
                    color: Qt.rgba(1, 1, 1, clockHover.hovered ? 0.07 : 0.04)
                    border.color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 160 } }
                    HoverHandler { id: clockHover }

                    // Three stacked centered lines: time, meridiem (tiny), date.
                    // AM/PM lives on its own row under the time so the time row
                    // stays pure digits and can't overrun the pill width.
                    Column {
                        anchors.centerIn: parent
                        spacing: 0

                        Text {
                            text: root.timeStr
                            color: "#e5e7eb"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 18 * win.ui
                            font.weight: Font.DemiBold
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: root.meridiemStr
                            color: "#8e8e96"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 8 * win.ui
                            font.weight: Font.Medium
                            font.letterSpacing: 1.0
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: root.dateStr
                            color: "#8e8e96"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9 * win.ui
                            font.letterSpacing: 0.5
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                // Network status — glyph swaps wifi⇄ethernet from the Network
                // service; click opens the manager flyout (qs ipc → network).
                IconButton {
                    glyph: Services.Network.glyph || "󰤯"
                    tint: Services.Network.connected ? "#a5d8ff"
                         : Services.Network.wifiEnabled ? "#8e8e96" : "#6b7280"
                    onActivated: root.launchShell("qs ipc call network toggle")
                }

                IconButton {
                    id: volBtn
                    glyph: root.volGlyph
                    tint: root.volMuted ? "#6b7280" : "#60a5fa"
                    onActivated: root.launchShell("pavucontrol")
                    onScrolledUp:   root.bumpVolume("2%+")
                    onScrolledDown: root.bumpVolume("2%-")
                }

                IconButton {
                    glyph: "\uF011"
                    tint: "#f43f5e"
                    onActivated: root.launchShell("power-menu")
                }
            }

            // ---- volume hover popover ------------------------------------
            // Floating tooltip-style readout. Rendered outside the mask
            // (so the cursor leaving the button \u2192 popover gap dismisses it
            // naturally \u2014 pure info surface, not interactive).
            Rectangle {
                id: volPop
                width: 168
                height: volPopCol.implicitHeight + 20
                x: root.edgeGap + root.sidebarW + 10
                y: sysmonStack.y + volBtn.y + (volBtn.height - height) / 2
                radius: 14
                color: Qt.rgba(0.06, 0.07, 0.10, 0.96)
                border.color: Qt.rgba(1, 1, 1, 0.07)
                border.width: 1
                opacity: volBtn.hovered ? 1 : 0
                visible: opacity > 0.01
                scale: volBtn.hovered ? 1.0 : 0.96
                transformOrigin: Item.Left
                Behavior on opacity { NumberAnimation { duration: 160 } }
                Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                Column {
                    id: volPopCol
                    anchors.centerIn: parent
                    spacing: 8
                    width: parent.width - 20

                    Item {
                        width: volPopCol.width
                        height: 16
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.volMuted ? "Muted" : "Volume"
                            color: "#f4f4f6"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.volPct + "%"
                            color: root.volMuted ? "#6b7280" : "#60a5fa"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }

                    Rectangle {
                        width: volPopCol.width
                        height: 4
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.10)
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * Math.max(0, Math.min(100, root.volPct)) / 100
                            radius: parent.radius
                            color: root.volMuted ? "#6b7280" : "#60a5fa"
                            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    //  Inline IconButton — single nerd-font glyph with hover glow + press scale.
    //  Note: `tint` (not `color`) is used because Rectangle already has a
    //  `color` property which we use for the hover background.
    // =========================================================================
    component IconButton : Rectangle {
        id: btn
        property string glyph: ""
        property color  tint: "#e5e7eb"
        // Exposed for callers that want to react to hover (e.g. volume tooltip).
        readonly property bool hovered: hh.hovered
        signal activated()
        // Vertical-wheel scroll deltas. Consumers wire these only where wheel
        // input makes sense (volume); for the rest, the signals are inert.
        signal scrolledUp()
        signal scrolledDown()

        // `ui` inherits the per-monitor scale from the parent column (topCol /
        // dock / sysmonStack each expose it); falls back to 1.0 if absent.
        property real ui: (parent && parent.ui !== undefined) ? parent.ui : 1.0
        width: root.sidebarW - 12
        height: 48 * ui
        radius: 14 * ui
        color: Qt.rgba(1, 1, 1, hh.hovered ? 0.08 : 0.0)
        scale: tap.pressed ? 0.92 : (hh.hovered ? 1.05 : 1.0)
        antialiasing: true

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

        Text {
            anchors.centerIn: parent
            text: btn.glyph
            color: btn.tint
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 24 * btn.ui
        }

        HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
        TapHandler   { id: tap; onTapped: btn.activated() }
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                if (event.angleDelta.y > 0)      btn.scrolledUp()
                else if (event.angleDelta.y < 0) btn.scrolledDown()
                event.accepted = true
            }
        }
    }
}
