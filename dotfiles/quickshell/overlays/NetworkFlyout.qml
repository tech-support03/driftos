// ~/.config/quickshell/overlays/NetworkFlyout.qml — network manager flyout.
//
// Triggered by `qs ipc call network toggle` (wired to the SideBar network
// button). Same overlay idiom as PowerFlyout/Launcher: full-screen Overlay
// layer, dim backdrop, click-outside / Escape closes, exclusive keyboard
// focus (needed so the inline password field can capture input).
//
// All link state + actions come from services/Network.qml; this file is the
// UI surface only — current status, wifi on/off, rescan, and a scannable list
// of APs with inline password entry for secured/unknown networks. The
// "Advanced" button drops to `nmtui` (ships with NetworkManager) for wired
// edits and anything this panel intentionally leaves out.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../services" as Services

Scope {
    id: scope

    readonly property var net: Services.Network

    property bool   active: false
    property string expandedSsid: ""   // SSID whose password field is open
    property string statusMsg: ""

    function open() {
        panel.visible = true
        active = true
        expandedSsid = ""
        statusMsg = ""
        net.refresh()
        net.rescan()
        Qt.callLater(() => content.forceActiveFocus())
    }
    function close() {
        active = false
        expandedSsid = ""
        hideTimer.restart()
    }
    function toggle() { active ? close() : open() }

    // Clicking a network row: active → disconnect; open/saved → connect
    // immediately; enterprise (802.1X) & unknown → hand off to nmtui, which can
    // capture the username + EAP method a PSK box can't; otherwise secured &
    // unknown → reveal the inline password field.
    function activate(n) {
        if (n.active) { net.disconnectWifi(); return }
        if (n.enterprise && !n.saved) {
            // School/eduroam-style WPA2/WPA3-Enterprise: set up in nmtui.
            Quickshell.execDetached(["alacritty", "-e", "nmtui", "edit"])
            scope.close()
            return
        }
        if (!n.secured || n.saved) {
            net.connectWifi(n.ssid, n.secured, "")
            statusMsg = "Connecting to " + n.ssid + "…"
        } else if (expandedSsid === n.ssid) {
            // handled by the field's submit
        } else {
            expandedSsid = n.ssid
        }
    }
    function submitPassword(ssid, secured, pw) {
        if (!pw.length) return
        net.connectWifi(ssid, secured, pw)
        statusMsg = "Connecting to " + ssid + "…"
        expandedSsid = ""
    }

    Connections {
        target: scope.net
        function onActionFinished(ok, message) {
            scope.statusMsg = ok ? "" : (message.length ? message : "Connection failed")
        }
    }

    Timer {
        id: hideTimer
        interval: 220
        onTriggered: if (!scope.active) panel.visible = false
    }

    IpcHandler {
        target: "network"
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
        WlrLayershell.namespace: "quickshell-network"
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
            // belonging to the SideBar that launched it.
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

                    // ---- header: current link --------------------------------
                    Item {
                        width: parent.width
                        height: 44

                        Rectangle {
                            id: hIcon
                            width: 44; height: 44; radius: 13
                            color: scope.net.connected ? Qt.rgba(0.65, 0.85, 1.0, 0.16)
                                                        : Qt.rgba(1, 1, 1, 0.05)
                            Text {
                                anchors.centerIn: parent
                                text: scope.net.glyph || "󰤯"
                                color: scope.net.connected ? "#60a5fa" : "#8e8e96"
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
                                text: scope.net.connected
                                      ? scope.net.primaryName
                                      : (scope.net.wifiEnabled ? "Not connected" : "Wi-Fi off")
                                color: "#f4f4f6"
                                font.family: "Inter"
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                width: 230
                            }
                            Text {
                                text: scope.net.connected
                                      ? (scope.net.primaryType === "ethernet"
                                         ? "Wired connection"
                                         : "Wi-Fi · " + scope.net.wifiSignal + "%")
                                      : "Select a network below"
                                color: "#8e8e96"
                                font.family: "Inter"
                                font.pixelSize: 11
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }

                    // ---- controls: wifi toggle + rescan ----------------------
                    Item {
                        width: parent.width
                        height: 30

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Wi-Fi"
                            color: "#c9c9d0"
                            font.family: "Inter"
                            font.pixelSize: 13
                        }

                        // Pill toggle
                        Rectangle {
                            id: toggle
                            anchors.left: parent.left
                            anchors.leftMargin: 54
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40; height: 22; radius: 11
                            color: scope.net.wifiEnabled ? Qt.rgba(0.65, 0.85, 1.0, 0.55)
                                                          : Qt.rgba(1, 1, 1, 0.10)
                            Behavior on color { ColorAnimation { duration: 180 } }
                            Rectangle {
                                width: 16; height: 16; radius: 8
                                color: "#f4f4f6"
                                y: 3
                                x: scope.net.wifiEnabled ? parent.width - width - 3 : 3
                                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: scope.net.toggleWifi()
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
                                color: scope.net.scanning ? "#60a5fa" : "#c9c9d0"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 16
                                RotationAnimation on rotation {
                                    running: scope.net.scanning === true
                                    loops: Animation.Infinite
                                    from: 0; to: 360; duration: 900
                                    onStopped: rescanIcon.rotation = 0
                                }
                            }
                            HoverHandler { id: rescanHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: scope.net.rescan()
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

                    // ---- network list ----------------------------------------
                    Flickable {
                        width: parent.width
                        height: Math.min(330, listCol.implicitHeight)
                        contentHeight: listCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        visible: scope.net.wifiEnabled !== false

                        Column {
                            id: listCol
                            width: parent.width
                            spacing: 2

                            Repeater {
                                model: scope.net.networks || []

                                delegate: Column {
                                    id: row
                                    required property var modelData
                                    width: listCol.width
                                    spacing: 0

                                    Rectangle {
                                        width: parent.width
                                        height: 46
                                        radius: 11
                                        color: row.modelData.active
                                               ? Qt.rgba(0.65, 0.85, 1.0, 0.14)
                                               : (rh.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                                        Behavior on color { ColorAnimation { duration: 160 } }

                                        Text {
                                            id: sg
                                            anchors.left: parent.left
                                            anchors.leftMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: scope.net.signalGlyph(row.modelData.signal)
                                            color: row.modelData.active ? "#60a5fa" : "#c9c9d0"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 18
                                        }
                                        Text {
                                            anchors.left: sg.right
                                            anchors.leftMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: row.modelData.ssid
                                            color: "#f4f4f6"
                                            font.family: "Inter"
                                            font.pixelSize: 13
                                            font.weight: row.modelData.active ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                            width: 210
                                        }
                                        // check = active · ID badge = enterprise
                                        // (802.1X) · lock = secured PSK
                                        Text {
                                            anchors.right: parent.right
                                            anchors.rightMargin: 14
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: row.modelData.active ? "󰄬"
                                                  : (row.modelData.enterprise ? "󰉹"
                                                  : (row.modelData.secured ? "󰌾" : ""))
                                            color: row.modelData.active ? "#86efac" : "#8e8e96"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: row.modelData.active ? 15 : 12
                                        }

                                        HoverHandler { id: rh }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: scope.activate(row.modelData)
                                        }
                                    }

                                    // inline password field (secured + unknown)
                                    Item {
                                        width: parent.width
                                        height: open ? 44 : 0
                                        clip: true
                                        readonly property bool open: scope.expandedSsid === row.modelData.ssid
                                        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                        onOpenChanged: if (open) Qt.callLater(() => pwField.forceActiveFocus())

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.topMargin: 2
                                            anchors.bottomMargin: 8
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 4
                                            radius: 10
                                            color: Qt.rgba(1, 1, 1, 0.05)
                                            border.color: pwField.activeFocus ? Qt.rgba(0.65, 0.85, 1.0, 0.5)
                                                                              : Qt.rgba(1, 1, 1, 0.08)
                                            border.width: 1

                                            TextInput {
                                                id: pwField
                                                anchors.left: parent.left
                                                anchors.leftMargin: 12
                                                anchors.right: goBtn.left
                                                anchors.rightMargin: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: "#f4f4f6"
                                                font.family: "Inter"
                                                font.pixelSize: 13
                                                echoMode: TextInput.Password
                                                clip: true
                                                onAccepted: scope.submitPassword(
                                                    row.modelData.ssid, row.modelData.secured, text)

                                                Text {
                                                    anchors.fill: parent
                                                    verticalAlignment: Text.AlignVCenter
                                                    visible: pwField.text.length === 0
                                                    text: "Password"
                                                    color: "#6b7280"
                                                    font: pwField.font
                                                }
                                            }
                                            Rectangle {
                                                id: goBtn
                                                anchors.right: parent.right
                                                anchors.rightMargin: 4
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 28; height: 28; radius: 8
                                                color: goHover.hovered ? Qt.rgba(0.65, 0.85, 1.0, 0.30)
                                                                       : Qt.rgba(0.65, 0.85, 1.0, 0.18)
                                                Behavior on color { ColorAnimation { duration: 140 } }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "󰜷"
                                                    color: "#60a5fa"
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 14
                                                }
                                                HoverHandler { id: goHover }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: scope.submitPassword(
                                                        row.modelData.ssid, row.modelData.secured, pwField.text)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // empty state
                            Text {
                                visible: (scope.net.networks || []).length === 0
                                width: listCol.width
                                horizontalAlignment: Text.AlignHCenter
                                topPadding: 18; bottomPadding: 18
                                text: scope.net.scanning ? "Scanning…" : "No networks found"
                                color: "#8e8e96"
                                font.family: "Inter"
                                font.pixelSize: 12
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }

                    // ---- advanced (nmtui) ------------------------------------
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
                            text: "Advanced settings (nmtui)"
                            color: "#c9c9d0"
                            font.family: "Inter"
                            font.pixelSize: 13
                        }
                        HoverHandler { id: advHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Quickshell.execDetached(["alacritty", "-e", "nmtui"])
                                scope.close()
                            }
                        }
                    }
                }
            }
        }
    }
}
