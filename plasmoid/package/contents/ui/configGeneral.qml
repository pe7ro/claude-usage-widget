// SPDX-FileCopyrightText: 2026 pe7ro
// SPDX-License-Identifier: MIT
// The settings page; the entries are in ../config/main.xml.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_showActivity: showActivity.checked
    property alias cfg_showClosed: showClosed.checked
    property alias cfg_panelIndicator: panelIndicator.checked
    // Plasma hands the page each entry's default as well; these give it somewhere to go.
    property bool cfg_showActivityDefault
    property bool cfg_showClosedDefault
    property bool cfg_panelIndicatorDefault

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: showActivity
            Kirigami.FormData.label: "Sessions:"
            text: "Show whether each one is working, needs you or is ready"
        }
        QQC2.CheckBox {
            id: showClosed
            text: "List closed sessions"
        }
        QQC2.CheckBox {
            id: panelIndicator
            Kirigami.FormData.label: "Panel:"
            text: "Show a dot while a session needs you"
            enabled: showActivity.checked
        }
    }
}
