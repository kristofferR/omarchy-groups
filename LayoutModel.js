.pragma library

// Every shell.json edit the drawer makes, as pure functions over a config
// object. BarWidget.qml owns the bindings, timers and injection; this owns the
// data. Nothing here reads QML state, so node can run it.
//
// A config is `{ bar: { layout: { left, center, right } }, plugins: [] }`.
// Functions that take one mutate it in place, matching mutateShellConfig, which
// hands out a deep clone and persists whatever comes back.

var SECTIONS = ["left", "center", "right"]

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

// Util.canonicalWidgetId in the host is the identity function, so an id is its
// own canonical form.
function entryIdOf(entry) {
  var id = isPlainObject(entry) ? entry.id : entry
  // Not String(id) straight away: String(undefined) is "undefined", which would
  // give every id-less entry the same phantom id.
  return id === undefined || id === null ? "" : String(id)
}

// Drops entries the drawer cannot host: no id, or the drawer itself.
function normalizeEntries(raw, moduleName) {
  var out = []
  // A `var` property from the host arrives as a QVariant, so a JSON array in it
  // fails Array.isArray. Index by length instead.
  if (!raw || typeof raw !== "object" || raw.length === undefined) return out
  for (var i = 0; i < raw.length; i++) {
    var id = entryIdOf(raw[i])
    if (!id || id === moduleName) continue
    var entry = { id: id }
    if (isPlainObject(raw[i])) {
      for (var key in raw[i]) if (key !== "id") entry[key] = raw[i][key]
    }
    out.push(entry)
  }
  return out
}

// Where each hostable entry sits in the raw items array. normalizeEntries drops
// an entry with no id and the drawer itself, so a position taken from the strip
// counts past them and cannot index items directly.
function hostableIndexes(items, moduleName) {
  var out = []
  if (!Array.isArray(items)) return out
  for (var i = 0; i < items.length; i++) {
    var id = entryIdOf(items[i])
    if (!id || id === moduleName) continue
    out.push(i)
  }
  return out
}

// A group ID selects one drawer. Ambiguous or absent IDs never edit a sibling.
function findDrawerEntry(layout, moduleName, groupId) {
  var matches = []
  if (!isPlainObject(layout)) return null
  for (var s = 0; s < SECTIONS.length; s++) {
    var list = layout[SECTIONS[s]]
    if (!Array.isArray(list)) continue
    for (var i = 0; i < list.length; i++) {
      if (entryIdOf(list[i]) !== moduleName) continue
      if (String(list[i].groupId || "") !== String(groupId || "")) continue
      matches.push({ entry: list[i], section: SECTIONS[s], index: i })
    }
  }
  if (matches.length !== 1) return null
  var found = matches[0]
  if (typeof found.entry === "string") {
    found.entry = { id: found.entry }
    layout[found.section][found.index] = found.entry
  }
  return found
}

function takeFromLayout(layout, id) {
  if (!isPlainObject(layout)) return null
  for (var s = 0; s < SECTIONS.length; s++) {
    var list = layout[SECTIONS[s]]
    if (!Array.isArray(list)) continue
    for (var i = 0; i < list.length; i++) {
      if (entryIdOf(list[i]) !== id) continue
      var moved = list[i]
      list.splice(i, 1)
      return typeof moved === "string" ? { id: moved } : moved
    }
  }
  return null
}

function takeFromItems(drawerEntry, id) {
  if (!drawerEntry || !Array.isArray(drawerEntry.items)) return null
  for (var i = 0; i < drawerEntry.items.length; i++) {
    if (entryIdOf(drawerEntry.items[i]) !== id) continue
    var moved = drawerEntry.items[i]
    drawerEntry.items.splice(i, 1)
    return typeof moved === "string" ? { id: moved } : moved
  }
  return null
}

// A bar widget shell.json does not reference is disabled and never built.
function markEnabled(config, id) {
  if (!Array.isArray(config.plugins)) config.plugins = []
  for (var i = 0; i < config.plugins.length; i++) {
    if (config.plugins[i] && String(config.plugins[i].id) === id) return
  }
  config.plugins.push({ id: id })
}

// Only drops a bare marker; an entry carrying settings or other kinds stays.
function unmarkEnabled(config, id) {
  if (!Array.isArray(config.plugins)) return
  config.plugins = config.plugins.filter(function(entry) {
    if (!entry || String(entry.id) !== id) return true
    return Object.keys(entry).length > 1
  })
}

