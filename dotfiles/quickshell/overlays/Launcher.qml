// ~/.config/quickshell/overlays/Launcher.qml — Launchpad-style app grid.
//
// Triggered by `qs ipc call launcher toggle` (wired to Mod+Space in niri).
// Full-screen Overlay layer with dim backdrop, centered search pill, and a
// paginated icon grid. Click outside / Escape / Enter (launches first match)
// all close the launcher.
//
// Icons are resolved through Quickshell.iconPath() using the system icon
// theme (Papirus-Dark). Apps come from DesktopEntries.

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Scope {
    id: scope

    // ---- state -------------------------------------------------------------
    property string query: ""
    property var allApps: []
    property var results: []
    property bool active: false        // drives open/close animation
    property int  selectedIndex: 0     // keyboard-highlighted tile

    function launchSelected() {
        const i = scope.selectedIndex
        if (i >= 0 && i < scope.results.length) {
            scope.results[i].execute()
            scope.close()
        }
    }

    // Move the keyboard selection by (dx, dy) cells, clamped to the result set.
    function moveSelection(dx, dy) {
        const n = scope.results.length
        if (n === 0) return
        const cols = grid.cols
        let i = scope.selectedIndex
        if (dx !== 0) {
            i = Math.max(0, Math.min(n - 1, i + dx))
        }
        if (dy !== 0) {
            const target = i + dy * cols
            // Don't wrap off the ends — clamp, but only jump rows if a row exists.
            if (target >= 0 && target < n) i = target
        }
        scope.selectedIndex = i
    }

    function buildAllApps() {
        const src = DesktopEntries.applications.values
        const out = []
        for (let i = 0; i < src.length; i++) {
            const e = src[i]
            if (!e || e.noDisplay || !e.name) continue
            out.push(e)
        }
        out.sort((a, b) => a.name.localeCompare(b.name))
        allApps = out
    }

    function recompute() {
        const q = query.trim().toLowerCase()
        if (q.length === 0) { results = allApps; return }
        const out = []
        for (let i = 0; i < allApps.length; i++) {
            const e = allApps[i]
            const name = (e.name || "").toLowerCase()
            const generic = (e.genericName || "").toLowerCase()
            const comment = (e.comment || "").toLowerCase()
            if (name.indexOf(q) !== -1 || generic.indexOf(q) !== -1 || comment.indexOf(q) !== -1)
                out.push(e)
        }
        // Prefer matches where the query is a prefix of the name.
        out.sort((a, b) => {
            const an = a.name.toLowerCase(), bn = b.name.toLowerCase()
            const ap = an.startsWith(q), bp = bn.startsWith(q)
            if (ap !== bp) return ap ? -1 : 1
            return an.localeCompare(bn)
        })
        results = out
    }

    onResultsChanged: {
        selectedIndex = 0
        grid.positionViewAtBeginning()
    }

    onQueryChanged: recompute()
    Component.onCompleted: { buildAllApps(); recompute() }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { scope.buildAllApps(); scope.recompute() }
    }

    // ---- lifecycle ---------------------------------------------------------
    function open() {
        panel.visible = true
        scope.query = ""
        scope.selectedIndex = 0
        active = true
        // Forcing focus immediately races with the layer-shell handshake;
        // a single frame delay is enough for the surface to be ready.
        Qt.callLater(() => searchField.forceActiveFocus())
    }
    function close() {
        active = false
        // Let the fade-out finish before unmapping the surface.
        hideTimer.restart()
    }
    function toggle() { active ? close() : open() }

    Timer {
        id: hideTimer
        interval: 220
        onTriggered: if (!scope.active) panel.visible = false
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void  { scope.toggle() }
        function show(): void    { scope.open() }
        function hide(): void    { scope.close() }
    }

    // ---- the overlay window ------------------------------------------------
    PanelWindow {
        id: panel
        visible: false
        color: "transparent"

        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: -1
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-launcher"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // ---- dim backdrop --------------------------------------------------
        Rectangle {
            id: dim
            anchors.fill: parent
            color: Qt.rgba(0.04, 0.04, 0.06, 0.84)
            opacity: scope.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

            MouseArea {
                anchors.fill: parent
                onClicked: scope.close()
            }
        }

        // ---- content -------------------------------------------------------
        Item {
            id: content
            anchors.fill: parent
            focus: true
            opacity: scope.active ? 1 : 0
            scale: scope.active ? 1.0 : 0.94
            transformOrigin: Item.Center
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

            Keys.onEscapePressed: scope.close()

            // Search pill ----------------------------------------------------
            Rectangle {
                id: searchPill
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(80, (parent.height - innerColumnHeight) / 2 - 90)
                readonly property int innerColumnHeight: 60 + 24 + (4 * 168)
                width: 460
                height: 48
                radius: 24
                color: Qt.rgba(1, 1, 1, 0.10)
                border.color: Qt.rgba(1, 1, 1, 0.14)
                border.width: 1

                Text {
                    id: searchIcon
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    text: ""   // nerd-font search glyph
                    color: "#8e8e96"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 15
                }

                TextField {
                    id: searchField
                    anchors.left: searchIcon.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    background: Item {}
                    color: "#f4f4f6"
                    placeholderText: "Search"
                    placeholderTextColor: "#8e8e96"
                    font.family: "Inter"
                    font.pixelSize: 16
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    onTextChanged: scope.query = text
                    onAccepted: scope.launchSelected()
                    Keys.onEscapePressed: scope.close()

                    // Arrow keys drive the grid selection instead of the text
                    // cursor — this is a launcher, the query is short and the
                    // grid is what you actually want to move through.
                    Keys.onPressed: (event) => {
                        switch (event.key) {
                        case Qt.Key_Right: scope.moveSelection(1, 0);  event.accepted = true; break
                        case Qt.Key_Left:  scope.moveSelection(-1, 0); event.accepted = true; break
                        case Qt.Key_Down:  scope.moveSelection(0, 1);  event.accepted = true; break
                        case Qt.Key_Up:    scope.moveSelection(0, -1); event.accepted = true; break
                        case Qt.Key_Tab:   scope.moveSelection(1, 0);  event.accepted = true; break
                        case Qt.Key_Backtab: scope.moveSelection(-1, 0); event.accepted = true; break
                        }
                    }
                }
            }

            // Icon grid ------------------------------------------------------
            GridView {
                id: grid
                anchors.top: searchPill.bottom
                anchors.topMargin: 36
                anchors.horizontalCenter: parent.horizontalCenter
                readonly property int cols: 7
                readonly property int rows: 4
                cellWidth: 168
                cellHeight: 168
                width: cols * cellWidth
                height: rows * cellHeight
                model: scope.results
                currentIndex: scope.selectedIndex
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
                clip: true
                interactive: true
                cacheBuffer: cellHeight * 4
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    width: 4
                    contentItem: Rectangle {
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.18)
                    }
                }

                delegate: Item {
                    id: tile
                    width: grid.cellWidth
                    height: grid.cellHeight
                    required property var modelData
                    required property int index

                    readonly property bool selected: tile.index === grid.currentIndex

                    // Resolve the icon up front; iconPath(name, true) returns ""
                    // when the theme has no match, which lets us fall back to a
                    // nicer lettered tile instead of the generic puzzle glyph.
                    readonly property string iconName:
                        (modelData && modelData.icon) ? modelData.icon : ""
                    readonly property string resolved:
                        iconName ? Quickshell.iconPath(iconName, true) : ""
                    readonly property bool hasIcon: resolved.length > 0

                    Rectangle {
                        id: iconBg
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 8
                        width: 108; height: 108
                        radius: 26
                        color: (tile.selected || hh.hovered) ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                        border.width: tile.selected ? 2 : 0
                        border.color: "#5b6ee0"
                        scale: ma.pressed ? 0.92 : ((tile.selected || hh.hovered) ? 1.06 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                        Behavior on color { ColorAnimation { duration: 140 } }

                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 78
                            visible: tile.hasIcon
                            source: tile.resolved
                            asynchronous: true
                        }

                        // Fallback: a tinted rounded square with the app's
                        // initial, used when no themed icon is found.
                        Rectangle {
                            anchors.centerIn: parent
                            width: 78; height: 78
                            radius: 20
                            visible: !tile.hasIcon
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(0.77, 0.70, 1.0, 0.22) }
                                GradientStop { position: 1.0; color: Qt.rgba(0.77, 0.70, 1.0, 0.10) }
                            }
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.10)

                            Text {
                                anchors.centerIn: parent
                                text: (tile.modelData && tile.modelData.name)
                                    ? tile.modelData.name.charAt(0).toUpperCase()
                                    : "?"
                                color: "#e7e1ff"
                                font.family: "Inter"
                                font.pixelSize: 36
                                font.weight: Font.DemiBold
                            }
                        }

                        HoverHandler { id: hh }
                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onEntered: scope.selectedIndex = tile.index
                            onClicked: {
                                if (tile.modelData) tile.modelData.execute()
                                scope.close()
                            }
                        }
                    }

                    Text {
                        anchors.top: iconBg.bottom
                        anchors.topMargin: 6
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 150
                        horizontalAlignment: Text.AlignHCenter
                        text: tile.modelData ? tile.modelData.name : ""
                        color: tile.selected ? "#ffffff" : "#f4f4f6"
                        font.family: "Inter"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                    }
                }
            }

            // Empty state ----------------------------------------------------
            Text {
                anchors.top: searchPill.bottom
                anchors.topMargin: 80
                anchors.horizontalCenter: parent.horizontalCenter
                visible: scope.results.length === 0
                text: scope.query.length > 0 ? "No results" : "No apps found"
                color: "#8e8e96"
                font.family: "Inter"
                font.pixelSize: 14
            }
        }
    }
}
