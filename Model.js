.pragma library

// Pure helpers for the Reqall panel: no Qt objects, so they can be unit
// tested from the shell with `qmljs` or `node` and never touch the network.

function parseFetch(raw) {
  var text = String(raw || "").trim()
  if (!text) return { auth: "error", message: "The fetch script produced no output", recent: [], counts: null }
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") throw new Error("not an object")
    if (!Array.isArray(parsed.recent)) parsed.recent = []
    if (typeof parsed.auth !== "string") parsed.auth = "error"
    return parsed
  } catch (e) {
    return { auth: "error", message: "Could not read the fetch result", recent: [], counts: null }
  }
}

// Nerd Font glyphs, one per record kind. The fallback is a plain dot so an
// unknown kind still lines up with its neighbours.
var KIND_GLYPHS = {
  todo: "\u{F0131}",   // nf-md-checkbox_blank_outline
  issue: "",     // nf-fa-bug
  spec: "\u{F0219}",   // nf-md-file_document
  arch: "",      // nf-fa-sitemap
  test: "\u{F0668}",   // nf-md-test_tube
  info: "",      // nf-fa-info_circle
  work: "\u{F051F}"    // nf-md-timer_sand
}

function kindGlyph(kind) {
  var key = String(kind || "").toLowerCase()
  return KIND_GLYPHS[key] || "•"
}

function kindLabel(kind) {
  var key = String(kind || "").toLowerCase()
  if (key === "arch") return "architecture"
  return key || "record"
}

// "just now", "4m", "3h", "2d", then a short date once it is a week old.
function relativeTime(iso, nowMs) {
  var t = Date.parse(String(iso || ""))
  if (isNaN(t)) return ""
  var diff = Math.max(0, nowMs - t)
  var minute = 60 * 1000, hour = 60 * minute, day = 24 * hour
  if (diff < minute) return "just now"
  if (diff < hour) return Math.floor(diff / minute) + "m"
  if (diff < day) return Math.floor(diff / hour) + "h"
  if (diff < 7 * day) return Math.floor(diff / day) + "d"
  var d = new Date(t)
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return months[d.getMonth()] + " " + d.getDate()
}

// 4329 -> "4.3k", 278 -> "278", 1200000 -> "1.2M"
function compactCount(n) {
  var v = Number(n)
  if (!isFinite(v)) return "—"
  if (v < 1000) return String(Math.round(v))
  if (v < 10000) return (v / 1000).toFixed(1).replace(/\.0$/, "") + "k"
  if (v < 1000000) return Math.round(v / 1000) + "k"
  return (v / 1000000).toFixed(1).replace(/\.0$/, "") + "M"
}

function hostOf(url) {
  var m = String(url || "").match(/^[a-z]+:\/\/([^\/]+)/i)
  return m ? m[1] : String(url || "")
}

// Human sentence for the hero meta line, one per auth state.
function statusLine(data) {
  if (!data) return "Loading"
  switch (data.auth) {
  case "ok": return "Signed in · " + hostOf(data.url)
  case "none": return "Not signed in"
  case "invalid": return "Credentials rejected"
  case "paused": return "API key paused"
  case "error": return "Offline"
  default: return "Loading"
  }
}

