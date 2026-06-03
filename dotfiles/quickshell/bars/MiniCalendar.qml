import QtQuick

// Compact navigable monthly calendar grid with today highlighted and hover effects.
Item {
    id: root

    property date today: new Date()

    // Separately tracked view state for month navigation
    property int viewYear:  today.getFullYear()
    property int viewMonth: today.getMonth()

    readonly property int todayYear:  today.getFullYear()
    readonly property int todayMonth: today.getMonth()
    readonly property int todayDate:  today.getDate()

    readonly property int firstDow:    new Date(viewYear, viewMonth, 1).getDay()
    readonly property int daysInMonth: new Date(viewYear, viewMonth + 1, 0).getDate()

    implicitWidth:  210
    implicitHeight: navHeader.height + calGrid.height + 14

    Column {
        anchors.centerIn: parent
        spacing: 6

        // ---- month navigation header ----------------------------------------
        Item {
            id: navHeader
            width: root.implicitWidth
            height: 20

            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "‹"
                color: prevHover.hovered ? Theme.accent : "#6b7280"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 18
                Behavior on color { ColorAnimation { duration: 100 } }
                HoverHandler { id: prevHover }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.viewMonth === 0) { root.viewMonth = 11; root.viewYear-- }
                        else root.viewMonth--
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
                color: "#e5e7eb"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "›"
                color: nextHover.hovered ? Theme.accent : "#6b7280"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 18
                Behavior on color { ColorAnimation { duration: 100 } }
                HoverHandler { id: nextHover }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.viewMonth === 11) { root.viewMonth = 0; root.viewYear++ }
                        else root.viewMonth++
                    }
                }
            }
        }

        // ---- day grid (weekday labels + cells in one flow) ------------------
        Grid {
            id: calGrid
            columns: 7
            rowSpacing: 2
            columnSpacing: 3
            anchors.horizontalCenter: parent.horizontalCenter

            Repeater {
                model: ["S", "M", "T", "W", "T", "F", "S"]
                Item {
                    width: 27; height: 18
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: "#6b7280"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                    }
                }
            }

            Repeater {
                model: 42
                Item {
                    id: cell
                    width: 27; height: 22

                    readonly property int dayNum: index - root.firstDow + 1
                    readonly property bool valid: dayNum >= 1 && dayNum <= root.daysInMonth
                    readonly property bool isToday: valid
                        && dayNum    === root.todayDate
                        && root.viewYear  === root.todayYear
                        && root.viewMonth === root.todayMonth

                    HoverHandler { id: cellHover; enabled: cell.valid }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 24; height: 20
                        radius: 6
                        color: cell.isToday             ? Theme.accent
                             : cellHover.hovered        ? Qt.rgba(1, 1, 1, 0.1)
                             : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: cell.valid
                        text: cell.valid ? cell.dayNum : ""
                        color: cell.isToday      ? "#ffffff"
                             : cellHover.hovered ? "#e5e7eb"
                             : "#9ca3af"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: cell.valid
                        cursorShape: Qt.PointingHandCursor
                        // Clicking a day in another month jumps the view to that month
                        onClicked: {}
                    }
                }
            }
        }
    }
}
