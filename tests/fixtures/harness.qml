import QtQuick
import Quickshell
import qs.Ui

// Loads the real BarWidget.qml against a mock bar and shell and drives the two
// reconcile timers: the stranded-settings reclaim and the uninstalled-plugin
// prune. Both write through mutate(), so this covers the whole path from a
// binding to a config write. The layout edits themselves are covered by
// layoutmodel.test.js, and absorb and eject by drag.test.py.
// The mock mutateShellConfig mirrors the host: deep clone, mutate, reassign,
// then reinject the drawer's settings.
ShellRoot {
  id: root

  readonly property string nookId: "kristofferr.groups"
  readonly property string sourceDir: Quickshell.env("NOOK_SOURCE_DIR")

  property var widget: null
  property var secondWidget: null
  property var settingsPanel: null
  property int stage: 0
  property int ticksInStage: 0

  function fail(message) {
    console.error("NOOK_TEST_FAIL stage " + stage + ": " + message
      + " config=" + JSON.stringify(mockShell.shellConfig))
    ticker.stop()
    Qt.quit()
  }

  function namedChild(object, name) {
    if (object.objectName === name) return object
    if (object.contentItem) {
      var contentChild = namedChild(object.contentItem, name)
      if (contentChild) return contentChild
    }
    var children = object.data || object.children || []
    for (var i = 0; i < children.length; i++) {
      var found = namedChild(children[i], name)
      if (found) return found
    }
    return null
  }

  function pass() {
    console.log("NOOK_TEST_OK")
    ticker.stop()
    Qt.quit()
  }

  function drawerEntry() {
    var right = mockShell.shellConfig.bar.layout.right
    for (var i = 0; i < right.length; i++) {
      if (right[i] && right[i].id === nookId) return right[i]
    }
    return null
  }

  function itemIds() {
    var entry = drawerEntry()
    var items = entry && entry.items ? entry.items : []
    return items.map(function(item) { return typeof item === "string" ? item : item.id })
  }

  // A widget whose colour is its own and happens to match the bar's right now.
  function makeProbe(flat) {
    var probe = Qt.createQmlObject('import QtQuick; Item { property bool up: false; '
      + 'property color flat; property color foreground: up ? "#00ff00" : flat }',
      root, "probe")
    probe.flat = flat === undefined ? mockBar.barForeground : flat
    return probe
  }

  function pluginEntry(id) {
    var plugins = mockShell.shellConfig.plugins || []
    for (var i = 0; i < plugins.length; i++) {
      if (plugins[i] && plugins[i].id === id) return plugins[i]
    }
    return null
  }

  QtObject {
    id: mockRegistry
    property var installedPlugins: ({
      "kristofferr.groups": { kinds: ["bar-widget"] },
      "w.hosted": { kinds: ["bar-widget"] },
      "w.bar": { kinds: ["bar-widget"] },
    })
    property bool scanning: false
  }

  QtObject {
    id: mockShell
    property var pluginRegistry: mockRegistry
    property var shellConfig: ({
      bar: {
        layout: {
          left: [],
          center: [],
          right: [
            { id: "omarchy.clock", format: "long" },
            {
              id: root.nookId,
              groupId: "first",
              trigger: "click",
              items: [{ id: "w.hosted" }, { id: "w.bar" }],
            },
          ],
        },
      },
      // w.bar's marker carries settings: what updateEntryInline does to a
      // hosted widget that saves its own.
      plugins: [{ id: "w.hosted" }, { id: "w.bar", style: "compact" }],
    })

    function mutateShellConfig(mutator) {
      var copy = JSON.parse(JSON.stringify(shellConfig))
      mutator(copy)
      shellConfig = copy
      syncSettings()
    }

    // The host reinjects a widget's settings after every layout write.
    function syncSettings() {
      var entry = root.drawerEntry()
      if (!entry || !root.widget) return
      var settings = {}
      for (var key in entry) if (key !== "id") settings[key] = entry[key]
      root.widget.settings = settings
      if (root.secondWidget) {
        root.secondWidget.settings = shellConfig.bar.layout.left[0]
      }
    }
  }

  QtObject {
    id: mockWidgetRegistry
    property var widgets: ({})
  }

  QtObject {
    id: mockBar
    property var shell: mockShell
    property var barWidgetRegistry: mockWidgetRegistry
    property string position: "top"
    property bool vertical: false
    property int barSize: 36
    property string fontFamily: "sans-serif"
    property color background: "#292025"
    property color foreground: "#ffffff"
    property color barForeground: "#ffffff"
    property color themeForeground: "#fff4d8"
    property color themeContrastForeground: "#292025"
    property bool useTransparentForeground: false
    property color urgent: "#ff5555"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    function requestPopout(owner) {
      if (activePopout === owner) return
      if (activePopout) activePopout.close()
      activePopout = owner
    }
    function releasePopout(owner) {
      if (activePopout === owner) activePopout = null
    }
    property var moduleSlots: []
    property var barDragSource: null
    property var barDragWindow: null
    property var barDragTarget: null
    property real barDragSceneX: 0
    property real barDragSceneY: 0
    // Empty peers make every instance the config writer.
    function moduleWidgets(_name) { return [root.widget, root.secondWidget].filter(function(w) { return !!w }) }
    function registerClickTarget(_target) {}
    function unregisterClickTarget(_target) {}
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
  }

  Component {
    id: popupProbe
    Panel {
      id: probe
      implicitWidth: 24
      implicitHeight: 24
      // Mirrors KeyboardPanel's binding-driven popout handoff without mapping
      // an input surface on the user's desktop.
      property bool popupOpen: opened
      onPopupOpenChanged: {
        if (popupOpen) mockBar.requestPopout(probe)
        else mockBar.releasePopout(probe)
      }
    }
  }

  QtObject { id: scopedShell; property var barConfig: ({}) }

  Item { id: host }

  Timer {
    interval: 1
    running: true
    onTriggered: {
      var component = Qt.createComponent(
        encodeURI("file://" + root.sourceDir + "/BarWidget.qml"),
        Component.PreferSynchronous)
      if (component.status !== Component.Ready) {
        console.error("NOOK_TEST_FAIL load: " + component.errorString())
        Qt.quit()
        return
      }
      root.widget = component.createObject(host, {
        bar: mockBar,
        moduleName: root.nookId,
      })
      if (!root.widget) {
        console.error("NOOK_TEST_FAIL create: " + component.errorString())
        Qt.quit()
        return
      }
      mockShell.syncSettings()
      console.log("NOOK_LOAD_OK")
      ticker.start()
    }
  }

  Timer {
    id: ticker
    interval: 50
    repeat: true
    onTriggered: root.tick()
  }

  function next() { stage += 1; ticksInStage = 0 }

  function tick() {
    ticksInStage += 1
    if (ticksInStage > 100) { fail("timed out"); return }

    if (stage === 0) {
      if (widget.entries.length !== 2 || widget.entries[0].id !== "w.hosted")
        return fail("initial entries: " + JSON.stringify(widget.entries))
      if (widget.trigger !== "click") return fail("trigger setting not injected")
      if (widget.missingIds.length !== 0) return fail("clean config flagged an uninstall")
      if (widget.strandedIds.join() !== "w.bar")
        return fail("stranded settings not spotted: " + widget.strandedIds)

      // A transparent bar over a light wallpaper picks the theme background as
      // its foreground. The card keeps the theme, and hosted widgets are
      // repainted against it.
      if (!Qt.colorEqual(widget.cardBackground, mockBar.background))
        return fail("card left the theme: " + widget.cardBackground)
      if (!Qt.colorEqual(widget.hostedForeground, mockBar.themeForeground))
        return fail("hosted foreground is not the theme colour")

      mockBar.barForeground = mockBar.themeContrastForeground
      mockBar.useTransparentForeground = true
      if (!Qt.colorEqual(widget.cardBackground, mockBar.background))
        return fail("a transparent bar must not move the card")
      if (Qt.colorEqual(widget.hostedForeground, widget.cardBackground))
        return fail("hosted widgets would be drawn in the card's colour")

      // The repaint replaces a widget's own binding, so it must run only when
      // the bar has left the theme colour. A frozen probe still reports the
      // right colour, so watch the binding rather than the value.
      var probe = makeProbe()
      widget.cells[0].paintForTheCard(probe)
      probe.up = true
      if (Qt.colorEqual(probe.foreground, "#00ff00"))
        return fail("a widget on the bar's colour was left adaptive")
      // Repainted with a binding, not a value, so a theme change still lands.
      mockBar.themeForeground = "#123456"
      if (!Qt.colorEqual(probe.foreground, "#123456"))
        return fail("a repainted widget stopped following the theme")
      mockBar.themeForeground = "#fff4d8"
      probe.destroy()

      mockBar.barForeground = mockBar.themeForeground
      probe = makeProbe(mockBar.themeForeground)
      widget.cells[0].paintForTheCard(probe)
      probe.up = true
      if (!Qt.colorEqual(probe.foreground, "#00ff00"))
        return fail("repaint ran while the bar was already on the theme colour")
      probe.destroy()

      mockBar.barForeground = mockBar.themeForeground
      mockBar.useTransparentForeground = false
      next()
    } else if (stage === 1) {
      // The reconcile timer fires 250ms after strandedIds changes.
      var item = drawerEntry().items[1]
      var marker = pluginEntry("w.bar")
      if (typeof item !== "object" || item.style !== "compact" || !marker
          || Object.keys(marker).length !== 1) return
      if (widget.strandedIds.length !== 0) return fail("strandedIds not cleared")
      // Uninstall the hosted plugin.
      var remaining = JSON.parse(JSON.stringify(mockRegistry.installedPlugins))
      delete remaining["w.bar"]
      mockRegistry.installedPlugins = remaining
      next()
    } else if (stage === 2) {
      if (ticksInStage === 1 && widget.missingIds.join() !== "w.bar")
        return fail("uninstall not flagged: " + widget.missingIds)
      // While the removal waits to be written, the dead cell must not draw.
      if (widget.missingIds.length > 0) {
        for (var i = 0; i < widget.cells.length; i++) {
          var cell = widget.cells[i]
          if (cell && cell.childId === "w.bar"
              && (cell.implicitWidth !== 0 || cell.implicitHeight !== 0))
            return fail("uninstalled cell still takes room")
        }
      }
      // The prune waits out settleDelay (1.5s) before it writes.
      if (itemIds().join() !== "w.hosted" || pluginEntry("w.bar")) return
      if (widget.missingIds.length !== 0) return fail("missingIds not cleared")
      var copy = JSON.parse(JSON.stringify(mockShell.shellConfig))
      copy.bar.layout.left = [{id: nookId, groupId: "second", trigger: "click", items: []}]
      mockShell.shellConfig = copy
      var component = Qt.createComponent(encodeURI("file://" + sourceDir + "/BarWidget.qml"), Component.PreferSynchronous)
      secondWidget = component.createObject(host, {bar: mockBar, moduleName: nookId,
        settings: copy.bar.layout.left[0]})
      if (!secondWidget || !secondWidget.configWriter) return fail("second group cannot write config")
      secondWidget.absorb("omarchy.clock", -1)
      if (itemIds().join() !== "w.hosted") return fail("second group changed first group")
      if (secondWidget.entries.length !== 1 || secondWidget.entries[0].format !== "long")
        return fail("second group did not retain absorbed settings")
      secondWidget.eject("omarchy.clock")
      if (mockShell.shellConfig.bar.layout.left[1].id !== "omarchy.clock")
        return fail("eject went to wrong region")
      // Suppress mapping windows in this harness while testing open coordination.
      widget.settings = {groupId: "first", items: [], trigger: "click"}
      secondWidget.settings = {groupId: "second", items: [], trigger: "click"}
      widget.open()
      if (!widget.latched || secondWidget.latched) return fail("open leaked into sibling")
      secondWidget.open()
      if (widget.expanded || !secondWidget.expanded) return fail("opening second did not close first")
      secondWidget.broadcastGroup("close")
      if (secondWidget.expanded) return fail("close failed")
      secondWidget.settings = {groupId: "second", items: [], trigger: "hover"}
      secondWidget.close()
      secondWidget.pointerInside = true
      if (!secondWidget.hoverHeld) return fail("close outside group suppressed next hover")
      secondWidget.close()
      if (secondWidget.hoverHeld) return fail("close under pointer immediately reopened group")
      secondWidget.pointerInside = false
      secondWidget.pointerInside = true
      if (!secondWidget.hoverHeld) return fail("leaving and returning did not restore hover")
      secondWidget.pointerInside = false
      secondWidget.close()
      mockRegistry.installedPlugins = {
        "w.first": {kinds: ["bar-widget"]},
        "w.second": {kinds: ["bar-widget"]}
      }
      mockWidgetRegistry.widgets = {
        "w.first": {component: popupProbe},
        "w.second": {component: popupProbe}
      }
      widget.settings = {groupId: "first", trigger: "click", items: ["w.first", "w.second"]}
      next()
    } else if (stage === 3) {
      if (widget.cells.length !== 2 || !widget.cells[0].childItem || !widget.cells[1].childItem) return
      var firstCell = widget.cells[0]
      var secondCell = widget.cells[1]
      var firstItem = firstCell.childItem
      var secondItem = secondCell.childItem
      // A settings reinjection hands Groups its scoped API again. Its native
      // host and loaded children must survive that presentation-only change.
      widget.bar = scopedShell
      if (widget.hostBar !== mockBar || widget.cells[0].childItem !== firstItem)
        return fail("scoped API reinjection unloaded the widget registry")
      widget.bar = mockBar
      widget.settings = {groupId: "first", trigger: "click", items: [
        "w.second", {id: "w.first", options: {values: [1, 2]}}
      ]}
      if (widget.cells[0] !== secondCell || widget.cells[1] !== firstCell
          || widget.cells[1].childItem !== firstItem || widget.cells[0].childItem !== secondItem)
        return fail("reorder recreated a hosted widget")
      if (!Array.isArray(firstItem.settings.options.values) || firstItem.settings.options.values[1] !== 2)
        return fail("model changed nested settings into a ListModel")
      widget.settings = {groupId: "first", trigger: "click", items: ["w.first"]}
      if (widget.cells.length !== 1 || widget.cells[0] !== firstCell || widget.cells[0].childItem !== firstItem)
        return fail("removal recreated the remaining widget")
      widget.settings = {groupId: "first", trigger: "click", items: ["w.first", "w.second"]}
      if (widget.cells[0] !== firstCell || widget.cells[0].childItem !== firstItem)
        return fail("insertion recreated the existing widget")
      widget.cells[0].childItem.open()
      if (widget.openChildCount !== 1) return fail("first popup did not hold drawer open")
      widget.cells[1].childItem.open()
      next()
    } else if (stage === 4) {
      var first = widget.cells[0].childItem
      var second = widget.cells[1].childItem
      if (first.opened || !second.opened || !second.controller.open || !second.popupOpen)
        return fail("popup handoff corrupted child open state")
      if (widget.openChildCount !== 1 || !widget.expanded || mockBar.activePopout !== second)
        return fail("popup handoff lost drawer or popout ownership")
      second.close()
      next()
    } else if (stage === 5) {
      if (widget.expanded || widget.openChildCount !== 0 || mockBar.activePopout !== null)
        return fail("last popup dismissal did not release drawer")
      widget.cells[1].childItem.open()
      widget.close()
      next()
    } else if (stage === 6) {
      if (widget.expanded || widget.cells[1].childItem.opened || mockBar.activePopout !== null)
        return fail("explicit group close did not dismiss child")
      var component = Qt.createComponent(encodeURI("file://" + sourceDir + "/Settings.qml"), Component.PreferSynchronous)
      settingsPanel = component.createObject(host, {shell: mockShell})
      if (!settingsPanel) return fail(component.errorString())
      // Keep the settings surface unmapped. Exercise the real controls against
      // the mock config, so this never edits the user's layout or takes focus.
      var surface = namedChild(settingsPanel, "settingsWindow")
      if (!surface) return fail("settings surface not found")
      surface.visible = false
      mockRegistry.installedPlugins = {"w.clock": {name: "Clock", kinds: ["bar-widget"]}, "w.new": {name: "New", kinds: ["bar-widget"]}}
      mockShell.shellConfig = {bar: {layout: {left: [{id: "w.clock", format: "short"}], center: [], right: ["kristofferr.groups"]}}, plugins: []}
      settingsPanel.open("{}")
      if (settingsPanel.groups.length !== 1 || !settingsPanel.selectedId) return fail("initial settings did not assign group identity")
      namedChild(settingsPanel, "groupName").text = "My group"
      namedChild(settingsPanel, "saveGroup").clicked()
      if (settingsPanel.groups[0].name !== "My group") return fail("name control did not save")
      namedChild(settingsPanel, "widgetsTab").clicked()
      namedChild(settingsPanel, "addWidgets").clicked()
      settingsPanel.addWidget(settingsPanel.availableWidgets.find(function(choice) { return choice.id === "w.clock" }))
      if (settingsPanel.groupWidgets.length !== 1) return fail("widget picker did not move clock")
      settingsPanel.showWidgets()
      settingsPanel.addWidget(settingsPanel.availableWidgets.find(function(choice) { return choice.id === "w.new" }))
      settingsPanel.moveWidget(1, -1)
      if (settingsPanel.groupWidgets[0].id !== "w.new") return fail("widget reorder control failed")
      settingsPanel.returnWidget(settingsPanel.groupWidgets[1])
      if (mockShell.shellConfig.bar.layout.right[1].format !== "short") return fail("return to bar lost widget settings")
      var originalId = settingsPanel.selectedId
      namedChild(settingsPanel, "addGroup").clicked()
      if (settingsPanel.groups.length !== 2) return fail("Add group button failed")
      var newId = settingsPanel.selectedId
      settingsPanel.open(JSON.stringify({groupId: originalId}))
      if (settingsPanel.selectedId !== originalId) return fail("settings ignored clicked group")
      namedChild(settingsPanel, "removeGroup").clicked()
      settingsPanel.selectGroup(settingsPanel.groups.find(function(group) { return group.id === newId }))
      namedChild(settingsPanel, "removeGroup").clicked()
      if (settingsPanel.groups.length || !settingsPanel.settingsShortcut) return fail("last group removed settings access")
      namedChild(settingsPanel, "addGroup").clicked()
      if (settingsPanel.groups.length !== 1) return fail("cannot start again after removing all groups")
      settingsPanel.close()
      settingsPanel.destroy()
      settingsPanel = component.createObject(host, {shell: scopedShell})
      namedChild(settingsPanel, "settingsWindow").visible = false
      var file = namedChild(settingsPanel, "groupsConfig")
      file.path = Quickshell.env("GROUPS_TEST_CONFIG")
      file.setText(JSON.stringify({version: 1, bar: {layout: {left: [], center: [], right: ["kristofferr.groups"]}}, plugins: [{id: "other-service", setting: "keep"}]}))
      namedChild(settingsPanel, "widgetCatalog").command = ["printf", "%s", JSON.stringify([{id: "w.new", name: "New", kinds: ["bar-widget"]}])]
      settingsPanel.open("{}")
      next()
    } else if (stage === 7) {
      if (!settingsPanel.catalogLoaded) return
      if (settingsPanel.groups.length !== 1 || !settingsPanel.selectedId) return fail("scoped settings did not load initial group")
      namedChild(settingsPanel, "groupName").text = "Saved to disk"
      namedChild(settingsPanel, "saveGroup").clicked()
      settingsPanel.addWidget(settingsPanel.availableWidgets.find(function(choice) { return choice.id === "w.new" }))
      var saved = JSON.parse(namedChild(settingsPanel, "groupsConfig").text())
      if (saved.bar.layout.right[0].label !== "Saved to disk" || saved.bar.layout.right[0].items[0].id !== "w.new")
        return fail("scoped settings did not persist name and widgets")
      if (saved.plugins[0].setting !== "keep") return fail("scoped settings overwrote unrelated service settings")
      settingsPanel.close()
      secondWidget.settings = {groupId: "second", items: [], trigger: "hover"}
      secondWidget.close()
      secondWidget.draggingIndex = 0
      if (!secondWidget.expanded || !secondWidget.hoverGrace) return fail("drag did not hold reveal grace")
      secondWidget.draggingIndex = -1
      if (!secondWidget.expanded) return fail("release closed drawer before hover handoff")
      secondWidget.pointerInside = true
      if (!secondWidget.hoverHeld || !secondWidget.expanded) return fail("hover did not take over after drop")
      secondWidget.pointerInside = false
      next()
    } else if (stage === 8) {
      if (ticksInStage < 6) return
      if (secondWidget.hoverGrace || secondWidget.expanded) return fail("drop grace did not expire after pointer left")
      pass()
    }
  }
}
