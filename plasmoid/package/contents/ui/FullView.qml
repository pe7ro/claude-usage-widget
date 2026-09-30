// SPDX-FileCopyrightText: 2026 pe7ro
// SPDX-License-Identifier: MIT
// The popup: the plan limits, then every Claude Code session seen lately.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: full

    property var report: null
    property real now: 0
    property string error: ""
    property real warnAt: 70
    property real criticalAt: 90

    readonly property var limits: report && report.limits ? report.limits : ({})
    readonly property var sessions: report && report.sessions ? report.sessions : []

    // Plasma remembers a popup's size (popupWidth in the applet config) and only the minimum
    // overrides it, so the minimum is what makes an existing popup wider.
    Layout.minimumWidth: Kirigami.Units.gridUnit * 26
    Layout.preferredWidth: Kirigami.Units.gridUnit * 28
    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight
    spacing: Kirigami.Units.smallSpacing

    SectionHeading {
        text: "Plan limits"
    }

    LimitRow {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        label: "5 hours"
        limit: full.limits.five_hour || null
        now: full.now
        warnAt: full.warnAt
        criticalAt: full.criticalAt
    }

    LimitRow {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        label: "7 days"
        limit: full.limits.seven_day || null
        now: full.now
        warnAt: full.warnAt
        criticalAt: full.criticalAt
    }

    LimitRow {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        visible: !!full.limits.spend_limit
        label: "Spend limit"
        limit: full.limits.spend_limit || null
        now: full.now
        warnAt: full.warnAt
        criticalAt: full.criticalAt
    }

    SectionHeading {
        Layout.topMargin: Kirigami.Units.largeSpacing
        text: "Sessions"
    }

    PlasmaComponents.ScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.preferredHeight: Math.min(list.contentHeight, Kirigami.Units.gridUnit * 26)
        visible: full.sessions.length > 0

        ListView {
            id: list
            model: full.sessions
            spacing: Kirigami.Units.largeSpacing
            clip: true
            interactive: contentHeight > height
            delegate: SessionRow {
                required property var modelData
                // Leave room for the scroll bar instead of drawing under it.
                width: ListView.view.width - (scroll.QQC2.ScrollBar.vertical.visible
                                              ? scroll.QQC2.ScrollBar.vertical.width + Kirigami.Units.smallSpacing : 0)
                session: modelData
                now: full.now
                warnAt: full.warnAt
                criticalAt: full.criticalAt
            }
        }
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: full.sessions.length === 0
        text: "No Claude Code session seen in the last 24 hours."
        wrapMode: Text.WordWrap
        opacity: 0.7
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: full.error !== ""
        text: "Error: " + full.error
        color: Kirigami.Theme.negativeTextColor
        wrapMode: Text.WordWrap
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        text: "Updated whenever a Claude Code session gets a response. Plan limits need a claude.ai Pro or Max login."
        font: Kirigami.Theme.smallFont
        wrapMode: Text.WordWrap
        opacity: 0.6
    }
}
