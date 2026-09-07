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
  readonly property var iconNames: GroupIcons.names
  readonly property var groups: {
    var layout = shell && shell.shellConfig && shell.shellConfig.bar ? shell.shellConfig.bar.layout : null
    var result = []
    if (!layout) return result
    Layout.SECTIONS.forEach(function(section) {
      ;(layout[section] || []).forEach(function(entry) {
        if (Layout.entryIdOf(entry) === "kristofferr.groups" && entry.role !== "manager")
          result.push({id: String(entry.groupId || ""), name: entry.label || "Group", icon: entry.icon || "group",
            trigger: entry.trigger || "hover", showBorder: entry.showBorder !== false, section: section, count: entry.items ? entry.items.length : 0})
      })
    })
    return result
  }

  function selectGroup(group) {
    hasSelection = !!group
    selectedId = group ? group.id : ""
    nameField.text = group ? group.name : ""
    chosenIcon = group ? group.icon : "group"
    positionPicker.value = group ? group.section : "right"
    triggerPicker.value = group ? group.trigger : "hover"
    borderToggle.checked = !group || group.showBorder !== false
    message = ""
  }
  function open(payload) {
    choosingIcon = false
    opened = true
    selectGroup(groups.find(function(group) { return group.id === selectedId }) || groups[0])
    Qt.callLater(function() { content.forceActiveFocus() })
  }
  function close() { opened = false }
  function toggle() { if (opened) close(); else open("") }
  function mutate(change) {
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
    var changes = {label: nameField.text, icon: chosenIcon, section: positionPicker.value, trigger: triggerPicker.value, showBorder: borderToggle.checked}
    var ok = mutate(function(config) { return Layout.updateGroup(config, "kristofferr.groups", selectedId, changes) })
    message = ok ? "Saved" : "Could not save. Check the name and that the group ID is unique."
    if (ok) nameField.text = changes.label.trim()
  }
  function removeGroup() {
    if (!hasSelection) return
    var installed = shell && shell.pluginRegistry ? shell.pluginRegistry.installedPlugins : ({})
    var widgetOnly = Object.keys(installed || {}).filter(function(id) {
      var kinds = installed[id].kinds
      return kinds && kinds.length === 1 && kinds[0] === "bar-widget"
    })
    var oldId = selectedId
    var next = groups.filter(function(group) { return group.id !== oldId })[0]
    var ok = mutate(function(config) { return Layout.removeGroup(config, "kristofferr.groups", oldId, widgetOnly) })
    if (ok) { selectGroup(next); message = "Group removed. Its icons are back on the bar." }
    else message = "Could not remove this group. Its ID may be ambiguous."
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

  PanelWindow {
    id: window
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
        visible: !root.choosingIcon
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
            sourceSize.height: sourceSize.width
          }
          Column {
            Label { text: "Groups"; font.pixelSize: Style.font.title; font.bold: true }
            Label { text: "Choose a group to customize it"; opacity: 0.65; font.pixelSize: Style.font.caption }
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
              height: Math.max(0, parent.height - addButton.height - parent.spacing)
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
                      sourceSize.height: sourceSize.width
                    }
                    Column {
                      anchors.left: groupIcon.right; anchors.leftMargin: Style.space(10)
                      anchors.right: parent.right; anchors.rightMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      Label { width: parent.width; text: modelData.name; elide: Text.ElideRight }
                      Label { text: modelData.section + " · " + modelData.count + " icons"; font.pixelSize: Style.font.caption; opacity: 0.6 }
                    }
                    HoverHandler { id: hover }
                    TapHandler { onTapped: root.selectGroup(modelData) }
                  }
                }
              }
            }
            Button { id: addButton; width: parent.width; text: "+ Add group"; bordered: true; focusable: true; onClicked: root.addGroup() }
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
              Label { text: "Name"; opacity: 0.7 }
              TextField { id: nameField; width: parent.width; maximumLength: 80; placeholderText: "Group name"; foreground: Color.menu.text; onAccepted: root.saveGroup() }
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
                  sourceSize.height: sourceSize.width
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
              Button { text: "Save changes"; bordered: true; selected: true; focusable: true; enabled: nameField.text.trim().length > 0; onClicked: root.saveGroup() }
              Label { width: parent.width; text: "Drag icons to reorder them or move them between groups."; wrapMode: Text.WordWrap; opacity: 0.6; font.pixelSize: Style.font.caption }
              Button { text: "Remove group"; bordered: true; focusable: true; onClicked: root.removeGroup() }
              Label { width: parent.width; text: "Removing a group returns its icons to the bar."; wrapMode: Text.WordWrap; opacity: 0.6; font.pixelSize: Style.font.caption }
            }
            Label { visible: !root.hasSelection; width: parent.width; text: "Add a group to get started."; wrapMode: Text.WordWrap }
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
        Label {
          text: iconGrid.count + " icons · current: " + root.chosenIcon.replace(/-/g, " ")
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
          model: GroupIcons.search(iconSearch.text)
          onModelChanged: positionViewAtBeginning()
          delegate: Button {
            required property string modelData
            width: iconGrid.cellWidth - Style.space(6)
            height: iconGrid.cellHeight - Style.space(6)
            bordered: true
            focusable: true
            selected: root.chosenIcon === modelData
            tooltipText: modelData.replace(/-/g, " ")
            onClicked: {
              root.chosenIcon = modelData
              root.choosingIcon = false
              content.forceActiveFocus()
            }
            Image {
              anchors.centerIn: parent
              width: Style.space(24); height: width
              source: GroupIcons.source(modelData, String(Color.menu.text))
              sourceSize.width: width * (window.screen ? window.screen.devicePixelRatio : 1)
              sourceSize.height: sourceSize.width
            }
          }
          Label { anchors.centerIn: parent; visible: iconGrid.count === 0; text: "No icons match this search."; opacity: 0.65 }
        }
      }
    }
  }
}
