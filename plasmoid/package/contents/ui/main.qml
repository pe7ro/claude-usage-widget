// SPDX-FileCopyrightText: 2026 pe7ro
// SPDX-License-Identifier: MIT
// Claude Usage: the Claude Code 5-hour plan limit in the panel, everything else in the popup.
//
// The numbers come from the `claude-usage` command (installed separately, see the README),
// which Claude Code runs as its status line command; this file only asks it for a report every
// pollMs and renders it.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

import "format.js" as Fmt

PlasmoidItem {
    id: root

    // The data only changes when a Claude Code session gets a response, so polling faster buys
    // nothing; the countdowns are recomputed from the clock on the same tick.
    readonly property int pollMs: 30 * 1000
    readonly property real warnAt: 70
    readonly property real criticalAt: 90
    // The settings, ../config/main.xml
    readonly property bool showActivity: Plasmoid.configuration.showActivity
    readonly property bool showClosed: Plasmoid.configuration.showClosed
    readonly property bool panelIndicator: Plasmoid.configuration.panelIndicator

    property var report: null
    property string error: ""
    property real now: Date.now() / 1000

    readonly property var fiveHour: report && report.limits ? report.limits.five_hour : null
    readonly property int needsYou: showActivity ? Fmt.needsYouCount(report) : 0
    // The executable engine runs this through a shell. Plasma's own PATH may lack ~/.local/bin,
    // where claude-usage/install.sh puts the command.
    readonly property string command: 'PATH="$HOME/.local/bin:$PATH" claude-usage report --json'
    // The report layout this widget reads; claude_usage.py bumps it only for incompatible changes.
    readonly property int reportVersion: 1

    function refresh() {
        now = Date.now() / 1000
        runner.connectSource(command)
    }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            if (data["exit code"] == 127) {
                root.error = "the claude-usage command is not installed (README, part 1)"
                return
            }
            if (data["exit code"] != 0) {
                root.error = (data.stderr || "").trim() || ("report exited with " + data["exit code"])
                return
            }
            var report
            try {
                report = JSON.parse(data.stdout)
            } catch (e) {
                root.error = "unreadable report: " + e
                return
            }
            if (report.version !== root.reportVersion) {
                root.error = "claude-usage reports version " + report.version + ", this widget reads "
                           + root.reportVersion + ": upgrade both"
                return
            }
            root.report = report
            root.error = ""
        }
    }

    Timer {
        interval: root.pollMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    onExpandedChanged: if (expanded) refresh()

    toolTipMainText: "Claude plan usage"
    toolTipSubText: Fmt.tooltip(report, now, error, showActivity)

    compactRepresentation: CompactView {
        limit: root.fiveHour
        now: root.now
        failed: root.error !== ""
        warnAt: root.warnAt
        criticalAt: root.criticalAt
        dotEnabled: root.showActivity && root.panelIndicator
        needsYou: root.needsYou
        onActivated: root.expanded = !root.expanded
    }

    fullRepresentation: FullView {
        report: root.report
        now: root.now
        error: root.error
        warnAt: root.warnAt
        criticalAt: root.criticalAt
        showActivity: root.showActivity
        showClosed: root.showClosed
    }
}
