// ~/.config/quickshell/bars/SystemMonitor.qml
// Combined system-monitor widget for the SideBar.
//
// • The compact pill (icon + mini-bar + percent ×4) lives in the sidebar column.
// • The detail popover overflows to the right of the sidebar; it's drawn from
//   the same QML Item (positioned at x = pillWidth + popoverGap) but its bounds
//   exceed the pill's, so the sidebar's `mask` must include the popover region
//   while `popoverVisible` is true.
// • Click anywhere on the pill or popover launches `alacritty -e btop` to match
//   the prior waybar behaviour the user wants preserved.

import QtQuick
import Quickshell
import "../services" as Services

Item {
    id: root

    // ---- public API ---------------------------------------------------------
    property int pillWidth: 56
    property int popoverWidth: 380
    property int popoverGap: 10            // px between pill and popover
    property real ui: 1.0                  // per-monitor scale (set by SideBar)

    // Y offset of the popover relative to this Item's origin (for the mask)
    readonly property int popoverLocalY: popover.y
    readonly property int popoverHeight: popover.height
    readonly property int popoverHeightMax: 280  // initial guess; updates after layout
    // True while the user is interacting with either pill or popover. Includes
    // a brief debounce so cursor traversal across the gap doesn't flicker it.
    property bool popoverVisible: false

    implicitWidth: pillWidth
    implicitHeight: pill.implicitHeight
    clip: false

    // ---- hover bookkeeping --------------------------------------------------
    readonly property bool _anyHover: pillHover.hovered || popoverHover.hovered
    on_AnyHoverChanged: {
        if (_anyHover) {
            hideTimer.stop()
            popoverVisible = true
        } else {
            hideTimer.restart()
        }
    }
    Timer {
        id: hideTimer
        interval: 180
        repeat: false
        onTriggered: if (!root._anyHover) root.popoverVisible = false
    }

    // ---- click handler (shared launcher) ------------------------------------
    function launchBtop() { Quickshell.execDetached(["alacritty", "-e", "btop"]) }

    // Color tokens, one per category — cool indigo→blue→cyan→teal ramp.
    readonly property color cpuColor:  "#5b6ee0"   // indigo (hero)
    readonly property color memColor:  "#60a5fa"   // blue
    readonly property color gpuColor:  "#22d3ee"   // cyan
    readonly property color diskColor: "#2dd4bf"   // teal

    readonly property var s: Services.SysStats

    // =========================================================================
    //  COMPACT PILL
    // =========================================================================
    Rectangle {
        id: pill
        x: 0
        y: 0
        width: root.pillWidth
        implicitHeight: pillCol.implicitHeight + 18 * root.ui
        radius: 16
        color: Qt.rgba(1, 1, 1, pillHover.hovered ? 0.07 : 0.04)
        border.color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        Behavior on color { ColorAnimation { duration: 160 } }

        HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.launchBtop() }

        Column {
            id: pillCol
            anchors.centerIn: parent
            spacing: 8 * root.ui
            width: parent.width - 12

            Repeater {
                model: [
                    { glyph: "󰍛", pct: root.s.cpuPct,  c: root.cpuColor  },
                    { glyph: "󰘚", pct: root.s.memPct,  c: root.memColor  },
                    { glyph: "󰢮", pct: root.s.gpuPct,  c: root.gpuColor  },
                    { glyph: "󰋊", pct: root.s.diskPct, c: root.diskColor }
                ]
                delegate: Item {
                    width: pillCol.width
                    height: 26 * root.ui

                    Text {
                        id: glyph
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.glyph
                        color: modelData.c
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 17 * root.ui
                    }

                    Rectangle {
                        anchors.left: glyph.right
                        anchors.leftMargin: 4
                        anchors.right: pctLabel.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        height: 3
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.10)

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * Math.max(0, Math.min(100, modelData.pct)) / 100
                            radius: parent.radius
                            color: modelData.c
                            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }
                    }

                    Text {
                        id: pctLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.pct
                        color: "#e5e7eb"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12 * root.ui
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignRight
                        width: 18 * root.ui
                    }
                }
            }
        }
    }

    // =========================================================================
    //  HOVER POPOVER
    // =========================================================================
    Rectangle {
        id: popover
        x: pill.width + root.popoverGap
        y: (pill.height - height) / 2
        width: root.popoverWidth
        height: popoverCol.implicitHeight + 28
        radius: 18
        color: Qt.rgba(0.06, 0.07, 0.10, 0.96)
        border.color: Qt.rgba(1, 1, 1, 0.07)
        border.width: 1

        opacity: root.popoverVisible ? 1 : 0
        visible: opacity > 0.01
        scale: root.popoverVisible ? 1.0 : 0.97
        transformOrigin: Item.Left
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
        Behavior on scale   { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        HoverHandler { id: popoverHover }
        TapHandler { onTapped: root.launchBtop() }

        Column {
            id: popoverCol
            anchors.centerIn: parent
            spacing: 16
            width: parent.width - 28

            Text {
                text: "SYSTEM MONITOR"
                color: "#6b7280"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                font.weight: Font.Medium
                font.letterSpacing: 1.6
            }

            component DetailRow : Column {
                id: blk
                width: popoverCol.width
                spacing: 6

                property string title: ""
                property string sub:   ""
                property int    pct:   0
                property color  tint:  "#5b6ee0"
                property var    facts: []

                Item {
                    width: blk.width
                    height: 18
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: blk.sub.length > 0 ? (blk.title + " · " + blk.sub) : blk.title
                        color: "#f4f4f6"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        width: parent.width - 50
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: blk.pct + "%"
                        color: blk.tint
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    width: blk.width
                    height: 4
                    radius: 2
                    color: Qt.rgba(1, 1, 1, 0.07)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * Math.max(0, Math.min(100, blk.pct)) / 100
                        radius: parent.radius
                        color: blk.tint
                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    }
                }

                Text {
                    width: blk.width
                    text: blk.facts.filter(function(s){ return s && s.length > 0 }).join("   ")
                    color: "#8e8e96"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            DetailRow {
                title: "CPU"
                sub:   root.s.cpuModel
                pct:   root.s.cpuPct
                tint:  root.cpuColor
                facts: [ root.s.cpuFreq, root.s.cpuTemp, root.s.cpuThreads ]
            }
            DetailRow {
                title: "Memory"
                sub:   root.s.memTotal
                pct:   root.s.memPct
                tint:  root.memColor
                facts: [ root.s.memUsed, root.s.memRate ]
            }
            DetailRow {
                title: "GPU"
                sub:   root.s.gpuModel
                pct:   root.s.gpuPct
                tint:  root.gpuColor
                facts: [ root.s.gpuFreq, root.s.gpuTemp, root.s.gpuVram ]
            }
            DetailRow {
                title: "Disk"
                sub:   root.s.diskMount + (root.s.diskSource ? " (" + root.s.diskSource + ")" : "")
                pct:   root.s.diskPct
                tint:  root.diskColor
                facts: [ root.s.diskUsed, root.s.diskFs, root.s.diskKind ]
            }
        }
    }
}
