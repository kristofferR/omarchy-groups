import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "GroupIcons.js" as GroupIcons
import "LayoutModel.js" as Layout

Item {
  id: root
  property var shell: null
  property var manifest: null
  property bool opened: false
  property string selectedId: ""
  property bool hasSelection: false
  property string chosenIcon: "group"
  property string message: ""
  property bool choosingIcon: false
  property bool choosingWidget: false
  property bool editingWidgets: false
  property var pluginCatalog: []
  property string catalogError: ""
  property bool catalogLoaded: false
  readonly property string pluginId: "kristofferr.groups"
  readonly property var iconNames: GroupIcons.names
  readonly property bool scopedHost: shell && !("shellConfig" in shell)
  property var diskConfig: null
  property bool writeFailed: false
  FileView {
    id: configFile
    objectName: "groupsConfig"
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: root.scopedHost
    blockAllReads: true
    atomicWrites: true
    blockWrites: true
    onFileChanged: reload()
    onSaveFailed: { root.writeFailed = true; root.message = "Could not save changes. Check that your settings folder is writable." }
    onLoaded: {
      try { root.diskConfig = JSON.parse(text()) }
      catch (error) { root.diskConfig = null }
    }
  }
  readonly property var currentConfig: {
    var config = scopedHost ? diskConfig : (shell ? shell.shellConfig : null)
    try { return JSON.parse(JSON.stringify(config)) } catch (error) { return null }
  }
  readonly property var groups: Layout.groupRows(currentConfig, pluginId)
  readonly property bool settingsShortcut: Layout.hasSettingsShortcut(currentConfig, pluginId)
  readonly property var selectedGroup: groups.find(function(group) { return group.id === selectedId }) || null
  readonly property var groupWidgets: {
    if (!currentConfig || !currentConfig.bar || !hasSelection) return []
    var found = Layout.findDrawerEntry(currentConfig.bar.layout, pluginId, selectedId)
    if (!found) return []
    return (found.entry.items || []).map(function(entry, index) {
      var id = Layout.entryIdOf(entry)
      var plugin = pluginCatalog.find(function(candidate) { return candidate.id === id })
      return {id: id, name: entry.label || (plugin ? plugin.name : id), location: {
        section: found.section, index: found.index, groupId: selectedId, itemIndex: index, snapshot: JSON.stringify(entry)}}
    }).filter(function(entry) { return entry.id && entry.id !== root.pluginId })
  }
  readonly property var availableWidgets: Layout.widgetChoices(currentConfig, pluginId, pluginCatalog, selectedId)

  function refreshCatalog() {
    catalogError = ""
    catalogLoaded = false
    var installed = shell && shell.pluginRegistry ? shell.pluginRegistry.installedPlugins : null
    if (installed) {
      pluginCatalog = Object.keys(installed).map(function(id) {
        return {id: id, name: installed[id].name || id, kinds: installed[id].kinds || []}
      })
      catalogLoaded = true
    } else if (!catalogProcess.running) catalogProcess.running = true
  }
  Process {
    id: catalogProcess
    objectName: "widgetCatalog"
    command: ["omarchy", "plugin", "list", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var plugins = JSON.parse(text)
          if (!Array.isArray(plugins)) throw new Error("Invalid catalog")
          root.pluginCatalog = plugins.map(function(plugin) {
            return {id: plugin.id, name: plugin.name || plugin.id,
              kinds: Array.isArray(plugin.kinds) ? plugin.kinds : []}
          })
          root.catalogLoaded = true
        } catch (error) { root.catalogError = "Could not load installed widgets. Try again." }
      }
    }
    onExited: function(code) { if (code !== 0) root.catalogError = "Could not load installed widgets. Try again." }
  }

  function widgetOnly(id) {
    var plugin = pluginCatalog.find(function(candidate) { return candidate.id === id })
    return !!plugin && plugin.kinds.length === 1 && plugin.kinds[0] === "bar-widget"
  }
  function showWidgets() {
    message = ""
    widgetSearch.text = ""
    choosingWidget = true
    refreshCatalog()
    Qt.callLater(function() { widgetSearch.forceActiveFocus() })
  }
  function addWidget(choice) {
    var ok = mutate(function(config) { return Layout.placeWidget(config, pluginId, selectedId, choice, widgetOnly(choice.id)) })
    message = ok ? choice.name + " added" : "The widget list changed. Try again."
    if (ok) { choosingWidget = false; editingWidgets = true; content.forceActiveFocus() }
  }
  function returnWidget(choice) {
    var ok = mutate(function(config) { return Layout.placeWidget(config, pluginId, null, choice, widgetOnly(choice.id)) })
    message = ok ? choice.name + " returned to the bar" : "The widget list changed. Try again."
  }
  function moveWidget(index, direction) {
    var ok = mutate(function(config) { return Layout.reorder(config, pluginId, index, index + (direction > 0 ? 2 : -1), selectedId) })
    message = ok ? "Widget order saved" : "Could not move this widget. Try again."
  }
  function setShortcut(enabled) {
    mutate(function(config) { return Layout.setSettingsShortcut(config, pluginId, enabled, "right") })
  }

  function selectGroup(group) {
    hasSelection = !!group
    selectedId = group ? group.id : ""
    nameField.text = group ? group.name : ""
    chosenIcon = group ? group.icon : "group"
    positionPicker.value = group ? group.section : "right"
    triggerPicker.value = group ? group.trigger : "hover"
    borderToggle.checked = !group || group.showBorder !== false
    durationField.value = group ? group.duration || 0 : 0
    message = ""
  }
  function open(payload) {
    choosingIcon = false
    choosingWidget = false
    editingWidgets = false
    if (scopedHost) configFile.reload()
    mutate(function(config) { return Layout.ensureGroupIds(config, root.pluginId) })
    refreshCatalog()
    var requestedId = selectedId
    try {
      var request = typeof payload === "string" ? JSON.parse(payload || "{}") : payload
      if (request && request.groupId !== undefined) requestedId = String(request.groupId)
    } catch (error) {}
    opened = true
    selectGroup(groups.find(function(group) { return group.id === requestedId }) || groups[0])
    Qt.callLater(function() { content.forceActiveFocus() })
  }
  function close() { opened = false }
  function toggle() { if (opened) close(); else open("") }
  function mutate(change) {
    // New scoped shell APIs omit whole-config mutation. Groups also manages
    // hosted plugin enablement, so edit the user-owned config atomically.
    if (scopedHost) {
      try {
        configFile.reload()
        var config = JSON.parse(configFile.text())
        if (!config.bar || !config.bar.layout) return false
        var changed = change(config)
        if (changed) {
          writeFailed = false
          configFile.setText(JSON.stringify(config, null, 2) + "\n")
          if (writeFailed) return false
          diskConfig = config
        }
        return changed
      } catch (error) { return false }
    }
    if (!shell || typeof shell.mutateShellConfig !== "function") return false
    var result = false
    shell.mutateShellConfig(function(config) {
      if (config.bar && config.bar.layout) result = change(config)
    })
    return result
  }
  function addGroup() {
    var id = mutate(function(config) { return Layout.addGroup(config, "kristofferr.groups", "right") })
    if (!id) { message = "Could not add a group."; return }
    selectGroup({id: id, name: "New group", icon: "group", section: "right", trigger: "hover"})
    Qt.callLater(function() { nameField.forceActiveFocus(); nameField.selectAll() })
  }
  function saveGroup() {
    if (!hasSelection) return
    var changes = {label: nameField.text, icon: chosenIcon, section: positionPicker.value, trigger: triggerPicker.value, duration: durationField.value, showBorder: borderToggle.checked}
    var ok = mutate(function(config) { return Layout.updateGroup(config, "kristofferr.groups", selectedId, changes) })
    message = ok ? "Saved" : "Could not save changes. Try again."
    if (ok) nameField.text = changes.label.trim()
  }
  function removeGroup() {
    if (!hasSelection || !catalogLoaded) return
    var widgetOnly = pluginCatalog.filter(function(plugin) {
      return plugin.kinds.length === 1 && plugin.kinds[0] === "bar-widget"
    }).map(function(plugin) { return plugin.id })
    var oldId = selectedId
    var next = groups.filter(function(group) { return group.id !== oldId })[0]
    var ok = mutate(function(config) { return Layout.removeGroup(config, "kristofferr.groups", oldId, widgetOnly) })
    if (ok) { selectGroup(next); message = "Group removed. Its icons are back on the bar." }
    else message = "Could not remove this group. Try again."
  }

  IpcHandler {
    target: "kristofferr.groups.settings-panel"
    function status(): string { return JSON.stringify({opened: root.opened, groups: root.groups, selectedId: root.selectedId, message: root.message}) }
    function close(): void { root.close() }
  }

  component Label: Text {
    color: Color.menu.text
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
    textFormat: Text.PlainText
  }

  component IconChoice: Button {
    required property string iconName
    width: Style.space(50)
    height: width
    bordered: true
    focusable: true
    selected: root.chosenIcon === iconName
    tooltipText: iconName.replace(/-/g, " ")
    onClicked: {
      root.chosenIcon = iconName
      root.choosingIcon = false
      content.forceActiveFocus()
    }
    Image {
      anchors.centerIn: parent
      width: Style.space(24); height: width
      source: GroupIcons.source(iconName, String(Color.menu.text))
      sourceSize.width: width * (window.screen ? window.screen.devicePixelRatio : 1)
      sourceSize.height: height * (window.screen ? window.screen.devicePixelRatio : 1)
    }
  }

  PanelWindow {
    id: window
    objectName: "settingsWindow"
    visible: root.opened
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-groups-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    Rectangle { anchors.fill: parent; color: Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(780), window.width - Style.gapsOut * 2)
      height: Math.min(Style.space(680), window.height - Style.gapsOut * 2)
      color: Color.menu.background
      radius: Style.cornerRadius
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      MouseArea { anchors.fill: parent }
      Column {
        id: content
        visible: !root.choosingIcon && !root.choosingWidget
        anchors.fill: parent
        anchors.margins: Style.space(24)
        spacing: Style.space(20)
        focus: true
        Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }
        Row {
          spacing: Style.space(12)
          Image {
            width: Style.space(36); height: width
            source: GroupIcons.source("manager", String(Color.accent))
            sourceSize.width: width * (window.screen ? window.screen.devicePixelRatio : 1)
            sourceSize.height: height * (window.screen ? window.screen.devicePixelRatio : 1)
          }
          Column {
            Label { text: "Groups"; font.pixelSize: Style.font.title; font.bold: true }
            Label { text: root.groups.length ? "Choose a group to customize it" : "Create a group, then add your widgets"; opacity: 0.65; font.pixelSize: Style.font.caption }
          }
        }
        Row {
          width: parent.width
          height: Math.max(0, content.height - y - footer.height - content.spacing)
          spacing: Style.space(24)
          Column {
            id: sidebar
            width: Math.round((parent.width - parent.spacing) * 0.4)
            height: parent.height
            spacing: Style.space(12)
            Flickable {
              width: parent.width
              height: Math.max(0, parent.height - addButton.height - shortcutToggle.height - parent.spacing * 2)
              contentWidth: width
              contentHeight: groupList.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              QQC.ScrollBar.vertical: QQC.ScrollBar {}
              Column {
                id: groupList
                width: parent.width
                spacing: Style.space(4)
                Repeater {
                  model: root.groups
                  Rectangle {
                    required property var modelData
                    width: groupList.width
                    height: Style.space(54)
                    radius: Style.cornerRadius
                    color: Qt.alpha(Color.menu.text, root.hasSelection && root.selectedId === modelData.id ? 0.14 : (hover.hovered ? 0.08 : 0.04))
                    Image {
                      id: groupIcon
                      anchors.left: parent.left; anchors.leftMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(20); height: width
                      source: GroupIcons.source(modelData.icon, String(Color.menu.text))
                      sourceSize.width: width * (window.screen ? window.screen.devicePixelRatio : 1)
                      sourceSize.height: height * (window.screen ? window.screen.devicePixelRatio : 1)
                    }
                    Column {
                      anchors.left: groupIcon.right; anchors.leftMargin: Style.space(10)
                      anchors.right: parent.right; anchors.rightMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      Label { width: parent.width; text: modelData.name; elide: Text.ElideRight }
                      Label { text: modelData.section + " · " + modelData.count + " icons"; font.pixelSize: Style.font.caption; opacity: 0.6 }
                    }
                    activeFocusOnTab: true
                    border.width: activeFocus ? 1 : 0
                    border.color: Color.accent
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.name
                    Keys.onReturnPressed: root.selectGroup(modelData)
                    Keys.onSpacePressed: root.selectGroup(modelData)
                    HoverHandler { id: hover }
                    TapHandler { onTapped: root.selectGroup(modelData) }
                  }
                }
              }
            }
            Button { id: addButton; objectName: "addGroup"; width: parent.width; text: "+ Add group"; bordered: true; focusable: true; onClicked: root.addGroup() }
            Toggle {
              id: shortcutToggle
              width: parent.width
              label: "Settings button on bar"
              foreground: Color.menu.text
              checked: root.settingsShortcut
              enabled: root.groups.length > 0
              onClicked: root.setShortcut(!checked)
            }
          }
          Flickable {
            width: parent.width - sidebar.width - parent.spacing
            height: parent.height
            contentWidth: width
            contentHeight: editor.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
              QQC.ScrollBar.vertical: QQC.ScrollBar {}
            Column {
              id: editor
              width: parent.width
              spacing: Style.space(16)
              visible: root.hasSelection
              Row {
                width: parent.width
                spacing: Style.space(8)
                Button { text: "Group"; selected: !root.editingWidgets; bordered: true; focusable: true; onClicked: root.editingWidgets = false }
                Button { objectName: "widgetsTab"; text: "Widgets (" + root.groupWidgets.length + ")"; selected: root.editingWidgets; bordered: true; focusable: true; onClicked: root.editingWidgets = true }
              }
              Column {
                width: parent.width
                spacing: Style.space(16)
                visible: !root.editingWidgets
                Label { text: "Name"; opacity: 0.7 }
                TextField { id: nameField; objectName: "groupName"; width: parent.width; maximumLength: 80; placeholderText: "Group name"; foreground: Color.menu.text; onAccepted: root.saveGroup() }
                Label { text: "Icon"; opacity: 0.7 }
                Button {
                  width: parent.width
                  text: root.chosenIcon.replace(/-/g, " ")
                  leftAlign: true
                  horizontalPadding: Style.space(50)
                  bordered: true
                  focusable: true
                  tooltipText: "Choose icon"
                  onClicked: {
                    iconSearch.text = ""
                    root.choosingIcon = true
                    Qt.callLater(function() { iconSearch.forceActiveFocus() })
                  }
                  Image {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(14)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(22); height: width
                    source: GroupIcons.source(root.chosenIcon, String(Color.menu.text))
                    sourceSize.width: width * (window.screen ? window.screen.devicePixelRatio : 1)
                    sourceSize.height: height * (window.screen ? window.screen.devicePixelRatio : 1)
                  }
                }
                Row {
                  width: parent.width
                  spacing: Style.space(12)
                  Dropdown { id: positionPicker; width: (parent.width - parent.spacing) / 2; label: "Position"; options: ["left", "center", "right"] }
                  Dropdown { id: triggerPicker; width: (parent.width - parent.spacing) / 2; label: "Open on"; options: ["hover", "click"] }
                }
                Toggle {
                  id: borderToggle
                  width: parent.width
                  label: "Show icon border"
                  foreground: Color.menu.text
                  onClicked: checked = !checked
                }
                NumberField { id: durationField; label: "Drawer animation (ms)"; from: 0; to: 1000; stepSize: 50; foreground: Color.menu.text; onModified: function(next) { value = next } }
                Button { objectName: "saveGroup"; text: "Save changes"; bordered: true; selected: true; focusable: true; enabled: nameField.text.trim().length > 0; onClicked: root.saveGroup() }
                Button { objectName: "removeGroup"; text: "Remove group"; enabled: root.catalogLoaded; bordered: true; focusable: true; onClicked: root.removeGroup() }
                Label { width: parent.width; text: "Removing a group returns its icons to the bar."; wrapMode: Text.WordWrap; opacity: 0.6; font.pixelSize: Style.font.caption }
              }
              Column {
                width: parent.width
                spacing: Style.space(12)
                visible: root.editingWidgets
                Button { objectName: "addWidgets"; text: "Add widgets"; bordered: true; focusable: true; onClicked: root.showWidgets() }
                Label { width: parent.width; visible: root.groupWidgets.length === 0; text: "This group is empty. Add installed widgets here, or drag icons from the bar."; wrapMode: Text.WordWrap; opacity: 0.65 }
                Repeater {
                  model: root.groupWidgets
                  Column {
                    required property var modelData
                    required property int index
                    width: parent.width
                    spacing: Style.space(6)
                    Label { width: parent.width; text: modelData.name; elide: Text.ElideRight }
                    Row {
                      spacing: Style.space(6)
                      Button { text: "↑"; tooltipText: "Move up"; Accessible.name: "Move " + modelData.name + " up"; bordered: true; focusable: true; enabled: index > 0; onClicked: root.moveWidget(index, -1) }
                      Button { text: "↓"; tooltipText: "Move down"; Accessible.name: "Move " + modelData.name + " down"; bordered: true; focusable: true; enabled: index < root.groupWidgets.length - 1; onClicked: root.moveWidget(index, 1) }
                      Button { text: "Return to bar"; enabled: root.catalogLoaded; bordered: true; focusable: true; onClicked: root.returnWidget(modelData) }
                    }
                  }
                }
                Label { width: parent.width; text: "To move a widget here from another group, choose Add widgets."; wrapMode: Text.WordWrap; font.pixelSize: Style.font.caption; opacity: 0.65 }
              }
            }
            Label { visible: !root.hasSelection; width: parent.width; text: "Add a group to get started. The settings button stays on your bar so you can always return here."; wrapMode: Text.WordWrap }
          }
        }
        Item {
          id: footer
          width: parent.width
          height: doneButton.height
          Label { anchors.left: parent.left; anchors.right: doneButton.left; anchors.rightMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter; text: root.message; wrapMode: Text.WordWrap; font.pixelSize: Style.font.caption; opacity: 0.7 }
          Button { id: doneButton; anchors.right: parent.right; text: "Done"; bordered: true; focusable: true; onClicked: root.close() }
        }
      }
      Column {
        id: widgetChooser
        anchors.fill: parent
        anchors.margins: Style.space(24)
        spacing: Style.space(16)
        visible: root.choosingWidget
        Keys.onEscapePressed: function(event) { root.choosingWidget = false; content.forceActiveFocus(); event.accepted = true }
        Row {
          width: parent.width
          spacing: Style.space(16)
          Button { text: "Back"; bordered: true; focusable: true; onClicked: { root.choosingWidget = false; content.forceActiveFocus() } }
          Label { anchors.verticalCenter: parent.verticalCenter; text: "Add widgets"; font.pixelSize: Style.font.title; font.bold: true }
        }
        Label { width: parent.width; text: "Choose an installed widget or move one from your bar or another group."; wrapMode: Text.WordWrap; opacity: 0.65 }
        TextField { id: widgetSearch; objectName: "widgetSearch"; width: parent.width; placeholderText: "Search widgets"; foreground: Color.menu.text }
        Label { width: parent.width; visible: root.message !== ""; text: root.message; wrapMode: Text.WordWrap; font.pixelSize: Style.font.caption }
        Row {
          width: parent.width
          spacing: Style.space(12)
          visible: root.catalogError !== ""
          Label { text: root.catalogError; font.pixelSize: Style.font.caption }
          Button { text: "Retry"; bordered: true; focusable: true; onClicked: root.refreshCatalog() }
        }
        ListView {
          id: widgetList
          width: parent.width
          height: Math.max(0, widgetChooser.height - y)
          clip: true
          spacing: Style.space(6)
          boundsBehavior: Flickable.StopAtBounds
          QQC.ScrollBar.vertical: QQC.ScrollBar {}
          model: root.availableWidgets.filter(function(widget) {
            var query = widgetSearch.text.trim().toLowerCase()
            return (widget.name + " " + widget.id + " " + widget.origin).toLowerCase().indexOf(query) !== -1
          })
          delegate: Button {
            required property var modelData
            width: widgetList.width
            text: modelData.name + "  ·  " + (modelData.location ? "Move from " + modelData.origin : "Add installed widget")
            leftAlign: true
            bordered: true
            focusable: true
            enabled: root.catalogLoaded
            onClicked: root.addWidget(modelData)
          }
          Label { anchors.centerIn: parent; visible: widgetList.count === 0; text: catalogProcess.running ? "Loading widgets…" : "No widgets match this search."; opacity: 0.65 }
        }
      }
      Column {
        id: iconChooser
        anchors.fill: parent
        anchors.margins: Style.space(24)
        spacing: Style.space(16)
        visible: root.choosingIcon
        Keys.onEscapePressed: function(event) { root.choosingIcon = false; content.forceActiveFocus(); event.accepted = true }
        Row {
          width: parent.width
          spacing: Style.space(16)
          Button { text: "Back"; bordered: true; focusable: true; onClicked: { root.choosingIcon = false; content.forceActiveFocus() } }
          Label { anchors.verticalCenter: parent.verticalCenter; text: "Choose an icon"; font.pixelSize: Style.font.title; font.bold: true }
        }
        TextField {
          id: iconSearch
          width: parent.width
          placeholderText: "Search " + root.iconNames.length + " icons by name or keyword"
          foreground: Color.menu.text
        }
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: iconSearch.text.trim() === ""
          Label { text: "Original icons"; opacity: 0.65; font.pixelSize: Style.font.caption }
          Flow {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: GroupIcons.originalNames
              IconChoice { required property string modelData; iconName: modelData }
            }
          }
        }
        Label {
          text: iconGrid.count + (iconSearch.text.trim() === "" ? " more icons · current: " : " matches · current: ") + root.chosenIcon.replace(/-/g, " ")
          opacity: 0.65
          font.pixelSize: Style.font.caption
        }
        GridView {
          id: iconGrid
          width: parent.width
          height: Math.max(0, iconChooser.height - y)
          cellWidth: width / Math.max(1, Math.floor(width / Style.space(56)))
          cellHeight: Style.space(56)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          QQC.ScrollBar.vertical: QQC.ScrollBar {}
          model: iconSearch.text.trim() === ""
            ? root.iconNames.filter(function(name) { return GroupIcons.originalNames.indexOf(name) === -1 })
            : GroupIcons.search(iconSearch.text)
          onModelChanged: positionViewAtBeginning()
          delegate: IconChoice {
            required property string modelData
            iconName: modelData
            width: iconGrid.cellWidth - Style.space(6)
            height: iconGrid.cellHeight - Style.space(6)
          }
          Label { anchors.centerIn: parent; visible: iconGrid.count === 0; text: "No icons match this search."; opacity: 0.65 }
        }
      }
    }
  }
}