// -1 appends. `plugin` false for a custom module, which has no plugins[] entry
// to enable.
function absorb(config, moduleName, id, index, plugin, groupId) {
  if (!id || id === moduleName) return false
  // Find the drawer before taking anything out: mutateShellConfig persists the
  // mutation even on an early return, so removing first would lose the widget.
  var found = findDrawerEntry(config.bar.layout, moduleName, groupId)
  if (!found) return false
  var moved = takeFromLayout(config.bar.layout, id)
  if (!moved) return false
  if (!Array.isArray(found.entry.items)) found.entry.items = []
  var slots = hostableIndexes(found.entry.items, moduleName)
  var at = index >= 0 && index < slots.length ? slots[index] : found.entry.items.length
  found.entry.items.splice(at, 0, moved)
  if (plugin !== false) markEnabled(config, id)
  return true
}

// A destination index refers to the existing bar layout, before insertion.
function eject(config, moduleName, id, widgetOnly, groupId, destination) {
  var found = findDrawerEntry(config.bar.layout, moduleName, groupId)
  if (!found) return false
  var section = destination ? destination.section : found.section
  var index = destination ? destination.index : found.index + 1
  var list = config.bar.layout[section]
  if (!Array.isArray(list) || !Number.isInteger(index) || index < 0 || index > list.length) return false
  if (widgetOnly) reclaim(config, found.entry, id)
  var moved = takeFromItems(found.entry, id)
  if (!moved) return false
  list.splice(index, 0, moved)
  unmarkEnabled(config, id)
  return true
}

// Both groups are resolved before anything is removed. Settings and enablement
// travel with the same entry; no intermediate bar placement is persisted.
function transfer(config, moduleName, id, fromGroup, toGroup, index) {
  if (fromGroup === toGroup) return false
  var from = findDrawerEntry(config.bar.layout, moduleName, fromGroup)
  var to = findDrawerEntry(config.bar.layout, moduleName, toGroup)
  if (!from || !to) return false
  var targetItems = Array.isArray(to.entry.items) ? to.entry.items : []
  if (targetItems.some(function(entry) { return entryIdOf(entry) === id })) return false
  var moved = takeFromItems(from.entry, id)
  if (!moved) return false
  to.entry.items = targetItems
  var slots = hostableIndexes(to.entry.items, moduleName)
  var at = index >= 0 && index < slots.length ? slots[index] : to.entry.items.length
  to.entry.items.splice(at, 0, moved)
  return true
}

// `to` is an insertion index measured before the removal, so a move to a later
// position shifts down by one.
function reorder(config, moduleName, from, to, groupId) {
  if (from < 0 || to < 0 || from === to || from === to - 1) return false
  var found = findDrawerEntry(config.bar.layout, moduleName, groupId)
  if (!found || !Array.isArray(found.entry.items)) return false
  var items = found.entry.items
  var slots = hostableIndexes(items, moduleName)
  if (from >= slots.length || to > slots.length) return false
  var rawFrom = slots[from]
  var rawTo = to < slots.length ? slots[to] : items.length
  var moved = items.splice(rawFrom, 1)[0]
  items.splice(rawTo > rawFrom ? rawTo - 1 : rawTo, 0, moved)
  return true
}

// Moves settings off a plugins[] marker onto the drawer entry and shrinks the
// marker back to a bare id.
function reclaim(config, drawerEntry, id) {
  if (!Array.isArray(config.plugins) || !drawerEntry || !Array.isArray(drawerEntry.items)) return false
  var marker = null
  for (var i = 0; i < config.plugins.length; i++) {
    if (config.plugins[i] && String(config.plugins[i].id) === id) { marker = config.plugins[i]; break }
  }
  // A bare marker has nothing to fold in; replacing anyway would wipe the
  // item's own settings.
  if (!marker || Object.keys(marker).length <= 1) return false
  var slot = -1
  for (var j = 0; j < drawerEntry.items.length; j++) {
    if (entryIdOf(drawerEntry.items[j]) === id) { slot = j; break }
  }
  if (slot < 0) return false
  // updateEntryInline writes settings whole: replace, do not merge.
  var keys = Object.keys(marker)
  var next = { id: id }
  for (var k = 0; k < keys.length; k++) {
    if (keys[k] === "id") continue
    next[keys[k]] = marker[keys[k]]
    delete marker[keys[k]]
  }
  drawerEntry.items[slot] = next
  return true
}

