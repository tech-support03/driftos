// ~/.config/quickshell/bars/SideBar.qml
// Left-edge vertical sidebar. One PanelWindow per output, anchored {left, top,
// bottom}. The window is wider than the visible sidebar so the SystemMonitor's
// hover popover can overflow rightward without being clipped; `exclusiveZone`
// still reserves only the 72px column. The `mask` region restricts input to
// the visible parts, expanding to include the popover area while it's open.
//
// Modules, top → bottom:
//   archlogo · workspace dots (per output) · app dock · launcher
//   SystemMonitor · clock pill · network · volume · battery · power
//
// Battery pill is laptop-only: Services.Battery self-gates on a real BAT*
// node, so the desktop install keeps CLAUDE.md's "no battery indicator".

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../services" as Services
import "../theme"

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

    // ---- volume -------------------------------------------------------------
    // Owned by the Services.Audio singleton (single wpctl poller, shared with
    // the VolumeOSD overlay). The button below binds to it and scroll-nudges
    // via Audio.setVolume; the OSD pops itself off Audio's bumped() signal.

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
                // Opaque in the light profile (no translucency to composite).
                color: Qt.rgba(0.055, 0.058, 0.082, Services.Profile.light ? 1.0 : 0.78)
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
                        tint: Theme.accent
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
                                    color: modelData.is_focused ? Theme.accent
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

                    IconButton {
                        glyph: Services.Profile.light ? "\uF269" : "\uF268"
                        tint:  Services.Profile.light ? "#fb923c" : "#f87171"
                        onActivated: root.launch(Services.Profile.light ? "firefox" : "google-chrome-stable")
                    }
                    IconButton { glyph: "\uF1BC";   tint: "#4ade80"; onActivated: root.launch("spotify") }
                    IconButton { glyph: "\uF120";   tint: Theme.accent; onActivated: root.launch("alacritty") }
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
                    tint: Services.Network.connected ? Theme.blue
                         : Services.Network.wifiEnabled ? "#8e8e96" : "#6b7280"
                    onActivated: root.launchShell("qs ipc call network toggle")
                }

                // Bluetooth — its own pill widget under the network button (like
                // the clock / battery pills): glyph tier + a short status line
                // (connected device name · "On" · "Off"). Click opens the manager
                // flyout (qs ipc → bluetooth). Self-gates on a real controller, so
                // a desktop with no BT adapter hides it (same idiom as battPill).
                Rectangle {
                    id: btPill
                    visible: Services.Bluetooth.available
                    width: parent.width
                    height: 50 * win.ui
                    radius: 14
                    color: Qt.rgba(1, 1, 1, btHover.hovered ? 0.07 : 0.04)
                    border.color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 160 } }
                    HoverHandler { id: btHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.launchShell("qs ipc call bluetooth toggle") }

                    readonly property color accentTint: Services.Bluetooth.connectedCount > 0 ? Theme.blue
                                                       : Services.Bluetooth.powered ? "#e5e7eb"
                                                       : "#6b7280"
                    // One-word/short status under the glyph. A single connected
                    // device shows its (ellipsized) name; otherwise on/off state.
                    readonly property string label: {
                        const c = Services.Bluetooth.connectedCount
                        if (c === 1) return Services.Bluetooth.connectedName
                        if (c > 1)   return c + " dev"
                        return Services.Bluetooth.powered ? "On" : "Off"
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 1
                        width: parent.width - 8

                        Text {
                            text: Services.Bluetooth.glyph
                            color: btPill.accentTint
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 19 * win.ui
                            anchors.horizontalCenter: parent.horizontalCenter
                            Behavior on color { ColorAnimation { duration: 160 } }
                        }
                        Text {
                            text: btPill.label
                            color: btPill.accentTint
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9 * win.ui
                            font.weight: Font.DemiBold
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: 160 } }
                        }
                    }
                }

                IconButton {
                    glyph: Services.Audio.glyph
                    tint: Services.Audio.muted ? "#6b7280" : Theme.blue
                    onActivated: root.launchShell("pavucontrol")
                    onScrolledUp:   Services.Audio.setVolume("2%+")
                    onScrolledDown: Services.Audio.setVolume("2%-")
                }

                // Battery \u2014 laptop only. Self-gates on a real BAT* node so the
                // desktop install keeps the spec's "no battery indicator". Glyph
                // tier + percent always shown; tint warns on low / charging.
                Rectangle {
                    id: battPill
                    visible: Services.Battery.present
                    width: parent.width
                    height: 50 * win.ui
                    radius: 14
                    color: Qt.rgba(1, 1, 1, battHover.hovered ? 0.07 : 0.04)
                    border.color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 160 } }
                    HoverHandler { id: battHover; cursorShape: Qt.PointingHandCursor }
                    // Click opens the same flyout as the power button below.
                    TapHandler { onTapped: root.launchShell("qs ipc call power toggle") }

                    readonly property color accentTint: Services.Battery.low ? "#f43f5e"
                                                       : Services.Battery.charging ? "#4ade80"
                                                       : "#e5e7eb"

                    Column {
                        anchors.centerIn: parent
                        spacing: 1

                        Text {
                            text: Services.Battery.glyph
                            color: battPill.accentTint
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 19 * win.ui
                            anchors.horizontalCenter: parent.horizontalCenter
                            Behavior on color { ColorAnimation { duration: 160 } }
                        }
                        Text {
                            text: Services.Battery.percent + "%"
                            color: battPill.accentTint
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11 * win.ui
                            font.weight: Font.DemiBold
                            anchors.horizontalCenter: parent.horizontalCenter
                            Behavior on color { ColorAnimation { duration: 160 } }
                        }
                    }
                }

                IconButton {
                    glyph: "\uF011"
                    tint: "#f43f5e"
                    // Same flyout as Mod+Escape (PowerFlyout's "power" IPC).
                    onActivated: root.launchShell("qs ipc call power toggle")
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
