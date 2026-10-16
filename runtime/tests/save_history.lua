-- save_history.lua - earlier saves, per node (headless): each Save keeps the
-- nodes it changed as they were (the game's .history/); the tree's menu
-- "Earlier saves >" lists them for a node; one picked puts the node back as
-- it was then (not saved). A folder game and a script game. Also the tree
-- filter's globs (ship*, /objects/**, sh?p).
-- Run: luajit save_history.lua   (or lua5.4)
local here = (arg and arg[0] or ""):match("^(.*[/\\])") or ""
package.path = here .. "../?.lua;" .. here .. "?.lua;" .. package.path
dofile(here .. "../boot.lua")                     -- (the viewer's Lua)
local ecs, fs = require("ecs"), require("fs")
hostfs = hostfs or { isdir = fs.isdir }
local n, fails = 0, 0
local function check(ok, what) n = n + 1; if not ok then fails = fails + 1; print("  FAIL: " .. what) end end
local function write(p, s) assert(fs.write(p, s)) end
local function rmtree(p)
  for _, e in ipairs(fs.list(p) or {}) do local q = fs.join(p, e.name); if e.dir then rmtree(q) else fs.rmfile(q) end end
  fs.rmdir(p)
end
local function saves_menu(w, p)
  local m = viewer_tree_menu(w, p)
  return m:match("Earlier saves>([^|]*)")
end

-- a folder game
local root = os.tmpname(); os.remove(root); fs.mkdir(root)
local game = fs.join(root, "game")
fs.mkdir(game); fs.mkdir(fs.join(game, "objects")); fs.mkdir(fs.join(game, "objects", "ship"))
write(fs.join(game, "objects", "ship", "transform.lua"), "return { x = 1, y = 2 }\n")
fs.mkdir(fs.join(game, "objects", "rock"))
write(fs.join(game, "objects", "rock", "transform.lua"), "return { x = 5, y = 5 }\n")
local w = assert(viewer_load(game))
check(saves_menu(w, "/objects/ship") == nil, "no saves yet: no Earlier saves")
w:node("/objects/ship").c.transform.x = 10
assert(viewer_save(w))
w:node("/objects/ship").c.transform.x = 20
w:node("/objects/ship").c.speed = 3
assert(viewer_save(w))
local hist = fs.list(fs.join(game, ".history")) or {}
check(#hist == 2, "two saves: two files in .history/: " .. #hist)
local list = viewer_saves(w, "/objects/ship")
check(#list == 2 and list[1].was.transform.x == 10 and list[2].was.transform.x == 1, "the ship's saves, newest first: what it was before each")
check(#viewer_saves(w, "/objects/rock") == 0, "the rock: never changed, no saves")
local m = saves_menu(w, "/objects/ship")
check(m and select(2, m:gsub(",", "")) == 1 and not m:find(":"), "the tree's menu: Earlier saves > two entries: " .. tostring(m))
local first = m:match("^[^,]+")
local ok, err = viewer_tree_action(w, "/objects/ship", "Earlier saves:" .. list[2].label)
check(ok and w:node("/objects/ship").c.transform.x == 1 and w:node("/objects/ship").c.speed == nil, "picked the oldest: as it was (x 1, no speed): " .. tostring(err))
check(viewer_dirty(w), "not saved yet")
assert(viewer_save(w))
check(#viewer_saves(w, "/objects/ship") == 3 and viewer_saves(w, "/objects/ship")[1].was.transform.x == 20, "saved: that's a save too (it can be undone the same way)")
w:spawn("/objects/star", { transform = { x = 0, y = 0 } })
assert(viewer_save(w))
local s = viewer_saves(w, "/objects/star")
check(#s == 1 and s[1].was == false and saves_menu(w, "/objects/star") == nil, "made by a save: listed (was = false), not offered")
check(select(1, viewer_restore_save(w, "/objects/star", s[1].name)) == false, "and can't be restored to before it")
-- the tree filter's globs
local function shown(f) local _, _, paths = viewer_outline(w, 1, 200, "", false, f); return table.concat(paths, " ") end
check(shown("s*"):find("/objects/ship", 1, true) and shown("s*"):find("/objects/star", 1, true) and not shown("s*"):find("rock", 1, true), "ship*: names: " .. shown("s*"))
check(shown("r?ck"):find("/objects/rock", 1, true) and not shown("r?ck"):find("ship", 1, true), "r?ck")
check(shown("/objects/**"):find("/objects/rock", 1, true) and shown("/objects/*"):find("/objects/ship", 1, true), "/objects/** and /objects/*: paths")
check(shown("ship"):find("/objects/ship", 1, true), "plain text: as before (a part of the name)")
rmtree(root)

-- a script game: <name>.history/ beside it
root = os.tmpname(); os.remove(root); fs.mkdir(root)
local script = fs.join(root, "toy.lua")
write(script, "local ecs = require('ecs')\nlocal w = ecs.world()\nw:spawn('/objects/box', { transform = { x = 1, y = 1 } })\nreturn w\n")
viewer_disk = nil
w = assert(viewer_load(script))
w:node("/objects/box").c.transform.x = 7
assert(viewer_save(w))
check(fs.list(fs.join(root, ".history", "toy")) and #fs.list(fs.join(root, ".history", "toy")) == 1, "a script game: .history/toy/ beside it")
local ls = viewer_saves(w, "/objects/box")
check(#ls == 1 and ls[1].was.transform.x == 1, "its box's save: as it was (x 1)")
check(viewer_restore_save(w, "/objects/box", ls[1].name) and w:node("/objects/box").c.transform.x == 1, "restored")
rmtree(root)

print(string.format("save history: %d checks, %d failed", n, fails))
os.exit(fails == 0 and 0 or 1)
