import QtQuick
import Quickshell.Io
import qs.Ui

// Native WidgetButton interactions, without commands or desktop side effects.
BarWidget {
  id: root
  property int leftClicks: 0
  property int rightClicks: 0
  property int middleClicks: 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "Probe"
    tooltipText: "Native probe tooltip"
    onPressed: function(button) {
      if (button === Qt.LeftButton) root.leftClicks++
      else if (button === Qt.RightButton) root.rightClicks++
      else if (button === Qt.MiddleButton) root.middleClicks++
    }
  }
  IpcHandler {
    target: "group-interaction-probe"
    function status(): string {
      return JSON.stringify({left: root.leftClicks, right: root.rightClicks, middle: root.middleClicks})
    }
  }
}
