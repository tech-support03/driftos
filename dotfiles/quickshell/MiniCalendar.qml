import QtQuick

// Compact current-month calendar grid with today highlighted.
Item {
    id: root

    property date today: new Date()

    readonly property int year: today.getFullYear()
    readonly property int month: today.getMonth()
    readonly property int todayDate: today.getDate()
    readonly property int firstDow: new Date(year, month, 1).getDay()        // 0 = Sunday
    readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()

    implicitWidth: 210
    implicitHeight: header.height + grid.height + 8

    Column {
        anchors.centerIn: parent
        spacing: 6

        Text {
            id: header
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(root.today, "MMMM yyyy")
            color: "#e5e7eb"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
            font.weight: Font.DemiBold
        }

        Grid {
            id: grid
            columns: 7
            rowSpacing: 3
            columnSpacing: 3
            anchors.horizontalCenter: parent.horizontalCenter

            Repeater {
                model: ["S", "M", "T", "W", "T", "F", "S"]
                Item {
                    width: 27; height: 19
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: "#6b7280"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }
                }
            }

            Repeater {
                model: 42
                Item {
                    id: cell
                    width: 27; height: 19
                    readonly property int dayNum: index - root.firstDow + 1
                    readonly property bool valid: dayNum >= 1 && dayNum <= root.daysInMonth
                    readonly property bool isToday: valid && dayNum === root.todayDate

                    Rectangle {
                        anchors.centerIn: parent
                        width: 23; height: 18
                        radius: 6
                        visible: cell.isToday
                        color: "#7c3aed"
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: cell.valid
                        text: cell.valid ? cell.dayNum : ""
                        color: cell.isToday ? "#ffffff" : "#cbd5e1"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
