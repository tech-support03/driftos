import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris

// Caelestia-style top bar: invisible at rest, a wide top-center hover target
// expands into a dashboard card. While media plays it shows a waveform that
// also expands the card on hover.
Scope {
    id: root

    // ---- clock --------------------------------------------------------------
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ---- active MPRIS player ------------------------------------------------
    readonly property var players: Mpris.players ? Mpris.players.values : []
    readonly property var player: players.length > 0 ? players[0] : null
    readonly property bool mediaActive: player !== null && player.isPlaying

    // ---- weather (wttr.in, refreshed every 15 min) --------------------------
    property string weatherText: ""
    Process {
        id: weatherProc
        command: ["sh", "-c", "curl -fsS --max-time 6 'https://wttr.in/?format=%c+%t' 2>/dev/null | head -n1 | tr -d '\\n'"]
        stdout: StdioCollector {
            onStreamFinished: root.weatherText = (this.text || "").trim()
        }
    }
    Timer {
        interval: 900000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: weatherProc.running = true
    }

    // ---- cava waveform (only runs while media is playing) -------------------
    property var bars: []
    Process {
        id: cavaProc
        running: root.mediaActive
        command: ["sh", "-c", "cava -p ~/.config/quickshell/cava.conf"]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split(";").filter(s => s.length > 0).map(s => parseInt(s, 10));
                if (parts.length > 0)
                    root.bars = parts;
            }
        }
    }

    // ---- one panel per monitor ---------------------------------------------
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            anchors { top: true; left: true; right: true }
            exclusiveZone: 0
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            implicitHeight: 360
            WlrLayershell.namespace: "quickshell-topbar"
            WlrLayershell.layer: WlrLayer.Top

            // 0 = hidden, 1 = waveform only, 2 = expanded dashboard.
            // `cardHover` is an ancestor handler of the media buttons, so the
            // child MouseAreas can't steal hover from it the way a sibling
            // HoverHandler would — that's what was collapsing the bar.
            readonly property int mode: (hover.hovered || cardHover.hovered)
                                        ? 2 : (root.mediaActive ? 1 : 0)

            // Target size of the visible card for the current mode.
            readonly property real cardW: mode === 2 ? 880
                                        : mode === 1 ? wave.implicitWidth + 64
                                        : 520
            readonly property real cardH: mode === 2 ? 240
                                        : mode === 1 ? 64
                                        : 14

            // Input region. It snaps instantly (no animation) and is always a
            // good deal larger than the visible card, so the cursor has a
            // comfortable margin to reach the widgets without the bar
            // collapsing. The card animates smoothly underneath.
            mask: Region { item: hitbox }

            Item {
                id: hitbox
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                width: win.mode === 2 ? win.cardW + 200
                     : win.mode === 1 ? win.cardW + 160
                     : 560
                height: win.mode === 2 ? win.cardH + 90
                      : win.mode === 1 ? win.cardH + 70
                      : 24
                HoverHandler { id: hover }
            }

            // ---- the visible card ----------------------------------------
            Rectangle {
                id: card
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0

                width: win.cardW
                height: win.cardH
                opacity: win.mode === 0 ? 0 : 1
                clip: true

                color: Qt.rgba(0.05, 0.055, 0.08, 0.97)
                bottomLeftRadius: 22
                bottomRightRadius: 22
                border.width: win.mode === 0 ? 0 : 1
                border.color: Qt.rgba(1, 1, 1, 0.07)

                Behavior on width  { NumberAnimation { duration: 340; easing.type: Easing.OutExpo } }
                Behavior on height { NumberAnimation { duration: 340; easing.type: Easing.OutExpo } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

                // Keeps the bar expanded while the cursor is anywhere on the
                // card, including over the media-button MouseAreas.
                HoverHandler { id: cardHover }

                // ---- waveform (mode 1) -----------------------------------
                Waveform {
                    id: wave
                    anchors.centerIn: parent
                    bars: root.bars
                    opacity: win.mode === 1 ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                }

                // ---- dashboard (mode 2) ----------------------------------
                Row {
                    id: dashboard
                    anchors.centerIn: parent
                    spacing: 34
                    opacity: win.mode === 2 ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

                    // -- time --
                    Column {
                        width: 190
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: Qt.formatDateTime(clock.date, "h:mm AP")
                            color: "#c4b5fd"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 58
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: Qt.formatDateTime(clock.date, "dddd")
                            color: "#e5e7eb"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 16
                        }
                        Text {
                            text: Qt.formatDateTime(clock.date, "dd MMMM yyyy")
                            color: "#9ca3af"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                        }
                    }

                    Rectangle {
                        width: 1; height: 170
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // -- calendar --
                    MiniCalendar {
                        anchors.verticalCenter: parent.verticalCenter
                        today: clock.date
                    }

                    Rectangle {
                        width: 1; height: 170
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // -- media + weather --
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 16
                        width: 250

                        Column {
                            spacing: 6
                            width: parent.width

                            Text {
                                width: parent.width
                                text: root.player
                                      ? (root.player.trackTitle || "Unknown track")
                                      : "Nothing playing"
                                color: "#fcd34d"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                visible: root.player && root.player.trackArtist
                                text: root.player ? (root.player.trackArtist || "") : ""
                                color: "#9ca3af"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Row {
                                spacing: 26
                                topPadding: 4
                                visible: root.player !== null

                                Text {
                                    text: ""   // previous
                                    color: prevArea.containsMouse ? "#ffffff" : "#d1d5db"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 18
                                    MouseArea {
                                        id: prevArea
                                        anchors.fill: parent
                                        anchors.margins: -8
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (root.player) root.player.previous()
                                    }
                                }
                                Text {
                                    text: root.mediaActive ? "" : ""   // pause / play
                                    color: playArea.containsMouse ? "#ffffff" : "#d1d5db"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 18
                                    MouseArea {
                                        id: playArea
                                        anchors.fill: parent
                                        anchors.margins: -8
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (root.player) root.player.togglePlaying()
                                    }
                                }
                                Text {
                                    text: ""   // next
                                    color: nextArea.containsMouse ? "#ffffff" : "#d1d5db"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 18
                                    MouseArea {
                                        id: nextArea
                                        anchors.fill: parent
                                        anchors.margins: -8
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (root.player) root.player.next()
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width; height: 1
                            color: Qt.rgba(1, 1, 1, 0.06)
                        }

                        Text {
                            width: parent.width
                            text: root.weatherText.length > 0
                                  ? root.weatherText
                                  : "weather unavailable"
                            color: "#67e8f9"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 15
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
