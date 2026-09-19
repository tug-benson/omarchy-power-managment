pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

BarWidget {
    id: root
    moduleName: "io.github.tug-benson.power-managment"

    readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
        ? (bar.shell.serviceFor("io.github.tug-benson.power-managment") || bar.shell.serviceFor("power-managment")) : null

    readonly property bool hypridleOk: service ? service.hypridleActive : true
    readonly property string saverText: service ? service.formatSec(service.screensaverSec) : "--"
    readonly property string lockText: service ? service.formatSec(service.lockSec) : "--"

    function injectPanel() {
        var t = panelLoader.item
        if (!t) return
        if ("hostWidget" in t) t.hostWidget = root
        if ("anchorItem" in t) t.anchorItem = button
        if ("bar" in t) t.bar = root.bar
    }

    function togglePanel() {
        if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
    }

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    function open() { if (panelLoader.item && panelLoader.item.open) panelLoader.item.open() }
    function close() { if (panelLoader.item && panelLoader.item.close) panelLoader.item.close() }
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
    function closeForPopoutSwitch() { if (panelLoader.item && panelLoader.item.closeForPopoutSwitch) panelLoader.item.closeForPopoutSwitch() }

    implicitWidth: button.implicitWidth
    implicitHeight: barSize
    onBarChanged: injectPanel()

    // Nerd Font: 󰐦 power-settings, 󰂄 AC, 󰁹 battery
    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: !root.hypridleOk ? "󰅺" : (service && service.onBattery ? "󰁹" : "󰐦")
        tooltipText: !root.hypridleOk ? "Power: hypridle inactive"
                   : service ? ("󰒲 " + saverText + " · 󰌾 " + lockText + (service.lidPresent ? " · 󰒋 " + service.handleLidSwitch : "") + " — click to manage")
                   : "Power Managment — click to manage"
        active: service ? service.screensaverEnabled || service.lockEnabled : false
        opacity: root.hypridleOk ? 1.0 : 0.6
        onPressed: function(b) {
            if (b === Qt.LeftButton) root.togglePanel()
        }
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
    }
}
