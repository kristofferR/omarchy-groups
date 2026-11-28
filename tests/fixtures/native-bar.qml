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
  property var heldSlot: null
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
  function layout() { return shell.shellConfig.bar.layout }
  function labels(section) { return layout()[section].map(entry => entry.groupId || entry.label).join(",") }
  function barSlot(label) { return bar.moduleSlots.find(slot => slot.visible && slot.entry && slot.entry.label === label) }
  function onItem(item, fraction) { return item.mapToItem(null, item.width * fraction, item.height / 2) }
  function onCard(widget, along) { return Qt.point(along, widget.barThickness + widget.stripThickness / 2) }

  // What the bar's own pointer does with a held widget on a move and on a
  // release (modulePointer in Bar.qml's ModuleSlot), without a real pointer.
  function barDragTo(slot, point) {
    if (bar.barDragSource !== slot) bar.beginBarDrag(slot, 2, 2)
    var screenPoint = bar.barDragScreenPoint(point)
    bar.barDragSceneX = point.x
    bar.barDragSceneY = point.y
    bar.barDragScreenX = screenPoint.x
    bar.barDragScreenY = screenPoint.y
    var drop = bar.moduleDropAtScene(point, slot)
    bar.barDragTarget = drop
    bar.moveDragRoom(drop)
    bar.setBarDragRemoveArmed(!drop && bar.moduleRemoveDistance(screenPoint) >= bar.barDragRemoveDistance)
  }
  function barRelease(slot) {
    if (bar.barDragSource === slot && bar.barDragRemoveArmed) bar.removeBarDrag(slot)
    else if (bar.barDragSource === slot) bar.settleBarDrag(slot)
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
        if (++root.ticks > 150) throw new Error("timed out: " + JSON.stringify(bar.debugBarGeometry()))
        var source = root.group("source")
        var target = root.group("target")
        if (!source || !target || !source.hostBar || !target.hostBar) return
        if (root.stage === 0) {
          if (source.cells.length !== 2 || !source.cells[1].childItem) return
          source.open()
          root.retainedCell = source.cells[0]
          root.stage++
        } else if (root.stage === 1) {
          // Drawer to another group.
          check(source.dismissActive && source.dismissInitialized, "dismissal surface was not initialized")
          source.beginChildDrag(source.cells[1], Qt.point(5, 5))
          check(source.draggingChild && source.childDragChoice.location.itemIndex === 1, "wrong repeated drag source")
          check(bar.barDragSource === source.cells[1].nativeDragSlot
            && bar.barDragExtent === Math.ceil(source.cells[1].width) && bar.barDragGhostHeight > 0,
            "drawer drag gave the bar's ghost no size")
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
          // Drawer to the bar: the bar opens room where the drop would land.
          if (!target.revealed || !target.cells[0].childItem) return
          target.beginChildDrag(target.cells[0], Qt.point(5, 5))
          check(target.draggingChild, "eject drag did not start")
          target.updateChildDrag(onCard(target, target.cardAlong + target.cardExtent / 2))
          check(target.childDropBar === null && bar.barDragRoom.home, "the bar opened room for a drag still over its drawer")
          target.updateChildDrag(onItem(barSlot("bar-second"), 0.25))
          check(target.childDropBar && target.childDropBar.section === "left" && target.childDropBar.index === 1,
            "drag over the bar missed the insertion place: " + JSON.stringify(target.childDropBar))
          root.stage++
        } else if (root.stage === 4) {
          // The room takes a few frames to open, and the ghost a frame to copy.
          if (bar.dragSpacers.length !== 1 || String(bar.barDragImageUrl) === "") return
          check(bar.dragSpacers[0].region === "left" && bar.dragSpacers[0].place === 1, "the bar opened room in the wrong place")
          target.endChildDrag()
          check(labels("left") === "bar-first,drawer-second,bar-second", "eject missed exact bar position: " + labels("left"))
          check(shell.shellConfig.plugins.some(entry => entry.id === "test.probe"), "eject disabled remaining hosted instance")
          check(bar.barDragSource === null && bar.barDragRoom === null, "eject left the bar's drag running")
          source.open()
          root.stage++
        } else if (root.stage === 5) {
          if (!source.revealed) return
          root.stage++
        } else if (root.stage === 6) {
          // A layout written from elsewhere mid-drag moves the bar's widgets
          // about, and the place it had open is stale: the drop is called off.
          source.beginChildDrag(source.cells[0], Qt.point(5, 5))
          source.updateChildDrag(onItem(barSlot("bar-second"), 0.25))
          check(source.childDropBar !== null, "drag over the bar found no place")
          shell.mutateShellConfig(function(config) { config.bar.layout.left.unshift({id: "test.probe", label: "elsewhere"}) })
          source.endChildDrag()
          check(labels("left") === "elsewhere,bar-first,drawer-second,bar-second" && source.entries.length === 1,
            "a drop landed at a place the layout had moved on from: " + labels("left"))
          shell.mutateShellConfig(function(config) { config.bar.layout.left.shift() })
          source.close()
          root.stage++
        } else if (root.stage === 7) {
          // Bar to a group's icon. The bar would open room beside it instead.
          root.heldSlot = barSlot("bar-second")
          if (!root.heldSlot) return
          barDragTo(root.heldSlot, onItem(source, 0.75))
          check(source.armedChoice && source.armedChoice.location.index === 2, "bar drag selected the wrong occurrence")
          check(bar.barDragRoom.home && bar.barDragTarget === null, "the bar kept its own drop beside the group")
          barRelease(root.heldSlot)
          root.stage++
        } else if (root.stage === 8) {
          if (bar.barDragSource) return
          check(source.entries.length === 2 && source.entries[1].label === "bar-second", "bar absorption moved wrong occurrence")
          check(labels("left") === "bar-first,drawer-second", "the bar moved the absorbed widget as well: " + labels("left"))
          source.open()
          root.stage++
        } else if (root.stage === 9) {
          // Bar to the open drawer, at a place among its widgets.
          root.heldSlot = barSlot("drawer-second")
          if (!source.revealed || !root.heldSlot) return
          var first = source.cells[0]
          barDragTo(root.heldSlot, onCard(source, first.mapToItem(null, 0, 0).x + first.width / 4))
          check(source.dropOnCard && source.armedIndex === 0, "drag over the drawer missed the insertion place")
          // Deep bars put the drawer past the bar's removal distance.
          bar.setBarDragRemoveArmed(true)
          check(!bar.barDragRemoveArmed, "a drop on the drawer would delete the widget")
          barDragTo(root.heldSlot, Qt.point(400, 400))
          check(bar.barDragRemoveArmed && !source.armedChoice, "group disarmed removal away from its drawer")
          barDragTo(root.heldSlot, onCard(source, first.mapToItem(null, 0, 0).x + first.width / 4))
          barRelease(root.heldSlot)
          root.stage++
        } else if (root.stage === 10) {
          if (bar.barDragSource) return
          check(source.entries.map(entry => entry.label).join(",") === "drawer-second,drawer-first,bar-second",
            "drawer drop missed its place: " + JSON.stringify(source.entries))
          check(labels("left") === "bar-first", "drawer drop left the widget on the bar")
          source.close()
          check(!source.dismissActive && source.dismissInitialized, "closing discarded dismissal objects")
          root.stage++
        } else if (root.stage === 11) {
          // A group's own icon is the bar's to move. Groups must not move it too.
          root.heldSlot = target.ownSlot
          barDragTo(root.heldSlot, onItem(source, 0.25))
          check(bar.barDragTarget && !bar.barDragRoom.home, "group interfered with its own reorder")
          barRelease(root.heldSlot)
          root.stage++
        } else if (root.stage === 12) {
          if (bar.barDragSource) return
          check(labels("right") === "target,source", "native group reorder failed: " + labels("right"))
          check(source.entries.length === 3, "reorder lost the group's widgets")
          // A group that still holds widgets survives a pull off the bar.
          root.heldSlot = source.ownSlot
          barDragTo(root.heldSlot, Qt.point(400, 400))
          check(!bar.barDragRemoveArmed, "a pull off the bar would delete a group and its widgets")
          barRelease(root.heldSlot)
          root.stage++
        } else if (root.stage === 13) {
          if (bar.barDragSource) return
          check(labels("right") === "target,source" && source.entries.length === 3, "a pull off the bar changed the layout")
          // An empty one can go, as any widget can.
          barDragTo(target.ownSlot, Qt.point(400, 400))
          check(bar.barDragRemoveArmed, "an empty group could not be removed from the bar")
          bar.clearBarDrag()
          source.open()
          check(source.dismissActive, "reopening did not restore dismissal")
          source.close()
          shell.mutateShellConfig(function(config) {
            var items = []
            for (var i = 0; i < 45; i++) items.push({id: "test.probe", label: "overflow-" + i})
            config.bar.layout.right[1].items = items
          })
          root.stage++
        } else if (root.stage === 14) {
          if (source.cells.length !== 45) return
          source.open()
          root.stage++
        } else if (root.stage === 15) {
          check(source.overflowing, "overflow fixture fits on the test display")
          source.beginChildDrag(source.cells[0], Qt.point(5, 5))
          source.updateChildDrag(onCard(source, source.cardAlong + source.cardExtent / 2))
          var previous = source.caretIndex
          source.scrollOffset = 128
          Qt.callLater(function() {
            try {
              check(source.caretIndex > previous, "scrolling left the stationary drag insertion point stale")
              source.cancelChildDrag()
              source.close()
              finish("")
            } catch (error) { finish(error) }
          })
          ticker.stop()
        }
      } catch (error) { finish(error) }
    }
  }
}
