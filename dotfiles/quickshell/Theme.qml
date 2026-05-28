// ~/.config/quickshell/Theme.qml — single source of truth
pragma Singleton
import QtQuick

QtObject {
    // Colors
    readonly property color accent:   "#c5b3ff"
    readonly property color accent2:  "#a5d8ff"
    readonly property color accent3:  "#b5f0d4"
    readonly property color danger:   "#e87575"
    readonly property color fg0:      "#f4f4f6"
    readonly property color fg1:      "#c9c9d0"
    readonly property color fg2:      "#8e8e96"
    readonly property color fg3:      "#5e5e66"
    readonly property color line:     Qt.rgba(1,1,1,0.09)

    // Translucency
    readonly property real  alpha:    0.32
    readonly property color surface:  Qt.rgba(0.086, 0.086, 0.110, alpha)
    readonly property color surface2: Qt.rgba(0.110, 0.110, 0.133, alpha + 0.18)
    readonly property color surface3: Qt.rgba(1,1,1,0.05)
    readonly property int   blur:     32

    // Shape
    readonly property int radius:      18
    readonly property int radiusSmall: 12
    readonly property int gap:         12
    readonly property int sidebarW:    72

    // Animation
    readonly property int  animFast: 180
    readonly property int  animMed:  240
    readonly property int  animSlow: 380
    // Use easing.bezierCurve: [x1,y1,x2,y2]
    readonly property var  easeOut:  [0.2, 0.85, 0.25, 1.0]

    // Fonts
    readonly property string fontSans: "Inter"
    readonly property string fontMono: "JetBrainsMono Nerd Font"
}
