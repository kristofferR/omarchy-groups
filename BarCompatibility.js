.pragma library
.import "LayoutModel.js" as Layout

// Stock bars before omacom/omarchy#10931 rebuild every array-backed ModuleList
// on a layout edit. Adapt only that implementation, in memory, until the native
// bar gains persistent models. The model belongs to the native Repeater so it
// survives Groups reloading or being removed from the layout.
function ensure(bar) {
  if (!bar || typeof bar.applySettingsDelta !== "function"
      || typeof bar.barConfigSerial !== "number") return

  var views = []
  var slots = bar.moduleSlots || []
  for (var i = 0; i < slots.length; i++) {
    var slot = slots[i]
    if (!slot || !("entry" in slot) || !("modelData" in slot)) continue
    var flow = slot.parent
    var owner = flow ? flow.parent : null
    if (!owner || owner.item !== flow || !Array.isArray(owner.entries)
        || typeof owner.region !== "string") continue
    var children = flow.children || []
    for (var j = 0; j < children.length; j++) {
      var view = children[j]
      if (view.model && typeof view.model.length === "number" && typeof view.itemAt === "function"
          && view.itemAdded && views.indexOf(view) < 0) views.push(view)
    }
  }

  for (var n = 0; n < views.length; n++) adapt(views[n])
}

function adapt(view) {
  // Qt.createQmlObject uses the parent's QML context. A Component created in
  // Groups' context would lose its bindings when the initial conversion
  // recreates Groups, even if its QObject parent were the native bar.
  var model = Qt.createQmlObject(`
    import QtQuick
    import QtQml.Models
    ListModel {
      id: model
      property var owner: null
      property var view: null
      property var reconcile
      function sync() { reconcile(model, owner.entries) }
      property Connections entriesConnection: Connections {
        target: model.owner
        function onEntriesChanged() { model.sync() }
      }
      property Connections itemsConnection: Connections {
        target: model.view
        function onItemAdded(index, item) {
          // Legacy delegates bind entry to modelData. Keep their existing
          // component, but decode the string role into ordinary JS settings.
          item.entry = Qt.binding(function() {
            return JSON.parse(item.modelData.entryJson)
          })
        }
      }
    }
  `, view, "GroupsBarCompatibility")
  model.owner = view.parent.parent
  model.reconcile = Layout.syncEntries
  model.sync()
  model.view = view
  view.model = model
}
