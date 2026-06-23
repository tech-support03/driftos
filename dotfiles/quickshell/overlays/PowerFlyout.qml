// ~/.config/quickshell/overlays/PowerFlyout.qml — power menu flyout.
//
// Triggered by `qs ipc call power toggle` (wired to Mod+Escape in niri).
// Same overlay idiom as Launcher.qml: full-screen Overlay layer with a
// dim backdrop, click-outside / Escape closes, focus is exclusive while
// open. Arrow keys move the selection, Enter fires it.
//
// Power verbs go through `systemctl` (poweroff/reboot/suspend) — these
// route through logind + polkit, so the active-session user can run them
// without a password. NB: `loginctl` does NOT have these verbs (only
// session/seat management), so the earlier loginctl-based wiring silently
// failed. Lock matches the niri Mod+L invocation (hyprlock is the only
// lock surface — parallel fingerprint + password).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"

Scope {
    id: scope

    property bool active: false
    property int  selected: 0

    // Every action runs through `sh -c` so the shell handles PATH resolution
    // and the wrapper's stderr can be redirected to a log file (`~/.cache/qs-
    // power.log`). Without the sh layer, calling `loginctl poweroff` directly
    // through execDetached was a no-op on this setup — wrapping it the same
    // way the Lock action is wrapped makes everything fire reliably.
    readonly property var actions: [
        { label: "Lock",      glyph: "",  shell: "pgrep -x hyprlock || hyprlock", danger: false },
        { label: "Sign out",  glyph: "",  shell: "niri msg action quit --skip-confirmation",                                 danger: false },
        { label: "Suspend",   glyph: "",  shell: "systemctl suspend",                                                        danger: false },
        { label: "Reboot",    glyph: "",  shell: "systemctl reboot",                                                         danger: true  },
        { label: "Power off", glyph: "",  shell: "systemctl poweroff",                                                       danger: true  },
    ]

    function open() {
        panel.visible = true
        selected = 0
        active = true
        Qt.callLater(() => content.forceActiveFocus())
    }
    function close() {
        active = false
        hideTimer.restart()
    }
    function toggle() { active ? close() : open() }

    function fire(i) {
        const a = actions[i]
        if (!a) return
        // execDetached forks+execs the child as an independent process so it
        // survives Quickshell — critical for `loginctl poweroff`/`reboot`,
        // which kill the parent before they finish. Wrap in sh -c so stderr
        // is captured for postmortem debugging if a future verb ever stops
        // firing again.
        Quickshell.execDetached(["sh", "-c",
            "{ " + a.shell + "; } 2>>\"$HOME/.cache/qs-power.log\""])
        close()
    }

    Timer {
        id: hideTimer
        interval: 220
        onTriggered: if (!scope.active) panel.visible = false
    }

    IpcHandler {
        target: "power"
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
        WlrLayershell.namespace: "quickshell-power"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // Dim backdrop. Lighter than the launcher's 0.84 so the desktop
        // stays partly visible behind the flyout.
        Rectangle {
            id: dim
            anchors.fill: parent
            color: Qt.rgba(0.04, 0.04, 0.06, 0.55)
            opacity: scope.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutQuad } }

            MouseArea {
                anchors.fill: parent
                onClicked: scope.close()
            }
        }

        Item {
            id: content
            anchors.fill: parent
            focus: true
            opacity: scope.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutQuad } }

            Keys.onEscapePressed: scope.close()
            Keys.onUpPressed:   scope.selected = (scope.selected - 1 + scope.actions.length) % scope.actions.length
            Keys.onDownPressed: scope.selected = (scope.selected + 1) % scope.actions.length
            Keys.onReturnPressed: scope.fire(scope.selected)
            Keys.onEnterPressed:  scope.fire(scope.selected)

            // Translucent card — matches Theme.surface2 (alpha 0.50, radius 18).
            Rectangle {
                id: card
                anchors.centerIn: parent
                width: 320
                implicitHeight: list.implicitHeight + 28
                radius: 18
                color: Qt.rgba(0.110, 0.110, 0.133, 0.50)
                border.color: Qt.rgba(1, 1, 1, 0.09)
                border.width: 1
                scale: scope.active ? 1.0 : 0.94
                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                Column {
                    id: list
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 4

                    Repeater {
                        model: scope.actions

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: 48
                            radius: 12

                            readonly property bool sel: scope.selected === row.index
                            readonly property bool dangerous: !!modelData.danger

                            color: row.sel
                                   ? (row.dangerous ? Qt.rgba(0.91, 0.46, 0.46, 0.18)
                                                    : Qt.rgba(0.77, 0.70, 1.0, 0.18))
                                   : (hh.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                            Behavior on color { ColorAnimation { duration: 180 } }

                            scale: ma.pressed ? 0.96 : 1.0
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                            Text {
                                id: glyph
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                text: row.modelData.glyph
                                color: row.dangerous ? "#e87575" : Theme.accent
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 16
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: glyph.right
                                anchors.leftMargin: 14
                                text: row.modelData.label
                                color: row.dangerous ? "#e87575" : "#f4f4f6"
                                font.family: "Inter"
                                font.pixelSize: 14
                            }

                            HoverHandler {
                                id: hh
                                onHoveredChanged: if (hovered) scope.selected = row.index
                            }
                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: scope.fire(row.index)
                            }
                        }
                    }
                }
            }
        }
    }
}
