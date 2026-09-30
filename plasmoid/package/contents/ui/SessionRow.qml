// SPDX-FileCopyrightText: 2026 pe7ro
// SPDX-License-Identifier: MIT
// One Claude Code session in the popup: which one, how much of its context is used.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "format.js" as Fmt

ColumnLayout {
    id: row

    property var session
    property real now: 0
    property real warnAt: 70
    property real criticalAt: 90

    readonly property var ctx: session && session.context ? session.context : ({})

    spacing: Math.round(Kirigami.Units.smallSpacing / 2)
    opacity: session && session.state === "active" ? 1 : 0.6

    RowLayout {
        Layout.fillWidth: true

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: row.session.title
            font.bold: true
            elide: Text.ElideRight
        }
        PlasmaComponents.Label {
            text: row.session.model_short || row.session.model || ""
            opacity: 0.7
        }
        PlasmaComponents.Label {
            text: Fmt.sessionState(row.session, row.now)
            opacity: 0.7
        }
        PercentLabel {
            Layout.leftMargin: Kirigami.Units.smallSpacing
            text: Fmt.contextValue(row.ctx)
            level: Fmt.contextLevel(row.ctx, row.warnAt, row.criticalAt)
        }
    }

    PlasmaComponents.ProgressBar {
        Layout.fillWidth: true
        from: 0
        to: 100
        value: row.ctx.used_percentage ?? 0
        indeterminate: false
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        text: Fmt.sessionDetail(row.session)
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        elide: Text.ElideMiddle
    }
}
