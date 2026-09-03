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
