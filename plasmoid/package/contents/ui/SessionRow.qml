// SPDX-FileCopyrightText: 2026 pe7ro
// SPDX-License-Identifier: MIT
// One Claude Code session in the popup: which one, how much of its context is used, and (the
// bar's color) whether it is working, needs you, is ready for your next prompt, or was closed.
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
    property bool showActivity: true

    readonly property var ctx: session && session.context ? session.context : ({})
    readonly property string activity: Fmt.activityLevel(session, showActivity)
    readonly property color textColor: Kirigami.Theme.textColor

    spacing: Math.round(Kirigami.Units.smallSpacing / 2)
    opacity: Fmt.dimmed(session, showActivity) ? 0.6 : 1

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
            text: Fmt.sessionState(row.session, row.now, row.showActivity)
            color: row.activity === "needs_input" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
            opacity: row.activity === "needs_input" ? 1 : 0.7
        }
        PercentLabel {
            Layout.leftMargin: Kirigami.Units.smallSpacing
            text: Fmt.contextValue(row.ctx)
            level: Fmt.contextLevel(row.ctx, row.warnAt, row.criticalAt)
        }
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: row.activity === "needs_input"
        text: Fmt.needsYouLine(row.session)
        color: Kirigami.Theme.neutralTextColor
        font: Kirigami.Theme.smallFont
        elide: Text.ElideRight
    }

    Bar {
        Layout.fillWidth: true
        value: row.ctx.used_percentage ?? 0
        fillColor: row.activity === "working" ? Kirigami.Theme.highlightColor
                 : row.activity === "needs_input" ? Kirigami.Theme.neutralTextColor
                 : row.activity === "ready" ? Qt.darker(Kirigami.Theme.positiveTextColor, 1.2)
                 : row.activity === "closed" ? Qt.rgba(row.textColor.r, row.textColor.g, row.textColor.b, 0.35)
                 : Kirigami.Theme.highlightColor
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        text: Fmt.sessionDetail(row.session)
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        elide: Text.ElideMiddle
    }
}
