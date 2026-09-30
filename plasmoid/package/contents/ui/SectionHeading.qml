// SPDX-FileCopyrightText: 2026 pe7ro
// SPDX-License-Identifier: MIT
// A section title in the popup, on a faint full-width band so the sections stand apart.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

Rectangle {
    property alias text: heading.text

    Layout.fillWidth: true
    implicitHeight: heading.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.cornerRadius
    // Translucent text color rather than a fixed gray: it works on light, dark and blurred popups.
    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)

    PlasmaExtras.Heading {
        id: heading
        anchors {
            left: parent.left
            right: parent.right
            leftMargin: Kirigami.Units.largeSpacing
            rightMargin: Kirigami.Units.largeSpacing
            verticalCenter: parent.verticalCenter
        }
        level: 4
        elide: Text.ElideRight
    }
}
