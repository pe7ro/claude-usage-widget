// SPDX-FileCopyrightText: 2026 pe7ro
// SPDX-License-Identifier: MIT
// The panel part: the 5-hour usage large, the time left until it resets small beneath it,
// stacked the way the digital clock stacks time over date.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "format.js" as Fmt

MouseArea {
    id: compact

    property var limit: null
    property real now: 0
    property bool failed: false
    property real warnAt: 70
    property real criticalAt: 90
    signal activated()

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property var lines: failed ? ({ top: "!", bottom: "error" }) : Fmt.compactLines(limit, now)
    readonly property string level: failed ? "critical" : Fmt.level(limit, now, warnAt, criticalAt)

    // Font sizes follow the panel's thickness; in a vertical panel, its width.
    readonly property int topSize: Math.max(9, Math.round(vertical ? width / 3.2 : height * 0.5))
    readonly property int bottomSize: Math.max(8, Math.round(vertical ? width / 5 : height * 0.3))

    // As wide as the widest text it will ever show, so the panel doesn't shift as digits change.
    readonly property real contentWidth: Math.ceil(Math.max(topWidest.width, bottomWidest.width,
                                                            top.implicitWidth, bottom.implicitWidth))

    Layout.minimumWidth: vertical ? -1 : contentWidth + Kirigami.Units.smallSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.maximumWidth: vertical ? -1 : Layout.minimumWidth
    Layout.minimumHeight: vertical ? column.implicitHeight + Kirigami.Units.smallSpacing * 2 : -1
    Layout.preferredHeight: Layout.minimumHeight

    hoverEnabled: true
    onClicked: activated()

    TextMetrics { id: topWidest; font: top.font; text: "100%" }
    TextMetrics { id: bottomWidest; font: bottom.font; text: "4h 59m" }

    ColumnLayout {
        id: column
        anchors.centerIn: parent
        spacing: 0

        PlasmaComponents.Label {
            id: top
            Layout.alignment: Qt.AlignHCenter
            text: compact.lines.top
            font.pixelSize: compact.topSize
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
            lineHeightMode: Text.FixedHeight
            lineHeight: compact.topSize
            topPadding: 0
            bottomPadding: 0
            color: compact.level === "critical" ? Kirigami.Theme.negativeTextColor
                 : compact.level === "warn" ? Kirigami.Theme.neutralTextColor
                 : Kirigami.Theme.textColor
            opacity: compact.level === "none" ? 0.6 : 1
        }

        PlasmaComponents.Label {
            id: bottom
            Layout.alignment: Qt.AlignHCenter
            text: compact.lines.bottom
            font.pixelSize: compact.bottomSize
            font.features: ({ "tnum": 1 })
            lineHeightMode: Text.FixedHeight
            lineHeight: Math.round(compact.bottomSize * 1.1)
            topPadding: 0
            bottomPadding: 0
            opacity: 0.75
        }
    }
}
