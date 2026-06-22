// ~/.config/quickshell/bars/VolumeFlyout.qml
// Hover flyout for the SideBar volume button. Drops in to the right of the
// volume IconButton and shows the live level (Services.Audio). Animation +
// translucent surface idiom mirrors SystemMonitor.qml's popover.
//
// Drop-in API (wired by the trigger widget):
//   property bool show   — driven by the volume button's hover state
//   property real ui     — per-monitor UI scale
// The flyout positions itself to the right of its parent and vertically
// centers on it; it never steals hover (no HoverHandler), so the parent's
// hover state stays authoritative.

import QtQuick
import "../services" as Services
import "../theme"

Rectangle {
    id: root

    property bool show: false
    property real ui:   1.0

    x: parent.width + 12 * ui
    anchors.verticalCenter: parent.verticalCenter

    width: 150 * ui
    height: col.implicitHeight + 24 * ui

    color: Qt.rgba(0.06, 0.07, 0.10, 0.96)
    radius: 16
    border.color: Qt.rgba(1, 1, 1, 0.07)
    border.width: 1

    opacity: show ? 1 : 0
    visible: opacity > 0.01
    scale: show ? 1.0 : 0.97
    transformOrigin: Item.Left
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
    Behavior on scale   { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    // Fill is the volume-button blue; dim it while muted.
    readonly property color fillColor: Services.Audio.muted ? "#6b7280" : Theme.blue

    Column {
        id: col
        anchors.centerIn: parent
        width: parent.width - 24 * ui
        spacing: 8 * ui

        Text {
            text: "VOLUME"
            color: "#6b7280"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9 * ui
            font.weight: Font.Medium
            font.letterSpacing: 1.6
        }

        // glyph (left) + level (right)
        Item {
            width: col.width
            height: 18 * ui

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: Services.Audio.glyph
                color: root.fillColor
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 15 * ui
                Behavior on color { ColorAnimation { duration: 160 } }
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Services.Audio.muted ? "Muted" : (Services.Audio.volume + "%")
                color: "#f4f4f6"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 13 * ui
                font.weight: Font.DemiBold
            }
        }

        // thin volume bar: track + animated fill
        Rectangle {
            id: track
            width: col.width
            height: 4 * ui
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.07)

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: track.width * Math.max(0, Math.min(100, Services.Audio.volume)) / 100
                radius: parent.radius
                color: root.fillColor
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 160 } }
            }
        }
    }
}
