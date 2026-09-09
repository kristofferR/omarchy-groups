import QtQuick
import QtQml.Models
import Quickshell
import "BarCompatibility.js" as Compatibility

ShellRoot {
  id: root
  property int stage: 0
  property var retained: []
  property var adaptedModel

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }
  function entry(id, items) { return {id: id, items: items || []} }

  // Preserve the legacy ModuleList's Loader/flow/Repeater structure and its
  // required modelData role. This catches Qt lifecycle and role conversion
  // failures that the pure reconciliation tests cannot exercise.
  Item {
    id: bar
    property int barConfigSerial: 0
    property var moduleSlots: []
    function applySettingsDelta() {}
    function register(slot) { moduleSlots = moduleSlots.concat([slot]) }
    function unregister(slot) { moduleSlots = moduleSlots.filter(s => s !== slot) }

    Loader {
      id: list
      property var entries: [root.entry("clock"), root.entry("groups", ["a"]), root.entry("groups", ["b"])]
      property string region: "right"
      property bool vertical: false
      active: entries.length > 0
      sourceComponent: vertical ? column : row
      Component {
        id: row
        Row {
          Repeater {
            model: list.entries
            delegate: slot
          }
        }
      }
      Component {
        id: column
        Column {
          Repeater {
            model: list.entries
            delegate: slot
          }
        }
      }
    }
    Component {
      id: slot
      Item {
        required property var modelData
        property var entry: modelData
        property string region: list.region
        property var settings: entry && entry.items
        Component.onCompleted: bar.register(this)
        Component.onDestruction: bar.unregister(this)
      }
    }
  }
  // Installing from a disposable widget must not tie the model's connections
  // to that widget's context. All later stages run after it has been destroyed.
  Loader {
    id: installer
    active: false
    sourceComponent: Component {
      Item { Component.onCompleted: Compatibility.ensure(bar) }
    }
  }

  function view() { return list.item.children.find(child => typeof child.itemAt === "function") }
  function items() {
    var result = []
    for (var i = 0; i < view().count; i++) result.push(view().itemAt(i))
    return result
  }

  Timer {
    interval: 25
    running: true
    repeat: true
    onTriggered: {
      try {
        if (root.stage === 0) {
          check(typeof view().model.length === "number", "fixture must start on the legacy array path")
          root.retained = items()
          Compatibility.ensure({moduleSlots: bar.moduleSlots})
          check(typeof view().model.length === "number" && items()[0] === retained[0], "modern bar was changed")
          installer.active = true
          check(typeof view().model.get === "function", "legacy bar was not adapted")
          installer.active = false
          root.adaptedModel = view().model
          root.retained = items()
          check(retained.length === 3 && Array.isArray(retained[1].settings), "nested settings must remain JS arrays")
          Compatibility.ensure(bar)
          check(view().model === adaptedModel && items()[0] === retained[0], "repeated installation rebuilt delegates")
          list.entries = [entry("groups", ["b"]), entry("clock"), entry("groups", ["a", {id: "nested", values: [1, 2]}])]
        } else if (root.stage === 1) {
          check(items()[0] === retained[2] && items()[1] === retained[0] && items()[2] === retained[1], "reorder or duplicate-ID settings rebuilt widgets")
          check(Array.isArray(items()[2].entry.items[1].values), "nested arrays became models")
          check(items()[2].entry.items.length === 2, "updated settings did not propagate")
          // The legacy settings-only fast path changes a live widget directly.
          // An unrelated layout edit must not reinject its old settings.
          items()[1].settings = ["live setting"]
          list.entries = [entry("new"), ...list.entries]
        } else if (root.stage === 2) {
          check(items()[2] === retained[0] && items()[2].settings[0] === "live setting", "insert reset an untouched widget")
          list.entries = list.entries.slice(1)
        } else if (root.stage === 3) {
          check(items()[1] === retained[0], "remove reset a surviving widget")
          list.vertical = true
        } else if (root.stage === 4) {
          Compatibility.ensure(bar)
          check(typeof view().model.get === "function", "new orientation was not adapted")
          root.retained = items()
          list.entries = list.entries.slice().reverse()
        } else if (root.stage === 5) {
          check(items()[1] === retained[1], "new orientation rebuilt surviving widgets")
          list.entries = []
        } else if (root.stage === 6) {
          check(list.item === null, "empty list stayed loaded")
          list.entries = [entry("clock")]
        } else if (root.stage === 7) {
          Compatibility.ensure(bar)
          check(typeof view().model.get === "function", "reactivated list was not adapted")
          console.log("GROUPS_COMPAT_OK")
          stop()
          Qt.quit()
        }
        root.stage++
      } catch (error) {
        console.error("GROUPS_COMPAT_FAIL stage " + root.stage + ": " + error)
        stop()
        Qt.quit()
      }
    }
  }
}
