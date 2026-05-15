import QtQuick

// Animated cava-driven waveform. `bars` is an array of ints in [0, maxValue].
Item {
    id: root

    property var bars: []
    property int barCount: 44
    property real maxValue: 1000
    property color barColor: "#a78bfa"

    implicitWidth: barCount * 7 - 3
    implicitHeight: 42

    Row {
        anchors.centerIn: parent
        spacing: 3

        Repeater {
            model: root.barCount

            Rectangle {
                id: bar
                width: 4
                radius: 2
                color: root.barColor
                anchors.verticalCenter: parent.verticalCenter

                readonly property real value:
                    (root.bars && index < root.bars.length) ? root.bars[index] : 0
                height: Math.max(2, (value / root.maxValue) * root.implicitHeight)

                Behavior on height {
                    NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
                }
            }
        }
    }
}
