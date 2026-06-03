// ~/.config/quickshell/overlays/VolumeOSD.qml — volume on-screen display.
//
// A passive, bottom-center pill that pops up whenever the volume changes and
// fades out 1.5s later. It NEVER grabs pointer/keyboard focus (empty input
// mask → fully click-through), so it's a pure readout that can't get in the
// way of whatever is underneath it.
//
// It shows for two reasons:
//   • `qs ipc call audio show` — fired by the niri XF86Audio* binds right
//     after they nudge wpctl, so a keyboard volume change pops the OSD
//     instantly (the niri bind keeps the wpctl call itself, so volume still
//     works even if Quickshell is down — the OSD is best-effort on top);
//   • Services.Audio.bumped() — any other change (sidebar scroll, pavucontrol)
//     pops it too, for consistent feedback.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../services" as Services
import "../theme"

Scope {
    id: scope

    function showOSD() {
        osd.shown = true
        hideTimer.restart()
    }

    // Keyboard path: niri runs wpctl, then pokes this so the OSD reflects the
    // already-applied value (refresh() re-probes; the bar animates to it).
    IpcHandler {
        target: "audio"
        function show(): void { Services.Audio.refresh(); scope.showOSD() }
    }

    // Any other volume change (scroll on the sidebar button, pavucontrol, …).
    Connections {
        target: Services.Audio
        function onBumped() { scope.showOSD() }
    }

    Timer { id: hideTimer; interval: 1500; onTriggered: osd.shown = false }

    PanelWindow {
        id: osd
        property bool shown: false
        // Stay mapped through the fade-out, then unmap.
        visible: shown || card.opacity > 0.01

        anchors { bottom: true }
        margins.bottom: 96
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-osd"
        // Empty input region — fully click-through, never steals focus.
        mask: Region {}
        color: "transparent"

        implicitWidth: 300
        implicitHeight: 64

        Rectangle {
            id: card
            anchors.fill: parent
            radius: 18
            color: Qt.rgba(0.06, 0.07, 0.10, 0.96)
            border.color: Qt.rgba(1, 1, 1, 0.07)
            border.width: 1

            opacity: osd.shown ? 1 : 0
            scale:   osd.shown ? 1.0 : 0.94
            transformOrigin: Item.Bottom
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

            readonly property color accent: Services.Audio.muted ? "#6b7280" : Theme.blue

            Row {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 14

                // Speaker glyph (tier / muted).
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    horizontalAlignment: Text.AlignHCenter
                    text: Services.Audio.glyph
                    color: card.accent
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 22
                    Behavior on color { ColorAnimation { duration: 160 } }
                }

                // Progress track + fill.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 24 - 44 - 28   // glyph + percent + spacing
                    height: 6
                    radius: 3
                    color: Qt.rgba(1, 1, 1, 0.10)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * Math.max(0, Math.min(100, Services.Audio.volume)) / 100
                        radius: parent.radius
                        color: card.accent
                        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }
                }

                // Percent readout.
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    horizontalAlignment: Text.AlignRight
                    text: Services.Audio.muted ? "Muted" : (Services.Audio.volume + "%")
                    color: Services.Audio.muted ? "#6b7280" : "#f4f4f6"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
