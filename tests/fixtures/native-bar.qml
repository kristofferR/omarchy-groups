import QtQuick
import Quickshell
import qs.Ui

// Exercise Groups against the installed native bar without loading desktop
// services or reading/writing the user's layout. Only the test compositor maps it.
ShellRoot {
  id: root
  property var bar: null
  property int stage: 0
  property int ticks: 0
  property var retainedCell: null
  readonly property string groupId: "kristofferr.groups"
  readonly property string sourceDir: Quickshell.env("NOOK_SOURCE_DIR")
  Item { id: host }

  QtObject {
    id: registry
    property var widgets: ({})
    function metadataFor(id) { return {firstParty: id !== root.groupId} }
  }
  QtObject {
    id: plugins
    property bool scanning: false
    property var installedPlugins: ({
      "kristofferr.groups": {kinds: ["bar-widget", "overlay"]},
      "test.probe": {kinds: ["bar-widget"]}
    })
  }
  QtObject {
    id: shell
    property var pluginRegistry: plugins
    property var shellConfig: ({
      bar: {position: "top", layout: {
        left: [{id: "test.probe", label: "bar-first"}, {id: "test.probe", label: "bar-second"}],
        center: [],
        right: [
          {id: root.groupId, groupId: "source", trigger: "click", items: [
            {id: "test.probe", label: "drawer-first"}, {id: "test.probe", label: "drawer-second"}
          ]},
          {id: root.groupId, groupId: "target", trigger: "click", items: []}
        ]
      }}, plugins: [{id: "test.probe"}]
    })
    function mutateShellConfig(change) {
      var config = JSON.parse(JSON.stringify(shellConfig))
      change(config)
      shellConfig = config
      root.bar.barConfig = config.bar
    }
  }
  Component {
    id: probe
    BarWidget {
      implicitWidth: 64
      implicitHeight: 26
      WidgetButton { anchors.fill: parent; bar: parent.bar; text: parent.settings.label || "Probe" }
    }
  }

  function group(id) { return bar.moduleWidgets(groupId).find(widget => widget.groupId === id) }
  function check(condition, message) { if (!condition) throw new Error(message) }
  function groupOrder() { return shell.shellConfig.bar.layout.right.map(entry => entry.groupId).join(",") }

  function dragGroup(from, to, after, cancel, outside) {
    var pointer = from.ownSlot.children.find(child => child instanceof MouseArea && "dragging" in child)
    check(!!pointer, "native group drag pointer not found")
    bar.clearBarDrag()
    pointer.dragging = true
    bar.barDragWindow = from.barWindow
    bar.barDragSource = from.ownSlot
    var point = to.ownSlot.mapToItem(null, to.width * (after ? 0.75 : 0.25), to.height / 2)
    bar.barDragSceneX = point.x
    bar.barDragSceneY = point.y
    var drop = bar.moduleDropAtScene(point, from.ownSlot)
    check(drop && drop.slot === to.ownSlot && drop.after === after, "wrong native drop target")
    bar.barDragTarget = drop.slot
    bar.barDragAfter = drop.after
    bar.barDragTargetGeometry = bar.dropMarkerRect(drop.slot, drop.after)
    if (outside) {
      bar.barDragSceneY = from.barWindow.height + 500
      bar.barDragTarget = null
      bar.barDragTargetGeometry = null
    }
    // Exercise the native MouseArea's handlers, including clearBarDrag's signal
    // order. A group intercepts the target, so release does not consume a mouse.
    check(bar.barDragTarget === null, "group did not intercept the native reorder")
    if (cancel) pointer.canceled()
    else pointer.released(null)
  }

  function finish(error) {
    console.log(error ? "GROUPS_NATIVE_FAIL stage " + stage + ": " + error : "GROUPS_NATIVE_OK")
    ticker.stop()
    Qt.quit()
  }

  Component.onCompleted: {
    var groups = Qt.createComponent(encodeURI("file://" + sourceDir + "/BarWidget.qml"))
    var nativeBar = Qt.createComponent(encodeURI("file://" + Quickshell.env("OMARCHY_PATH") + "/shell/plugins/bar/Bar.qml"))
    if (groups.status !== Component.Ready || nativeBar.status !== Component.Ready) {
      finish(groups.errorString() + nativeBar.errorString())
      return
    }
    registry.widgets = {"kristofferr.groups": {component: groups}, "test.probe": {component: probe, metadata: {firstParty: true}}}
    bar = nativeBar.createObject(host, {shell: shell, barWidgetRegistry: registry})
    if (!bar) { finish(nativeBar.errorString()); return }
    // Assign after construction, like the host; createObject's initial map
    // converts nested arrays into QVariantLists before the bar normalizes them.
    bar.barConfig = shell.shellConfig.bar
    ticker.start()
  }

  Timer {
    id: ticker
    interval: 80
    repeat: true
    onTriggered: {
      try {
        if (++root.ticks > 70) throw new Error("timed out: " + JSON.stringify(bar.debugBarGeometry()))
        var source = root.group("source")
        var target = root.group("target")
        if (!source || !target || !source.hostBar || !target.hostBar) return
        if (root.stage === 0) {
          if (source.cells.length !== 2 || !source.cells[1].childItem) return
          source.open()
          root.retainedCell = source.cells[0]
          root.stage++
        } else if (root.stage === 1) {
          check(source.dismissActive && source.dismissInitialized, "dismissal surface was not initialized")
          source.beginChildDrag(source.cells[1], Qt.point(5, 5))
          check(source.draggingChild && source.childDragChoice.location.itemIndex === 1, "wrong repeated drag source")
          source.childDropGroup = target
          target.caretIndex = 0
          source.endChildDrag()
          root.stage++
        } else if (root.stage === 2) {
          if (target.cells.length !== 1) return
          check(source.cells[0] === root.retainedCell, "transfer rebuilt an unrelated widget")
          check(source.entries[0].label === "drawer-first" && target.entries[0].label === "drawer-second", "transfer moved wrong occurrence")
          check(!source.expanded && !source.dismissActive, "transfer left the source dismissal surface intercepting destination input")
          target.open()
          root.stage++
        } else if (root.stage === 3) {
          target.beginChildDrag(target.cells[0], Qt.point(5, 5))
          check(target.draggingChild, "eject drag did not start")
          target.childDropBar = {section: "left", index: 1}
          target.endChildDrag()
          root.stage++
        } else if (root.stage === 4) {
          check(shell.shellConfig.bar.layout.left[1].label === "drawer-second", "eject missed exact bar position")
          check(shell.shellConfig.plugins.some(entry => entry.id === "test.probe"), "eject disabled remaining hosted instance")
          var slot = bar.moduleSlots.find(slot => slot.entry && slot.entry.label === "bar-second")
          check(!!slot, "bar occurrence not found")
          bar.barDragWindow = source.barWindow
          bar.barDragSource = slot
          bar.barDragSceneX = source.chevronAlong + source.width / 2
          bar.barDragSceneY = source.height / 2
          check(source.armedChoice && source.armedChoice.location.index === 2, "bar drag selected first matching ID")
          bar.clearBarDrag()
          root.stage++
        } else if (root.stage === 5) {
          check(source.entries.length === 2 && source.entries[1].label === "bar-second", "bar absorption moved wrong occurrence")
          source.close()
          check(!source.dismissActive && source.dismissInitialized, "closing discarded dismissal objects")
          root.stage++
        } else if (root.stage === 6) {
          source.open()
          check(source.dismissActive, "reopening did not restore dismissal")
          source.close()
          shell.mutateShellConfig(function(config) {
            var items = []
            for (var i = 0; i < 45; i++) items.push({id: "test.probe", label: "overflow-" + i})
            config.bar.layout.right[0].items = items
          })
          root.stage++
        } else if (root.stage === 7) {
          if (source.cells.length !== 45) return
          source.open()
          root.stage++
        } else if (root.stage === 8) {
          check(source.overflowing, "overflow fixture fits on the test display")
          source.beginChildDrag(source.cells[0], Qt.point(5, 5))
          source.updateChildDrag(Qt.point(source.cardAlong + source.cardExtent / 2, source.barSize + source.stripThickness / 2))
          var previous = source.caretIndex
          source.scrollOffset = 128
          Qt.callLater(function() {
            try {
              check(source.caretIndex > previous, "scrolling left the stationary drag insertion point stale")
              source.cancelChildDrag()
              source.close()
              root.stage++
              ticker.start()
            } catch (error) { finish(error) }
          })
          ticker.stop()
        } else if (root.stage === 9) {
          // The destination connected first; it must not swallow this drop.
          dragGroup(target, source, false, false, false)
          root.stage++
        } else if (root.stage === 10) {
          check(groupOrder() === "target,source", "destination-first handlers lost the group drop")
          dragGroup(source, target, false, false, false)
          root.stage++
        } else if (root.stage === 11) {
          check(groupOrder() === "source,target", "source-first handlers lost the group drop")
          dragGroup(target, source, false, true, false)
          check(groupOrder() === "source,target", "canceled drag committed a group reorder")
          dragGroup(target, source, false, false, true)
          check(groupOrder() === "source,target", "drop outside the bar used a stale destination")
          dragGroup(source, target, true, false, false)
          root.stage++
        } else if (root.stage === 12) {
          check(groupOrder() === "target,source", "release after cancellation missed the after-target drop")
          finish("")
        }
      } catch (error) { finish(error) }
    }
  }
}
