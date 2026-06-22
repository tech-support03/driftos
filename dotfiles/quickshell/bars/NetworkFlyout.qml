// ~/.config/quickshell/bars/NetworkFlyout.qml
// Hover flyout for the SideBar's network button. Plain-text readout of the
// active uplink: connection TYPE (Wi-Fi / Ethernet), NAME (SSID / wired conn),
// and the local IPv4 ADDRESS. Driven entirely off the Network singleton.
//
// Visual + animation idiom mirrors SystemMonitor's hover popover: translucent
// dark surface, opacity+scale show animation anchored to the left edge. The
// `show` flag and `ui` scale are set by the trigger widget (wired separately).

import QtQuick
import "../services" as Services
import "../theme"

Rectangle {
    id: root

    property bool show: false      // driven externally by the trigger's hover
    property real ui:   1.0        // per-monitor UI scale

    // Sit to the right of the sidebar button, vertically centered on it.
    x: parent.width + 12 * ui
    anchors.verticalCenter: parent.verticalCenter

    width: 210 * ui
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

    // TYPE label from the primary-link summary.
    readonly property string typeStr: {
        if (Services.Network.primaryType === "wifi")     return "Wi-Fi"
        if (Services.Network.primaryType === "ethernet") return "Ethernet"
        return "Disconnected"
    }

    Column {
        id: col
        anchors.centerIn: parent
        width: parent.width - 28 * ui
        spacing: 12 * ui

        Text {
            text: "NETWORK"
            color: "#6b7280"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9 * root.ui
            font.weight: Font.Medium
            font.letterSpacing: 1.6
        }

        // A label / value row. Value brightens, label stays dim.
        component FieldRow : Column {
            width: col.width
            spacing: 3 * root.ui
            property string label: ""
            property string value: ""

            Text {
                text: parent.label
                color: "#8e8e96"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9 * root.ui
                font.weight: Font.Medium
                font.letterSpacing: 0.8
            }
            Text {
                width: parent.width
                text: parent.value
                color: "#e5e7eb"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 13 * root.ui
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        FieldRow {
            label: "TYPE"
            value: root.typeStr
        }
        FieldRow {
            label: "NAME"
            value: Services.Network.primaryName.length ? Services.Network.primaryName : "—"
        }
        FieldRow {
            label: "IP ADDRESS"
            value: Services.Network.localIp.length ? Services.Network.localIp : "—"
        }
    }
}
