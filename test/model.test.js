// Unit tests for the pure helpers in Model.js. Run with: node --test
//
// Model.js is a QML `.pragma library` script, not a CommonJS module, so it is
// loaded into a fresh VM context with the pragma line removed. Results are
// copied back through JSON so arrays from that context compare equal here.

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*$/m, "")
const context = vm.createContext({})
vm.runInContext(source, context)
const plain = (v) => (v === undefined ? v : JSON.parse(JSON.stringify(v)))
const Model = new Proxy(context, {
  get: (target, name) => (typeof target[name] === "function" ? (...args) => plain(target[name](...args)) : target[name]),
})

const names = [
  "ReqallSystem/omarchy_plugin",
  "ReqallSystem/claude-plugin",
  "ReqallSystem/codex-plugin",
  "fingerskier/reqall_net",
  "fingerskier/omarchy_postgres",
  ".machine/omarchy/fingerskier",
  ".user",
  "acme/notes",
]
const projects = names.map((name, i) => ({
  id: i + 1,
  name,
  records: i * 3,
  activeAt: new Date(Date.UTC(2026, 9, 1 + i)).toISOString(), // later index = more recent
}))
const ranked = (q, current = "", used = [], limit = 8) =>
  Model.rankProjects(projects, q, current, used, limit).map((r) => r.name)

test("fuzzyScore matches subsequences and rejects the rest", () => {
  assert.ok(Model.fuzzyScore("rqomp", "ReqallSystem/omarchy_plugin") > 0)
  assert.equal(Model.fuzzyScore("zzz", "ReqallSystem/omarchy_plugin"), -1)
  assert.equal(Model.fuzzyScore("pluginx", "plugin"), -1)
  assert.equal(Model.fuzzyScore("", "anything"), 0)
})

test("fuzzyScore does not lose a match by jumping to a later word start", () => {
  assert.ok(Model.fuzzyScore("abc", "axbc-b") > 0)
})

test("fuzzyScore prefers exact, then substring, then word starts", () => {
  const exact = Model.fuzzyScore(".user", ".user")
  const sub = Model.fuzzyScore("notes", "acme/notes")
  const scattered = Model.fuzzyScore("notes", "nothing-to-see-s")
  assert.ok(exact > sub, "exact beats substring")
  assert.ok(sub > scattered, "substring beats scattered")
  assert.ok(Model.fuzzyScore("op", "x/omarchy_plugin") > Model.fuzzyScore("op", "xoxxxpx"),
    "word starts beat a scattered mid-word match")
})

test("rankProjects with no query: current, then used, then most recent", () => {
  const out = ranked("", "fingerskier/reqall_net", ["ReqallSystem/codex-plugin", "acme/notes"], 5)
  assert.deepEqual(out, [
    "fingerskier/reqall_net",
    "ReqallSystem/codex-plugin",
    "acme/notes",
    ".user",
    ".machine/omarchy/fingerskier",
  ])
})

test("rankProjects tags current and used rows", () => {
  const rows = Model.rankProjects(projects, "", "acme/notes", [".user"], 3)
  assert.deepEqual(rows.map((r) => [r.name, r.tag]), [
    ["acme/notes", "current"],
    [".user", "last used"],
    [".machine/omarchy/fingerskier", ""],
  ])
})

test("rankProjects with a query puts the best fuzzy match first", () => {
  assert.equal(ranked("rqomp")[0], "ReqallSystem/omarchy_plugin")
  assert.equal(ranked("omarchy")[0], ".machine/omarchy/fingerskier") // tie on substring; more recent wins
  assert.equal(ranked("omarchy", "", ["ReqallSystem/omarchy_plugin"])[0], "ReqallSystem/omarchy_plugin")
  assert.equal(ranked("claude")[0], "ReqallSystem/claude-plugin")
  assert.deepEqual(ranked("nomatchhere"), [])
})

test("rankProjects respects the limit and tolerates junk input", () => {
  assert.equal(ranked("", "", [], 3).length, 3)
  assert.deepEqual(Model.rankProjects(null, "x", "", null, 5), [])
  assert.deepEqual(Model.rankProjects([null, { id: 1 }], "", "", [], 5), [])
})

test("findProject and findProjectById", () => {
  assert.equal(Model.findProject(projects, "acme/notes").id, 8)
  assert.equal(Model.findProjectById(projects, 8).name, "acme/notes")
  assert.equal(Model.findProjectById(projects, 999), null)
  assert.equal(Model.findProjectById(null, 1), null)
})

test("parse helpers fall back on bad input", () => {
  assert.equal(Model.parseProjects("").auth, "error")
  assert.equal(Model.parseProjects("{not json").auth, "error")
  assert.deepEqual(Model.parseProjects('{"auth":"ok"}').projects, [])
  assert.equal(Model.parseRemember("").ok, false)
  assert.equal(Model.parseRemember('{"ok":true,"id":5}').id, 5)
  assert.equal(Model.parseRemember('{"ok":"yes"}').ok, false)
})

test("projectDetail summarises a row", () => {
  const now = Date.parse("2026-10-09T00:00:00Z")
  const row = { tag: "current", records: 1, activeAt: "2026-10-08T21:00:00Z" }
  assert.equal(Model.projectDetail(row, now), "current · 1 record · active 3h")
})

// Optional: rank against a real list saved from bin/reqall-widget-projects.
const live = process.env.REQALL_PROJECTS_JSON
test("rankProjects on a live project list", { skip: !live }, () => {
  const doc = Model.parseProjects(fs.readFileSync(live, "utf8"))
  const top = Model.rankProjects(doc.projects, "rqomp", "", doc.used, 3)
  assert.equal(top[0].name, "ReqallSystem/omarchy_plugin")
})
