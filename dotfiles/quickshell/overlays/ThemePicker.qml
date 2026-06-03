// ~/.config/quickshell/overlays/ThemePicker.qml — theme switcher "menu".
//
// Triggered by `qs ipc call theme toggle` (wired to Mod+T in niri). Same
// overlay idiom as PowerFlyout/Launcher: full-screen Overlay layer, dim
// backdrop, click-outside / Escape closes, exclusive keyboard focus.
//
// Lists every saved theme (~/.config/rice/themes/*.theme) with its four-colour
// swatch; clicking one runs `rice-theme set <name>`. The shell re-themes live
// off Theme.qml's FileView, and the active marker tracks ~/.config/rice/theme.
// The cycle bind (Mod+Shift+T) calls `rice-theme next` directly — no overlay.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: scope

    property bool active: false
    property var  themes: []          // [{ name, colors: [c1,c2,c3,c4] }]
    property string activeName: ""
    property int  selected: 0

    function open()   { panel.visible = true; lister.running = true; active = true;
                        Qt.callLater(() => content.forceActiveFocus()) }
    function close()  { active = false; hideTimer.restart() }
    function toggle() { active ? close() : open() }

    function apply(name) {
        if (!name) return
        Quickshell.execDetached(["sh", "-c", "rice-theme set " + name +
                                 " 2>>\"$HOME/.cache/qs-theme.log\""])
        close()
    }

    Timer { id: hideTimer; interval: 220; onTriggered: if (!scope.active) panel.visible = false }

    // Active theme name — tracked live so the ● marker is always right.
    FileView {
        path: Quickshell.env("HOME") + "/.config/rice/theme"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: scope.activeName = text().trim()
    }

    // Theme list: one line per theme "name #c1 #c2 #c3 #c4".
    Process {
        id: lister
        command: ["sh", "-c",
            "for f in \"$HOME\"/.config/rice/themes/*.theme; do [ -e \"$f\" ] || continue; " +
            "n=$(basename \"$f\" .theme); " +
            "cs=$(grep -oE '#[0-9a-fA-F]{6}' \"$f\" | head -4 | tr '\\n' ' '); " +
            "echo \"$n $cs\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of this.text.trim().split("\n")) {
                    if (!line.trim()) continue
                    const t = line.trim().split(/\s+/)
                    out.push({ name: t[0], colors: t.slice(1, 5) })
                }
                scope.themes = out
            }
        }
    }

    IpcHandler {
        target: "theme"
        function toggle(): void { scope.toggle() }
        function show(): void   { scope.open() }
        function hide(): void   { scope.close() }
    }

    PanelWindow {
        id: panel
        visible: false
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: -1
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-theme"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.04, 0.04, 0.06, 0.55)
            opacity: scope.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutQuad } }
            MouseArea { anchors.fill: parent; onClicked: scope.close() }
        }

        Item {
            id: content
            anchors.fill: parent
            focus: true
            opacity: scope.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutQuad } }

            Keys.onEscapePressed: scope.close()
            Keys.onUpPressed:   scope.selected = (scope.selected - 1 + scope.themes.length) % Math.max(1, scope.themes.length)
            Keys.onDownPressed: scope.selected = (scope.selected + 1) % Math.max(1, scope.themes.length)
            Keys.onReturnPressed: if (scope.themes[scope.selected]) scope.apply(scope.themes[scope.selected].name)
            Keys.onEnterPressed:  if (scope.themes[scope.selected]) scope.apply(scope.themes[scope.selected].name)

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: 320
                implicitHeight: col.implicitHeight + 28
                radius: 18
                color: Qt.rgba(0.110, 0.110, 0.133, 0.50)
                border.color: Qt.rgba(1, 1, 1, 0.09)
                border.width: 1
                scale: scope.active ? 1.0 : 0.94
                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                Column {
                    id: col
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 4

                    Text {
                        text: "Themes"
                        color: Theme.fg2
                        font.family: "Inter"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        bottomPadding: 6
                    }

                    Repeater {
                        model: scope.themes

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: 44
                            radius: 12

                            readonly property bool isActive: modelData.name === scope.activeName
                            readonly property bool sel: scope.selected === row.index

                            color: row.sel ? Qt.rgba(0.36, 0.43, 0.88, 0.18)
                                           : (hh.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                            Behavior on color { ColorAnimation { duration: 180 } }
                            scale: ma.pressed ? 0.97 : 1.0
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                            // active ● / inactive ○
                            Text {
                                id: dot
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                text: row.isActive ? "●" : "○"
                                color: row.isActive ? Theme.accent : Theme.fg3
                                font.pixelSize: 12
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: dot.right
                                anchors.leftMargin: 12
                                text: row.modelData.name
                                color: row.isActive ? Theme.fg0 : Theme.fg1
                                font.family: "Inter"
                                font.pixelSize: 14
                            }

                            // four-colour swatch
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                spacing: 4
                                Repeater {
                                    model: row.modelData.colors
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 16; height: 16; radius: 4
                                        color: modelData
                                        border.color: Qt.rgba(1, 1, 1, 0.12)
                                        border.width: 1
                                    }
                                }
                            }

                            HoverHandler { id: hh; onHoveredChanged: if (hovered) scope.selected = row.index }
                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: scope.apply(row.modelData.name)
                            }
                        }
                    }
                }
            }
        }
    }
}
