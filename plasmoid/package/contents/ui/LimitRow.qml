// SPDX-FileCopyrightText: 2026 pe7ro
// SPDX-License-Identifier: MIT
// One plan limit window in the popup: name and percentage, a bar, when it resets.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "format.js" as Fmt

ColumnLayout {
    id: row

    property string label
    property var limit: null
    property real now: 0
    property real warnAt: 70
    property real criticalAt: 90

    readonly property bool reset: Fmt.isReset(limit, now)
    readonly property string level: Fmt.level(limit, now, warnAt, criticalAt)

    spacing: Math.round(Kirigami.Units.smallSpacing / 2)

    RowLayout {
        Layout.fillWidth: true

        PlasmaComponents.Label {
            text: row.label
            font.bold: true
        }
        Item { Layout.fillWidth: true }
        PercentLabel {
            text: Fmt.limitValue(row.limit, row.now)
            level: row.level
        }
    }

    Bar {
        Layout.fillWidth: true
        value: row.limit && !row.reset ? row.limit.used_percentage : 0
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        text: Fmt.limitDetail(row.limit, row.now)
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        elide: Text.ElideRight
    }
}
