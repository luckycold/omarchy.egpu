import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui

// eGPU bar widget: visible only while an eGPU is attached (or ejected but
// still plugged in). Left click ejects (or reattaches), right click opens the
// eGPU submenu of the Omarchy menu. All work happens in bin/egpu.
BarWidget {
  id: root
  moduleName: "lucky.egpu"

  readonly property string cli: Quickshell.env("HOME") + "/.config/omarchy/plugins/lucky.egpu/bin/egpu"
  property string state: "absent"
  property string gpuName: ""
  property bool compositorUsesIt: false

  readonly property bool shown: state !== "absent"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  visible: shown
  implicitWidth: shown ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  function peers() {
    var key = bar && bar.moduleName ? bar.moduleName : root.moduleName
    return bar && typeof bar.moduleWidgets === "function"
      ? bar.moduleWidgets(key) : [root]
  }

  function isLeader() {
    var items = peers()
    return items.length === 0 || items[0] === root
  }

  function applyStatus(nextState, nextName, nextComp) {
    root.state = nextState
    root.gpuName = nextName
    root.compositorUsesIt = nextComp
  }

  function refresh() {
    var items = peers()
    if (items.length > 0 && items[0] && items[0] !== root) {
      if (typeof items[0].refresh === "function") items[0].refresh()
      return
    }
    if (!statusProc.running) statusProc.running = true
  }

  function run(args) {
    Quickshell.execDetached([root.cli].concat(args))
    refreshSoon.restart()
  }

  Component.onCompleted: {
    var items = peers()
    if (items.length > 0 && items[0] && items[0] !== root) {
      applyStatus(items[0].state, items[0].gpuName, items[0].compositorUsesIt)
    }
  }

  Process {
    id: statusProc
    command: [root.cli, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var nextState = "absent"
        var nextName = ""
        var nextComp = false
        try {
          var s = JSON.parse(String(text))
          nextState = ["attached", "ejected", "absent"].indexOf(s.state) >= 0 ? s.state : "absent"
          nextName = String(s.name || "").slice(0, 120)
          nextComp = s.compositorUsesIt === true
        } catch (e) {
          nextState = "absent"
        }
        var items = root.peers()
        for (var i = 0; i < items.length; i++) {
          if (items[i] && typeof items[i].applyStatus === "function") {
            items[i].applyStatus(nextState, nextName, nextComp)
          }
        }
      }
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (root.isLeader()) root.refresh()
  }

  Timer {
    id: refreshSoon
    interval: 2500
    repeat: false
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: "lucky.egpu"
    function refresh(): void { root.refresh() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.shown ? "\udb82\udcae" : ""
    dimmed: root.state === "ejected"
    active: root.compositorUsesIt
    tooltipText: root.state === "ejected"
      ? strings.t("tooltip.ejected")
      : (root.compositorUsesIt ? strings.t("tooltip.compositor").arg(root.gpuName)
                               : strings.t("tooltip.attached").arg(root.gpuName))
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton)
        root.run([root.state === "ejected" ? "reattach" : "eject"])
      else if (buttonCode === Qt.RightButton)
        Quickshell.execDetached(["omarchy-menu", "summon", "egpu"])
    }
  }
}