// Both jobs in one write: config refreshes only after a write.
function reconcile(config, moduleName, gone, stranded, groupId) {
  var found = findDrawerEntry(config.bar.layout, moduleName, groupId)
  if (!found) return false
  for (var i = 0; i < gone.length; i++) {
    takeFromItems(found.entry, gone[i])
    unmarkEnabled(config, gone[i])
  }
  for (var j = 0; j < stranded.length; j++) reclaim(config, found.entry, stranded[j])
  return true
}

// A disabled plugin still has a manifest; a built-in still has a component.
// Uninstalled means neither.
function missingIds(entries, installed, widgets, moduleName, scanning) {
  // installedPlugins without the drawer in it has not been scanned yet.
  if (!installed || !installed[moduleName] || scanning) return []
  var out = []
  for (var i = 0; i < entries.length; i++) {
    var id = entries[i].id
    if (installed[id] || (widgets && widgets[id])) continue
    out.push(id)
  }
  return out
}

// updateEntryInline searches bar.layout and plugins[], not items, so a hosted
// widget's saved settings land on absorb()'s marker and nothing reads them.
// `hostedIds` is the subset safe to fold in: see BarWidget.widgetOnly.
function strandedIds(plugins, hostedIds) {
  if (!Array.isArray(plugins)) return []
  var hosted = ({})
  for (var i = 0; i < hostedIds.length; i++) hosted[hostedIds[i]] = true
  var out = []
  for (var j = 0; j < plugins.length; j++) {
    var entry = plugins[j]
    if (!entry || !hosted[String(entry.id)]) continue
    if (Object.keys(entry).length > 1) out.push(String(entry.id))
  }
  return out
}

// Settings edits resolve against the latest config, retaining hosted widgets
// and fields a different plugin or concurrent bar drag may have changed.
function addGroup(config, moduleName, section) {
  if (SECTIONS.indexOf(section) < 0 || !config.bar || !config.bar.layout) return ""
  var layout = config.bar.layout
  var used = []
  SECTIONS.forEach(function(key) {
    ;(layout[key] || []).forEach(function(entry) {
      if (entryIdOf(entry) === moduleName) used.push(String(entry.groupId || ""))
    })
  })
  var n = 1
  while (used.indexOf("group-" + n) !== -1) n++
  var id = "group-" + n
  if (!Array.isArray(layout[section])) layout[section] = []
  layout[section].push({id: moduleName, groupId: id, label: "New group", icon: "group", trigger: "hover", duration: 0, items: []})
  return id
}

function updateGroup(config, moduleName, groupId, changes) {
  if (!changes || typeof changes.label !== "string" || !changes.label.trim()
      || typeof changes.icon !== "string" || !changes.icon.trim()
      || ["hover", "click"].indexOf(changes.trigger) < 0
      || SECTIONS.indexOf(changes.section) < 0) return false
  var found = findDrawerEntry(config.bar.layout, moduleName, groupId)
  if (!found || found.entry.role === "manager") return false
  found.entry.label = changes.label.trim()
  found.entry.icon = changes.icon
  found.entry.trigger = changes.trigger
  if (found.section !== changes.section) {
    if (!Array.isArray(config.bar.layout[changes.section])) config.bar.layout[changes.section] = []
    config.bar.layout[found.section].splice(found.index, 1)
    config.bar.layout[changes.section].push(found.entry)
  }
  return true
}

function removeGroup(config, moduleName, groupId, widgetOnlyIds) {
  var found = findDrawerEntry(config.bar.layout, moduleName, groupId)
  if (!found || found.entry.role === "manager") return false
  var items = Array.isArray(found.entry.items) ? found.entry.items : []
  items.forEach(function(entry) {
    var id = entryIdOf(entry)
    if ((widgetOnlyIds || []).indexOf(id) !== -1) reclaim(config, found.entry, id)
    unmarkEnabled(config, id)
  })
  // reclaim can replace item objects, so read the resulting array again.
  var restored = found.entry.items || []
  config.bar.layout[found.section].splice.apply(config.bar.layout[found.section], [found.index, 1].concat(restored))
  // Keep settings accessible even when the last drawer is removed.
  markEnabled(config, moduleName)
  return true
}
