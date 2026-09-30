// SPDX-FileCopyrightText: 2026 pe7ro
// SPDX-License-Identifier: MIT
// A share in percent as a bar. Drawn here rather than with the Plasma progress bar, whose color
// and thickness come from the theme's SVG.
import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: bar

    property real value: 0  // 0 to 100
    property color fillColor: Kirigami.Theme.highlightColor

    // A little thicker than the Breeze progress bar.
    implicitHeight: Math.round(Kirigami.Units.smallSpacing * 1.5)
    radius: height / 2
    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)

    Rectangle {
        width: bar.width * Math.max(0, Math.min(100, bar.value)) / 100
        height: bar.height
        radius: bar.radius
        color: bar.fillColor
        visible: width > 0
    }
}
