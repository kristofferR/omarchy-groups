import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "GroupIcons.js" as GroupIcons

Item {
  id: root
  property var shell: null
  property var manifest: null
  property bool opened: false
  readonly property var groups: {
    var layout = shell && shell.shellConfig && shell.shellConfig.bar
      ? shell.shellConfig.bar.layout : null
    var result = []
    if (!layout) return result
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var entries = layout[sections[s]] || []
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        if (entry.id === "kristofferr.groups" && entry.role !== "manager")
          result.push({name: entry.label || "Group", icon: entry.icon || "group",
            section: sections[s], count: Array.isArray(entry.items) ? entry.items.length : 0})
      }
    }
    return result
  }

  function open(payload) {
    opened = true
    Qt.callLater(function() { content.forceActiveFocus() })
  }
  function close() { opened = false }
  function toggle() { if (opened) close(); else open("") }

  IpcHandler {
    target: "kristofferr.groups.settings-panel"
    function status(): string { return JSON.stringify({opened: root.opened, groups: root.groups}) }
    function close(): void { root.close() }
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
      width: Math.min(Style.space(520), window.width - Style.gapsOut * 2)
      height: Math.min(heading.implicitHeight + introduction.implicitHeight + groupList.implicitHeight + footer.implicitHeight + content.spacing * 3 + Style.space(48), window.height - Style.gapsOut * 2)
      color: Color.menu.background
      radius: Style.cornerRadius
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      MouseArea { anchors.fill: parent }

      Column {
        id: content
        anchors.fill: parent
        anchors.margins: Style.space(24)
        spacing: Style.space(20)
        focus: true
        Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }

        Row {
          id: heading
          spacing: Style.space(12)
          Image {
            width: Style.space(36)
            height: width
            source: GroupIcons.source("manager", String(Color.accent))
            sourceSize.width: width * (window.screen ? window.screen.devicePixelRatio : 1)
            sourceSize.height: sourceSize.width
          }
          Column {
            Text { text: "Groups"; color: Color.menu.text; font.family: Style.font.menuFamily; font.pixelSize: Style.font.title; font.bold: true }
            Text { text: "Settings"; color: Qt.alpha(Color.menu.text, 0.65); font.family: Style.font.menuFamily; font.pixelSize: Style.font.caption }
          }
        }

        Text {
          id: introduction
          width: parent.width
          text: "Drag icons between the bar and your groups to organize them."
          wrapMode: Text.WordWrap
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }

        Flickable {
          width: parent.width
          height: Math.max(0, Math.min(groupList.implicitHeight, content.height - y - footer.implicitHeight - content.spacing))
          contentWidth: width
          contentHeight: groupList.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          Column {
            id: groupList
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: root.groups
              Rectangle {
                required property var modelData
                width: groupList.width
                height: Style.space(46)
                radius: Style.cornerRadius
                color: Qt.alpha(Color.menu.text, 0.04)
                Image {
                  id: groupIcon
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(20)
                  height: width
                  source: GroupIcons.source(modelData.icon, String(Color.menu.text))
                  sourceSize.width: width * (window.screen ? window.screen.devicePixelRatio : 1)
                  sourceSize.height: sourceSize.width
                }
                Text {
                  anchors.left: groupIcon.right
                  anchors.leftMargin: Style.space(12)
                  anchors.right: details.left
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.name
                  elide: Text.ElideRight
                  color: Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  id: details
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.section + " · " + modelData.count + " icons"
                  color: Qt.alpha(Color.menu.text, 0.6)
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        Column {
          id: footer
          width: parent.width
          spacing: Style.space(16)
          Text {
            width: parent.width
            text: "Coming next: add and remove groups, customize names and icons."
            wrapMode: Text.WordWrap
            color: Qt.alpha(Color.menu.text, 0.6)
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
          Button {
            anchors.right: parent.right
            text: "Done"
            bordered: true
            focusable: true
            foreground: Color.menu.text
            onClicked: root.close()
          }
        }
      }
    }
  }
}
