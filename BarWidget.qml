import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "LayoutModel.js" as Layout
import "GroupIcons.js" as GroupIcons

// Hosts other bar widgets behind a chevron, in a strip that opens off the bar.
//
// The strip spans the bar's own screen edge and is as thick as the bar plus
// itself, because Ui/KeyboardPanel positions a widget's panel from the anchor's
// offset within its own window and that window's thickness. A smaller window
// puts every hosted widget's panel against the screen edge.
//
// Widgets in here must also be listed in shell.json's `plugins[]`, or
// PluginRegistry.isEnabled never builds them. absorb() and eject() maintain it.
BarWidget {
  id: root
  moduleName: "kristofferr.groups"

  // Read `settings` directly, not through the base class's setting(): the host
  // assigns it after construction, and a binding that reaches it through a helper
  // call never re-evaluates when that lands.
  readonly property bool showBorder: !settings || settings.showBorder !== false
  readonly property bool isManager: settings && settings.role === "manager"
  readonly property string groupId: settings && settings.groupId ? String(settings.groupId) : ""
  readonly property string groupLabel: settings && settings.label ? String(settings.label) : "Group"
  readonly property string groupIcon: isManager ? "manager" : (settings && settings.icon ? String(settings.icon) : "group")

  readonly property var itemsSetting: settings ? settings.items : null
  readonly property var entries: Layout.normalizeEntries(itemsSetting, moduleName)
  readonly property string trigger: settings && settings.trigger ? String(settings.trigger) : "hover"
  readonly property int animationDuration: settings && settings.duration !== undefined
    ? Math.max(0, Number(settings.duration)) : 0

  readonly property var widgetRegistry: bar && bar.barWidgetRegistry ? bar.barWidgetRegistry.widgets : ({})
  readonly property var pluginRegistry: bar && bar.shell ? bar.shell.pluginRegistry : null

  readonly property var missingIds: {
    var registry = root.pluginRegistry
    var plugins = []
    for (var i = 0; i < root.entries.length; i++) {
      if (!root.customTypeOf(root.entries[i])) plugins.push(root.entries[i])
    }
    return Layout.missingIds(plugins, registry ? registry.installedPlugins : null,
      root.widgetRegistry, root.moduleName, registry ? registry.scanning : false)
  }

  readonly property var shellConfig: bar && bar.shell ? bar.shell.shellConfig : null

  // A transparent bar picks barForeground to contrast with the wallpaper, not
  // with this card, so the card stays on the theme and hosted widgets are
  // repainted to match it.
  readonly property color cardBackground: bar ? bar.background : Color.background
  readonly property color hostedForeground: bar ? bar.themeForeground : Color.foreground

  // The bar owns the rules for what counts as a custom module, so ask it.
  function customTypeOf(entry) {
    if (!bar || typeof bar.customModuleType !== "function") return ""
    return String(bar.customModuleType(entry) || "")
  }

  function customSourceOf(entry) {
    if (!bar || typeof bar.customModuleSource !== "function") return ""
    return String(bar.customModuleSource(entry) || "")
  }

  // A plugin that also ships a service reads plugins[] itself.
  function widgetOnly(id) {
    var installed = root.pluginRegistry ? root.pluginRegistry.installedPlugins : null
    var manifest = installed ? installed[id] : null
    var kinds = manifest ? manifest.kinds : null
    if (!kinds || kinds.length !== 1) return false
    return String(kinds[0]) === "bar-widget"
  }

  readonly property var strandedIds: {
    var config = root.shellConfig
    var plugins = null
    try { plugins = JSON.parse(JSON.stringify(config ? config.plugins : null)) } catch (e) { return [] }
    var hosted = []
    for (var i = 0; i < root.entries.length; i++) {
      if (root.widgetOnly(root.entries[i].id)) hosted.push(root.entries[i].id)
    }
    return Layout.strandedIds(plugins, hosted)
  }

  readonly property var ownSlot: {
    var slots = bar && bar.moduleSlots ? bar.moduleSlots : []
    for (var i = 0; i < slots.length; i++) {
      if (slots[i] && slots[i].activeItem === root) return slots[i]
    }
    return null
  }
  readonly property string region: ownSlot ? String(ownSlot.region || "") : ""
  readonly property bool reversed: region === "right"
  readonly property string barPosition: bar ? String(bar.position || "top") : "top"

  readonly property var barWindow: root.QsWindow.window
  readonly property real screenAlong: {
    var screen = barWindow ? barWindow.screen : null
    if (!screen) return 0
    return vertical ? screen.height : screen.width
  }


  property bool pointerInside: false
  property bool latched: false
  // A panel anchors to the widget that opened it, so hold the strip open or the
  // panel loses its anchor.
  property int openChildCount: 0

  readonly property bool pointerOnDrawer: pointerInside || cardHover.hovered
  readonly property bool hoverHeld: !isManager && trigger === "hover" && !hoverSuppressed && pointerOnDrawer
  // The pointer is over neither while crossing from chevron to strip.
  property bool hoverGrace: false

  // Without this the hover under a closing click reopens it immediately.
  property bool hoverSuppressed: false

  onPointerOnDrawerChanged: if (!pointerOnDrawer) hoverSuppressed = false

  onHoverHeldChanged: {
    if (hoverHeld) {
      hoverGrace = true
      hoverGraceTimer.stop()
    } else {
      hoverGraceTimer.restart()
    }
  }

  Timer {
    id: hoverGraceTimer
    interval: 220
    onTriggered: root.hoverGrace = false
  }

  readonly property bool expanded: latched || openChildCount > 0 || dropHovered
    || draggingChild || incomingGroup !== null || hoverHeld || hoverGrace

  property real revealProgress: expanded && entries.length > 0 ? 1 : 0
  Behavior on revealProgress {
    NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
  }
  readonly property bool revealed: revealProgress > 0.99

  implicitWidth: chevron.implicitWidth
  implicitHeight: chevron.implicitHeight

  function noteChildOpen(wasOpen, isOpen) {
    if (wasOpen === isOpen) return
    openChildCount = Math.max(0, openChildCount + (isOpen ? 1 : -1))
  }

  // Bar.findPanelWidget only routes `omarchy-shell shell summon/hide/toggle` to a
  // widget that reports all three, so without `opened` those are silent no-ops.
  readonly property bool opened: expanded

  function openSettings() {
    close()
    if (bar && bar.shell) bar.shell.summon(moduleName, "")
  }
  function open() { if (isManager) openSettings(); else latched = true }
  function close() {
    latched = false
    hoverSuppressed = pointerOnDrawer
    hoverGrace = false
    hoverGraceTimer.stop()
    for (var i = 0; i < cells.length; i++) {
      var child = cells[i] ? cells[i].childItem : null
      if (child && child.opened && typeof child.close === "function") child.close()
    }
  }

  function groupPeers() {
    return bar && typeof bar.moduleWidgets === "function"
      ? bar.moduleWidgets(moduleName).filter(function(peer) { return peer && !peer.isManager }) : [root]
  }

  function broadcastGroup(method) {
    var peers = groupPeers()
    for (var i = 0; i < peers.length; i++) {
      if (peers[i] && peers[i].groupId === groupId && typeof peers[i][method] === "function")
        peers[i][method]()
    }
  }

  function closeOtherGroups() {
    var peers = groupPeers()
    for (var i = 0; i < peers.length; i++) {
      if (peers[i] && peers[i] !== root && peers[i].groupId !== groupId && peers[i].expanded && !peers[i].draggingChild)
        peers[i].close()
    }
  }
  function toggle() { if (latched) close(); else open() }

  IpcHandler {
    target: root.moduleName + (root.groupId ? "." + root.groupId : "")

    // One bar surface per monitor, so state changes go to every instance. Config
    // writes do not: shell.json is shared and one write is the whole change.
    function open(): void { root.broadcastGroup("open") }
    function close(): void { root.broadcastGroup("close") }
    function toggle(): void { root.broadcastGroup("toggle") }
    function absorb(id: string): void { root.absorb(id, -1) }
    function eject(id: string): void { root.eject(id) }
    function reorder(from: string, to: string): void { root.reorder(Number(from), Number(to)) }

    function status(): string {
      return JSON.stringify({
        childTooltipVisible: childTooltip.visible,
        childTooltipText: childTooltip.visible && root.bar ? root.bar.tooltipText : "",
        dragging: root.draggingChild,
        groupId: root.groupId,
        label: root.groupLabel,
        trigger: root.trigger,
        hoverHeld: root.hoverHeld,
        latched: root.latched,
        expanded: root.expanded,
        pointerOnDrawer: root.pointerOnDrawer,
        hoverSuppressed: root.hoverSuppressed,
        openChildren: root.openChildCount,
        items: root.entries.length,
        overflowing: root.overflowing,
        x: root.chevronAlong,
        width: root.implicitWidth,
        cardStart: root.cardAlong,
        children: root.cells.map(function(cell) {
          return cell ? { id: cell.childId, loaded: !!cell.childItem,
            width: cell.width, opened: cell.childOpen } : null
        })
      })
    }
  }


  readonly property real stripThickness: barSize + cardPadding * 2
  readonly property real cardPadding: Style.space(4)
  readonly property real cardMargin: Style.gapsOut

  readonly property real contentExtent: vertical ? itemsFlow.implicitHeight : itemsFlow.implicitWidth
  readonly property real cardExtent: Math.max(chevronExtent,
    Math.min(contentExtent + cardPadding * 2, Math.max(0, screenAlong - cardMargin * 2)))
  readonly property real chevronExtent: vertical ? chevron.implicitHeight : chevron.implicitWidth
  readonly property real stripExtent: cardExtent - cardPadding * 2

  readonly property real maxScroll: Math.max(0, contentExtent - stripExtent)
  readonly property bool overflowing: maxScroll > 0.5
  property real scrollOffset: 0

  onMaxScrollChanged: scrollOffset = Math.max(0, Math.min(scrollOffset, maxScroll))
  onExpandedChanged: {
    if (!expanded) scrollOffset = 0
    else closeOtherGroups()
  }

  function scrollBy(amount) {
    if (!overflowing) return
    scrollOffset = Math.max(0, Math.min(scrollOffset + amount, maxScroll))
  }

  TransformWatcher {
    id: chevronWatcher
    a: root.barWindow ? root.barWindow.contentItem : null
    b: chevron
  }

  // The bar window spans its edge from the corner, so a position in its content
  // space is already a screen position along that axis, which is the space the
  // strip uses too. That is why one number addresses both windows.
  readonly property real chevronAlong: {
    chevronWatcher.transform          // reactive dependency
    if (!chevron || !barWindow) return 0
    var point = chevron.mapToItem(barWindow.contentItem, 0, 0)
    return vertical ? point.y : point.x
  }

  readonly property real cardAlong: {
    var wanted = reversed ? chevronAlong + chevronExtent - cardExtent : chevronAlong
    var limit = Math.max(cardMargin, screenAlong - cardExtent - cardMargin)
    return Math.round(Math.max(cardMargin, Math.min(wanted, limit)))
  }


  property var cells: []

  onEntriesChanged: cells = []

  function setCell(index, cell) {
    var next = cells.slice()
    while (next.length <= index) next.push(null)
    next[index] = cell
    cells = next
  }

  function clearCell(cell) {
    var next = cells.slice()
    for (var i = 0; i < next.length; i++) {
      if (next[i] === cell) next[i] = null
    }
    cells = next
  }

  // `along` is a screen position on the bar axis, valid in either window.
  function insertionIndexAt(along) {
    for (var i = 0; i < cells.length; i++) {
      var cell = cells[i]
      if (!cell || cell.width <= 0 || cell.height <= 0) continue
      var point = cell.mapToItem(null, 0, 0)
      var start = vertical ? point.y : point.x
      var middle = start + (vertical ? cell.height : cell.width) / 2
      if (along < middle) return i
    }
    return entries.length
  }

  // Bar.qml commits its own reorder and knows nothing about drawers, so a drop
  // here would only park the entry beside the chevron.

  readonly property bool dragActive: !isManager && bar && bar.barDragSource !== null
    && bar.barDragSource !== ownSlot && !draggingChild
  // Without this both monitors' drawers would light up.
  readonly property bool dragInThisWindow: dragActive && bar.barDragWindow
    && barWindow === bar.barDragWindow
  readonly property point dragPoint: dragInThisWindow
    ? root.mapFromItem(null, bar.barDragSceneX, bar.barDragSceneY) : Qt.point(-1, -1)
  readonly property bool dropOnChevron: dragInThisWindow
    && dragPoint.x >= 0 && dragPoint.x <= width
    && dragPoint.y >= 0 && dragPoint.y <= height
  readonly property bool dropOnCard: dragInThisWindow && revealProgress > 0.01
    && withinCard(bar.barDragSceneX, bar.barDragSceneY)
  readonly property bool dropHovered: dropOnChevron || dropOnCard

  // Across the bar axis, anything past the bar's thickness is over the strip.
  function withinCard(sceneX, sceneY) {
    if (!barWindow) return false
    var along = vertical ? sceneY : sceneX
    var across = vertical ? sceneX : sceneY
    var barThickness = vertical ? barWindow.width : barWindow.height
    var pastBar = barPosition === "top" || barPosition === "left"
      ? across >= barThickness && across <= barThickness + stripThickness
      : across <= 0 && across >= -stripThickness
    return pastBar && along >= cardAlong && along <= cardAlong + cardExtent
  }

  property string armedId: ""
  property int armedIndex: -1

  onDropHoveredChanged: {
    if (!bar) return
    if (dropHovered) {
      armedId = dragSourceId()
    } else if (bar.barDragSource) {
      armedId = ""                                // pointer left again, still dragging
      armedIndex = -1
      caretIndex = -1
    }
  }

  // Over the card the pointer has left the bar window, so `barDragTarget` never
  // changes and the handler watching it never fires.
  onDragPointChanged: {
    if (!dropOnCard || !bar) return
    armedIndex = insertionIndexAt(vertical ? bar.barDragSceneY : bar.barDragSceneX)
    caretIndex = armedIndex
  }

  function dragSourceId() {
    var source = bar ? bar.barDragSource : null
    var id = source ? String(source.moduleName || "") : ""
    // Never swallow this drawer, or a second drawer that shares its id.
    if (!id || id === moduleName) return ""
    return id
  }

  Connections {
    target: root.bar

    // Null the bar's target so its release is a no-op. ModuleSlot.onReleased reads
    // it into a local before clearBarDrag(), and the bar's write is synchronous:
    // it reassigns layoutConfig, rebuilding every widget on every monitor, this one
    // included. Watches the target rather than the pointer because Bar.qml sets
    // barDragSceneX first and the target a few lines later.
    function onBarDragTargetChanged() {
      if (!root.dropHovered || !root.bar || root.bar.barDragTarget === null) return
      root.armedIndex = root.dropOnCard
        ? root.insertionIndexAt(root.vertical ? root.bar.barDragSceneY : root.bar.barDragSceneX)
        : -1
      root.caretIndex = root.armedIndex
      root.bar.barDragTarget = null            // re-enters, and returns at the null check
    }

    // Release and cancel look identical here, so an abandoned drag lands.
    function onBarDragSourceChanged() {
      if (!root.bar || root.bar.barDragSource) return
      var id = root.armedId
      var index = root.armedIndex
      root.armedId = ""
      root.armedIndex = -1
      root.caretIndex = -1
      if (id) root.absorb(id, index)
    }
  }


  property int draggingIndex: -1
  property int caretIndex: -1
  property bool draggingOutside: false
  property point childDragPoint: Qt.point(-1, -1)
  property var childDropGroup: null
  property var childDropBar: null

  readonly property bool anyGroupDragging: groupPeers().some(function(peer) { return peer && peer.draggingChild })
  readonly property var incomingGroup: {
    var peers = groupPeers()
    for (var i = 0; i < peers.length; i++) {
      var peer = peers[i]
      if (peer && peer !== root && peer.draggingChild && peer.childDropGroup === root) return peer
    }
    return null
  }
  onIncomingGroupChanged: if (!incomingGroup && !draggingChild) caretIndex = -1

  function groupAtPoint(point) {
    var peers = groupPeers()
    for (var i = 0; i < peers.length; i++) {
      var peer = peers[i]
      if (!peer || peer === root || peer.barWindow !== barWindow) continue
      var along = vertical ? point.y : point.x
      var across = vertical ? point.x : point.y
      var onButton = along >= peer.chevronAlong && along <= peer.chevronAlong + peer.chevronExtent
        && across >= 0 && across <= barSize
      if (onButton || (peer.expanded && peer.withinCard(point.x, point.y))) return peer
    }
    return null
  }

  // The bar normalizes the tray position and splits the center into separate
  // rows. Resolve a visible slot back to the saved entry by ID occurrence.
  function slotLayoutIndex(slot) {
    if (!slot || !bar || !shellConfig || !shellConfig.bar) return -1
    var candidates = bar.moduleSlots.filter(function(peer) {
      return peer && peer.region === slot.region && peer.moduleName === slot.moduleName
        && bar.slotWindow(peer) === barWindow
    })
    candidates.sort(function(a, b) {
      var pa = a.mapToItem(null, 0, 0)
      var pb = b.mapToItem(null, 0, 0)
      return vertical ? pa.y - pb.y : pa.x - pb.x
    })
    var occurrence = candidates.indexOf(slot)
    if (occurrence < 0) return -1
    var entries = shellConfig.bar.layout[slot.region] || []
    for (var i = 0; i < entries.length; i++) {
      if (Layout.entryIdOf(entries[i]) !== slot.moduleName) continue
      if (occurrence-- === 0) return i
    }
    return -1
  }

  function barDestinationAt(point) {
    if (!bar || !barWindow) return null
    var along = vertical ? point.y : point.x
    var across = vertical ? point.x : point.y
    if (across < 0 || across > barSize) return null
    var slots = bar.moduleSlots.filter(function(slot) {
      return slot && slot.visible && slot.width > 0 && slot.height > 0
        && bar.slotWindow(slot) === barWindow
    })
    var best = null
    var distance = Infinity
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      var position = slot.mapToItem(barWindow.contentItem, 0, 0)
      var start = vertical ? position.y : position.x
      var size = vertical ? slot.height : slot.width
      var before = Math.abs(along - start)
      var after = Math.abs(along - start - size)
      // Shared edges belong to the following widget. The tray is moved by the
      // host, so "after tray" in the raw config can be far from this edge.
      if (before <= distance + 0.5) {
        best = {slot: slot, after: false}
        distance = before
      }
      if (after < distance - 0.5) {
        best = {slot: slot, after: true}
        distance = after
      }
    }
    if (!best) return null
    var index = slotLayoutIndex(best.slot)
    return index < 0 ? null : {section: best.slot.region, index: index + (best.after ? 1 : 0)}
  }

  readonly property bool draggingChild: draggingIndex >= 0

  function beginChildDrag(cell) {
    if (!cell) return
    draggingIndex = cell.index
    caretIndex = -1
    draggingOutside = false
  }

  // The card's edge is flush against the bar, so testing the card's rectangle
  // turned a reorder that drifted a pixel up into an eject. Ejecting means
  // putting the widget back on the bar, so only a deliberate move onto the bar
  // counts. Overshooting the ends is still a reorder: insertionIndexAt clamps.
  readonly property real ejectMargin: Style.space(10)

  function draggedOntoBar(scenePoint) {
    var across = vertical ? scenePoint.x : scenePoint.y
    var start = vertical ? cardArea.x : cardArea.y
    var end = start + (vertical ? cardArea.width : cardArea.height)
    return barPosition === "top" || barPosition === "left"
      ? across < start - ejectMargin
      : across > end + ejectMargin
  }

  function updateChildDrag(scenePoint) {
    var global = strip.contentItem.mapToGlobal(scenePoint.x, scenePoint.y)
    childDragPoint = barWindow.contentItem.mapFromGlobal(global.x, global.y)
    var previous = childDropGroup
    childDropGroup = groupAtPoint(childDragPoint)
    if (previous && previous !== childDropGroup) previous.caretIndex = -1
    draggingOutside = draggedOntoBar(scenePoint)
    childDropBar = !childDropGroup && draggingOutside ? barDestinationAt(childDragPoint) : null
    if (childDropGroup) {
      childDropGroup.caretIndex = childDropGroup.withinCard(childDragPoint.x, childDragPoint.y)
        ? childDropGroup.insertionIndexAt(vertical ? childDragPoint.y : childDragPoint.x) : -1
    }
    var across = vertical ? scenePoint.x : scenePoint.y
    var start = vertical ? cardArea.x : cardArea.y
    caretIndex = !childDropGroup && !draggingOutside && across >= start - ejectMargin
      && across <= start + stripThickness
      ? insertionIndexAt(vertical ? scenePoint.y : scenePoint.x) : -1
  }

  function endChildDrag() {
    var from = draggingIndex
    var caret = caretIndex
    var target = childDropGroup
    var destination = childDropBar
    var targetIndex = target ? target.caretIndex : -1
    var entry = from >= 0 && from < entries.length ? entries[from] : null
    var targetId = target ? target.groupId : ""

    cancelChildDrag()
    if (!entry) return
    if (target) {
      mutate(function(config) {
        Layout.transfer(config, root.moduleName, entry.id, root.groupId, targetId, targetIndex)
      })
    } else if (destination) {
      mutate(function(config) {
        Layout.eject(config, root.moduleName, entry.id, root.widgetOnly(entry.id), root.groupId, destination)
      })
    } else if (caret >= 0) reorder(from, caret)
  }

  function cancelChildDrag() {
    if (childDropGroup) childDropGroup.caretIndex = -1
    childDropGroup = null
    childDropBar = null
    draggingIndex = -1
    caretIndex = -1
    draggingOutside = false
  }


  function mutate(change) {
    var host = bar && bar.shell ? bar.shell : null
    if (!host || typeof host.mutateShellConfig !== "function") return
    host.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar) || !Util.isPlainObject(config.bar.layout)) return
      change(config)
    })
  }


  // -1 appends.
  function absorb(id, index) {
    var plugin = !root.customTypeOf(root.entryOnBar(id))
    mutate(function(config) { Layout.absorb(config, root.moduleName, id, index, plugin, root.groupId) })
  }

  function entryOnBar(id) {
    var layout = bar && bar.layoutConfig ? bar.layoutConfig : null
    if (!layout) return null
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var list = layout[sections[s]]
      if (!list) continue
      for (var i = 0; i < list.length; i++) {
        if (Layout.entryIdOf(list[i]) === id) return list[i]
      }
    }
    return null
  }

  function eject(id) {
    mutate(function(config) { Layout.eject(config, root.moduleName, id, root.widgetOnly(id), root.groupId) })
  }

  function reorder(from, to) {
    mutate(function(config) { Layout.reorder(config, root.moduleName, from, to, root.groupId) })
  }

  // Both jobs in one write: config refreshes only after a write.
  function reconcile(gone, stranded) {
    mutate(function(config) { Layout.reconcile(config, root.moduleName, gone, stranded, root.groupId) })
  }

  readonly property bool configWriter: {
    var peers = groupPeers().filter(function(peer) { return peer && peer.groupId === root.groupId })
    return peers.length === 0 || peers[0] === root
  }

  // A reload rebuilds the registries in steps. Wait before pruning.
  readonly property int settleDelay: 1500
  property real missingSince: 0

  onMissingIdsChanged: {
    missingSince = missingIds.length === 0 ? 0 : (missingSince || Date.now())
    reconcileTimer.restart()
  }
  onStrandedIdsChanged: if (strandedIds.length > 0) reconcileTimer.restart()
  Component.onCompleted: if (missingIds.length > 0 || strandedIds.length > 0) reconcileTimer.restart()

  Timer {
    id: reconcileTimer
    interval: 250
    onTriggered: {
      if (!root.configWriter) return
      var waiting = root.missingSince > 0
      var ripe = waiting && Date.now() - root.missingSince >= root.settleDelay
      var gone = ripe ? root.missingIds : []
      if (gone.length > 0 || root.strandedIds.length > 0)
        root.reconcile(gone, root.strandedIds)
      if (waiting && !ripe) restart()
    }
  }


  HoverHandler {
    id: drawerHover
    onHoveredChanged: root.pointerInside = hovered
  }

  // Bar.moduleClickTargetAt maps clicks into every registered target's geometry,
  // across windows, and takes the last registered. Re-registering the chevron
  // after the strip's widgets keeps it first in that scan.
  function claimChevronClicks() {
    if (!bar || typeof bar.unregisterClickTarget !== "function") return
    bar.unregisterClickTarget(chevron)
    bar.registerClickTarget(chevron)
  }

  onCellsChanged: Qt.callLater(claimChevronClicks)
  onRevealedChanged: if (revealed) Qt.callLater(claimChevronClicks)

  readonly property bool canShowGroupTitle: pointerInside && expanded
    && openChildCount === 0 && !draggingChild
  property bool groupTitleReady: false
  onCanShowGroupTitleChanged: {
    groupTitleReady = false
    if (canShowGroupTitle) groupTitleTimer.restart()
    else groupTitleTimer.stop()
  }

  Timer {
    id: groupTitleTimer
    interval: 400
    onTriggered: root.groupTitleReady = true
  }

  // Anchor the hover title to the drawer, keeping its icons unobstructed.
  PopupWindow {
    id: groupTitle
    visible: root.canShowGroupTitle && root.groupTitleReady && strip.visible
    color: "transparent"
    implicitWidth: Math.ceil(groupTitleBubble.implicitWidth)
    implicitHeight: Math.ceil(groupTitleBubble.implicitHeight)
    mask: Region {}

    anchor {
      window: strip
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1
      rect.x: Math.round(cardArea.x + (root.vertical
        ? (root.barPosition === "right" ? -groupTitle.width - 6 : cardArea.width + 6)
        : (cardArea.width - groupTitle.width) / 2))
      rect.y: Math.round(cardArea.y + (root.vertical
        ? (cardArea.height - groupTitle.height) / 2
        : (root.barPosition === "bottom" ? -groupTitle.height - 6 : cardArea.height + 6)))
    }

    BorderSurface {
      id: groupTitleBubble
      implicitWidth: groupTitleLabel.implicitWidth + 20
      implicitHeight: groupTitleLabel.implicitHeight + 14
      color: Color.tooltip.background
      borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
      radius: Style.cornerRadius

      Text {
        id: groupTitleLabel
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.groupLabel + " · " + root.entries.length + " plugins"
        color: Color.tooltip.text
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }

  WidgetButton {
    id: chevron
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    Image {
      anchors.centerIn: parent
      width: Style.space(14)
      height: Style.space(14)
      sourceSize.width: width * (root.barWindow && root.barWindow.screen ? root.barWindow.screen.devicePixelRatio : 1)
      sourceSize.height: sourceSize.width
      source: GroupIcons.source(root.groupIcon, String(chevron.active ? chevron.activeColor : chevron.foreground))
    }
    fixedWidth: Style.space(28)
    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.space(4)
      radius: Style.space(3)
      color: Qt.alpha(root.hostedForeground, root.expanded ? 0.12 : 0.04)
      border.width: root.showBorder ? 1 : 0
      border.color: Qt.alpha(root.hostedForeground, root.expanded ? 0.7 : 0.35)
      z: -1
    }
    active: root.dropHovered || root.expanded
    activeColor: Color.accent          // `active` defaults to bar.urgent, kept for urgency
    tooltipText: root.isManager ? "Groups settings" : root.trigger === "hover" || root.expanded
      ? "" : root.groupLabel + " · " + root.entries.length + " plugins"
    // Tests `latched`, not `expanded`: hovering already makes it expanded, so
    // branching on that meant a click could only ever close it.
    onPressed: function(button) {
      if (root.isManager || button === Qt.RightButton) { root.openSettings(); return }
      if (root.latched) {
        root.latched = false
        root.hoverSuppressed = true
        root.hoverGrace = false
        hoverGraceTimer.stop()
      } else {
        root.latched = true
      }
    }
  }


  PopupWindow {
    id: childTooltip
    readonly property var target: root.bar ? root.bar.tooltipTarget : null
    visible: root.revealed && !root.anyGroupDragging && root.bar && root.bar.tooltipShown === true
      && target && root.bar.targetBelongsToWindow(target, strip)
    color: "transparent"
    implicitWidth: Math.ceil(childTooltipBubble.implicitWidth)
    implicitHeight: Math.ceil(childTooltipBubble.implicitHeight)
    mask: Region {}
    anchor {
      id: childTooltipAnchor
      window: strip
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1
      onAnchoring: {
        if (!childTooltip.target) return
        var x = childTooltip.target.width / 2 - childTooltip.width / 2
        var y = childTooltip.target.height + 6
        if (root.barPosition === "bottom") y = -childTooltip.height - 6
        else if (root.barPosition === "left") { x = childTooltip.target.width + 6; y = (childTooltip.target.height - childTooltip.height) / 2 }
        else if (root.barPosition === "right") { x = -childTooltip.width - 6; y = (childTooltip.target.height - childTooltip.height) / 2 }
        var point = strip.contentItem.mapFromItem(childTooltip.target, x, y)
        childTooltipAnchor.rect.x = Math.round(point.x)
        childTooltipAnchor.rect.y = Math.round(point.y)
      }
    }
    BorderSurface {
      id: childTooltipBubble
      implicitWidth: childTooltipLabel.implicitWidth + 20
      implicitHeight: childTooltipLabel.implicitHeight + 14
      color: Color.tooltip.background
      borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
      radius: Style.cornerRadius
      Text {
        id: childTooltipLabel
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.bar ? root.bar.tooltipText : ""
        color: Color.tooltip.text
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }

  // A separate surface preserves the strip's thickness, which child panels use
  // for anchoring. The bar and card remain input holes so hover and native
  // widget clicks keep working. Child panels own dismissal while they are open.
  Variants {
    model: root.expanded && root.openChildCount === 0 && !root.anyGroupDragging
      && !(root.bar && root.bar.barDragSource) ? Quickshell.screens : []
    delegate: Component {
      PanelWindow {
        required property var modelData
        readonly property bool ownScreen: root.barWindow && root.barWindow.screen
          && modelData.name === root.barWindow.screen.name
        screen: modelData
        visible: root.expanded
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-group-dismiss-" + root.groupId
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        mask: Region {
          width: modelData.width
          height: modelData.height
          Region {
            intersection: Intersection.Subtract
            x: root.barPosition === "right" ? modelData.width - root.barSize : 0
            y: root.barPosition === "bottom" ? modelData.height - root.barSize : 0
            width: root.vertical ? root.barSize : modelData.width
            height: root.vertical ? modelData.height : root.barSize
          }
          Region {
            intersection: Intersection.Subtract
            x: ownScreen ? (root.vertical ? (root.barPosition === "right"
              ? modelData.width - root.barSize - root.stripThickness : root.barSize) : root.cardAlong) : 0
            y: ownScreen ? (root.vertical ? root.cardAlong : (root.barPosition === "bottom"
              ? modelData.height - root.barSize - root.stripThickness : root.barSize)) : 0
            width: ownScreen ? cardArea.width : 0
            height: ownScreen ? cardArea.height : 0
          }
        }
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onPressed: root.close()
        }
      }
    }
  }

  // Observe a bar press, then reject it so the native widget still receives it.
  MouseArea {
    parent: root.barWindow ? root.barWindow.contentItem : null
    anchors.fill: parent
    z: 10000
    enabled: root.expanded
    acceptedButtons: Qt.AllButtons
    onPressed: function(mouse) {
      var along = root.vertical ? mouse.y : mouse.x
      if (along < root.chevronAlong || along > root.chevronAlong + root.chevronExtent)
        root.close()
      mouse.accepted = false
    }
  }

  PanelWindow {
    id: strip

    screen: root.barWindow ? root.barWindow.screen : null
    visible: root.revealProgress > 0.001 && root.entries.length > 0
    color: "transparent"
    surfaceFormat.opaque: false
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-group-" + root.groupId
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: root.barPosition === "top" || root.vertical
      bottom: root.barPosition === "bottom" || root.vertical
      left: root.barPosition === "left" || !root.vertical
      right: root.barPosition === "right" || !root.vertical
    }

    implicitWidth: root.vertical ? root.barSize + root.stripThickness : 0
    implicitHeight: root.vertical ? 0 : root.barSize + root.stripThickness

    // Only the card takes input, or the stretch over the bar would swallow its
    // clicks. Spelled out rather than `Region { item: cardArea }`: the item form
    // snapshots geometry, and the card moves after the window exists.
    // Except while dragging: motion stops at the input region's edge, hiding the
    // move onto the bar that means eject.
    mask: Region {
      x: root.draggingChild ? 0 : Math.round(cardArea.x)
      y: root.draggingChild ? 0 : Math.round(cardArea.y)
      width: root.draggingChild ? strip.width : Math.ceil(cardArea.width)
      height: root.draggingChild ? strip.height : Math.ceil(cardArea.height)
    }

    Item {
      id: cardArea

      readonly property real acrossOffset: root.barPosition === "top" || root.barPosition === "left"
        ? root.barSize : 0

      x: root.vertical ? acrossOffset : root.cardAlong
      y: root.vertical ? root.cardAlong : acrossOffset
      width: root.vertical ? root.stripThickness : root.cardExtent
      height: root.vertical ? root.cardExtent : root.stripThickness

      readonly property real hiddenShift: root.barPosition === "top" || root.barPosition === "left"
        ? -root.stripThickness : root.stripThickness
      transform: Translate {
        x: root.vertical ? cardArea.hiddenShift * (1 - root.revealProgress) : 0
        y: root.vertical ? 0 : cardArea.hiddenShift * (1 - root.revealProgress)
      }
      opacity: root.revealProgress

      HoverHandler { id: cardHover }

      // WidgetButton forwards onWheel to the widget under the pointer and several use
      // it, so the edge-scroll below carries the cases the wheel cannot.
      WheelHandler {
        enabled: root.overflowing
        target: null
        onWheel: function(event) {
          root.scrollBy(-event.angleDelta.y / 3)
          event.accepted = true
        }
      }

      // -1 scrolls back toward the first widget, +1 on toward the last.
      readonly property int edgeDirection: {
        if (!root.overflowing || !cardHover.hovered) return 0
        var position = root.vertical ? cardHover.point.position.y : cardHover.point.position.x
        var extent = root.vertical ? height : width
        if (extent <= 0) return 0
        var margin = Math.max(Style.space(12), extent * 0.18)
        if (position < margin) return -1
        if (position > extent - margin) return 1
        return 0
      }

      Timer {
        running: cardArea.edgeDirection !== 0
        repeat: true
        interval: 16
        onTriggered: root.scrollBy(cardArea.edgeDirection * Style.space(3))
      }

      BorderSurface {
        anchors.fill: parent
        color: root.cardBackground
        borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border,
          Color.popups.border, Math.max(1, Style.space(2)))
        radius: Style.cornerRadius
      }

      Item {
        id: cardClip
        anchors.fill: parent
        anchors.margins: root.cardPadding
        clip: true

        Row {
          id: itemsRow
          visible: !root.vertical
          spacing: 0
          x: Math.max(0, (parent.width - implicitWidth) / 2) - root.scrollOffset
          anchors.verticalCenter: parent.verticalCenter

          Repeater {
            model: root.vertical ? [] : root.entries
            DrawerItem {
              anchors.verticalCenter: parent.verticalCenter
              required property var modelData
              required property int index
              entry: modelData
              position: index
            }
          }
        }

        Column {
          id: itemsColumn
          visible: root.vertical
          spacing: 0
          y: Math.max(0, (parent.height - implicitHeight) / 2) - root.scrollOffset
          anchors.horizontalCenter: parent.horizontalCenter

          Repeater {
            model: root.vertical ? root.entries : []
            DrawerItem {
              anchors.horizontalCenter: parent.horizontalCenter
              required property var modelData
              required property int index
              entry: modelData
              position: index
            }
          }
        }

        Rectangle {
          readonly property var target: root.caretIndex >= 0 && root.caretIndex < root.cells.length
            ? root.cells[root.caretIndex] : null
          readonly property var trailing: root.cells.length > 0 ? root.cells[root.cells.length - 1] : null
          readonly property var anchorCell: target ? target : trailing
          readonly property bool atEnd: target === null

          visible: opacity > 0
          opacity: root.caretIndex >= 0 && anchorCell ? 0.9 : 0
          color: Color.accent
          radius: Math.min(width, height) / 2
          width: root.vertical ? (anchorCell ? anchorCell.width : 0) : Style.spacing.xs
          height: root.vertical ? Style.spacing.xs : (anchorCell ? anchorCell.height : 0)
          x: {
            if (!anchorCell) return 0
            var point = anchorCell.mapToItem(parent, 0, 0)
            if (root.vertical) return point.x
            return Math.round(point.x + (atEnd ? anchorCell.width : 0) - width / 2)
          }
          y: {
            if (!anchorCell) return 0
            var point = anchorCell.mapToItem(parent, 0, 0)
            if (!root.vertical) return point.y
            return Math.round(point.y + (atEnd ? anchorCell.height : 0) - height / 2)
          }

          Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
          Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
          Behavior on opacity { NumberAnimation { duration: 90 } }
        }

        Repeater {
          model: 2

          Rectangle {
            required property int index
            readonly property bool leading: index === 0
            readonly property bool moreThisWay: leading
              ? root.scrollOffset > 0.5
              : root.scrollOffset < root.maxScroll - 0.5
            readonly property real thickness: Style.space(14)
            readonly property color cardBackground: root.cardBackground

            visible: opacity > 0
            opacity: root.overflowing && moreThisWay ? 1 : 0
            z: 40

            width: root.vertical ? parent.width : thickness
            height: root.vertical ? thickness : parent.height
            x: root.vertical ? 0 : (leading ? 0 : parent.width - thickness)
            y: root.vertical ? (leading ? 0 : parent.height - thickness) : 0

            gradient: Gradient {
              orientation: root.vertical ? Gradient.Vertical : Gradient.Horizontal
              GradientStop { position: 0; color: leading ? cardBackground : "transparent" }
              GradientStop { position: 1; color: leading ? "transparent" : cardBackground }
            }

            Behavior on opacity { NumberAnimation { duration: 120 } }
          }
        }
      }
    }
  }

  readonly property var itemsFlow: vertical ? itemsColumn : itemsRow

  component DrawerItem: Item {
    id: cell

    // Captured: during teardown `root` is gone before these destruction handlers run.
    readonly property var owner: root
    readonly property var host: root.bar

    required property var entry
    required property int position
    readonly property int index: position

    // The Repeater hands entries over as QVariant maps, whose keys a plain for-in
    // does not enumerate. A JSON round-trip makes them ordinary objects again.
    readonly property var plainEntry: entry ? JSON.parse(JSON.stringify(entry)) : ({})
    readonly property string childId: String(plainEntry.id || "")
    readonly property var childSettings: {
      var copy = ({})
      for (var key in plainEntry) {
        if (key !== "id") copy[key] = plainEntry[key]
      }
      return copy
    }
    // "command" for an `exec` entry, "qml" for a `source` one, "" for a plugin.
    readonly property string customType: root.customTypeOf(cell.entry)
    readonly property bool custom: customType !== ""

    // Reading `widgetRegistry` is what makes this re-evaluate when a plugin is
    // enabled, disabled, or reloaded from disk.
    readonly property var childComponent: {
      if (cell.customType === "command") return commandModule
      if (cell.customType === "qml") return null
      var widgets = root.widgetRegistry
      var registered = widgets && widgets[cell.childId] ? widgets[cell.childId] : null
      return registered ? registered.component : null
    }
    readonly property var childItem: cell.customType === "qml" ? qmlLoader.item : childLoader.item
    readonly property bool dragSource: root.draggingIndex === cell.index

    // Uninstalled: take up no room while the removal is written out.
    readonly property bool uninstalled: !cell.custom && root.missingIds.indexOf(cell.childId) !== -1

    implicitWidth: uninstalled ? 0
      : (childItem ? (root.vertical ? root.barSize : childItem.implicitWidth) : Style.bar.iconSlot)
    implicitHeight: uninstalled ? 0
      : (childItem ? childItem.implicitHeight : Style.bar.iconSlot)
    width: implicitWidth
    height: implicitHeight

    Component.onCompleted: root.setCell(cell.index, cell)
    // A reused delegate never runs onCompleted again.
    onPositionChanged: root.setCell(cell.index, cell)

    // QML hands back an error object, not null, for a parent that is already gone,
    // so a plain truth test is not enough to know the call is safe.
    Component.onDestruction: {
      if (owner && typeof owner.clearCell === "function") owner.clearCell(cell)
      if (childOpen && owner && typeof owner.noteChildOpen === "function") owner.noteChildOpen(true, false)
      // A cell destroyed mid-drag never reports the drag ending.
      if (owner && typeof owner.cancelChildDrag === "function" && owner.draggingIndex === cell.index)
        owner.cancelChildDrag()
    }

    function inject() {
      var target = childItem
      if (!target) return
      if ("bar" in target) target.bar = cell.host
      if ("entry" in target) target.entry = cell.plainEntry
      if ("moduleName" in target) target.moduleName = cell.childId
      if ("settings" in target) target.settings = cell.childSettings
    }

    // Ui/WidgetButton and the icons it loads take their colour from
    // bar.barForeground. Rebind that to the colour the card is painted
    // against, and only where it is still the bar's colour, so a widget that
    // chose its own is left alone. Qt.binding, not a value, so it still
    // follows the theme. A readonly property cannot be rebound and keeps the
    // bar's colour.
    function paintForTheCard(item) {
      if (!item || !root.bar) return
      // Only when the bar has moved off the theme colour. Rebinding replaces
      // the widget's own binding, so leave every widget alone when there is
      // nothing to correct.
      if (Qt.colorEqual(root.bar.barForeground, root.hostedForeground)) return
      if ("foreground" in item) {
        try {
          if (Qt.colorEqual(item.foreground, root.bar.barForeground))
            item.foreground = Qt.binding(function() { return root.hostedForeground })
        } catch (e) {
        }
      }
      var kids = item.children
      for (var i = 0; i < kids.length; i++) cell.paintForTheCard(kids[i])
    }

    onChildSettingsChanged: inject()
    onHostChanged: inject()

    property bool childOpen: childItem && childItem.opened === true
    onChildOpenChanged: {
      root.noteChildOpen(!childOpen, childOpen)
      // A child dismissed by an outside click must not leave a pinned drawer.
      if (!childOpen && root.openChildCount === 0) root.close()
    }

    Loader {
      id: qmlLoader
      anchors.fill: parent
      active: cell.customType === "qml"
      source: cell.customType === "qml" ? root.customSourceOf(cell.entry) : ""
      visible: root.revealProgress > 0.01
      opacity: cell.dragSource ? (root.draggingOutside ? 0.12 : 0.3) : 1.0
      onLoaded: {
        cell.inject()
        Qt.callLater(cell.inject)
        Qt.callLater(function() { cell.paintForTheCard(cell.childItem) })
      }
    }

    Loader {
      id: childLoader
      anchors.fill: parent
      active: cell.customType !== "qml"
      sourceComponent: cell.childComponent
      // An icon loaded from a Component does not exist until the strip is
      // drawn, so catch it on the way in as well.
      onVisibleChanged: if (visible) Qt.callLater(function() { cell.paintForTheCard(cell.childItem) })

      // Every WidgetButton here registers in `bar.clickTargets`, which
      // Bar.moduleClickTargetAt scans across windows with no idea the strip is shut.
      // It skips targets whose `visible` is false.
      visible: root.revealProgress > 0.01
      opacity: cell.dragSource ? (root.draggingOutside ? 0.12 : 0.3) : 1.0
      onLoaded: {
        cell.inject()
        Qt.callLater(cell.inject)
        Qt.callLater(function() { cell.paintForTheCard(cell.childItem) })
      }

      Behavior on opacity { NumberAnimation { duration: 90 } }
    }

    // Marks a child whose plugin is disabled.
    Text {
      anchors.centerIn: parent
      visible: !cell.custom && cell.childComponent === null && !cell.uninstalled
        && root.revealProgress > 0.01
      text: ""
      font.family: cell.host ? cell.host.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      color: cell.host ? cell.host.barForeground : Color.foreground
      opacity: 0.4
    }

    // Lets the host's id-to-widget lookups find a child that owns no layout entry.
    Item {
      id: proxySlot
      visible: false
      width: 0
      height: 0

      readonly property var entry: cell.entry
      readonly property string region: root.region
      readonly property string moduleName: cell.childId
      readonly property var moduleSettings: cell.childSettings
      readonly property string customType: cell.customType
      readonly property bool qmlCustom: cell.customType === "qml"
      readonly property bool commandCustom: cell.customType === "command"
      readonly property bool registered: true
      readonly property var registryComponent: cell.childComponent
      readonly property var activeItem: cell.childItem
      readonly property bool hovered: false
      readonly property bool dragSource: cell.dragSource
      readonly property bool panelOpen: cell.childOpen
      readonly property real panelIndicatorExtent: 0

      property var registeredWith: null

      function attach() {
        var next = cell.host
        if (next === registeredWith) return
        detach()
        registeredWith = next
        if (registeredWith && registeredWith.registerModuleSlot) registeredWith.registerModuleSlot(proxySlot)
      }

      function detach() {
        if (registeredWith && registeredWith.unregisterModuleSlot) registeredWith.unregisterModuleSlot(proxySlot)
        registeredWith = null
      }

      Component.onCompleted: attach()
      Component.onDestruction: detach()

      Connections {
        target: cell
        function onHostChanged() { proxySlot.attach() }
      }
    }

    // The host draws its dot per bar slot, so these draw their own.
    Rectangle {
      readonly property int inset: Style.space(2)
      readonly property bool alongBar: !root.vertical

      visible: opacity > 0
      opacity: cell.childOpen && !cell.dragSource ? 0.9 : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
      width: alongBar ? Math.max(Style.space(10), Math.round(cell.width * 0.55)) : Style.space(2)
      height: alongBar ? Style.space(2) : Math.max(Style.space(10), Math.round(cell.height * 0.55))
      x: alongBar
        ? Math.round((parent.width - width) / 2)
        : (root.barPosition === "left" ? inset : parent.width - width - inset)
      y: alongBar
        ? (root.barPosition === "bottom" ? parent.height - height - inset : inset)
        : Math.round((parent.height - height) / 2)
      z: 50

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
    }

    // The bar's own exec module is private to Bar.qml, so a drawer that hosts
    // one has to carry its own. Same settings, same waybar-style JSON output.
    Component {
      id: commandModule

      WidgetButton {
        id: command

        property var entry: null
        readonly property var moduleSettings: Util.isPlainObject(entry) ? entry : ({})
        property string outputText: ""
        property string outputTooltip: ""
        property bool outputActive: false

        function setting(name, fallback) {
          var value = moduleSettings[name]
          return value === undefined || value === null ? fallback : value
        }

        function update(raw) {
          var data = Util.parseModuleJson(raw)
          var klass = data.class || data.alt || ""
          outputText = data.text || String(raw || "").trim()
          outputTooltip = data.tooltip || String(setting("tooltip", ""))
          outputActive = klass === "active" || (Array.isArray(klass) && klass.indexOf("active") !== -1)
        }

        text: outputText || String(setting("text", ""))
        tooltipText: outputTooltip || String(setting("tooltip", ""))
        active: outputActive
        keepSpace: setting("keepSpace", false) === true
        horizontalMargin: Number(setting("horizontalMargin", 7.5))
        verticalPadding: Number(setting("verticalPadding", 6))
        fontSize: Number(setting("fontSize", 12))

        onPressed: function(button) {
          var script = button === Qt.RightButton ? String(setting("onRightClick", ""))
            : button === Qt.MiddleButton ? String(setting("onMiddleClick", ""))
            : String(setting("onClick", ""))
          if (script) Util.execDetached(script)
        }

        Process {
          id: commandProcess
          command: ["bash", "-lc", String(command.setting("exec", ""))]
          stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: command.update(text)
          }
        }

        Timer {
          interval: Math.max(1, Number(command.setting("interval", 5))) * 1000
          running: String(command.setting("exec", "")) !== ""
          repeat: true
          triggeredOnStart: true
          onTriggered: if (!commandProcess.running) commandProcess.running = true
        }
      }
    }

    // A handler, not a MouseArea: a MouseArea over the cell takes the press before
    // the widget does. DragHandler only claims the gesture past the threshold.
    DragHandler {
      id: cellDrag

      target: null
      acceptedButtons: Qt.LeftButton
      dragThreshold: Style.space(4)
      grabPermissions: PointerHandler.CanTakeOverFromAnything

      onActiveChanged: {
        if (active) {
          root.beginChildDrag(cell)
          root.updateChildDrag(centroid.scenePosition)
        } else root.endChildDrag()
      }
      onCanceled: root.cancelChildDrag()

      onCentroidChanged: if (active) root.updateChildDrag(centroid.scenePosition)
    }
  }
}
