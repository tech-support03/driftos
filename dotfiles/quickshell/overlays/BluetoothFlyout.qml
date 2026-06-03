// ~/.config/quickshell/overlays/BluetoothFlyout.qml — bluetooth manager flyout.
//
// Triggered by `qs ipc call bluetooth toggle` (wired to the SideBar bluetooth
// button). Same overlay idiom as NetworkFlyout/PowerFlyout/Launcher: full-screen
// Overlay layer, dim backdrop, click-outside / Escape closes, exclusive keyboard
// focus.
//
// All adapter state + actions come from services/Bluetooth.qml; this file is the
// UI surface only — current status, power on/off, rescan, and a list of devices
// (connected / paired / discovered) with one-tap connect / disconnect and a
// forget button. The "Advanced" button drops to `blueman-manager` for pairing
// flows that need a PIN/passkey agent and anything this panel leaves out.
//
// Mirrors NetworkFlyout.qml; the chief difference is no inline password field —
// BT pairing is agent-driven, so unknown devices are pair+trust+connect in one
// tap and anything needing a passkey is handed to blueman-manager.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../services" as Services

Scope {
    id: scope

    readonly property var bt: Services.Bluetooth

    property bool   active: false
    property string statusMsg: ""

    function open() {
        panel.visible = true
        active = true
        statusMsg = ""
        bt.refresh()
        if (bt.powered) bt.rescan()
        Qt.callLater(() => content.forceActiveFocus())
    }
    function close() {
        active = false
        hideTimer.restart()
    }
    function toggle() { active ? close() : open() }

    // Tapping a device row: connected → disconnect; paired (offline) → connect;
    // unknown → pair+trust+connect (Bluetooth singleton bundles the three).
    function activate(d) {
        if (d.connected) {
            bt.disconnect(d.mac)
            statusMsg = "Disconnecting " + d.name + "…"
        } else {
            bt.connect(d.mac, d.paired)
            statusMsg = (d.paired ? "Connecting to " : "Pairing ") + d.name + "…"
        }
    }

    Connections {
        target: scope.bt
        function onActionFinished(ok, message) {
            scope.statusMsg = ok ? "" : (message.length ? message : "Action failed")
        }
    }

    Timer {
        id: hideTimer
        interval: 220
        onTriggered: if (!scope.active) panel.visible = false
    }

    IpcHandler {
        target: "bluetooth"
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
        WlrLayershell.namespace: "quickshell-bluetooth"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            id: dim
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

            // Translucent card — sits a bit left of centre so it reads as
            // belonging to the SideBar that launched it (matches NetworkFlyout).
            Rectangle {
                id: card
                anchors.verticalCenter: parent.verticalCenter
                x: 120
                width: 380
                height: Math.min(560, body.implicitHeight + 28)
                radius: 18
                color: Qt.rgba(0.075, 0.078, 0.102, 0.94)
                border.color: Qt.rgba(1, 1, 1, 0.09)
                border.width: 1
                scale: scope.active ? 1.0 : 0.95
                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                Column {
                    id: body
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    // ---- header: adapter status ------------------------------
                    Item {
                        width: parent.width
                        height: 44

                        Rectangle {
                            id: hIcon
                            width: 44; height: 44; radius: 13
                            color: scope.bt.connectedCount > 0 ? Qt.rgba(0.65, 0.85, 1.0, 0.16)
                                                               : Qt.rgba(1, 1, 1, 0.05)
                            Text {
                                anchors.centerIn: parent
                                text: scope.bt.glyph || "󰂯"
                                color: scope.bt.connectedCount > 0 ? Theme.blue : "#8e8e96"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 22
                            }
                        }
                        Column {
                            anchors.left: hIcon.right
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: scope.bt.connectedCount > 0
                                      ? scope.bt.connectedName
                                      : (scope.bt.powered ? "Bluetooth on" : "Bluetooth off")
                                color: "#f4f4f6"
                                font.family: "Inter"
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                width: 230
                            }
                            Text {
                                text: scope.bt.connectedCount > 1
                                      ? (scope.bt.connectedCount + " devices connected")
                                      : (scope.bt.connectedCount === 1
                                         ? "Connected"
                                         : (scope.bt.powered ? "Select a device below" : "Turn on to connect"))
                                color: "#8e8e96"
                                font.family: "Inter"
                                font.pixelSize: 11
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }

                    // ---- controls: power toggle + rescan ---------------------
                    Item {
                        width: parent.width
                        height: 30

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Bluetooth"
                            color: "#c9c9d0"
                            font.family: "Inter"
                            font.pixelSize: 13
                        }

                        // Pill toggle
                        Rectangle {
                            id: toggle
                            anchors.left: parent.left
                            anchors.leftMargin: 80
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40; height: 22; radius: 11
                            color: scope.bt.powered ? Qt.rgba(0.65, 0.85, 1.0, 0.55)
                                                    : Qt.rgba(1, 1, 1, 0.10)
                            Behavior on color { ColorAnimation { duration: 180 } }
                            Rectangle {
                                width: 16; height: 16; radius: 8
                                color: "#f4f4f6"
                                y: 3
                                x: scope.bt.powered ? parent.width - width - 3 : 3
                                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: scope.bt.togglePower()
                            }
                        }

                        // Rescan
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30; height: 30; radius: 9
                            color: rescanHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                            Behavior on color { ColorAnimation { duration: 160 } }
                            Text {
                                id: rescanIcon
                                anchors.centerIn: parent
                                text: "󰑐"
                                color: scope.bt.scanning ? Theme.blue : "#c9c9d0"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 16
                                RotationAnimation on rotation {
                                    running: scope.bt.scanning === true
                                    loops: Animation.Infinite
                                    from: 0; to: 360; duration: 900
                                    onStopped: rescanIcon.rotation = 0
                                }
                            }
                            HoverHandler { id: rescanHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: scope.bt.rescan()
                            }
                        }
                    }

                    // ---- status message (errors / connecting) ----------------
                    Text {
                        width: parent.width
                        visible: scope.statusMsg.length > 0
                        text: scope.statusMsg
                        color: "#e8b475"
                        font.family: "Inter"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                    }

                    // ---- device list -----------------------------------------
                    Flickable {
                        width: parent.width
                        height: Math.min(330, listCol.implicitHeight)
                        contentHeight: listCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        visible: scope.bt.powered

                        Column {
                            id: listCol
                            width: parent.width
                            spacing: 2

                            Repeater {
                                model: scope.bt.devices || []

                                delegate: Rectangle {
                                    id: row
                                    required property var modelData
                                    width: listCol.width
                                    height: 46
                                    radius: 11
                                    color: row.modelData.connected
                                           ? Qt.rgba(0.65, 0.85, 1.0, 0.14)
                                           : (rh.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                                    Behavior on color { ColorAnimation { duration: 160 } }

                                    Text {
                                        id: dg
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: row.modelData.glyph
                                        color: row.modelData.connected ? Theme.blue : "#c9c9d0"
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 18
                                    }
                                    Column {
                                        anchors.left: dg.right
                                        anchors.leftMargin: 12
                                        anchors.right: actions.left
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 1
                                        Text {
                                            width: parent.width
                                            text: row.modelData.name
                                            color: "#f4f4f6"
                                            font.family: "Inter"
                                            font.pixelSize: 13
                                            font.weight: row.modelData.connected ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            visible: row.modelData.connected || row.modelData.paired
                                            text: row.modelData.connected ? "Connected"
                                                  : (row.modelData.paired ? "Paired" : "")
                                            color: "#8e8e96"
                                            font.family: "Inter"
                                            font.pixelSize: 10
                                        }
                                    }

                                    // right-side controls: a forget (✕) button for
                                    // paired devices + the connect/disconnect glyph.
                                    Row {
                                        id: actions
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4

                                        // Forget — only for known (paired) devices.
                                        Rectangle {
                                            width: 28; height: 28; radius: 8
                                            visible: row.modelData.paired
                                            color: forgetHover.hovered ? Qt.rgba(0.96, 0.25, 0.37, 0.22)
                                                                        : "transparent"
                                            Behavior on color { ColorAnimation { duration: 140 } }
                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰧧"   // bluetooth-off / unlink
                                                color: forgetHover.hovered ? "#fb7185" : "#8e8e96"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 14
                                            }
                                            HoverHandler { id: forgetHover }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    scope.bt.forget(row.modelData.mac)
                                                    scope.statusMsg = "Forgetting " + row.modelData.name + "…"
                                                }
                                            }
                                        }

                                        // Connect / disconnect state glyph.
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: row.modelData.connected ? "󰄬" : "󰂯"
                                            color: row.modelData.connected ? "#86efac" : "#8e8e96"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: row.modelData.connected ? 15 : 13
                                        }
                                    }

                                    HoverHandler { id: rh }
                                    MouseArea {
                                        anchors.fill: parent
                                        // Don't swallow taps over the forget button.
                                        anchors.rightMargin: row.modelData.paired ? 46 : 14
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: scope.activate(row.modelData)
                                    }
                                }
                            }

                            // empty state
                            Text {
                                visible: (scope.bt.devices || []).length === 0
                                width: listCol.width
                                horizontalAlignment: Text.AlignHCenter
                                topPadding: 18; bottomPadding: 18
                                text: scope.bt.scanning ? "Scanning…" : "No devices found"
                                color: "#8e8e96"
                                font.family: "Inter"
                                font.pixelSize: 12
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }

                    // ---- advanced (blueman-manager) --------------------------
                    Rectangle {
                        width: parent.width
                        height: 38
                        radius: 11
                        color: advHover.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                        Behavior on color { ColorAnimation { duration: 160 } }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰒓"
                            color: "#c9c9d0"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 15
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 40
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Advanced settings (Blueman)"
                            color: "#c9c9d0"
                            font.family: "Inter"
                            font.pixelSize: 13
                        }
                        HoverHandler { id: advHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Quickshell.execDetached(["blueman-manager"])
                                scope.close()
                            }
                        }
                    }
                }
            }
        }
    }
}
