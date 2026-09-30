// SPDX-FileCopyrightText: 2026 pe7ro
// SPDX-License-Identifier: MIT
// The percentage at the right of a popup row, colored by how close it is to the limit.
import QtQuick
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmaComponents.Label {
    // "none" | "normal" | "warn" | "critical", from Fmt.level / Fmt.contextLevel
    property string level: "none"

    font.bold: true
    color: level === "critical" ? Kirigami.Theme.negativeTextColor
         : level === "warn" ? Kirigami.Theme.neutralTextColor
         : Kirigami.Theme.textColor
    opacity: level === "none" ? 0.6 : 1
}
