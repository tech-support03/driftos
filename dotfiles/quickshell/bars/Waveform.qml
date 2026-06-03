import QtQuick

// Animated cava-driven waveform. `bars` is an array of ints in [0, maxValue].
Item {
    id: root

    property var bars: []
    property int barCount: 44
    property real maxValue: 1000
    property color barColor: "#5b6ee0"

    // bar=3, gap=2 → 44*5-2=218px wide, 28px tall (was 305×42)
    implicitWidth: barCount * 5 - 2
    implicitHeight: 28

    Row {
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.barCount

            Rectangle {
                id: bar
                width: 3
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
