pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
    id: root
    moduleName: "io.github.tug-benson.power-managment"
    manageIpc: false

    property var hostWidget: null
    property var anchorItem: null
    readonly property var barIdentity: hostWidget || root

    function switchPanel(direction) {
        if (bar && typeof bar.switchPanelFrom === "function")
            return bar.switchPanelFrom(barIdentity, direction)
        return false
    }

    readonly property var service: hostWidget && hostWidget.service ? hostWidget.service
        : (bar && bar.shell && typeof bar.shell.serviceFor === "function"
            ? (bar.shell.serviceFor("io.github.tug-benson.power-managment") || bar.shell.serviceFor("power-managment")) : null)

    // local editing copies (initialized from service when panel opens)
    property int editSaver: 1800
    property int editDisplay: 0
    property int editLock: 2700
    property string editIdleAction: "ignore"
    property int editIdleSec: 1800
    property string editLid: "suspend"
    property string editLidExt: "suspend"
    property string editLidDocked: "ignore"

    property bool timingsCollapsed: false
    property bool idleCollapsed: false
    property bool lidCollapsed: false

    readonly property var timeOptions: [
        { value: 0, label: "Never" },
        { value: 60, label: "1m" },
        { value: 120, label: "2m" },
        { value: 300, label: "5m" },
        { value: 600, label: "10m" },
        { value: 900, label: "15m" },
        { value: 1800, label: "30m" },
        { value: 2700, label: "45m" },
        { value: 3600, label: "60m" },
        { value: 5400, label: "90m" },
        { value: 7200, label: "120m" }
    ]
    readonly property var lidOptions: ["ignore", "suspend", "hibernate", "poweroff", "lock"]
    readonly property var idleOptions: ["ignore", "suspend", "suspend-then-hibernate", "hibernate", "poweroff", "lock"]

    function syncFromService() {
        if (!service) return
        editSaver = service.screensaverSec
        editDisplay = service.displayOffSec
        editLock = service.lockSec
        editIdleAction = service.idleAction
        editIdleSec = service.idleActionSec
        editLid = service.handleLidSwitch
        editLidExt = service.handleLidSwitchExternalPower
        editLidDocked = service.handleLidSwitchDocked
    }

    function formatLabel(sec) {
        if (sec === 0) return "Never"
        if (sec < 60) return sec + "s"
        return (sec / 60) + "m"
    }

    // when service updates while panel is open, reflect if not busy editing? simple sync on open
    Connections {
        target: service
        function onLastRefreshChanged() {
            // only auto-sync if user hasn't deviated too much? For v1, keep manual Apply
        }
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: Style.space(380)
        contentHeight: panel.fittedContentHeight(flick.contentHeight + Style.space(16))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function(dir) { root.switchPanel(dir) }

            Flickable {
                id: flick
                anchors.fill: parent
                contentWidth: width
                contentHeight: col.implicitHeight + Style.space(12)
                clip: true

                ColumnLayout {
                    id: col
                    width: flick.width - Style.space(16)
                    x: Style.space(8)
                    y: Style.space(8)
                    spacing: Style.space(8)

                    // ── Header ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(8)
                        Label {
                            textFormat: Text.PlainText
                            text: "󰐦"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Style.space(28)
                            color: Color.accent
                            Layout.alignment: Qt.AlignVCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label {
                                textFormat: Text.PlainText
                                text: "Power Managment"
                                font.family: Style.font.family
                                font.pixelSize: Style.font.title + 1
                                font.bold: true
                                color: Color.foreground
                            }
                            Label {
                                textFormat: Text.PlainText
                                text: service ? ((service.hypridleActive ? "hypridle ● active" : "hypridle ○ stopped") + " · " + service.powerProfile + (service.isLaptop ? " · laptop" : " · desktop")) : "--"
                                font.family: Style.font.family
                                font.pixelSize: Style.font.caption
                                color: Color.muted
                            }
                        }
                        Button {
                            iconText: ""
                            fontFamily: "JetBrainsMono Nerd Font"
                            fontSize: Style.font.caption
                            tooltipText: "Refresh"
                            Layout.preferredWidth: Style.space(26)
                            onClicked: { if (service) service.refresh(); root.syncFromService() }
                        }
                    }

                    // hypridle warning
                    Rectangle {
                        Layout.fillWidth: true
                        visible: service && !service.hypridleActive
                        radius: Style.space(6)
                        color: Util.alpha(Color.urgent, 0.12)
                        border.color: Util.alpha(Color.urgent, 0.35)
                        border.width: 1
                        implicitHeight: hyprWarnCol.implicitHeight + Style.space(12)
                        ColumnLayout {
                            id: hyprWarnCol
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            spacing: Style.space(4)
                            Label { textFormat: Text.PlainText; text: "hypridle not running"; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; color: Color.urgent }
                            Label { Layout.fillWidth: true; textFormat: Text.PlainText; text: "Run: systemctl --user enable --now hypridle"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: Style.font.caption - 1; color: Color.muted; wrapMode: Text.Wrap }
                        }
                    }

                    // error / info
                    Label {
                        Layout.fillWidth: true
                        visible: service && service.lastError
                        textFormat: Text.PlainText
                        text: service ? service.lastError : ""
                        font.family: Style.font.family; font.pixelSize: Style.font.caption; color: Color.urgent; wrapMode: Text.Wrap
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: service && service.lastInfo
                        textFormat: Text.PlainText
                        text: service ? service.lastInfo : ""
                        font.family: Style.font.family; font.pixelSize: Style.font.caption; color: Color.accent; wrapMode: Text.Wrap
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.rgba(1,1,1,0.08) }

                    // ── Timings section ──
                    Rectangle {
                        Layout.fillWidth: true
                        radius: Style.space(6)
                        color: Util.alpha(Color.foreground, 0.02)
                        border.color: Util.alpha(Color.foreground, 0.06)
                        border.width: 1
                        implicitHeight: timingsCol.implicitHeight + Style.space(12)
                        ColumnLayout {
                            id: timingsCol
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            spacing: Style.space(6)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(6)
                                Label {
                                    textFormat: Text.PlainText
                                    text: root.timingsCollapsed ? "" : ""
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Style.font.caption
                                    color: Color.accent
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.timingsCollapsed = !root.timingsCollapsed }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: "󰒲 Timings"
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    color: Color.foreground
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.timingsCollapsed = !root.timingsCollapsed }
                                }
                                Label {
                                    textFormat: Text.PlainText
                                    text: service ? (service.formatSec(service.screensaverSec) + " · " + service.formatSec(service.lockSec)) : ""
                                    font.pixelSize: Style.font.caption - 1
                                    color: Color.muted
                                    opacity: 0.7
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: !root.timingsCollapsed
                                spacing: Style.space(8)

                                // Screensaver row
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(4)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { textFormat: Text.PlainText; text: "󰒲 Screensaver"; font.family: Style.font.family; font.pixelSize: Style.font.caption; color: Color.muted; Layout.fillWidth: true }
                                        Label { textFormat: Text.PlainText; text: root.formatLabel(root.editSaver); font.family: Style.font.family; font.pixelSize: Style.font.caption; color: Color.accent; font.bold: true }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Style.space(6)
                                        PanelSlider {
                                            Layout.fillWidth: true
                                            bar: root.bar
                                            minimum: 0
                                            maximum: root.timeOptions.length - 1
                                            step: 1
                                            integer: true
                                            value: {
                                                for (var i=0;i<root.timeOptions.length;i++) if (root.timeOptions[i].value===root.editSaver) return i
                                                return 6
                                            }
                                            onMoved: function(v) {
                                                var idx = Math.round(v)
                                                if (idx>=0 && idx<root.timeOptions.length) root.editSaver = root.timeOptions[idx].value
                                            }
                                            onReleased: function(v) {
                                                var idx = Math.round(v)
                                                if (idx>=0 && idx<root.timeOptions.length) root.editSaver = root.timeOptions[idx].value
                                            }
                                        }
                                        Dropdown {
                                            value: String(root.editSaver)
                                            options: root.timeOptions.map(function(o){ return {value: String(o.value), label: o.label} })
                                            showLabel: false
                                            onChanged: function(v){ root.editSaver = parseInt(v,10) }
                                            implicitWidth: Style.space(90)
                                        }
                                    }
                                }

                                // Display off row
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(4)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { textFormat: Text.PlainText; text: "󰍹 Display off (DPMS)"; font.family: Style.font.family; font.pixelSize: Style.font.caption; color: Color.muted; Layout.fillWidth: true }
                                        Label { textFormat: Text.PlainText; text: root.formatLabel(root.editDisplay); font.family: Style.font.family; font.pixelSize: Style.font.caption; color: Color.accent; font.bold: true }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Style.space(6)
                                        PanelSlider {
                                            Layout.fillWidth: true
                                            bar: root.bar
                                            minimum: 0
                                            maximum: root.timeOptions.length - 1
                                            step: 1
                                            integer: true
                                            value: {
                                                for (var i=0;i<root.timeOptions.length;i++) if (root.timeOptions[i].value===root.editDisplay) return i
                                                return 0
                                            }
                                            onMoved: function(v) {
                                                var idx = Math.round(v)
                                                if (idx>=0 && idx<root.timeOptions.length) root.editDisplay = root.timeOptions[idx].value
                                            }
                                            onReleased: function(v) {
                                                var idx = Math.round(v)
                                                if (idx>=0 && idx<root.timeOptions.length) root.editDisplay = root.timeOptions[idx].value
                                            }
                                        }
                                        Dropdown {
                                            value: String(root.editDisplay)
                                            options: root.timeOptions.map(function(o){ return {value: String(o.value), label: o.label} })
                                            showLabel: false
                                            onChanged: function(v){ root.editDisplay = parseInt(v,10) }
                                            implicitWidth: Style.space(90)
                                        }
                                    }
                                    Label { Layout.fillWidth: true; textFormat: Text.PlainText; text: "Adds hyprctl dpms off listener"; font.pixelSize: Style.font.caption -2; color: Color.muted; opacity: 0.6; wrapMode: Text.Wrap }
                                }

                                // Lock row
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(4)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { textFormat: Text.PlainText; text: "󰌾 Auto-lock"; font.family: Style.font.family; font.pixelSize: Style.font.caption; color: Color.muted; Layout.fillWidth: true }
                                        Label { textFormat: Text.PlainText; text: root.formatLabel(root.editLock); font.family: Style.font.family; font.pixelSize: Style.font.caption; color: Color.accent; font.bold: true }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Style.space(6)
                                        PanelSlider {
                                            Layout.fillWidth: true
                                            bar: root.bar
                                            minimum: 0
                                            maximum: root.timeOptions.length - 1
                                            step: 1
                                            integer: true
                                            value: {
                                                for (var i=0;i<root.timeOptions.length;i++) if (root.timeOptions[i].value===root.editLock) return i
                                                return 7
                                            }
                                            onMoved: function(v) {
                                                var idx = Math.round(v)
                                                if (idx>=0 && idx<root.timeOptions.length) root.editLock = root.timeOptions[idx].value
                                            }
                                            onReleased: function(v) {
                                                var idx = Math.round(v)
                                                if (idx>=0 && idx<root.timeOptions.length) root.editLock = root.timeOptions[idx].value
                                            }
                                        }
                                        Dropdown {
                                            value: String(root.editLock)
                                            options: root.timeOptions.map(function(o){ return {value: String(o.value), label: o.label} })
                                            showLabel: false
                                            onChanged: function(v){ root.editLock = parseInt(v,10) }
                                            implicitWidth: Style.space(90)
                                        }
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        visible: root.editLock > 0 && root.editSaver > 0 && root.editLock < root.editSaver
                                        textFormat: Text.PlainText
                                        text: "⚠ Lock before screensaver — lock will trigger first"
                                        font.pixelSize: Style.font.caption -1; color: Color.urgent; wrapMode: Text.Wrap
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(6)
                                    Button {
                                        text: "Reset"
                                        fontSize: Style.font.caption
                                        Layout.fillWidth: true
                                        onClicked: { root.editSaver = 1800; root.editDisplay = 0; root.editLock = 2700 }
                                    }
                                    Button {
                                        text: service && service.busy ? "Applying…" : "Apply timings"
                                        fontSize: Style.font.caption
                                        Layout.fillWidth: true
                                        enabled: service && !service.busy
                                        onClicked: if (service) service.setAllTimings(root.editSaver, root.editDisplay, root.editLock)
                                    }
                                }
                            }
                        }
                    }

                    // ── Idle / Suspend section ──
                    Rectangle {
                        Layout.fillWidth: true
                        radius: Style.space(6)
                        color: Util.alpha(Color.foreground, 0.02)
                        border.color: Util.alpha(Color.foreground, 0.06)
                        border.width: 1
                        implicitHeight: idleCol.implicitHeight + Style.space(12)
                        ColumnLayout {
                            id: idleCol
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            spacing: Style.space(6)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(6)
                                Label {
                                    textFormat: Text.PlainText
                                    text: root.idleCollapsed ? "" : ""
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Style.font.caption
                                    color: Color.accent
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.idleCollapsed = !root.idleCollapsed }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: "󰾤 Idle & Suspend"
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    color: Color.foreground
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.idleCollapsed = !root.idleCollapsed }
                                }
                                Label {
                                    textFormat: Text.PlainText
                                    text: service ? (service.idleAction + " " + service.formatSec(service.idleActionSec)) : ""
                                    font.pixelSize: Style.font.caption -1
                                    color: Color.muted
                                    opacity: 0.7
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: !root.idleCollapsed
                                spacing: Style.space(6)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(6)
                                    Label { textFormat: Text.PlainText; text: "Action"; font.pixelSize: Style.font.caption; color: Color.muted; Layout.preferredWidth: Style.space(60) }
                                    Dropdown {
                                        Layout.fillWidth: true
                                        value: root.editIdleAction
                                        options: root.idleOptions
                                        showLabel: false
                                        onChanged: function(v){ root.editIdleAction = v }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(6)
                                    Label { textFormat: Text.PlainText; text: "Delay"; font.pixelSize: Style.font.caption; color: Color.muted; Layout.preferredWidth: Style.space(60) }
                                    PanelSlider {
                                        Layout.fillWidth: true
                                        bar: root.bar
                                        minimum: 0
                                        maximum: root.timeOptions.length - 1
                                        step: 1
                                        integer: true
                                        value: {
                                            for (var i=0;i<root.timeOptions.length;i++) if (root.timeOptions[i].value===root.editIdleSec) return i
                                            return 6
                                        }
                                        onMoved: function(v) {
                                            var idx = Math.round(v)
                                            if (idx>=0 && idx<root.timeOptions.length) root.editIdleSec = root.timeOptions[idx].value
                                        }
                                        onReleased: function(v) {
                                            var idx = Math.round(v)
                                            if (idx>=0 && idx<root.timeOptions.length) root.editIdleSec = root.timeOptions[idx].value
                                        }
                                    }
                                    Dropdown {
                                        value: String(root.editIdleSec)
                                        options: root.timeOptions.map(function(o){ return {value: String(o.value), label: o.label} })
                                        showLabel: false
                                        onChanged: function(v){ root.editIdleSec = parseInt(v,10) }
                                        implicitWidth: Style.space(90)
                                    }
                                }
                                Label { Layout.fillWidth: true; textFormat: Text.PlainText; text: "Writes /etc/systemd/logind.conf.d drop-in via pkexec (explicit Apply)"; font.pixelSize: Style.font.caption -2; color: Color.muted; opacity: 0.6; wrapMode: Text.Wrap }
                                // battery-aware note when desktop
                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: service && !service.isLaptop
                                    radius: Style.space(4)
                                    color: Util.alpha(Color.muted, 0.08)
                                    implicitHeight: batNote.implicitHeight + Style.space(8)
                                    Label {
                                        id: batNote
                                        anchors.fill: parent
                                        anchors.margins: Style.space(6)
                                        textFormat: Text.PlainText
                                        text: "󰂄 No battery detected — AC settings only on this device"
                                        font.pixelSize: Style.font.caption -1; color: Color.muted; wrapMode: Text.Wrap
                                    }
                                }
                                Button {
                                    Layout.fillWidth: true
                                    text: service && service.busy ? "Applying…" : "Apply idle (pkexec)"
                                    fontSize: Style.font.caption
                                    enabled: service && !service.busy
                                    onClicked: if (service) service.setIdleAction(root.editIdleAction, root.editIdleSec)
                                }
                            }
                        }
                    }

                    // ── Lid section (auto-hidden on desktop) ──
                    Rectangle {
                        Layout.fillWidth: true
                        visible: service ? service.lidPresent : false
                        radius: Style.space(6)
                        color: Util.alpha(Color.foreground, 0.02)
                        border.color: Util.alpha(Color.foreground, 0.06)
                        border.width: 1
                        implicitHeight: lidCol.implicitHeight + Style.space(12)
                        ColumnLayout {
                            id: lidCol
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            spacing: Style.space(6)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(6)
                                Label {
                                    textFormat: Text.PlainText
                                    text: root.lidCollapsed ? "" : ""
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Style.font.caption
                                    color: Color.accent
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.lidCollapsed = !root.lidCollapsed }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: "󰒋 Lid"
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    color: Color.foreground
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.lidCollapsed = !root.lidCollapsed }
                                }
                                Label {
                                    textFormat: Text.PlainText
                                    text: service ? service.handleLidSwitch : ""
                                    font.pixelSize: Style.font.caption -1
                                    color: Color.muted
                                    opacity: 0.7
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: !root.lidCollapsed
                                spacing: Style.space(6)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(6)
                                    Label { textFormat: Text.PlainText; text: "On battery"; font.pixelSize: Style.font.caption; color: Color.muted; Layout.preferredWidth: Style.space(90) }
                                    Dropdown {
                                        Layout.fillWidth: true
                                        value: root.editLid
                                        options: root.lidOptions
                                        showLabel: false
                                        onChanged: function(v){ root.editLid = v }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(6)
                                    Label { textFormat: Text.PlainText; text: "On AC"; font.pixelSize: Style.font.caption; color: Color.muted; Layout.preferredWidth: Style.space(90) }
                                    Dropdown {
                                        Layout.fillWidth: true
                                        value: root.editLidExt
                                        options: root.lidOptions
                                        showLabel: false
                                        onChanged: function(v){ root.editLidExt = v }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(6)
                                    Label { textFormat: Text.PlainText; text: "Docked"; font.pixelSize: Style.font.caption; color: Color.muted; Layout.preferredWidth: Style.space(90) }
                                    Dropdown {
                                        Layout.fillWidth: true
                                        value: root.editLidDocked
                                        options: root.lidOptions
                                        showLabel: false
                                        onChanged: function(v){ root.editLidDocked = v }
                                    }
                                }
                                Button {
                                    Layout.fillWidth: true
                                    text: service && service.busy ? "Applying…" : "Apply lid (pkexec)"
                                    fontSize: Style.font.caption
                                    enabled: service && !service.busy
                                    onClicked: if (service) service.setLidActions(root.editLid, root.editLidExt, root.editLidDocked)
                                }
                            }
                        }
                    }
                    // desktop placeholder when lid not present
                    Rectangle {
                        Layout.fillWidth: true
                        visible: service ? !service.lidPresent : false
                        radius: Style.space(6)
                        color: Util.alpha(Color.muted, 0.06)
                        border.color: Util.alpha(Color.muted, 0.12)
                        border.width: 1
                        implicitHeight: deskLid.implicitHeight + Style.space(12)
                        RowLayout {
                            id: deskLid
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            spacing: Style.space(8)
                            Label { textFormat: Text.PlainText; text: "󰒋"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: Style.font.body; color: Color.muted }
                            Label { Layout.fillWidth: true; textFormat: Text.PlainText; text: "No lid detected — lid settings hidden on desktop"; font.pixelSize: Style.font.caption; color: Color.muted; wrapMode: Text.Wrap }
                        }
                    }

                    // ── Actions (5 icon buttons) ──
                    property string confirmAction: ""
                    Rectangle {
                        Layout.fillWidth: true
                        radius: Style.space(6)
                        color: Util.alpha(Color.foreground, 0.02)
                        border.color: Util.alpha(Color.foreground, 0.06)
                        border.width: 1
                        implicitHeight: actionsCol.implicitHeight + Style.space(12)
                        ColumnLayout {
                            id: actionsCol
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            spacing: Style.space(6)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Label {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: "Actions"
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    color: Color.foreground
                                }
                                Label {
                                    textFormat: Text.PlainText
                                    text: "󰐦"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Style.font.caption
                                    color: Color.muted
                                    opacity: 0.6
                                }
                            }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 5
                                columnSpacing: Style.space(6)
                                rowSpacing: Style.space(6)
                                Button {
                                    iconText: "󰒲"
                                    fontFamily: "JetBrainsMono Nerd Font"
                                    fontSize: Style.font.body + 2
                                    tooltipText: "Screensaver"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Style.space(36)
                                    enabled: service && !service.busy
                                    onClicked: if (service) service.triggerScreensaver()
                                }
                                Button {
                                    iconText: "󰌾"
                                    fontFamily: "JetBrainsMono Nerd Font"
                                    fontSize: Style.font.body + 2
                                    tooltipText: "Lock"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Style.space(36)
                                    enabled: service && !service.busy
                                    onClicked: if (service) service.lockScreen()
                                }
                                Button {
                                    iconText: "󰍃"
                                    fontFamily: "JetBrainsMono Nerd Font"
                                    fontSize: Style.font.body + 2
                                    tooltipText: "Logout"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Style.space(36)
                                    enabled: service && !service.busy
                                    onClicked: root.confirmAction = "logout"
                                }
                                Button {
                                    iconText: "󰜉"
                                    fontFamily: "JetBrainsMono Nerd Font"
                                    fontSize: Style.font.body + 2
                                    tooltipText: "Reboot"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Style.space(36)
                                    enabled: service && !service.busy
                                    onClicked: root.confirmAction = "reboot"
                                }
                                Button {
                                    iconText: "󰐥"
                                    fontFamily: "JetBrainsMono Nerd Font"
                                    fontSize: Style.font.body + 2
                                    tooltipText: "Shutdown"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Style.space(36)
                                    enabled: service && !service.busy
                                    onClicked: root.confirmAction = "shutdown"
                                }
                            }
                            // labels under icons
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(6)
                                Repeater {
                                    model: ["Saver","Lock","Logout","Reboot","Off"]
                                    delegate: Label {
                                        required property string modelData
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: modelData
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.caption - 2
                                        color: Color.muted
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }
                            // confirm row
                            Rectangle {
                                Layout.fillWidth: true
                                visible: root.confirmAction !== ""
                                radius: Style.space(6)
                                color: Util.alpha(Color.urgent, 0.10)
                                border.color: Util.alpha(Color.urgent, 0.30)
                                border.width: 1
                                implicitHeight: confirmRow.implicitHeight + Style.space(8)
                                RowLayout {
                                    id: confirmRow
                                    anchors.fill: parent
                                    anchors.margins: Style.space(6)
                                    spacing: Style.space(6)
                                    Label {
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: root.confirmAction === "logout" ? "Logout now?" : root.confirmAction === "reboot" ? "Reboot now?" : root.confirmAction === "shutdown" ? "Shutdown now?" : ""
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.caption
                                        color: Color.urgent
                                        wrapMode: Text.Wrap
                                    }
                                    Button {
                                        text: "Cancel"
                                        fontSize: Style.font.caption
                                        onClicked: root.confirmAction = ""
                                    }
                                    Button {
                                        text: "Confirm"
                                        fontSize: Style.font.caption
                                        onClicked: {
                                            var a = root.confirmAction
                                            root.confirmAction = ""
                                            if (!service) return
                                            if (a === "logout") service.logout()
                                            else if (a === "reboot") service.reboot()
                                            else if (a === "shutdown") service.shutdown()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Footer actions ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(6)
                        Button {
                            text: "Open hypridle.conf"
                            fontSize: Style.font.caption
                            Layout.fillWidth: true
                            onClicked: openConfProc.running = true
                        }
                        Button {
                            text: "Reload"
                            fontSize: Style.font.caption
                            Layout.fillWidth: true
                            onClicked: { if (service) service.refresh(); root.syncFromService() }
                        }
                    }

                    Process {
                        id: openConfProc
                        command: ["bash", "-lc", "xdg-open ~/.config/hypr/hypridle.conf 2>/dev/null || xdg-open ~/.config/hypr 2>/dev/null || true"]
                    }
                }
            }
        }
    }

    // sync when panel opens
    onOpenedChanged: {
        if (opened) root.syncFromService()
    }
}
