pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Item {
    id: root

    property string omarchyPath: ""
    property var shell: null
    property var manifest: null
    property var pluginRegistry: null

    // ── Public state (read by Panel / BarWidget) ──
    property int screensaverSec: 1800
    property int displayOffSec: 0
    property int lockSec: 2700
    property bool screensaverEnabled: true
    property bool displayOffEnabled: false
    property bool lockEnabled: true

    property string idleAction: "ignore"
    property int idleActionSec: 1800
    property string handleLidSwitch: "suspend"
    property string handleLidSwitchExternalPower: "suspend"
    property string handleLidSwitchDocked: "ignore"

    property bool lidPresent: false
    property bool isLaptop: false
    property bool onBattery: false
    property int batteryPct: 0
    property string powerProfile: "balanced"

    property bool hypridleActive: false
    property string uptime: "--"
    property string lastError: ""
    property string lastInfo: ""
    property bool busy: false
    property double lastRefresh: 0

    // ── Lid suspend inhibitor (chupe logic, adapted) ──
    readonly property string lidFlagName: "lid-suspend-off"
    readonly property string togglesDir: Quickshell.env("HOME") + "/.local/state/omarchy/toggles"
    readonly property string lidFlagPath: togglesDir + "/" + lidFlagName
    readonly property string inhibitUnit: "io.github.tug-benson.power-managment-inhibit.service"

    property bool ignoreLid: false
    property bool lidStateLoaded: false
    property bool lidClosed: false
    property bool hasPendingWrite: false
    property bool pendingWrite: false
    property string pendingLidAction: ""
    property bool inhibitorHeld: false
    property bool inhibitorSyncPending: false
    property bool lidInhibitorStateLoaded: false

    readonly property int maxOutputBytes: 65536

    function scriptPath(name) {
        return Qt.resolvedUrl("bin/" + name).toString().replace(/^file:\/\//, "")
    }

    Component.onCompleted: {
        refresh()
        pollTimer.start()
        refreshLidFlag()
        refreshLidState()
    }

    Timer {
        id: pollTimer
        interval: 5000
        repeat: true
        onTriggered: root.refresh()
    }

    function refresh() {
        if (!hypridleProc.running) hypridleProc.running = true
        if (!logindProc.running) logindProc.running = true
        if (!upowerProc.running) upowerProc.running = true
        if (!uptimeProc.running) uptimeProc.running = true
        refreshLidFlag()
        refreshLidState()
    }

    // ── Lid inhibitor helpers (chupe) ──
    function refreshLidFlag() { if (!lidStateProbe.running) lidStateProbeSync.running = true }
    function setIgnoreLid(value) {
        var enabled = !!value
        root.ignoreLid = enabled
        root.lidInhibitorStateLoaded = true
        root.reconcileLidPowerProfile()
        if (lidFlagWriter.running) {
            root.pendingWrite = enabled
            root.hasPendingWrite = true
            return
        }
        runLidFlagWriter(enabled)
    }
    function toggleIgnoreLid() { setIgnoreLid(!root.ignoreLid) }
    function runLidFlagWriter(enabled) {
        lidFlagWriter.command = ["omarchy-toggle", root.lidFlagName, enabled ? "on" : "off"]
        lidFlagWriter.running = true
    }
    function syncInhibitor() {
        if (!lidInhibitorStateLoaded) return
        if (inhibitorSync.running) { inhibitorSyncPending = true; return }
        inhibitorSync.command = ["bash", root.scriptPath("inhibitor-control"), ignoreLid ? "hold" : "release"]
        inhibitorSync.running = true
    }
    function refreshLidState() { lidUpowerProbe.running = true }
    function desiredLidPowerAction() {
        if (!lidInhibitorStateLoaded || !lidStateLoaded) return ""
        return ignoreLid && lidClosed ? "close" : "open"
    }
    function reconcileLidPowerProfile() {
        var action = desiredLidPowerAction()
        if (action !== "") applyLidPowerProfile(action === "close")
    }
    function applyLidPowerProfile(closed) {
        pendingLidAction = closed ? "close" : "open"
        if (!lidPowerProfileProc.running) runPendingLidAction()
    }
    function runPendingLidAction() {
        var action = pendingLidAction
        pendingLidAction = ""
        lidPowerProfileProc.command = ["bash", root.scriptPath("lid-power-profile"), action]
        lidPowerProfileProc.running = true
    }
    function lidStatusJson() {
        return JSON.stringify({
            ignoreLid: root.ignoreLid,
            stateLoaded: root.lidInhibitorStateLoaded,
            flagPath: root.lidFlagPath,
            inhibitUnit: root.inhibitUnit,
            inhibitorHeld: root.inhibitorHeld,
            lidClosed: root.lidClosed,
            lidStateLoaded: root.lidStateLoaded,
            lidPresent: root.lidPresent,
            isLaptop: root.isLaptop
        })
    }

    function formatSec(sec) {
        if (sec <= 0) return "Never"
        if (sec < 60) return sec + "s"
        if (sec % 3600 === 0) return (sec / 3600) + "h"
        if (sec % 60 === 0) return (sec / 60) + "m"
        var m = Math.floor(sec / 60)
        var s = sec % 60
        return m + "m " + s + "s"
    }

    // ── hypridle probe ──
    Process {
        id: hypridleProc
        command: ["python3", root.scriptPath("omarchy-power-managment-hypridle"), "get"]
        stdout: StdioCollector { id: hypridleOut; waitForEnd: true }
        stderr: StdioCollector { id: hypridleErr; waitForEnd: true }
        onExited: function(code) {
            var txt = hypridleOut.text.trim()
            if (txt.length > root.maxOutputBytes) txt = txt.substring(0, root.maxOutputBytes)
            if (code !== 0) {
                // keep defaults but flag error
                if (txt) root.lastError = txt.substring(0, 300)
                root.hypridleActive = false
                return
            }
            try {
                var j = JSON.parse(txt)
                if (j.screensaverSec !== undefined) root.screensaverSec = j.screensaverSec
                if (j.displayOffSec !== undefined) root.displayOffSec = j.displayOffSec
                if (j.lockSec !== undefined) root.lockSec = j.lockSec
                root.screensaverEnabled = j.screensaverEnabled !== false
                root.displayOffEnabled = j.displayOffEnabled === true
                root.lockEnabled = j.lockEnabled !== false
                root.hypridleActive = j.hypridleActive !== false
                if (j.error) root.lastError = String(j.error).substring(0, 300)
                else root.lastError = ""
                root.lastRefresh = Date.now()
            } catch (e) {
                root.lastError = "hypridle parse failed: " + e
            }
        }
    }

    // ── logind probe ──
    Process {
        id: logindProc
        command: ["python3", root.scriptPath("omarchy-power-managment-logind"), "get"]
        stdout: StdioCollector { id: logindOut; waitForEnd: true }
        stderr: StdioCollector { id: logindErr; waitForEnd: true }
        onExited: function(code) {
            var txt = logindOut.text.trim()
            if (txt.length > root.maxOutputBytes) txt = txt.substring(0, root.maxOutputBytes)
            if (code !== 0) {
                if (txt) root.lastError = txt.substring(0, 300)
                return
            }
            try {
                var j = JSON.parse(txt)
                if (j.idleAction) root.idleAction = j.idleAction
                if (j.idleActionSec !== undefined) root.idleActionSec = j.idleActionSec
                if (j.handleLidSwitch) root.handleLidSwitch = j.handleLidSwitch
                if (j.handleLidSwitchExternalPower) root.handleLidSwitchExternalPower = j.handleLidSwitchExternalPower
                if (j.handleLidSwitchDocked) root.handleLidSwitchDocked = j.handleLidSwitchDocked
            } catch (e) {
                root.lastError = "logind parse failed: " + e
            }
        }
    }

    // ── upower / powerprofiles probe ──
    Process {
        id: upowerProc
        command: ["python3", root.scriptPath("omarchy-power-managment-upower"), "get"]
        stdout: StdioCollector { id: upowerOut; waitForEnd: true }
        stderr: StdioCollector { id: upowerErr; waitForEnd: true }
        onExited: function(code) {
            var txt = upowerOut.text.trim()
            if (txt.length > root.maxOutputBytes) txt = txt.substring(0, root.maxOutputBytes)
            if (code !== 0) {
                if (txt) root.lastError = txt.substring(0, 300)
                return
            }
            try {
                var j = JSON.parse(txt)
                root.lidPresent = j.lidPresent === true
                root.isLaptop = j.isLaptop === true
                root.onBattery = j.onBattery === true
                root.batteryPct = j.batteryPct || 0
                root.powerProfile = j.powerProfile || "balanced"
            } catch (e) {
                root.lastError = "upower parse failed: " + e
            }
        }
    }

    // ── Uptime probe (abbreviated) ──
    Process {
        id: uptimeProc
        command: ["bash", "-lc", "uptime -p 2>/dev/null | sed -e 's/^up //' -e 's/ hours,/h/' -e 's/ hour,/h/' -e 's/ minutes/m/' -e 's/ minute/m/' -e 's/ hours/h/' -e 's/ hour/h/' | cut -c1-30 || awk '{printf \"%dd %dh %dm\", $1/86400, ($1%86400)/3600, ($1%3600)/60}' /proc/uptime | cut -c1-30"]
        stdout: StdioCollector { id: uptimeOut; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            if (code === 0) {
                var t = uptimeOut.text.trim()
                if (t) root.uptime = t.substring(0, 30)
            }
        }
    }

    // ── Lid inhibitor processes (chupe) ──
    Process {
        id: lidStateProbeSync
        command: ["bash", "-c", "mkdir -p \"$1\"; [[ -f $1/$2 ]] && echo yes || echo no", "_", root.togglesDir, root.lidFlagName]
        stdout: SplitParser {
            onRead: function(line) {
                root.ignoreLid = String(line).trim() === "yes"
                root.lidInhibitorStateLoaded = true
                root.reconcileLidPowerProfile()
            }
        }
        onExited: function() {
            togglesDirWatcher.reload()
            root.syncInhibitor()
        }
    }
    Process {
        id: lidFlagWriter
        onExited: function() {
            if (root.hasPendingWrite) {
                var pending = root.pendingWrite
                root.hasPendingWrite = false
                root.runLidFlagWriter(pending)
                return
            }
            root.refreshLidFlag()
        }
    }
    Process {
        id: inhibitorSync
        stdout: SplitParser {
            onRead: function(line) { root.inhibitorHeld = String(line).trim() === "held" }
        }
        stderr: SplitParser {
            onRead: function(line) { console.warn("power-managment: inhibitor", String(line).trim()) }
        }
        onExited: function() {
            if (root.inhibitorSyncPending) {
                root.inhibitorSyncPending = false
                root.syncInhibitor()
                return
            }
            if (root.inhibitorHeld !== root.ignoreLid) console.warn("power-managment: inhibitor", root.inhibitorHeld ? "held" : "released", "while flag is", root.ignoreLid ? "on" : "off")
        }
    }
    Process {
        id: lidUpowerProbe
        command: ["busctl", "get-property", "org.freedesktop.UPower", "/org/freedesktop/UPower", "org.freedesktop.UPower", "LidIsClosed"]
        stdout: SplitParser {
            onRead: function(line) {
                var closed = String(line).trim() === "b true"
                if (!root.lidStateLoaded || root.lidClosed !== closed) {
                    root.lidClosed = closed
                    root.lidStateLoaded = true
                    root.reconcileLidPowerProfile()
                }
            }
        }
    }
    Process {
        id: lidMonitor
        command: ["dbus-monitor", "--system", "type='signal',sender='org.freedesktop.UPower',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/org/freedesktop/UPower'"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                if (String(line).indexOf('"LidIsClosed"') !== -1) root.refreshLidState()
            }
        }
        stderr: SplitParser {
            onRead: function(line) { console.warn("power-managment: lid monitor", String(line).trim()) }
        }
    }
    Process {
        id: lidPowerProfileProc
        stderr: SplitParser {
            onRead: function(line) { console.warn("power-managment: power-profile", String(line).trim()) }
        }
        onExited: function() {
            if (root.pendingLidAction !== "") root.runPendingLidAction()
        }
    }
    FileView {
        id: togglesDirWatcher
        path: root.togglesDir
        watchChanges: true
        printErrors: false
        onFileChanged: root.refreshLidFlag()
    }
    Connections {
        target: PowerProfiles
        function onProfileChanged() {
            if (root.lidInhibitorStateLoaded && root.ignoreLid && root.lidStateLoaded && root.lidClosed && PowerProfiles.profile !== PowerProfile.PowerSaver)
                root.applyLidPowerProfile(true)
        }
    }

    // ── Apply helpers ──
    Process {
        id: applyHypridleProc
        stdout: StdioCollector { id: applyHypridleOut; waitForEnd: true }
        stderr: StdioCollector { id: applyHypridleErr; waitForEnd: true }
        property bool timedOut: false
        onRunningChanged: {
            if (running) { timedOut = false; applyHypridleDeadline.restart(); root.busy = true }
            else { applyHypridleDeadline.stop(); root.busy = false }
        }
        onExited: function(code) {
            applyHypridleDeadline.stop()
            root.busy = false
            if (timedOut) { root.lastError = "hypridle apply timeout"; return }
            var out = applyHypridleOut.text.trim()
            var err = applyHypridleErr.text.trim()
            if (code === 0) {
                root.lastError = ""
                root.lastInfo = out ? out.substring(0, 300) : "hypridle updated"
                // auto-refresh
                hypridleProc.running = true
            } else {
                root.lastError = (err || out).substring(0, 500) || "hypridle apply failed"
            }
        }
    }
    Timer { id: applyHypridleDeadline; interval: 8000; onTriggered: { applyHypridleProc.timedOut = true; applyHypridleProc.running = false } }

    // Generic setter for hypridle timings
    function setScreensaver(sec) {
        var v = parseInt(sec, 10)
        if (isNaN(v) || v < 0 || v > 7200) { root.lastError = "invalid screensaver value"; return }
        applyHypridleProc.command = ["python3", root.scriptPath("omarchy-power-managment-hypridle"), "set-screensaver", String(v)]
        applyHypridleProc.running = true
    }
    function setDisplayOff(sec) {
        var v = parseInt(sec, 10)
        if (isNaN(v) || v < 0 || v > 7200) { root.lastError = "invalid displayOff value"; return }
        applyHypridleProc.command = ["python3", root.scriptPath("omarchy-power-managment-hypridle"), "set-displayoff", String(v)]
        applyHypridleProc.running = true
    }
    function setLock(sec) {
        var v = parseInt(sec, 10)
        if (isNaN(v) || v < 0 || v > 7200) { root.lastError = "invalid lock value"; return }
        applyHypridleProc.command = ["python3", root.scriptPath("omarchy-power-managment-hypridle"), "set-lock", String(v)]
        applyHypridleProc.running = true
    }
    function setAllTimings(saver, display, lock) {
        var a = parseInt(saver, 10), b = parseInt(display, 10), c = parseInt(lock, 10)
        if ([a,b,c].some(function(x){ return isNaN(x) || x < 0 || x > 7200 })) { root.lastError = "invalid timing"; return }
        applyHypridleProc.command = ["python3", root.scriptPath("omarchy-power-managment-hypridle"), "set-all", String(a), String(b), String(c)]
        applyHypridleProc.running = true
    }

    // logind apply via pkexec
    Process {
        id: applyLogindProc
        stdout: StdioCollector { id: applyLogindOut; waitForEnd: true }
        stderr: StdioCollector { id: applyLogindErr; waitForEnd: true }
        property bool timedOut: false
        onRunningChanged: {
            if (running) { timedOut = false; applyLogindDeadline.restart(); root.busy = true }
            else { applyLogindDeadline.stop(); root.busy = false }
        }
        onExited: function(code) {
            applyLogindDeadline.stop()
            root.busy = false
            if (timedOut) { root.lastError = "logind apply timeout"; return }
            var out = applyLogindOut.text.trim()
            var err = applyLogindErr.text.trim()
            if (code === 0) {
                root.lastError = ""
                root.lastInfo = out ? out.substring(0, 400) : "logind updated — restart may be needed"
                logindProc.running = true
            } else {
                root.lastError = (err || out).substring(0, 500) || "logind apply failed (pkexec cancelled?)"
            }
        }
    }
    Timer { id: applyLogindDeadline; interval: 20000; onTriggered: { applyLogindProc.timedOut = true; applyLogindProc.running = false } }

    function setIdleAction(action, sec) {
        var allowed = ["ignore", "suspend", "suspend-then-hibernate", "poweroff", "hibernate", "lock"]
        if (allowed.indexOf(action) === -1) { root.lastError = "invalid idle action"; return }
        var v = parseInt(sec, 10)
        if (isNaN(v) || v < 0 || v > 7200) { root.lastError = "invalid idle sec"; return }
        applyLogindProc.command = ["python3", root.scriptPath("omarchy-power-managment-logind"), "set-idle", action, String(v)]
        applyLogindProc.running = true
    }
    function setLidActions(lid, lidExt, lidDocked) {
        var allowed = ["ignore", "suspend", "hibernate", "poweroff", "lock"]
        if ([lid, lidExt, lidDocked].some(function(x){ return allowed.indexOf(x)===-1 })) { root.lastError = "invalid lid action"; return }
        applyLogindProc.command = ["python3", root.scriptPath("omarchy-power-managment-logind"), "set-lid", lid, lidExt, lidDocked]
        applyLogindProc.running = true
    }
    function setLidAction(which, action) {
        // convenience for single lid key: which = lid|external|docked
        var curLid = root.handleLidSwitch
        var curExt = root.handleLidSwitchExternalPower
        var curDock = root.handleLidSwitchDocked
        if (which === "lid") curLid = action
        else if (which === "external") curExt = action
        else if (which === "docked") curDock = action
        else { root.lastError = "invalid lid target"; return }
        setLidActions(curLid, curExt, curDock)
    }

    // ── Power actions (screensaver/lock/logout/reboot/shutdown) ──
    Process {
        id: powerProc
        stdout: StdioCollector { id: powerOut; waitForEnd: true }
        stderr: StdioCollector { id: powerErr; waitForEnd: true }
        property bool timedOut: false
        onRunningChanged: {
            if (running) { timedOut = false; powerDeadline.restart(); root.busy = true }
            else { powerDeadline.stop(); root.busy = false }
        }
        onExited: function(code) {
            powerDeadline.stop()
            root.busy = false
            if (timedOut) { root.lastError = "action timeout"; return }
            var out = powerOut.text.trim()
            var err = powerErr.text.trim()
            if (code === 0) {
                root.lastError = ""
                root.lastInfo = out ? out.substring(0,300) : "done"
            } else {
                root.lastError = (err || out).substring(0,400) || "action failed"
            }
        }
    }
    Timer { id: powerDeadline; interval: 10000; onTriggered: { powerProc.timedOut = true; powerProc.running = false } }

    function triggerScreensaver() {
        powerProc.command = ["bash", "-lc", "pidof hyprlock >/dev/null || omarchy-launch-screensaver"]
        powerProc.running = true
    }
    function lockScreen() {
        powerProc.command = ["omarchy-system-lock"]
        powerProc.running = true
    }
    function logout() {
        powerProc.command = ["omarchy-system-logout"]
        powerProc.running = true
    }
    function reboot() {
        powerProc.command = ["omarchy-system-reboot"]
        powerProc.running = true
    }
    function shutdown() {
        powerProc.command = ["omarchy-system-shutdown"]
        powerProc.running = true
    }

    IpcHandler {
        target: "power-managment"
        function status(): string { return root.lidStatusJson() }
        function enable(): string { root.setIgnoreLid(true); return "enabled" }
        function disable(): string { root.setIgnoreLid(false); return "disabled" }
        function toggle(): string { root.toggleIgnoreLid(); return root.ignoreLid ? "enabled" : "disabled" }
    }
}
