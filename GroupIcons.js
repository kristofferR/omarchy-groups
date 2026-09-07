.pragma library
.import "LucideIcons.js" as Lucide

// Fixed viewboxes avoid Nerd Font glyph bearings shifting icons off center.
var paths = {
  "manager": "<rect x=\"2\" y=\"3\" width=\"20\" height=\"4\" rx=\"1\"/><path d=\"M6 7v4m12-4v4\"/><rect x=\"2\" y=\"11\" width=\"8\" height=\"9\" rx=\"2\"/><rect x=\"14\" y=\"11\" width=\"8\" height=\"9\" rx=\"2\"/>",
  "windows": "<rect x=\"3\" y=\"4\" width=\"18\" height=\"16\" rx=\"2\"/><path d=\"M3 9h18M9 9v11\"/>",
  "development": "<path d=\"m8 6-6 6 6 6m8-12 6 6-6 6m-3-14-2 16\"/>",
  "input": "<rect x=\"2\" y=\"5\" width=\"20\" height=\"14\" rx=\"2\"/><path d=\"M5 9h1m3 0h1m3 0h1m3 0h1M5 13h1m3 0h1m3 0h1m3 0h1M7 16h10\"/>",
  "sound": "<path d=\"m3 10 4 0 5-4v12l-5-4H3Zm13-2a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14\"/>",
  "devices": "<path d=\"M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8 16a6 6 0 0 1 8 0\"/><circle cx=\"12\" cy=\"20\" r=\"1\"/>",
  "display": "<rect x=\"2\" y=\"3\" width=\"20\" height=\"14\" rx=\"2\"/><path d=\"M8 21h8m-4-4v4\"/>",
  "appearance": "<path d=\"m12 2 3 7 7 3-7 3-3 7-3-7-7-3 7-3Z\"/>",
  "maintenance": "<path d=\"M21 4a6 6 0 0 1-8 8l-8 8-3-3 8-8a6 6 0 0 1 8-8l-4 4 3 3Z\"/>",
  "group": "<rect x=\"3\" y=\"3\" width=\"7\" height=\"7\" rx=\"1\"/><rect x=\"14\" y=\"3\" width=\"7\" height=\"7\" rx=\"1\"/><rect x=\"3\" y=\"14\" width=\"7\" height=\"7\" rx=\"1\"/><rect x=\"14\" y=\"14\" width=\"7\" height=\"7\" rx=\"1\"/>"
}

var originalNames = ["windows", "development", "input", "sound", "devices", "display", "appearance", "maintenance", "group"]
var names = originalNames
  .concat(Object.keys(Lucide.paths).filter(function(name) { return !paths[name] }).sort())

function search(query) {
  var text = String(query || "").toLowerCase().trim()
  if (!text) return names
  var tokens = text.split(/\s+/)
  var matches = names.filter(function(name) {
    var keywords = (name + " " + (Lucide.keywords[name] || "")).toLowerCase()
    return tokens.every(function(token) { return keywords.indexOf(token) !== -1 })
  })
  var exact = matches.indexOf(text)
  if (exact > 0) matches.unshift(matches.splice(exact, 1)[0])
  return matches
}

function source(name, color) {
  var body = paths[name] || Lucide.paths[name] || paths.group
  return "data:image/svg+xml;utf8," + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="'
    + color + '" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">'
    + body + '</svg>')
}
