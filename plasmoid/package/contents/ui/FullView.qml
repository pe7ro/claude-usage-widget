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
    property bool showActivity: true
    property bool showClosed: true

    readonly property var limits: report && report.limits ? report.limits : ({})
    readonly property var allSessions: report && report.sessions ? report.sessions : []
    readonly property var sessions: showClosed ? allSessions : allSessions.filter(s => s.state !== "ended")
    // Missing altogether from a claude-usage older than the session states: then nothing to say.
    readonly property string liveError: showActivity && report && report.live && !report.live.available
                                        ? (report.live.error || "unknown error") : ""

    // Plasma remembers a popup's size (popupWidth in the applet config) and only the minimum
    // overrides it, so the minimum is what makes an existing popup wider.
    Layout.minimumWidth: Kirigami.Units.gridUnit * 26
    Layout.preferredWidth: Kirigami.Units.gridUnit * 28
    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight
    // No taller than its content: a size remembered from a day with more sessions would
    // otherwise spread the rows apart. (The session list scrolls beyond its own cap anyway.)
    Layout.maximumHeight: implicitHeight
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

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: full.liveError !== ""
        text: "Session states unavailable: " + full.liveError
        font: Kirigami.Theme.smallFont
        wrapMode: Text.WordWrap
        opacity: 0.6
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
                showActivity: full.showActivity
            }
        }
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: full.sessions.length === 0
        text: full.allSessions.length > 0 ? "No open Claude Code session. Closed ones are hidden in the settings."
                                          : "No Claude Code session seen in the last 24 hours."
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

    // Takes any height left over, should the popup still be taller, so the rows stay together.
    Item {
        Layout.fillHeight: true
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        text: "Limits and context update whenever a Claude Code session gets a response, session states every 30 s. Plan limits need a claude.ai Pro or Max login."
        font: Kirigami.Theme.smallFont
        wrapMode: Text.WordWrap
        opacity: 0.6
    }
}
