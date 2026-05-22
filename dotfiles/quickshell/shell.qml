import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris

// Caelestia-style top bar: invisible at rest, a wide top-center hover target
// expands into a dashboard card. While media plays it shows a waveform that
// floats with no background, and expands the card on hover.
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

    // ---- weather (wttr.in, pipe-delimited, refreshed every 15 min) ----------
    // Format: "⛅ +72°F~Partly cloudy~Feels +70°F~10 mph NW~Humidity: 58%"
    property string weatherRaw: ""
    property var weatherParts: []
    onWeatherRawChanged: {
        weatherParts = weatherRaw
            ? weatherRaw.split("~").map(function(s) { return s.trim() })
            : []
    }

    Process {
        id: weatherProc
        command: ["sh", "-c",
            "curl -fsS --max-time 8 'https://wttr.in/?format=%c+%t~%C~Feels+%f~%w~Humidity:+%h' 2>/dev/null | head -n1 | tr -d '\\n'"]
        stdout: StdioCollector {
            onStreamFinished: root.weatherRaw = (this.text || "").trim()
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
                const parts = line.split(";").filter(s => s.length > 0).map(s => parseInt(s, 10))
                if (parts.length > 0)
                    root.bars = parts
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
            implicitHeight: 380
            WlrLayershell.namespace: "quickshell-topbar"
            WlrLayershell.layer: WlrLayer.Top

            // 0 = hidden, 1 = floating waveform, 2 = expanded dashboard
            readonly property int mode: (hover.hovered || cardHover.hovered)
                                        ? 2 : (root.mediaActive ? 1 : 0)

            readonly property real cardW: mode === 2 ? 1000
                                        : mode === 1 ? wave.implicitWidth + 48
                                        : 520
            readonly property real cardH: mode === 2 ? 244
                                        : mode === 1 ? 44
                                        : 14

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

            // ---- the visible card ------------------------------------------
            Rectangle {
                id: card
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0

                width: win.cardW
                height: win.cardH
                opacity: win.mode === 0 ? 0 : 1
                clip: true

                // Transparent in waveform mode so bars appear to float
                color: win.mode === 1 ? "transparent" : Qt.rgba(0.05, 0.055, 0.08, 0.97)
                bottomLeftRadius: 22
                bottomRightRadius: 22
                border.width: win.mode === 2 ? 1 : 0
                border.color: Qt.rgba(1, 1, 1, 0.07)

                Behavior on width   { NumberAnimation { duration: 340; easing.type: Easing.OutExpo } }
                Behavior on height  { NumberAnimation { duration: 340; easing.type: Easing.OutExpo } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                Behavior on color   { ColorAnimation  { duration: 200 } }

                // Keeps bar expanded while cursor is anywhere on the card
                HoverHandler { id: cardHover }

                // ---- waveform (mode 1 — floating, no background) ------------
                Waveform {
                    id: wave
                    anchors.centerIn: parent
                    bars: root.bars
                    opacity: win.mode === 1 ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                }

                // ---- dashboard (mode 2) ------------------------------------
                Row {
                    id: dashboard
                    anchors.centerIn: parent
                    spacing: 28
                    opacity: win.mode === 2 ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

                    // -- time ------------------------------------------------
                    Column {
                        width: 165
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: Qt.formatDateTime(clock.date, "h:mm AP")
                            color: "#c4b5fd"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 54
                            font.weight: Font.DemiBold
                            // Scale down to fit the column — prevents bleed into calendar
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: 28
                        }
                        Text {
                            text: Qt.formatDateTime(clock.date, "dddd")
                            color: "#e5e7eb"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 15
                        }
                        Text {
                            text: Qt.formatDateTime(clock.date, "dd MMMM yyyy")
                            color: "#9ca3af"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                        }
                    }

                    Rectangle {
                        width: 1; height: 170
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // -- calendar --------------------------------------------
                    MiniCalendar {
                        anchors.verticalCenter: parent.verticalCenter
                        today: clock.date
                    }

                    Rectangle {
                        width: 1; height: 170
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // -- media -----------------------------------------------
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        width: 205

                        // Album art + track info row
                        Row {
                            spacing: 10
                            width: parent.width

                            // Album art thumbnail
                            Rectangle {
                                id: artBox
                                width: 58; height: 58
                                radius: 8
                                clip: true
                                color: "#1a172b"
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.player !== null

                                Image {
                                    id: artImg
                                    anchors.fill: parent
                                    source: root.player ? root.player.trackArtUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                }
                                // Music note placeholder when no art is available
                                Text {
                                    anchors.centerIn: parent
                                    text: "♪"
                                    color: "#4b4570"
                                    font.pixelSize: 24
                                    visible: artImg.status !== Image.Ready
                                }
                            }

                            Column {
                                spacing: 3
                                width: parent.width - (root.player !== null ? 68 : 0)
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    width: parent.width
                                    text: root.player
                                          ? (root.player.trackTitle || "Unknown track")
                                          : "Nothing playing"
                                    color: "#fcd34d"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    visible: root.player && root.player.trackArtist
                                    text: root.player ? (root.player.trackArtist || "") : ""
                                    color: "#9ca3af"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    visible: root.player && root.player.trackAlbum
                                    text: root.player ? (root.player.trackAlbum || "") : ""
                                    color: "#6b7280"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // Playback controls
                        Row {
                            spacing: 28
                            visible: root.player !== null
                            anchors.horizontalCenter: parent.horizontalCenter
                            topPadding: 2

                            Text {
                                text: ""
                                color: prevArea.containsMouse ? "#ffffff" : "#d1d5db"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 17
                                MouseArea {
                                    id: prevArea
                                    anchors.fill: parent; anchors.margins: -8
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: if (root.player) root.player.previous()
                                }
                            }
                            Text {
                                text: root.mediaActive ? "" : ""
                                color: playArea.containsMouse ? "#ffffff" : "#d1d5db"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 17
                                MouseArea {
                                    id: playArea
                                    anchors.fill: parent; anchors.margins: -8
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: if (root.player) root.player.togglePlaying()
                                }
                            }
                            Text {
                                text: ""
                                color: nextArea.containsMouse ? "#ffffff" : "#d1d5db"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 17
                                MouseArea {
                                    id: nextArea
                                    anchors.fill: parent; anchors.margins: -8
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: if (root.player) root.player.next()
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: 1; height: 170
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // -- weather ---------------------------------------------
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        width: 168

                        // Condition + temperature (large)
                        Text {
                            width: parent.width
                            text: root.weatherParts.length > 0
                                  ? root.weatherParts[0]
                                  : "Loading…"
                            color: "#67e8f9"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        // Condition description
                        Text {
                            width: parent.width
                            visible: root.weatherParts.length > 1
                            text: root.weatherParts.length > 1 ? root.weatherParts[1] : ""
                            color: "#e5e7eb"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        // Feels like
                        Text {
                            width: parent.width
                            visible: root.weatherParts.length > 2
                            text: root.weatherParts.length > 2 ? root.weatherParts[2] : ""
                            color: "#9ca3af"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                        // Wind
                        Text {
                            width: parent.width
                            visible: root.weatherParts.length > 3
                            text: root.weatherParts.length > 3 ? root.weatherParts[3] : ""
                            color: "#9ca3af"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                        // Humidity
                        Text {
                            width: parent.width
                            visible: root.weatherParts.length > 4
                            text: root.weatherParts.length > 4 ? root.weatherParts[4] : ""
                            color: "#9ca3af"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