function shellQuote(value) {
  return "'" + String(value).replace(/'/g, "'\\''") + "'"
}

// ---------------------------------------------------------------- Remember

// Record kinds the Remember form offers. "auto" sends no kind so Reqall
// classifies the record itself.
var REMEMBER_KINDS = ["auto", "todo", "issue", "spec", "arch", "info", "test", "work"]

function parseJsonDoc(raw, fallback) {
  var text = String(raw || "").trim()
  if (!text) return fallback
  try {
    var parsed = JSON.parse(text)
    return parsed && typeof parsed === "object" ? parsed : fallback
  } catch (e) {
    return fallback
  }
}

function parseProjects(raw) {
  var doc = parseJsonDoc(raw, null)
  if (!doc) return { auth: "error", message: "Could not read the project list", projects: [], used: [] }
  if (!Array.isArray(doc.projects)) doc.projects = []
  if (!Array.isArray(doc.used)) doc.used = []
  if (typeof doc.auth !== "string") doc.auth = "error"
  return doc
}

function parseRemember(raw) {
  var doc = parseJsonDoc(raw, null)
  if (!doc) return { ok: false, auth: "error", message: "Could not read the save result" }
  doc.ok = doc.ok === true
  return doc
}

function isSeparator(c) {
  return c === "/" || c === "." || c === "-" || c === "_" || c === " " || c === ":"
}

function isSubsequence(q, t, from) {
  var ti = from
  for (var i = 0; i < q.length; i++) {
    ti = t.indexOf(q[i], ti)
    if (ti === -1) return false
    ti++
  }
  return true
}

// Fuzzy subsequence score of query against text, case-insensitive. -1 when
// the query's characters do not all appear in order. Matches at the start,
// right after a separator (so "rqomp" finds ReqallSystem/omarchy_plugin by
// its word starts), and in runs score higher; a plain substring or an exact
// name beats any scattered match.
function fuzzyScore(query, text) {
  var q = String(query || "").toLowerCase().replace(/\s+/g, "")
  var t = String(text || "").toLowerCase()
  if (q === "") return 0
  if (q.length > t.length) return -1

  var best = -1
  for (var start = t.indexOf(q[0]); start !== -1; start = t.indexOf(q[0], start + 1)) {
    var score = 0, ti = start, prev = -2, ok = true
    for (var qi = 0; qi < q.length; qi++) {
      var next = t.indexOf(q[qi], ti)
      if (next === -1) { ok = false; break }
      // A mid-word hit that does not continue a run gives way to a later
      // word-start hit, as long as the rest of the query still fits after it.
      if (qi > 0 && next !== prev + 1 && !isSeparator(t[next - 1])) {
        for (var k = next + 1; k < t.length; k++) {
          if (t[k] === q[qi] && isSeparator(t[k - 1]) && isSubsequence(q.slice(qi + 1), t, k + 1)) { next = k; break }
        }
      }
      score += 1
      if (next === 0) score += 8
      else if (isSeparator(t[next - 1])) score += 6
      if (next === prev + 1) score += 4
      else if (prev >= 0) score -= Math.min(3, (next - prev - 1) * 0.1)
      prev = next
      ti = next + 1
    }
    if (ok && score > best) best = score
  }
  if (best < 0) return -1
  if (t === q) best += 100
  else if (t.indexOf(q) !== -1) best += 20
  return best
}

function activeMs(project) {
  var t = Date.parse(String(project && project.activeAt || ""))
  return isNaN(t) ? 0 : t
}

// The picker's rows for a query. With no query: the current project (the
// widget's project filter), the projects last used from this form, then the
// most recently active. With a query: fuzzy matches, best first, with current
// and used projects winning ties. Each row is the project plus a `tag`
// ("current", "last used", or "").
function rankProjects(projects, query, current, used, limit) {
  var list = Array.isArray(projects) ? projects : []
  var usedList = Array.isArray(used) ? used : []
  var max = limit > 0 ? limit : 8
  var q = String(query || "").trim()
  var cur = String(current || "")

  function tagFor(name) {
    if (cur !== "" && name === cur) return "current"
    if (usedList.indexOf(name) !== -1) return "last used"
    return ""
  }
  function preference(name) {
    if (cur !== "" && name === cur) return 0
    var i = usedList.indexOf(name)
    return i === -1 ? 1000 : 1 + i
  }

  var rows = []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p || typeof p.name !== "string") continue
    var score = q === "" ? 0 : fuzzyScore(q, p.name)
    if (score < 0) continue
    rows.push({ project: p, score: score, pref: preference(p.name), active: activeMs(p) })
  }

  rows.sort(function(a, b) {
    if (q !== "" && b.score !== a.score) return b.score - a.score
    if (a.pref !== b.pref) return a.pref - b.pref
    if (b.active !== a.active) return b.active - a.active
    return a.project.name < b.project.name ? -1 : a.project.name > b.project.name ? 1 : 0
  })

  var out = []
  for (var j = 0; j < rows.length && out.length < max; j++) {
    var row = rows[j].project
    out.push({ id: row.id, name: row.name, records: row.records || 0, activeAt: row.activeAt || "", tag: tagFor(row.name) })
  }
  return out
}

function findProject(projects, name) {
  var list = Array.isArray(projects) ? projects : []
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].name === name) return list[i]
  return null
}

function findProjectById(projects, id) {
  var list = Array.isArray(projects) ? projects : []
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].id === id) return list[i]
  return null
}

// Second line under a picker row: tag, record count, last activity.
function projectDetail(row, nowMs) {
  if (!row) return ""
  var parts = []
  if (row.tag) parts.push(row.tag)
  parts.push(compactCount(row.records) + (Number(row.records) === 1 ? " record" : " records"))
  var rel = relativeTime(row.activeAt, nowMs)
  if (rel) parts.push("active " + rel)
  return parts.join(" · ")
}
