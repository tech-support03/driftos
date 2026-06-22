// ~/.config/quickshell/bars/BatteryFlyout.qml
// Hover flyout for the SideBar's battery pill. Mirrors the visual + animation
// idiom of SystemMonitor.qml's `popover`: a translucent dark card that overflows
// to the RIGHT of the sidebar, fading + scaling in from its left edge.
//
// Drop-in API (integration is wired by the trigger widget):
//   • `show`  — bool, driven by the pill's hover state
//   • `ui`    — per-monitor UI scale
//   • positions itself at `parent.width + 12*ui`, vertically centered
//
// Content: the live charge percentage (tinted with the same low/charging logic
// as battPill.accentTint) plus a human time estimate from Services.Battery.

import QtQuick
import "../services" as Services
import "../theme"

Rectangle {
    id: root

    property bool show: false        // driven externally by the trigger's hover
    property real ui: 1.0            // per-monitor UI scale

    x: parent.width + 12 * ui
    anchors.verticalCenter: parent.verticalCenter

    width: 190 * ui
    height: col.implicitHeight + 28 * ui
    radius: 16
    color: Qt.rgba(0.06, 0.07, 0.10, 0.96)
    border.color: Qt.rgba(1, 1, 1, 0.07)
    border.width: 1

    opacity: show ? 1 : 0
    visible: opacity > 0.01
    scale: show ? 1.0 : 0.97
    transformOrigin: Item.Left
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
    Behavior on scale   { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    // Same tint ramp as battPill.accentTint in SideBar.qml.
    readonly property color accentTint: Services.Battery.low ? "#f43f5e"
                                       : Services.Battery.charging ? "#4ade80"
                                       : "#e5e7eb"

    Column {
        id: col
        anchors.centerIn: parent
        spacing: 6 * ui
        width: parent.width - 28 * ui

        Text {
            text: "BATTERY"
            color: "#6b7280"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9 * ui
            font.weight: Font.Medium
            font.letterSpacing: 1.6
        }

        Text {
            text: Services.Battery.percent + "%"
            color: root.accentTint
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 26 * ui
            font.weight: Font.DemiBold
            Behavior on color { ColorAnimation { duration: 160 } }
        }

        Text {
            width: col.width
            text: {
                if (Services.Battery.charging) {
                    if (Services.Battery.status === "Full") return "Fully charged"
                    return Services.Battery.timeRemaining.length
                        ? (Services.Battery.timeRemaining + " to full")
                        : "Charging"
                }
                return Services.Battery.timeRemaining.length
                    ? (Services.Battery.timeRemaining + " remaining")
                    : "Calculating…"
            }
            color: "#8e8e96"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11 * ui
            elide: Text.ElideRight
        }
    }
}
